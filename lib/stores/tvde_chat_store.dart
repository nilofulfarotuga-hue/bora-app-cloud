import 'dart:async';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Mensagem de chat TVDE (tabela dedicada `tvde_messages`, scoping por corrida).
class TvdeMessage {
  TvdeMessage({
    required this.id,
    required this.rideId,
    required this.senderRole,
    required this.content,
    required this.createdAt,
  });

  final String id;
  final String rideId;
  final String senderRole; // 'client' | 'driver'
  final String content;
  final DateTime createdAt;

  factory TvdeMessage.fromMap(Map<String, dynamic> m) => TvdeMessage(
        id: m['id'] as String,
        rideId: m['tvde_ride_id'] as String,
        senderRole: m['sender_role'] as String? ?? 'client',
        content: m['message'] as String? ?? '',
        createdAt: DateTime.tryParse(m['created_at']?.toString() ?? '') ??
            DateTime.now(),
      );
}

/// Chat bidirecional TVDE — realtime via `.stream()` (mesmo padrão do delivery
/// [ChatStore]), scoped por `tvde_ride_id`. Push é disparado por trigger no DB.
class TvdeChatStore extends ChangeNotifier {
  final _sb = Supabase.instance.client;

  final Map<String, List<TvdeMessage>> _messages = {};
  final Map<String, StreamSubscription<List<Map<String, dynamic>>>>
      _subscriptions = {};

  List<TvdeMessage> messagesForRide(String rideId) =>
      List.unmodifiable(_messages[rideId] ?? const <TvdeMessage>[]);

  void listen(String rideId) {
    _subscriptions.remove(rideId)?.cancel();
    final sub = _sb
        .from('tvde_messages')
        .stream(primaryKey: ['id'])
        .eq('tvde_ride_id', rideId)
        .order('created_at', ascending: true)
        .listen(
          (rows) {
            _messages[rideId] = rows.map(TvdeMessage.fromMap).toList();
            notifyListeners();
          },
          onError: (Object e) =>
              debugPrint('[TvdeChatStore] stream($rideId) ERROR: $e'),
        );
    _subscriptions[rideId] = sub;
  }

  Future<void> sendMessage({
    required String rideId,
    required String senderRole,
    required String content,
  }) async {
    final trimmed = content.trim();
    if (trimmed.isEmpty) return;
    try {
      await _sb.from('tvde_messages').insert({
        'tvde_ride_id': rideId,
        'sender_role': senderRole,
        'message': trimmed,
      });
    } catch (e) {
      debugPrint('[TvdeChatStore] sendMessage ERROR: $e');
      rethrow;
    }
  }

  void unlisten(String rideId) {
    _subscriptions.remove(rideId)?.cancel();
    _messages.remove(rideId);
  }

  @override
  void dispose() {
    for (final s in _subscriptions.values) {
      s.cancel();
    }
    _subscriptions.clear();
    super.dispose();
  }
}
