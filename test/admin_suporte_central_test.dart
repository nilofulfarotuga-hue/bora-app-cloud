// Central do robô do suporte (05/11/2026): conversas com ferramentas, perguntas sem
// resposta e ajustes. Sem as RPCs no servidor mostra o erro e não rebenta.
// 15/11/2026 (auditoria S6): as conversas vêm de admin_suporte_sessoes (traduzidas por
// SuporteCentralApi.linhaDaSessao) e abrir uma usa admin_suporte_conversa(p_session_id).
import 'package:bora_app/screens/admin/_admin_rpc_errors.dart';
import 'package:bora_app/screens/admin/admin_suporte_central_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// O que o servidor devolve quando a função ainda não foi instalada.
const _semFuncao = PostgrestException(
  message: 'Could not find the function public.admin_suporte_sem_resposta(p_dias) in the schema cache',
  code: 'PGRST202',
);

class _Falsa extends SuporteCentralApi {
  const _Falsa({this.falha = false, this.chamadas, this.semFuncoesDaProposta = false});
  final bool falha;
  final List<String>? chamadas;

  /// Como em produção a 15/11: sessões e conversa existem, o resto da proposta não.
  final bool semFuncoesDaProposta;

  @override
  Future<List<Map<String, dynamic>>> conversas() async {
    if (falha) throw Exception('function does not exist');
    // Uma linha tal como admin_suporte_sessoes a devolve.
    return [
      SuporteCentralApi.linhaDaSessao({
        'session_id': 's1', 'user_id': 'u1', 'nome': 'Cliente Demo', 'telefone': null, 'papel': 'client',
        'iniciada_em': '2026-11-05T13:54:00Z', 'ultima_msg_em': '2026-11-05T13:56:00Z',
        'ultima_msg': 'porque não me descontaram os tokens?', 'ultima_msg_papel': 'user',
        'mensagens': 3, 'escalada': false, 'modo': 'bot', 'nao_lida': true, 'ticket_id': null,
      }),
    ];
  }

  @override
  Future<List<Map<String, dynamic>>> conversa(String id) async {
    chamadas?.add('conversa:$id');
    // Tal como admin_suporte_conversa: as de ferramenta não trazem texto nem entrada/saída.
    return SuporteCentralApi.mensagensDaConversa({
      'ok': true,
      'mensagens': [
        {'id': 1, 'papel': 'user', 'texto': 'porque não me descontaram os tokens?', 'ferramenta': null},
        {'id': 2, 'papel': 'tool', 'texto': null, 'ferramenta': 'agent_get_order_full'},
        {'id': 3, 'papel': 'assistant', 'texto': 'Total 19,46 €, menos tokens 2,63 €, cobrado 16,83 €.'},
        {'id': 4, 'papel': 'admin', 'texto': 'Já confirmámos o desconto.'},
      ],
    });
  }

  @override
  Future<List<Map<String, dynamic>>> semResposta(int dias) async {
    if (semFuncoesDaProposta) throw _semFuncao;
    return [
      {'pergunta': 'como faço X?', 'quando': '2026-11-05T13:54:00Z', 'motivo': 'passou à equipa', 'resposta': 'Vou confirmar.'}
    ];
  }

  @override
  Future<Map<String, dynamic>> config() async {
    if (semFuncoesDaProposta) throw _semFuncao;
    return {
      'modelo': 'gemini-3.5-flash-lite',
      'ferramentas_desligadas': <String>[],
      'skills': [
        {'nome': 'ORDER_STATUS', 'ativa': true, 'modo': 'read_only'}
      ],
    };
  }

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

  test('linhaDaSessao traduz os campos de admin_suporte_sessoes', () {
    final l = SuporteCentralApi.linhaDaSessao({
      'session_id': '6b5aa568-9516-4f06-8167-85ecca48a439',
      'iniciada_em': '2026-11-15T10:00:00Z',
      'escalada': true,
      'ultima_msg': 'quero falar com uma pessoa',
      'nome': 'Ana',
    });
    expect(l['id'], '6b5aa568-9516-4f06-8167-85ecca48a439');
    expect(l['quando'], '2026-11-15T10:00:00Z');
    expect(l['passou_a_equipa'], isTrue);
    expect(l['ultima'], 'quero falar com uma pessoa');
    expect(l['nome'], 'Ana');
    expect(SuporteCentralApi.linhaDaSessao({'session_id': 'x'})['passou_a_equipa'], isFalse);
  });

  test('mensagensDaConversa lê a lista "mensagens" do objeto do servidor', () {
    expect(SuporteCentralApi.mensagensDaConversa({'ok': false, 'erro': 'conversa não encontrada'}), isEmpty);
    expect(SuporteCentralApi.mensagensDaConversa(null), isEmpty);
    final m = SuporteCentralApi.mensagensDaConversa({
      'ok': true,
      'mensagens': [
        {'id': 1, 'papel': 'user', 'texto': 'olá'},
      ],
    });
    expect(m.single['texto'], 'olá');
  });

  testWidgets('conversa mostra a última mensagem, a ferramenta e a resposta da equipa', (t) async {
    final chamadas = <String>[];
    await abrir(t, _Falsa(chamadas: chamadas));
    expect(find.textContaining('Cliente Demo'), findsOneWidget);
    expect(find.textContaining('Última mensagem: porque não me descontaram'), findsOneWidget);
    expect(find.text('3 msg.'), findsOneWidget);
    await t.tap(find.byKey(const Key('conversa_s1')));
    await t.pumpAndSettle();
    expect(chamadas.toSet(), {'conversa:s1'});
    expect(find.textContaining('Ferramenta: agent_get_order_full'), findsOneWidget);
    expect(find.textContaining('Conta completa do pedido'), findsOneWidget);
    expect(find.textContaining('cobrado 16,83'), findsOneWidget);
    expect(find.textContaining('Equipa Bora: Já confirmámos'), findsOneWidget);
    // a ferramenta sem entrada/saída explica que o servidor ainda não as mostra
    await t.tap(find.textContaining('Ferramenta: agent_get_order_full'));
    await t.pumpAndSettle();
    expect(find.textContaining('ainda não mostra o que a ferramenta pediu'), findsOneWidget);
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

  testWidgets('como em produção: conversas abrem, "Sem resposta" e "Ajustes" dizem que falta instalar',
      (t) async {
    await abrir(t, const _Falsa(semFuncoesDaProposta: true));
    expect(find.textContaining('Cliente Demo'), findsOneWidget);
    await t.tap(find.text('Sem resposta'));
    await t.pumpAndSettle();
    expect(find.textContaining('ainda não foi instalada no servidor'), findsOneWidget);
    expect(find.textContaining('PGRST202'), findsNothing);
    await t.tap(find.text('Ajustes'));
    await t.pumpAndSettle();
    expect(find.textContaining('ainda não foi instalada no servidor'), findsOneWidget);
  });

  test('mensagemDoErroCentral: função em falta, erro do servidor e erro qualquer', () {
    expect(mensagemDoErroCentral(_semFuncao), contains('ainda não foi instalada'));
    // os outros erros do servidor passam pelo tradutor comum do painel
    const semAdmin = PostgrestException(message: 'admin_required');
    expect(mensagemDoErroCentral(semAdmin), humanizeAdminRpcError(semAdmin));
    expect(mensagemDoErroCentral(Exception('x'), acao: 'guardar'), startsWith('Não foi possível guardar.'));
  });
}
