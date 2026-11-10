// Missão fecho-contabilista-2026-11-10 (Danilo, 10/11/2026: "O que vai pro
// estafeta, o que vai pro parceiro, o que vai pro contabilista... O sistema tem
// que estar ótimo, sem erro.").
//  - B2: painel /admin/fecho-mensal → secção "Para o contabilista" (o mesmo
//    texto que vai ao contabilista; copiar, CSV, nota, reenviar);
//  - C2: painel "Dados fiscais (DAC7)" com filtro "só em falta" e CSV sem IBAN;
//  - C3: aviso "Faltam dados para as Finanças" na app de limpeza, Casa,
//    lavagem e lojas.
import 'package:bora_app/screens/admin/admin_dados_fiscais_screen.dart';
import 'package:bora_app/screens/admin/admin_menu_registry.dart';
import 'package:bora_app/widgets/admin/admin_fecho_contabilista_section.dart';
import 'package:bora_app/widgets/aviso_dados_fiscais_em_falta.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

const _texto = 'Bora — fecho de outubro de 2026 (para a contabilidade)\n'
    '1. RECEITA PRÓPRIA DA BORA\n= TOTAL RECEITA PRÓPRIA DA BORA: 159,17 €';

Map<String, dynamic> _contab({String? nota, Map<String, dynamic>? envio}) => {
      'periodo': {'ano': 2026, 'mes': 10, 'nome': 'outubro'},
      'receita': {
        'rubricas': {'entrega': 76.94, 'tokens_descontados': -3.29, 'ajustes_descontos': 0},
        'entregas_e_mercados': 129.56,
        'limpeza': {'taxa_bora': 29.61},
        'lavagem_taxa_bora': 0,
        'marcacoes': 0,
        'total': 159.17,
      },
      'faturacao': [
        {'destinatario': 'Consumidor final', 'nif': null, 'valor': 159.17, 'descricao': 'Parte da Bora em outubro 2026'}
      ],
      'prestadores': {
        'estafetas': [
          {'nome': 'Estafeta Exemplo', 'nif': '999999990', 'entregas': 3, 'ganho': 16.08}
        ],
        'limpeza': const [],
        'lavagem': const [],
        'lojas_parceiras': [
          {'nome': 'Loja Exemplo', 'nif': '500000000', 'pedidos': 1, 'vendas': 11.55, 'parte_bora': 1.65}
        ],
      },
      'extras': {
        'tokens_oferecidos': {'tokens': 12578, 'valor': 62.89},
        'tokens_descontados_em_pedidos': {'pedidos': 3, 'valor': 3.29},
        'codigos_promocionais': [
          {'codigo': 'BEMVINDO', 'usos': 7, 'valor': 35.0, 'nota': 'Oferta de tokens'}
        ],
        'premios_checkin': {'emitidos': 2, 'emitidos_custo': 13.3, 'usados': 0, 'usados_custo': 0},
        'cancelados_e_reembolsos': {'cancelados': 19, 'cancelados_valor': 281.83, 'reembolsados': 6, 'reembolsado_valor': 67.39},
        'stripe_parte_bora': {'taxas_a_considerar': 5.95, 'fonte': 'extrato_stripe'},
        'pedidos_com_nif_do_cliente': const [],
      },
      'pedidos_no_prejuizo': [
        {'data': '2026-10-31', 'loja': 'Continente', 'resultado': -2.69, 'motivo': 'talão acima do catálogo', 'order_id': '48669acf'}
      ],
      'dados_em_falta': [
        {'nome': 'Estafeta Exemplo', 'papel': 'estafeta', 'falta': ['IBAN', 'comprovativo de atividade']}
      ],
      'nota_admin': nota,
      'envio': envio,
      'texto': _texto,
    };

Widget _app(Widget w) => MaterialApp(
    home: Scaffold(body: SingleChildScrollView(child: w)));

