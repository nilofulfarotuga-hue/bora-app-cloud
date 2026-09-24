import 'package:bora_app/config/app_theme.dart';
import 'package:bora_app/models/decisao_model.dart';
import 'package:bora_app/screens/admin/admin_decisoes_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'golden/fabrica_de_fotos.dart' show carregaFonteInter;

/// [jev-decisor-2026-09-23 · BLOCO 4] Ecrã "Decisões" (admin) + modelo `Decisao`.
///
/// O que estes testes trancam:
///  (a) o modelo lê a linha real de `decisoes` e diz se acertou (choice, noul, score);
///  (b) o cartão "Quanto custou hoje" soma os motores do resumo do servidor;
///  (c) só o Robot B oferece o modo "ativo" (despacho é zona protegida);
///  (d) tocar num modo chama `admin_decisor_set_modo` com a regra e o modo certos;
///  (e) os filtros por motor escondem o que não interessa;
///  (f) nada estoura a 360×800.
///
/// O ecrã recebe `carregar` e `chamarRpc` falsos: nunca toca no Supabase.
class _RpcFalso {
  final chamadas = <(String, Map<String, dynamic>)>[];

  Future<dynamic> call(String fn, Map<String, dynamic> params) async {
    chamadas.add((fn, Map<String, dynamic>.from(params)));
    return {'regra': params['p_regra'], 'antes': 'sombra', 'depois': params['p_modo']};
  }
}

Map<String, dynamic> _resumo() => {
      'hoje': {
        'jev': {'chamadas': 20, 'tokens_entrada': 6000, 'tokens_saida': 400, 'custo_usd': 0.000252, 'latencia_mediana_ms': 180},
        'gemini': {'chamadas': 5, 'tokens_entrada': 1500, 'tokens_saida': 90, 'custo_usd': 0, 'latencia_mediana_ms': 900},
      },
      'acerto': {
        'robotb:gemini': {'com_resultado': 4, 'acertou': 3},
      },
      'modos': {'despacho': 'sombra', 'noshow': 'sombra', 'robotb': 'sombra', 'suporte': 'desligado'},
      'tem_chave_jev': false,
      'preco_jev_usd_mtok': 0.042,
    };

List<Map<String, dynamic>> _linhas() {
  final agora = DateTime.now().toUtc().toIso8601String();
  return [
    {
      'id': 'd1', 'quando': agora, 'tipo': 'choice', 'pergunta': 'Which courier should get this job?',
      'resposta': 'estafeta_1', 'confianca': 0.81, 'probabilidades': {'estafeta_1': 0.9, 'estafeta_2': 0.1},
      'motor': 'jev', 'modelo': 'jev-1.13.0', 'latencia_ms': 150, 'tokens_entrada': 300, 'custo_usd': 0.0000126,
      'usado_por': 'despacho', 'contexto_id': 'ord-1', 'modo': 'sombra', 'resultado_real': 'estafeta_1',
    },
    {
      'id': 'd2', 'quando': agora, 'tipo': 'noul', 'pergunta': 'Worth opening?',
      'resposta': 'nao', 'confianca': 0.4, 'probabilidades': {'sim': 0.2, 'nao': 0.8},
      'motor': 'gemini', 'modelo': 'gemini-3.1-flash-lite', 'latencia_ms': 900,
      'usado_por': 'robotb', 'contexto_id': 's-1', 'modo': 'sombra', 'resultado_real': 'sim',
    },
    {
      'id': 'd3', 'quando': agora, 'tipo': 'score', 'pergunta': 'No-show risk?',
      'resposta': '', 'motor': 'nenhum', 'usado_por': 'noshow', 'modo': 'sombra',
      'erro': 'jev_sem_chave | gemini http 503',
    },
  ];
}

Future<_RpcFalso> _abrir(WidgetTester tester, {Size tamanho = const Size(1024, 768)}) async {
  tester.view.physicalSize = tamanho;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final rpc = _RpcFalso();
  await tester.pumpWidget(MaterialApp(
    theme: AppTheme.lightTheme,
    home: AdminDecisoesScreen(
      carregar: () async => (_resumo(), _linhas()),
      chamarRpc: rpc.call,
    ),
  ));
  await tester.pumpAndSettle();
  return rpc;
}

