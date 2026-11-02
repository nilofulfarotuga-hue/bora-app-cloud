// lib/services/stripe_contas.dart — as DUAS contas Stripe do Bora, do lado da app.
// Missão stripe-empresa-2026-11-01 (autorização do Danilo 01/11/2026 22:03).
//
//   PESSOAL ("bora app")  → TVDE / Bora Motorista e tudo o que já foi pago antes da mudança.
//   EMPRESA ("Bora", Unipessoal Lda) → entregas, Favores, limpeza, lavagem, Casa, marcações,
//                           reservas de mesa, gorjetas de entregas, dívida, peso, extras.
//
// Quem decide a conta é o SERVIDOR (interruptor platform_settings.stripe_conta_nao_tvde): cada
// resposta de criar pagamento traz `stripe_account` e `publishable_key`. Antes de abrir a folha
// do cartão (ou a confirmação de um cartão guardado, ou o checkout web) a app aplica essa chave
// publicável ao SDK da Stripe. Sem chave na resposta (função antiga ou TVDE) fica a do arranque
// (pessoal). Nada muda na aparência nem nos fluxos.
//
// A app diz ao servidor que sabe lidar com duas contas mandando `stripe_contas_v2: true` nos
// pedidos de criar pagamento (apps antigas não mandam e ficam na pessoal).

import 'package:flutter/foundation.dart';
import 'package:flutter_stripe/flutter_stripe.dart';

class StripeContas {
  StripeContas._();

  /// Bandeira que vai em cada pedido de criar pagamento.
  static const String campoBandeira = 'stripe_contas_v2';

  /// Chaves publicáveis compiladas (`.dart_defines`). A da empresa pode faltar em builds antigos.
  static const String chavePessoal = String.fromEnvironment('STRIPE_PUBLISHABLE_KEY');
  static const String chavePessoalTeste =
      String.fromEnvironment('STRIPE_TEST_PUBLISHABLE_KEY');
  static const String chaveEmpresa =
      String.fromEnvironment('STRIPE_PUBLISHABLE_KEY_EMPRESA');
  static const String chaveEmpresaTeste =
      String.fromEnvironment('STRIPE_TEST_PUBLISHABLE_KEY_EMPRESA');
  static const String modo =
      String.fromEnvironment('BORA_STRIPE_MODE', defaultValue: 'live');

  /// A chave aplicada no arranque (main.dart). É o recurso quando o servidor não diz nada.
  static String chaveDeArranque = '';

  /// A última chave efetivamente aplicada ao SDK (para não repetir applySettings).
  static String? _aplicada;

  /// Conta do último pagamento criado (só informação/diagnóstico).
  static String? ultimaConta;

  /// Acrescenta a bandeira a um corpo de pedido (não altera o mapa original).
  static Map<String, dynamic> marcar(Map<String, dynamic> body) =>
      <String, dynamic>{...body, campoBandeira: true};

  /// Chave publicável compilada para uma conta (`'pessoal'` | `'empresa'`).
  static String chavePara(String? conta) {
    const teste = modo == 'test';
    if (conta == 'empresa') {
      const k = teste ? chaveEmpresaTeste : chaveEmpresa;
      // sem chave da empresa compilada: fica a do arranque (o servidor só manda a empresa a
      // apps que sabem lidar com ela, e manda sempre a publishable_key — isto é só recurso)
      return k.isNotEmpty ? k : chaveDeArranque;
    }
    const k = teste ? chavePessoalTeste : chavePessoal;
    return k.isNotEmpty ? k : chaveDeArranque;
  }

  /// A chave que uma resposta do servidor pede: `publishable_key` se vier; senão a compilada
  /// para `stripe_account`; senão null (= chave do arranque).
  static String? chaveDaResposta(Map<String, dynamic>? resposta) {
    if (resposta == null) return null;
    final conta = resposta['stripe_account'];
    if (conta is String && conta.isNotEmpty) ultimaConta = conta;
    final pk = resposta['publishable_key'];
    if (pk is String && pk.startsWith('pk_')) return pk;
    if (conta is String && conta.isNotEmpty) return chavePara(conta);
    return null;
  }

  /// Aplica [publishableKey] ao SDK da Stripe (telemóvel) se for diferente da atual.
  /// null/vazio = volta à chave do arranque. Na web não faz nada (o `pay.html` recebe a chave).
  /// Nunca lança: uma falha a aplicar fica no log e a folha tenta abrir na mesma.
  static Future<void> usarChave(String? publishableKey) async {
    if (kIsWeb) return;
    final alvo = (publishableKey != null && publishableKey.startsWith('pk_'))
        ? publishableKey
        : chaveDeArranque;
    if (alvo.isEmpty) return;
    final atual = _aplicada ?? chaveDeArranque;
    if (alvo == atual) return;
    try {
      Stripe.publishableKey = alvo;
      await Stripe.instance.applySettings();
      _aplicada = alvo;
      debugPrint('[StripeContas] chave publicável aplicada: ${_rotulo(alvo)}');
    } catch (e) {
      debugPrint('[StripeContas] applySettings falhou (segue com a atual): $e');
    }
  }

  /// Rótulo seguro para logs: só o tipo e os últimos 4 caracteres.
  static String _rotulo(String pk) {
    final conta = pk == chaveEmpresa || pk == chaveEmpresaTeste ? 'empresa' : 'pessoal';
    final fim = pk.length > 4 ? pk.substring(pk.length - 4) : pk;
    return '$conta (…$fim)';
  }
}
