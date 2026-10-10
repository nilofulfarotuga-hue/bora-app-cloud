// Guarda do canal das ofertas v4 (10/10/2026).
//
// Cicatriz: a 09/10 (Favor d383a09e) e a 10/10 (reserva TVDE 6f89ef6a) a
// oferta só vibrou no Samsung A36 do Danilo, em Vibrar/modo noite. O canal v3
// toca pelo volume da CAMPAINHA; o v4 toca pelo volume do ALARME. O áudio de
// um canal não muda depois de criado — por isso o id novo, e por isso todas as
// definições têm de ser IGUAIS (quem cria primeiro manda).
import 'dart:io';

import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:bora_app/services/incoming_job_alert.dart';

// Sem '\r': os ficheiros podem vir com fins de linha do Windows.
String _ler(String caminho) =>
    File(caminho).readAsStringSync().replaceAll('\r\n', '\n');

void main() {
  test('o canal das ofertas toca pelo volume do ALARME, com o som bora_alert', () {
    expect(kCanalOfertasAlarme, 'bora_offers_alarm_v4');
    expect(canalOfertasAlarme.id, kCanalOfertasAlarme);
    expect(canalOfertasAlarme.audioAttributesUsage, AudioAttributesUsage.alarm);
    expect(canalOfertasAlarme.importance, Importance.max);
    expect(canalOfertasAlarme.playSound, isTrue);
    expect((canalOfertasAlarme.sound as RawResourceAndroidNotificationSound).sound,
        'bora_alert');
    // Quem já importava o id antigo dos alertas de trabalho passa ao v4.
    expect(kIncomingJobChannelId, kCanalOfertasAlarme);
  });

  test('o Android nativo cria o MESMO canal, com USAGE_ALARM', () {
    final kt = _ler('android/app/src/main/kotlin/pt/boraapp/bora/MainActivity.kt');
    expect(kt, contains('CHANNEL_OFFERS_ALARM_V4 = "bora_offers_alarm_v4"'));
    expect(kt, contains('createOffersAlarmChannelV4()'));
    final corpo = kt.substring(kt.indexOf('private fun createOffersAlarmChannelV4'));
    expect(corpo, contains('AudioAttributes.USAGE_ALARM'));
    expect(corpo, contains('raw/bora_alert'));
  });

  test('as ofertas insistentes usam o canal v4 (nunca o v3) e ninguém recria o v4 de outra forma', () {
    final ns = _ler('lib/services/notification_service.dart');
    final ota = _ler('lib/services/oferta_trabalho_aviso.dart');
    final ija = _ler('lib/services/incoming_job_alert.dart');
    // Oferta de entrega/Favor em fundo, wake da app, parceiro, TVDE: canal v4.
    expect(RegExp('kCanalOfertasAlarme,').allMatches(ns).length, greaterThanOrEqualTo(5));
    expect(ota, contains('garantirCanalOfertasAlarme(plugin)'));
    // A única definição do canal v4 em Dart é a de incoming_job_alert.dart.
    for (final f in <String>[ns, ota, _ler('lib/main.dart')]) {
      expect(f.contains("AndroidNotificationChannel(\n        kIncomingJobChannelId"), isFalse);
      expect(f.contains("'bora_offers_alarm_v4'"), isFalse,
          reason: 'o id do canal v4 só se escreve em incoming_job_alert.dart');
    }
    expect(ija, contains("'bora_offers_alarm_v4'"));
  });

  test('o aviso que acorda a app mantém o som em ciclo (FLAG_INSISTENT)', () {
    final ns = _ler('lib/services/notification_service.dart');
    final inicio = ns.indexOf('Future<void> postWakeActivityNotification(');
    final wake = ns.substring(inicio, ns.indexOf('\n}\n', inicio));
    expect(wake, contains('additionalFlags: Int32List.fromList(<int>[4])'));
    expect(wake, contains('kCanalOfertasAlarme'));
  });

  test('o tempo do toque acompanha o prazo da oferta', () {
    final daqui30s =
        DateTime.now().add(const Duration(seconds: 30)).toUtc().toIso8601String();
    final ms = msAteFimDaOferta(daqui30s);
    expect(ms, inInclusiveRange(28000, 30000));
    expect(msAteFimDaOferta(null, semPrazo: 90000), 90000);
    expect(msAteFimDaOferta('2020-01-01T00:00:00Z'), 5000);
  });
}
