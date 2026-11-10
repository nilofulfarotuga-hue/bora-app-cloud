// Depósito Volta no painel admin (09/11/2026, ramo
// ai/2026-11-09-volta-deposito-kfc): lógica pura (dinheiro, filtros, CSV,
// páginas, relatório, cartão do pedido), as duas chaves das Configurações,
// e o ecrã com um servidor falso — incluindo o servidor SEM as funções.
import 'dart:io';

import 'package:bora_app/screens/admin/admin_platform_settings_screen.dart'
    show erroDepositoVolta, kChavesDinheiroSemMarca, kRotulosDepositoVolta;
import 'package:bora_app/screens/admin/admin_volta_screen.dart';
import 'package:bora_app/utils/deposito_volta_admin.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show PostgrestException;

Map<String, dynamic> _produto(String id, String nome,
        {int unidades = 0,
        bool rever = false,
        String tipo = 'produto',
        num? preco = 1.29,
        String? origem,
        int total = 1}) =>
    {
      'tipo': tipo,
      'id': id,
      'loja_id': 'kfc-guarda',
      'loja_nome': 'KFC Guarda',
      'nome': nome,
      'categoria': 'Bebidas',
      'preco': preco,
      'deposit_units': unidades,
      'deposit_review': rever,
      'deposit_origem': origem,
      'image_url': null,
      'total': total,
    };

class _ApiFalsa extends VoltaAdminApi {
  _ApiFalsa({this.semFuncoes = false});

  final bool semFuncoes;
  final pedidosProdutos = <Map<String, Object?>>[];
  final definidos = <(String, String, int)>[];
  final relatorios = <(int, int)>[];

  void _talvezFalhe(String funcao) {
    if (semFuncoes) {
      throw PostgrestException(
          message: 'Could not find the function public.$funcao',
          code: 'PGRST202');
    }
  }

  @override
  Future<List<Map<String, dynamic>>> resumoLojas() async {
    _talvezFalhe('admin_volta_resumo_lojas');
    return [
      {
        'loja_id': 'kfc-guarda',
        'loja_nome': 'KFC Guarda',
        'produtos_com': 3,
        'opcoes_com': 2,
        'rever': 1,
      },
    ];
  }

  @override
  Future<List<Map<String, dynamic>>> configuracao() async {
    _talvezFalhe('admin_list_settings');
    return [
      {'key': 'volta_deposit_cents', 'value': 10},
      {'key': 'volta_deposit_enabled', 'value': true},
    ];
  }

  @override
  Future<List<Map<String, dynamic>>> produtos({
    String? loja,
    FiltroVolta filtro = FiltroVolta.todos,
    String? busca,
    int limite = 50,
    int offset = 0,
  }) async {
    _talvezFalhe('admin_volta_produtos');
    pedidosProdutos.add({
      'loja': loja,
      'filtro': filtroVoltaParaRpc(filtro),
      'busca': busca,
      'limite': limite,
      'offset': offset,
    });
    if (offset > 0) return [];
    return [_produto('p1', 'Pepsi lata 33cl', unidades: 1, rever: true)];
  }

  @override
  Future<Map<String, dynamic>> definir({
    required String tipo,
    required String id,
    required int unidades,
  }) async {
    _talvezFalhe('admin_volta_definir');
    definidos.add((tipo, id, unidades));
    return {'ok': true, 'tipo': tipo, 'id': id, 'deposit_units': unidades};
  }

  @override
  Future<Map<String, dynamic>> relatorioMensal(int ano, int mes) async {
    _talvezFalhe('admin_volta_relatorio_mensal');
    relatorios.add((ano, mes));
    return {
      'pedidos': 12,
      'embalagens': 40,
      'cobrado_cents': 400,
      'ajustes_cents': -20,
      'talao_cents': 380,
      'parceiros_cents': 250,
      'bora_cents': 130,
    };
  }
}

