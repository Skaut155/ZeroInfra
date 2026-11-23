import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart' show debugPrint;

import '../../core/constants/meshtastic_ble.dart';
import '../../core/emergency_codec.dart';
import '../../generated/meshtastic/channel.pb.dart' as pb;
import '../../generated/meshtastic/mesh.pb.dart' as pb;
import '../../generated/meshtastic/portnums.pbenum.dart' as pb;
import '../../generated/meshtastic/telemetry.pb.dart' as pb;
import '../../models/connection_status.dart';
import '../../models/discovered_device.dart';
import '../../models/emergency_alert.dart';
import '../../models/mesh_channel.dart';
import '../../models/mesh_message.dart';
import '../../models/mesh_node.dart';
import '../ble/mesh_transport.dart';
import '../mesh_repository.dart';
import 'emergency_policy.dart';

/// [MeshRepository] real: habla el protocolo de la Client API de Meshtastic
/// (mensajes Protobuf `ToRadio`/`FromRadio`) sobre un [MeshTransport].
///
/// Lo crea `createMeshRepository` con un `BleMeshTransport` cuando no se
/// usa la malla simulada. Mantiene en memoria nodos, canales y acuses.
class MeshtasticClient implements MeshRepository {
  /// [configTimeout] es el tiempo máximo para recibir la configuración del
  /// nodo en [connect]; los tests lo acortan.
  MeshtasticClient(
    this._transport, {
    Duration configTimeout = const Duration(seconds: 30),
  }) : _configTimeout = configTimeout {
    // Se escucha desde el principio: el stream de BLE es broadcast y lo que
    // llega sin oyente se pierde.
    _fromRadioSub = _transport.fromRadioStream.listen(
      _onFromRadio,
      onError: _onReadError,
    );
    _linkSub = _transport.linkState.listen((up) {
      if (!up) _handleLinkDown();
    });
  }

  /// Se usa si el nodo no informa de su hop_limit. Un paquete con hop_limit 0
  /// solo llega a los vecinos directos, así que nunca se envía sin fijarlo.
  static const int defaultHopLimit = 3;
  /// Tamaño máximo del texto en bytes UTF-8 (233 en Meshtastic).
  static final int maxPayloadBytes = pb.Constants.DATA_PAYLOAD_LEN.value;
  // Límite de mensajes a la espera de acuse; se descarta el más antiguo.
  static const int _maxPendingAcks = 100;
  // Límite de alertas recordadas para descartar las repetidas.
  static const int _maxSeenAlerts = 200;

  final MeshTransport _transport;
  final Duration _configTimeout;
  final Random _random = Random();
  late final StreamSubscription<List<int>> _fromRadioSub;
  late final StreamSubscription<bool> _linkSub;

  final _statusController = StreamController<ConnectionStatus>.broadcast();
  final _nodesController = StreamController<List<MeshNode>>.broadcast();
  final _channelsController = StreamController<List<MeshChannel>>.broadcast();
  final _messagesController = StreamController<MeshMessage>.broadcast();
  final _alertsController = StreamController<EmergencyAlert>.broadcast();

  ConnectionStatus _status = ConnectionStatus.disconnected;
  int? _myNodeNum;
  int _hopLimit = defaultHopLimit;
  final Map<int, MeshNode> _nodes = {};
  final Map<int, MeshChannel> _channels = {};
  // Mensajes propios a la espera de acuse, por id de paquete.
  final Map<int, MeshMessage> _pendingAcks = {};
  // Alertas activas de otros nodos, por EmergencyAlert.compositeKey.
  final Map<String, EmergencyAlert> _activeAlerts = {};
  // Alertas ya vistas (activas o canceladas), en orden de llegada.
  final Set<String> _seenAlerts = {};
  // SOS propio sin cancelar: su id EMG1 y el nodo que lo emitió. Se
  // conserva al reconectar con el mismo nodo para poder cancelarlo.
  ({int id, int originNode})? _ownSos;
  int? _configNonce;
  Completer<void>? _configDone;

  // --- Conexión ---

  @override
  ConnectionStatus get status => _status;

  @override
  Stream<ConnectionStatus> get statusStream => _statusController.stream;

  @override
  Stream<List<DiscoveredDevice>> get scanResults => _transport.scanResults;

  @override
  Stream<bool> get isScanning => _transport.isScanning;

  @override
  Future<void> startScan() => _transport.startScan();

  @override
  Future<void> stopScan() => _transport.stopScan();

