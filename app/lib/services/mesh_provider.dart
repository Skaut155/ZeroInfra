import 'dart:async';
import 'dart:math';

import 'package:flutter/foundation.dart';

import '../models/mesh_message.dart';
import '../models/mesh_node.dart';

class MeshProvider extends ChangeNotifier {
  bool _isScanning = false;
  String? _connectedNodeId = 'node_esp32_01';
  bool _isEmergencyActive = false;
  Timer? _scanTimer;

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
  List<MeshNode> get nodes => List.unmodifiable(_nodes);
  List<MeshMessage> get messages => List.unmodifiable(_messages);

  MeshNode? get connectedNode {
    for (final node in _nodes) {
      if (node.id == _connectedNodeId) return node;
    }
    return null;
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
