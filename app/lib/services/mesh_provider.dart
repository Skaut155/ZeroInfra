import 'dart:async';
import 'dart:math';

import 'package:flutter/foundation.dart';

import '../core/emergency_codec.dart';
import '../models/emergency_alert.dart';
import '../models/mesh_message.dart';
import '../models/mesh_node.dart';

class MeshProvider extends ChangeNotifier {
  bool _isScanning = false;
  String? _connectedNodeId = 'node_esp32_01';
  bool _isEmergencyActive = false;
  Timer? _scanTimer;
  final Map<String, EmergencyAlert> _emergencyAlerts = {};
  int _localNodeNum = 0x1a21fd32;

  final List<MeshNode> _nodes = [
    MeshNode(
      id: 'node_esp32_01',
      name: 'Mi Nodo (ESP32)',
      latitude: 41.38879,
      longitude: 2.11296,
      batteryLevel: 88,
      snr: 8.5,
      lastHeard: DateTime.now(),
    ),
    MeshNode(
      id: 'node_gateway_01',
      name: 'Gateway MQTT (Vertex)',
      latitude: 41.38980,
      longitude: 2.11450,
      batteryLevel: 100,
      snr: 11.2,
      isGateway: true,
      lastHeard: DateTime.now().subtract(const Duration(seconds: 40)),
    ),
    MeshNode(
      id: 'node_repeater_01',
      name: 'Repetidor Malla (A5)',
      latitude: 41.38720,
      longitude: 2.11180,
      batteryLevel: 64,
      snr: 4.1,
      lastHeard: DateTime.now().subtract(const Duration(minutes: 2)),
    ),
  ];

  final List<MeshMessage> _messages = [
    MeshMessage(
      id: 'init_broadcast',
      senderId: 'node_gateway_01',
      senderName: 'Gateway_Base',
      recipientId: 'broadcast',
      content: 'Canal 0 público sincronizado (868.125 MHz - SF12 / BW 125kHz).',
      timestamp: DateTime.now().subtract(const Duration(minutes: 5)),
    ),
  ];

  bool get isScanning => _isScanning;
  String? get connectedNodeId => _connectedNodeId;
  bool get isEmergencyActive => _isEmergencyActive;
  int get localNodeNum => _localNodeNum;
  List<EmergencyAlert> get emergencyAlerts {
    final list = _emergencyAlerts.values.where((a) => !a.isExpired).toList()
      ..sort((a, b) => b.receivedAt.compareTo(a.receivedAt));
    return List.unmodifiable(list);
  }

  List<MeshNode> get nodes => List.unmodifiable(_nodes);
  List<MeshMessage> get messages => List.unmodifiable(_messages);

  MeshNode? get connectedNode {
    for (final node in _nodes) {
      if (node.id == _connectedNodeId) return node;
    }
    return null;
  }

  void updateLocalNodeNum(int nodeNum) {
    if (nodeNum > 0 && nodeNum <= 0xffffffff) {
      _localNodeNum = nodeNum;
      notifyListeners();
    }
  }

