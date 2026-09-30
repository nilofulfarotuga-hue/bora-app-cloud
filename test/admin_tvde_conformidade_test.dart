// [tvde-conformidade-lei-59-2026] Painel admin "Conformidade TVDE (IMT/AMT)".
//
// O que estes testes fecham (sem Supabase — a função das RPCs é injetada):
//  1. Interruptores: o mestre aparece no topo com a explicação "Enquanto o
//     mestre estiver desligado nenhuma regra nova muda a app", os contadores
//     do resumo aparecem, o preço fixo tem o aviso vermelho, e ligar o mestre
//     pede confirmação e chama admin_tvde_conf_set(p_key, p_value=true).
//  2. Checklist: contagem "X verdes de Y", agrupado por área, bolinha com a
//     cor do estado, e tocar num requisito grava admin_tvde_requisito_estado
//     com o estado e a nota escolhidos.
//  3. O ecrã principal abre com o título e os 12 separadores.
//  4. As peças puras: euros em cêntimos, jsonb booleano, CSV da fiscalização.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:bora_app/screens/admin/admin_tvde_conformidade_screen.dart';
import 'package:bora_app/screens/admin/tvde_conformidade/_comum.dart';
import 'package:bora_app/screens/admin/tvde_conformidade/checklist_tab.dart';
import 'package:bora_app/screens/admin/tvde_conformidade/fiscalizacao_tab.dart';
import 'package:bora_app/screens/admin/tvde_conformidade/interruptores_tab.dart';

class _FakeRpc {
  _FakeRpc(this.respostas);

  final Map<String, dynamic Function(Map<String, dynamic>? p)> respostas;
  final List<(String, Map<String, dynamic>?)> chamadas = [];

  Future<dynamic> call(String funcao, [Map<String, dynamic>? params]) async {
    chamadas.add((funcao, params));
    final r = respostas[funcao];
    return r == null ? const [] : r(params);
  }

  List<Map<String, dynamic>?> de(String funcao) =>
      [for (final c in chamadas) if (c.$1 == funcao) c.$2];
}

Map<String, dynamic> _resumo({bool mestre = false}) => {
      'interruptores': [
        {
          'key': 'tvde_compliance_enforce',
          'value': mestre,
          'description': 'INTERRUPTOR MESTRE da conformidade TVDE.',
          'category': 'tvde_conformidade',
        },
        {
          'key': 'tvde_fixed_price_option_enabled',
          'value': false,
          'description': 'Opção de preço fixo. PROPOSTA.',
          'category': 'tvde_conformidade',
        },
        {
          'key': 'tvde_horas_max_24h',
          'value': 10,
          'description': 'Máximo de horas de trabalho em 24h.',
          'category': 'tvde_conformidade',
        },
        {
          'key': 'plataforma_nome',
          'value': 'Bora',
          'description': 'Nome da plataforma.',
          'category': 'geral',
        },
      ],
      'operadores': 2,
      'operadores_aprovados': 1,
      'veiculos': 4,
      'veiculos_pendentes': 2,
      'motoristas': 7,
      'motoristas_com_impedimentos': 3,
      'queixas_abertas': 1,
      'sos_7d': 0,
      'acima_teto': 5,
      'requisitos': {'verde': 1, 'amarelo': 1, 'vermelho': 1},
    };

final List<Map<String, dynamic>> _requisitos = [
  {
    'codigo': 'licenca_plataforma',
    'ordem': 1,
    'area': 'Licenciamento',
    'requisito': 'Licença de plataforma TVDE no IMT',
    'base_legal': 'Lei 45/2018, art. 17.º',
    'estado': 'vermelho',
    'o_que_falta': 'Constituir a empresa',
    'interruptor': null,
  },
  {
    'codigo': 'teto_intermediacao',
    'ordem': 2,
    'area': 'Preços',
    'requisito': 'Intermediação até 25%',
    'base_legal': 'Lei 59/2026',
    'estado': 'verde',
    'o_que_falta': null,
    'interruptor': 'tvde_compliance_enforce',
  },
  {
    'codigo': 'livro_reclamacoes',
    'ordem': 3,
    'area': 'Licenciamento',
    'requisito': 'Livro de reclamações eletrónico',
    'base_legal': 'DL 156/2005',
    'estado': 'amarelo',
    'o_que_falta': 'Falta o link',
    'interruptor': null,
  },
];

Future<void> _pump(WidgetTester tester, Widget ecra) async {
  tester.view.physicalSize = const Size(1024, 2400);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(MaterialApp(home: Scaffold(body: ecra)));
  await tester.pumpAndSettle();
}

