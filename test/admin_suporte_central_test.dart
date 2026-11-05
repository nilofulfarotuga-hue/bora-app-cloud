// Central do robô do suporte (05/11/2026): conversas com ferramentas, perguntas sem
// resposta e ajustes. Sem as RPCs no servidor mostra o erro e não rebenta.
import 'package:bora_app/screens/admin/admin_suporte_central_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class _Falsa extends SuporteCentralApi {
  const _Falsa({this.falha = false, this.chamadas});
  final bool falha;
  final List<String>? chamadas;

  @override
  Future<List<Map<String, dynamic>>> conversas(int dias) async {
    if (falha) throw Exception('function does not exist');
    return [
      {
        'id': 's1', 'nome': 'Cliente Demo', 'papel': 'client', 'quando': '2026-11-05T13:54:00Z',
        'primeira': 'porque não me descontaram os tokens?', 'ferramentas': ['agent_get_order_full'],
        'passou_a_equipa': false, 'mensagens': 2,
      }
    ];
  }

  @override
  Future<List<Map<String, dynamic>>> conversa(String id) async => [
        {'papel': 'user', 'texto': 'porque não me descontaram os tokens?'},
        {'papel': 'tool', 'ferramenta': 'agent_get_order_full', 'entrada': {'p_order': '#9124CF'}, 'saida': {'ok': true}},
        {'papel': 'assistant', 'texto': 'Total 19,46 €, menos tokens 2,63 €, cobrado 16,83 €.'},
      ];

  @override
  Future<List<Map<String, dynamic>>> semResposta(int dias) async => [
        {'pergunta': 'como faço X?', 'quando': '2026-11-05T13:54:00Z', 'motivo': 'passou à equipa', 'resposta': 'Vou confirmar.'}
      ];

  @override
  Future<Map<String, dynamic>> config() async => {
        'modelo': 'gemini-3.5-flash-lite',
        'ferramentas_desligadas': <String>[],
        'skills': [
          {'nome': 'ORDER_STATUS', 'ativa': true, 'modo': 'read_only'}
        ],
      };

  @override
  Future<bool> definir(String tipo, String nome, String valor) async {
    chamadas?.add('$tipo:$nome:$valor');
    return true;
  }
}

void main() {
  Future<void> abrir(WidgetTester t, SuporteCentralApi api) async {
    t.view.physicalSize = const Size(1000, 1800);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    await t.pumpWidget(MaterialApp(home: AdminSuporteCentralScreen(api: api)));
    await t.pumpAndSettle();
  }

  testWidgets('conversa mostra a ferramenta que o robô usou', (t) async {
    await abrir(t, const _Falsa());
    expect(find.textContaining('Cliente Demo'), findsOneWidget);
    await t.tap(find.byKey(const Key('conversa_s1')));
    await t.pumpAndSettle();
    expect(find.textContaining('Ferramenta: agent_get_order_full'), findsOneWidget);
    expect(find.textContaining('cobrado 16,83'), findsOneWidget);
  });

  testWidgets('sem resposta lista a pergunta com o botão de propor', (t) async {
    await abrir(t, const _Falsa());
    await t.tap(find.text('Sem resposta'));
    await t.pumpAndSettle();
    expect(find.textContaining('como faço X?'), findsOneWidget);
    expect(find.byKey(const Key('propor_0')), findsOneWidget);
  });

  testWidgets('desligar uma ferramenta chama o servidor', (t) async {
    final chamadas = <String>[];
    await abrir(t, _Falsa(chamadas: chamadas));
    await t.tap(find.text('Ajustes'));
    await t.pumpAndSettle();
    await t.tap(find.byKey(const Key('ferramenta_agent_get_store_info')));
    await t.pumpAndSettle();
    expect(chamadas, ['ferramenta:agent_get_store_info:desligar']);
  });

  testWidgets('sem as funções no servidor mostra o erro', (t) async {
    await abrir(t, const _Falsa(falha: true));
    expect(find.textContaining('Não foi possível carregar'), findsOneWidget);
  });
}
