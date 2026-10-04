import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'payment_service.dart';

/// Resultado de uma tentativa de gorjeta, já em palavras para o cliente (PT-PT).
class TipResult {
  const TipResult(this.ok, this.mensagem);
  final bool ok;
  final String mensagem;
}

/// GORJETA (missão 03/10 · bloco 3) — 100% para o estafeta/motorista.
///
/// Porque existe: até 04/10 nenhuma gorjeta ficou gravada. No checkout a
/// gorjeta só existia no ecrã (a RPC `create_order` nunca a recebia) e no ecrã
/// de avaliação escrevia-se um número no pedido sem cobrar nada.
///
/// Agora: cartão/MB Way → Edge Function `charge-tip` (cobrança separada,
/// PaymentIntent próprio `kind=tip`); dinheiro → RPC `tip_registar_dinheiro`
/// (só no checkout, entregue em mão). Tudo atrás de
/// `platform_settings.tips_enabled` — desligado, o seletor não aparece.
class TipService {
  TipService._();

  static SupabaseClient get _sb => Supabase.instance.client;

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
  static Future<TipResult> cobrar({
    required String target,
    required String id,
    required int cents,
    required String moment,
  }) async {
    try {
      final r = await _sb.functions.invoke('charge-tip', body: {
        'action': 'create',
        'target': target,
        'id': id,
        'amountCents': cents,
        'moment': moment,
      });
      final m = Map<String, dynamic>.from(r.data as Map);
      if (m['error'] != null) return TipResult(false, _motivo(m['error'].toString()));
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
        status = await _confirmar(tipId);
      } else if (status != 'succeeded' && m['method'] == 'mbway') {
        // MB Way: o cliente aprova na app do banco — perguntamos até 90 s.
        for (var i = 0; i < 30 && status != 'succeeded' && status != 'failed'; i++) {
          await Future<void>.delayed(const Duration(seconds: 3));
          status = await _confirmar(tipId);
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

  static Future<String> _confirmar(String tipId) async {
    try {
      final r = await _sb.functions
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
