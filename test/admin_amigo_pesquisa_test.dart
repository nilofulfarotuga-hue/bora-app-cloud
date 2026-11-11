// Painel admin — secção "Pesquisa na internet" do Amigo (missão fechar-tudo-2026-11-11, bloco 2).
import 'package:bora_app/screens/admin/admin_amigo_pesquisa_secao.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Map<String, dynamic> _overview({bool ativo = true, int max = 3}) => {
      'hoje': {'pesquisas': 7, 'chamadas': 4, 'usd': 0.07},
      'mes': {'pesquisas': 123, 'chamadas': 80, 'usd': 1.23},
      'dia': '2026-11-11',
      'mes_inicio': '2026-11-01',
      'usd_por_pesquisa': 0.01,
      'definicoes': {
        'assistant_web_search_enabled': ativo,
        'assistant_web_search_max_uses': max,
      },
    };

Widget _app(Widget filho) => MaterialApp(
      home: Scaffold(body: SingleChildScrollView(padding: const EdgeInsets.all(16), child: filho)),
    );

void main() {
  testWidgets('pesquisas de hoje e do mês, interruptor e máximo por mensagem', (tester) async {
    tester.view.physicalSize = const Size(1100, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final gravados = <Map<String, Object>>[];
    await tester.pumpWidget(_app(AdminAmigoPesquisaSecao(
      carregar: () async => _overview(),
      definir: (m) async => gravados.add(m),
    )));
    await tester.pumpAndSettle();

    expect(find.text('Pesquisa na internet'), findsOneWidget);
    expect(find.descendant(of: find.byKey(const Key('admin-amigo-pesquisa-hoje')), matching: find.text('7')), findsOneWidget);
    expect(find.textContaining('4 respostas com pesquisa · US\$ 0.07'), findsOneWidget);
    expect(find.descendant(of: find.byKey(const Key('admin-amigo-pesquisa-mes')), matching: find.text('123')), findsOneWidget);
    expect(find.textContaining('US\$ 1.23'), findsOneWidget);
    expect(find.byKey(const Key('admin-amigo-pesquisa-sem-migracao')), findsNothing);
    final sw = tester.widget<SwitchListTile>(find.byKey(const Key('admin-amigo-pesquisa-ativo')));
    expect(sw.value, isTrue);

    // desligar
    await tester.tap(find.byKey(const Key('admin-amigo-pesquisa-ativo')));
    await tester.pumpAndSettle();
    expect(gravados.last, {'p_ativo': false});
    expect(find.textContaining('fica na auditoria'), findsOneWidget);

    // máximo por mensagem: 1 a 5
    await tester.tap(find.byKey(const Key('admin-amigo-pesquisa-max')));
    await tester.pumpAndSettle();
    for (final n in kAdminAmigoPesquisaUsos) {
      expect(find.text('$n'), findsWidgets);
    }
    await tester.tap(find.text('5').last);
    await tester.pumpAndSettle();
    expect(gravados.last, {'p_max_usos': 5});
  });

  testWidgets('sem a migração: aviso e nada se grava', (tester) async {
    tester.view.physicalSize = const Size(1100, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final gravados = <Map<String, Object>>[];
    await tester.pumpWidget(_app(AdminAmigoPesquisaSecao(
      carregar: () async => throw Exception('function admin_amigo_pesquisa_overview does not exist'),
      definir: (m) async => gravados.add(m),
    )));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('admin-amigo-pesquisa-sem-migracao')), findsOneWidget);
    final sw = tester.widget<SwitchListTile>(find.byKey(const Key('admin-amigo-pesquisa-ativo')));
    expect(sw.onChanged, isNull);
    await tester.tap(find.byKey(const Key('admin-amigo-pesquisa-ativo')));
    await tester.pumpAndSettle();
    expect(gravados, isEmpty);
  });
}
