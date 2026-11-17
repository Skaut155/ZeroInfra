/// Nodo de la malla tal como lo conoce la app.
///
/// Los campos de [id] a [lastHeard] y el orden y tipos del constructor son
/// los de Carlos; los usa `services/mesh_provider.dart`. El resto se añade
/// para la malla real y es opcional. Como los campos de Carlos no admiten
/// null, la falta de dato se indica aparte: [hasPosition], [hasBattery],
/// [lastHeard] igual a [neverHeard] y [snr] igual a 0.
class MeshNode {
  // --- Campos originales de Carlos, con sus tipos ---
  /// Id en texto. Con la malla real, `"!a1b2c3d4"` ([idFromNum]); en el
  /// simulador de Carlos, uno libre (`node_esp32_01`).
  final String id;
  /// Nombre largo. Mientras no llega la ficha del nodo, `Nodo xxxx` (los
  /// cuatro últimos dígitos del id).
  final String name;
  /// Grados decimales. Solo es válida si [hasPosition] es true.
  final double latitude;
  /// Grados decimales. Solo es válida si [hasPosition] es true.
  final double longitude;
  /// 0-100; solo es válido si [hasBattery] es true.
  final int batteryLevel;
  /// SNR (dB) del último paquete oído de este nodo; 0 si no se conoce.
  final double snr;
  /// Pendiente: Meshtastic no marca qué nodo es el gateway; con la placa
  /// real es siempre false (solo los simuladores marcan uno).
  final bool isGateway;
  /// Tiene un SOS activo, recibido o, si [isMe], enviado desde este móvil.
  final bool isEmergency;
  /// Última vez que se oyó al nodo; [neverHeard] si aún no se le ha oído.
  final DateTime lastHeard;

  // --- Añadidos para la malla real (todos opcionales) ---
  /// Número de nodo Meshtastic, que identifica el nodo; 0 en los nodos del
  /// simulador de Carlos.
  final int nodeNum;
  /// Nombre corto; vacío si no se conoce.
  final String shortName;
  /// Saltos hasta este nodo: 0 = vecino directo; null si no se conoce.
  final int? hopsAway;
  /// Es el nodo conectado a este móvil.
  final bool isMe;
  /// [latitude] y [longitude] son válidas. Por defecto true, porque los
  /// nodos del simulador de Carlos siempre traen posición.
  final bool hasPosition;
  /// [batteryLevel] es válido. Por defecto true, como [hasPosition].
  final bool hasBattery;

  /// Valor de [lastHeard] de un nodo al que aún no se ha oído (instante 0).
  static final DateTime neverHeard = DateTime.fromMillisecondsSinceEpoch(0);

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
    this.nodeNum = 0,
    this.shortName = '',
    this.hopsAway,
    this.isMe = false,
    this.hasPosition = true,
    this.hasBattery = true,
  });

  /// Nodo del que solo se conoce el número: sin posición, batería, SNR ni
  /// nombre propio. Es el punto de partida cuando llega el primer dato de un
  /// nodo nuevo.
  factory MeshNode.unknown(int nodeNum) {
    final id = idFromNum(nodeNum);
    return MeshNode(
      id: id,
      name: 'Nodo ${id.substring(id.length - 4)}',
      latitude: 0,
      longitude: 0,
      batteryLevel: 0,
      snr: 0,
      lastHeard: neverHeard,
      nodeNum: nodeNum,
      hasPosition: false,
      hasBattery: false,
    );
  }

  /// Id en texto de un número de nodo, como lo escribe Meshtastic:
  /// `0xa1b2c3d4` → `"!a1b2c3d4"` (8 dígitos hexadecimales).
  static String idFromNum(int nodeNum) =>
      '!${nodeNum.toRadixString(16).padLeft(8, '0')}';

  /// Copia cambiando los campos indicados. Un argumento null conserva el
  /// valor actual (así que [hopsAway] no puede volver a null). La posición
  /// solo cambia si llegan las dos coordenadas; pasar posición o batería
  /// marca además el dato como conocido ([hasPosition], [hasBattery]).
  /// [id] y [nodeNum] no cambian.
  MeshNode copyWith({
    String? name,
    String? shortName,
    double? latitude,
    double? longitude,
    int? batteryLevel,
    double? snr,
    int? hopsAway,
    bool? isMe,
    bool? isGateway,
    bool? isEmergency,
    DateTime? lastHeard,
  }) {
    // La posición solo cambia si llegan las dos coordenadas.
    final lat = longitude == null ? null : latitude;
    final lon = latitude == null ? null : longitude;
    return MeshNode(
      id: id,
      name: name ?? this.name,
      latitude: lat ?? this.latitude,
      longitude: lon ?? this.longitude,
      batteryLevel: batteryLevel ?? this.batteryLevel,
      snr: snr ?? this.snr,
      isGateway: isGateway ?? this.isGateway,
      isEmergency: isEmergency ?? this.isEmergency,
      lastHeard: lastHeard ?? this.lastHeard,
      nodeNum: nodeNum,
      shortName: shortName ?? this.shortName,
      hopsAway: hopsAway ?? this.hopsAway,
      isMe: isMe ?? this.isMe,
      hasPosition: hasPosition || lat != null,
      hasBattery: hasBattery || batteryLevel != null,
    );
  }
}
