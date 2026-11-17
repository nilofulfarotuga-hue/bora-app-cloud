// Cartão e MB Way na receita da farmácia (missão receita-cartao-mbway-17-11).
//
// Não há código de pagamento novo: usa os mesmos caminhos do Favor.
//   • Cartão  → o SERVIDOR monta o pedido (prescricao_preparar_pedido) e a app segue o
//               payment-first de sempre: create-payment-intent cria o rascunho (payment_drafts),
//               a folha do cartão cobra, e o pedido só nasce no finalize-order-from-intent depois
//               de pago. Nunca há cobrança sem pedido.
//   • MB Way  → o servidor cria o pedido à espera de pagamento; a app pede o MB Way
//               (create-mbway-payment-intent) e espera como no checkout. Toque duplo devolve o
//               mesmo pedido.
// A receita liga-se ao pedido no servidor (gatilho _prescricao_liga_pedido_pago) quando o
// pagamento entra; o ecrã vê isso pelo tempo real de pedidos_prescricao.
import 'package:flutter/foundation.dart';
import 'package:flutter_stripe/flutter_stripe.dart' show StripeException, FailureCode;
import 'package:supabase_flutter/supabase_flutter.dart';

import '../utils/mensagem_mbway.dart';
import 'payment_service.dart';
import 'prescricao_service.dart';
import 'stripe_contas.dart';

enum ResultadoCartaoReceita { pago, cancelado }

/// O que o servidor devolveu para o MB Way.
class MbwayReceitaPreparado {
  final String orderId;
  final int totalCents;

  /// O que o MB Way pede (com a margem do Favor até ao talão).
  final int cobrarCents;
  final bool jaPago;
  const MbwayReceitaPreparado({
    required this.orderId,
    required this.totalCents,
    required this.cobrarCents,
    required this.jaPago,
  });
}

class PrescricaoPagamentoService {
  PrescricaoPagamentoService({PrescricaoService? prescricoes, PaymentService? pagamentos, SupabaseClient? client})
      : _prescricoes = prescricoes ?? PrescricaoService(client: client),
        _pagamentos = pagamentos ?? PaymentService(),
        _sbOverride = client;

  final PrescricaoService _prescricoes;
  final PaymentService _pagamentos;
  final SupabaseClient? _sbOverride;
  SupabaseClient get _sb => _sbOverride ?? Supabase.instance.client;

  /// Cartão: prepara no servidor, abre a folha do cartão e devolve quando o cartão aceitou.
  /// O pedido nasce no servidor logo a seguir (o ecrã vê a receita passar a "confirmado").
  /// Lança [PrescricaoErro] com a frase para o cliente.
  Future<ResultadoCartaoReceita> pagarComCartao(String prescricaoId, {bool soDisponiveis = true}) async {
    final prep = await _prescricoes.prepararPagamento(prescricaoId, metodo: 'card', soDisponiveis: soDisponiveis);
    final cartInput = prep['cart_input'];
    if (cartInput is! Map) {
      throw PrescricaoErro('Não foi possível preparar o pagamento. Tente outra vez.');
    }
    Map<String, dynamic>? rascunho;
    try {
      final resp = await _sb.functions.invoke(
        'create-payment-intent',
        body: {'cart_input': Map<String, dynamic>.from(cartInput), StripeContas.campoBandeira: true},
      );
      rascunho = resp.data is Map ? Map<String, dynamic>.from(resp.data as Map) : null;
    } catch (e) {
      debugPrint('[receita-pagar] create-payment-intent falhou: $e');
      throw PrescricaoErro('Não foi possível iniciar o pagamento com cartão. Verifique a internet e tente outra vez.');
    }
    final clientSecret = rascunho?['clientSecret'] as String?;
    final draftId = rascunho?['draftId'] as String?;
    if (clientSecret == null || draftId == null) {
      debugPrint('[receita-pagar] resposta incompleta: $rascunho');
      throw PrescricaoErro('Não foi possível iniciar o pagamento com cartão. Tente outra vez ou escolha MB Way.');
    }
    try {
      await _pagamentos.processPayment(
        clientSecret,
        vertical: 'pedido',
        referenciaId: draftId,
        publishableKey: StripeContas.chaveDaResposta(rascunho),
      );
    } on StripeException catch (e) {
      // Sem pedido para limpar: o rascunho expira sozinho (payment-first). Marca-se a desistência
      // para o dinheiro e o cancelar não ficarem à espera deste cartão.
      await _prescricoes.desistirDoCartao(prescricaoId);
      if (e.error.code == FailureCode.Canceled) return ResultadoCartaoReceita.cancelado;
      throw PrescricaoErro(e.error.localizedMessage ?? 'Pagamento recusado. Tente outra vez ou escolha MB Way.');
    } catch (e) {
      debugPrint('[receita-pagar] folha do cartão: $e');
      await _prescricoes.desistirDoCartao(prescricaoId);
      throw PrescricaoErro('Pagamento com cartão indisponível. Tente MB Way ou dinheiro.');
    }
    return ResultadoCartaoReceita.pago;
  }

