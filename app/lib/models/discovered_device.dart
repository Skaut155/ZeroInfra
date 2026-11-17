/// Nodo Meshtastic encontrado en un escaneo BLE (aún sin conectar).
///
/// Lo muestra la vista Nodos; su [id] es lo que recibe
/// `MeshRepository.connect`.
class DiscoveredDevice {
  const DiscoveredDevice({
    required this.id,
    required this.name,
    required this.rssi,
  });

  /// Android: dirección MAC. iOS: UUID que asigna el sistema.
  final String id;
  /// Nombre anunciado o el que conoce el sistema; si no hay ninguno,
  /// «Nodo Meshtastic».
  final String name;
  /// Intensidad de la señal recibida, en dBm.
  final int rssi;
}