void main() {
  group('separador Interruptores', () {
    testWidgets('mestre no topo, contadores e aviso do preço fixo', (tester) async {
      final rpc = _FakeRpc({'admin_tvde_conf_resumo': (_) => _resumo()});
      await _pump(tester, TvdeInterruptoresTab(rpc: rpc.call));

      expect(find.byKey(const Key('tvde-mestre')), findsOneWidget);
      expect(find.text(kTvdeTextoMestre), findsOneWidget);
      expect(find.text('DESLIGADO'), findsOneWidget);

      // Contadores do resumo.
      expect(find.byKey(const Key('tvde-contador-motoristas_com_impedimentos')),
          findsOneWidget);
      expect(find.text('Motoristas com impedimentos'), findsOneWidget);
      expect(find.text('Corridas acima do teto de 25%'), findsOneWidget);
      expect(find.text('3'), findsWidgets);

      // Preço fixo com aviso vermelho.
      final aviso = tester.widget<Text>(find.byKey(const Key('tvde-aviso-preco-fixo')));
      expect(aviso.data, kTvdeAvisoPrecoFixo);
      expect(aviso.style?.color, isNotNull);

      // Número e texto têm campo editável; bool tem Switch.
      expect(find.byKey(const Key('tvde-campo-tvde_horas_max_24h')), findsOneWidget);
      expect(find.byKey(const Key('tvde-campo-plataforma_nome')), findsOneWidget);
      expect(find.byKey(const Key('tvde-switch-tvde_fixed_price_option_enabled')),
          findsOneWidget);
    });

    testWidgets('ligar o mestre pede confirmação e grava com admin_tvde_conf_set',
        (tester) async {
      final rpc = _FakeRpc({
        'admin_tvde_conf_resumo': (_) => _resumo(),
        'admin_tvde_conf_set': (p) =>
            {'ok': true, 'key': p!['p_key'], 'value': p['p_value']},
      });
      await _pump(tester, TvdeInterruptoresTab(rpc: rpc.call));

      await tester.tap(find.byKey(const Key('tvde-switch-tvde_compliance_enforce')));
      await tester.pumpAndSettle();
      expect(find.text('Ligar o interruptor mestre?'), findsOneWidget);

      // Cancelar não grava nada.
      await tester.tap(find.text('Cancelar'));
      await tester.pumpAndSettle();
      expect(rpc.de('admin_tvde_conf_set'), isEmpty);

      await tester.tap(find.byKey(const Key('tvde-switch-tvde_compliance_enforce')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Confirmar'));
      await tester.pumpAndSettle();

      final sets = rpc.de('admin_tvde_conf_set');
      expect(sets, hasLength(1));
      expect(sets.single, {'p_key': 'tvde_compliance_enforce', 'p_value': true});
      expect(find.textContaining('LIGADO'), findsOneWidget);
    });

    testWidgets('um número grava como número', (tester) async {
      final rpc = _FakeRpc({
        'admin_tvde_conf_resumo': (_) => _resumo(),
        'admin_tvde_conf_set': (p) =>
            {'ok': true, 'key': p!['p_key'], 'value': p['p_value']},
      });
      await _pump(tester, TvdeInterruptoresTab(rpc: rpc.call));

      await tester.enterText(find.byKey(const Key('tvde-campo-tvde_horas_max_24h')), '12');
      await tester.tap(find.byKey(const Key('tvde-gravar-tvde_horas_max_24h')));
      await tester.pumpAndSettle();

      expect(rpc.de('admin_tvde_conf_set').single,
          {'p_key': 'tvde_horas_max_24h', 'p_value': 12});
    });
  });

  group('separador Checklist', () {
    testWidgets('contagem, grupos por área e bolinhas com a cor do estado',
        (tester) async {
      final rpc = _FakeRpc({'admin_tvde_requisitos': (_) => _requisitos});
      await _pump(tester, TvdeChecklistTab(rpc: rpc.call));

      expect(find.text('1 verdes de 3'), findsOneWidget);
      expect(find.text('1 amarelos · 1 vermelhos'), findsOneWidget);
      expect(find.text('Licenciamento'), findsOneWidget);
      expect(find.text('Preços'), findsOneWidget);
      expect(find.byKey(const Key('tvde-bolinha-licenca_plataforma-vermelho')),
          findsOneWidget);
      expect(find.byKey(const Key('tvde-bolinha-teto_intermediacao-verde')),
          findsOneWidget);
      expect(find.byKey(const Key('tvde-bolinha-livro_reclamacoes-amarelo')),
          findsOneWidget);
      expect(find.text('Base legal: Lei 45/2018, art. 17.º'), findsOneWidget);
      expect(find.text('O que falta: Constituir a empresa'), findsOneWidget);
      expect(find.text('Interruptor: tvde_compliance_enforce'), findsOneWidget);

      final bolinha = tester.widget<Container>(
          find.byKey(const Key('tvde-bolinha-teto_intermediacao-verde')));
      expect((bolinha.decoration as BoxDecoration).color,
          tvdeCorRequisito('verde'));
    });

    testWidgets('tocar muda o estado com nota via admin_tvde_requisito_estado',
        (tester) async {
      final rpc = _FakeRpc({
        'admin_tvde_requisitos': (_) => _requisitos,
        'admin_tvde_requisito_estado': (_) => {'ok': true},
      });
      await _pump(tester, TvdeChecklistTab(rpc: rpc.call));

      await tester.tap(find.text('Licença de plataforma TVDE no IMT'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('tvde-estado-amarelo')));
      await tester.enterText(
          find.byKey(const Key('tvde-requisito-nota')), 'Pedido entregue no IMT');
      await tester.tap(find.byKey(const Key('tvde-requisito-gravar')));
      await tester.pumpAndSettle();

      expect(rpc.de('admin_tvde_requisito_estado').single, {
        'p_codigo': 'licenca_plataforma',
        'p_estado': 'amarelo',
        'p_o_que_falta': 'Pedido entregue no IMT',
      });
      // Recarregou depois de gravar.
      expect(rpc.de('admin_tvde_requisitos'), hasLength(2));
    });

    test('agrupar por área mantém a ordem', () {
      final g = tvdeAgruparPorArea(_requisitos);
      expect(g.keys.toList(), ['Licenciamento', 'Preços']);
      expect(g['Licenciamento']!.map((r) => r['codigo']),
          ['licenca_plataforma', 'livro_reclamacoes']);
    });
  });

  testWidgets('o ecrã principal abre com o título e os 12 separadores',
      (tester) async {
    final rpc = _FakeRpc({'admin_tvde_conf_resumo': (_) => _resumo()});
    tester.view.physicalSize = const Size(1024, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
        MaterialApp(home: AdminTvdeConformidadeScreen(rpc: rpc.call)));
    await tester.pumpAndSettle();

    expect(find.text('Conformidade TVDE (IMT/AMT)'), findsOneWidget);
    expect(kTvdeSeparadores, hasLength(12));
    expect(find.text('Interruptores'), findsOneWidget);
    expect(find.text(kTvdeTextoMestre), findsOneWidget);
    expect(rpc.de('admin_tvde_conf_resumo'), hasLength(1));
  });

  group('peças puras', () {
    test('euros a partir de cêntimos, sem vírgula flutuante', () {
      expect(tvdeEuros(12168), '121,68 €');
      expect(tvdeEuros(5), '0,05 €');
      expect(tvdeEuros(-250), '-2,50 €');
      expect(tvdeEuros(null), '0,00 €');
    });

    test('jsonb booleano em qualquer forma', () {
      expect(tvdeBool(true), isTrue);
      expect(tvdeBool('false'), isFalse);
      expect(tvdeBool('"true"'), isTrue);
      expect(tvdeBool(0), isFalse);
      expect(tvdeBool('talvez'), isNull);
    });

    test('CSV da fiscalização tem uma secção por bloco', () {
      final csv = tvdeFiscalCsv({
        'periodo': {'de': '2026-09-01T00:00:00Z', 'ate': '2026-10-01T00:00:00Z'},
        'gerado_em': '2026-09-30T10:00:00Z',
        'plataforma': {'denominacao': 'Bora'},
        'viagens': [
          {'codigo': 'AB12CD34', 'valor_cents': 750, 'intermediacao_cents': 150, 'motorista': 'Ney'},
        ],
        'tempos_trabalho': [],
        'documentos': [],
        'queixas': [],
        'bloqueios': [],
      });
      for (final s in [
        '# PLATAFORMA E PERÍODO',
        '# VIAGENS (1)',
        '# TEMPOS DE TRABALHO (0)',
        '# DOCUMENTOS (0)',
        '# QUEIXAS (0)',
        '# BLOQUEIOS (0)',
      ]) {
        expect(csv, contains(s));
      }
      expect(csv, contains('AB12CD34'));
      expect(csv, contains('7,50'));
      expect(csv, contains('1,50'));
    });
  });
}
