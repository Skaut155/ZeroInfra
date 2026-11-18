enum MessageStatus { queued, transmitted, ack, failed }

class MeshMessage {
  final String id;
  final String senderId;
  final String senderName;
  final String? recipientId;
  final String content;
  final DateTime timestamp;
  final bool isMe;
  MessageStatus status;

  bool get isDirect => recipientId != null && recipientId != 'broadcast';
  bool get isEmergency => senderId == 'sos_beacon';

  MeshMessage({
    required this.id,
    required this.senderId,
    required this.senderName,
    required this.recipientId,
    required this.content,
    required this.timestamp,
    this.isMe = false,
    this.status = MessageStatus.ack,
  });
}
