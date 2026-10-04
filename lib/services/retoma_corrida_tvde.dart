/// Retoma da corrida TVDE viva quando a app do CLIENTE arranca.
///
/// Cicatriz de 04/10/2026: a app recarregou a meio de uma corrida (separador
/// do Safari descartado, app morta pelo sistema) e o cliente caiu na home sem
/// sinal nenhum da corrida — só a reencontrava se tocasse em "Bora Motorista".
/// Uma corrida a decorrer tem de voltar sozinha para o ecrã, como na Uber.
library;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../screens/client/tvde/tvde_ride_tracking_screen.dart';
import '../stores/session_store.dart';
import '../stores/tvde_store.dart';
import 'notification_service.dart';
import 'web_checkout.dart';

/// Chamada uma vez no arranque, depois do primeiro fotograma. Não faz nada
/// quando não há sessão de cliente nem corrida viva — que é o caso normal.
Future<void> retomarCorridaTvdeViva() async {
  try {
    // Regresso de um pagamento web: quem abre o ecrã é a retoma do pagamento.
    if (lerPagamentoWebPendente() != null) return;
    if (Supabase.instance.client.auth.currentUser == null) return;

    final ctx = NotificationService.navigatorKey.currentContext;
    if (ctx == null) return;
    if (ctx.read<SessionStore>().role != UserRole.client) return;

    final store = ctx.read<TvdeStore>();
    await store.loadActiveRide();
    if (!ctx.mounted) return;
    final ride = store.activeRide;
    if (ride == null || !ride.isLive || ride.isAwaitingPayment) return;

    Navigator.of(ctx).push(
      MaterialPageRoute(builder: (_) => const TvdeRideTrackingScreen()),
    );
  } catch (e) {
    debugPrint('[RetomaCorrida] falhou (segue sem retoma): $e');
  }
}
