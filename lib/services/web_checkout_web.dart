/// Lado web do `web_checkout`.
///
/// Dois caminhos, escolhidos pelo browser e nunca pelo optimismo:
///
/// 1. **Janela nova** (só em computador). Abre `pay.html` numa janela pequena,
///    o Stripe.js trata do cartão e a app Flutter fica viva o tempo todo — o
///    código que corre **depois** do pagamento é o mesmo do telemóvel.
/// 2. **Mesmo separador** (telemóvel, ou janela bloqueada). Guarda o estado em
///    `localStorage`, navega para o `pay.html` e a app retoma no arranque
///    seguinte (ver `lerPagamentoWebPendente`).
///
/// ## A cicatriz (22/09/2026, cliente Priscila Prates)
///
/// Cliente nova, iPhone, Safari, pediu uma corrida às 13:34 e nunca lhe
/// apareceu onde pôr o cartão: "não deu opção, ficou a rodar". A corrida morreu
/// 2m22s depois em `payment_failed` sem nenhum motorista chamado.
///
/// O Safari do iPhone bloqueia o `window.open` que não venha colado a um toque
/// — e aqui não vinha (entre o toque e o open há a biometria e a chamada à Edge
/// Function). A versão anterior deste ficheiro fazia:
///
/// ```dart
/// try { blocked = popup.closed ?? true; }
/// catch (_) { blocked = false; }   // ← "cross-origin = está viva"
/// ```
///
/// Com a janela bloqueada, `popup` é `null`, `popup.closed` **atira**, e o
/// `catch` concluía que estava viva. A app ficava à espera para sempre de uma
/// janela que nunca existiu. O watchdog de 700 ms tinha o mesmo `catch` e fazia
/// o mesmo. Por isso agora:
///
/// - em telemóvel **nem se tenta** o popup;
/// - `null` ou excepção à primeira leitura = **BLOQUEADA**, nunca "viva";
/// - só se assume viva depois de o `pay.html` dizer `pronto` (≤ 1,5 s);
/// - há tecto de espera em todos os caminhos — nunca mais um rodar infinito.
///
/// Usa `dart:html` por coerência com os ficheiros web que já existem no repo
/// (`place_autocomplete_service_web.dart`, `directions_service_web.dart`).
library;

import 'dart:async';
import 'dart:convert';
// ignore: avoid_web_libraries_in_flutter, deprecated_member_use
import 'dart:html' as html;

import 'package:flutter/foundation.dart';

import 'web_checkout_regras.dart';

/// Lançada quando o utilizador fecha a janela sem pagar.
class WebCheckoutCancelled implements Exception {
  const WebCheckoutCancelled();

  @override
  String toString() => 'Pagamento cancelado.';
}

/// Lançada quando o Stripe recusa o pagamento — ou quando a página de
/// pagamento deixa de dar sinal de vida.
class WebCheckoutFailed implements Exception {
  const WebCheckoutFailed(this.message);

  final String message;

  @override
  String toString() => message;
}

/// Chave do estado guardado quando se sai da app pelo mesmo separador.
const String _chavePendente = 'bora.pagamento_pendente';

/// Um pagamento pendente só vale enquanto a corrida/pedido ainda pode viver.
/// Passado isto o cron já limpou; retomar seria mentir ao cliente.
const Duration _validadeDoPendente = Duration(minutes: 30);

/// Pagamento que saiu da app pelo mesmo separador e ainda não foi fechado.
class PagamentoWebPendente {
  const PagamentoWebPendente({
    required this.vertical,
    required this.clientSecret,
    required this.rotaRegresso,
    required this.criadoEm,
    this.referenciaId,
    this.paymentIntentId,
  });

  /// `tvde` | `entrega` | `limpeza` | `lavagem` | `reserva` | `marcacao` |
  /// `divida` | `plano` — serve para o ecrã de retoma saber a quem perguntar.
  final String vertical;
  final String clientSecret;

  /// Endereço completo de onde a app saiu. É para aqui que o `pay.html` volta
  /// — nunca para a raiz do site.
  final String rotaRegresso;
  final DateTime criadoEm;

  /// Id da corrida/pedido, quando o chamador o sabe.
  final String? referenciaId;
  final String? paymentIntentId;

  bool get expirado => DateTime.now().difference(criadoEm) > _validadeDoPendente;

