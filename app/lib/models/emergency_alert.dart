enum EmergencyDeliveryStatus {
  prepared,
  acceptedByBle,
  networkAck,
  appReceipt,
  resolved,
  failed,
}

class EmergencyAlert {
  final int id;
  final int originNode;
  final int severity;
  final String text;
  final int expiresUnix;
  final int senderNode;
  final int destinationNode;
  final int channel;
  final int meshPacketId;
  final DateTime receivedAt;
  EmergencyDeliveryStatus status;
  bool isReplay;
  String? resolutionNote;
  int? receiptFromNode;

  // Añadidos por la capa de datos (opcionales):
  /// Posición que trae el texto de la alerta; null si no la trae.
  final double? latitude;
  final double? longitude;
  /// El firmware verificó la firma del emisor (`MeshPacket.xeddsa_signed`).
  /// Si es false, cualquiera podría haber suplantado al origen.
  final bool isVerified;

  EmergencyAlert({
    required this.id,
    required this.originNode,
    required this.severity,
    required this.text,
    required this.expiresUnix,
    required this.senderNode,
    required this.destinationNode,
    required this.channel,
    required this.meshPacketId,
    required this.receivedAt,
    this.status = EmergencyDeliveryStatus.prepared,
    this.isReplay = false,
    this.resolutionNote,
    this.receiptFromNode,
    this.latitude,
    this.longitude,
    this.isVerified = false,
  });

  String get compositeKey => '${originNode}_$id';

  bool get hasPosition => latitude != null && longitude != null;

  bool get isBroadcast => destinationNode == 0xffffffff;

  bool get isExpired {
    if (expiresUnix == 0) return false;
    final nowUnix = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    return nowUnix > expiresUnix;
  }

  String get severityLabel {
    switch (severity) {
      case 3:
        return 'CRÍTICA';
      case 2:
        return 'MEDIA';
      case 1:
      default:
        return 'BAJA';
    }
  }
}
