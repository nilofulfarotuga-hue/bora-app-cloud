// OFERTA DE LIMPEZA E DE LAVAGEM — o aviso no telemóvel (09/10/2026 · Mayra).
//
// A cicatriz: a 09/10 a Mayra (só faz limpeza) aceitou uma limpeza mas o aviso não
// tocou a sério. A oferta chegava como uma notificação de estado normal — sem ecrã
// inteiro, sem som em ciclo, sem botões — e o push data-only chegava SEM TEXTO,
// porque a app lia o título do bloco `notification`, que deixou de vir.
//
// Agora é igual ao estafeta/TVDE (que não se mexe — só se copia o padrão):
//  - canal das ofertas `bora_offers_alarm_v4` (volume do alarme), ecrã inteiro, som em ciclo (FLAG_INSISTENT);
//  - botões na própria notificação: Aceitar ABRE a app (o gancho global
//    `NotificationService.trabalhoOfertaAction`, no main.dart, aceita pelo store);
//    Recusar NÃO abre a app (isolate de fundo → RPC por HTTP cru);
//  - o mesmo id do `IncomingJobAlert` (`bookingId.hashCode`): quem cancela um cancela o outro;
//  - o servidor repete o toque a cada minuto (cron `cleaning-offer-reping`) enquanto a
//    oferta vive; depois de responder, a marca "já respondida" impede que uma repetição
//    já a caminho volte a tocar.

import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'incoming_job_alert.dart';

/// Botões da notificação de oferta de trabalho (limpeza e lavagem).
const String kTrabalhoAceitarAction = 'trabalho_aceitar';
const String kTrabalhoRecusarAction = 'trabalho_recusar';

const String _kTratadasPrefs = 'bora_trabalho_ofertas_tratadas';
const Duration _kTratadaValidade = Duration(minutes: 30);

/// Quanto tempo a notificação fica sem ser renovada. O servidor repete o toque a
/// cada minuto enquanto a oferta vive — cada repetição volta a pôr o relógio a
/// zero. Quando a oferta morre (aceite, recusada, expirada ou passada a outra
/// pessoa) as repetições param e o aviso sai sozinho, sem ficar fantasma.
const Duration kOfertaTrabalhoTimeout = Duration(minutes: 3);

/// 'cleaning_offer' → 'limpeza'; 'carwash_offer' → 'lavagem'; o resto → null.
String? categoriaDaOfertaDeTrabalho(String? type) => switch (type) {
      'cleaning_offer' => 'limpeza',
      'carwash_offer' => 'lavagem',
      _ => null,
    };

/// O `type` do push/payload para a categoria.
String tipoDaOfertaDeTrabalho(String categoria) =>
    categoria == 'lavagem' ? 'carwash_offer' : 'cleaning_offer';

/// A RPC que recusa a oferta, por categoria (a mesma que os stores chamam).
String rpcRecusarOfertaDeTrabalho(String categoria) =>
    categoria == 'lavagem' ? 'washer_reject_booking' : 'cleaner_reject_booking';

/// [4.C · lavagem sem texto] Título e corpo de um aviso de limpeza/lavagem.
/// O push de oferta é DATA-ONLY (sem bloco `notification`): o texto vem dentro
/// do `data`. Antes lia-se só `notification.title`, que vinha nulo — o aviso
/// aparecia só com "🚿 Bora Lavagem" e o corpo vazio. Ordem: data → notification
/// → texto de recurso (nunca vazio).
({String titulo, String corpo}) textoDoAvisoDeTrabalho({
  required Map<String, dynamic> data,
  String? notifTitle,
  String? notifBody,
  required String tituloDeRecurso,
  String corpoDeRecurso = 'Toca para ver.',
}) {
  String? limpo(Object? v) {
    final s = v?.toString().trim();
    return (s == null || s.isEmpty) ? null : s;
  }

  return (
    titulo: limpo(data['title']) ?? limpo(notifTitle) ?? tituloDeRecurso,
    corpo: limpo(data['body']) ?? limpo(notifBody) ?? corpoDeRecurso,
  );
}

/// Os dois botões da notificação de oferta. Pura (sem plugin) para se testar.
List<AndroidNotificationAction> ofertaTrabalhoNotificationActions() =>
    const <AndroidNotificationAction>[
      AndroidNotificationAction(
        kTrabalhoAceitarAction,
        '✅ Aceitar',
        showsUserInterface: true,
        cancelNotification: false,
      ),
      AndroidNotificationAction(
        kTrabalhoRecusarAction,
        '❌ Recusar',
        showsUserInterface: false,
        cancelNotification: true,
      ),
    ];

// ── "já respondida" ─────────────────────────────────────────────────────────
// Memória (síncrona) + SharedPreferences (o isolate de fundo não partilha memória).

final Map<String, DateTime> _tratadas = <String, DateTime>{};

