class MeshMessage {
  final String senderId;
  final String senderName;
  final String content;
  final DateTime timestamp;
  final bool isDirect;
  final bool isMe;

  MeshMessage({
    required this.senderId,
    required this.senderName,
    required this.content,
    required this.timestamp,
    this.isDirect = false,
    this.isMe = false,
  });
}