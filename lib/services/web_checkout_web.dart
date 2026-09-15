/// Lado web do `web_checkout`.
///
/// Abre `pay.html` numa janela pequena, deixa o Stripe.js tratar do cartão
/// (incluindo o redirect 3-D Secure, que acontece dentro dessa janela) e
/// espera pela mensagem de resultado. A app Flutter fica viva o tempo todo,
/// por isso o código que corre **depois** do pagamento é o mesmo do telemóvel.
///
/// Se o browser bloquear a janela (acontece no Safari quando o `window.open`
/// não vem colado a um toque), caímos para redirect no mesmo separador: o
/// pagamento conclui à mesma e o `stripe-webhook` marca como pago — o que se
/// perde é só o retorno automático ao ecrã anterior.
///
/// Usa `dart:html` por coerência com os ficheiros web que já existem no repo
/// (`place_autocomplete_service_web.dart`, `directions_service_web.dart`).
library;

import 'dart:async';
// ignore: avoid_web_libraries_in_flutter, deprecated_member_use
import 'dart:html' as html;

import 'package:flutter/foundation.dart';

/// Lançada quando o utilizador fecha a janela sem pagar.
class WebCheckoutCancelled implements Exception {
  const WebCheckoutCancelled();

  @override
  String toString() => 'Pagamento cancelado.';
}

/// Lançada quando o Stripe recusa o pagamento.
class WebCheckoutFailed implements Exception {
  const WebCheckoutFailed(this.message);

  final String message;

  @override
  String toString() => message;
}

Future<void> startWebCardCheckout({
  required String clientSecret,
  required String publishableKey,
  String label = 'Bora',
}) async {
  if (publishableKey.isEmpty) {
    throw const WebCheckoutFailed(
      'Falta a chave pública do Stripe neste build web.',
    );
  }

  final base = html.window.location.origin;
  // Os parâmetros vão no fragmento (#), não na query: o fragmento nunca é
  // enviado ao servidor nem aparece em logs de acesso.
  final url = '$base/pay.html'
      '#cs=${Uri.encodeComponent(clientSecret)}'
      '&pk=${Uri.encodeComponent(publishableKey)}'
      '&label=${Uri.encodeComponent(label)}';

  final popup = html.window.open(url, 'bora_pagamento',
      'width=460,height=760,menubar=no,toolbar=no,location=no');

  // Janela bloqueada pelo browser → redirect no mesmo separador.
  bool blocked;
  try {
    blocked = popup.closed ?? true;
  } catch (_) {
    blocked = false; // cross-origin durante o redirect do Stripe = está viva
  }
  if (blocked) {
    debugPrint('[WebCheckout] janela bloqueada — redirect no mesmo separador');
    html.window.location.href = url;
    // A página vai descarregar; este Future nunca completa de propósito.
    return Completer<void>().future;
  }

  final completer = Completer<void>();
  late final StreamSubscription<html.MessageEvent> sub;
  Timer? watchdog;

  void finish(void Function() action) {
    if (completer.isCompleted) return;
    watchdog?.cancel();
    sub.cancel();
    action();
  }

  sub = html.window.onMessage.listen((event) {
    // Só aceitamos mensagens da nossa própria origem.
    if (event.origin != base) return;
    final data = event.data;
    if (data is! Map || data['bora'] != 'pagamento') return;

    switch (data['estado']) {
      case 'pago':
        finish(completer.complete);
      case 'cancelado':
        finish(() => completer.completeError(const WebCheckoutCancelled()));
      default:
        finish(() => completer.completeError(
              WebCheckoutFailed(
                (data['erro'] as String?) ?? 'O pagamento não foi concluído.',
              ),
            ));
    }
  });

  // Se o utilizador fechar a janela no X, não chega mensagem nenhuma.
  watchdog = Timer.periodic(const Duration(milliseconds: 700), (_) {
    bool closed;
    try {
      closed = popup.closed ?? false;
    } catch (_) {
      return; // cross-origin (está no Stripe) — continuar à espera
    }
    if (closed) {
      finish(() => completer.completeError(const WebCheckoutCancelled()));
    }
  });

  return completer.future;
}
