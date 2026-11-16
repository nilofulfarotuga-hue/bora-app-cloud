// Missão noite-farmacia-17-11, 1.1 — painel do robô Glovo das farmácias, testes sem rede.
import 'package:bora_app/screens/admin/admin_farmacias_screen.dart';
import 'package:bora_app/screens/admin/admin_menu_registry.dart';
import 'package:bora_app/screens/admin/admin_robo_glovo_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Map<String, dynamic> _estado({bool ligado = true, List<Map<String, dynamic>> corridas = const []}) => {
      'ligado': ligado,
      'lojas': ['farmacia-se-guarda', 'farmacia-teixeira-guarda'],
      'corridas': corridas,
      'ignorados': 5,
    };

final _ok = <String, dynamic>{
  'id': 2,
  'loja': 'farmacia-se-guarda',
  'origem': 'agendado',
  'estado': 'ok',
  'iniciada_em': '2026-11-17T07:30:00Z',
  'lidos': 870,
  'conhecidos': 862,
  'cobertura': 99.4,
  'pedidos_glovo': 190,
  'mudou_preco': 12,
  'esgotou': 3,
  'voltou': 0,
  'novos': 2,
  'mao': 1,
  'suspeitos': 0,
  'exemplos': {
    'precos': [
      {'nome': 'NUXE PRODIGIEUSE OL SECO FLORAL 50ML', 'de': 24.08, 'para': 24.5},
    ],
    'esgotados': [
      {'nome': 'KLORANE CAPILAR FIGO INDIA CH 400ML', 'porque': 'esgotado na Glovo'},
    ],
  },
};

final _abortada = <String, dynamic>{
  'id': 1,
  'loja': 'farmacia-teixeira-guarda',
  'origem': 'manual',
  'estado': 'abortada',
  'iniciada_em': '2026-11-16T21:00:00Z',
  'lidos': 120,
  'conhecidos': 511,
  'cobertura': 23.5,
  'erro': 'Leitura da Glovo com 23.5% dos produtos (mínimo 80%): 120 de 511. Nada foi mudado.',
};

Future<void> _abrir(WidgetTester t, Map<String, dynamic> estado) async {
  t.view.physicalSize = const Size(900, 2200);
  t.view.devicePixelRatio = 1.0;
  addTearDown(t.view.reset);
  await t.pumpWidget(MaterialApp(home: AdminRoboGlovoScreen(carregar: () async => estado)));
  await t.pumpAndSettle();
}

void main() {
  testWidgets('mostra ligado, botão Atualizar agora e as leituras com contagens', (t) async {
    await _abrir(t, _estado(corridas: [_ok, _abortada]));
    expect(find.text('Robô ligado'), findsOneWidget);
    expect(find.text('Atualizar agora'), findsOneWidget);
    expect(find.textContaining('Farmácia da Sé'), findsWidgets);
    expect(find.textContaining('Preço mudou: 12'), findsOneWidget);
    expect(find.textContaining('Não aplicada (leitura incompleta)'), findsOneWidget);
    expect(find.textContaining('Nada foi mudado'), findsOneWidget);
    // exemplos abrem ao tocar
    await t.tap(find.textContaining('Farmácia da Sé ·'));
    await t.pumpAndSettle();
    expect(find.textContaining('NUXE PRODIGIEUSE OL SECO FLORAL 50ML'), findsOneWidget);
    expect(find.textContaining('esgotado na Glovo'), findsOneWidget);
  });

  testWidgets('desligado: diz que não lê e o botão fica apagado', (t) async {
    await _abrir(t, _estado(ligado: false));
    expect(find.text('Robô desligado'), findsOneWidget);
    expect(find.text('Ainda não houve leituras.'), findsOneWidget);
    final b = t.widget<ButtonStyleButton>(find.byKey(const Key('robo_glovo_agora')));
    expect(b.onPressed, isNull);
  });

  testWidgets('leitura a correr: botão mostra que está a ler', (t) async {
    await _abrir(t, _estado(corridas: [
      {'id': 3, 'loja': 'farmacia-se-guarda', 'origem': 'manual', 'estado': 'a_correr', 'iniciada_em': '2026-11-17T08:00:00Z', 'categoria_atual': 20, 'categorias': 76, 'lidos': 300},
    ]));
    expect(find.text('A ler a Glovo…'), findsOneWidget);
    expect(find.textContaining('Categoria 20 de 76'), findsOneWidget);
  });

  test('selo da farmácia: escondida, em breve e aberta', () {
    expect(estadoPublicoFarmacia({'so_lista_permissao': true, 'coming_soon': false}), 'Escondida (só a lista)');
    expect(estadoPublicoFarmacia({'so_lista_permissao': false, 'coming_soon': true}), 'Em breve (todos veem, sem pedidos)');
    expect(estadoPublicoFarmacia({'so_lista_permissao': false, 'coming_soon': false}), 'Aberta ao público');
  });

  test('o robô está no menu do painel (paridade admin)', () {
    final item = adminMenuAllItems().where((i) => i.id == 'farmacias_robo_glovo');
    expect(item, hasLength(1));
    expect(item.first.title, 'Robô Glovo das farmácias');
  });
}
