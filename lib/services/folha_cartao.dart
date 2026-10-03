// Folha do cartão (Stripe PaymentSheet) — porta única no telemóvel.
//
// 2026-10-03 — o cartão no iPhone ficava só a rodar (Divan 02/10, Danilo
// 21/09; nenhum cartão de iPhone tinha passado). Causa: com UIScene o plugin
// do Stripe não encontrava a janela e a folha era apresentada "no vazio" — o
// `presentPaymentSheet()` nunca devolvia. O conserto nativo está em
// `ios/Runner/AppDelegate.swift`; isto é a rede de segurança para nunca mais
// rodar em silêncio:
//
//   1. no iOS pede à parte nativa para ligar a janela antes de abrir;
//   2. `initPaymentSheet` tem tempo limite
//      (`platform_settings.payment_sheet_timeout_seconds`, 20 s por defeito);
//   3. no iOS confirma que a folha apareceu mesmo dentro desse tempo — se não
//      aparecer, desiste com uma mensagem clara (MB Way / dinheiro);
//   4. qualquer falha (não o cancelamento do cliente) vai para
//      `payment_client_failures` via `log_payment_failure`, que avisa o Danilo
//      no Telegram e aparece no painel em "Pagamentos presos".
//
// O tempo limite só conta até a folha APARECER. Depois de aberta, o cliente
// tem o tempo que precisar para escrever o cartão ou passar o 3D Secure.
//
// Os erros saem como `StripeException` com `FailureCode.Failed`, para os
// `on StripeException` que já existem em cada fluxo os tratarem como falha
// (e não como cancelamento) sem mudar mais nada.

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_stripe/flutter_stripe.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'platform_tag_service.dart';

/// Mensagem mostrada ao cliente quando o ecrã do cartão não abre.
const String kMensagemFolhaCartaoNaoAbriu =
    'O ecrã do cartão não abriu. Não foi cobrado nada — tenta de novo ou '
    'escolhe MB Way ou dinheiro.';

const MethodChannel _canalNativo = MethodChannel('pt.boraapp.bora/native');

const int _tempoLimitePorDefeito = 20;
int? _tempoLimiteEmCache;

bool get _ehIos => !kIsWeb && defaultTargetPlatform == TargetPlatform.iOS;

/// Lê `payment_sheet_timeout_seconds` (cache por sessão). Nunca falha: sem
/// rede ou sem a chave, usa 20 s.
Future<int> tempoLimiteFolhaCartao() async {
  final emCache = _tempoLimiteEmCache;
  if (emCache != null) return emCache;
  var segundos = _tempoLimitePorDefeito;
  try {
    final linha = await Supabase.instance.client
        .from('platform_settings')
        .select('value')
        .eq('key', 'payment_sheet_timeout_seconds')
        .maybeSingle()
        .timeout(const Duration(seconds: 5));
    final v = linha?['value'];
    final lido = v is num ? v.toInt() : int.tryParse('$v');
    if (lido != null && lido >= 5 && lido <= 120) segundos = lido;
  } catch (e) {
    debugPrint('[FolhaCartao] tempo limite ilegível ($e) — a usar $segundos s');
  }
  _tempoLimiteEmCache = segundos;
  return segundos;
}

/// Grava a falha no servidor (tabela de falhas + Telegram do Danilo).
/// Fire-and-forget: gravar nunca pode partir o fluxo do cliente.
void registarFalhaPagamento({
  required String vertical,
  required String fase,
  required String erro,
  String? referenciaId,
  String? clientSecret,
}) {
  unawaited(() async {
    try {
      String? versao;
      try {
        final diag = await _canalNativo
            .invokeMapMethod<String, String>('getDeviceDiagnostics')
            .timeout(const Duration(seconds: 2));
        versao = diag?['app_version'];
      } catch (_) {/* sem diagnóstico — segue sem versão */}
      await Supabase.instance.client.rpc('log_payment_failure', params: {
        'p_vertical': vertical,
        'p_referencia_id': referenciaId,
        'p_payment_intent_id': clientSecret?.split('_secret_').first,
        'p_platform': PlatformTagService.plataformaActual,
        'p_app_version': versao,
        'p_stage': fase,
        'p_error_message': erro,
      });
    } catch (e) {
      debugPrint('[FolhaCartao] não consegui gravar a falha: $e');
    }
  }());
}

