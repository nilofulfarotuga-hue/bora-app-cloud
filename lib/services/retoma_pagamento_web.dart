/// Retoma de um pagamento que saiu da app pelo mesmo separador (só web).
///
/// No telemóvel (e no computador com janela nova) a app fica viva durante o
/// pagamento e o código a seguir corre normalmente. No Safari do iPhone não:
/// o `window.open` é bloqueado, o pagamento tem de sair pelo mesmo separador e
/// a app **morre**. Quando volta, tem de descobrir sozinha o que aconteceu.
///
/// Cicatriz de 22/09/2026: sem isto, a cliente Priscila Prates ficou com o
/// ecrã a rodar e a corrida morreu em `payment_failed` sem ninguém saber
/// porquê. Ver `web_checkout_web.dart`.
///
/// Regra de segurança herdada do `_aguardarPagamentoOnline`: só se cancela
/// quando o servidor **responde** que não está pago. Não conseguir perguntar
/// nunca é motivo para cancelar às cegas — pode ter sido cobrado.
library;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../l10n/tr.dart';
import '../screens/client/tvde/tvde_ride_tracking_screen.dart';
import '../stores/tvde_store.dart';
import 'notification_service.dart';
import 'payment_service.dart';
import 'web_checkout.dart';

/// Chamada uma vez no arranque da app web, depois do primeiro fotograma.
///
/// Não faz nada quando não há pagamento pendente — que é o caso normal.
Future<void> retomarPagamentoWebPendente() async {
  if (!kIsWeb) return;

  final pendente = lerPagamentoWebPendente();
  if (pendente == null) return;

  final ctx = NotificationService.navigatorKey.currentContext;
  if (ctx == null) {
    // A árvore ainda não existe. Deixa o pendente onde está: volta a tentar no
    // arranque seguinte, dentro da validade.
    debugPrint('[RetomaPagamento] sem contexto ainda — fica para a próxima');
    return;
  }

  debugPrint('[RetomaPagamento] pendente: vertical=${pendente.vertical} '
      'ref=${pendente.referenciaId}');

  // Só o TVDE sabe hoje responder "isto ficou pago?" a partir do id. As outras
  // verticais caem na mensagem neutra: o ecrã delas já faz o seu próprio poll.
  if (pendente.vertical == 'tvde' && pendente.referenciaId != null) {
    await _retomarTvde(ctx, pendente);
    return;
  }

  limparPagamentoWebPendente();
  if (!ctx.mounted) return;
  _aviso(ctx,
      'Voltaste de um pagamento. Vê o estado do teu pedido no ecrã dele.'.tr);
}

Future<void> _retomarTvde(
    BuildContext ctx, PagamentoWebPendente pendente) async {
  final store = ctx.read<TvdeStore>();
  final rideId = pendente.referenciaId!;

  final res = await store.confirmRidePayment(rideId);
  if (!ctx.mounted) return;

  final estado = res?['payment_status'] as String?;

  // a) Pago (ou a processar) → segue para o acompanhamento.
  if ((res != null && res['succeeded'] == true) || estado == 'processing') {
    limparPagamentoWebPendente();
    _abrirAcompanhamento(ctx);
    return;
  }

  // b) Não se conseguiu falar com o servidor. NÃO cancelar às cegas.
  if (res == null) {
    limparPagamentoWebPendente();
    _aviso(
        ctx,
        'Não conseguimos confirmar o pagamento agora. Vê o estado no ecrã da corrida.'
            .tr);
    return;
  }

  // c) O servidor respondeu que não está pago. Escolha explícita — nunca
  //    matar a corrida em silêncio, que foi o que aconteceu a 22/09.
  final pagarDeNovo = await showDialog<bool>(
    context: ctx,
    barrierDismissible: false,
    builder: (d) => AlertDialog(
      title: Text('O pagamento não foi concluído'.tr),
      content: Text(
          'A corrida ainda não foi pedida e não foste cobrado. Queres tentar pagar outra vez?'
              .tr),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(d, false),
            child: Text('Cancelar'.tr)),
        FilledButton(
            onPressed: () => Navigator.pop(d, true),
            child: Text('Pagar de novo'.tr)),
      ],
    ),
  );
  if (!ctx.mounted) return;

  if (pagarDeNovo != true) {
    limparPagamentoWebPendente();
    try {
      await store.cancelRide(rideId, reason: 'payment_failed', skipRefund: true);
    } catch (_) {/* o cron limpa (payment_timeout) */}
    store.clearActiveRide();
    if (!ctx.mounted) return;
    _aviso(ctx, 'Corrida cancelada. Não foste cobrado.'.tr);
    return;
  }

  // "Pagar de novo" reusa o MESMO PaymentIntent — reabrir duas vezes não cobra
  // duas vezes. O pendente só se limpa depois de sabermos o desfecho: se isto
  // voltar a sair pelo mesmo separador, ele é reescrito por dentro.
  try {
    await PaymentService().processPayment(
      pendente.clientSecret,
      vertical: 'tvde',
      referenciaId: rideId,
      paymentIntentId: pendente.paymentIntentId,
    );
  } catch (e) {
    limparPagamentoWebPendente();
    if (!ctx.mounted) return;
    _aviso(ctx, 'Pagamento não concluído. A corrida não foi pedida.'.tr);
    return;
  }
  limparPagamentoWebPendente();
  if (!ctx.mounted) return;
  _abrirAcompanhamento(ctx);
}

void _abrirAcompanhamento(BuildContext ctx) {
  Navigator.of(ctx).push(
    MaterialPageRoute(builder: (_) => const TvdeRideTrackingScreen()),
  );
}

void _aviso(BuildContext ctx, String texto) {
  ScaffoldMessenger.of(ctx).showSnackBar(SnackBar(content: Text(texto)));
}