  /// MB Way, passo 1: o servidor cria (ou devolve) o pedido à espera de pagamento.
  Future<MbwayReceitaPreparado> prepararMbway(String prescricaoId, {bool soDisponiveis = true}) async {
    final prep = await _prescricoes.prepararPagamento(prescricaoId, metodo: 'mbway', soDisponiveis: soDisponiveis);
    final orderId = prep['order_id']?.toString();
    if (orderId == null || orderId.isEmpty) {
      throw PrescricaoErro('Não foi possível preparar o pagamento MB Way. Tente outra vez.');
    }
    final total = (prep['total_cents'] as num?)?.toInt() ?? 0;
    return MbwayReceitaPreparado(
      orderId: orderId,
      totalCents: total,
      cobrarCents: (prep['cobrar_cents'] as num?)?.toInt() ?? total,
      jaPago: prep['payment_status'] == 'paid',
    );
  }

  /// MB Way, passo 2: pede o pagamento à app MB WAY (a mesma Edge Function do checkout).
  /// Devolve null quando o pedido foi enviado; senão a frase do erro.
  /// [jaTratado] = o servidor diz que esse pagamento já foi tratado (pode estar pago).
  Future<({String? erro, bool jaTratado})> pedirMbway(String orderId, String telefone) async {
    final pi = await _pagamentos.initiateMbwayPayment(
      orderId: orderId,
      phone: telefone.replaceAll(RegExp(r'\D'), ''),
    );
    if (pi != null) return (erro: null, jaTratado: false);
    return (
      erro: _pagamentos.ultimoErroMbway ?? mensagemErroMbway(),
      jaTratado: _pagamentos.ultimoMbwayJaTratado,
    );
  }

  /// MB Way que não entrou: cancela o pedido sem custo (o mesmo caminho do checkout).
  /// [CancelarMbway.jaPago] = o servidor recusou cancelar porque o pagamento JÁ entrou;
  /// [CancelarMbway.falhou] = sem rede/erro: o pedido pode continuar à espera do MB Way.
  Future<CancelarMbway> cancelarMbwayNaoPago(String orderId) async {
    try {
      await _sb.functions.invoke('client-cancel-order', body: {'order_id': orderId, 'reason': 'payment_failed'});
      return CancelarMbway.cancelado;
    } on FunctionException catch (e) {
      final d = e.details;
      final erro = d is Map ? d['error']?.toString() : d?.toString();
      if (cancelamentoRecusadoPorPagamento(e.status, erro)) return CancelarMbway.jaPago;
      debugPrint('[receita-pagar] cancelar MB Way: $e');
      return CancelarMbway.falhou;
    } catch (e) {
      debugPrint('[receita-pagar] cancelar MB Way: $e');
      return CancelarMbway.falhou;
    }
  }
}

enum CancelarMbway { cancelado, jaPago, falhou }
