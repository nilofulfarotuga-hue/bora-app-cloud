// Prova no emulador Android 15 (missão fecho-total-2026-10-09, Blocos 4 e 7.2).
// Sem login e sem tocar no servidor:
//  1-2. o cartão global da oferta de LIMPEZA e de LAVAGEM em ecrã inteiro,
//       por cima de outro ecrã, com o som real em ciclo;
//  3.   a notificação real de oferta de lavagem (data-only: o texto vem do
//       `data`) com os botões Aceitar/Recusar;
//  4.   o serviço em primeiro plano do estafeta (o MESMO `BoraForegroundService`
//       da app) numa sessão longa — o guião do PC encurta por adb o limite de
//       6 h do tipo dataSync do Android 15 para ver o que acontece ao fim.
// Cada paragem escreve `[prova] PRONTO <nome>`; quem fotografa é o PC (adb
// screencap). Guião: .claude/.ai/provas/fecho-total-2026-10-09/emulador/capturar.ps1
import 'package:bora_app/models/carwash_models.dart';
import 'package:bora_app/models/cleaning_models.dart';
import 'package:bora_app/services/foreground_service.dart';
import 'package:bora_app/services/oferta_trabalho_aviso.dart';
import 'package:bora_app/stores/cleaner_store.dart';
import 'package:bora_app/stores/washer_store.dart';
import 'package:bora_app/widgets/trabalho_oferta_overlay_host.dart';
import 'package:flutter/material.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:provider/provider.dart';

const int _minutosDeServico =
    int.fromEnvironment('PROVA_MINUTOS_FGS', defaultValue: 6);

Future<void> _espera(WidgetTester tester, int segundos) async {
  for (var i = 0; i < segundos * 4; i++) {
    await tester.pump(const Duration(milliseconds: 250));
  }
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('prova fecho-total 09/10 — oferta de trabalho e serviço Android 15',
      (tester) async {
    final limpeza = CleanerStore();
    final lavagem = WasherStore();
    final agora = DateTime.now();

    limpeza.debugDefinirOfertas([
      CleaningBooking.fromSupabase(<String, dynamic>{
        'id': 'prova-limpeza-0910',
        'status': 'scheduled',
        'scheduled_at': '2026-10-10T09:00:00Z',
        'address_city': 'Guarda',
        'cleaner_earnings_cents': 3400,
        'total_cents': 4000,
        'offer_cleaner_id': 'c-prova',
        'offer_expires_at':
            agora.add(const Duration(minutes: 9)).toUtc().toIso8601String(),
      }),
    ]);

    await tester.pumpWidget(MultiProvider(
      providers: [
        ChangeNotifierProvider<CleanerStore>.value(value: limpeza),
        ChangeNotifierProvider<WasherStore>.value(value: lavagem),
      ],
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        home: Scaffold(
          appBar: AppBar(title: const Text('Ecrã do estafeta (por baixo)')),
          body: const Center(child: Text('A Mayra estava aqui')),
        ),
        builder: (context, child) => TrabalhoOfertaOverlayHost(
          ligarSessao: false,
          child: child!,
        ),
      ),
    ));
    await tester.pump();
    // ignore: avoid_print
    print('[prova] PRONTO 01_oferta_limpeza_ecra_inteiro');
    await _espera(tester, 9);

    limpeza.debugDefinirOfertas(const []);
    lavagem.debugDefinir(
      perfil: WasherProfile.fromSupabase(const <String, dynamic>{
        'id': 'w-prova',
        'user_id': 'u-prova',
        'approval_status': 'approved',
        'is_active': true,
      }),
      ofertas: [
        CarwashBooking.fromSupabase(<String, dynamic>{
          'id': 'prova-lavagem-0910',
          'status': 'scheduled',
          'scheduled_at': '2026-10-10T14:30:00Z',
          'address_street': 'Rua Francisco de Passos 12',
          'address_city': 'Guarda',
          'washer_earnings_cents': 900,
          'offer_expires_at':
              agora.add(const Duration(minutes: 9)).toUtc().toIso8601String(),
        }),
      ],
    );
    await tester.pump();
    // ignore: avoid_print
    print('[prova] PRONTO 02_oferta_lavagem_ecra_inteiro');
    await _espera(tester, 9);

    lavagem.debugDefinir(ofertas: const []);
    await tester.pump();

    // 3. A notificação REAL do Android, como o push data-only a desenha.
    final plugin = FlutterLocalNotificationsPlugin();
    await plugin.initialize(const InitializationSettings(
        android: AndroidInitializationSettings('@mipmap/ic_launcher')));
    final texto = textoDoAvisoDeTrabalho(
      data: const <String, dynamic>{
        'type': 'carwash_offer',
        'bookingId': 'prova-lavagem-0910',
        'title': '🚿 Nova lavagem!',
        'body': 'Ganhas €9,00 · Guarda · Aceita ou recusa.',
      },
      tituloDeRecurso: '🚿 Bora Lavagem',
    );
    await mostrarOfertaDeTrabalho(
      categoria: 'lavagem',
      bookingId: 'prova-lavagem-0910',
      titulo: texto.titulo,
      corpo: texto.corpo,
    );
    // ignore: avoid_print
    print('[prova] PRONTO 03_aviso_lavagem_com_texto_e_botoes');
    await _espera(tester, 12);
    await calarOfertaDeTrabalho('prova-lavagem-0910');

    // 4. O serviço em primeiro plano do estafeta, sessão longa.
    await BoraForegroundService.init();
    final ok = await BoraForegroundService.startDriver();
    // ignore: avoid_print
    print('[prova] FGS arrancou ok=$ok');
    for (var minuto = 1; minuto <= _minutosDeServico; minuto++) {
      await tester.runAsync(
          () => Future<void>.delayed(const Duration(seconds: 60)));
      final vivo = await FlutterForegroundTask.isRunningService;
      // ignore: avoid_print
      print('[prova] FGS minuto=$minuto a_correr=$vivo');
      if (minuto == 1) {
        // ignore: avoid_print
        print('[prova] PRONTO 04_servico_em_primeiro_plano');
      }
    }
    await BoraForegroundService.stop();
    // ignore: avoid_print
    print('[prova] FIM');
  }, timeout: const Timeout(Duration(minutes: 40)));
}
