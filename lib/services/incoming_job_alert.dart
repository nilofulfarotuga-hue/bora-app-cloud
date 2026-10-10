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

/// Canal das OFERTAS de trabalho (10/10/2026): toca pelo volume do ALARME.
///
/// O canal antigo `bora_orders_urgent_v3` toca pelo volume da campainha — com o
/// telemóvel em Vibrar ou em modo noite só vibra (Favor d383a09e de 09/10 e
/// reserva TVDE 6f89ef6a de 10/10, Samsung A36 do Danilo). O áudio de um canal
/// não muda depois de criado, por isso é um id novo. O MainActivity cria-o com
/// os mesmos atributos (quem cria primeiro manda; os dois têm de ser iguais).
const String kCanalOfertasAlarme = 'bora_offers_alarm_v4';
const String kCanalOfertasAlarmeNome = 'Bora — Ofertas de trabalho (alarme)';

/// Definição única do canal das ofertas — usar SEMPRE esta (Dart e isolate de
/// fundo), nunca uma cópia.
const AndroidNotificationChannel canalOfertasAlarme = AndroidNotificationChannel(
  kCanalOfertasAlarme,
  kCanalOfertasAlarmeNome,
  description: 'Toca como um alarme até aceitares, recusares ou a oferta acabar.',
  importance: Importance.max,
  playSound: true,
  sound: RawResourceAndroidNotificationSound('bora_alert'),
  audioAttributesUsage: AudioAttributesUsage.alarm,
  enableVibration: true,
  showBadge: true,
);

/// Cria o canal das ofertas (idempotente). Serve qualquer isolate.
Future<void> garantirCanalOfertasAlarme(
    FlutterLocalNotificationsPlugin plugin) async {
  final androidImpl = plugin.resolvePlatformSpecificImplementation<
      AndroidFlutterLocalNotificationsPlugin>();
  await androidImpl?.createNotificationChannel(canalOfertasAlarme);
}

/// Milissegundos até ao fim da oferta (para o `timeoutAfter`). Sem prazo
/// conhecido usa [semPrazo]; nunca menos de 5 s.
int msAteFimDaOferta(String? prazoIso, {int semPrazo = 60000}) {
  final prazo = DateTime.tryParse((prazoIso ?? '').trim());
  if (prazo == null) return semPrazo;
  final ms = prazo.difference(DateTime.now()).inMilliseconds;
  return ms < 5000 ? 5000 : ms;
}

/// Mantido para quem já o importa: os alertas de trabalho usam o canal novo.
const String kIncomingJobChannelId = kCanalOfertasAlarme;
const String kIncomingJobChannelName = kCanalOfertasAlarmeNome;

/// Alerta insistente e reutilizável para "trabalho a chegar" (pedido de parceiro,
/// oferta de limpeza, corrida TVDE, favor…). Um único ponto para a mecânica provada.
class IncomingJobAlert {
  IncomingJobAlert._();

  static final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();

  static bool _channelReady = false;

  static Future<void> _ensureChannel() async {
    if (_channelReady) return;
    await garantirCanalOfertasAlarme(_plugin);
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
    // 10/10/2026 — o toque dura até ao fim da oferta (antes eram 45 s fixos).
    int timeoutMs = 45000,
  }) async {
    if (id.isEmpty) return;
    try {
      await _ensureChannel();
      final androidDetails = AndroidNotificationDetails(
        kCanalOfertasAlarme,
        kCanalOfertasAlarmeNome,
        channelDescription: 'Trabalho a chegar — toca para abrir e responder.',
        importance: Importance.max,
        priority: Priority.max,
        playSound: true,
        sound: const RawResourceAndroidNotificationSound('bora_alert'),
        audioAttributesUsage: AudioAttributesUsage.alarm,
        enableVibration: true,
        category: AndroidNotificationCategory.call,
        fullScreenIntent: true,
        autoCancel: true,
        onlyAlertOnce: false,
        ticker: title,
        visibility: NotificationVisibility.public,
        // Como o estafeta: som em loop (FLAG_INSISTENT) para não perder o trabalho.
        additionalFlags: Int32List.fromList(<int>[4]),
        timeoutAfter: timeoutMs < 5000 ? 5000 : timeoutMs,
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
