import 'dart:async';
import 'dart:math';

import '../../models/connection_status.dart';
import '../../models/discovered_device.dart';
import '../../models/mesh_channel.dart';
import '../../models/mesh_message.dart';
import '../../models/mesh_node.dart';
import '../meshtastic/sos_protocol.dart';
import '../mesh_repository.dart';

/// Malla simulada para desarrollar la interfaz sin placa (emulador o
/// escritorio). Se activa con:  flutter run --dart-define=FAKE_MESH=true
///
/// Al conectar crea 4 nodos alrededor del Campus Nord (uno sin GPS) y 2
/// canales; cada 20 s llega un mensaje de otro nodo y los envíos propios
/// pasan por queued → transmitted (0,3 s) → ack (1,5 s). No limita el
/// tamaño del texto ni simula fallos de entrega. También la usa
/// `widget_test.dart`.
class FakeMeshRepository implements MeshRepository {
  static const int _myNum = 0x0a0b0c01;
  static const DiscoveredDevice _device = DiscoveredDevice(
    id: 'AA:BB:CC:DD:EE:01',
    name: 'Meshtastic_0c01 (simulado)',
    rssi: -68,
  );

  final _statusController = StreamController<ConnectionStatus>.broadcast();
  final _scanController = StreamController<List<DiscoveredDevice>>.broadcast();
  final _scanningController = StreamController<bool>.broadcast();
  final _nodesController = StreamController<List<MeshNode>>.broadcast();
  final _channelsController = StreamController<List<MeshChannel>>.broadcast();
  final _messagesController = StreamController<MeshMessage>.broadcast();

  // Todos los temporizadores vivos, para cancelarlos al desconectar.
  final Set<Timer> _timers = {};
  final Random _random = Random();
  ConnectionStatus _status = ConnectionStatus.disconnected;
  final Map<int, MeshNode> _nodes = {};
  List<MeshChannel> _channels = const [];
  int _nextId = 1;
  bool _disposed = false;

  // Ejecuta [action] tras [delay] salvo que se haya desconectado o liberado.
  void _later(Duration delay, void Function() action) {
    late final Timer timer;
    timer = Timer(delay, () {
      _timers.remove(timer);
      if (!_disposed) action();
    });
    _timers.add(timer);
  }

  void _cancelTimers() {
    for (final timer in _timers) {
      timer.cancel();
    }
    _timers.clear();
  }

  void _setStatus(ConnectionStatus status) {
    _status = status;
    _statusController.add(status);
  }

  @override
  ConnectionStatus get status => _status;

  @override
  Stream<ConnectionStatus> get statusStream => _statusController.stream;

  @override
  Stream<List<DiscoveredDevice>> get scanResults => _scanController.stream;

  @override
  Stream<bool> get isScanning => _scanningController.stream;

  @override
  Future<void> startScan() async {
    _scanningController.add(true);
    _scanController.add(const []);
    _later(const Duration(seconds: 1), () => _scanController.add([_device]));
    _later(const Duration(seconds: 3), () => _scanningController.add(false));
  }

  @override
  Future<void> stopScan() async => _scanningController.add(false);

  @override
  Future<void> connect(String deviceId) async {
    if (_status != ConnectionStatus.disconnected) {
      throw StateError('Ya hay una conexión activa o en curso');
    }
    _setStatus(ConnectionStatus.connecting);
    await Future<void>.delayed(const Duration(milliseconds: 400));
    _setStatus(ConnectionStatus.configuring);
    await Future<void>.delayed(const Duration(milliseconds: 400));
    if (_disposed) return;

    final now = DateTime.now();
    _nodes
      ..clear()
      ..addAll({
        for (final node in [
          MeshNode(
            nodeNum: _myNum,
            id: MeshNode.idFromNum(_myNum),
            name: 'Mi nodo',
            shortName: 'YO',
            latitude: 41.38879,
            longitude: 2.11296,
            batteryLevel: 88,
            snr: 0,
            isMe: true,
            lastHeard: now,
          ),
          MeshNode(
            nodeNum: 0x0a0b0c02,
            id: MeshNode.idFromNum(0x0a0b0c02),
            name: 'Gateway Vertex',
            shortName: 'GW',
            latitude: 41.38980,
            longitude: 2.11450,
            batteryLevel: 100,
            snr: 11.2,
            hopsAway: 0,
            isGateway: true,
            lastHeard: now,
          ),
          MeshNode(
            nodeNum: 0x0a0b0c03,
            id: MeshNode.idFromNum(0x0a0b0c03),
            name: 'Repetidor A5',
            shortName: 'A5',
            latitude: 41.38720,
            longitude: 2.11180,
            batteryLevel: 64,
            snr: 4.1,
            hopsAway: 1,
            lastHeard: now,
          ),
          // Sin posición ni telemetría (hasPosition y hasBattery a false),
          // para probar cómo se pintan los datos que faltan.
          MeshNode.unknown(0x0a0b0c04).copyWith(
            name: 'Nodo sin GPS',
            shortName: 'NG',
            snr: -2.3,
            hopsAway: 2,
          ),
        ])
          node.nodeNum: node,
      });
    _channels = const [
      MeshChannel(index: 0, name: '', role: MeshChannelRole.primary),
      MeshChannel(index: 1, name: 'Rescate', role: MeshChannelRole.secondary),
    ];
    _setStatus(ConnectionStatus.connected);
    _nodesController.add(nodes);
    _channelsController.add(channels);
    _scheduleIncoming();
  }

