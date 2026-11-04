import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'tvde_visibilidade.dart';

/// Avisos do Bora Motorista (TVDE de passageiros) no sininho: `tvde_*`
/// (ex.: `tvde_cancel_comp`, `tvde_goodwill_credit`) e `ride_*`
/// (ex.: `ride_update`).
@visibleForTesting
bool eAvisoDoBoraMotorista(Map<String, dynamic> n) {
  final kind = (n['kind'] as String? ?? '').toLowerCase();
  return kind.startsWith('tvde') || kind.startsWith('ride_');
}

/// 04/11/2026 (fechar-bora-motorista): com `tvde_app_visivel` fechado os
/// avisos de corridas saem da lista (ficam na base, intactos).
List<Map<String, dynamic>> _semBoraMotoristaSeFechado(
    List<Map<String, dynamic>> l) {
  if (TvdeVisibilidade.aberto) return l;
  return [
    for (final n in l)
      if (!eAvisoDoBoraMotorista(n)) n,
  ];
}

/// T2.3 — In-app notifications wrapper.
class InAppNotificationsService {
  InAppNotificationsService._();
  static final instance = InAppNotificationsService._();

  final _supa = Supabase.instance.client;

  Future<int> unreadCount() async {
    try {
      // 04/11/2026: com o Bora Motorista fechado o número do sininho conta
      // só o que a lista mostra (sem os avisos de corridas).
      if (!TvdeVisibilidade.aberto) {
        final l = await listOrThrow();
        return l.where((n) => n['read_at'] == null).length;
      }
      final res = await _supa.rpc('client_unread_notifications_count');
      return (res as num?)?.toInt() ?? 0;
    } catch (e) {
      debugPrint('[InAppNotif] unread error: $e');
      return 0;
    }
  }

  /// Igual a [list] mas deixa passar o erro — para o ecrã mostrar
  /// "Não foi possível carregar" em vez de "Sem notificações" (04/10).
  Future<List<Map<String, dynamic>>> listOrThrow({int limit = 50}) async {
    final res = await _supa
        .rpc('client_list_notifications', params: {'p_limit': limit});
    return _semBoraMotoristaSeFechado(
        (res as List).cast<Map<String, dynamic>>());
  }

  Future<List<Map<String, dynamic>>> list({int limit = 50}) async {
    try {
      final res = await _supa
          .rpc('client_list_notifications', params: {'p_limit': limit});
      return _semBoraMotoristaSeFechado(
          (res as List).cast<Map<String, dynamic>>());
    } catch (e) {
      debugPrint('[InAppNotif] list error: $e');
      return const [];
    }
  }

  Future<void> markRead(String id) async {
    await _supa.rpc('client_mark_notification_read', params: {'p_id': id});
  }

  Future<int> markAllRead() async {
    final res = await _supa.rpc('client_mark_all_notifications_read');
    return (res as num?)?.toInt() ?? 0;
  }
}
