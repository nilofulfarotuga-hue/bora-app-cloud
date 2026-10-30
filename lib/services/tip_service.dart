import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../l10n/tr.dart';
import 'payment_service.dart';

/// Resultado de uma tentativa de gorjeta, já em palavras para o cliente (PT-PT).
class TipResult {
  const TipResult(this.ok, this.mensagem);
  final bool ok;
  final String mensagem;
}

/// GORJETA (missão 03/10 · bloco 3; regra do Danilo de 30/10/2026).
///
/// A regra de 30/10: (1) gorjeta dada no carrinho com cartão/MB Way vai no
/// MESMO pagamento da compra e chega inteira ao estafeta; (2) gorjeta paga
/// depois (avaliação da entrega ou da corrida) com cartão/MB Way é um
/// pagamento à parte e o estafeta/motorista recebe-a MENOS a taxa exata que a
/// Stripe cobrou nesse pagamento (ex.: 2,00 € − 0,28 € = 1,72 €); (3) em
/// dinheiro, inteira; (4) a Bora não ganha nada e, com o pedido cancelado, a
/// gorjeta volta inteira ao cliente.
///
/// Porque existe: até 04/10 nenhuma gorjeta ficou gravada. No checkout a
/// gorjeta só existia no ecrã (a RPC `create_order` nunca a recebia) e no ecrã
/// de avaliação escrevia-se um número no pedido sem cobrar nada.
///
/// Agora: cartão/MB Way → Edge Function `charge-tip` (cobrança separada,
/// PaymentIntent próprio `kind=tip`); dinheiro → RPC `tip_registar_dinheiro`
/// (só no checkout, entregue em mão). Com o interruptor
/// `tips_checkout_junto_pagamento` ligado, a gorjeta do carrinho é marcada no
/// servidor antes do pagamento (`client_preparar_gorjeta_checkout`) e o
/// servidor soma-a ao pagamento da compra. Tudo atrás de
/// `platform_settings.tips_enabled` — desligado, o seletor não aparece.
class TipService {
  TipService._();

  static SupabaseClient get _sb => Supabase.instance.client;

  /// Gorjeta do carrinho no MESMO pagamento da compra (30/10)? Interruptor
  /// `platform_settings.tips_checkout_junto_pagamento`. Em erro (sem rede,
  /// chave ainda por criar) responde que não: fica tudo como antes.
  static Future<bool> juntoDoPagamento({SupabaseClient? cliente}) async {
    try {
      final res = await (cliente ?? _sb)
          .rpc('get_setting', params: {'p_key': 'tips_checkout_junto_pagamento'})
          .timeout(const Duration(seconds: 8));
      return res?.toString() == 'true';
    } catch (e) {
      debugPrint('[TipService] tips_checkout_junto_pagamento => $e');
      return false;
    }
  }

  /// Marca no servidor a gorjeta do próximo pagamento da compra (vale 20 min);
  /// 0 limpa a marcação. Nunca rebenta: devolve se ficou marcada.
  static Future<bool> prepararCheckout(int cents, {SupabaseClient? cliente}) async {
    try {
      final res = await (cliente ?? _sb)
          .rpc('client_preparar_gorjeta_checkout',
              params: {'p_tip_cents': cents < 0 ? 0 : cents})
          .timeout(const Duration(seconds: 8));
      return !(res is Map && res['ok'] == false);
    } catch (e) {
      debugPrint('[TipService] client_preparar_gorjeta_checkout => $e');
      return false;
    }
  }

  /// A gorjeta do carrinho vai junto da compra? Só com o interruptor ligado
  /// ([junto]) e havendo algo a pagar por cartão/MB Way: pedido pago todo com
  /// saldo Bora → a gorjeta continua à parte (charge-tip), como antes.
  static bool vaiJuntoDaCompra({
    required bool junto,
    required double restoAPagarEur,
  }) =>
      junto && restoAPagarEur > 0.005;

  /// Texto por baixo do seletor da gorjeta, no carrinho.
  static String textoDoCarrinho({required bool vaiJunto}) => vaiJunto
      ? 'A gorjeta vai toda para o estafeta.'.tr
      : 'A gorjeta vai toda para o estafeta e é cobrada à parte.'.tr;

  /// Total a mostrar com a gorjeta que vai no mesmo pagamento. Só para o ecrã:
  /// a gorjeta nunca entra no `PricingService` nem na cotação do servidor.
  static double totalComGorjeta(double totalEur, int gorjetaCents) =>
      totalEur > 0 && gorjetaCents > 0 ? totalEur + gorjetaCents / 100 : totalEur;

  /// Antes de abrir o ecrã de pagamento. Interruptor desligado ([junto] =
  /// false) → não chama nada, fica exatamente como antes. Ligado → marca a
  /// gorjeta (ou limpa, com 0, quando não vai junto) e devolve os cêntimos que
  /// ficaram marcados — 0 se a marcação falhou (aí a gorjeta segue à parte,
  /// depois do pedido, como antes; nunca cobrada duas vezes).
  static Future<int> marcarAntesDoPagamento({
    required bool junto,
    required int tipCents,
    required double restoAPagarEur,
    SupabaseClient? cliente,
  }) async {
    if (!junto) return 0;
    final cents =
        vaiJuntoDaCompra(junto: junto, restoAPagarEur: restoAPagarEur) && tipCents > 0
            ? tipCents
            : 0;
    final ok = await prepararCheckout(cents, cliente: cliente);
    return ok ? cents : 0;
  }