  // Cada cierto tiempo, otro nodo «escribe» por el canal primario.
  void _scheduleIncoming() {
    _later(const Duration(seconds: 20), () {
      final others = _nodes.values.where((n) => !n.isMe).toList();
      final sender = others[_random.nextInt(others.length)];
      _messagesController.add(
        MeshMessage(
          id: 'fake_${_nextId++}',
          senderId: sender.id,
          senderName: sender.name,
          recipientId: MeshMessage.broadcastId,
          content: 'Mensaje de prueba de ${sender.name}',
          timestamp: DateTime.now(),
          senderNum: sender.nodeNum,
        ),
      );
      _scheduleIncoming();
    });
  }

  @override
  Future<void> disconnect() async {
    _cancelTimers();
    _setStatus(ConnectionStatus.disconnected);
  }

  @override
  int? get myNodeNum => _status.isConnected ? _myNum : null;

  @override
  List<MeshNode> get nodes => List.unmodifiable(_nodes.values);

  @override
  Stream<List<MeshNode>> get nodesStream => _nodesController.stream;

  @override
  List<MeshChannel> get channels => _channels;

  @override
  Stream<List<MeshChannel>> get channelsStream => _channelsController.stream;

  @override
  Stream<MeshMessage> get messages => _messagesController.stream;

  @override
  Future<MeshMessage> sendText(String text, {int? toNode, int channel = 0}) {
    return _send(text, toNode: toNode, channel: channel);
  }

  @override
  Future<MeshMessage> sendSos() => _sendSos(SosKind.alert);

  @override
  Future<MeshMessage> cancelSos() => _sendSos(SosKind.cancel);

  Future<MeshMessage> _sendSos(SosKind kind) async {
    final me = _nodes[_myNum];
    final fix = (me != null && me.hasPosition) ? me : null;
    final message = await _send(
      SosCodec.encode(
        SosSignal(
          kind: kind,
          nodeNum: _myNum,
          latitude: fix?.latitude,
          longitude: fix?.longitude,
        ),
      ),
      channel: SosPolicy.channel,
      isSos: true,
    );
    if (me != null) {
      _nodes[_myNum] = me.copyWith(isEmergency: kind == SosKind.alert);
      _nodesController.add(nodes);
    }
    return message;
  }

  // Recorre los estados de entrega como lo haría un nodo real.
  Future<MeshMessage> _send(
    String text, {
    int? toNode,
    int channel = 0,
    bool isSos = false,
  }) async {
    if (!_status.isConnected) throw StateError('No hay ningún nodo conectado');
    if (text.isEmpty) throw ArgumentError('El mensaje está vacío');
    final sending = MeshMessage(
      id: 'fake_${_nextId++}',
      senderId: MeshNode.idFromNum(_myNum),
      senderName: _nodes[_myNum]?.name ?? 'Mi nodo',
      recipientId: toNode == null
          ? MeshMessage.broadcastId
          : MeshNode.idFromNum(toNode),
      content: text,
      timestamp: DateTime.now(),
      isMe: true,
      status: MessageStatus.queued,
      senderNum: _myNum,
      recipientNum: toNode,
      channel: channel,
      isSos: isSos,
    );
    _messagesController.add(sending);
    final sent = sending.copyWith(status: MessageStatus.transmitted);
    _later(
      const Duration(milliseconds: 300),
      () => _messagesController.add(sent),
    );
    _later(
      const Duration(milliseconds: 1500),
      () => _messagesController.add(
        sent.copyWith(status: MessageStatus.ack),
      ),
    );
    return sent;
  }

  @override
  Future<void> dispose() async {
    _disposed = true;
    _cancelTimers();
    await _statusController.close();
    await _scanController.close();
    await _scanningController.close();
    await _nodesController.close();
    await _channelsController.close();
    await _messagesController.close();
  }
}
