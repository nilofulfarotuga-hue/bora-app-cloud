import 'package:bora_app/models/credito_claude_model.dart' show LicaoRobo;
import 'package:bora_app/models/hermes_diretor_model.dart';
import 'package:bora_app/screens/admin/admin_licoes_robos_screen.dart';
import 'package:bora_app/stores/licoes_robos_store.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// [hermes-diretor B10] Lições dos robôs + casos de teste no painel. Fonte falsa: sem rede.
class _Fonte implements LicoesRobosFonte {
  _Fonte({this.licoesLista = const [], this.casosLista = const [], this.falha});

  final List<Map<String, dynamic>> licoesLista;
  final List<Map<String, dynamic>> casosLista;
  final Object? falha;
  final licaoAtiva = <String>[];
  final casoAtivo = <String>[];

  @override
  Future<List<Map<String, dynamic>>> licoes() async {
    if (falha != null) throw falha!;
    return licoesLista;
  }

  @override
  Future<List<Map<String, dynamic>>> casos() async {
    if (falha != null) throw falha!;
    return casosLista;
  }

  // Simula a RPC ainda por criar: o ecrã tem de calcular o resumo pelos casos.
  @override
  Future<Object?> resumoRegressao(String robo) async =>
      throw Exception('PGRST202: Could not find the function public.robos_regressao_resumo');

  @override
  Future<void> definirAtiva(LicaoRobo l, bool ativa) async => licaoAtiva.add('${l.id}:$ativa');

  @override
  Future<void> editar(LicaoRobo l, {required String errou, required String regra}) async {}

  @override
  Future<void> definirCasoAtivo(CasoTesteRobo c, bool ativo) async => casoAtivo.add('${c.id}:$ativo');
}

Map<String, dynamic> _licao(int id, String robo, {bool ativa = true, int vezes = 3}) => {
      'id': id,
      'criada_em': '2026-11-20T10:00:00Z',
      'robo': robo,
      'errou': 'Prometeu entrega grátis',
      'regra': 'Nunca prometer entrega grátis',
      'origem': 'fiscal',
      'vezes': vezes,
      'ativa': ativa,
    };

Map<String, dynamic> _caso(int id, String robo, String? resultado) => {
      'id': id,
      'robo': robo,
      'pergunta': 'A entrega é grátis?',
      'deve_conter': ['2,50'],
      'nao_pode_conter': ['grátis'],
      'ativo': true,
      'ultimo_resultado': resultado,
      'ultima_resposta': resultado == 'falhou' ? 'É grátis sim' : null,
      'ultima_corrida_em': resultado == null ? null : '2026-11-22T09:00:00Z',
    };

Future<void> _abrir(WidgetTester t, _Fonte f) async {
  t.view.physicalSize = const Size(1200, 3000);
  t.view.devicePixelRatio = 1.0;
  addTearDown(t.view.reset);
  await t.pumpWidget(MaterialApp(home: AdminLicoesRobosScreen(store: LicoesRobosStore(fonte: f))));
  await t.pumpAndSettle();
}

void main() {
  testWidgets('lista vazia: os 4 robôs aparecem sem lições nem testes', (t) async {
    await _abrir(t, _Fonte());
    expect(find.text('Suporte'), findsOneWidget);
    expect(find.text('Amigo Bora'), findsOneWidget);
    expect(find.text('WhatsApp das lojas'), findsOneWidget);
    expect(find.text('Hermes'), findsOneWidget);
    expect(find.textContaining('0 lições (0 ligadas) · sem casos de teste'), findsNWidgets(4));
  });

  testWidgets('com dados: lição com contador, casos de teste e resumo da regressão; ligar/desligar', (t) async {
    final f = _Fonte(
      licoesLista: [_licao(1, 'suporte', vezes: 4), _licao(2, 'suporte', ativa: false)],
      casosLista: [_caso(10, 'suporte', 'passou'), _caso(11, 'suporte', 'falhou'), _caso(12, 'suporte', null)],
    );
    await _abrir(t, f);
    expect(find.textContaining('4x · Nunca prometer entrega grátis'), findsOneWidget);
    expect(find.textContaining('2 lições (1 ligadas) · testes: 1 de 3 passaram'), findsOneWidget);
    expect(find.text('Passou'), findsOneWidget);
    expect(find.text('Falhou'), findsOneWidget);
    expect(find.text('Nunca corrido'), findsOneWidget);
    expect(find.textContaining('3 casos, 1 passaram, 1 falharam, 1 nunca corridos'), findsOneWidget);

    // Desligar a lição 1.
    await t.tap(find.descendant(of: find.byKey(const ValueKey('licao-1')), matching: find.byType(Switch)));
    await t.pumpAndSettle();
    expect(f.licaoAtiva, ['1:false']);

    // Desligar o caso 11.
    await t.tap(find.descendant(of: find.byKey(const ValueKey('caso-11')), matching: find.byType(Switch)));
    await t.pumpAndSettle();
    expect(f.casoAtivo, ['11:false']);
  });

  testWidgets('ainda não ligado no servidor: faixa calma, sem erro vermelho', (t) async {
    await _abrir(t, _Fonte(falha: Exception('PGRST205: Could not find the table public.licoes_robos')));
    expect(find.text('Esta parte ainda não foi ligada no servidor'), findsOneWidget);
    expect(find.textContaining('Não foi possível carregar'), findsNothing);
  });
}