  /// A gorjeta está ligada? Em erro, responde que não (não se mostra o que
  /// não se consegue cobrar).
  static Future<bool> ligada() async {
    try {
      final res = await _sb
          .rpc('get_setting', params: {'p_key': 'tips_enabled'})
          .timeout(const Duration(seconds: 8));
      return res?.toString() == 'true';
    } catch (e) {
      debugPrint('[TipService] tips_enabled => $e');
      return false;
    }
  }

  /// Gorjeta em dinheiro, no checkout: fica registada e o cliente entrega-a em
  /// mão com o pedido.
  static Future<TipResult> registarDinheiro(String orderId, int cents) async {
    try {
      final res = await _sb.rpc('tip_registar_dinheiro',
          params: {'p_order_id': orderId, 'p_amount_cents': cents});
      final m = Map<String, dynamic>.from(res as Map);
      if (m['ok'] == true) {
        return TipResult(true,
            'Gorjeta de ${_eur(cents)} registada — entrega-a ao estafeta com o pagamento.');
      }
      return TipResult(false, _motivo(m['motivo']?.toString()));
    } catch (e) {
      debugPrint('[TipService] registarDinheiro => $e');
      return const TipResult(false, 'A gorjeta não ficou registada. Não foi cobrado nada.');
    }
  }

  /// Gorjeta por cartão ou MB Way, cobrada à parte.
  /// [target] = 'order' ou 'tvde'; [moment] = 'checkout' ou 'after'.
  /// Com a gorjeta do carrinho já paga junto da compra (30/10), o servidor
  /// responde `note: 'already_exists'` e não cobra nada.
  static Future<TipResult> cobrar({
    required String target,
    required String id,
    required int cents,
    required String moment,
    SupabaseClient? cliente,
  }) async {
    try {
      final r = await (cliente ?? _sb).functions.invoke('charge-tip', body: {
        'action': 'create',
        'target': target,
        'id': id,
        'amountCents': cents,
        'moment': moment,
      });
      final m = Map<String, dynamic>.from(r.data as Map);
      if (m['error'] != null) return TipResult(false, _motivo(m['error'].toString()));
      if (m['note'] == 'already_exists') {
        return TipResult(true,
            'Gorjeta de ${_eur(cents)} incluída no pagamento do pedido. Obrigado!');
      }
      final tipId = m['tipId'] as String;
      var status = m['status']?.toString() ?? 'pending';

      if (status != 'succeeded' && m['method'] == 'card' && m['clientSecret'] != null) {
        // Cartão sem cartão reutilizável, ou o banco pediu confirmação: folha da Stripe.
        await PaymentService().processPayment(
          m['clientSecret'] as String,
          vertical: 'gorjeta',
          referenciaId: tipId,
          paymentIntentId: m['paymentIntentId'] as String?,
        );
        status = await _confirmar(tipId, cliente);
      } else if (status != 'succeeded' && m['method'] == 'mbway') {
        // MB Way: o cliente aprova na app do banco — perguntamos até 90 s.
        for (var i = 0; i < 30 && status != 'succeeded' && status != 'failed'; i++) {
          await Future<void>.delayed(const Duration(seconds: 3));
          status = await _confirmar(tipId, cliente);
        }
      }

      if (status == 'succeeded') {
        return TipResult(true, 'Gorjeta de ${_eur(cents)} enviada. Obrigado!');
      }
      if (m['method'] == 'mbway' && status != 'failed') {
        return const TipResult(false,
            'Ainda não recebemos a confirmação do MB WAY. Se aprovares, a gorjeta segue na mesma.');
      }
      return const TipResult(false, 'A gorjeta não foi cobrada. Não pagaste nada a mais.');
    } on FunctionException catch (e) {
      debugPrint('[TipService] cobrar FunctionException => ${e.status} ${e.details}');
      final d = e.details;
      final code = d is Map ? d['error']?.toString() : null;
      return TipResult(false, _motivo(code));
    } catch (e) {
      debugPrint('[TipService] cobrar => $e');
      return const TipResult(false, 'A gorjeta não foi cobrada. Não pagaste nada a mais.');
    }
  }

  static Future<String> _confirmar(String tipId, [SupabaseClient? cliente]) async {
    try {
      final r = await (cliente ?? _sb).functions
          .invoke('charge-tip', body: {'action': 'confirm', 'tipId': tipId});
      return (r.data as Map)['status']?.toString() ?? 'pending';
    } catch (e) {
      debugPrint('[TipService] confirm => $e');
      return 'pending';
    }
  }

  static String _eur(int cents) =>
      '${(cents / 100).toStringAsFixed(2).replaceAll('.', ',')} €';

  static String _motivo(String? code) {
    switch (code) {
      case 'already_tipped':
      case 'ja_tem_gorjeta':
        return 'Já deste gorjeta neste pedido. Obrigado!';
      case 'amount_invalid':
      case 'valor_invalido':
        return 'Escolhe uma gorjeta entre 0,50 € e 50 €.';
      case 'passa_limite_dinheiro':
        return 'Com a gorjeta passa o limite de pagamento em dinheiro. Dá-a em mão ao estafeta.';
      case 'tips_disabled':
      case 'gorjetas_desligadas':
        return 'As gorjetas estão indisponíveis de momento.';
      default:
        return 'A gorjeta não foi cobrada. Não pagaste nada a mais.';
    }
  }
}
