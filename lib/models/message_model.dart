import 'dart:convert';

import 'package:uuid/uuid.dart';

enum MessageType { text, substitution }

/// Parsed content of a substitution proposal message.
class SubstitutionContent {
  const SubstitutionContent({
    required this.original,
    required this.suggestion,
    required this.price,
  });

  final String original;
  final String suggestion;
  final double price;

  factory SubstitutionContent.fromJson(Map<String, dynamic> json) {
    return SubstitutionContent(
      original: json['original'] as String? ?? '',
      suggestion: json['suggestion'] as String? ?? '',
      price: (json['price'] as num?)?.toDouble() ?? 0.0,
    );
  }

  Map<String, dynamic> toJson() => {
        'original': original,
        'suggestion': suggestion,
        'price': price,
      };
}

/// Supabase-backed chat message with support for plain text and
/// structured substitution proposals.
class MessageModel {
  MessageModel({
    required this.id,
    required this.orderId,
    required this.senderId,
    required this.senderRole,
    required this.type,
    required this.content,
    required this.createdAt,
  });

  final String id;
  final String orderId;
  final String senderId;

  /// 'client' or 'driver'
  final String senderRole;
  final MessageType type;

  /// Plain text for [MessageType.text]; JSON-encoded [SubstitutionContent]
  /// for [MessageType.substitution].
  final String content;
  final DateTime createdAt;

  /// Parsed substitution data. Returns null for text messages or on
  /// malformed JSON.
  SubstitutionContent? get substitutionContent {
    if (type != MessageType.substitution) return null;
    try {
      return SubstitutionContent.fromJson(
          jsonDecode(content) as Map<String, dynamic>);
    } catch (_) {
      return null;
    }
  }

  // ── Factories ─────────────────────────────────────────────────────────────

  factory MessageModel.text({
    required String orderId,
    required String senderId,
    required String senderRole,
    required String content,
  }) {
    return MessageModel(
      id: const Uuid().v4(),
      orderId: orderId,
      senderId: senderId,
      senderRole: senderRole,
      type: MessageType.text,
      content: content,
      createdAt: DateTime.now(),
    );
  }

  factory MessageModel.substitution({
    required String orderId,
    required String senderId,
    required String original,
    required String suggestion,
    required double price,
  }) {
    final payload = SubstitutionContent(
      original: original,
      suggestion: suggestion,
      price: price,
    );
    return MessageModel(
      id: const Uuid().v4(),
      orderId: orderId,
      senderId: senderId,
      senderRole: 'driver',
      type: MessageType.substitution,
      content: jsonEncode(payload.toJson()),
      createdAt: DateTime.now(),
    );
  }

  // ── Serialisation ─────────────────────────────────────────────────────────

  factory MessageModel.fromMap(Map<String, dynamic> data) {
    final typeStr = data['type'] as String? ?? 'text';
    final type = MessageType.values.firstWhere(
      (e) => e.name == typeStr,
      orElse: () => MessageType.text,
    );
    return MessageModel(
      id: data['id'] as String,
      orderId: data['order_id'] as String,
      senderId: data['sender_id'] as String,
      senderRole: data['sender_role'] as String? ?? 'client',
      type: type,
      content: data['content'] as String? ?? '',
      createdAt: data['created_at'] != null
          ? DateTime.tryParse(data['created_at'].toString()) ?? DateTime.now()
          : DateTime.now(),
    );
  }

  Map<String, dynamic> toMap() => {
        'id': id,
        'order_id': orderId,
        'sender_id': senderId,
        'sender_role': senderRole,
        'type': type.name,
        'content': content,
        'created_at': createdAt.toIso8601String(),
      };
}