StripeException _falha(String detalhe) => StripeException(
      error: LocalizedErrorMessage(
        code: FailureCode.Failed,
        localizedMessage: kMensagemFolhaCartaoNaoAbriu,
        message: detalhe,
      ),
    );

/// Abre a folha do cartão e espera pelo resultado.
///
/// Completa em sucesso; lança `StripeException` em cancelamento (código
/// `Canceled`), recusa ou quando a folha não abre (código `Failed`).
Future<void> apresentarFolhaCartao(
  SetupPaymentSheetParameters parametros, {
  required String vertical,
  String? referenciaId,
}) async {
  final segredo = parametros.paymentIntentClientSecret;
  final limite = Duration(seconds: await tempoLimiteFolhaCartao());

  // 1) iOS: ligar a janela do Flutter ao Stripe.
  if (_ehIos) {
    bool? pronta;
    try {
      pronta = await _canalNativo
          .invokeMethod<bool>('prepararFolhaStripe')
          .timeout(const Duration(seconds: 3));
    } catch (e) {
      // Build antigo sem o método nativo — segue e deixa o vigia decidir.
      debugPrint('[FolhaCartao] prepararFolhaStripe indisponível: $e');
    }
    if (pronta == false) {
      const detalhe = 'iOS sem janela para apresentar a folha do Stripe';
      registarFalhaPagamento(
          vertical: vertical,
          fase: 'janela',
          erro: detalhe,
          referenciaId: referenciaId,
          clientSecret: segredo);
      throw _falha(detalhe);
    }
  }

  // 2) Preparar a folha, com tempo limite.
  try {
    await Stripe.instance
        .initPaymentSheet(paymentSheetParameters: parametros)
        .timeout(limite);
  } on TimeoutException {
    final detalhe = 'initPaymentSheet sem resposta em ${limite.inSeconds}s';
    registarFalhaPagamento(
        vertical: vertical,
        fase: 'preparar',
        erro: detalhe,
        referenciaId: referenciaId,
        clientSecret: segredo);
    throw _falha(detalhe);
  } on StripeException catch (e) {
    registarFalhaPagamento(
        vertical: vertical,
        fase: 'preparar',
        erro: '${e.error.code.name}: ${e.error.message ?? e.error.localizedMessage}',
        referenciaId: referenciaId,
        clientSecret: segredo);
    rethrow;
  }

  // 3) Abrir. No iOS confirma-se que a folha apareceu mesmo.
  final resultado = Completer<void>();
  Stripe.instance.presentPaymentSheet().then(
        (_) { if (!resultado.isCompleted) resultado.complete(); },
        onError: (Object e, StackTrace s) {
          if (!resultado.isCompleted) resultado.completeError(e, s);
        },
      );

  if (_ehIos) {
    final fim = DateTime.now().add(limite);
    var apareceu = false;
    while (!resultado.isCompleted && DateTime.now().isBefore(fim)) {
      await Future.any([
        resultado.future.then((_) {}, onError: (_) {}),
        Future<void>.delayed(const Duration(milliseconds: 500)),
      ]);
      if (resultado.isCompleted) break;
      try {
        apareceu = await _canalNativo.invokeMethod<bool>('folhaStripeVisivel') ?? false;
      } catch (_) {
        // Build antigo sem o método: não dá para confirmar — não se inventa
        // falha, espera-se pelo resultado como antes.
        apareceu = true;
      }
      if (apareceu) break;
    }
    if (!resultado.isCompleted && !apareceu) {
      final detalhe =
          'A folha do Stripe não apareceu em ${limite.inSeconds}s (iOS)';
      registarFalhaPagamento(
          vertical: vertical,
          fase: 'apresentar',
          erro: detalhe,
          referenciaId: referenciaId,
          clientSecret: segredo);
      throw _falha(detalhe);
    }
  }

  try {
    await resultado.future;
  } on StripeException catch (e) {
    if (e.error.code != FailureCode.Canceled) {
      registarFalhaPagamento(
          vertical: vertical,
          fase: 'pagar',
          erro:
              '${e.error.code.name}: ${e.error.declineCode ?? ''} ${e.error.message ?? e.error.localizedMessage}',
          referenciaId: referenciaId,
          clientSecret: segredo);
    }
    rethrow;
  }
}