  static PagamentoWebPendente? _deJson(String bruto) {
    try {
      final m = jsonDecode(bruto) as Map<String, dynamic>;
      final cs = m['clientSecret'] as String?;
      if (cs == null || cs.isEmpty) return null;
      return PagamentoWebPendente(
        vertical: (m['vertical'] as String?) ?? 'desconhecida',
        clientSecret: cs,
        rotaRegresso: (m['rotaRegresso'] as String?) ?? '/',
        criadoEm:
            DateTime.tryParse((m['criadoEm'] as String?) ?? '') ?? DateTime.now(),
        referenciaId: m['referenciaId'] as String?,
        paymentIntentId: m['paymentIntentId'] as String?,
      );
    } catch (e) {
      debugPrint('[WebCheckout] pendente ilegível: $e');
      return null;
    }
  }
}

/// Lê o pagamento que ficou a meio, se houver. Devolve `null` quando não há
/// nenhum, quando está ilegível ou quando já passou da validade (e nesse caso
/// limpa-o, para não ficar a apodrecer no browser do cliente).
PagamentoWebPendente? lerPagamentoWebPendente() {
  try {
    final bruto = html.window.localStorage[_chavePendente];
    if (bruto == null || bruto.isEmpty) return null;
    final p = PagamentoWebPendente._deJson(bruto);
    if (p == null || p.expirado) {
      limparPagamentoWebPendente();
      return null;
    }
    return p;
  } catch (e) {
    debugPrint('[WebCheckout] não consegui ler o pendente: $e');
    return null;
  }
}

/// Apaga o estado pendente. Chamado sempre que a retoma fecha — paga ou não.
void limparPagamentoWebPendente() {
  try {
    html.window.localStorage.remove(_chavePendente);
  } catch (e) {
    debugPrint('[WebCheckout] não consegui limpar o pendente: $e');
  }
}

/// Browser de telemóvel? Aqui **nunca** se tenta a janela nova: o Safari do
/// iPhone bloqueia-a e o Chrome de Android abre um separador que o cliente não
/// percebe que tem de fechar.
bool _ehBrowserDeTelemovel() {
  try {
    final ua = html.window.navigator.userAgent;
    if (RegExp(r'iPhone|iPod|Android|Mobile|Silk|Opera Mini',
            caseSensitive: false)
        .hasMatch(ua)) {
      return true;
    }
    // O iPad com iPadOS 13+ diz-se "Macintosh"; distingue-se pelo toque.
    final toques = html.window.navigator.maxTouchPoints ?? 0;
    return toques > 1 &&
        RegExp(r'Macintosh|iPad', caseSensitive: false).hasMatch(ua);
  } catch (e) {
    // Sem forma de saber → o caminho seguro é o que funciona nos dois.
    debugPrint('[WebCheckout] não consegui identificar o browser ($e)');
    return true;
  }
}