  void onPrivateAppPacketReceived({
    required List<int> payload,
    required int senderNode,
    required int destinationNode,
    required int meshPacketId,
    int channel = 0,
  }) {
    try {
      final emg = EmgCodec.decode(payload);
      final key = '${emg.originNode}_${emg.id}';

      switch (emg.kind) {
        case EmgKind.alert:
          if (_emergencyAlerts.containsKey(key)) return;
          _emergencyAlerts[key] = EmergencyAlert(
            id: emg.id,
            originNode: emg.originNode,
            severity: emg.severity,
            text: emg.text,
            expiresUnix: emg.expiresUnix,
            senderNode: senderNode,
            destinationNode: destinationNode,
            channel: channel,
            meshPacketId: meshPacketId,
            receivedAt: DateTime.now(),
            status: EmergencyDeliveryStatus.networkAck,
          );
          _isEmergencyActive = true;
        case EmgKind.receipt:
          final existing = _emergencyAlerts[key];
          if (existing != null &&
              existing.status != EmergencyDeliveryStatus.resolved) {
            existing.status = EmergencyDeliveryStatus.appReceipt;
            existing.receiptFromNode = senderNode;
          }
        case EmgKind.resolved:
          if (emg.originNode != senderNode) return;
          final existing = _emergencyAlerts[key];
          if (existing != null) {
            existing.status = EmergencyDeliveryStatus.resolved;
            if (emg.text.isNotEmpty) existing.resolutionNote = emg.text;
            _updateEmergencyActive();
          }
        case EmgKind.replay:
          if (_emergencyAlerts.containsKey(key)) return;
          _emergencyAlerts[key] = EmergencyAlert(
            id: emg.id,
            originNode: emg.originNode,
            severity: emg.severity,
            text: emg.text,
            expiresUnix: emg.expiresUnix,
            senderNode: senderNode,
            destinationNode: destinationNode,
            channel: channel,
            meshPacketId: meshPacketId,
            receivedAt: DateTime.now(),
            status: EmergencyDeliveryStatus.networkAck,
            isReplay: true,
          );
          _isEmergencyActive = true;
        case EmgKind.fetch:
          break;
      }
      notifyListeners();
    } on FormatException catch (error) {
      debugPrint('Trama EMG1 inválida descartada: ${error.message}');
    }
  }

  Future<Uint8List> sendEmgAlert({
    required String text,
    int severity = 3,
    int destinationNode = 0xffffffff,
    bool requestReceipt = false,
    int expiresUnix = 0,
  }) async {
    final alertId = Random().nextInt(0x7fffffff) + 1;
    final meshPacketId = Random().nextInt(0x7fffffff) + 1;
    final isUnicast = destinationNode != 0xffffffff;
    final emgMsg = EmgMessage(
      kind: EmgKind.alert,
      severity: severity.clamp(1, 3),
      flags: isUnicast && requestReceipt ? 1 : 0,
      id: alertId,
      expiresUnix: expiresUnix,
      originNode: _localNodeNum,
      text: text,
    );
    final encodedPayload = EmgCodec.encode(emgMsg);
    final alert = EmergencyAlert(
      id: alertId,
      originNode: _localNodeNum,
      severity: emgMsg.severity,
      text: text,
      expiresUnix: expiresUnix,
      senderNode: _localNodeNum,
      destinationNode: destinationNode,
      channel: 0,
      meshPacketId: meshPacketId,
      receivedAt: DateTime.now(),
    );
    _emergencyAlerts[alert.compositeKey] = alert;
    _isEmergencyActive = true;
    notifyListeners();
    return encodedPayload;
  }

  Uint8List? buildResolvePayload(EmergencyAlert alert, {String note = ''}) {
    if (alert.originNode != _localNodeNum) {
      debugPrint(
        'No se puede resolver una alerta cuyo origen no es este nodo.',
      );
      return null;
    }
    final bytes = EmgCodec.encode(
      EmgMessage(
        kind: EmgKind.resolved,
        severity: 0,
        flags: 0,
        id: alert.id,
        expiresUnix: 0,
        originNode: _localNodeNum,
        text: note,
      ),
    );
    alert.status = EmergencyDeliveryStatus.resolved;
    alert.resolutionNote = note;
    _updateEmergencyActive();
    notifyListeners();
    return bytes;
  }

  void _updateEmergencyActive() {
    _isEmergencyActive = _emergencyAlerts.values.any(
      (a) => a.status != EmergencyDeliveryStatus.resolved && !a.isExpired,
    );
  }

  List<MeshMessage> getMessagesForChannel(String? targetPeerId) {
    if (targetPeerId == null || targetPeerId == 'broadcast') {
      return _messages.where((message) {
        return !message.isDirect || message.isEmergency;
      }).toList();
    }
    return _messages.where((message) {
      final matchesPeer =
          (!message.isMe && message.senderId == targetPeerId) ||
          (message.isMe && message.recipientId == targetPeerId);
      return matchesPeer && !message.isEmergency;
    }).toList();
  }

