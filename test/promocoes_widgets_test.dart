// Promoções com preço riscado (adendo 5 · item 4, 29/10/2026): os ecrãs.
// O cartão do cliente (só mostra o riscado quando o servidor devolve a promoção),
// o formulário do parceiro e o painel do admin. Sem rede: o servidor é trocado
// por uma porta de mentira e os nomes são inventados.
import 'package:bora_app/l10n/bora_lang.dart';
import 'package:bora_app/screens/admin/admin_promocoes_screen.dart';
import 'package:bora_app/services/partner_price_rules.dart';
import 'package:bora_app/services/promocoes_service.dart';
import 'package:bora_app/models/partner_product.dart';
import 'package:bora_app/widgets/preco_com_promocao.dart';
import 'package:bora_app/widgets/promocao_parceiro_form.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

final DateTime _agora = DateTime.utc(2026, 10, 29, 12);

void ecraAlto(WidgetTester t) {
  t.view.physicalSize = const Size(900, 3200);
  t.view.devicePixelRatio = 1.0;
  addTearDown(t.view.resetPhysicalSize);
  addTearDown(t.view.resetDevicePixelRatio);
}

Map<String, dynamic> linha({
  String id = 'p1',
  num preco = 10,
  num promo = 7,
  num? minimo = 10,
  String inicio = '2026-10-29T10:00:00Z',
  String? fim = '2026-10-30T10:00:00Z',
}) =>
    {
      'product_id': id,
      'price': preco,
      'discount_price': promo,
      'starts_at': inicio,
      'ends_at': fim,
      'lowest_price_30d': minimo,
    };

Future<PromocoesLoja> lojaCom(List<Map<String, dynamic>> linhas) async {
  final loja = PromocoesLoja(
    buscar: (_) async => linhas,
    relogio: () => _agora,
  );
  PromocoesLoja.usarParaTeste(loja);
  return loja;
}

Widget preco({bool parceira = true, String produto = 'p1'}) => MaterialApp(
      home: Scaffold(
        body: Center(
          child: PrecoComPromocao(
            restaurantId: 'loja1',
            productId: produto,
            isPartnerStore: parceira,
            estiloPreco: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
            semPromocao: const Text('PRECO NORMAL', key: Key('sem_promo')),
          ),
        ),
      ),
    );