  @override
  Future<void> connect(String deviceId) async {
    if (_status != ConnectionStatus.disconnected) {
      throw StateError('Ya hay una conexión activa o en curso');
    }
    _setStatus(ConnectionStatus.connecting);
    try {
      await _transport.connect(deviceId);
      _setStatus(ConnectionStatus.configuring);
      await _downloadConfig();
      _setStatus(ConnectionStatus.connected);
      // Por si la ficha del nodo propio llegó antes que my_info.
      final me = _myNodeNum;
      if (me != null && _nodes.containsKey(me)) _updateNode(me, (node) => node);
      // La descarga vacía los nodos: se vuelven a marcar las emergencias.
      if (_ownSos?.originNode != me) _ownSos = null;
      if (me != null && _ownSos != null) {
        _updateNode(me, (node) => node.copyWith(isEmergency: true));
      }
      for (final alert in _activeAlerts.values) {
        _markEmergency(alert);
      }
      // Durante la descarga no se publican las listas; se publican una vez.
      _publishNodes();
      _publishChannels();
    } catch (_) {
      try {
        await _transport.disconnect();
      } catch (_) {
        // No se había llegado a conectar.
      }
      _handleLinkDown();
      rethrow;
    }
  }

  @override
  Future<void> disconnect() async {
    await _transport.disconnect();
    _handleLinkDown();
  }

  // Pide al nodo toda su configuración (want_config_id) y espera a que
  // conteste con config_complete_id y el mismo número.
  Future<void> _downloadConfig() async {
    _myNodeNum = null;
    _hopLimit = defaultHopLimit;
    _nodes.clear();
    _channels.clear();
    _pendingAcks.clear();

    // Por debajo de 100000 hay valores que el firmware reserva (69420, 69421).
    final nonce = 100000 + _random.nextInt(0x7FFFFFFF - 100000);
    final done = Completer<void>();
    // Si el enlace cae antes de llegar al await de abajo, el error no debe
    // quedar sin oyente.
    done.future.ignore();
    _configNonce = nonce;
    _configDone = done;
    try {
      await _transport.writeToRadio(
        pb.ToRadio(wantConfigId: nonce).writeToBuffer(),
      );
      await _transport.drainFromRadio();
      await done.future.timeout(
        _configTimeout,
        onTimeout: () => throw TimeoutException(
          'El nodo no terminó de enviar su configuración',
        ),
      );
    } finally {
      _configNonce = null;
      _configDone = null;
    }
  }

  void _handleLinkDown() {
    final done = _configDone;
    if (done != null && !done.isCompleted) {
      done.completeError(StateError('Se perdió la conexión con el nodo'));
    }
    // Lo que no llegó a entregarse al nodo ya no saldrá.
    for (final message in _pendingAcks.values.toList()) {
      if (message.status == MessageStatus.queued) {
        _emitMessage(message.copyWith(status: MessageStatus.failed));
      }
    }
    _pendingAcks.clear();
    _myNodeNum = null;
    _setStatus(ConnectionStatus.disconnected);
  }

  void _setStatus(ConnectionStatus status) {
    if (_status == status) return;
    _status = status;
    if (!_statusController.isClosed) _statusController.add(status);
  }

  // --- Estado de la malla ---

  @override
  int? get myNodeNum => _myNodeNum;

  @override
  List<MeshNode> get nodes => List.unmodifiable(_nodes.values);

  @override
  Stream<List<MeshNode>> get nodesStream => _nodesController.stream;

  @override
  List<MeshChannel> get channels => List.unmodifiable(_channels.values);

  @override
  Stream<List<MeshChannel>> get channelsStream => _channelsController.stream;

  void _publishNodes() {
    if (_status == ConnectionStatus.configuring) return;
    if (!_nodesController.isClosed) _nodesController.add(nodes);
  }

  void _publishChannels() {
    if (_status == ConnectionStatus.configuring) return;
    if (!_channelsController.isClosed) _channelsController.add(channels);
  }

  void _updateNode(int nodeNum, MeshNode Function(MeshNode node) update) {
    final current = _nodes[nodeNum] ?? MeshNode.unknown(nodeNum);
    _nodes[nodeNum] = update(current).copyWith(isMe: nodeNum == _myNodeNum);
    _publishNodes();
  }

  // --- Recepción ---

  void _onReadError(Object error) {
    debugPrint('Error de lectura BLE: $error');
    final done = _configDone;
    if (done != null && !done.isCompleted) done.completeError(error);
  }

