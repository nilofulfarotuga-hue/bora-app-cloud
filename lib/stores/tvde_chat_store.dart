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
  final bool
      read; // [Item I] lida pelo destinatario (coluna tvde_messages.read)

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

/// Chat bidirecional TVDE, scoped por `tvde_ride_id`.
///
/// O histórico é carregado por SELECT e as alterações chegam por um canal
/// Postgres explícito. Não usamos apenas `.stream()`: uma falha de subscrição
/// não pode deixar uma mensagem já confirmada no servidor invisível no ecrã.
class TvdeChatStore extends ChangeNotifier {
  final _sb = Supabase.instance.client;

  final Map<String, List<TvdeMessage>> _messages = {};
  final Map<String, RealtimeChannel> _channels = {};
  final Map<String, String> _syncErrors = {};
  final Map<String, int> _revisions = {};
  // [Item I] refcount por corrida: a tela de corrida (para o badge) e o ecra de
  // chat podem ambos ouvir a MESMA corrida — a subscricao so morre quando ambos
  // saem, senao fechar o chat matava o badge da tela de corrida.
  final Map<String, int> _refCount = {};

  List<TvdeMessage> messagesForRide(String rideId) =>
      List.unmodifiable(_messages[rideId] ?? const <TvdeMessage>[]);

  String? syncErrorForRide(String rideId) => _syncErrors[rideId];

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
    if (_channels.containsKey(rideId)) return;

    final channel = _sb.channel('tvde_messages_$rideId')
      ..onPostgresChanges(
        event: PostgresChangeEvent.insert,
        schema: 'public',
        table: 'tvde_messages',
        filter: PostgresChangeFilter(
          type: PostgresChangeFilterType.eq,
          column: 'tvde_ride_id',
          value: rideId,
        ),
        callback: (payload) => _upsertFromRealtime(rideId, payload.newRecord),
      )
      ..onPostgresChanges(
        event: PostgresChangeEvent.update,
        schema: 'public',
        table: 'tvde_messages',
        filter: PostgresChangeFilter(
          type: PostgresChangeFilterType.eq,
          column: 'tvde_ride_id',
          value: rideId,
        ),
        callback: (payload) => _upsertFromRealtime(rideId, payload.newRecord),
      )
      ..subscribe((status, [error]) {
        if (status == RealtimeSubscribeStatus.subscribed) {
          _syncErrors.remove(rideId);
          _loadHistory(rideId);
          return;
        }
        if (status == RealtimeSubscribeStatus.channelError ||
            status == RealtimeSubscribeStatus.closed ||
            status == RealtimeSubscribeStatus.timedOut) {
          _syncErrors[rideId] = 'A conversa está a tentar voltar a ligar.';
          debugPrint(
              '[TvdeChatStore] channel($rideId) status=$status error=$error');
          notifyListeners();
        }
      });
    _channels[rideId] = channel;
    _loadHistory(rideId);
  }

  Future<void> sendMessage({
    required String rideId,
    required String senderRole,
    required String content,
  }) async {
    final trimmed = content.trim();
    if (trimmed.isEmpty) return;
    try {
      final raw = await _sb
          .from('tvde_messages')
          .insert({
            'tvde_ride_id': rideId,
            'sender_role': senderRole,
            'message': trimmed,
          })
          .select()
          .single();
      _upsert(rideId, TvdeMessage.fromMap(Map<String, dynamic>.from(raw)));
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
    _channels.remove(rideId)?.unsubscribe();
    _messages.remove(rideId);
    _syncErrors.remove(rideId);
    _revisions.remove(rideId);
  }

  @override
  void dispose() {
    for (final channel in _channels.values) {
      channel.unsubscribe();
    }
    _channels.clear();
    _refCount.clear();
    _syncErrors.clear();
    _revisions.clear();
    super.dispose();
  }

  Future<void> _loadHistory(String rideId) async {
    final revisionBeforeLoad = _revisions[rideId] ?? 0;
    try {
      final rows = await _sb
          .from('tvde_messages')
          .select()
          .eq('tvde_ride_id', rideId)
          .order('created_at', ascending: true);
      if (!_channels.containsKey(rideId)) return;

      final fetched = (rows as List)
          .map((row) => TvdeMessage.fromMap(Map<String, dynamic>.from(row)))
          .toList();
      if ((_revisions[rideId] ?? 0) == revisionBeforeLoad) {
        _messages[rideId] = fetched;
        _revisions[rideId] = revisionBeforeLoad + 1;
      } else {
        for (final message in fetched) {
          _upsert(rideId, message, notify: false);
        }
      }
      _syncErrors.remove(rideId);
      notifyListeners();
    } catch (e) {
      if (!_channels.containsKey(rideId)) return;
      _syncErrors[rideId] = 'Não foi possível atualizar as mensagens.';
      debugPrint('[TvdeChatStore] history($rideId) ERROR: $e');
      notifyListeners();
    }
  }

  void _upsertFromRealtime(String rideId, Map<String, dynamic> raw) {
    if (raw.isEmpty) return;
    _syncErrors.remove(rideId);
    _upsert(rideId, TvdeMessage.fromMap(raw));
  }

  void _upsert(String rideId, TvdeMessage message, {bool notify = true}) {
    final current = [...(_messages[rideId] ?? const <TvdeMessage>[])];
    final index = current.indexWhere((item) => item.id == message.id);
    if (index == -1) {
      current.add(message);
    } else {
      current[index] = message;
    }
    current.sort((a, b) => a.createdAt.compareTo(b.createdAt));
    _messages[rideId] = current;
    _revisions[rideId] = (_revisions[rideId] ?? 0) + 1;
    if (notify) notifyListeners();
  }
}
