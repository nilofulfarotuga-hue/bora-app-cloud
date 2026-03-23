import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/message_model.dart';

/// Manages realtime chat messages per order, backed by Supabase.
///
/// Call [listen] once per order to load history and subscribe to new INSERTs.
/// The subscription is idempotent — calling [listen] again for the same order
/// is a no-op.
class ChatStore extends ChangeNotifier {
  final _supabase = Supabase.instance.client;

  final Map<String, List<MessageModel>> _messages = {};
  final Map<String, RealtimeChannel> _channels = {};

  // ── Read ──────────────────────────────────────────────────────────────────

  /// Returns an unmodifiable snapshot of messages for [orderId],
  /// sorted oldest-first.
  List<MessageModel> messagesForOrder(String orderId) =>
      List.unmodifiable(_messages[orderId] ?? const <MessageModel>[]);

  // ── Subscription ──────────────────────────────────────────────────────────

  /// Loads existing messages for [orderId] and subscribes to new INSERTs.
  /// Idempotent: subsequent calls for the same [orderId] are ignored.
  Future<void> listen(String orderId) async {
    if (_channels.containsKey(orderId)) return;

    // Load history before opening the channel so we don't miss or double-count
    // rows that arrive during the async load.
    try {
      final rows = await _supabase
          .from('messages')
          .select()
          .eq('order_id', orderId)
          .order('created_at');
      _messages[orderId] = rows.map(MessageModel.fromMap).toList();
      notifyListeners();
    } catch (e) {
      debugPrint('ChatStore.listen: history load error => $e');
    }

    final channel = _supabase
        .channel('messages_$orderId')
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'messages',
          callback: (payload) {
            try {
              final data = payload.newRecord;
              if (data.isEmpty) return;
              // Filter by order in the callback — avoids SDK filter API
              // version differences and keeps the same pattern as OrderStore.
              if (data['order_id'] != orderId) return;
              final msg = MessageModel.fromMap(data);
              final list = _messages[orderId] ??= [];
              if (list.any((m) => m.id == msg.id)) return; // dedup
              list.add(msg);
              notifyListeners();
            } catch (e) {
              debugPrint('ChatStore realtime INSERT error => $e');
            }
          },
        )
        .subscribe((status, [error]) {
      if (error != null) {
        debugPrint('ChatStore[$orderId] subscribe error: $error');
      }
    });

    _channels[orderId] = channel;
  }

  // ── Write ─────────────────────────────────────────────────────────────────

  /// Inserts a plain text message into the `messages` table.
  /// Throws on network / Supabase error — caller should handle.
  Future<void> sendMessage({
    required String orderId,
    required String senderId,
    required String senderRole,
    required String content,
  }) async {
    final msg = MessageModel.text(
      orderId: orderId,
      senderId: senderId,
      senderRole: senderRole,
      content: content,
    );
    await _supabase.from('messages').insert(msg.toMap());
    // Realtime INSERT event will add the row to _messages automatically.
  }

  /// Inserts a structured substitution proposal message.
  /// Throws on network / Supabase error — caller should handle.
  Future<void> sendSubstitution({
    required String orderId,
    required String senderId,
    required String original,
    required String suggestion,
    required double price,
  }) async {
    final msg = MessageModel.substitution(
      orderId: orderId,
      senderId: senderId,
      original: original,
      suggestion: suggestion,
      price: price,
    );
    await _supabase.from('messages').insert(msg.toMap());
  }

  // ── Cleanup ───────────────────────────────────────────────────────────────

  /// Unsubscribes from [orderId] and clears its local messages.
  void unlisten(String orderId) {
    final channel = _channels.remove(orderId);
    if (channel != null) _supabase.removeChannel(channel);
    _messages.remove(orderId);
  }

  @override
  void dispose() {
    for (final channel in _channels.values) {
      _supabase.removeChannel(channel);
    }
    super.dispose();
  }
}
