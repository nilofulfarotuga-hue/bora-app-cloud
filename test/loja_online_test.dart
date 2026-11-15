// Loja Online dentro da app (15/11/2026, fechar-tudo-15-11 ponto E, caixa 10).
// Sem rede nem Supabase: o serviço recebe funções falsas.
//  - modelo tolerante, preço "12,90 €", frase do prazo, vitrine (nicho da semana);
//  - serviço: interruptor desligado / chave em falta / tabelas por instalar / erro;
//  - ecrã do cliente: "Em breve", vitrine, ficha com preço, prazo e botão Encomendar (checkup-15-11);
//  - painel: "Esta parte ainda não foi instalada no servidor.", motivo obrigatório;
//  - l10n: toda frase .tr dos ecrãs novos tem inglês; o painel não usa .tr.
import 'dart:io';

import 'package:bora_app/l10n/strings_en.dart';
import 'package:bora_app/models/loja_online_produto.dart';
import 'package:bora_app/screens/admin/admin_loja_online_screen.dart';
import 'package:bora_app/screens/client/loja_online/loja_online_screen.dart';
import 'package:bora_app/screens/client/loja_online/produto_loja_online_screen.dart';
import 'package:bora_app/screens/admin/admin_loja_online_encomendas_screen.dart';
import 'package:bora_app/screens/client/loja_online/checkout_loja_online_screen.dart';
import 'package:bora_app/services/loja_online_pagamento_service.dart';
import 'package:bora_app/services/loja_online_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

const PostgrestException _tabelaEmFalta = PostgrestException(
  message:
      "Could not find the table 'public.loja_online_produtos' in the schema cache",
  code: 'PGRST205',
);

const PostgrestException _funcaoEmFalta = PostgrestException(
  message:
      'Could not find the function public.admin_loja_online_produto_estado(p_ativo, p_destaque, p_id, p_motivo) in the schema cache',
  code: 'PGRST202',
);

Map<String, dynamic> _nicho({
  String id = 'n-pets',
  String slug = 'pets',
  String nome = 'Pets',
  int ordem = 10,
  bool ativo = true,
  String? destaqueDesde = '2026-11-15T13:00:00Z',
}) =>
    <String, dynamic>{
      'id': id,
      'slug': slug,
      'nome': nome,
      'ordem': ordem,
      'ativo': ativo,
      'destaque_desde': destaqueDesde,
    };

Map<String, dynamic> _produto({
  String id = 'p1',
  String nicho = 'n-pets',
  String titulo = 'Limpador de patas',
  int preco = 1290,
  int custo = 645,
  bool ativo = true,
  bool destaque = true,
  int prazoMin = 7,
  int prazoMax = 15,
  List<String> imagens = const [],
  String descricao = 'Copo de silicone que limpa as patas em segundos.',
}) =>
    <String, dynamic>{
      'id': id,
      'shopify_product_id': 'gid://shopify/Product/$id',
      'shopify_variant_id': null,
      'nicho_id': nicho,
      'titulo': titulo,
      'descricao': descricao,
      'imagens': imagens,
      'custo_fornecedor_cents': custo,
      'preco_bora_cents': preco,
      'prazo_min_dias': prazoMin,
      'prazo_max_dias': prazoMax,
      'ativo': ativo,
      'destaque': destaque,
      'criado_em': '2026-11-15T12:00:00Z',
    };

LojaOnlineService _servico({
  bool ligada = true,
  bool chaveExiste = true,
  Object? erroTabelas,
  List<Map<String, dynamic>>? nichos,
  List<Map<String, dynamic>>? produtos,
  List<String>? tabelasLidas,
  int? leiturasDaChave,
  DateTime Function()? agora,
  void Function()? aoLerChave,
  Future<bool> Function()? lerVisivel,
}) {
  final Object? erro = erroTabelas;
  return LojaOnlineService(
    agora: agora,
    // Por defeito a função do servidor "ainda não existe": vale o interruptor.
    lerVisivel: lerVisivel ?? () async => throw StateError('sem rpc'),
    lerDefinicoes: (chaves) async {
      aoLerChave?.call();
      if (!chaveExiste) return <String, dynamic>{};
      return <String, dynamic>{kLojaOnlineChaveInterruptor: ligada};
    },
    lerAtivos: (tabela) async {
      tabelasLidas?.add(tabela);
      final e = erro;
      if (e != null) throw e;
      if (tabela == kLojaOnlineTabelaSubcategorias) return const [];
      if (tabela == kLojaOnlineTabelaNichos) return nichos ?? [_nicho()];
      return produtos ?? [_produto()];
    },
  );
}