  void _onFromRadio(List<int> bytes) {
    try {
      _dispatch(pb.FromRadio.fromBuffer(bytes));
    } catch (e) {
      // Un paquete ilegible no debe detener la recepción de los siguientes.
      debugPrint('FromRadio descartado: $e');
    }
  }

  void _dispatch(pb.FromRadio msg) {
    switch (msg.whichPayloadVariant()) {
      case pb.FromRadio_PayloadVariant.myInfo:
        _myNodeNum = msg.myInfo.myNodeNum;
      case pb.FromRadio_PayloadVariant.nodeInfo:
        _onNodeInfo(msg.nodeInfo);
      case pb.FromRadio_PayloadVariant.channel:
        _onChannel(msg.channel);
      case pb.FromRadio_PayloadVariant.config:
        if (msg.config.hasLora() && msg.config.lora.hopLimit > 0) {
          _hopLimit = msg.config.lora.hopLimit;
        }
      case pb.FromRadio_PayloadVariant.configCompleteId:
        final done = _configDone;
        if (done != null &&
            !done.isCompleted &&
            msg.configCompleteId == _configNonce) {
          done.complete();
        }
      case pb.FromRadio_PayloadVariant.packet:
        _onMeshPacket(msg.packet);
      case pb.FromRadio_PayloadVariant.queueStatus:
        // res != 0: el nodo no ha podido encolar el paquete para emitirlo.
        final queue = msg.queueStatus;
        if (queue.res != 0) {
          _setDeliveryStatus(queue.meshPacketId, MessageStatus.failed);
        }
      default:
        break;
    }
  }

  void _onNodeInfo(pb.NodeInfo info) {
    final user = info.hasUser() ? info.user : null;
    final metrics = info.hasDeviceMetrics() ? info.deviceMetrics : null;
    _updateNode(
      info.num,
      (node) => _withPosition(
        node.copyWith(
          name: _nonEmpty(user?.longName),
          shortName: _nonEmpty(user?.shortName),
          batteryLevel: _battery(metrics),
          snr: info.snr != 0 ? info.snr : null,
          hopsAway: info.hasHopsAway() ? info.hopsAway : null,
          lastHeard: info.lastHeard > 0
              ? DateTime.fromMillisecondsSinceEpoch(info.lastHeard * 1000)
              : null,
        ),
        info.hasPosition() ? info.position : null,
      ),
    );
  }

  void _onChannel(pb.Channel channel) {
    if (channel.role == pb.Channel_Role.DISABLED) {
      _channels.remove(channel.index);
    } else {
      _channels[channel.index] = MeshChannel(
        index: channel.index,
        name: channel.settings.name,
        role: channel.role == pb.Channel_Role.PRIMARY
            ? MeshChannelRole.primary
            : MeshChannelRole.secondary,
      );
    }
    _publishChannels();
  }

  // Cualquier paquete de otro nodo actualiza su SNR y su lastHeard; después
  // se procesa según el puerto.
  void _onMeshPacket(pb.MeshPacket packet) {
    final from = packet.from;
    if (from != 0 && from != _myNodeNum) {
      _updateNode(
        from,
        (node) => node.copyWith(
          snr: packet.rxSnr != 0 ? packet.rxSnr : null,
          lastHeard: DateTime.now(),
        ),
      );
    }
    // Sin `decoded`: cifrado con una clave que este nodo no tiene.
    if (!packet.hasDecoded()) return;
    final data = packet.decoded;
    final port = data.portnum;

    if (port == pb.PortNum.ROUTING_APP) {
      _onRouting(packet, data);
    } else if (port == pb.PortNum.POSITION_APP) {
      final position = pb.Position.fromBuffer(data.payload);
      _updateNode(from, (node) => _withPosition(node, position));
    } else if (port == pb.PortNum.NODEINFO_APP) {
      final user = pb.User.fromBuffer(data.payload);
      _updateNode(
        from,
        (node) => node.copyWith(
          name: _nonEmpty(user.longName),
          shortName: _nonEmpty(user.shortName),
        ),
      );
    } else if (port == pb.PortNum.TELEMETRY_APP) {
      final telemetry = pb.Telemetry.fromBuffer(data.payload);
      if (telemetry.hasDeviceMetrics()) {
        final battery = _battery(telemetry.deviceMetrics);
        _updateNode(from, (node) => node.copyWith(batteryLevel: battery));
      }
    } else if (port == pb.PortNum.TEXT_MESSAGE_APP) {
      _emitReceived(
        packet,
        utf8.decode(data.payload, allowMalformed: true),
      );
    } else if (port == EmergencyPolicy.portNum) {
      _onEmergency(packet, data);
    }
  }