void main() {
  group('dinheiro e filtros', () {
    test('cêntimos em euros, com vírgula e sinal', () {
      expect(eurosDeCentimos(10), '0,10 €');
      expect(eurosDeCentimos(0), '0,00 €');
      expect(eurosDeCentimos(null), '0,00 €');
      expect(eurosDeCentimos(-20), '-0,20 €');
      expect(eurosDeCentimos(20, comSinal: true), '+0,20 €');
      expect(eurosDeCentimos(0, comSinal: true), '0,00 €');
      expect(eurosDeCentimos(123456), '1234,56 €');
      expect(precoVolta(1.29), '1,29 €');
      expect(precoVolta(null), '—');
    });

    test('filtro → p_filtro da RPC e rótulo do chip', () {
      expect(FiltroVolta.values.map(filtroVoltaParaRpc).toList(),
          ['todos', 'com', 'sem', 'rever']);
      expect(FiltroVolta.values.map(rotuloFiltroVolta).toList(),
          ['Todos', 'Com Volta', 'Sem Volta', 'Rever']);
    });

    test('embalagens: inteiro de 0 a 48', () {
      expect(validarUnidadesVolta('6'), 6);
      expect(validarUnidadesVolta(' 0 '), 0);
      expect(validarUnidadesVolta('48'), 48);
      expect(validarUnidadesVolta('49'), isNull);
      expect(validarUnidadesVolta('-1'), isNull);
      expect(validarUnidadesVolta('1.5'), isNull);
      expect(validarUnidadesVolta(''), isNull);
    });

    test('origem e números que chegam como texto', () {
      expect(rotuloOrigemVolta('admin'), 'painel');
      expect(rotuloOrigemVolta(null), 'sem origem');
      expect(rotuloOrigemVolta('regra'), 'regra');
      expect(numVolta('1.5'), 1.5);
      expect(numVolta(3), 3);
      expect(numVolta(null), isNull);
    });
  });

  group('CSV', () {
    test('cabeçalho e uma linha simples', () {
      final csv = csvDepositoVolta([
        _produto('p1', 'Pepsi lata 33cl', unidades: 1, rever: true, origem: 'admin'),
      ]);
      final linhas = csv.split('\r\n');
      expect(linhas.first,
          'tipo;id;loja;nome;categoria;preco;deposit_units;rever;origem');
      expect(linhas[1], 'produto;p1;KFC Guarda;Pepsi lata 33cl;Bebidas;"1,29";1;sim;admin');
    });

    test('vírgulas, ponto e vírgula e aspas não partem as colunas', () {
      final csv = csvDepositoVolta([
        _produto('p2', 'Água "Luso", 1,5 L; pack', preco: null, tipo: 'opcao'),
      ]);
      final linha = csv.split('\r\n')[1];
      expect(linha, 'opcao;p2;KFC Guarda;"Água ""Luso"", 1,5 L; pack";Bebidas;;0;não;');
      expect(campoCsvVolta('a,b'), '"a,b"');
      expect(campoCsvVolta('diz "olá"'), '"diz ""olá"""');
      expect(campoCsvVolta('linha\nnova'), '"linha\nnova"');
      expect(campoCsvVolta(null), '');
      expect(campoCsvVolta('simples'), 'simples');
    });

    test('todas as páginas do filtro atual', () async {
      final pedidos = <(int, int)>[];
      Future<List<Map<String, dynamic>>> buscar(int offset, int limite) async {
        pedidos.add((offset, limite));
        final fim = (offset + limite).clamp(0, 1203);
        return [
          for (var i = offset; i < fim; i++) {'id': 'p$i', 'total': 1203},
        ];
      }

      final todas = await buscarTodasAsPaginasVolta(buscar, limite: 500);
      expect(todas.length, 1203);
      expect(pedidos, [(0, 500), (500, 500), (1000, 500)]);

      final vazio = await buscarTodasAsPaginasVolta((_, __) async => []);
      expect(vazio, isEmpty);

      final cortado =
          await buscarTodasAsPaginasVolta(buscar, limite: 500, maximo: 600);
      expect(cortado.length, 600, reason: 'a trava contra o ciclo sem fim');
    });

    test('relatório mensal em CSV', () {
      final csv = csvRelatorioVolta('2026-11', {'pedidos': 2, 'cobrado_cents': 60});
      final linhas = csv.split('\r\n');
      expect(linhas.first, 'mes;rubrica;valor');
      expect(linhas[1], '2026-11;Pedidos com depósito;2');
      expect(linhas[3], '2026-11;Cobrado aos clientes;"0,60 €"');
      expect(linhas.length, 8);
    });
  });

  group('relatório e configuração', () {
    test('as sete linhas do mês, por ordem', () {
      final l = linhasRelatorioVolta({
        'pedidos': 12,
        'embalagens': 40,
        'cobrado_cents': 400,
        'ajustes_cents': -20,
        'talao_cents': 380,
        'parceiros_cents': 250,
        'bora_cents': 130,
      });
      expect(l, [
        ('Pedidos com depósito', '12'),
        ('Embalagens', '40'),
        ('Cobrado aos clientes', '4,00 €'),
        ('Acertos (talão/falta)', '-0,20 €'),
        ('Lido nos talões', '3,80 €'),
        ('Entregue aos parceiros', '2,50 €'),
        ('Fica com a Bora (não-parceiros)', '1,30 €'),
      ]);
      expect(linhasRelatorioVolta({}).map((e) => e.$2).first, '0');
    });

    test('lê as chaves volta_deposit_* (bool, número ou texto)', () {
      expect(
          lerConfigVolta([
            {'key': 'volta_deposit_enabled', 'value': true},
            {'key': 'volta_deposit_cents', 'value': 10},
          ]),
          (ligado: true, centimos: 10));
      expect(
          lerConfigVolta([
            {'key': 'volta_deposit_enabled', 'value': 'false'},
            {'key': 'volta_deposit_cents', 'value': '12'},
          ]),
          (ligado: false, centimos: 12));
      expect(lerConfigVolta([]), (ligado: null, centimos: null));
    });

    test('função que falta no servidor → mensagem calma', () {
      final m = mensagemErroVolta(
          const PostgrestException(message: 'Could not find the function x', code: 'PGRST202'),
          'admin_volta_produtos');
      expect(m, startsWith(kVoltaFuncaoNaoPublicada));
      expect(m, contains('admin_volta_produtos'));
      expect(mensagemErroVolta(const PostgrestException(message: 'not_admin'), 'f'),
          contains('Sem permissão'));
    });
  });

  group('cartão do pedido', () {
    test('sem colunas no servidor → sem cartão', () {
      expect(DepositoVoltaPedido.daLinha(null), isNull);
    });

    test('tudo a zero → escondido', () {
      final d = DepositoVoltaPedido.daLinha({
        'deposit_units': 0,
        'deposit_cents': 0,
        'deposit_ajuste_cents': null,
        'deposit_from_receipt_cents': null,
      })!;
      expect(d.vazio, isTrue);
    });

    test('acerto cobrado e devolvido, com o total final', () {
      final mais = DepositoVoltaPedido.daLinha({
        'deposit_units': 6,
        'deposit_cents': 60,
        'deposit_ajuste_cents': 20,
        'deposit_from_receipt_cents': 80,
      })!;
      expect(mais.vazio, isFalse);
      expect(mais.totalFinalCents, 80);
      expect(mais.acertoTexto, '+0,20 € (diferença cobrada)');

      final menos = DepositoVoltaPedido.daLinha({
        'deposit_units': 3,
        'deposit_cents': 30,
        'deposit_ajuste_cents': -10,
      })!;
      expect(menos.totalFinalCents, 20);
      expect(menos.talaoCents, isNull);
      expect(menos.acertoTexto, '-0,10 € (diferença devolvida)');
    });
  });

  group('Configurações, pedido, acerto semanal e menu', () {
    String fonte(String f) => File(f).readAsStringSync();

    test('as duas chaves têm etiqueta PT-BR e estão na lista branca', () {
      expect(kRotulosDepositoVolta.keys,
          containsAll(['volta_deposit_cents', 'volta_deposit_enabled']));
      final ecra = fonte('lib/screens/admin/admin_platform_settings_screen.dart');
      final i = ecra.indexOf('bool _isEditable(String key)');
      final f = ecra.indexOf('bool _isMoneyKey(String key)');
      expect(i, greaterThan(-1));
      expect(ecra.substring(i, f),
          contains('kRotulosDepositoVolta.containsKey(key)'),
          reason: 'sem isto as chaves ficam com o cadeado');
      expect(ecra, contains('kRotulosDepositoVolta[s.key]'),
          reason: 'a etiqueta PT-BR tem de aparecer no ecrã');
    });

    test('as duas vão pelo caminho com motivo e auditoria', () {
      expect('volta_deposit_cents'.contains('cents'), isTrue);
      expect(kChavesDinheiroSemMarca, contains('volta_deposit_enabled'));
      final ecra = fonte('lib/screens/admin/admin_platform_settings_screen.dart');
      expect(RegExp(r'erroDepositoVolta\(s\.key, novo\)').hasMatch(ecra), isTrue);
      expect(RegExp(r'erroDepositoVolta\(s\.key, parsed\)').hasMatch(ecra), isTrue);
    });

    test('validação das duas chaves', () {
      expect(erroDepositoVolta('volta_deposit_cents', 10), isNull);
      expect(erroDepositoVolta('volta_deposit_cents', 0), isNull);
      expect(erroDepositoVolta('volta_deposit_cents', 10.5), isNotNull);
      expect(erroDepositoVolta('volta_deposit_cents', 101), isNotNull);
      expect(erroDepositoVolta('volta_deposit_cents', -1), isNotNull);
      expect(erroDepositoVolta('volta_deposit_enabled', false), isNull);
      expect(erroDepositoVolta('volta_deposit_enabled', 'sim'), isNotNull);
      expect(erroDepositoVolta('outra_chave', 'x'), isNull);
    });

    test('detalhe do pedido: colunas do depósito fora do select principal', () {
      final ecra = fonte('lib/screens/admin/admin_order_detail_screen.dart');
      final i = ecra.indexOf("'id, status, payment_method");
      final f = ecra.indexOf(".eq('id', widget.orderId)", i);
      expect(ecra.substring(i, f), isNot(contains('deposit_')),
          reason: 'uma coluna que ainda não existe partia o ecrã inteiro');
      expect(ecra, contains("'deposit_units, deposit_cents, deposit_ajuste_cents, '"));
      expect(ecra, contains("_order!['_deposito_volta'] = deposito"));
    });

    test('acerto semanal mostra o depósito do parceiro', () {
      final ecra = fonte('lib/screens/admin/admin_settlements_screen.dart');
      expect(ecra, contains("s['deposit_volta_total']"));
      expect(ecra, contains('Depósito Volta (vai 100% para o parceiro)'));
    });

    test('menu: entrada ao pé do Catálogo', () {
      final menu = fonte('lib/screens/admin/admin_menu_registry.dart');
      final catalogo = menu.indexOf('builder: () => const AdminCatalogScreen()');
      final volta = menu.indexOf('builder: () => const AdminVoltaScreen()');
      expect(volta, greaterThan(catalogo));
      expect(volta - catalogo, lessThan(800));
      expect(menu, contains("title: 'Depósito Volta'"));
      expect(menu, contains("subtitle: 'Latas e garrafas de plástico com depósito de 0,10 €'"));
    });
  });

  group('ecrã', () {
    Widget app(_ApiFalsa api, List<(String, String)> exportados) => MaterialApp(
          home: AdminVoltaScreen(
            api: api,
            agora: () => DateTime.utc(2026, 11, 9, 12),
            exportar: (nome, csv) async => exportados.add((nome, csv)),
          ),
        );

    testWidgets('resumo → loja → mudar embalagens → exportar CSV',
        (tester) async {
      final api = _ApiFalsa();
      final exportados = <(String, String)>[];
      await tester.pumpWidget(app(api, exportados));
      await tester.pumpAndSettle();

      expect(find.text('Cobrança ao cliente: LIGADA'), findsOneWidget);
      expect(find.text('Valor por embalagem: 0,10 €'), findsOneWidget);
      expect(find.text('KFC Guarda'), findsOneWidget);
      expect(find.text('1 para rever'), findsOneWidget);

      await tester.tap(find.text('KFC Guarda'));
      await tester.pumpAndSettle();
      expect(api.pedidosProdutos.last['loja'], 'kfc-guarda');
      expect(find.text('Pepsi lata 33cl'), findsOneWidget);

      await tester.tap(find.text('Rever'));
      await tester.pumpAndSettle();
      expect(api.pedidosProdutos.last['filtro'], 'rever');

      await tester.tap(find.text('Pepsi lata 33cl'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const Key('volta_unidades')), '6');
      await tester.pump();
      await tester.tap(find.text('Salvar'));
      await tester.pumpAndSettle();
      expect(api.definidos, [('produto', 'p1', 6)]);
      expect(find.textContaining('Salvo: 6 embalagens'), findsOneWidget);

      await tester.tap(find.text('Exportar CSV'));
      await tester.pumpAndSettle();
      expect(exportados, hasLength(1));
      expect(exportados.first.$1, 'deposito-volta-rever-kfc-guarda.csv');
      expect(exportados.first.$2, startsWith('tipo;id;loja;nome'));
      expect(exportados.first.$2, contains('Pepsi lata 33cl'));
    });

    testWidgets('relatório do mês', (tester) async {
      final api = _ApiFalsa();
      await tester.pumpWidget(app(api, []));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Relatório'));
      await tester.pumpAndSettle();
      expect(api.relatorios.last, (2026, 11));
      expect(find.text('Novembro de 2026'), findsOneWidget);
      expect(find.text('Pedidos com depósito'), findsOneWidget);
      expect(find.text('-0,20 €'), findsOneWidget);
      expect(find.text('1,30 €'), findsOneWidget);
    });

    testWidgets('servidor sem as funções: avisa e não parte', (tester) async {
      final api = _ApiFalsa(semFuncoes: true);
      await tester.pumpWidget(app(api, []));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.textContaining(kVoltaFuncaoNaoPublicada), findsWidgets);

      await tester.tap(find.text('Produtos'));
      await tester.pumpAndSettle();
      expect(find.textContaining('(admin_volta_produtos)'), findsOneWidget);

      await tester.tap(find.text('Relatório'));
      await tester.pumpAndSettle();
      expect(find.textContaining('(admin_volta_relatorio_mensal)'),
          findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });
}