/// Marca a oferta [bookingId] como respondida (aceite ou recusada).
Future<void> marcarOfertaTrabalhoTratada(String bookingId,
    {@visibleForTesting DateTime? quando}) async {
  if (bookingId.isEmpty) return;
  final agora = quando ?? DateTime.now();
  _tratadas[bookingId] = agora;
  try {
    final prefs = await SharedPreferences.getInstance();
    await prefs.reload();
    final corte = agora.subtract(_kTratadaValidade);
    final linhas = <String>[
      for (final l in prefs.getStringList(_kTratadasPrefs) ?? const <String>[])
        if (!l.startsWith('$bookingId|') && (_quandoDaLinha(l)?.isAfter(corte) ?? false))
          l,
      '$bookingId|${agora.millisecondsSinceEpoch}',
    ];
    await prefs.setStringList(_kTratadasPrefs, linhas);
  } catch (e) {
    debugPrint('[BORA-TRABALHO] oferta tratada não gravada: $e');
  }
}

/// Esta oferta já foi respondida neste aparelho (há menos de 30 min)? Lê a
/// memória e o que o outro isolate gravou.
Future<bool> ofertaTrabalhoJaTratada(String bookingId,
    {@visibleForTesting DateTime? agora}) async {
  if (bookingId.isEmpty) return false;
  final now = agora ?? DateTime.now();
  final mem = _tratadas[bookingId];
  if (mem != null && now.difference(mem) < _kTratadaValidade) return true;
  try {
    final prefs = await SharedPreferences.getInstance();
    await prefs.reload();
    for (final l in prefs.getStringList(_kTratadasPrefs) ?? const <String>[]) {
      if (!l.startsWith('$bookingId|')) continue;
      final q = _quandoDaLinha(l);
      return q != null && now.difference(q) < _kTratadaValidade;
    }
  } catch (_) {/* sem prefs: decide a memória */}
  return false;
}

/// Só para testes: esquece a memória (as prefs limpam-se com setMockInitialValues).
@visibleForTesting
void esquecerOfertasTrabalhoTratadas() => _tratadas.clear();

DateTime? _quandoDaLinha(String linha) {
  final p = linha.split('|');
  if (p.length != 2) return null;
  final ms = int.tryParse(p[1]);
  return ms == null ? null : DateTime.fromMillisecondsSinceEpoch(ms);
}

// ── a notificação ──────────────────────────────────────────────────────────

/// Mostra (ou renova) a notificação de oferta de [categoria] ('limpeza' ou
/// 'lavagem') para [bookingId]: ecrã inteiro, som em ciclo, Aceitar/Recusar.
/// Não mostra nada se a oferta já foi respondida neste aparelho.
@pragma('vm:entry-point')
Future<void> mostrarOfertaDeTrabalho({
  required String categoria,
  required String bookingId,
  required String titulo,
  required String corpo,
}) async {
  if (bookingId.isEmpty) return;
  if (await ofertaTrabalhoJaTratada(bookingId)) {
    debugPrint('[BORA-TRABALHO] oferta $bookingId já respondida — não toca');
    return;
  }
  try {
    final plugin = FlutterLocalNotificationsPlugin();
    // [10/10] definição única do canal das ofertas (volume do alarme). Criar o
    // mesmo id com outros atributos fazia-o nascer errado para sempre.
    await garantirCanalOfertasAlarme(plugin);
    final androidDetails = AndroidNotificationDetails(
      kCanalOfertasAlarme,
      kCanalOfertasAlarmeNome,
      channelDescription: 'Trabalho a chegar — aceita ou recusa.',
      importance: Importance.max,
      priority: Priority.max,
      playSound: true,
      sound: const RawResourceAndroidNotificationSound('bora_alert'),
      audioAttributesUsage: AudioAttributesUsage.alarm,
      enableVibration: true,
      category: AndroidNotificationCategory.call,
      fullScreenIntent: true,
      ongoing: true,
      autoCancel: false,
      onlyAlertOnce: false,
      ticker: titulo,
      visibility: NotificationVisibility.public,
      // Som em ciclo (FLAG_INSISTENT), como a oferta do estafeta.
      additionalFlags: Int32List.fromList(<int>[4]),
      timeoutAfter: kOfertaTrabalhoTimeout.inMilliseconds,
      styleInformation: BigTextStyleInformation(corpo, contentTitle: titulo),
      actions: ofertaTrabalhoNotificationActions(),
    );
    await plugin.show(
      bookingId.hashCode,
      titulo,
      corpo,
      NotificationDetails(android: androidDetails),
      payload: jsonEncode(<String, String>{
        'type': tipoDaOfertaDeTrabalho(categoria),
        'bookingId': bookingId,
        'categoria': categoria,
      }),
    );
    debugPrint('[BORA-TRABALHO] oferta $categoria $bookingId a tocar');
  } catch (e) {
    debugPrint('[BORA-TRABALHO] erro a mostrar oferta $bookingId: $e');
  }
}

/// Cala a notificação da oferta (mesmo id do IncomingJobAlert).
Future<void> calarOfertaDeTrabalho(String bookingId) =>
    IncomingJobAlert.dismiss(bookingId);
