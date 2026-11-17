import '../../models/discovered_device.dart';

/// Transporte de bytes entre la app y el nodo Meshtastic, sin saber nada de
/// Protobuf.
///
/// Lo usa `MeshtasticClient`. La implementación real es `BleMeshTransport`;
/// los tests usan una de mentira.
abstract class MeshTransport {
  /// Dispositivos encontrados en el escaneo en curso.
  Stream<List<DiscoveredDevice>> get scanResults;
  /// true mientras hay un escaneo en marcha.
  Stream<bool> get isScanning;
  Future<void> startScan();
  Future<void> stopScan();

  /// Establece el enlace con el nodo [deviceId] y prepara sus
  /// características; no envía nada al nodo.
  Future<void> connect(String deviceId);
  Future<void> disconnect();
  /// true al establecerse el enlace, false al perderse.
  Stream<bool> get linkState;

  /// Un evento por paquete FromRadio; los fallos de lectura llegan como error.
  Stream<List<int>> get fromRadioStream;
  /// Escribe un `ToRadio` ya serializado.
  Future<void> writeToRadio(List<int> bytes);
  /// Lee todos los paquetes pendientes y los publica en [fromRadioStream].
  /// El cliente la llama una vez tras pedir la configuración; después el
  /// transporte vacía solo con cada aviso del nodo.
  Future<void> drainFromRadio();

  Future<void> dispose();
}