  // Publica un mensaje recibido de otro nodo (texto o SOS legible).
  void _emitReceived(
    pb.MeshPacket packet,
    String content, {
    bool isSos = false,
  }) {
    final from = packet.from;
    final isBroadcast = packet.to == AppConstants.broadcastAddress;
    _emitMessage(
      MeshMessage(
        id: _messageId(from, packet.id),
        senderId: MeshNode.idFromNum(from),
        senderName: _nodes[from]?.name ?? MeshNode.idFromNum(from),
        recipientId: isBroadcast
            ? MeshMessage.broadcastId
            : MeshNode.idFromNum(packet.to),
        content: content,
        timestamp: DateTime.now(),
        packetId: packet.id,
        senderNum: from,
        recipientNum: isBroadcast ? null : packet.to,
        channel: packet.channel,
        isSos: isSos,
      ),
    );
  }

  // --- Alertas EMG1 (formato y reglas del firmware de Cristina) ---

  @override
  Stream<EmergencyAlert> get alerts => _alertsController.stream;

  @override
  List<EmergencyAlert> get activeAlerts => List.unmodifiable(
    _activeAlerts.values.where((alert) => !alert.isExpired),
  );

  // Lo que no es un EMG1 válido se descarta sin error.
  void _onEmergency(pb.MeshPacket packet, pb.Data data) {
    if (packet.from == 0 || packet.from == _myNodeNum) return;
    final EmgMessage emg;
    try {
      emg = EmgCodec.decode(data.payload);
    } on FormatException catch (e) {
      debugPrint('PRIVATE_APP descartado: $e');
      return;
    }
    switch (emg.kind) {
      case EmgKind.alert || EmgKind.replay:
        _onAlert(packet, emg);
      case EmgKind.resolved:
        _onResolved(packet, emg);
      case EmgKind.receipt || EmgKind.fetch:
        // Los gestiona el propio firmware.
        break;
    }
  }

  void _onAlert(pb.MeshPacket packet, EmgMessage emg) {
    final isReplay = emg.kind == EmgKind.replay;
    // Un ALERT lo emite su origen; un REPLAY lo reenvía otro nodo que lo
    // tenía guardado (respuesta a un FETCH).
    if (!isReplay && emg.originNode != packet.from) return;
    final key = _alertKey(emg);
    if (!_markSeen(key)) return;

    final position = EmergencyText.position(emg.text);
    final alert = EmergencyAlert(
      id: emg.id,
      originNode: emg.originNode,
      severity: emg.severity,
      text: EmergencyText.body(emg.text),
      expiresUnix: emg.expiresUnix,
      senderNode: packet.from,
      destinationNode: packet.to,
      channel: packet.channel,
      meshPacketId: packet.id,
      receivedAt: DateTime.now(),
      isReplay: isReplay,
      latitude: position?.latitude,
      longitude: position?.longitude,
      // La firma de un REPLAY es la de quien lo reenvía, no la del origen.
      isVerified: !isReplay && packet.xeddsaSigned,
    );
    if (alert.isExpired) return;

    _activeAlerts[key] = alert;
    _markEmergency(alert);
    _emitAlert(alert);
    _emitReceived(
      packet,
      EmergencyText.describe(
        kind: EmgKind.alert,
        body: alert.text,
        latitude: alert.latitude,
        longitude: alert.longitude,
        verified: alert.isVerified,
      ),
      isSos: true,
    );
  }

  void _onResolved(pb.MeshPacket packet, EmgMessage emg) {
    if (emg.originNode != packet.from) return;
    final key = _alertKey(emg);
    // Si llega antes que su ALERT, el ALERT se descartará después.
    _markSeen(key);
    final alert = _activeAlerts.remove(key);
    if (alert == null) return;

    alert.status = EmergencyDeliveryStatus.resolved;
    final origin = alert.originNode;
    final stillActive = _activeAlerts.values.any((a) => a.originNode == origin);
    _updateNode(origin, (node) => node.copyWith(isEmergency: stillActive));
    _emitAlert(alert);
    _emitReceived(
      packet,
      EmergencyText.describe(kind: EmgKind.resolved),
      isSos: true,
    );
  }

