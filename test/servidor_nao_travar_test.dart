// [16/11/2026 servidor-nao-travar] A app da Isabel pediu a lista de pedidos
// 23 890 vezes em 80 min e travou o servidor Micro. Estes testes guardam as
// duas portas que impedem que volte a acontecer:
//  1. PortaoReleitura — N voltas à app em 10 s dão no máximo 1 releitura;
//     janelas por cima (inactive→resumed) não releem; no web, mudar de
//     separador (hidden→resumed) relê.
//  2. ReligarComEspera — erros seguidos do tempo real dão UMA religação de
//     cada vez, com espera crescente (5, 10, 20, 40, 60 s), e voltam aos 5 s
//     quando chegam dados.
import 'package:bora_app/services/app_update_service.dart';
import 'package:bora_app/utils/portao_releitura.dart';
import 'package:bora_app/utils/religar_com_espera.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('PortaoReleitura (voltar à app)', () {
    test('20 voltas reais em 10 s dão no máximo 1 releitura', () {
      final portao = PortaoReleitura();
      final t0 = DateTime(2026, 11, 16, 17, 5);
      var leituras = 0;
      for (var i = 0; i < 20; i++) {
        final agora = t0.add(Duration(milliseconds: i * 500));
        portao.deveReler(AppLifecycleState.inactive, agora);
        portao.deveReler(AppLifecycleState.hidden, agora);
        portao.deveReler(AppLifecycleState.paused, agora);
        portao.deveReler(AppLifecycleState.hidden, agora);
        portao.deveReler(AppLifecycleState.inactive, agora);
        if (portao.deveReler(AppLifecycleState.resumed, agora)) leituras++;
      }
      expect(leituras, 1);
    });

    test('janela por cima (inactive→resumed, ex. microfone) não relê', () {
      final portao = PortaoReleitura();
      final t0 = DateTime(2026, 11, 16, 16, 20);
      var leituras = 0;
      for (var i = 0; i < 100; i++) {
        final agora = t0.add(Duration(seconds: i * 5));
        portao.deveReler(AppLifecycleState.inactive, agora);
        if (portao.deveReler(AppLifecycleState.resumed, agora)) leituras++;
      }
      expect(leituras, 0);
    });

    test('web: mudar de separador (hidden→resumed) relê ao voltar', () {
      final portao = PortaoReleitura();
      final t0 = DateTime(2026, 11, 16, 18);
      portao.deveReler(AppLifecycleState.inactive, t0);
      portao.deveReler(AppLifecycleState.hidden, t0);
      expect(
          portao.deveReler(AppLifecycleState.inactive,
              t0.add(const Duration(seconds: 30))),
          isFalse);
      expect(
          portao.deveReler(
              AppLifecycleState.resumed, t0.add(const Duration(seconds: 30))),
          isTrue);
    });

    test('volta depois de 15 s relê outra vez', () {
      final portao = PortaoReleitura();
      final t0 = DateTime(2026, 11, 16, 18);
      portao.deveReler(AppLifecycleState.paused, t0);
      expect(portao.deveReler(AppLifecycleState.resumed, t0), isTrue);
      final t1 = t0.add(const Duration(seconds: 16));
      portao.deveReler(AppLifecycleState.paused, t1);
      expect(portao.deveReler(AppLifecycleState.resumed, t1), isTrue);
    });
  });

  group('ReligarComEspera (tempo real dos pedidos)', () {
    testWidgets('50 erros seguidos marcam uma só religação', (tester) async {
      final r = ReligarComEspera();
      var religacoes = 0;
      var marcadas = 0;
      for (var i = 0; i < 50; i++) {
        if (r.agendar(() => religacoes++)) marcadas++;
      }
      expect(marcadas, 1);
      await tester.pump(const Duration(seconds: 4));
      expect(religacoes, 0);
      await tester.pump(const Duration(seconds: 2));
      expect(religacoes, 1);
      r.cancelar();
    });

    testWidgets('espera cresce 5→10→20→40→60 s e volta aos 5 s com dados',
        (tester) async {
      final r = ReligarComEspera();
      final esperas = <int>[];
      for (var i = 0; i < 6; i++) {
        esperas.add(r.proximaEspera.inSeconds);
        r.agendar(() {});
        await tester.pump(r.maximo);
      }
      expect(esperas, [5, 10, 20, 40, 60, 60]);
      r.correuBem();
      expect(r.proximaEspera.inSeconds, 5);
    });

    testWidgets('em 10 min de erros sem parar: no máximo 14 religações',
        (tester) async {
      // Antes: uma religação a cada 5 s POR CANAL e os canais somavam-se
      // (13 904 leituras em 10 min). Agora: 5+10+20+40+60×n ≤ 600 s.
      final r = ReligarComEspera();
      var religacoes = 0;
      void falhar() {
        r.agendar(() {
          religacoes++;
          falhar(); // o canal novo também falha logo
        });
      }

      falhar();
      for (var s = 0; s < 600; s++) {
        await tester.pump(const Duration(seconds: 1));
      }
      expect(religacoes, lessThanOrEqualTo(14));
      r.cancelar();
    });

    testWidgets('cancelar desmarca a religação pendente', (tester) async {
      final r = ReligarComEspera();
      var religacoes = 0;
      r.agendar(() => religacoes++);
      r.cancelar();
      await tester.pump(const Duration(minutes: 2));
      expect(religacoes, 0);
      expect(r.agendada, isFalse);
    });
  });

  group('Versão mínima ao voltar à app', () {
    test('confere no máximo uma vez por hora', () {
      final t0 = DateTime(2026, 11, 16, 18);
      expect(AppUpdateService.deveConferirAoVoltar(null, t0), isTrue);
      expect(
          AppUpdateService.deveConferirAoVoltar(
              t0, t0.add(const Duration(minutes: 59))),
          isFalse);
      expect(
          AppUpdateService.deveConferirAoVoltar(
              t0, t0.add(const Duration(hours: 1))),
          isTrue);
    });
  });
}
