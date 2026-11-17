import '../../generated/meshtastic/mesh.pbenum.dart' show MeshPacket_Priority;
import '../../generated/meshtastic/portnums.pbenum.dart' show PortNum;

/// PROVISIONAL: el equipo aún no ha cerrado el formato del SOS. Todo lo que
/// distingue un SOS de un mensaje normal está en este fichero.
///
/// Cómo se envía un SOS por la malla. La aplican `MeshtasticClient` (y, en
/// parte, `FakeMeshRepository`); cambiar el comportamiento del SOS es
/// cambiar estas constantes. Se envía un solo paquete, con acuse.
abstract final class SosPolicy {
  /// ALERT_APP es el puerto de Meshtastic para alertas críticas: el firmware
  /// puede reconocer un SOS por el puerto, sin leer el texto. Al recibir, el
  /// cliente acepta un SOS tanto por ALERT_APP como por TEXT_MESSAGE_APP.
  static const PortNum portNum = PortNum.ALERT_APP;
  /// Prioridad en la cola de envío del nodo emisor (por confirmar si los
  /// nodos intermedios la conocen).
  static const MeshPacket_Priority priority = MeshPacket_Priority.ALERT;
  /// TTL del SOS en saltos. 7 es el máximo del protocolo (3 bits de cabecera).
  static const int hopLimit = 7;
  /// Canal por el que se difunde el SOS (el primario).
  static const int channel = 0;
}

/// Tipo de señal SOS: alerta o cancelación de una alerta anterior.
enum SosKind { alert, cancel }

/// Contenido de un SOS ya decodificado (o por codificar).
class SosSignal {
  const SosSignal({
    required this.kind,
    required this.nodeNum,
    this.latitude,
    this.longitude,
  });

  final SosKind kind;
  /// Nodo que emite el SOS, según el texto.
  final int nodeNum;
  /// Posición del nodo (viaja con 5 decimales); null sin GPS o al cancelar.
  final double? latitude;
  final double? longitude;
}

/// Codifica y decodifica el texto de un SOS:
///
/// ```text
/// SOS|v1|!a1b2c3d4|41.38879|2.11296   (alerta)
/// SOS|v1|!a1b2c3d4|CANCEL             (cancelación)
/// ```
///
/// La posición va vacía si el nodo no tiene GPS (`SOS|v1|!a1b2c3d4||`).
abstract final class SosCodec {
  static const String _prefix = 'SOS';
  static const String _version = 'v1';
  static const String _cancel = 'CANCEL';

  /// Texto que viaja en el paquete para [signal].
  static String encode(SosSignal signal) {
    final node = '!${signal.nodeNum.toRadixString(16).padLeft(8, '0')}';
    final head = '$_prefix|$_version|$node';
    if (signal.kind == SosKind.cancel) return '$head|$_cancel';
    final lat = signal.latitude?.toStringAsFixed(5) ?? '';
    final lon = signal.longitude?.toStringAsFixed(5) ?? '';
    return '$head|$lat|$lon';
  }

  /// null si [text] no es un SOS con este formato.
  static SosSignal? tryDecode(String text) {
    final parts = text.split('|');
    if (parts.length < 4 || parts[0] != _prefix || parts[1] != _version) {
      return null;
    }
    final node = parts[2];
    if (!node.startsWith('!')) return null;
    final nodeNum = int.tryParse(node.substring(1), radix: 16);
    if (nodeNum == null) return null;
    if (parts[3] == _cancel) {
      return SosSignal(kind: SosKind.cancel, nodeNum: nodeNum);
    }
    if (parts.length < 5) return null;
    return SosSignal(
      kind: SosKind.alert,
      nodeNum: nodeNum,
      latitude: double.tryParse(parts[3]),
      longitude: double.tryParse(parts[4]),
    );
  }
}
