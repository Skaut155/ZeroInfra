import '../models/connection_status.dart';
import '../models/discovered_device.dart';
import '../models/emergency_alert.dart';
import '../models/mesh_channel.dart';
import '../models/mesh_message.dart';
import '../models/mesh_node.dart';

/// Faltan los permisos del sistema necesarios para usar el Bluetooth.
///
/// La lanzan [MeshRepository.startScan] y [MeshRepository.connect];
/// `ConnectionProvider` la convierte en un mensaje para la interfaz.
class MeshPermissionException implements Exception {
  const MeshPermissionException({required this.permanentlyDenied});

  /// true: el sistema ya no muestra el diálogo; hay que ir a los ajustes.
  final bool permanentlyDenied;

  @override
  String toString() => 'Faltan permisos de Bluetooth';
}

/// Contrato de la capa de datos de la malla: conexión con el nodo, nodos,
/// canales y mensajes.
///
/// Los providers solo dependen de esta interfaz. Hay dos implementaciones:
/// `MeshtasticClient` (nodo real por BLE) y `FakeMeshRepository` (simulada).
abstract class MeshRepository {
  // --- Conexión con el nodo ---
  /// Estado actual de la conexión con el nodo.
  ConnectionStatus get status;
  /// Emite cada cambio de [status].
  Stream<ConnectionStatus> get statusStream;
  /// Nodos Meshtastic encontrados en el escaneo en curso.
  Stream<List<DiscoveredDevice>> get scanResults;
  /// true mientras hay un escaneo BLE en marcha.
  Stream<bool> get isScanning;
  /// Empieza a buscar nodos; los resultados llegan por [scanResults].
  ///
  /// Lanza [MeshPermissionException] si faltan permisos y [StateError] si el
  /// Bluetooth está apagado o el móvil no lo soporta.
  Future<void> startScan();
  /// Detiene el escaneo en curso.
  Future<void> stopScan();
  /// Conecta con el nodo [deviceId] (un [DiscoveredDevice.id]) y descarga su
  /// configuración: nodos, canales y nodo propio. Al terminar, [status] es
  /// [ConnectionStatus.connected].
  ///
  /// Lanza [MeshPermissionException] si faltan permisos; [StateError] si ya
  /// hay una conexión activa o en curso, si el dispositivo no ofrece el
  /// servicio Meshtastic o si el enlace se pierde durante la descarga; y
  /// `TimeoutException` si el nodo no completa la configuración (30 s en
  /// `MeshtasticClient`). Puede propagar también errores del propio plugin
  /// BLE. Si falla, el estado vuelve a [ConnectionStatus.disconnected].
  Future<void> connect(String deviceId);
  /// Cierra la conexión con el nodo.
  Future<void> disconnect();

  // --- Estado de la malla ---
  /// Número del nodo conectado a este móvil; null sin conexión.
  int? get myNodeNum;
  /// Nodos conocidos por el nodo conectado, incluido el propio
  /// ([MeshNode.isMe]).
  List<MeshNode> get nodes;
  /// Emite la lista completa de [nodes] cada vez que cambia algún nodo.
  Stream<List<MeshNode>> get nodesStream;
  /// Canales activos del nodo (los deshabilitados no aparecen).
  List<MeshChannel> get channels;
  /// Emite la lista completa de [channels] cada vez que cambia.
  Stream<List<MeshChannel>> get channelsStream;

  // --- Mensajes ---
  /// Emite cada mensaje nuevo y, para los propios, una copia con el mismo id
  /// cada vez que cambia su estado de entrega.
  ///
  /// No guarda historial: quien escucha debe acumularlos (lo hace
  /// `ChatProvider`).
  Stream<MeshMessage> get messages;
  /// Envía [text] por la malla: con [toNode] null es una difusión por el
  /// canal [channel]; con [toNode] es un mensaje directo a ese nodo.
  ///
  /// Antes de entregarlo al nodo lo emite por [messages] en estado
  /// [MessageStatus.queued]. Devuelve el mensaje en
  /// [MessageStatus.transmitted] (o en un estado posterior si el acuse llegó
  /// antes); los cambios siguientes llegan por [messages].
  ///
  /// Lanza [StateError] sin conexión y [ArgumentError] si el texto está
  /// vacío o supera 233 bytes en UTF-8 (el simulador no mira el tamaño).
  Future<MeshMessage> sendText(String text, {int? toNode, int channel = 0});
  /// Difunde un SOS (EMG1 ALERT) con la posición del nodo propio, si la
  /// tiene, y marca el nodo propio en emergencia. Formato y política en
  /// `emergency_policy.dart`. También lo emite por [messages] con
  /// [MeshMessage.isSos] y un texto legible.
  ///
  /// Lanza [StateError] sin conexión.
  Future<MeshMessage> sendSos();
  /// Difunde la cancelación (EMG1 RESOLVED) del último SOS y quita la marca
  /// de emergencia del nodo propio. Lanza [StateError] sin conexión o si no
  /// hay un SOS activo.
  Future<MeshMessage> cancelSos();

  // --- Alertas de otros nodos ---
  /// Emite cada alerta EMG1 de otro nodo al llegar y otra vez, con
  /// `status` [EmergencyDeliveryStatus.resolved], cuando se cancela. Cada
  /// alerta (origen + id) llega una sola vez aunque se reciba repetida.
  Stream<EmergencyAlert> get alerts;
  /// Alertas de otros nodos sin cancelar ni caducar, la más reciente última.
  List<EmergencyAlert> get activeAlerts;

  Future<void> dispose();
}