void main() {
  group('B2 — "Para o contabilista" no fecho do mês', () {
    testWidgets('mostra o estado, o que falta, e copia o MESMO texto que vai ao contabilista',
        (t) async {
      final copias = <String>[];
      t.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
        if (call.method == 'Clipboard.setData') copias.add((call.arguments as Map)['text'] as String);
        return null;
      });
      addTearDown(() => t.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, null));
      await t.binding.setSurfaceSize(const Size(900, 1400));
      addTearDown(() => t.binding.setSurfaceSize(null));

      final pedidos = <String>[];
      await t.pumpWidget(_app(AdminFechoContabilistaSection(
        ano: 2026,
        mes: 10,
        carregar: (a, m) async {
          pedidos.add('$a-$m');
          return _contab(nota: 'Outubro foi no nome individual do Danilo.');
        },
      )));
      await t.pumpAndSettle();

      expect(pedidos, ['2026-10']);
      expect(find.text('Envio: ainda não enviado'), findsOneWidget);
      expect(find.byKey(const Key('fecho_contab_falta')), findsOneWidget);
      expect(find.text('Nota do Danilo: Outubro foi no nome individual do Danilo.'), findsOneWidget);
      expect(find.textContaining('nunca às lojas'), findsOneWidget);
      expect(find.byTooltip('Descarregar CSV'), findsOneWidget);

      await t.tap(find.byKey(const Key('fecho_contab_copiar')));
      await t.pumpAndSettle();
      expect(copias, [_texto]);

      await t.tap(find.byKey(const Key('fecho_contab_ver_texto')));
      await t.pumpAndSettle();
      expect(find.byKey(const Key('fecho_contab_texto')), findsOneWidget);
    });

    testWidgets('nota: grava e recarrega; reenviar pede confirmação', (t) async {
      await t.binding.setSurfaceSize(const Size(900, 1400));
      addTearDown(() => t.binding.setSurfaceSize(null));
      final notas = <String>[];
      final reenvios = <String>[];
      var cargas = 0;
      await t.pumpWidget(_app(AdminFechoContabilistaSection(
        ano: 2026,
        mes: 11,
        carregar: (a, m) async {
          cargas++;
          return _contab(envio: {'estado': 'sent', 'enviado_em': '2026-12-01T08:00:00Z'});
        },
        guardarNota: (a, m, n) async => notas.add('$a-$m: $n'),
        reenviar: (a, m) async => reenvios.add('$a-$m'),
      )));
      await t.pumpAndSettle();
      expect(find.textContaining('Envio: sent'), findsOneWidget);

      await t.tap(find.byKey(const Key('fecho_contab_nota_editar')));
      await t.pumpAndSettle();
      await t.enterText(find.byKey(const Key('fecho_contab_nota_campo')), 'Novembro já é a sociedade.');
      await t.tap(find.byKey(const Key('fecho_contab_nota_salvar')));
      await t.pumpAndSettle();
      expect(notas, ['2026-11: Novembro já é a sociedade.']);
      expect(cargas, 2, reason: 'recarrega depois de gravar');

      await t.tap(find.byKey(const Key('fecho_contab_reenviar')));
      await t.pumpAndSettle();
      expect(reenvios, isEmpty, reason: 'só depois de confirmar');
      await t.tap(find.byKey(const Key('fecho_contab_reenviar_confirmar')));
      await t.pumpAndSettle();
      expect(reenvios, ['2026-11']);
    });

    testWidgets('servidor sem a função: aviso claro e nada parte', (t) async {
      await t.pumpWidget(_app(AdminFechoContabilistaSection(
        ano: 2026,
        mes: 10,
        carregar: (a, m) async => throw Exception('PGRST202 Could not find the function'),
      )));
      await t.pumpAndSettle();
      expect(find.text(kFechoContabilistaNaoPublicada), findsOneWidget);
      expect(t.takeException(), isNull);
    });

    test('CSV: uma linha por número, com a faturação ao consumidor final e o que falta', () {
      final l = linhasCsvContabilista(_contab());
      expect(l.where((x) => x['descricao'] == 'TOTAL').single['valor'], 159.17);
      expect(l.where((x) => x['descricao'] == 'tokens_descontados').single['valor'], -3.29);
      expect(l.where((x) => x['secao'] == '2. Faturação da parte da Bora').single['descricao'], 'Consumidor final');
      expect(l.where((x) => x['secao'] == '3. Lojas parceiras').single['nota'], contains('faturada aos clientes'));
      expect(l.where((x) => x['secao'] == '6. Stripe (parte Bora)').single['valor'], 5.95);
      expect(l.where((x) => x['secao'] == '8. Dados em falta (DAC7)').single['nota'],
          'falta IBAN, comprovativo de atividade');
      expect([for (final c in AdminFechoContabilistaSection.colunasCsv) c.$1], ['secao', 'descricao', 'valor', 'nota']);
    });
  });

  group('C2 — Dados fiscais (DAC7) no painel', () {
    final linhas = [
      {
        'papel': 'estafeta', 'ref_id': 'd1', 'nome': 'Estafeta Exemplo', 'nif': '999999990',
        'tem_iban': false, 'atividade': 'por_enviar', 'em_falta': true,
        'falta': ['IBAN', 'comprovativo de atividade'],
      },
      {
        'papel': 'loja_parceira', 'ref_id': 'r1', 'nome': 'Loja Sem NIF', 'nif': null,
        'tem_iban': false, 'atividade': 'não se aplica', 'em_falta': true, 'falta': ['NIF', 'IBAN'],
      },
      {
        'papel': 'limpeza', 'ref_id': 'c1', 'nome': 'Profissional Completa', 'nif': '123456789',
        'tem_iban': true, 'atividade': 'aprovada', 'em_falta': false, 'falta': const <String>[],
      },
    ];

    testWidgets('abre só com os em falta; o filtro mostra todos', (t) async {
      await t.binding.setSurfaceSize(const Size(900, 1400));
      addTearDown(() => t.binding.setSurfaceSize(null));
      await t.pumpWidget(MaterialApp(
        home: AdminDadosFiscaisScreen(carregar: () async => {'linhas': linhas}),
      ));
      await t.pumpAndSettle();
      expect(find.text('3 prestadores e lojas · 2 com dados em falta'), findsOneWidget);
      expect(find.byKey(const Key('dados_fiscais_estafeta_d1')), findsOneWidget);
      expect(find.text('Falta: IBAN, comprovativo de atividade'), findsOneWidget);
      expect(find.text('Falta: NIF, IBAN'), findsOneWidget);
      expect(find.byKey(const Key('dados_fiscais_limpeza_c1')), findsNothing);

      await t.tap(find.byKey(const Key('dados_fiscais_so_em_falta')));
      await t.pumpAndSettle();
      expect(find.byKey(const Key('dados_fiscais_limpeza_c1')), findsOneWidget);
      expect(find.byTooltip('Descarregar CSV'), findsOneWidget);
    });

    test('CSV: IBAN só sim/não, papel em PT-BR', () {
      final c = linhaCsvDadosFiscais(linhas.first);
      expect(c['tem_iban'], 'não');
      expect(c['papel'], 'Entregador');
      expect(c['falta'], 'IBAN, comprovativo de atividade');
      expect(c.values.join(' '), isNot(contains('PT50')));
      expect(papelDadosFiscais('casa'), 'Casa e Manutenção');
    });

    testWidgets('servidor sem a função: aviso claro', (t) async {
      await t.pumpWidget(MaterialApp(
        home: AdminDadosFiscaisScreen(carregar: () async => throw Exception('PGRST202')),
      ));
      await t.pumpAndSettle();
      expect(find.text(kDadosFiscaisNaoPublicada), findsOneWidget);
    });

    test('o ecrã está no menu do painel', () {
      AdminMenuItem? achado;
      void procurar(List<AdminMenuItem> itens) {
        for (final i in itens) {
          if (i.id == 'dinheiro_dados_fiscais_dac7') achado = i;
          procurar(i.filhos);
        }
      }

      for (final s in adminMenuSections()) {
        procurar(s.items);
      }
      expect(achado, isNotNull);
      expect(achado!.title, 'Dados fiscais (DAC7)');
      expect(achado!.builder(), isA<AdminDadosFiscaisScreen>());
      expect(achado!.matches('dac7'), isTrue);
    });
  });

  group('C3 — aviso na app de quem tem dados em falta', () {
    final resposta = {
      'ok': true,
      'em_falta': [
        {'papel': 'limpeza', 'falta': ['IBAN', 'data de nascimento', 'comprovativo de atividade']},
        {'papel': 'loja_parceira', 'falta': ['NIF']},
      ],
    };

    test('falta só do papel pedido; texto em PT-PT', () {
      expect(faltaDoPapel(resposta, 'limpeza'), ['IBAN', 'data de nascimento', 'comprovativo de atividade']);
      expect(faltaDoPapel(resposta, 'casa'), isEmpty);
      expect(faltaDoPapel({'ok': false}, 'limpeza'), isEmpty);
      expect(faltaDoPapel(null, 'limpeza'), isEmpty);
      expect(textoFaltaDadosFiscais(['IBAN']), 'Faltam dados para as Finanças: IBAN.');
      expect(textoFaltaDadosFiscais(['IBAN', 'NIF', 'morada']), 'Faltam dados para as Finanças: IBAN, NIF e morada.');
    });

    testWidgets('limpeza: barra sem repetir o comprovativo (já tem o aviso próprio)', (t) async {
      await t.pumpWidget(_app(AvisoDadosFiscaisEmFalta(
          papel: 'limpeza', semComprovativo: true, carregar: () async => resposta)));
      await t.pumpAndSettle();
      expect(find.byKey(const Key('aviso_dados_fiscais_em_falta')), findsOneWidget);
      expect(find.text('Faltam dados para as Finanças: IBAN e data de nascimento. Toque para completar.'),
          findsOneWidget);
    });

    testWidgets('loja: o toque abre o sítio certo (callback do ecrã)', (t) async {
      var abriu = 0;
      await t.pumpWidget(_app(AvisoDadosFiscaisEmFalta(
          papel: 'loja_parceira',
          carregar: () async => resposta,
          aoCompletar: (_) async => abriu++)));
      await t.pumpAndSettle();
      await t.tap(find.byKey(const Key('aviso_dados_fiscais_em_falta')));
      await t.pumpAndSettle();
      expect(abriu, 1);
    });

    testWidgets('nada em falta, erro ou servidor sem a função: não aparece e não parte', (t) async {
      for (final c in <Future<Object?> Function()>[
        () async => {'ok': true, 'em_falta': const []},
        () async => throw Exception('PGRST202'),
      ]) {
        await t.pumpWidget(_app(AvisoDadosFiscaisEmFalta(papel: 'casa', carregar: c)));
        await t.pumpAndSettle();
        expect(find.byKey(const Key('aviso_dados_fiscais_em_falta')), findsNothing);
        expect(t.takeException(), isNull);
      }
    });
  });
}