Future<void> startWebCardCheckout({
  required String clientSecret,
  required String publishableKey,
  String label = 'Bora',
  String vertical = 'desconhecida',
  String? referenciaId,
  String? paymentIntentId,
}) async {
  if (publishableKey.isEmpty) {
    throw const WebCheckoutFailed(
      'Falta a chave pública do Stripe neste build web.',
    );
  }

  final base = html.window.location.origin;
  // Para onde o `pay.html` tem de voltar quando o pagamento sai pelo mesmo
  // separador. Lê-se AGORA, antes de sair da página.
  final regresso = html.window.location.href;

  // Os parâmetros vão no fragmento (#), não na query: o fragmento nunca é
  // enviado ao servidor nem aparece em logs de acesso.
  final url = '$base/pay.html'
      '#cs=${Uri.encodeComponent(clientSecret)}'
      '&pk=${Uri.encodeComponent(publishableKey)}'
      '&label=${Uri.encodeComponent(label)}'
      '&volta=${Uri.encodeComponent(regresso)}';

  // Sai pelo mesmo separador. Devolve um Future que **nunca completa** de
  // propósito: a página vai descarregar e nada do que vem a seguir ao
  // pagamento pode correr. Se isto atirasse, o `catch` do ecrã cancelava a
  // corrida (`cancelRide`) mesmo antes de o browser navegar.
  Future<void> pelaMesmaJanela(String porque) {
    debugPrint('[WebCheckout] mesmo separador ($porque)');
    _guardarPendente(
      clientSecret: clientSecret,
      rotaRegresso: regresso,
      vertical: vertical,
      referenciaId: referenciaId,
      paymentIntentId: paymentIntentId,
    );
    html.window.location.href = url;
    return Completer<void>().future;
  }

  final telemovel = _ehBrowserDeTelemovel();

  // No telemóvel nem se chega a tentar abrir a janela.
  dynamic janela;
  if (!telemovel) {
    try {
      janela = html.window.open(url, 'bora_pagamento',
          'width=460,height=760,menubar=no,toolbar=no,location=no');
    } catch (e) {
      // `null` OU excepção = bloqueada. Nunca "está viva".
      debugPrint('[WebCheckout] window.open atirou: $e');
      janela = null;
    }
  }

  final caminho = escolherCaminhoDoCheckout(
    ehBrowserDeTelemovel: telemovel,
    janelaAbriu: janela != null,
  );
  if (caminho == CaminhoDoCheckout.mesmoSeparador) {
    return pelaMesmaJanela(
        telemovel ? 'browser de telemóvel' : 'janela bloqueada pelo browser');
  }

  final completer = Completer<void>();
  late final StreamSubscription<html.MessageEvent> sub;
  Timer? vigia;
  final abertura = DateTime.now();
  var ultimoSinal = abertura;
  var deuSinal = false;
  var aPagar = false;

  void terminar(void Function() accao) {
    if (completer.isCompleted) return;
    vigia?.cancel();
    sub.cancel();
    accao();
  }

  void fecharJanela() {
    try {
      janela.close();
    } catch (_) {/* já fechada ou cross-origin */}
  }

  sub = html.window.onMessage.listen((event) {
    // Só aceitamos mensagens da nossa própria origem.
    if (event.origin != base) return;
    final data = event.data;
    if (data is! Map || data['bora'] != 'pagamento') return;

    ultimoSinal = DateTime.now();
    switch (data['estado']) {
      case 'pronto':
      case 'vivo':
        // A janela existe mesmo. Só a partir daqui é que se pode confiar nela.
        deuSinal = true;
      case 'a-pagar':
        // O cliente carregou em Pagar — pode estar no banco a fazer 3-D Secure.
        deuSinal = true;
        aPagar = true;
      case 'pago':
        terminar(completer.complete);
      case 'cancelado':
        terminar(() => completer.completeError(const WebCheckoutCancelled()));
      default:
        terminar(() => completer.completeError(
              WebCheckoutFailed(
                (data['erro'] as String?) ?? 'O pagamento não foi concluído.',
              ),
            ));
    }
  });

  vigia = Timer.periodic(const Duration(milliseconds: 500), (_) {
    final agora = DateTime.now();

    bool fechada;
    try {
      fechada = (janela.closed as bool?) ?? false;
    } catch (_) {
      // Cross-origin (está no banco). Não prova nada — quem decide é o tecto
      // de silêncio, não este `catch`. Foi exactamente aqui que a versão
      // anterior se enganou.
      fechada = false;
    }

    switch (avaliarEspera(
      deuSinal: deuSinal,
      aPagar: aPagar,
      janelaFechada: fechada,
      desdeAbertura: agora.difference(abertura),
      desdeUltimoSinal: agora.difference(ultimoSinal),
    )) {
      case PassoDaEspera.continuar:
        return;

      case PassoDaEspera.tratarComoBloqueada:
        vigia?.cancel();
        sub.cancel();
        fecharJanela();
        if (!completer.isCompleted) {
          debugPrint('[WebCheckout] sem sinal em '
              '${prazoDoSinal.inMilliseconds}ms — a tratar como bloqueada');
          // O completer fica por completar de propósito: a página descarrega.
          pelaMesmaJanela('janela aberta mas sem sinal de vida');
        }

      case PassoDaEspera.cancelar:
        terminar(() => completer.completeError(const WebCheckoutCancelled()));

      case PassoDaEspera.desistirPorSilencio:
        fecharJanela();
        terminar(() => completer.completeError(const WebCheckoutFailed(
              'A janela de pagamento deixou de responder. '
              'Não foste cobrado — tenta outra vez ou escolhe outro método.',
            )));
    }
  });

  return completer.future;
}

void _guardarPendente({
  required String clientSecret,
  required String rotaRegresso,
  required String vertical,
  String? referenciaId,
  String? paymentIntentId,
}) {
  try {
    html.window.localStorage[_chavePendente] = jsonEncode({
      'vertical': vertical,
      'referenciaId': referenciaId,
      'paymentIntentId': paymentIntentId,
      'clientSecret': clientSecret,
      'rotaRegresso': rotaRegresso,
      'criadoEm': DateTime.now().toIso8601String(),
    });
  } catch (e) {
    // Modo privado do Safari pode recusar escrever. O pagamento segue à mesma
    // — o que se perde é a retoma automática.
    debugPrint('[WebCheckout] não consegui guardar o pendente: $e');
  }
}