void main() {
  setUp(() => BoraLang.notifier.value = AppLang.pt);

  group('PrecoComPromocao (o cartão do cliente)', () {
    testWidgets('sem promoção devolvida pelo servidor (interruptor desligado): o preço de sempre',
        (t) async {
      await lojaCom(const []);
      await t.pumpWidget(preco());
      await t.pumpAndSettle();
      expect(find.byKey(const Key('sem_promo')), findsOneWidget);
      expect(find.byKey(const Key('promo_preco_atual')), findsNothing);
      expect(find.byKey(const Key('promo_preco_riscado')), findsNothing);
      expect(find.byKey(const Key('promo_omnibus')), findsNothing);
    });

    testWidgets('com promoção ativa: preço novo, preço antigo riscado e a linha dos 30 dias',
        (t) async {
      await lojaCom([linha()]);
      await t.pumpWidget(preco());
      await t.pumpAndSettle();
      expect(find.byKey(const Key('sem_promo')), findsNothing);
      expect(find.text('7,00 €'), findsOneWidget);
      expect(find.text('10,00 €'), findsOneWidget);
      final riscado = t.widget<Text>(find.byKey(const Key('promo_preco_riscado')));
      expect(riscado.style?.decoration, TextDecoration.lineThrough);
      expect(find.text('Preço mais baixo dos últimos 30 dias: 10,00 €'), findsOneWidget);
    });

    testWidgets('loja não parceira: os três valores levam os 15 %', (t) async {
      await lojaCom([linha(preco: 4, promo: 3, minimo: 4)]);
      await t.pumpWidget(preco(parceira: false));
      await t.pumpAndSettle();
      expect(find.text('3,45 €'), findsOneWidget);
      expect(find.text('4,60 €'), findsOneWidget); // o riscado
      expect(find.text('Preço mais baixo dos últimos 30 dias: 4,60 €'), findsOneWidget);
    });

    testWidgets('outro produto da mesma loja sem promoção: preço de sempre', (t) async {
      await lojaCom([linha()]);
      await t.pumpWidget(preco(produto: 'outro'));
      await t.pumpAndSettle();
      expect(find.byKey(const Key('sem_promo')), findsOneWidget);
    });

    testWidgets('promoção que já acabou: o preço de sempre', (t) async {
      await lojaCom([linha(fim: '2026-10-29T11:59:59Z')]);
      await t.pumpWidget(preco());
      await t.pumpAndSettle();
      expect(find.byKey(const Key('sem_promo')), findsOneWidget);
    });

    testWidgets('sem descida real em relação ao mais baixo dos 30 dias: só o preço que se paga',
        (t) async {
      await lojaCom([linha(minimo: 6)]);
      await t.pumpWidget(preco());
      await t.pumpAndSettle();
      expect(find.text('7,00 €'), findsOneWidget);
      expect(find.byKey(const Key('promo_preco_riscado')), findsNothing);
      expect(find.byKey(const Key('promo_omnibus')), findsNothing);
    });

    testWidgets('em inglês a linha legal sai em inglês', (t) async {
      BoraLang.notifier.value = AppLang.en;
      addTearDown(() => BoraLang.notifier.value = AppLang.pt);
      await lojaCom([linha()]);
      await t.pumpWidget(preco());
      await t.pumpAndSettle();
      expect(find.text('Lowest price in the last 30 days: 10,00 €'), findsOneWidget);
    });
  });

  group('carrossel e coluna estreita', () {
    testWidgets('a altura do carrossel só cresce quando há promoção ativa', (t) async {
      await lojaCom([linha()]);
      Widget carrossel(List<String> ids) => MaterialApp(
            home: Scaffold(
              body: AlturaCarrosselPromocao(
                restaurantId: 'loja1',
                produtosIds: ids,
                altura: 210,
                child: const SizedBox.expand(key: Key('corpo')),
              ),
            ),
          );
      await t.pumpWidget(carrossel(['outro']));
      expect(t.getSize(find.byKey(const Key('corpo'))).height, 210);
      // Sem ainda ter lido a loja: continua 210; lida a promoção, sobe 30.
      await PromocoesLoja.instance.garantir('loja1');
      await t.pumpWidget(carrossel(['p1', 'outro']));
      await t.pumpAndSettle();
      expect(t.getSize(find.byKey(const Key('corpo'))).height, 240);
    });

    testWidgets('na coluna mais estreita (cartão Glovo) não rebenta e não cresce sem limite',
        (t) async {
      await lojaCom([linha()]);
      await t.pumpWidget(const MaterialApp(
        home: Scaffold(
          body: Align(
            alignment: Alignment.topLeft,
            child: SizedBox(
              width: 88,
              child: PrecoComPromocao(
                restaurantId: 'loja1',
                productId: 'p1',
                isPartnerStore: true,
                estiloPreco:
                    TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700),
                semPromocao: Text('NORMAL'),
              ),
            ),
          ),
        ),
      ));
      await t.pumpAndSettle();
      expect(t.takeException(), isNull);
      // Nos testes o tipo de letra (Ahem) é quase 1,5 vez mais largo que o Inter
      // da app: aqui o teto é largo de propósito. Com o Inter são ~66 px, que
      // cabem nos 90 px que o carrossel ganha (AlturaCarrosselPromocao).
      expect(t.getSize(find.byType(PrecoComPromocao)).height, lessThan(115));
    });
  });

  group('PromocaoParceiroForm (editar produto do parceiro)', () {
    PartnerProduct produto({double preco = 10, double? balcao = 8.0}) => PartnerProduct(
          id: 'p1',
          restaurantId: 'loja1',
          name: 'Bitoque',
          description: '',
          price: preco,
          partnerShelfPrice: balcao,
          photoUrl: '',
          isAvailable: true,
        );

    Future<void> abrir(WidgetTester t, ApiParceiroFalsa api,
        {bool parceira = true, PartnerPriceRules? regras, PartnerProduct? p}) async {
      ecraAlto(t);
      await t.pumpWidget(MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: PromocaoParceiroForm(
              product: p ?? produto(),
              lojaParceira: parceira,
              regras: regras,
              api: api,
            ),
          ),
        ),
      ));
      await t.pumpAndSettle();
    }

    testWidgets('interruptor desligado: o formulário nem aparece', (t) async {
      final api = ApiParceiroFalsa(ligadoGeral: false);
      await abrir(t, api);
      expect(find.byKey(const Key('promocao_parceiro')), findsNothing);
      expect(api.chamadas, isEmpty);
    });

    testWidgets('loja não parceira: grava o preço escrito, sem conversão', (t) async {
      final api = ApiParceiroFalsa();
      await abrir(t, api, parceira: false, p: produto(balcao: null));
      await t.enterText(find.byKey(const Key('promo_preco')), '7,50');
      await t.tap(find.byKey(const Key('promo_guardar')));
      await t.pumpAndSettle();
      expect(api.chamadas, ['definir p1 7.5 null null']);
      expect(find.byKey(const Key('promo_ok')), findsOneWidget);
    });

    testWidgets('loja parceira: o balcão promocional vira o preço que o cliente vê', (t) async {
      final api = ApiParceiroFalsa();
      const regras = PartnerPriceRules(visibleCommissionPct: 0.10, hiddenMarkupPct: 0.05);
      await abrir(t, api, regras: regras);
      await t.enterText(find.byKey(const Key('promo_preco')), '6,00');
      await t.pump();
      // Mostra quanto o cliente vai ver: 6,00 → 7,00 (em vez de 10,00).
      expect(find.textContaining('O cliente vê 7,00 € em vez de 10,00 €'), findsOneWidget);
      await t.tap(find.byKey(const Key('promo_guardar')));
      await t.pumpAndSettle();
      expect(api.chamadas, ['definir p1 7.0 null null']);
    });

    testWidgets('preço promocional igual ou acima do normal: recusa sem ir ao servidor', (t) async {
      final api = ApiParceiroFalsa();
      await abrir(t, api, parceira: false, p: produto(balcao: null));
      await t.enterText(find.byKey(const Key('promo_preco')), '10,00');
      await t.tap(find.byKey(const Key('promo_guardar')));
      await t.pumpAndSettle();
      expect(api.chamadas, isEmpty);
      expect(find.byKey(const Key('promo_erro')), findsOneWidget);
    });

    testWidgets('promoção existente: mostra o estado e deixa terminar', (t) async {
      final api = ApiParceiroFalsa(
        atual: PromocaoDefinida(
          precoPromocional: 7,
          inicio: DateTime.now().subtract(const Duration(hours: 2)),
          fim: DateTime.now().add(const Duration(days: 2)),
        ),
      );
      await abrir(t, api, parceira: false, p: produto(balcao: null));
      expect(find.text('Promoção ativa agora.'), findsOneWidget);
      await t.tap(find.byKey(const Key('promo_terminar')));
      await t.pumpAndSettle();
      expect(api.chamadas, ['definir p1 null null null']);
      expect(find.byKey(const Key('promo_terminar')), findsNothing);
    });

    testWidgets('erro do servidor aparece em português', (t) async {
      final api = ApiParceiroFalsa(erro: StateError('promo_preco_invalido: x'));
      await abrir(t, api, parceira: false, p: produto(balcao: null));
      await t.enterText(find.byKey(const Key('promo_preco')), '5');
      await t.tap(find.byKey(const Key('promo_guardar')));
      await t.pumpAndSettle();
      expect(find.textContaining('maior que zero e menor que o preço normal'), findsOneWidget);
    });
  });

  group('AdminPromocoesScreen (painel PT-BR)', () {
    PromocaoAdmin promo(
      String id, {
      String nome = 'Produto',
      double preco = 10,
      double promo = 7,
      DateTime? inicio,
      DateTime? fim,
      bool ativada = true,
      bool parceira = true,
      String? por = 'maria@bora.test',
    }) =>
        PromocaoAdmin(
          productId: id,
          produto: nome,
          restaurantId: 'loja1',
          loja: 'Loja Um',
          lojaParceira: parceira,
          preco: preco,
          precoPromocional: promo,
          inicio: inicio,
          fim: fim,
          ativada: ativada,
          criadaPor: por,
          maisBaixo30d: 10,
        );

    ApiAdminFalsa api0({EstadoPromocoes? estado}) => ApiAdminFalsa(
          estado: estado ?? const EstadoPromocoes(ligado: false, servidorPronto: false),
          itens: [
            promo('ativa', nome: 'Pizza ativa', inicio: _agora.subtract(const Duration(days: 1)), fim: _agora.add(const Duration(days: 1))),
            promo('agendada', nome: 'Pizza agendada', inicio: _agora.add(const Duration(days: 1))),
            promo('expirada', nome: 'Pizza expirada', inicio: _agora.subtract(const Duration(days: 5)), fim: _agora.subtract(const Duration(days: 1))),
            promo('desligada', nome: 'Pizza desligada', inicio: _agora.subtract(const Duration(days: 1)), ativada: false),
            promo('antiga', nome: 'Pizza antiga', por: null),
          ],
          registos: [
            AuditoriaPromocao(
              quando: _agora,
              quem: 'danilo@bora.test',
              acao: 'promotion_disabled',
              produto: 'Pizza desligada',
            ),
          ],
        );

    Future<void> abrir(WidgetTester t, ApiAdminFalsa api) async {
      ecraAlto(t);
      await t.pumpWidget(MaterialApp(
        home: AdminPromocoesScreen(api: api, relogio: () => _agora),
      ));
      await t.pumpAndSettle();
    }

    testWidgets('mostra o interruptor desligado, o aviso do servidor e as 5 promoções com o estado certo',
        (t) async {
      final api = api0();
      await abrir(t, api);
      expect(t.widget<SwitchListTile>(find.byKey(const Key('promo_interruptor'))).value, isFalse);
      expect(find.text('O servidor ainda NÃO aplica o preço promocional.'), findsOneWidget);
      expect(find.text('Promoções (5)'), findsOneWidget);
      Text estado(String id) => t.widget<Text>(find.byKey(Key('promo_estado_$id')));
      expect(estado('ativa').data, 'Ativa');
      expect(estado('agendada').data, 'Agendada');
      expect(estado('expirada').data, 'Expirada');
      expect(estado('desligada').data, 'Desligada');
      expect(estado('antiga').data, 'Sem datas (não é aplicada)');
      expect(find.text('Criada por maria@bora.test'), findsWidgets);
    });

    testWidgets('filtros: contam e mostram só o estado escolhido', (t) async {
      await abrir(t, api0());
      expect(find.text('Todas (5)'), findsOneWidget);
      expect(find.text('Ativas (1)'), findsOneWidget);
      expect(find.text('Agendadas (1)'), findsOneWidget);
      expect(find.text('Expiradas (1)'), findsOneWidget);
      expect(find.text('Desligadas (1)'), findsOneWidget);
      expect(find.text('Sem datas (1)'), findsOneWidget);
      await t.tap(find.byKey(const Key('promo_filtro_ativas')));
      await t.pumpAndSettle();
      expect(find.byKey(const Key('promo_item_ativa')), findsOneWidget);
      expect(find.byKey(const Key('promo_item_agendada')), findsNothing);
      expect(find.byKey(const Key('promo_item_antiga')), findsNothing);
    });

    testWidgets('desligar uma promoção pede confirmação e chama o servidor', (t) async {
      final api = api0();
      await abrir(t, api);
      await t.tap(find.byKey(const Key('promo_switch_ativa')));
      await t.pumpAndSettle();
      expect(find.text('Desligar esta promoção?'), findsOneWidget);
      await t.tap(find.text('Desligar'));
      await t.pumpAndSettle();
      expect(api.chamadas, contains('ligarDesligar ativa false'));
    });

    testWidgets('ligar o interruptor geral avisa se o servidor ainda não aplica e só liga com confirmação',
        (t) async {
      final api = api0();
      await abrir(t, api);
      await t.tap(find.byKey(const Key('promo_interruptor')));
      await t.pumpAndSettle();
      expect(find.text('Ligar as promoções?'), findsOneWidget);
      expect(find.textContaining('o servidor ainda NÃO aplica'), findsOneWidget);
      // Cancelar não muda nada.
      await t.tap(find.text('Cancelar'));
      await t.pumpAndSettle();
      expect(api.chamadas.where((c) => c.startsWith('interruptor')), isEmpty);
      // Confirmar liga.
      await t.tap(find.byKey(const Key('promo_interruptor')));
      await t.pumpAndSettle();
      await t.tap(find.text('Ligar'));
      await t.pumpAndSettle();
      expect(api.chamadas, contains('interruptor true'));
    });

    testWidgets('servidor pronto: sem aviso de atenção', (t) async {
      await abrir(
          t,
          api0(
              estado: const EstadoPromocoes(ligado: true, servidorPronto: true)));
      expect(find.text('O servidor já aplica o preço promocional.'), findsOneWidget);
      expect(t.widget<SwitchListTile>(find.byKey(const Key('promo_interruptor'))).value, isTrue);
    });

    testWidgets('auditoria mostra quem fez o quê', (t) async {
      await abrir(t, api0());
      await t.tap(find.byKey(const Key('promo_auditoria')));
      await t.pumpAndSettle();
      expect(find.text('Desligou a promoção: Pizza desligada'), findsOneWidget);
      expect(find.textContaining('danilo@bora.test'), findsOneWidget);
    });

    testWidgets('nova promoção: procura o produto, escolhe e cria', (t) async {
      final api = api0();
      await abrir(t, api);
      await t.tap(find.byKey(const Key('promo_nova')));
      await t.pumpAndSettle();
      await t.enterText(find.byKey(const Key('nova_busca')), 'bitoque');
      await t.tap(find.byKey(const Key('nova_procurar')));
      await t.pumpAndSettle();
      expect(find.text('Bitoque'), findsOneWidget);
      // O produto ao peso aparece mas não se pode escolher.
      expect(find.textContaining('ao peso: não leva promoção'), findsOneWidget);
      await t.tap(find.byKey(const Key('nova_achado_b1')));
      await t.pumpAndSettle();
      // Preço igual ao normal: recusa.
      await t.enterText(find.byKey(const Key('nova_preco')), '9,00');
      await t.tap(find.byKey(const Key('nova_criar')));
      await t.pumpAndSettle();
      expect(find.byKey(const Key('nova_erro')), findsOneWidget);
      expect(api.chamadas.where((c) => c.startsWith('definir')), isEmpty);
      // Preço certo: cria.
      await t.enterText(find.byKey(const Key('nova_preco')), '7,5');
      await t.tap(find.byKey(const Key('nova_criar')));
      await t.pumpAndSettle();
      expect(api.chamadas, contains('definir b1 7.5'));
      expect(find.text('Promoção criada.'), findsOneWidget);
    });

    testWidgets('sem promoções: diz como começar', (t) async {
      await abrir(t, ApiAdminFalsa(estado: const EstadoPromocoes(ligado: false, servidorPronto: false)));
      expect(find.textContaining('Ainda não há nenhuma promoção'), findsOneWidget);
    });

    testWidgets('erro de leitura: mostra a mensagem e deixa tentar de novo', (t) async {
      await abrir(
          t,
          ApiAdminFalsa(
              estado: const EstadoPromocoes(ligado: false, servidorPronto: false),
              falha: StateError('boom')));
      expect(find.text('Tentar de novo'), findsOneWidget);
    });
  });
}