LojaOnlineAdminService _painel({
  Map<String, dynamic>? interruptor = const <String, dynamic>{
    'key': 'loja_online_ativa',
    'value': false,
  },
  bool chaveFalha = false,
  Object? erroTabelas,
  List<Map<String, dynamic>>? nichos,
  List<Map<String, dynamic>>? produtos,
  List<String>? chamadas,
}) {
  final Object? erro = erroTabelas;
  return LojaOnlineAdminService(
    lerDefinicao: (chave) async {
      if (chaveFalha) throw _tabelaEmFalta;
      return interruptor;
    },
    lerTabela: (tabela) async {
      final e = erro;
      if (e != null) throw e;
      if (tabela == kLojaOnlineTabelaSubcategorias) return const [];
      if (tabela == kLojaOnlineTabelaNichos) return nichos ?? [_nicho()];
      return produtos ?? [_produto()];
    },
    rpc: (funcao, params) async {
      chamadas?.add(funcao);
      return null;
    },
  );
}

/// Ecrã alto para a lista inteira ficar construída (ListView é preguiçoso).
void _ecraGrande(WidgetTester tester) {
  tester.view.physicalSize = const Size(1200, 2400);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

/// A mesma rede de test/l10n_cobertura_test.dart.
final RegExp _padraoTr = RegExp(
  r"""(['"])((?:\\.|(?!\1).)*?)\1\s*\.tr(?:Args\()?(?![A-Za-z])""",
  dotAll: true,
);

const List<String> _ficheirosCliente = <String>[
  'lib/models/loja_online_produto.dart',
  'lib/screens/client/loja_online/loja_online_screen.dart',
  'lib/screens/client/loja_online/produto_loja_online_screen.dart',
  'lib/screens/client/loja_online/checkout_loja_online_screen.dart',
  'lib/screens/client/loja_online/minhas_encomendas_loja_online_screen.dart',
];

const List<String> _ficheirosNovos = <String>[
  ..._ficheirosCliente,
  'lib/services/loja_online_service.dart',
  'lib/screens/admin/admin_loja_online_screen.dart',
];

void main() {
  group('modelo', () {
    test('fromJson tolera números em texto, imagens em JSON e campos em falta',
        () {
      final p = LojaOnlineProduto.fromJson(<String, dynamic>{
        'id': 'x',
        'titulo': '  Cama para gato ',
        'imagens': '["https://a/1.jpg", "https://a/2.jpg"]',
        'custo_fornecedor_cents': '645',
        'preco_bora_cents': 1290.0,
        'prazo_min_dias': '7',
        'prazo_max_dias': 15,
        'ativo': 'true',
        'destaque': 'false',
      });
      expect(p.titulo, 'Cama para gato');
      expect(p.imagens, ['https://a/1.jpg', 'https://a/2.jpg']);
      expect(p.fotoPrincipal, 'https://a/1.jpg');
      expect(p.custoFornecedorCents, 645);
      expect(p.precoBoraCents, 1290);
      expect(p.prazoMinDias, 7);
      expect(p.prazoMaxDias, 15);
      expect(p.ativo, isTrue);
      expect(p.destaque, isFalse);

      final vazio = LojaOnlineProduto.fromJson(<String, dynamic>{'id': 'v'});
      expect(vazio.titulo, 'Produto');
      expect(vazio.imagens, isEmpty);
      expect(vazio.fotoPrincipal, isNull);
      expect(vazio.ativo, isFalse, reason: 'nasce escondido');
      expect(vazio.precoBoraCents, 0);

      final arrayPostgres = LojaOnlineProduto.fromJson(
          <String, dynamic>{'id': 'a', 'imagens': '{https://a/1.jpg,https://a/2.jpg}'});
      expect(arrayPostgres.imagens.length, 2);
    });

    test('nicho tolerante e preço em euros com vírgula', () {
      final n = LojaOnlineNicho.fromJson(<String, dynamic>{
        'id': 'n',
        'slug': 'pets',
        'ordem': '10',
        'destaque_desde': '2026-11-15T13:00:00Z',
      });
      expect(n.nome, 'pets', reason: 'sem nome usa o slug');
      expect(n.ordem, 10);
      expect(n.ativo, isTrue);
      expect(n.destaqueDesde, DateTime.utc(2026, 11, 15, 13));

      expect(formatarEurosCents(1290), '12,90 €');
      expect(formatarEurosCents(500), '5,00 €');
      expect(formatarEurosCents(0), '0,00 €');
      expect(LojaOnlineProduto.fromJson(_produto()).precoTexto, '12,90 €');
    });

    test('frase do prazo pelo correio', () {
      expect(textoPrazoCorreio(7, 15), 'Chega pelo correio em 7 a 15 dias úteis');
      expect(textoPrazoCorreio(10, 10), 'Chega pelo correio em 10 dias úteis');
      expect(textoPrazoCorreio(0, 5), 'Chega pelo correio em 5 dias úteis');
      expect(textoPrazoCorreio(15, 7), 'Chega pelo correio em 7 a 15 dias úteis',
          reason: 'trocados: ordena');
      expect(textoPrazoCorreio(1, 1), 'Chega pelo correio em 1 dia útil');
      expect(textoPrazoCorreio(0, 0), '', reason: 'sem prazo não inventa');
    });

    test('vitrine: nicho da semana é o destacado mais recente; destaques primeiro',
        () {
      final nichos = [
        LojaOnlineNicho.fromJson(_nicho(
            id: 'n-casa', slug: 'casa', nome: 'Casa', ordem: 5,
            destaqueDesde: '2026-11-01T10:00:00Z')),
        LojaOnlineNicho.fromJson(_nicho()), // pets, 15/11
        LojaOnlineNicho.fromJson(
            _nicho(id: 'n-off', slug: 'off', nome: 'Desligado', ativo: false)),
      ];
      final produtos = [
        LojaOnlineProduto.fromJson(_produto(id: 'p1', destaque: true)),
        LojaOnlineProduto.fromJson(
            _produto(id: 'p2', titulo: 'Cama', destaque: false)),
        LojaOnlineProduto.fromJson(
            _produto(id: 'p3', titulo: 'Inativo', ativo: false)),
        LojaOnlineProduto.fromJson(
            _produto(id: 'p4', nicho: 'n-casa', titulo: 'Candeeiro')),
        LojaOnlineProduto.fromJson(
            _produto(id: 'p5', nicho: 'n-off', titulo: 'Fantasma')),
      ];
      final v = LojaOnlineVitrine.montar(nichos, produtos);
      expect(v.nichoDaSemana?.slug, 'pets');
      expect(v.novidade.map((p) => p.id), ['p1'],
          reason: 'só os destaques do nicho da semana');
      expect(v.porNicho.map((g) => g.nicho.slug), ['casa', 'pets'],
          reason: 'pela ordem; o nicho desligado não entra');
      expect(v.porNicho.last.produtos.map((p) => p.id), ['p1', 'p2'],
          reason: 'inativo fora, destaque primeiro');
      expect(v.vazia, isFalse);

      final semDestaque = LojaOnlineVitrine.montar(
        [LojaOnlineNicho.fromJson(_nicho(destaqueDesde: null))],
        [LojaOnlineProduto.fromJson(_produto(destaque: false))],
      );
      expect(semDestaque.nichoDaSemana?.slug, 'pets',
          reason: 'sem carimbo vale o primeiro ativo');
      expect(semDestaque.novidade.length, 1,
          reason: 'sem destaques mostra os do nicho');

      expect(LojaOnlineVitrine.montar(nichos, const []).vazia, isTrue);
    });
  });

  group('serviço', () {
    test('reconhece servidor por instalar', () {
      expect(lojaOnlineServidorEmFalta(_tabelaEmFalta), isTrue);
      expect(lojaOnlineServidorEmFalta(_funcaoEmFalta), isTrue);
      expect(
          lojaOnlineServidorEmFalta(const PostgrestException(
              message: 'relation "public.loja_online_nichos" does not exist',
              code: '42P01')),
          isTrue);
      expect(
          lojaOnlineServidorEmFalta(
              const PostgrestException(message: 'Could not find the table x')),
          isTrue);
      expect(
          lojaOnlineServidorEmFalta(
              const PostgrestException(message: 'not_admin', code: '42501')),
          isFalse);
      expect(lojaOnlineServidorEmFalta(Exception('rede')), isFalse);
    });

    test('interruptor desligado: estado desligada e não toca nas tabelas',
        () async {
      final lidas = <String>[];
      final s = _servico(ligada: false, tabelasLidas: lidas);
      final c = await s.carregar();
      expect(c.estado, LojaOnlineEstado.desligada);
      expect(s.ativa.value, isFalse);
      expect(lidas, isEmpty);
    });

    test('chave ainda não instalada conta como desligada', () async {
      final s = _servico(chaveExiste: false);
      expect((await s.carregar()).estado, LojaOnlineEstado.desligada);
      expect(s.ativa.value, isFalse);
    });

    test('tabelas por instalar: Em breve, sem rebentar', () async {
      final s = _servico(erroTabelas: _tabelaEmFalta);
      expect((await s.carregar()).estado, LojaOnlineEstado.emBreve);
      expect(s.ativa.value, isTrue, reason: 'o interruptor até estava ligado');
    });

    test('falha de rede: estado erro', () async {
      final s = _servico(erroTabelas: Exception('sem rede'));
      expect((await s.carregar()).estado, LojaOnlineEstado.erro);
    });

    test('tudo instalado: catálogo pronto com nichos e produtos', () async {
      final s = _servico(produtos: [_produto(), _produto(id: 'p2', titulo: 'Cama')]);
      final c = await s.carregar();
      expect(c.estado, LojaOnlineEstado.pronta);
      expect(c.nichos.single.slug, 'pets');
      expect(c.produtos.length, 2);
      expect(c.vitrine.porNicho.single.produtos.length, 2);
    });

    test('o interruptor tem cache de 2 minutos e "forcar" ignora-a', () async {
      var agora = DateTime.utc(2026, 11, 15, 14);
      var leituras = 0;
      final s = _servico(agora: () => agora, aoLerChave: () => leituras++);
      await s.atualizarInterruptor();
      await s.atualizarInterruptor();
      expect(leituras, 1);
      agora = agora.add(const Duration(minutes: 3));
      await s.atualizarInterruptor();
      expect(leituras, 2);
      await s.atualizarInterruptor(forcar: true);
      expect(leituras, 3);
    });
  });

  group('ecrã do cliente', () {
    testWidgets('com o interruptor desligado mostra "Em breve" e nada mais',
        (tester) async {
      final lidas = <String>[];
      await tester.pumpWidget(MaterialApp(
          home: LojaOnlineScreen(
              service: _servico(ligada: false, tabelasLidas: lidas))));
      await tester.pumpAndSettle();
      expect(find.text('Em breve'), findsOneWidget);
      expect(
          find.text('A Loja Online da Bora está quase pronta. Volta em breve.'),
          findsOneWidget);
      expect(find.text('Novidade da semana'), findsNothing);
      expect(lidas, isEmpty);
    });

    testWidgets('com as tabelas por instalar também é "Em breve"',
        (tester) async {
      await tester.pumpWidget(MaterialApp(
          home: LojaOnlineScreen(service: _servico(erroTabelas: _tabelaEmFalta))));
      await tester.pumpAndSettle();
      expect(find.text('Em breve'), findsOneWidget);
    });

    testWidgets('sem rede oferece "Tentar outra vez"', (tester) async {
      await tester.pumpWidget(MaterialApp(
          home: LojaOnlineScreen(
              service: _servico(erroTabelas: Exception('sem rede')))));
      await tester.pumpAndSettle();
      expect(find.text('Não foi possível carregar a loja. Tenta outra vez.'),
          findsOneWidget);
      expect(find.widgetWithText(OutlinedButton, 'Tentar outra vez'),
          findsOneWidget);
    });

    testWidgets('loja ligada mas vazia', (tester) async {
      await tester.pumpWidget(MaterialApp(
          home: LojaOnlineScreen(service: _servico(produtos: const []))));
      await tester.pumpAndSettle();
      expect(find.text('Ainda não há produtos nesta loja.'), findsOneWidget);
    });

    testWidgets(
        'vitrine: Novidade da semana no topo, grelha do nicho, abre a ficha com o botão Encomendar',
        (tester) async {
      _ecraGrande(tester);
      await tester.pumpWidget(MaterialApp(
          home: LojaOnlineScreen(
              service: _servico(produtos: [
        _produto(),
        _produto(id: 'p2', titulo: 'Cama para gato', preco: 2490, destaque: false),
      ]))));
      await tester.pumpAndSettle();

      expect(find.text('Loja Online'), findsOneWidget);
      expect(find.text('Novidade da semana'), findsOneWidget);
      expect(find.text('Pets'), findsNWidgets(2),
          reason: 'título da novidade e título do nicho');
      expect(find.text('Limpador de patas'), findsNWidgets(2),
          reason: 'na novidade e na grelha');
      expect(find.text('Cama para gato'), findsOneWidget,
          reason: 'sem destaque fica só na grelha');
      expect(find.text('12,90 €'), findsNWidgets(2));
      expect(find.text('24,90 €'), findsOneWidget);
      expect(find.text('7 a 15 dias úteis'), findsNWidgets(3),
          reason: 'Juiz 15/11 18:27 (D): dias úteis já na montra');

      await tester.tap(find.text('Cama para gato'));
      await tester.pumpAndSettle();
      expect(find.byType(ProdutoLojaOnlineScreen), findsOneWidget);
      expect(find.text('Cama para gato'), findsOneWidget);
      final botao = tester.widget<FilledButton>(
          find.byKey(const Key('loja_online_encomendar')));
      expect(botao.onPressed, isNotNull,
          reason: 'checkup-15-11: Encomendar abre o pagamento (MB WAY ou cartão)');
      expect(find.text('Pagas com MB WAY ou cartão e recebes pelo correio.'),
          findsOneWidget);
    });
  });

  group('ficha do produto', () {
    testWidgets('preço final, prazo em grande, descrição e botão que abre o pagamento',
        (tester) async {
      _ecraGrande(tester);
      await tester.pumpWidget(MaterialApp(
          home: ProdutoLojaOnlineScreen(
              produto: LojaOnlineProduto.fromJson(_produto()))));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('loja_online_preco')), findsOneWidget);
      expect(find.text('12,90 €'), findsOneWidget);
      expect(find.text('Preço final, com IVA e envio incluídos'), findsOneWidget);
      expect(find.text('Chega pelo correio em 7 a 15 dias úteis'), findsOneWidget);
      expect(find.text('Sobre este produto'), findsOneWidget);
      expect(find.text('Copo de silicone que limpa as patas em segundos.'),
          findsOneWidget);
      expect(find.text('Sem fotografia'), findsOneWidget,
          reason: 'sem imagens não tenta a rede');
      expect(find.text('Encomendar'), findsOneWidget);
      expect(
          tester
              .widget<FilledButton>(
                  find.byKey(const Key('loja_online_encomendar')))
              .onPressed,
          isNotNull);
      expect(find.text('Pagas com MB WAY ou cartão e recebes pelo correio.'),
          findsOneWidget);
      expect(find.text('6,45 €'), findsNothing,
          reason: 'o custo do fornecedor nunca aparece ao cliente');
    });

    testWidgets('sem prazo não mostra a caixa do correio', (tester) async {
      await tester.pumpWidget(MaterialApp(
          home: ProdutoLojaOnlineScreen(
              produto: LojaOnlineProduto.fromJson(
                  _produto(prazoMin: 0, prazoMax: 0, descricao: '')))));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('loja_online_prazo')), findsNothing);
      expect(find.text('Sobre este produto'), findsNothing);
    });
  });

  group('painel (PT-BR)', () {
    test('erros: por instalar dá a frase única; o resto segue o painel', () {
      expect(erroAdminLojaOnline(_tabelaEmFalta), kLojaOnlineNaoInstalada);
      expect(erroAdminLojaOnline(_funcaoEmFalta), kLojaOnlineNaoInstalada);
      expect(
          erroAdminLojaOnline(const PostgrestException(
              message: 'unknown_setting: loja_online_ativa', code: '23503')),
          kLojaOnlineNaoInstalada);
      expect(
          erroAdminLojaOnline(
              const PostgrestException(message: 'reason_required')),
          'Preencha o motivo (mínimo 3 caracteres).');
      expect(kLojaOnlineNaoInstalada,
          'Esta parte ainda não foi instalada no servidor.');
    });

    test('resumo do produto para a lista', () {
      final p = LojaOnlineProduto.fromJson(_produto());
      expect(resumoProdutoLojaOnline(p, 'Pets'),
          'Pets · Preço na Bora 12,90 € · custo 6,45 € · correio 7 a 15 dias');
      expect(
          resumoProdutoLojaOnline(
              LojaOnlineProduto.fromJson(_produto(prazoMin: 0, prazoMax: 0)), ''),
          'Preço na Bora 12,90 € · custo 6,45 €');
    });

    testWidgets('servidor por instalar: a frase aparece uma vez, com o caminho da proposta',
        (tester) async {
      _ecraGrande(tester);
      await tester.pumpWidget(MaterialApp(
          home: AdminLojaOnlineScreen(
              service: _painel(chaveFalha: true, erroTabelas: _tabelaEmFalta))));
      await tester.pumpAndSettle();
      expect(find.text(kLojaOnlineNaoInstalada), findsOneWidget);
      expect(find.textContaining('E_loja_online.PROPOSTA.sql'), findsOneWidget);
      expect(find.text('Tentar de novo'), findsOneWidget);
      expect(find.byKey(const Key('loja_online_interruptor')), findsNothing);
    });

    testWidgets('só a chave em falta: o interruptor fica bloqueado com a frase',
        (tester) async {
      _ecraGrande(tester);
      await tester.pumpWidget(MaterialApp(
          home: AdminLojaOnlineScreen(service: _painel(interruptor: null))));
      await tester.pumpAndSettle();
      final sw = tester.widget<SwitchListTile>(
          find.byKey(const Key('loja_online_interruptor')));
      expect(sw.onChanged, isNull);
      expect(sw.value, isFalse);
      expect(find.text(kLojaOnlineNaoInstalada), findsOneWidget);
      expect(find.text('Limpador de patas'), findsOneWidget,
          reason: 'os produtos continuam a listar-se');
    });

    testWidgets('com tudo instalado: interruptor desligado, nicho da semana, motivo obrigatório',
        (tester) async {
      _ecraGrande(tester);
      final chamadas = <String>[];
      await tester.pumpWidget(MaterialApp(
          home: AdminLojaOnlineScreen(service: _painel(chamadas: chamadas))));
      await tester.pumpAndSettle();

      expect(find.textContaining('Para que serve:'), findsOneWidget);
      final sw = tester.widget<SwitchListTile>(
          find.byKey(const Key('loja_online_interruptor')));
      expect(sw.value, isFalse);
      expect(sw.onChanged, isNotNull);
      expect(find.text('Nicho da semana'), findsOneWidget);
      expect(find.text('Em destaque'), findsOneWidget, reason: 'pets é o da semana');
      expect(find.text('Produtos (1)'), findsOneWidget);
      expect(find.text('Limpador de patas'), findsOneWidget);
      expect(find.textContaining('custo 6,45 €'), findsOneWidget,
          reason: 'o painel vê o custo; o cliente não');

      // Desligar "Ativo" pede motivo; cancelar não chama o servidor.
      final ativo = find.descendant(
          of: find.byKey(const Key('loja_online_ativo_p1')),
          matching: find.byType(Switch));
      await tester.tap(ativo);
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('loja_online_motivo')), findsOneWidget);
      await tester.tap(find.text('Cancelar'));
      await tester.pumpAndSettle();
      expect(chamadas, isEmpty);

      // Motivo curto é recusado no próprio painel.
      await tester.tap(ativo);
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const Key('loja_online_motivo')), 'ab');
      await tester.tap(find.text('Confirmar'));
      await tester.pumpAndSettle();
      expect(find.text('Escreva o motivo (mínimo 3 letras).'), findsOneWidget);
      expect(chamadas, isEmpty);

      // Motivo válido chama a RPC proposta.
      await tester.tap(ativo);
      await tester.pumpAndSettle();
      await tester.enterText(
          find.byKey(const Key('loja_online_motivo')), 'produto sem stock');
      await tester.tap(find.text('Confirmar'));
      await tester.pumpAndSettle();
      expect(chamadas, [kLojaOnlineRpcProdutoEstado]);
    });

    testWidgets('ligar o interruptor usa admin_update_setting depois de confirmar',
        (tester) async {
      _ecraGrande(tester);
      final chamadas = <String>[];
      await tester.pumpWidget(MaterialApp(
          home: AdminLojaOnlineScreen(service: _painel(chamadas: chamadas))));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('loja_online_interruptor')));
      await tester.pumpAndSettle();
      expect(find.text('Ligar a Loja Online no app?'), findsOneWidget);
      await tester.tap(find.text('Confirmar'));
      await tester.pumpAndSettle();
      expect(chamadas, ['admin_update_setting']);
    });
  });

  group('pagamento (checkup-15-11 B3.7)', () {
    test('telemóvel e código postal portugueses', () {
      expect(lojaOnlineTelemovel('912 345 678'), '912345678');
      expect(lojaOnlineTelemovel('+351 932345678'), '932345678');
      expect(lojaOnlineTelemovel('212345678'), isNull,
          reason: 'fixo não serve para MB WAY');
      expect(lojaOnlineCodigoPostal('6300-123'), '6300-123');
      expect(lojaOnlineCodigoPostal('6300123'), '6300-123');
      expect(lojaOnlineCodigoPostal('630-123'), isNull);
    });

    test('faltas da morada, vazio quando está tudo', () {
      expect(
          lojaOnlineFaltas(
              nome: 'Ana',
              telefone: '912345678',
              morada: 'Rua A 1',
              codigoPostal: '6300-123',
              localidade: 'Guarda'),
          isEmpty);
      expect(
          lojaOnlineFaltas(
                  nome: '',
                  telefone: '1',
                  morada: '',
                  codigoPostal: 'x',
                  localidade: '')
              .length,
          5);
    });

    test('o corpo para o servidor nunca leva preço e marca as duas contas', () {
      final c = const LojaOnlinePedidoPagamento(
        produtoId: 'p1',
        quantidade: 2,
        metodo: LojaOnlineMetodo.mbway,
        nome: ' Ana Sousa ',
        telefone: '+351912345678',
        morada: 'Rua A 1',
        codigoPostal: '6300123',
        localidade: 'Guarda',
      ).corpo();
      expect(c['acao'], 'criar');
      expect(c['metodo'], 'mbway');
      expect(c['telefone'], '912345678');
      expect(c['codigo_postal'], '6300-123');
      expect(
          c.keys.where((k) =>
              k.contains('preco') || k.contains('total') || k.contains('amount')),
          isEmpty);
      expect(c['stripe_contas_v2'], isTrue);
    });

    test('erro do servidor vira frase para o cliente', () async {
      final s = LojaOnlinePagamentoService(
          invocar: (f, b) async => {'error': 'loja_fechada'});
      await expectLater(
          s.criar(const LojaOnlinePedidoPagamento(
              produtoId: 'p1',
              quantidade: 1,
              metodo: LojaOnlineMetodo.cartao,
              nome: 'Ana',
              telefone: '912345678',
              morada: 'Rua A 1',
              codigoPostal: '6300-123',
              localidade: 'Guarda')),
          throwsA(isA<StateError>().having(
              (e) => e.message, 'message', 'A loja ainda não está aberta.')));
    });

    test('pagamento recusado e travão de tentativas têm frase própria', () {
      expect(lojaOnlineErroPagamento('pagamento_recusado'), contains('recusado'));
      expect(lojaOnlineErroPagamento('demasiadas_tentativas'), contains('Espera uns minutos'));
      expect(lojaOnlineErroPagamento('Stripe: card_declined xyz'),
          'Não foi possível iniciar o pagamento. Tenta outra vez.',
          reason: 'nunca a mensagem crua');
    });

    test('Juiz 18:27: webhook e vigia conhecem a loja; a Edge recusa PI de outra encomenda', () {
      final core = File('supabase/functions/_shared/stripe_webhook_core.ts').readAsStringSync();
      expect(core, contains("if (intent.metadata?.kind === 'loja_online') {"));
      expect(core.split("intent.metadata?.kind === 'loja_online'").length - 1, 2,
          reason: 'succeeded e failed/canceled');
      final rec = File('supabase/functions/payments-reconciler/index.ts').readAsStringSync();
      expect(rec, contains("if (k === 'loja_online') {"));
      final edge = File('supabase/functions/loja-online-pagamento/index.ts').readAsStringSync();
      expect(edge, contains('pi.metadata?.encomenda_id !== enc.id'));
      expect(edge, contains("'demasiadas_tentativas'"));
      expect(edge, contains("'pagamento_recusado'"));
      expect(edge, contains("rpc('is_admin')"));
      final sql = File('docs/propostas/checkup-15-11/B3_7_loja_online_encomendas.PROPOSTA.sql').readAsStringSync();
      expect(sql, contains('revoke select on public.loja_online_produtos from anon;'));
      expect(sql, contains("raise exception 'pi_aberto'"));
      final svc = File('lib/services/loja_online_service.dart').readAsStringSync();
      expect(svc, contains('kLojaOnlineColunasCliente'));
      expect(kLojaOnlineColunasCliente, isNot(contains('custo')));
    });

    test('esperarPagamento para quando fica paga', () async {
      var n = 0;
      final s = LojaOnlinePagamentoService(invocar: (f, b) async {
        n++;
        return {'ok': true, 'estado': n < 3 ? 'aguarda_pagamento' : 'paga'};
      });
      final e = await s.esperarPagamento('e1',
          intervalo: Duration.zero, limite: const Duration(seconds: 5));
      expect(e, 'paga');
      expect(n, 3);
    });

    test('lista de permissão: a função do servidor manda; sem ela vale o interruptor',
        () async {
      final dono = _servico(ligada: false, lerVisivel: () async => true);
      expect(await dono.atualizarInterruptor(), isTrue);
      final outro = _servico(ligada: true, lerVisivel: () async => false);
      expect(await outro.atualizarInterruptor(), isFalse);
      final antigo = _servico(ligada: true);
      expect(await antigo.atualizarInterruptor(), isTrue);
    });

    testWidgets('checkout: total com a quantidade, sem dinheiro, aviso da morada',
        (tester) async {
      _ecraGrande(tester);
      var chamadas = 0;
      await tester.pumpWidget(MaterialApp(
          home: CheckoutLojaOnlineScreen(
              produto: LojaOnlineProduto.fromJson(_produto()),
              perfil: () async => const LojaOnlinePerfil(),
              servico: LojaOnlinePagamentoService(invocar: (f, b) async {
                chamadas++;
                return null;
              }))));
      await tester.pumpAndSettle();
      expect(find.text('Pagar 12,90 €'), findsOneWidget);
      await tester.tap(find.byKey(const Key('loja_online_mais')));
      await tester.pumpAndSettle();
      expect(find.text('Pagar 25,80 €'), findsOneWidget);
      expect(find.text('Dinheiro'), findsNothing);
      await tester.tap(find.byKey(const Key('loja_online_pagar')));
      await tester.pumpAndSettle();
      expect(find.text('Escreve o teu nome completo.'), findsOneWidget);
      expect(chamadas, 0, reason: 'sem morada não se chama o servidor');
    });

    test('painel: passos de logística e nomes dos estados', () {
      expect(adminProximoPasso('paga'), 'encomendada_fornecedor');
      expect(adminProximoPasso('encomendada_fornecedor'), 'enviada');
      expect(adminProximoPasso('enviada'), 'entregue');
      expect(adminProximoPasso('aguarda_pagamento'), isNull);
      expect(adminEstadoEncomenda('paga'), contains('PAGA'));
    });

    test('proposta SQL das encomendas e Edge batem com a app', () {
      final sql = File(
              'docs/propostas/checkup-15-11/B3_7_loja_online_encomendas.PROPOSTA.sql')
          .readAsStringSync()
          .replaceAll('\r\n', '\n');
      expect(sql,
          contains('create table if not exists public.loja_online_encomendas'));
      expect(sql, contains('function public.loja_online_visivel_para_mim()'));
      expect(sql,
          contains('function public.admin_loja_online_encomendas(p_estado text default null)'));
      expect(sql, contains('function public.admin_loja_online_encomenda_estado('));
      expect(sql, contains("metodo in ('card', 'mbway')"));
      final codigoSql =
          sql.split('\n').map((l) => l.split('--').first).join('\n');
      expect(codigoSql, isNot(contains('current_user')));
      final edge = File('supabase/functions/loja-online-pagamento/index.ts')
          .readAsStringSync();
      expect(edge, contains("kind: 'loja_online'"));
      expect(edge, contains('preco_bora_cents'));
      expect(edge, isNot(contains("'cash'")));
    });
  });

  group('l10n e código', () {
    test('toda frase .tr dos ecrãs da Loja Online tem inglês', () {
      final emFalta = <String>[];
      var total = 0;
      for (final f in _ficheirosCliente) {
        final src = File(f).readAsStringSync();
        for (final m in _padraoTr.allMatches(src)) {
          total++;
          final chave = m.group(2)!.replaceAll(r"\'", "'");
          if (!kStringsEn.containsKey(chave)) emFalta.add('$f: $chave');
        }
      }
      expect(total, greaterThan(10), reason: 'a rede tem de apanhar as frases');
      expect(emFalta, isEmpty);
      expect(kStringsEn['Loja Online'], 'Online Store',
          reason: 'o ladrilho da home passa por .tr');
      expect(kStringsEn['Em breve'], isNotNull);
      expect(kStringsEn['Tentar outra vez'], isNotNull);
    });

    test('o painel é PT-BR sem .tr; nenhum ficheiro novo toca em preços, carrinho ou pagamentos',
        () {
      final admin =
          File('lib/screens/admin/admin_loja_online_screen.dart').readAsStringSync();
      expect(_padraoTr.hasMatch(admin), isFalse);
      for (final f in _ficheirosNovos) {
        final src = File(f).readAsStringSync();
        expect(src, isNot(contains('pricing_service.dart')), reason: f);
        expect(src, isNot(contains('order_store.dart')), reason: f);
        expect(src, isNot(contains('cart_store.dart')), reason: f);
        expect(src, isNot(contains('payment_service.dart')), reason: f);
        expect(src, isNot(contains('stripe_')), reason: f);
      }
    });

    test('a proposta SQL existe e bate certo com o que a app chama', () {
      final sql = File('docs/propostas/fechar-tudo-15-11/E_loja_online.PROPOSTA.sql')
          .readAsStringSync();
      expect(sql, contains('create table if not exists public.loja_online_nichos'));
      expect(sql, contains('create table if not exists public.loja_online_produtos'));
      expect(sql, contains("'loja_online_ativa', 'false'::jsonb"));
      expect(sql, contains('on conflict (key) do nothing'));
      expect(
          sql,
          contains(
              'admin_loja_online_produto_estado(p_id uuid, p_ativo boolean, p_destaque boolean, p_motivo text)'));
      expect(sql,
          contains('admin_loja_online_nicho_da_semana(p_nicho_id uuid, p_motivo text)'));
      expect(sql, contains('public.is_admin()'));
      expect(sql, contains('public.log_admin_action('));
      expect(sql, contains('security definer'));
      expect(sql, contains('enable row level security'));
      expect(sql, contains("('pets', 'Pets'"));
      // 15/11 (CI 308): só o código conta — o comentário da proposta explica
      // justamente que a guarda é is_admin() e "nunca current_user".
      final codigoSql = sql
          .split('\n')
          .map((l) => l.split('--').first)
          .join('\n');
      expect(codigoSql, isNot(contains('current_user')),
          reason: 'guarda por is_admin(), nunca current_user');
      expect(sql.toLowerCase(), isNot(contains('shpat_')),
          reason: 'nenhum token da Shopify no repo');
    });
  });
}
