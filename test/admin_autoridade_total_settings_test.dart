import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// [Autoridade total no painel · 06/09] Ordem do Danilo: as chaves de dinheiro
/// passam a ser visíveis E editáveis no painel admin, "com autoridade total:
/// ver, editar, auditar".
///
/// **O que já não é problema:** as 49 chaves sem categoria (que por isso nem
/// apareciam no painel) foram todas categorizadas na base — confirmado por
/// SELECT: `count(*) FILTER (WHERE category IS NULL)` = 0, em 248 chaves e 30
/// categorias.
///
/// **O que estes testes guardam** é o lado do Flutter, que era a metade que
/// faltava: a lista branca do ecrã continuava a bloquear tudo o que tem
/// "cents", e o servidor já permitia (a `admin_update_setting` nunca teve
/// lista branca).
///
/// A regra de desenho que se está a trancar aqui: uma chave de dinheiro é
/// editável, mas **nunca pelo diálogo comum** — vai pelo caminho que exige
/// motivo e escreve no `admin_audit_log`. Autoridade total não é o mesmo que
/// mudar dinheiro sem deixar rasto.
void main() {
  final fonte =
      File('lib/screens/admin/admin_platform_settings_screen.dart')
          .readAsStringSync();

  group('as chaves de dinheiro ficaram editáveis', () {
    test('a lista branca reconhece o dinheiro', () {
      expect(fonte, contains('_isMoneyKey'),
          reason: 'sem esta classificação as chaves de dinheiro voltam ao '
              'cadeado');
      expect(RegExp(r'if\s*\(_isMoneyKey\(key\)\)\s*return\s+true')
          .hasMatch(fonte), isTrue,
          reason: 'a lista branca deixou de aceitar as chaves de dinheiro');
    });

    test('as 13 chaves do lote invisível são reconhecidas como dinheiro', () {
      // Estas eram as que tinham ficado com o cadeado depois de ganharem
      // categoria. São o alvo directo da ordem.
      const asTreze = [
        'cancel_fee_after_accept_cents',
        'cancel_fee_after_accept_driver_cents',
        'cancel_fee_after_pickup_ratio',
        'cancel_fee_before_dispatch_cents',
        'max_extra_charge_cents',
        'token_payment_max_pct',
        'token_withdrawal_max_pct_weekly',
        'wallet_cancel_hard_floor_cents',
        'wallet_hard_floor_cents',
        'wallet_max_negative_balance_cents',
        'wallet_negative_action_days',
        'wallet_negative_alert_days',
        'wallet_negative_enabled',
      ];
      for (final k in asTreze) {
        expect(_ehDinheiro(k), isTrue,
            reason: '$k deixou de ser reconhecida como chave de dinheiro e '
                'passaria pelo diálogo comum, sem motivo nem auditoria');
      }
    });

    test('chaves operacionais NÃO são tratadas como dinheiro', () {
      // Se tudo fosse dinheiro, cada afinação de mapa passava a exigir motivo
      // e o painel ficava insuportável de usar.
      for (final k in [
        'tvde_nav_zoom',
        'tvde_driver_stale_seconds',
        'dispatch_offer_timeout_seconds',
        'delivery_max_distance_km',
        'carwash_duration_min',
        'reservation_default_slot_duration_minutes',
      ]) {
        expect(_ehDinheiro(k), isFalse, reason: '$k não mexe em dinheiro');
      }
    });
  });

  group('o dinheiro nunca passa pelo diálogo comum', () {
    test('existe um caminho de edição próprio, auditado', () {
      expect(fonte, contains('_editMoneySetting'));
      expect(fonte, contains('admin_update_money_setting'),
          reason: 'tem de chamar a RPC auditada, não a genérica');
    });

    test('o motivo é obrigatório antes de gravar', () {
      expect(fonte, contains("reasonCtrl.text.trim().length < 3"),
          reason: 'sem motivo não há rasto que sirva para alguma coisa');
    });

    test('o toque encaminha o dinheiro para o caminho auditado', () {
      expect(
        RegExp(r'_isMoneyKey\(s\.key\)\s*\?\s*_editMoneySetting\(s\)')
            .hasMatch(fonte),
        isTrue,
        reason: 'uma chave de dinheiro voltou a abrir o diálogo comum',
      );
    });

    test('o aviso ao Danilo diz que é dinheiro e que fica registado', () {
      expect(fonte, contains('ISTO MEXE EM DINHEIRO'));
      // Painel admin é PT-BR (só o Danilo o usa).
      expect(fonte, contains('registrada'),
          reason: 'o painel admin escreve-se em PT-BR');
    });
  });

  test('a lista deste teste não divergiu da lista do ecrã', () {
    // Sem isto, o teste acima estaria a exercitar uma cópia: alguém apertava o
    // `_isMoneyKey` no ecrã, uma chave de dinheiro caía no diálogo comum, e a
    // bateria continuava verde. Um teste que verifica uma cópia de si próprio
    // não verifica nada.
    final i = fonte.indexOf('bool _isMoneyKey(String key)');
    expect(i, greaterThan(-1), reason: '`_isMoneyKey` mudou de assinatura');
    final corpo = fonte.substring(i, fonte.indexOf('}', i));
    final noEcra = RegExp("'([a-z_]+)'")
        .allMatches(corpo)
        .map((m) => m.group(1)!)
        .toSet();
    const noTeste = {
      'cents', '_ratio', '_pct', 'pct_', 'price', 'fee_', '_fee',
      'wallet', 'token', 'payout', 'reward', 'markup', 'commission',
      'cut_', '_cut', 'share', 'stripe_',
    };
    expect(noEcra, noTeste,
        reason: 'a lista de marcas do ecrã e a deste teste têm de ser a mesma. '
            'No ecrã: $noEcra');
  });
}

/// Espelha o `_isMoneyKey` do ecrã. Se as duas listas divergirem, os testes
/// acima deixam de provar o que dizem provar — por isso o próprio ficheiro é
/// verificado no teste seguinte.
bool _ehDinheiro(String key) {
  const marcas = [
    'cents', '_ratio', '_pct', 'pct_', 'price', 'fee_', '_fee',
    'wallet', 'token', 'payout', 'reward', 'markup', 'commission',
    'cut_', '_cut', 'share', 'stripe_',
  ];
  return marcas.any(key.contains);
}