void main() {
  setUpAll(carregaFonteInter);

  group('modelo Decisao', () {
    test('(a) choice acerta quando a opção escolhida foi quem ficou com o trabalho', () {
      final d = Decisao.fromMap(_linhas()[0]);
      expect(d.respostaLegivel, 'estafeta_1');
      expect(d.probabilidades['estafeta_2'], 0.1);
      expect(d.acertou, isTrue);
    });

    test('(a) noul "nao" contra resultado "sim" é erro; sem decisão não conta', () {
      expect(Decisao.fromMap(_linhas()[1]).acertou, isFalse);
      final falhou = Decisao.fromMap(_linhas()[2]);
      expect(falhou.acertou, isNull);
      expect(falhou.respostaLegivel, 'sem decisão');
    });

    test('(a) score de no-show: nota >= 2 acerta se a pessoa faltou', () {
      Decisao nota(String r, String real) => Decisao.fromMap({
            'id': 'x', 'quando': DateTime.now().toIso8601String(), 'tipo': 'score', 'pergunta': 'p',
            'resposta': r, 'motor': 'gemini', 'usado_por': 'noshow', 'modo': 'sombra', 'resultado_real': real,
          });
      expect(nota('2.6', 'faltou').acertou, isTrue);
      expect(nota('0.4', 'compareceu').acertou, isTrue);
      expect(nota('0.4', 'faltou').acertou, isFalse);
      expect(nota('3.1', 'compareceu').acertou, isFalse);
    });

    test('(b) custo e contagens de hoje somam todos os motores', () {
      final hoje = Map<String, dynamic>.from(_resumo()['hoje'] as Map);
      expect(custoHojeUsd(hoje), closeTo(0.000252, 1e-12));
      expect(somaHoje(hoje, 'chamadas'), 25);
      expect(somaHoje(hoje, 'tokens_entrada'), 7500);
      expect(custoHojeUsd(null), 0);
    });

    test('(c) só o Robot B aceita modo ativo', () {
      expect(regraAceitaAtivo('robotb'), isTrue);
      expect(regraAceitaAtivo('despacho'), isFalse);
      expect(regraAceitaAtivo('noshow'), isFalse);
      expect(regraAceitaAtivo('suporte'), isFalse);
    });

    test('(e) filtro por motor e por regra', () {
      final todas = _linhas().map(Decisao.fromMap).toList();
      expect(filtrarDecisoes(todas, motor: 'jev').map((d) => d.id), ['d1']);
      expect(filtrarDecisoes(todas, usadoPor: 'noshow').map((d) => d.id), ['d3']);
      expect(filtrarDecisoes(todas).length, 3);
    });

    // (f) fallback (fecho-manha-2026-09-24): os dois motores falharam e valeu a regra
    // determinística — conta-se à parte, filtra-se à parte e a resposta aparece (não é "sem decisão").
    test('(f) fallback conta-se e filtra-se à parte; a resposta da regra aparece', () {
      final todas = [
        ..._linhas(),
        {
          'id': 'd4', 'quando': DateTime.now().toIso8601String(), 'tipo': 'choice',
          'pergunta': 'Which courier should get this job?', 'resposta': 'estafeta_1',
          'motor': 'fallback', 'modelo': 'regra-deterministica', 'latencia_ms': 0,
          'usado_por': 'despacho', 'modo': 'sombra', 'erro': 'jev_sem_chave | gemini http 429',
          'probabilidades': {'estafeta_1': 1, 'estafeta_2': 0},
        },
      ].map(Decisao.fromMap).toList();
      expect(contarFallbacks(todas), 1);
      expect(contarFallbacks(_linhas().map(Decisao.fromMap).toList()), 0);
      expect(filtrarDecisoes(todas, motor: 'fallback').map((d) => d.id), ['d4']);
      expect(filtrarDecisoes(todas, motor: 'fallback').single.respostaLegivel, 'estafeta_1');
      expect(filtrarDecisoes(todas).length, 4);
    });
  });

  group('ecrã', () {
    testWidgets('(b)(c) mostra o custo, o aviso de sem chave e o ativo só no Robot B', (tester) async {
      await _abrir(tester);
      expect(find.text('Quanto custou hoje'), findsOneWidget);
      expect(find.text('0.000252'), findsOneWidget);
      expect(find.text('SEM chave — usando Gemini'), findsOneWidget);
      expect(find.byKey(const ValueKey('modo_robotb_ativo')), findsOneWidget);
      expect(find.byKey(const ValueKey('modo_despacho_ativo')), findsNothing);
      expect(find.textContaining('zona protegida'), findsOneWidget);
    });

    testWidgets('(d) tocar em "ativo" do Robot B chama o RPC certo', (tester) async {
      final rpc = await _abrir(tester);
      await tester.tap(find.byKey(const ValueKey('modo_robotb_ativo')));
      await tester.pumpAndSettle();
      expect(rpc.chamadas.single.$1, 'admin_decisor_set_modo');
      expect(rpc.chamadas.single.$2, {'p_regra': 'robotb', 'p_modo': 'ativo'});
      expect(find.textContaining('agora em "ativo"'), findsOneWidget);
    });

    testWidgets('(e) filtro "jev" deixa só a decisão do Jev', (tester) async {
      // Ecrã alto: a lista é preguiçosa e as linhas fora de vista nem são construídas.
      await _abrir(tester, tamanho: const Size(1024, 2400));
      expect(find.textContaining('Risco de falta na marcação · sem decisão'), findsOneWidget);
      final chipJev = find.widgetWithText(ChoiceChip, 'jev');
      await tester.ensureVisible(chipJev);
      await tester.tap(chipJev);
      await tester.pumpAndSettle();
      expect(find.textContaining('Escolha do entregador/motorista · estafeta_1'), findsOneWidget);
      expect(find.textContaining('Risco de falta na marcação · sem decisão'), findsNothing);
    });

    testWidgets('(f) a 360×800 nada estoura', (tester) async {
      await _abrir(tester, tamanho: const Size(360, 800));
      expect(tester.takeException(), isNull);
      await tester.drag(find.byType(Scrollable).first, const Offset(0, -1500));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });
  });
}
