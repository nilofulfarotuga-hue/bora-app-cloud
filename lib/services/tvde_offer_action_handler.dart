import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../stores/tvde_driver_store.dart';
import '../widgets/tvde/tvde_offer_overlay_host.dart';
import 'notification_service.dart';

/// [Oferta sobreposta 20/09/2026 · Bloco 3] Os botões da NOTIFICAÇÃO de
/// oferta TVDE (imediata e de reserva), tratados ao nível da app.
///
/// Com o Waze ou o Maps por cima, a app do Bora não desenha nada: a
/// notificação é a única coisa em que o motorista pode tocar. Até hoje só
/// dizia "toca para abrir". Passa a ter Aceitar e Recusar:
///  - **Aceitar** abre a app (`showsUserInterface: true`) e cai aqui, no
///    isolate principal, com o store inteiro: aceita pela RPC de sempre e
///    leva-o ao ecrã certo (a corrida activa, ou a fila se já leva alguém).
///  - **Recusar** não abre a app: corre no isolate de segundo plano
///    (`onBackgroundNotificationAction`, em `notification_service.dart`) e
///    chama a RPC por HTTP cru. O servidor roda para o seguinte.
///
/// Registado UMA vez no `main.dart` — nunca dentro de um ecrã (cicatriz de
/// 20/08: gancho preso ao initState de um ecrã ficava a null com outro ecrã
/// por cima).
Future<void> tvdeResponderOfertaGlobal(String rideId, String actionId) async {
  if (rideId.isEmpty) return;

  // Arranque a frio: o navegador e a sessão podem demorar a estar prontos.
  BuildContext? ctx;
  for (var tentativa = 0; tentativa < 10; tentativa++) {
    ctx = NotificationService.navigatorKey.currentContext;
    final sessao = Supabase.instance.client.auth.currentUser;
    if (ctx != null && ctx.mounted && sessao != null) break;
    await Future<void>.delayed(const Duration(milliseconds: 700));
  }
  if (ctx == null || !ctx.mounted) {
    debugPrint('[BORA-TVDE] acção $actionId sem UI montada — ignorada');
    return;
  }

  final store = ctx.read<TvdeDriverStore>();
  final messenger = ScaffoldMessenger.maybeOf(ctx);
  void snack(String t) => messenger?.showSnackBar(SnackBar(content: Text(t)));

  switch (actionId) {
    case kTvdeOfferAcceptAction:
      try {
        final r = await store.acceptOffer(rideId);
        unawaited(cancelTvdeRideNotification(rideId));
        snack(r.isQueued
            ? 'Corrida em fila — abre sozinha quando terminares esta.'
            : 'Corrida aceite.');
        if (!r.isQueued) await abrirCorridaActivaSeFechada();
      } catch (e) {
        store.clearOffer();
        unawaited(cancelTvdeRideNotification(rideId));
        snack(mensagemDeOfertaFalhada(e));
        unawaited(store.reloadOffers());
      }
      return;

    case kTvdeReservationAcceptAction:
      try {
        await store.acceptReservation(rideId);
        unawaited(cancelTvdeRideNotification(rideId));
        snack('Reserva aceite. Fica na tua agenda — avisamos-te perto da '
            'hora.');
      } catch (e) {
        unawaited(cancelTvdeRideNotification(rideId));
        snack(e.toString().contains('offer_no_longer_valid')
            ? 'Essa reserva já não está disponível.'
            : 'Não consegui aceitar a reserva. Abre a app e tenta outra vez.');
        unawaited(store.loadAgenda());
      }
      return;

    // Os "recusar" correm sem UI (isolate de segundo plano). Se alguma vez
    // chegarem aqui — plataforma sem acções em segundo plano — tratam-se na
    // mesma, pelo store.
    case kTvdeOfferRejectAction:
      try {
        await store.rejectOffer(rideId);
      } catch (_) {
        store.clearOffer();
      }
      return;

    case kTvdeReservationRejectAction:
      try {
        await store.rejectReservation(rideId);
      } catch (_) {
        store.clearReservationOffer();
      }
      return;
  }
}
