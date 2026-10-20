// B2 (fechar-pendencias-2026-10-20) — o painel "KPIs de pesquisa" só tinha 1
// linha: só a lupa registava, e só ao tocar num resultado. O RegistoPesquisa é
// o que todos os ecrãs de pesquisa do cliente usam agora: não regista cada
// letra, não repete, envia o que ficou ao sair, e nunca parte a pesquisa
// quando a rede (ou a sessão) falha.
import 'package:bora_app/services/registo_pesquisa.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('regista uma vez depois de o cliente parar de escrever',
      (tester) async {
    final enviados = <String>[];
    final r = RegistoPesquisa(
      espera: const Duration(seconds: 2),
      enviar: (t) async => enviados.add(t),
    );
    for (final parcial in ['a', 'az', 'aze', 'azei', 'azeite']) {
      r.aoEscrever(parcial);
      await tester.pump(const Duration(milliseconds: 300));
    }
    expect(enviados, isEmpty, reason: 'nada enquanto escreve');
    await tester.pump(const Duration(seconds: 2));
    expect(enviados, ['azeite']);
    r.dispose();
  });

  testWidgets('não repete o mesmo texto e ignora 1 letra', (tester) async {
    final enviados = <String>[];
    final r = RegistoPesquisa(enviar: (t) async => enviados.add(t));
    r.registarJa('Leite');
    r.registarJa('leite ');
    r.registarJa('x');
    expect(enviados, ['Leite']);
    r.dispose();
  });

  testWidgets('ao sair do ecrã envia o que estava à espera', (tester) async {
    final enviados = <String>[];
    final r = RegistoPesquisa(
      espera: const Duration(seconds: 5),
      enviar: (t) async => enviados.add(t),
    );
    r.aoEscrever('papo-seco');
    await tester.pump(const Duration(seconds: 1));
    r.dispose();
    await tester.pump();
    expect(enviados, ['papo-seco']);
    await tester.pump(const Duration(seconds: 10));
    expect(enviados, ['papo-seco'], reason: 'o temporizador já não volta');
  });

  testWidgets('falha de rede não sobe para quem pesquisa', (tester) async {
    var tentativas = 0;
    final r = RegistoPesquisa(enviar: (t) async {
      tentativas++;
      throw Exception('sem rede');
    });
    expect(() => r.registarJa('pão'), returnsNormally);
    await tester.pump();
    expect(tentativas, 1);
    r.dispose();
  });

  testWidgets('sem Supabase iniciado (teste/arranque) também não parte',
      (tester) async {
    final r = RegistoPesquisa(); // usa o serviço real → falha e é engolida
    expect(() => r.registarJa('coxinha'), returnsNormally);
    await tester.pump();
    r.dispose();
  });
}
