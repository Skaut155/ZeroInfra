class MeshNode {
  final String id;
  final String name;
  final double latitude;
  final double longitude;
  final int batteryLevel;
  final double snr;
  final bool isGateway;
  final bool isEmergency;
  final DateTime lastHeard;

  MeshNode({
    required this.id,
    required this.name,
    required this.latitude,
    required this.longitude,
    required this.batteryLevel,
    required this.snr,
    this.isGateway = false,
    this.isEmergency = false,
    required this.lastHeard,
  });
}