// ─── Portas de mentira ──────────────────────────────────────────────────────

class ApiParceiroFalsa extends Fake implements PromocoesApi {
  ApiParceiroFalsa({this.ligadoGeral = true, this.atual, this.erro});
  final bool ligadoGeral;
  PromocaoDefinida? atual;
  final Object? erro;
  final List<String> chamadas = [];

  @override
  Future<bool> ligado() async => ligadoGeral;

  @override
  Future<PromocaoDefinida?> doProduto(String productId) async => atual;

  @override
  Future<void> definir({
    required String productId,
    required double? precoPromocional,
    DateTime? inicio,
    DateTime? fim,
  }) async {
    if (erro != null) throw erro!;
    chamadas.add('definir $productId $precoPromocional '
        '${inicio == null ? null : 'ini'} ${fim == null ? null : 'fim'}');
    atual = precoPromocional == null
        ? null
        : PromocaoDefinida(precoPromocional: precoPromocional, inicio: inicio, fim: fim);
  }
}

class ApiAdminFalsa extends Fake implements PromocoesApi {
  ApiAdminFalsa({
    required this.estado,
    this.itens = const [],
    this.registos = const [],
    this.falha,
  });

  EstadoPromocoes estado;
  List<PromocaoAdmin> itens;
  final List<AuditoriaPromocao> registos;
  final Object? falha;
  final List<String> chamadas = [];

