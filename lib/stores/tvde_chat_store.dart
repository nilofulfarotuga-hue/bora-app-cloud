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
    required this.read,
  });

  final String id;
  final String rideId;
  final String senderRole; // 'client' | 'driver'
  final String content;
  final DateTime createdAt;
  final bool read; // [Item I] lida pelo destinatario (coluna tvde_messages.read)

  factory TvdeMessage.fromMap(Map<String, dynamic> m) => TvdeMessage(
        id: m['id'] as String,
        rideId: m['tvde_ride_id'] as String,
        senderRole: m['sender_role'] as String? ?? 'client',
        content: m['message'] as String? ?? '',
        createdAt: DateTime.tryParse(m['created_at']?.toString() ?? '') ??
            DateTime.now(),
        read: (m['read'] as bool?) ?? false,
      );
}

/// Chat bidirecional TVDE — realtime via `.stream()` (mesmo padrão do delivery
/// [ChatStore]), scoped por `tvde_ride_id`. Push é disparado por trigger no DB.
class TvdeChatStore extends ChangeNotifier {
  final _sb = Supabase.instance.client;

  final Map<String, List<TvdeMessage>> _messages = {};
  final Map<String, StreamSubscription<List<Map<String, dynamic>>>>
      _subscriptions = {};
  // [Item I] refcount por corrida: a tela de corrida (para o badge) e o ecra de
  // chat podem ambos ouvir a MESMA corrida — a subscricao so morre quando ambos
  // saem, senao fechar o chat matava o badge da tela de corrida.
  final Map<String, int> _refCount = {};

  List<TvdeMessage> messagesForRide(String rideId) =>
      List.unmodifiable(_messages[rideId] ?? const <TvdeMessage>[]);

  /// [Item I] Nº de mensagens por ler recebidas do OUTRO lado (as que este papel
  /// ainda nao abriu). Usa a coluna tvde_messages.read.
  int unreadFor(String rideId, String myRole) {
    final msgs = _messages[rideId];
    if (msgs == null) return 0;
    var n = 0;
    for (final m in msgs) {
      if (m.senderRole != myRole && !m.read) n++;
    }
    return n;
  }

  void listen(String rideId) {
    _refCount[rideId] = (_refCount[rideId] ?? 0) + 1;
    // Ja a transmitir esta corrida (outro ouvinte) → reusa a subscricao.
    if (_subscriptions.containsKey(rideId)) return;
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

  /// [Item I] Marca como lidas as mensagens recebidas do OUTRO lado (via RPC
  /// SECURITY DEFINER — a tabela nao tem policy de UPDATE). O stream re-emite com
  /// read=true → o badge zera sozinho.
  Future<void> markRead(String rideId, String myRole) async {
    try {
      await _sb.rpc('tvde_mark_messages_read', params: {
        'p_ride_id': rideId,
        'p_my_role': myRole,
      });
    } catch (e) {
      debugPrint('[TvdeChatStore] markRead($rideId) ERROR: $e');
    }
  }

  void unlisten(String rideId) {
    final n = (_refCount[rideId] ?? 1) - 1;
    if (n > 0) {
      _refCount[rideId] = n;
      return;
    }
    _refCount.remove(rideId);
    _subscriptions.remove(rideId)?.cancel();
    _messages.remove(rideId);
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
