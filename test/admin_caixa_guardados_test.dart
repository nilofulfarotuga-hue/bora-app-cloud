import 'dart:io';

import 'package:bora_app/screens/admin/admin_caixa_guardados_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// [sistema-conteudo 14/11 · blocos 5.3 e 5.5] Caixa de guardados + Quadro Sim/Não no painel.
/// O ecrã recebe uma fonte falsa: renderiza sem Supabase inicializado.
class _FonteFalsa implements CaixaGuardadosFonte {
  _FonteFalsa({this.itens = const [], this.radar = const [], this.cortex = const [], this.ultimo});

  final List<Map<String, dynamic>> itens;
  final List<Map<String, dynamic>> radar;
  final List<Map<String, dynamic>>? cortex;
  Map<String, dynamic>? ultimo;
  int pedidos = 0;
  final atualizacoes = <Map<String, dynamic>>[];
  final radarDecisoes = <String>[];
  final cortexDecisoes = <String>[];

  @override
  Future<List<Map<String, dynamic>>> listar({String? estado, String? tipo}) async => itens
      .where((i) => (estado == null || i['estado'] == estado) && (tipo == null || i['tipo'] == tipo))
      .toList();

  @override
  Future<List<Map<String, dynamic>>> caixaPorDecidir() async =>
      itens.where((i) => kCaixaPorDecidir.contains(i['estado'])).toList();

  @override
  Future<List<Map<String, dynamic>>> radarPendentes() async => radar;

  @override
  Future<List<Map<String, dynamic>>?> cortexPendentes() async => cortex;

  @override
  Future<Map<String, dynamic>?> ultimoPedidoAgente() async => ultimo;

  @override
  Future<int> atualizar(int id, Map<String, dynamic> campos, {required String acao}) async {
    atualizacoes.add({'id': id, 'acao': acao, ...campos});
    return 1;
  }

  @override
  Future<void> correrAgora() async {
    pedidos++;
    ultimo = {'estado': 'aberta', 'origem': 'evento', 'created_at': '2026-11-14T10:00:00Z'};
  }

  @override
  Future<void> radarDecidir(String youtubeId, {required bool sim}) async =>
      radarDecisoes.add('$youtubeId:${sim ? 'sim' : 'nao'}');

  @override
  Future<void> cortexDecidir(String pid, {required bool sim}) async =>
      cortexDecisoes.add('$pid:${sim ? 'sim' : 'nao'}');
}

Map<String, dynamic> _item({int id = 7, String estado = 'guardado'}) => {
      'id': id,
      'criado_em': '2026-07-01T10:05:00Z', // verão: Lisboa = UTC+1
      'origem': 'claude-ai',
      'tipo': 'missao',
      'titulo': 'Missão de teste',
      'conteudo': 'texto',
      'prioridade': 2,
      'estado': estado,
    };

Future<void> _abrir(WidgetTester t, CaixaGuardadosFonte f) async {
  t.view.physicalSize = const Size(1200, 2400);
  t.view.devicePixelRatio = 1.0;
  addTearDown(t.view.reset);
  await t.pumpWidget(MaterialApp(home: AdminCaixaGuardadosScreen(key: UniqueKey(), fonte: f)));
  await t.pumpAndSettle();
}

ButtonStyleButton _botao(WidgetTester t, String texto) => t.widget<ButtonStyleButton>(
    find.ancestor(of: find.text(texto), matching: find.bySubtype<ButtonStyleButton>()).first);

