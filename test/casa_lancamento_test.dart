// CASA & MANUTENÇÃO — lançamento como NOVIDADE (m11, adendo 3, 09/11/2026).
//
// Ordem do Danilo (09/11 06:54 e 07:02): "o profissional leva só as
// ferramentas, o material é pelo cliente"; "publique já … com o ícone
// certinho, 3D, cartoon; deixa publicada como novidade".
//
// Prova, sem rede:
//  1. a pergunta `material` é OBRIGATÓRIA e só passa com "Sim, já tenho tudo";
//  2. o ecrã do serviço e o resumo dizem que o material é do cliente;
//  3. o profissional vê "Material do cliente" na oferta;
//  4. o selo "Novo" vive numa data de definição (`casa_novo_ate`), hora de
//     Lisboa, e desliga-se com o valor vazio;
//  5. o painel liga/desliga o selo e escolhe a data;
//  6. o ícone `cat_casa.png` existe, é quadrado 1024, opaco, e está ligado ao
//     ladrilho da home.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:provider/provider.dart';

import 'package:bora_app/models/casa_models.dart';
import 'package:bora_app/screens/admin/admin_casa_comum.dart'
    show casaHojeLisboa;
import 'package:bora_app/screens/admin/admin_casa_definicoes_tab.dart';
import 'package:bora_app/screens/client/casa/casa_pedido_wizard_screen.dart';
import 'package:bora_app/screens/client/casa/casa_regras.dart';
import 'package:bora_app/screens/handyman/handyman_home_screen.dart'
    show CasaOfertaCartao;
import 'package:bora_app/stores/casa_store.dart';
import 'package:bora_app/widgets/bora/bora_tile_card.dart';

import 'golden/fabrica_de_fotos.dart';

// A pergunta tal como está no catálogo de produção (lida a 09/11/2026).
const _perguntaMaterial = {
  'id': 'material',
  'tipo': 'escolha',
  'texto':
      'O profissional leva só as ferramentas. Já tens todo o material (peças, parafusos, suportes, silicone)?',
  'opcoes': ['Sim, já tenho tudo'],
};

final _roupeiro = CasaServico.fromJson({
  'id': 's-roupeiro',
  'oficio': 'montagem',
  'nome': 'Montar roupeiro',
  'modo': 'fixo',
  'preco_cents': 8000,
  'unidade': 'movel',
  'min_quantidade': 1,
  'perguntas': [
    {
      'id': 'marca',
      'tipo': 'escolha',
      'texto': 'É do IKEA ou de outra marca?',
      'opcoes': ['IKEA', 'Outra marca', 'Não sei'],
    },
    _perguntaMaterial,
  ],
});

final _semMaterial = CasaServico.fromJson({
  'id': 's-mato',
  'oficio': 'jardinagem',
  'nome': 'Limpar terreno ou mato grande',
  'modo': 'orcamento',
  'perguntas': [
    {'id': 'tamanho', 'tipo': 'texto', 'texto': 'Mais ou menos que área tem?'},
  ],
});

final _config = CasaConfig.fromJson({
  'visivel': true,
  'enabled': true,
  'valores_autorizados': true,
  'max_cash_cents': 4000,
  'max_fotos': 5,
  'min_lead_hours': 2,
  'quote_max_pros': 3,
  'oficios': [
    {'codigo': 'montagem', 'nome': 'Montagem de móveis', 'fase': 1, 'ativo': true},
  ],
  'servicos': [
    {
      'id': 's-roupeiro',
      'oficio': 'montagem',
      'nome': 'Montar roupeiro',
      'modo': 'fixo',
      'preco_cents': 8000,
      'unidade': 'movel',
    },
  ],
});

class _Rpc {
  _Rpc(this.respostas);
  final Map<String, dynamic> respostas;
  final chamadas = <(String, Map<String, dynamic>)>[];

  Future<dynamic> call(String fn, Map<String, dynamic> params) async {
    chamadas.add((fn, params));
    return respostas[fn];
  }

  List<Map<String, dynamic>> de(String fn) =>
      [for (final c in chamadas) if (c.$1 == fn) c.$2];
}

Future<void> _montarWizard(WidgetTester tester, CasaServico s) async {
  tester.view.physicalSize = const Size(430, 2400);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(ChangeNotifierProvider<CasaStore>.value(
    value: CasaStore.semRede(config: _config),
    child: MaterialApp(home: CasaPedidoWizardScreen(servico: s)),
  ));
  await tester.pump();
}

