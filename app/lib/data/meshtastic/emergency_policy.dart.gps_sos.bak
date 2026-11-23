import '../../core/emergency_codec.dart';
import '../../generated/meshtastic/mesh.pbenum.dart' show MeshPacket_Priority;
import '../../generated/meshtastic/portnums.pbenum.dart' show PortNum;

/// Cómo viaja un SOS por la malla. El formato binario es EMG1, el del
/// firmware de Cristina (`EmergencyWire.h`), y lo codifica `EmgCodec`.
///
/// El firmware solo da prioridad ALERT en cada salto a un EMG1 de tipo
/// ALERT por PRIVATE_APP, con `originNode` igual al emisor y firmado. Como
/// Meshtastic solo firma las difusiones, el SOS se envía siempre en difusión.
abstract final class EmergencyPolicy {
  /// Puerto que reconoce el módulo de emergencias del firmware.
  static const PortNum portNum = PortNum.PRIVATE_APP;
  /// Prioridad en la cola del nodo emisor (el firmware la fija igualmente).
  static const MeshPacket_Priority priority = MeshPacket_Priority.ALERT;
  /// TTL en saltos; 7 es el máximo del protocolo (3 bits de cabecera).
  static const int hopLimit = 7;
  /// Canal por el que se difunde (el primario).
  static const int channel = 0;
  /// Gravedad de un SOS enviado desde la app (1 a 3; 3 es la máxima).
  static const int severity = 3;
  /// 0 = sin caducidad. La hora de las placas puede no ser fiable, así que
  /// la app no fija una.
  static const int expiresUnix = 0;
  /// Texto del SOS tras las coordenadas. Debe ser corto: si el paquete no
  /// cabe junto con la firma, pierde la prioridad en los retransmisores.
  static const String text = 'SOS';
}

/// Posición dentro del texto de un EMG1: `@41.38879,2.11296 SOS`.
///
/// EMG1 no tiene campos de posición, así que las coordenadas van al
/// principio del texto, con 5 decimales (≈ 1 m). Sin GPS el texto va solo.
abstract final class EmergencyText {
  static final RegExp _prefix = RegExp(
    r'^@(-?\d{1,3}(?:\.\d+)?),(-?\d{1,3}(?:\.\d+)?)(?:\s+|$)',
  );

  /// Texto de un ALERT: [body] precedido de la posición, si la hay.
  static String encode({
    double? latitude,
    double? longitude,
    String body = EmergencyPolicy.text,
  }) {
    if (latitude == null || longitude == null) return body;
    final lat = latitude.toStringAsFixed(5);
    final lon = longitude.toStringAsFixed(5);
    return '@$lat,$lon $body';
  }

  /// Posición al principio de [text]; null si no la lleva o está fuera de
  /// rango.
  static ({double latitude, double longitude})? position(String text) {
    final match = _prefix.firstMatch(text);
    if (match == null) return null;
    final lat = double.parse(match.group(1)!);
    final lon = double.parse(match.group(2)!);
    if (lat.abs() > 90 || lon.abs() > 180) return null;
    return (latitude: lat, longitude: lon);
  }

  /// [text] sin la posición del principio.
  static String body(String text) => text.replaceFirst(_prefix, '').trim();

  /// Contenido legible para el chat de un ALERT o un RESOLVED.
  static String describe({
    required EmgKind kind,
    String body = '',
    double? latitude,
    double? longitude,
    bool verified = true,
  }) {
    if (kind == EmgKind.resolved) return 'SOS cancelado';
    final parts = [
      body.isEmpty ? EmergencyPolicy.text : body,
      if (latitude != null && longitude != null)
        '${latitude.toStringAsFixed(5)}, ${longitude.toStringAsFixed(5)}',
      if (!verified) 'no verificada',
    ];
    return parts.join(' · ');
  }
}