void main() {
  testWidgets('tudo vazio renderiza sem Supabase; Correr agora ativo; separador Caixa toda', (t) async {
    await _abrir(t, _FonteFalsa());
    expect(find.text('Caixa de guardados'), findsOneWidget);
    expect(find.text('Esperando você (0)'), findsOneWidget);
    expect(find.text('Nada por decidir na caixa.'), findsOneWidget);
    expect(find.text('Nenhuma opção do radar à espera.'), findsOneWidget);
    expect(find.text('Nenhuma proposta do Córtex à espera.'), findsOneWidget);
    expect(find.text('Ainda não houve nenhum pedido ao agente de segunda.'), findsOneWidget);
    expect(_botao(t, 'Correr agora').onPressed, isNotNull);
    await t.tap(find.text('Caixa toda'));
    await t.pumpAndSettle();
    expect(find.text('Nada guardado com estes filtros.'), findsOneWidget);
  });

  testWidgets('item por decidir com data de Lisboa; agente a executar desliga o botão', (t) async {
    await _abrir(
      t,
      _FonteFalsa(
        itens: [_item()],
        ultimo: {'estado': 'executando', 'origem': 'painel-admin', 'created_at': '2026-11-14T10:00:00Z'},
      ),
    );
    expect(find.text('Esperando você (1)'), findsOneWidget);
    expect(find.text('Missão de teste'), findsOneWidget);
    expect(find.textContaining('01/07 11:05'), findsOneWidget);
    expect(find.textContaining('Executando agora'), findsOneWidget);
    expect(_botao(t, 'Correr agora').onPressed, isNull);
  });

  testWidgets('Correr agora pede confirmação e manda um pedido', (t) async {
    final f = _FonteFalsa();
    await _abrir(t, f);
    await t.tap(find.text('Correr agora'));
    await t.pumpAndSettle();
    expect(find.text('Correr o agente de segunda agora?'), findsOneWidget);
    await t.tap(find.descendant(of: find.byType(AlertDialog), matching: find.text('Correr agora')));
    await t.pumpAndSettle();
    expect(f.pedidos, 1);
    expect(find.textContaining('Na fila'), findsOneWidget);
  });

  testWidgets('Sim na caixa = aprovado + "sim (painel)"; Não no radar = rejeita', (t) async {
    final f = _FonteFalsa(
      itens: [_item()],
      radar: [
        {'youtube_id': 'abc123', 'titulo': 'Vídeo X', 'tema': 'Reels de bairro', 'nota_utilidade': 9, 'canal': 'C'},
      ],
    );
    await _abrir(t, f);
    expect(find.text('Esperando você (2)'), findsOneWidget);
    expect(find.text('Reels de bairro'), findsOneWidget);
    await t.tap(find.text('Sim').first);
    await t.pumpAndSettle();
    expect(f.atualizacoes.single['estado'], 'aprovado');
    expect(f.atualizacoes.single['decisao'], 'sim (painel)');
    expect(f.atualizacoes.single['acao'], 'quadro_caixa_sim');
    await t.tap(find.text('Não').last);
    await t.pumpAndSettle();
    expect(f.radarDecisoes, ['abc123:nao']);
  });

  testWidgets('Córtex: Sim pede confirmação; sem leitura mostra "ver no Córtex"', (t) async {
    final f = _FonteFalsa(cortex: [
      {'pid': 'p1', 'tarefa': 'Proposta vermelha', 'zona': 'vermelha', 'tipo': 'ordem', 'who': 'hermes'},
    ]);
    await _abrir(t, f);
    await t.tap(find.text('Sim'));
    await t.pumpAndSettle();
    expect(find.text('Aprovar esta proposta do Córtex?'), findsOneWidget);
    await t.tap(find.text('Aprovar'));
    await t.pumpAndSettle();
    expect(f.cortexDecisoes, ['p1:sim']);

    await _abrir(t, _FonteFalsa(cortex: null));
    expect(find.text('Propostas do Córtex: ver no Córtex'), findsOneWidget);
  });

  test('menu e rota ligados; o ecrã nunca apaga; inserts e RPCs certos', () {
    final menu = File('lib/screens/admin/admin_menu_registry.dart').readAsStringSync();
    expect(menu.contains('builder: () => const AdminCaixaGuardadosScreen()'), isTrue);
    final rotas = File('lib/main.dart').readAsStringSync();
    expect(rotas.contains("'/admin/caixa-guardados': (_) => const AdminCaixaGuardadosScreen()"), isTrue);
    final s = File('lib/screens/admin/admin_caixa_guardados_screen.dart').readAsStringSync();
    expect(s.contains('.delete('), isFalse, reason: 'sem DELETE no ecrã');
    expect(s.contains("'para': kCaixaAgente"), isTrue);
    expect(s.contains("const String kCaixaAgente = 'agente-segunda'"), isTrue);
    // O check despacho_origem_check só aceita danilo-telegram, claude-ai, relogio, evento, agente.
    expect(s.contains("const String kCaixaOrigemDespacho = 'evento'"), isTrue);
    expect(s.contains("'titulo': 'agente-segunda: correr agora \$kCaixaMarcaPainel'"), isTrue);
    expect(kCaixaMarcaPainel, '(painel admin)');
    expect(s.contains(".select('id')"), isTrue, reason: '0 linhas = erro, nunca "guardado"');
    expect(s.contains("rpc('admin_quadro_radar_decidir'"), isTrue);
    expect(s.contains("'p_status': 'decidida_fora'"), isTrue);
    final migracao = File('supabase/migrations/$kCaixaMigracao');
    expect(migracao.existsSync(), isTrue);
    final sql = migracao.readAsStringSync();
    expect(sql.contains('painel-admin'), isFalse, reason: 'o despacho não muda: origem evento');
    expect(sql.contains("values ('evento', 'emerson', 'tarefa',"), isTrue);
    expect(sql.contains("'aprovado'::text"), isTrue);
    expect(sql.contains('if not public.is_admin() then'), isTrue);
    expect(sql.contains('from anon'), isTrue);
  });
}