  // Marca el nodo de origen en emergencia, con la posición de la alerta.
  void _markEmergency(EmergencyAlert alert) {
    _updateNode(
      alert.originNode,
      (node) => node.copyWith(
        isEmergency: true,
        latitude: alert.latitude,
        longitude: alert.longitude,
      ),
    );
  }

  // Devuelve false si la alerta ya se había visto.
  bool _markSeen(String key) {
    if (!_seenAlerts.add(key)) return false;
    if (_seenAlerts.length > _maxSeenAlerts) {
      _seenAlerts.remove(_seenAlerts.first);
    }
    return true;
  }

  // Misma clave que EmergencyAlert.compositeKey.
  static String _alertKey(EmgMessage emg) => '${emg.originNode}_${emg.id}';

  void _emitAlert(EmergencyAlert alert) {
    if (!_alertsController.isClosed) _alertsController.add(alert);
  }

  // Acuse (o error) de un paquete enviado con want_ack.
  void _onRouting(pb.MeshPacket packet, pb.Data data) {
    final pending = _pendingAcks[data.requestId];
    if (pending == null) return;
    final routing = pb.Routing.fromBuffer(data.payload);
    if (routing.errorReason != pb.Routing_Error.NONE) {
      _setDeliveryStatus(pending.packetId, MessageStatus.failed);
      return;
    }
    // En difusión no hay acuse del destinatario: el nodo genera uno
    // «implícito» al oír que otro nodo retransmite. En un mensaje directo ese
    // acuse implícito (from = este nodo) solo indica que la malla lo reenvió,
    // así que se espera al acuse real del destinatario.
    if (!pending.isDirect || packet.from == pending.recipientNum) {
      _setDeliveryStatus(pending.packetId, MessageStatus.ack);
    }
  }

  static MeshNode _withPosition(MeshNode node, pb.Position? position) {
    // 0,0 significa «sin posición».
    if (position == null ||
        (position.latitudeI == 0 && position.longitudeI == 0)) {
      return node;
    }
    return node.copyWith(
      latitude: position.latitudeI * 1e-7,
      longitude: position.longitudeI * 1e-7,
    );
  }

  static int? _battery(pb.DeviceMetrics? metrics) {
    if (metrics == null || !metrics.hasBatteryLevel()) return null;
    // Meshtastic usa valores por encima de 100 para «alimentado por cable».
    return min(100, max(0, metrics.batteryLevel));
  }

  // Id único de un mensaje en la app: nodo remitente + id de paquete.
  static String _messageId(int senderNum, int packetId) =>
      '${MeshNode.idFromNum(senderNum)}_$packetId';

  static String? _nonEmpty(String? value) =>
      (value == null || value.isEmpty) ? null : value;

  // --- Envío ---

  @override
  Stream<MeshMessage> get messages => _messagesController.stream;

  @override
  Future<MeshMessage> sendText(String text, {int? toNode, int channel = 0}) {
    return _send(
      payload: utf8.encode(text),
      content: text,
      portNum: pb.PortNum.TEXT_MESSAGE_APP,
      toNode: toNode,
      channel: channel,
      hopLimit: _hopLimit,
    );
  }

  @override
  Future<MeshMessage> sendSos() async {
    final me = _connectedNode();
    final self = _nodes[me];
    final fix = (self != null && self.hasPosition) ? self : null;
    // Cada SOS lleva un id nuevo: el firmware descarta un (origen, id) que
    // ya ha visto.
    final id = _newId();
    final message = await _sendEmergency(
      EmgMessage(
        kind: EmgKind.alert,
        severity: EmergencyPolicy.severity,
        flags: 0,
        id: id,
        expiresUnix: EmergencyPolicy.expiresUnix,
        originNode: me,
        text: EmergencyText.encode(
          latitude: fix?.latitude,
          longitude: fix?.longitude,
        ),
      ),
      content: EmergencyText.describe(
        kind: EmgKind.alert,
        latitude: fix?.latitude,
        longitude: fix?.longitude,
      ),
    );
    _ownSos = (id: id, originNode: me);
    _updateNode(me, (node) => node.copyWith(isEmergency: true));
    return message;
  }

  @override
  Future<MeshMessage> cancelSos() async {
    final me = _connectedNode();
    final sos = _ownSos;
    if (sos == null || sos.originNode != me) {
      throw StateError('No hay ningún SOS activo que cancelar');
    }
    // RESOLVED con el mismo id y origen que el ALERT que cancela.
    final message = await _sendEmergency(
      EmgMessage(
        kind: EmgKind.resolved,
        severity: EmergencyPolicy.severity,
        flags: 0,
        id: sos.id,
        expiresUnix: EmergencyPolicy.expiresUnix,
        originNode: me,
      ),
      content: EmergencyText.describe(kind: EmgKind.resolved),
    );
    _ownSos = null;
    _updateNode(me, (node) => node.copyWith(isEmergency: false));
    return message;
  }