/// Deixa acabar o que a morada automática deixou a correr (sem GPS no teste).
Future<void> _assentar(WidgetTester tester) async {
  await tester.pump(const Duration(seconds: 30));
  await tester.pump(const Duration(seconds: 30));
}

void main() {
  group('material do cliente — regra do pedido', () {
    test('o serviço com a pergunta `material` pede-a; o orçamento não', () {
      expect(casaServicoPedeMaterial(_roupeiro), isTrue);
      expect(casaServicoPedeMaterial(_semMaterial), isFalse);
    });

    test('sem resposta ao material não deixa pedir, e diz porquê', () {
      final falta = casaFaltaNoServico(
        servico: _roupeiro,
        respostas: {'marca': 'IKEA'},
        quantidade: 1,
        descricao: '',
      );
      expect(falta, isNotNull);
      expect(falta!.campo, CasaCampo.pergunta);
      expect(falta.perguntaId, kCasaPerguntaMaterial);
      expect(falta.mensagem, contains('o profissional leva só as ferramentas'));
    });

    test('outra resposta qualquer (se o painel um dia a juntar) também não',
        () {
      final falta = casaFaltaNoServico(
        servico: _roupeiro,
        respostas: {'marca': 'IKEA', 'material': 'Não, compra o profissional'},
        quantidade: 1,
        descricao: '',
      );
      expect(falta?.perguntaId, kCasaPerguntaMaterial);
    });

    test('com "Sim, já tenho tudo" passa', () {
      expect(
        casaFaltaNoServico(
          servico: _roupeiro,
          respostas: {'marca': 'IKEA', 'material': kCasaMaterialSim},
          quantidade: 1,
          descricao: '',
        ),
        isNull,
      );
      expect(kCasaMaterialSim, 'Sim, já tenho tudo',
          reason: 'tem de bater com a opção gravada no catálogo');
    });

    test('o profissional só lê "material do cliente" quando o cliente confirmou',
        () {
      expect(casaMaterialDoCliente({'material': 'Sim, já tenho tudo'}), isTrue);
      expect(casaMaterialDoCliente({'material': ''}), isFalse);
      expect(casaMaterialDoCliente(const {}), isFalse);
    });
  });

  group('material do cliente — ecrãs', () {
    testWidgets(
        'ecrã do serviço: aviso à vista e "Continuar" sem o material avisa',
        (tester) async {
      await _montarWizard(tester, _roupeiro);
      expect(find.byKey(const Key('casa_aviso_material')), findsOneWidget);
      expect(
          find.textContaining('O profissional leva só as ferramentas. O material'),
          findsOneWidget);
      expect(find.text('Sim, já tenho tudo'), findsOneWidget);

      await tester.tap(find.text('IKEA'));
      await tester.pump();
      await tester.tap(find.text('Continuar'));
      await tester.pump(const Duration(milliseconds: 400));
      expect(
          find.text(
              'Para pedir, confirma que já tens todo o material: o profissional leva só as ferramentas.'),
          findsOneWidget,
          reason: 'o botão nunca falha calado');
      // Continua no passo 1 (o aviso do material ainda está lá).
      expect(find.byKey(const Key('casa_aviso_material')), findsOneWidget);

      // Com a confirmação, passa ao passo 2.
      await tester.tap(find.text('Sim, já tenho tudo'));
      await tester.pump();
      await tester.tap(find.text('Continuar'));
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.byKey(const Key('casa_aviso_material')), findsNothing);
      await _assentar(tester);
      expect(tester.takeException(), isNull);
    });

    testWidgets('serviço sem a pergunta do material não mostra o aviso',
        (tester) async {
      await _montarWizard(tester, _semMaterial);
      expect(find.byKey(const Key('casa_aviso_material')), findsNothing);
      await _assentar(tester);
    });

    testWidgets('o profissional vê "Material do cliente" na oferta',
        (tester) async {
      Map<String, dynamic> oferta(Map<String, dynamic> respostas) => {
            'pedido_id': 'p1',
            'tipo': 'oferta',
            'oficio': 'montagem',
            'oficio_nome': 'Montagem de móveis',
            'servico_nome': 'Montar roupeiro',
            'modo': 'fixo',
            'respostas': respostas,
            'localidade': 'Guarda',
            'scheduled_at': '2026-11-12T10:00:00Z',
            'ganho_cents': 6800,
            'total_cents': 8000,
          };
      Widget app(Map<String, dynamic> m) => MaterialApp(
            home: Scaffold(
              body: SingleChildScrollView(
                child: CasaOfertaCartao(oferta: CasaOferta.fromJson(m)),
              ),
            ),
          );

      await tester.pumpWidget(
          app(oferta({'marca': 'IKEA', 'material': 'Sim, já tenho tudo'})));
      expect(find.byKey(const Key('casa_oferta_material')), findsOneWidget);
      expect(find.text('Material do cliente — levas só as ferramentas'),
          findsOneWidget);

      await tester.pumpWidget(app(oferta({'marca': 'IKEA'})));
      expect(find.byKey(const Key('casa_oferta_material')), findsNothing);
    });
  });

  group('selo "Novo" — data na definição, hora de Lisboa', () {
    test('sem data, vazio ou ilegível: sem selo', () {
      final agora = DateTime.utc(2026, 11, 9, 12);
      expect(casaSeloNovoVisivel(null, agora), isFalse);
      expect(casaSeloNovoVisivel('', agora), isFalse);
      expect(casaSeloNovoVisivel('amanhã', agora), isFalse);
    });

    test('até ao fim do último dia, no relógio de Lisboa', () {
      // Inverno (UTC+0).
      expect(casaSeloNovoVisivel('2026-11-23', DateTime.utc(2026, 11, 9, 8)),
          isTrue);
      expect(casaSeloNovoVisivel('2026-11-23', DateTime.utc(2026, 11, 23, 23, 59)),
          isTrue);
      expect(casaSeloNovoVisivel('2026-11-23', DateTime.utc(2026, 11, 24, 0, 0)),
          isFalse);
      // Verão (UTC+1): 23:30 UTC já é o dia seguinte em Lisboa.
      expect(casaSeloNovoVisivel('2026-07-10', DateTime.utc(2026, 7, 10, 22, 59)),
          isTrue);
      expect(casaSeloNovoVisivel('2026-07-10', DateTime.utc(2026, 7, 10, 23, 30)),
          isFalse);
      // O valor pode chegar com aspas (jsonb texto).
      expect(casaSeloNovoVisivel('"2026-11-23"', DateTime.utc(2026, 11, 20)),
          isTrue);
    });

    test('a loja lê o selo da definição', () {
      final s = CasaStore.semRede(config: _config, novoAte: '2026-11-23');
      expect(s.seloNovo(DateTime.utc(2026, 11, 10)), isTrue);
      expect(s.seloNovo(DateTime.utc(2026, 12, 1)), isFalse);
      expect(CasaStore.semRede(config: _config).seloNovo(), isFalse);
      expect(CasaStore.kCasaChaveNovoAte, kCasaChaveNovoAte,
          reason: 'a app e o painel usam a mesma chave');
    });

    test('ligar sem data dá 14 dias a contar de hoje (Lisboa)', () {
      expect(casaNovoAteAoLigar(DateTime.utc(2026, 11, 9)), '2026-11-23');
      expect(kCasaDiasSeloNovo, 14);
    });

    testWidgets('o ladrilho desenha o selo só quando o recebe', (tester) async {
      Widget ladrilho(String? selo) => MaterialApp(
            home: Scaffold(
              body: Center(
              child: SizedBox(
                width: 90,
                height: 102,
                child: BoraTileCard.image(
                  label: 'Casa e\nManutenção',
                  gradient: const LinearGradient(
                      colors: [Colors.brown, Colors.brown]),
                  imageAsset: 'assets/categories/cat_casa.png',
                  onTap: () {},
                  compacto: true,
                  selo: selo,
                ),
              ),
              ),
            ),
          );
      await tester.pumpWidget(ladrilho('Novo'));
      expect(find.byKey(const Key('bora_tile_selo')), findsOneWidget);
      expect(find.text('Novo'), findsOneWidget);
      expect(find.text('Casa e\nManutenção'), findsOneWidget);
      expect(tester.takeException(), isNull);

      await tester.pumpWidget(ladrilho(null));
      expect(find.byKey(const Key('bora_tile_selo')), findsNothing);
    });
  });

  group('painel (PT-BR): selo "Novo" e faixa', () {
    void ecraGrande(WidgetTester tester) {
      tester.view.physicalSize = const Size(1400, 4000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
    }

    Map<String, dynamic> respostas(Object? novoAte) => {
          'admin_casa_definicoes': [
            {'key': 'casa_enabled', 'value': true, 'description': 'Casa ligada'},
            if (novoAte != null)
              {
                'key': 'casa_novo_ate',
                'value': novoAte,
                'description': 'Selo Novo até',
              },
          ],
          'admin_casa_resumo': {
            'enabled': true,
            'valores_autorizados': {'autorizado': true},
          },
          'admin_casa_guardar_definicao': {'ok': true},
        };

    testWidgets('desligado: ligar grava hoje + 14 dias em casa_novo_ate',
        (tester) async {
      ecraGrande(tester);
      final rpc = _Rpc(respostas(''));
      await tester.pumpWidget(MaterialApp(
          home: Scaffold(body: AdminCasaDefinicoesTab(rpc: rpc.call))));
      await tester.pumpAndSettle();
      expect(find.text('Novidade (lançamento)'), findsOneWidget);
      expect(find.text('Desligado.'), findsOneWidget);
      expect(find.byKey(const ValueKey('casa-faixa-home')), findsOneWidget);
      // A chave não aparece duplicada em "Tempos e limites".
      expect(find.text('casa_novo_ate'), findsNothing);

      await tester.tap(find.byKey(const ValueKey('casa-selo-novo')));
      await tester.pumpAndSettle();
      final gravou = rpc.de('admin_casa_guardar_definicao');
      expect(gravou, hasLength(1));
      expect(gravou.single['p_key'], 'casa_novo_ate');
      expect(gravou.single['p_value'], casaNovoAteAoLigar(casaHojeLisboa()));
    });

    testWidgets('ligado: desligar grava o valor vazio', (tester) async {
      ecraGrande(tester);
      final ate = casaNovoAteAoLigar(casaHojeLisboa());
      final rpc = _Rpc(respostas(ate));
      await tester.pumpWidget(MaterialApp(
          home: Scaffold(body: AdminCasaDefinicoesTab(rpc: rpc.call))));
      await tester.pumpAndSettle();
      expect(find.textContaining('Aparece no atalho "Casa"'), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('casa-selo-novo')));
      await tester.pumpAndSettle();
      expect(rpc.de('admin_casa_guardar_definicao').single['p_value'], '');
    });

    testWidgets('sem a chave no servidor: interruptor travado e explica',
        (tester) async {
      ecraGrande(tester);
      final rpc = _Rpc(respostas(null));
      await tester.pumpWidget(MaterialApp(
          home: Scaffold(body: AdminCasaDefinicoesTab(rpc: rpc.call))));
      await tester.pumpAndSettle();
      expect(find.textContaining('ainda não existe no servidor'), findsOneWidget);
      final sw = tester.widget<SwitchListTile>(
          find.byKey(const ValueKey('casa-selo-novo')));
      expect(sw.onChanged, isNull);
    });
  });

  group('ícone cat_casa.png', () {
    test('existe, é quadrado 1024, sem um único píxel transparente', () {
      final f = File('assets/categories/cat_casa.png');
      expect(f.existsSync(), isTrue);
      final im = img.decodePng(f.readAsBytesSync());
      expect(im, isNotNull);
      expect(im!.width, 1024);
      expect(im.height, 1024);
      var transparentes = 0;
      for (final p in im) {
        if (p.a < p.maxChannelValue) transparentes++;
      }
      expect(transparentes, 0, reason: 'fundo de cor cheia, nunca transparente');
    });

    test('está ligado ao ladrilho da Casa na home (sem o ícone provisório)', () {
      final h = File('lib/screens/client_home_screen.dart').readAsStringSync();
      final i = h.indexOf("label: 'Casa e\\nManutenção'");
      expect(i, greaterThan(0));
      final bloco = h.substring(i, h.indexOf('onTap:', i));
      expect(bloco, contains("imageAsset: 'assets/categories/cat_casa.png'"));
      expect(bloco, contains('seloNovo()'));
      expect(bloco, isNot(contains('Icons.handyman_rounded')));
    });
  });

  group('fotografias', () {
    setUpAll(() async {
      await carregaFonteInter();
      await carregaFontesSdk();
    });

    testWidgets('ecrã do serviço "Montar roupeiro" com o aviso do material',
        (tester) async {
      await fotografaTela(
        tester,
        nome: 'casa_servico_roupeiro',
        tela: ChangeNotifierProvider<CasaStore>.value(
          value: CasaStore.semRede(config: _config),
          child: CasaPedidoWizardScreen(servico: _roupeiro),
        ),
        tamanho: kTamanhos[1],
      );
      await _assentar(tester);
      expect(File('test/golden/_fotos/casa_servico_roupeiro_medio.png')
          .existsSync(), isTrue);
    });
  });
}
