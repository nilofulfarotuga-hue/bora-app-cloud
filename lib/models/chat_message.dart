enum ChatSenderType { client, driver }

class ChatMessage {
  ChatMessage({
    required this.id,
    required this.orderId,
    required this.senderType,
    required this.message,
    required this.timestamp,
  });

  final String id;
  final String orderId;
  final ChatSenderType senderType;
  final String message;
  final DateTime timestamp;
}