  Future<void> sendMessage(String text, {String? recipientId}) async {
    final trimmed = text.trim();
    if (trimmed.isEmpty) return;

    final target = recipientId == null || recipientId == 'broadcast'
        ? 'broadcast'
        : recipientId;
    final message = MeshMessage(
      id: 'msg_${DateTime.now().microsecondsSinceEpoch}',
      senderId: _connectedNodeId ?? 'local_user',
      senderName: 'Carlos (Yo)',
      recipientId: target,
      content: trimmed,
      timestamp: DateTime.now(),
      isMe: true,
      status: MessageStatus.queued,
    );
    _messages.add(message);
    notifyListeners();

    await Future<void>.delayed(const Duration(milliseconds: 800));
    if (!_messages.contains(message)) return;
    message.status = MessageStatus.transmitted;
    notifyListeners();

    await Future<void>.delayed(const Duration(milliseconds: 1800));
    if (!_messages.contains(message)) return;
    final acknowledged = target == 'broadcast' || Random().nextDouble() > 0.10;
    message.status = acknowledged ? MessageStatus.ack : MessageStatus.failed;
    notifyListeners();
  }

  void simulateIncomingMessage({
    String? fromNodeId,
    String? text,
    bool isDirect = false,
  }) {
    final sender = _nodes.firstWhere(
      (node) => node.id == fromNodeId,
      orElse: () => _nodes.firstWhere(
        (node) => node.id != _connectedNodeId,
        orElse: () => _nodes.first,
      ),
    );
    _messages.add(
      MeshMessage(
        id: 'incoming_${DateTime.now().microsecondsSinceEpoch}',
        senderId: sender.id,
        senderName: sender.name,
        recipientId: isDirect
            ? (_connectedNodeId ?? 'local_user')
            : 'broadcast',
        content:
            text ??
            (isDirect
                ? 'Confirmando recepción de baliza P2P.'
                : 'Tráfico de prueba en el canal general.'),
        timestamp: DateTime.now(),
      ),
    );
    notifyListeners();
  }

  void triggerSos() {
    _isEmergencyActive = true;
    final sosNode = MeshNode(
      id: 'sos_beacon',
      name: 'Alerta SOS (Carlos)',
      latitude: 41.38650,
      longitude: 2.11520,
      batteryLevel: 88,
      snr: 9.8,
      isEmergency: true,
      lastHeard: DateTime.now(),
    );
    final index = _nodes.indexWhere((node) => node.id == sosNode.id);
    if (index >= 0) {
      _nodes[index] = sosNode;
    } else {
      _nodes.add(sosNode);
    }
    _messages.add(
      MeshMessage(
        id: 'sos_${DateTime.now().microsecondsSinceEpoch}',
        senderId: sosNode.id,
        senderName: 'ALERTA SOS',
        recipientId: 'broadcast',
        content: 'EMERGENCIA PRIORITARIA: Baliza transmitida en 41.3865° N, 2.1152° E',
        timestamp: DateTime.now(),
        isMe: true,
      ),
    );
    notifyListeners();
  }

  void cancelSos() {
    _isEmergencyActive = false;
    _nodes.removeWhere((node) => node.id == 'sos_beacon');
    notifyListeners();
  }

  Future<void> startScan() async {
    if (_isScanning) return;
    _isScanning = true;
    notifyListeners();
    _scanTimer = Timer(const Duration(seconds: 5), () {
      _isScanning = false;
      notifyListeners();
    });
  }

  Future<void> stopScan() async {
    _scanTimer?.cancel();
    _scanTimer = null;
    _isScanning = false;
    notifyListeners();
  }

  Future<void> connectToNode(String nodeId) async {
    if (_nodes.any((node) => node.id == nodeId)) {
      _connectedNodeId = nodeId;
      notifyListeners();
    }
  }

  Future<void> disconnectNode() async {
    _connectedNodeId = null;
    notifyListeners();
  }

  @override
  void dispose() {
    _scanTimer?.cancel();
    super.dispose();
  }
}
