// MEGA-FIX 2026-07-18 Parte 6 — serviço reutilizável de alerta de "trabalho a chegar".
//
// Extrai o padrão persistente que o estafeta já usa (canal urgente `bora_orders_urgent_v3`,
// fullScreenIntent + som `bora_alert` em loop/FLAG_INSISTENT + BigText) num único ponto, para
// qualquer papel poder disparar o MESMO alerta insistente sem duplicar a mecânica.
//
// PORQUÊ um serviço novo e ADITIVO (em vez de refatorar o notification_service):
//   - O sistema de oferta do estafeta (offer_presentation_gate + os 6 blocos fullScreenIntent do
//     bg handler) é delicado, testado em device e a FUNCIONAR. Refatorá-lo às cegas (sem device
//     para validar som/heads-up/full-screen) arriscava regredir uma feature-core. Ver CLAUDE.md
//     "NEVER break existing working features".
//   - Este serviço reutiliza EXACTAMENTE o mesmo canal e flags provados, só parametrizado. Papéis
//     que hoje não têm alerta nenhum (ex.: profissional de limpeza — Parte 7) passam a ter, e
//     papéis que já apresentam oferta em foreground (estafeta, TVDE, parceiro) podem migrar para
//     aqui numa sessão de QA com device, sem pressa e sem risco.
//
// PROIBIDO (removido de vez): CallKit / CallStyle / FlutterOverlayWindow. Só notificação local
// fullScreenIntent — acorda o ecrã e, ao tocar, abre a app (o roteamento por `type` do payload é
// tratado pelo router de tap já existente no NotificationService).
//
// Ver .claude/.ai/knowledge/wiki/licoes/licao-notify-canal-errado.md

import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_local_notifications/flutter_local_notifications.dart';

/// Canal urgente partilhado (o mesmo do estafeta/TVDE). Mantê-lo idêntico garante
/// que o Android trata todos os alertas de "trabalho a chegar" com a mesma prioridade.
const String kIncomingJobChannelId = 'bora_orders_urgent_v3';
const String kIncomingJobChannelName = 'Bora — Novos pedidos';

/// Alerta insistente e reutilizável para "trabalho a chegar" (pedido de parceiro,
/// oferta de limpeza, corrida TVDE, favor…). Um único ponto para a mecânica provada.
class IncomingJobAlert {
  IncomingJobAlert._();

  static final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();

  static bool _channelReady = false;

  static Future<void> _ensureChannel() async {
    if (_channelReady) return;
    final androidImpl = _plugin.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    await androidImpl?.createNotificationChannel(
      const AndroidNotificationChannel(
        kIncomingJobChannelId,
        kIncomingJobChannelName,
        description: 'Som contínuo + vibração para novos pedidos urgentes.',
        importance: Importance.max,
        playSound: true,
        sound: RawResourceAndroidNotificationSound('bora_alert'),
        enableVibration: true,
        showBadge: true,
      ),
    );
    _channelReady = true;
  }

  /// Mostra o alerta persistente. `id` deve ser estável por trabalho (ex.: bookingId)
  /// para dedup/cancelamento. `type` entra no payload para o router de tap saber para
  /// onde abrir (ex.: 'cleaning_offer', 'new_order', 'new_tvde_ride_offer').
  ///
  /// `extraPayload` acrescenta chaves ao payload (ex.: {'bookingId': id}).
  static Future<void> show({
    required String id,
    required String type,
    required String title,
    required String body,
    Map<String, dynamic> extraPayload = const {},
  }) async {
    if (id.isEmpty) return;
    try {
      await _ensureChannel();
      final androidDetails = AndroidNotificationDetails(
        kIncomingJobChannelId,
        kIncomingJobChannelName,
        channelDescription: 'Trabalho a chegar — toca para abrir e responder.',
        importance: Importance.max,
        priority: Priority.max,
        playSound: true,
        sound: const RawResourceAndroidNotificationSound('bora_alert'),
        enableVibration: true,
        category: AndroidNotificationCategory.call,
        fullScreenIntent: true,
        autoCancel: true,
        onlyAlertOnce: false,
        ticker: title,
        visibility: NotificationVisibility.public,
        // Como o estafeta: som em loop (FLAG_INSISTENT) para não perder o trabalho.
        additionalFlags: Int32List.fromList(<int>[4]),
        timeoutAfter: 45000,
        styleInformation: BigTextStyleInformation(body, contentTitle: title),
      );
      await _plugin.show(
        id.hashCode,
        title,
        body,
        NotificationDetails(android: androidDetails),
        payload: jsonEncode({'type': type, 'id': id, ...extraPayload}),
      );
    } catch (_) {
      // Nunca deixar um alerta falhado quebrar o fluxo que o disparou.
    }
  }

  /// Cancela o alerta (aceite/expirado/tratado) — mesmo `id` usado no [show].
  static Future<void> dismiss(String id) async {
    if (id.isEmpty) return;
    try {
      await _plugin.cancel(id.hashCode);
    } catch (_) {}
  }
}
