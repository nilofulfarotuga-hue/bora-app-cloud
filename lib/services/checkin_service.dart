// lib/services/checkin_service.dart
//
// Check-in diário (Bora Todo Dia, novidade n.º 1 — 13/10/2026).
// Ciclo de 7 dias com prémios fixos em tokens; falhar um dia volta ao Dia 1.
// As regras e os valores vivem no servidor (`platform_settings.checkin_*`):
//  - `client_checkin_status()` → estado de hoje (só leitura);
//  - `client_daily_checkin()`  → grava o check-in e credita os tokens do dia.
// Se o servidor ainda não tiver as funções (ou o check-in estiver desligado),
// `estado()` devolve `null` e o cartão não aparece.
import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class CheckinEstado {
  const CheckinEstado({
    required this.enabled,
    required this.eligible,
    required this.reason,
    required this.alreadyDone,
    required this.streakDay,
    required this.tokensToday,
    required this.nextDay,
    required this.nextReward,
    required this.rewards,
    this.tokensAwarded,
    this.balance,
  });

  final bool enabled;
  final bool eligible;

  /// `null` quando pode fazer check-in; senão 'desligado' | 'nao_cliente' |
  /// 'sem_telemovel' | 'sem_sessao'.
  final String? reason;

  /// Já fez o check-in de hoje (dia de calendário em Lisboa).
  final bool alreadyDone;

  /// Dia do ciclo (1..7) de hoje — feito ou por fazer.
  final int streakDay;

  /// Tokens de hoje: ganhos (se já fez) ou a ganhar.
  final int tokensToday;
  final int nextDay;
  final int nextReward;

  /// Os 7 prémios do ciclo, Dia 1 a Dia 7.
  final List<int> rewards;

  /// Só na resposta do check-in: tokens dados agora (0 num toque repetido).
  final int? tokensAwarded;

  /// Só na resposta do check-in: saldo de tokens depois do crédito.
  final int? balance;

  bool get semTelemovel => reason == 'sem_telemovel';

  /// O cartão mostra-se a quem pode fazer check-in e a quem só falta o telemóvel.
  bool get mostrarCartao => enabled && (eligible || semTelemovel);

  static int _int(dynamic v, [int d = 0]) =>
      v is num ? v.toInt() : int.tryParse('${v ?? ''}') ?? d;

  factory CheckinEstado.fromJson(Map<String, dynamic> m) {
    final premios = (m['rewards'] is List)
        ? (m['rewards'] as List).map((e) => _int(e)).toList()
        : const <int>[];
    // Na resposta de client_daily_checkin, 'already_done' quer dizer "já tinha
    // feito antes deste toque" (e então tokens_awarded = 0). Para o cartão, uma
    // resposta ok do check-in quer sempre dizer: o de hoje está feito.
    final respostaDoCheckin = m['ok'] == true && m.containsKey('tokens_awarded');
    return CheckinEstado(
      enabled: m['enabled'] == true,
      eligible: m['eligible'] == true,
      reason: m['reason'] as String?,
      alreadyDone: respostaDoCheckin || m['already_done'] == true,
      streakDay: _int(m['streak_day'], 1).clamp(1, 7),
      tokensToday: _int(m['tokens_today']),
      nextDay: _int(m['next_day'], 1).clamp(1, 7),
      nextReward: _int(m['next_reward']),
      rewards: premios.length == 7 ? premios : const [5, 5, 10, 10, 15, 15, 40],
      tokensAwarded: m.containsKey('tokens_awarded') ? _int(m['tokens_awarded']) : null,
      balance: m['balance'] == null ? null : _int(m['balance']),
    );
  }
}

class CheckinService {
  CheckinService._();
  static final CheckinService instance = CheckinService._();

  static const Duration _limite = Duration(seconds: 15);

  /// Estado de hoje, ou `null` se o servidor não o der (função em falta,
  /// sem rede, sem sessão). Nunca rebenta: quem chama esconde o cartão.
  Future<CheckinEstado?> estado() async {
    try {
      final res = await Supabase.instance.client
          .rpc('client_checkin_status')
          .timeout(_limite);
      if (res is! Map) return null;
      return CheckinEstado.fromJson(res.cast<String, dynamic>());
    } catch (e) {
      debugPrint('[CheckinService] estado: $e');
      return null;
    }
  }

  /// Faz o check-in de hoje. Lança se o servidor falhar — o cartão mostra o
  /// erro e deixa tentar de novo.
  Future<CheckinEstado> fazerCheckin() async {
    final res = await Supabase.instance.client
        .rpc('client_daily_checkin')
        .timeout(_limite);
    if (res is! Map) throw StateError('resposta_invalida');
    return CheckinEstado.fromJson(res.cast<String, dynamic>());
  }
}