  // Difunde un EMG1 con la política de EmergencyPolicy.
  Future<MeshMessage> _sendEmergency(
    EmgMessage emg, {
    required String content,
  }) {
    return _send(
      payload: EmgCodec.encode(emg),
      content: content,
      portNum: EmergencyPolicy.portNum,
      channel: EmergencyPolicy.channel,
      hopLimit: EmergencyPolicy.hopLimit,
      priority: EmergencyPolicy.priority,
      isSos: true,
    );
  }

  // Número del nodo conectado; StateError si no hay conexión completa.
  int _connectedNode() {
    final me = _myNodeNum;
    if (_status != ConnectionStatus.connected || me == null) {
      throw StateError('No hay ningún nodo conectado');
    }
    return me;
  }

  // Id de 32 bits distinto de 0 (paquetes y alertas EMG1).
  int _newId() => 1 + _random.nextInt(0xFFFFFFFF);

  // [content] es lo que se muestra en el chat; [payload], lo que viaja.
  Future<MeshMessage> _send({
    required List<int> payload,
    required String content,
    required pb.PortNum portNum,
    required int channel,
    required int hopLimit,
    int? toNode,
    pb.MeshPacket_Priority? priority,
    bool isSos = false,
  }) async {
    final me = _connectedNode();
    if (payload.isEmpty) throw ArgumentError('El mensaje está vacío');
    if (payload.length > maxPayloadBytes) {
      throw ArgumentError(
        'El mensaje ocupa ${payload.length} bytes; el máximo es '
        '$maxPayloadBytes',
      );
    }

    // El id se genera aquí (y no en el nodo) para poder casarlo con su acuse.
    final id = _newId();
    final packet = pb.MeshPacket(
      to: toNode ?? AppConstants.broadcastAddress,
      channel: channel,
      id: id,
      wantAck: true,
      hopLimit: hopLimit,
      priority: priority,
      decoded: pb.Data(portnum: portNum, payload: payload),
    );
    final message = MeshMessage(
      id: _messageId(me, id),
      senderId: MeshNode.idFromNum(me),
      senderName: _nodes[me]?.name ?? MeshNode.idFromNum(me),
      recipientId: toNode == null
          ? MeshMessage.broadcastId
          : MeshNode.idFromNum(toNode),
      content: content,
      timestamp: DateTime.now(),
      isMe: true,
      status: MessageStatus.queued,
      packetId: id,
      senderNum: me,
      recipientNum: toNode,
      channel: channel,
      isSos: isSos,
    );
    if (_pendingAcks.length >= _maxPendingAcks) {
      _pendingAcks.remove(_pendingAcks.keys.first);
    }
    _pendingAcks[id] = message;
    _emitMessage(message);

    try {
      await _transport.writeToRadio(
        pb.ToRadio(packet: packet).writeToBuffer(),
      );
    } catch (_) {
      _setDeliveryStatus(id, MessageStatus.failed);
      rethrow;
    }
    return _setDeliveryStatus(id, MessageStatus.transmitted) ?? message;
  }

  // Devuelve el mensaje actualizado, o null si ya no se esperaba su acuse.
  MeshMessage? _setDeliveryStatus(int packetId, MessageStatus status) {
    final current = _pendingAcks[packetId];
    if (current == null) return null;
    // Un acuse que llegara antes de terminar la escritura no debe retroceder.
    if (status == MessageStatus.transmitted &&
        current.status != MessageStatus.queued) {
      return current;
    }
    final updated = current.copyWith(status: status);
    if (status == MessageStatus.ack || status == MessageStatus.failed) {
      _pendingAcks.remove(packetId);
    } else {
      _pendingAcks[packetId] = updated;
    }
    _emitMessage(updated);
    return updated;
  }

  void _emitMessage(MeshMessage message) {
    if (!_messagesController.isClosed) _messagesController.add(message);
  }

  @override
  Future<void> dispose() async {
    await _fromRadioSub.cancel();
    await _linkSub.cancel();
    await _transport.dispose();
    await _statusController.close();
    await _nodesController.close();
    await _channelsController.close();
    await _messagesController.close();
    await _alertsController.close();
  }
}
