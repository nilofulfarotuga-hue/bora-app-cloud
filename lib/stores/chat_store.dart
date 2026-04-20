import 'dart:async';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/message_model.dart';

/// Manages realtime chat messages per order, backed by Supabase.
///
/// Call [listen] once per order to open a realtime stream. History is
/// delivered on the first emission; subsequent emissions include any new
/// rows inserted by either party.
class ChatStore extends ChangeNotifier {
  final _supabase = Supabase.instance.client;

  final Map<String, List<MessageModel>> _messages = {};

  // StreamSubscription per order.
  // .stream() handles initial load + realtime in one subscription.
  final Map<String, StreamSubscription<List<Map<String, dynamic>>>>
      _subscriptions = {};

  // ── Read ──────────────────────────────────────────────────────────────────

  /// Returns an unmodifiable snapshot of messages for [orderId],
  /// sorted oldest-first (guaranteed by .order('created_at') on the stream).
  List<MessageModel> messagesForOrder(String orderId) =>
      List.unmodifiable(_messages[orderId] ?? const <MessageModel>[]);

  // ── Subscription ──────────────────────────────────────────────────────────

  /// Opens a Supabase `.stream()` for [orderId].
  ///
  /// The stream fires immediately with existing rows and again on every INSERT
  /// or UPDATE, so both sides (client and driver) receive new messages without
  /// any polling.
  void listen(String orderId) {
    // Always reconnect to ensure a fresh Realtime channel.
    final old = _subscriptions.remove(orderId);
    if (old != null) {
      debugPrint(
          '[ChatStore] ♻️ listen($orderId) — cancelling previous subscription');
      old.cancel();
    }

    debugPrint(
        '[ChatStore] 🔌 listen($orderId) — opening stream with filter: order=$orderId');

    final sub = _supabase
        .from('messages')
        .stream(primaryKey: ['id'])
        .eq('order_id', orderId)
        .order('created_at', ascending: true)
        .listen(
          (rows) {
            debugPrint(
                '[ChatStore] 📨 stream($orderId) delivered ${rows.length} rows');
            // .stream() always delivers the complete current list — replace in
            // full. The optimistic insert is overwritten by the authoritative DB
            // row on the next emission; because IDs match, the UI is unchanged.
            _messages[orderId] = rows.map(MessageModel.fromMap).toList();
            notifyListeners();
          },
          onError: (Object e) {
            debugPrint('[ChatStore] ❌ stream($orderId) ERROR: $e');
          },
          onDone: () {
            debugPrint('[ChatStore] 🔒 stream($orderId) DONE (channel closed)');
          },
        );

    _subscriptions[orderId] = sub;
    debugPrint('[ChatStore] ✅ listen($orderId) — subscription active');
  }

  // ── Write ─────────────────────────────────────────────────────────────────

  /// Inserts a plain text message into the `messages` table.
  ///
  /// Uses an **optimistic insert**: the message is added to the local list
  /// immediately so the UI updates without waiting for the Supabase round-trip.
  /// If the insert fails the message is rolled back and the error rethrown.
  /// The `.stream()` subscription will overwrite the optimistic entry with the
  /// authoritative DB row on its next emission (same ID, no visible change).
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

    // Optimistic insert — shows the message instantly in the UI.
    final list = _messages[orderId] ??= [];
    list.add(msg);
    notifyListeners();

    try {
      debugPrint(
          '[ChatStore] 📤 sendMessage → INSERT id=${msg.id} order=$orderId role=$senderRole');
      await _supabase.from('messages').insert(msg.toMap());
      debugPrint('[ChatStore] ✅ sendMessage → SUCCESS');
    } catch (e, st) {
      debugPrint('[ChatStore] ❌ sendMessage ERROR\n'
          '  orderId   : $orderId\n'
          '  senderRole: $senderRole\n'
          '  auth.uid(): ${_supabase.auth.currentUser?.id}\n'
          '  error     : $e\n$st');
      // Roll back the optimistic insert so the UI reflects reality.
      list.remove(msg);
      notifyListeners();
      rethrow;
    }
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

    // Optimistic insert.
    final list = _messages[orderId] ??= [];
    list.add(msg);
    notifyListeners();

    try {
      debugPrint(
          '[ChatStore] 📤 sendSubstitution → INSERT id=${msg.id} order=$orderId');
      await _supabase.from('messages').insert(msg.toMap());
      debugPrint('[ChatStore] ✅ sendSubstitution → SUCCESS');
    } catch (e, st) {
      debugPrint('[ChatStore] ❌ sendSubstitution ERROR\n'
          '  orderId  : $orderId\n'
          '  senderId : $senderId\n'
          '  auth.uid(): ${_supabase.auth.currentUser?.id}\n'
          '  error    : $e\n$st');
      list.remove(msg);
      notifyListeners();
      rethrow;
    }
  }

  // ── Cleanup ───────────────────────────────────────────────────────────────

  /// Cancels the stream subscription for [orderId] and clears its local messages.
  void unlisten(String orderId) {
    debugPrint('[ChatStore] 🔌 unlisten($orderId)');
    _subscriptions.remove(orderId)?.cancel();
    _messages.remove(orderId);
  }

  @override
  void dispose() {
    debugPrint(
        '[ChatStore] 🗑️ dispose — cancelling ${_subscriptions.length} subscriptions');
    for (final sub in _subscriptions.values) {
      sub.cancel();
    }
    _subscriptions.clear();
    super.dispose();
  }
}
