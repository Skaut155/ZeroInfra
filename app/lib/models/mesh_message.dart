/// Estado de entrega de un [MeshMessage]. Los cuatro valores son los que
/// definió Carlos:
///
/// - `queued`: propio; todavía no se ha entregado al nodo por BLE.
/// - `transmitted`: propio; el nodo lo ha aceptado para emitirlo por radio.
/// - `ack`: acuse recibido. En difusión, algún nodo lo ha retransmitido; en
///   un directo, lo ha confirmado el destinatario. No significa que nadie lo
///   haya leído. Es también el estado de todo mensaje recibido.
/// - `failed`: propio; no se pudo escribir en el nodo, el nodo no pudo
///   encolarlo, la malla devolvió un error o se perdió la conexión antes de
///   entregarlo al nodo.
enum MessageStatus { queued, transmitted, ack, failed }

/// Mensaje de texto de la malla, propio o recibido (incluidos los SOS).
///
/// Los campos de [id] a [status], [isDirect], [isEmergency] (ampliado con
/// [isSos]) y el constructor son los de Carlos; los usan
/// `services/mesh_provider.dart` y el chat. La segunda mitad se añade para
/// la malla real y es opcional: los mensajes simulados se crean como antes.
class MeshMessage {
  // --- Campos originales de Carlos ---
  /// Clave única del mensaje en la app. Con la malla real es
  /// `"<senderId>_<packetId>"`; no es el id del paquete (ver [packetId]).
  final String id;
  /// Id en texto del remitente; con la malla real, `"!a1b2c3d4"`.
  final String senderId;
  /// Nombre del remitente en el momento de crear el mensaje.
  final String senderName;
  /// [broadcastId] (o null) en una difusión; en un directo, el id del nodo
  /// destinatario.
  final String? recipientId;
  /// Texto. En un SOS, una descripción legible (`EmergencyText.describe`);
  /// lo que viaja por radio es un EMG1 binario.
  final String content;
  /// Hora de envío o de recepción en este móvil.
  final DateTime timestamp;
  /// Enviado desde este móvil.
  final bool isMe;
  /// Estado de entrega. Es mutable porque el simulador de Carlos lo cambia
  /// en el sitio; la capa real no lo modifica, emite una copia ([copyWith]).
  MessageStatus status;

  // --- Añadidos para la malla real (todos opcionales) ---
  /// Id del paquete Meshtastic (`MeshPacket.id`), el que casa con su acuse;
  /// 0 en los mensajes simulados.
  final int packetId;
  /// Número del nodo remitente; 0 en los mensajes del simulador de Carlos.
  final int senderNum;
  /// Número del nodo destinatario; null en una difusión.
  final int? recipientNum;
  /// Índice del canal (`MeshChannel.index`) por el que viaja.
  final int channel;
  /// Es un SOS o su cancelación (EMG1, ver `emergency_policy.dart`).
  final bool isSos;

  /// Valor de [recipientId] en una difusión (el texto que ya usaba Carlos).
  static const String broadcastId = 'broadcast';

  /// Va dirigido a un nodo concreto (no es una difusión).
  bool get isDirect => recipientId != null && recipientId != broadcastId;
  /// Es un SOS de la malla real ([isSos]) o la alerta del simulador de
  /// Carlos (`senderId == 'sos_beacon'`).
  bool get isEmergency => isSos || senderId == 'sos_beacon';

  MeshMessage({
    required this.id,
    required this.senderId,
    required this.senderName,
    required this.recipientId,
    required this.content,
    required this.timestamp,
    this.isMe = false,
    this.status = MessageStatus.ack,
    this.packetId = 0,
    this.senderNum = 0,
    this.recipientNum,
    this.channel = 0,
    this.isSos = false,
  });

  /// Copia del mensaje con otro [status]; el resto de campos no cambia.
  MeshMessage copyWith({MessageStatus? status}) {
    return MeshMessage(
      id: id,
      senderId: senderId,
      senderName: senderName,
      recipientId: recipientId,
      content: content,
      timestamp: timestamp,
      isMe: isMe,
      status: status ?? this.status,
      packetId: packetId,
      senderNum: senderNum,
      recipientNum: recipientNum,
      channel: channel,
      isSos: isSos,
    );
  }
}
