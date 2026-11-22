import 'package:bora_app/screens/admin/admin_sentinela_screen.dart';
import 'package:bora_app/stores/sentinela_store.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// [hermes-diretor B10] Sentinela (o vigia do Hermes) no painel. Fonte falsa: sem rede.
class _Fonte implements SentinelaFonte {
  _Fonte({this.eventosLista = const [], this.tarefasLista = const [], this.falha});

  final List<Map<String, dynamic>> eventosLista;
  final List<Map<String, dynamic>> tarefasLista;
  final Object? falha;
  final vistos = <int>[];

  @override
  Future<List<Map<String, dynamic>>> eventos() async {
    if (falha != null) throw falha!;
    return eventosLista;
  }

  @override
  Future<List<Map<String, dynamic>>> tarefas(List<int> ids) async => tarefasLista;

  @override
  Future<void> marcarVisto(int id) async => vistos.add(id);
}

Map<String, dynamic> _ev(int id, String gravidade, String titulo,
        {int? despacho, String? tratadoEm, String tipo = 'pedido_parado'}) =>
    {
      'id': id,
      'criado_em': '2026-11-22T10:00:00Z',
      'tipo': tipo,
      'gravidade': gravidade,
      'titulo': titulo,
      'dados': <String, dynamic>{},
      'despacho_id': despacho,
      'tratado_em': tratadoEm,
      'tratado_por': tratadoEm == null ? null : 'admin',
    };

Future<void> _abrir(WidgetTester t, _Fonte f) async {
  t.view.physicalSize = const Size(1200, 2600);
  t.view.devicePixelRatio = 1.0;
  addTearDown(t.view.reset);
  await t.pumpWidget(MaterialApp(home: AdminSentinelaScreen(store: SentinelaStore(fonte: f))));
  await t.pumpAndSettle();
}

void main() {
  testWidgets('lista vazia: diz que está tudo calmo', (t) async {
    await _abrir(t, _Fonte());
    expect(find.textContaining('Está tudo calmo'), findsOneWidget);
  });

  testWidgets('com dados: por gravidade, com "o que o Hermes fez"; filtro e marcar como visto', (t) async {
    final f = _Fonte(
      eventosLista: [
        _ev(101, 'urgente', 'Pedido parado há 25 minutos', despacho: 5),
        _ev(102, 'normal', 'Carrinho abandonado', tipo: 'carrinho_abandonado'),
        _ev(103, 'info', 'Sistema reiniciado', tratadoEm: '2026-11-22T10:30:00Z', tipo: 'sistema'),
      ],
      tarefasLista: [
        {'id': 5, 'estado': 'concluida', 'resultado': 'Reatribuí o pedido'},
      ],
    );
    await _abrir(t, f);
    expect(find.text('Pedido parado há 25 minutos'), findsOneWidget);
    expect(find.text('Carrinho abandonado'), findsWidgets); // título + rótulo do tipo
    expect(find.text('Sistema reiniciado'), findsOneWidget);
    expect(find.textContaining('Tarefa número 5: concluida — Reatribuí o pedido'), findsOneWidget);
    expect(find.textContaining('Ainda sem tarefa'), findsNWidgets(2));
    expect(find.text('Urgente (1)'), findsOneWidget);
    expect(find.text('Informação (0)'), findsOneWidget, reason: 'o info já está visto');

    // Filtro: só urgentes.
    await t.tap(find.text('Urgente (1)'));
    await t.pumpAndSettle();
    expect(find.text('Pedido parado há 25 minutos'), findsOneWidget);
    expect(find.text('Sistema reiniciado'), findsNothing);

    // Marcar como visto chama a fonte com o id certo.
    await t.tap(find.text('Marcar como visto'));
    await t.pumpAndSettle();
    expect(f.vistos, [101]);
  });

  testWidgets('ainda não ligado no servidor: faixa calma, sem erro vermelho', (t) async {
    await _abrir(t, _Fonte(falha: Exception('42P01: relation "sentinela_eventos" does not exist')));
    expect(find.text('Esta parte ainda não foi ligada no servidor'), findsOneWidget);
    expect(find.textContaining('Não foi possível carregar'), findsNothing);
  });
}
