import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

/// Aviso "o teu motorista está quase a chegar" (lado CLIENTE, TVDE).
///
/// Reutiliza o canal que **já existe** — `bora_orders` ("Bora — Notificações"),
/// criado no arranque em `main.dart` e usado pelas Edge Functions
/// `notify-client` / `notify-tvde-client`. Não se cria canal novo: um canal a
/// mais no Android é uma linha a mais nas definições do telemóvel do cliente,
/// e mais uma coisa que ele pode desligar sem perceber.
///
/// Local de propósito: o ETA que dispara isto é calculado no telemóvel do
/// cliente (poll + Directions). Mandá-lo dar a volta pelo servidor só para
/// voltar ao mesmo telemóvel era caro e mais frágil.
///
/// Sem som insistente, sem `ongoing`, sem botões: é um aviso, não uma decisão.
class TvdeArrivingNotice {
  /// Id estável por corrida — reavisar a mesma corrida substitui em vez de
  /// empilhar. (O ecrã já só dispara uma vez, isto é a segunda rede.)
  static int _idFor(String rideId) => 'tvde_arriving_$rideId'.hashCode;

  /// Mostra o aviso. Nunca lança: falhar um aviso não pode partir o ecrã da
  /// corrida.
  static Future<void> show({
    required String rideId,
    required String title,
    required String body,
  }) async {
    // flutter_local_notifications não existe na Web (mesmo guarda do main).
    if (kIsWeb) return;
    try {
      const androidDetails = AndroidNotificationDetails(
        'bora_orders',
        'Bora — Notificações',
        channelDescription: 'Estado das encomendas e avisos do Bora App.',
        importance: Importance.high,
        priority: Priority.high,
        playSound: true,
        ongoing: false,
        autoCancel: true,
        category: AndroidNotificationCategory.message,
      );
      await FlutterLocalNotificationsPlugin().show(
        _idFor(rideId),
        title,
        body,
        const NotificationDetails(android: androidDetails),
        payload: jsonEncode({
          'type': 'tvde_driver_arriving',
          'rideId': rideId,
        }),
      );
      debugPrint('[TVDE-CLIENTE] aviso "quase a chegar" enviado ride=$rideId');
    } catch (e) {
      debugPrint('[TVDE-CLIENTE] falhou o aviso "quase a chegar": $e');
    }
  }
}