  @override
  Future<EstadoPromocoes> estadoGeral() async => estado;

  @override
  Future<List<PromocaoAdmin>> lista() async {
    if (falha != null) throw falha!;
    return itens;
  }

  @override
  Future<List<AuditoriaPromocao>> auditoria({int limite = 60}) async => registos;

  @override
  Future<void> definirInterruptor(bool ligado) async {
    chamadas.add('interruptor $ligado');
    estado = EstadoPromocoes(ligado: ligado, servidorPronto: estado.servidorPronto);
  }

  @override
  Future<void> ligarDesligar(String productId, bool ativada, {String? motivo}) async {
    chamadas.add('ligarDesligar $productId $ativada');
  }

  @override
  Future<List<ProdutoPesquisa>> procurarProdutos(String texto) async => const [
        ProdutoPesquisa(id: 'b1', nome: 'Bitoque', preco: 9, loja: 'Loja Um', lojaParceira: true),
        ProdutoPesquisa(id: 'b2', nome: 'Bitoque ao peso', preco: 5, loja: 'Loja Um', aoPeso: true),
      ];

  @override
  Future<void> definir({
    required String productId,
    required double? precoPromocional,
    DateTime? inicio,
    DateTime? fim,
  }) async {
    chamadas.add('definir $productId $precoPromocional');
  }
}
