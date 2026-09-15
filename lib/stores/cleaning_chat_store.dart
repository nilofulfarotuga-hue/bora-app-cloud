import 'dart:async';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Mensagem de chat da LIMPEZA (tabela dedicada `cleaning_messages`,
/// scoping por reserva — padrão TVDE E1).
class CleaningMessage {
  CleaningMessage({
    required this.id,
    required this.bookingId,
    required this.senderRole,
    required this.content,
    required this.createdAt,
    required this.read,
  });

  final String id;
  final String bookingId;
  final String senderRole; // 'client' | 'cleaner'
  final String content;
  final DateTime createdAt;
  final bool read;

  factory CleaningMessage.fromMap(Map<String, dynamic> m) => CleaningMessage(
        id: m['id'] as String,
        bookingId: m['booking_id'] as String,
        senderRole: m['sender_role'] as String? ?? 'client',
        content: m['message'] as String? ?? '',
        createdAt: DateTime.tryParse(m['created_at']?.toString() ?? '') ??
            DateTime.now(),
        read: (m['read'] as bool?) ?? false,
      );
}

/// Chat bidirecional cliente ↔ profissional de limpeza. Clone do
/// TvdeChatStore (realtime via .stream(), refcount por reserva, push por
/// trigger no DB, mark_read via RPC SECURITY DEFINER).
class CleaningChatStore extends ChangeNotifier {
  final _sb = Supabase.instance.client;

  final Map<String, List<CleaningMessage>> _messages = {};
  final Map<String, StreamSubscription<List<Map<String, dynamic>>>>
      _subscriptions = {};
  // refcount por reserva: tracking/painel (badge) e o ecrã de chat podem
  // ouvir a MESMA reserva — a subscrição só morre quando ambos saem.
  final Map<String, int> _refCount = {};

  List<CleaningMessage> messagesForBooking(String bookingId) =>
      List.unmodifiable(_messages[bookingId] ?? const <CleaningMessage>[]);

  /// Nº de mensagens por ler recebidas do OUTRO lado.
  int unreadFor(String bookingId, String myRole) {
    final msgs = _messages[bookingId];
    if (msgs == null) return 0;
    var n = 0;
    for (final m in msgs) {
      if (m.senderRole != myRole && !m.read) n++;
    }
    return n;
  }

  /// Última mensagem da conversa (para preview no botão), null se vazia.
  CleaningMessage? lastFor(String bookingId) {
    final msgs = _messages[bookingId];
    if (msgs == null || msgs.isEmpty) return null;
    return msgs.last;
  }

  void listen(String bookingId) {
    _refCount[bookingId] = (_refCount[bookingId] ?? 0) + 1;
    if (_subscriptions.containsKey(bookingId)) return;
    final sub = _sb
        .from('cleaning_messages')
        .stream(primaryKey: ['id'])
        .eq('booking_id', bookingId)
        .order('created_at', ascending: true)
        .listen(
          (rows) {
            _messages[bookingId] = rows.map(CleaningMessage.fromMap).toList();
            notifyListeners();
          },
          onError: (Object e) =>
              debugPrint('[CleaningChatStore] stream($bookingId) ERROR: $e'),
        );
    _subscriptions[bookingId] = sub;
  }

  Future<void> sendMessage({
    required String bookingId,
    required String senderRole,
    required String content,
  }) async {
    final trimmed = content.trim();
    if (trimmed.isEmpty) return;
    try {
      await _sb.from('cleaning_messages').insert({
        'booking_id': bookingId,
        'sender_role': senderRole,
        'message': trimmed,
      });
    } catch (e) {
      debugPrint('[CleaningChatStore] sendMessage ERROR: $e');
      rethrow;
    }
  }

  /// Marca lidas as mensagens do OUTRO lado (RPC — tabela sem policy UPDATE).
  Future<void> markRead(String bookingId, String myRole) async {
    try {
      await _sb.rpc('cleaning_mark_messages_read', params: {
        'p_booking_id': bookingId,
        'p_my_role': myRole,
      });
    } catch (e) {
      debugPrint('[CleaningChatStore] markRead($bookingId) ERROR: $e');
    }
  }

  void unlisten(String bookingId) {
    final n = (_refCount[bookingId] ?? 1) - 1;
    if (n > 0) {
      _refCount[bookingId] = n;
      return;
    }
    _refCount.remove(bookingId);
    _subscriptions.remove(bookingId)?.cancel();
    _messages.remove(bookingId);
  }

  @override
  void dispose() {
    for (final s in _subscriptions.values) {
      s.cancel();
    }
    _subscriptions.clear();
    _refCount.clear();
    super.dispose();
  }
}
