import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';
import 'package:provider/provider.dart';

import '../models/falha_de_acao.dart';
import '../models/tvde_ride.dart';
import '../stores/tvde_driver_store.dart';
import 'navigation_service.dart';
import 'notification_service.dart';

/// [Fix 2026-08-20 — "A caminho" não abria a navegação]
///
/// **O que estava mal.** `NotificationService.tvdeReservationReadyTap` era
/// registado no `initState` da `TvdeDriverHomeScreen` e posto a `null` no
/// `dispose`. Com o ecrã de corrida activa por cima — que é *exactamente* onde
/// o motorista está quando a reserva arranca — o gancho estava a `null`: a RPC
/// ainda corria pelo caminho headless (por isso o servidor gravava
/// `reservation_driver_ready_at` e tudo parecia bem), mas a navegação nunca
/// chegava a ser lançada.
///
/// Provado na 539: `[NOTIF TAP] FG actionId=tvde_reservation_ready` no log,
/// servidor gravado 2 s depois, e nenhum selector de navegação no ecrã.
///
/// **Como passou a ser.** O tratamento vive aqui, fora de qualquer ecrã, e é
/// registado uma vez no arranque da app (`main.dart`). Funciona com a app em
/// qualquer ecrã. Com a app fechada ou em segundo plano continua a valer o
/// caminho headless do `NotificationService`, que já existia — este handler é
/// a parte que precisa de UI.
Future<void> tvdeConfirmarACaminhoGlobal(String rideId) async {
  if (rideId.isEmpty) return;

  // O contexto do navegador global. Se for null, a UI não está montada — o
  // caminho headless já tratou (ou vai tratar) da confirmação no servidor.
  final context = NotificationService.navigatorKey.currentContext;
  if (context == null) {
    debugPrint('[BORA-RESERVA] a_caminho sem UI montada — fica ao headless');
    return;
  }

  final store = context.read<TvdeDriverStore>();
  final messenger = ScaffoldMessenger.maybeOf(context);

  bool ok;
  try {
    ok = await store.reservationReady(rideId);
  } catch (e) {
    messenger?.showSnackBar(SnackBar(
      content: Text(mensagemDeFalhaDeAcao(e, trabalho: TrabalhoEmCurso.corrida)),
    ));
    return;
  }

  if (!ok) {
    messenger?.showSnackBar(const SnackBar(
      content: Text('Não consegui confirmar. Abre a agenda e tenta outra vez.'),
    ));
    return;
  }

  messenger?.showSnackBar(const SnackBar(
    content: Text('Confirmado. Vai a caminho da recolha.'),
  ));

  // Onde é a recolha? Agenda → corrida activa → servidor. A reserva activada
  // NÃO está na agenda (o sweep põe-lhe `status='motorista_atribuido'` e a
  // agenda pede `'agendada'`), por isso a procura não pode parar aí.
  TvdeRide? r;
  for (final x in store.agenda) {
    if (x.id == rideId) {
      r = x;
      break;
    }
  }
  if (r == null && store.activeRide?.id == rideId) r = store.activeRide;
  r ??= await store.fetchRideById(rideId);
  if (r == null) return;

  final ctx = NotificationService.navigatorKey.currentContext;
  if (ctx == null) return;
  await NavigationService.openNavigationOptions(
    ctx,
    LatLng(r.originLat, r.originLng),
  );
}
