// ADENDO 4 + PARIDADE PEQUENA (29/10/2026) — P1 a P5.
//
//   P1 sem talheres por defeito   P2 troco ("com que nota?")
//   P3 andar/porta/código na morada   P4 filtros rápidos na lista de
//   restaurantes   P5 "Juntar mais" no carrinho.
//
// Nada aqui toca em preço, taxa ou token: as linhas automáticas só entram na
// nota do pedido e o "Juntar mais" só escolhe produtos que o carrinho depois
// junta pelo método de sempre.
import 'package:bora_app/l10n/bora_lang.dart';
import 'package:bora_app/models/client_address.dart';
import 'package:bora_app/models/order_service_type.dart';
import 'package:bora_app/models/partner_product.dart';
import 'package:bora_app/models/restaurant_model.dart';
import 'package:bora_app/services/complemento_morada.dart';
import 'package:bora_app/services/interruptores_app.dart';
import 'package:bora_app/utils/nota_do_pedido.dart';
import 'package:bora_app/widgets/filtros_rapidos_lojas.dart';
import 'package:bora_app/widgets/juntar_mais_tira.dart';
import 'package:bora_app/widgets/talheres_troco_cards.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

ClientAddress _morada(String texto, {String? details, String? cidade}) =>
    ClientAddress.fromJson({
      'id': 'a1',
      'user_id': 'u1',
      'label': 'Casa',
      'address': texto,
      'city': cidade,
      'details': details,
      'is_default': true,
      'created_at': '2026-10-29T10:00:00Z',
      'updated_at': '2026-10-29T10:00:00Z',
    });

const _d = DayHours(open: '11:00', close: '23:00');
const _horarioCompleto =
    BusinessHours(mon: _d, tue: _d, wed: _d, thu: _d, fri: _d, sat: _d, sun: _d);

RestaurantModel _loja(String id,
        {bool takeaway = false, bool online = true}) =>
    RestaurantModel(
      id: id,
      name: 'Loja $id',
      phone: '',
      address: '',
      email: '',
      photoUrl: '',
      cuisineType: '',
      isPartner: true,
      category: BusinessCategory.restaurant,
      businessHours: _horarioCompleto,
      takeawayEnabled: takeaway,
      isOnline: online,
    );

PartnerProduct _prod(String id, double preco,
        {bool disponivel = true, String nome = ''}) =>
    PartnerProduct(
      id: id,
      restaurantId: 'r1',
      name: nome.isEmpty ? 'Produto $id' : nome,
      description: '',
      price: preco,
      photoUrl: '',
      isAvailable: disponivel,
    );

Widget _app(Widget filho) => MaterialApp(home: Scaffold(body: filho));

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    BoraLang.notifier.value = AppLang.pt;
    InterruptoresApp.instance.definirParaTeste({
      InterruptoresApp.talheres: true,
      InterruptoresApp.troco: true,
      InterruptoresApp.detalhesMorada: true,
      InterruptoresApp.juntarMais: true,
    });
  });

  group('P1 — talheres: linha automática na nota', () {
    test('desligado (por defeito) escreve SEM TALHERES à cabeça', () {
      expect(
        NotaDoPedido.compor(precisaTalheres: false, textoDoCliente: 'sem cebola'),
        'SEM TALHERES\nsem cebola',
      );
    });

    test('ligado escreve COM TALHERES', () {
      expect(NotaDoPedido.compor(precisaTalheres: true), 'COM TALHERES');
    });

    test('pergunta não feita (null): nenhuma linha', () {
      expect(NotaDoPedido.compor(precisaTalheres: null, textoDoCliente: 'x'),
          'x');
      expect(NotaDoPedido.compor(), isNull);
    });

    test('só restaurante e "ir buscar" perguntam por talheres', () {
      expect(NotaDoPedido.perguntaTalheres(OrderServiceType.restaurant), isTrue);
      expect(NotaDoPedido.perguntaTalheres(OrderServiceType.takeaway), isTrue);
      for (final t in [
        OrderServiceType.storeShopping,
        OrderServiceType.errand,
        OrderServiceType.sendPackage,
        OrderServiceType.carryGroceries,
      ]) {
        expect(NotaDoPedido.perguntaTalheres(t), isFalse, reason: '$t');
      }
    });

    test('a linha dos talheres reconhece-se para pôr a negrito no parceiro', () {
      expect(NotaDoPedido.temLinhaDeTalheres('SEM TALHERES\nx'), isTrue);
      expect(NotaDoPedido.temLinhaDeTalheres('COM TALHERES'), isTrue);
      expect(NotaDoPedido.temLinhaDeTalheres('sem cebola'), isFalse);
      expect(NotaDoPedido.temLinhaDeTalheres(null), isFalse);
    });

    testWidgets('cartão nasce desligado e avisa quando se liga', (t) async {
      bool? ultimo;
      await t.pumpWidget(_app(StatefulBuilder(
        builder: (_, setState) => TalheresCard(
          precisa: ultimo ?? false,
          onChanged: (v) => setState(() => ultimo = v),
        ),
      )));
      final sw = find.byKey(const Key('interruptor_talheres'));
      expect(sw, findsOneWidget);
      expect(t.widget<SwitchListTile>(sw).value, isFalse);
      expect(find.text('Talheres e guardanapos'), findsOneWidget);
      expect(
          find.text(
              'Se não precisares, poupas plástico e ajudas a loja. Só enviamos se pedires.'),
          findsOneWidget);
      await t.tap(sw);
      await t.pump();
      expect(ultimo, isTrue);
    });
  });

  group('P2 — troco', () {
    test('só aparecem as notas MAIORES que o total', () {
      expect(NotaDoPedido.notasParaTroco(8.5), [10, 20, 50]);
      expect(NotaDoPedido.notasParaTroco(10), [20, 50]);
      expect(NotaDoPedido.notasParaTroco(19.99), [20, 50]);
      expect(NotaDoPedido.notasParaTroco(35), [50]);
      expect(NotaDoPedido.notasParaTroco(50), isEmpty);
    });

    test('linha: TROCO PARA 20 €, depois a morada, depois o texto', () {
      expect(
        NotaDoPedido.compor(
          precisaTalheres: false,
          trocoPara: 20,
          detalhesMorada: '2.º Dto · código 1234',
          textoDoCliente: 'tocar duas vezes',
        ),
        'SEM TALHERES\nTROCO PARA 20 €\nMORADA: 2.º Dto · código 1234\ntocar duas vezes',
      );
    });

    test('a marca das Festas fica à frente do texto do cliente', () {
      expect(
        NotaDoPedido.compor(
            marcaFestas: 'Encomenda para 31/10 às 18:00', textoDoCliente: 'x'),
        'Encomenda para 31/10 às 18:00 · x',
      );
    });

    testWidgets('chips: "Valor certo" por defeito e só as notas oferecidas',
        (t) async {
      int? escolhida;
      var vezes = 0;
      await t.pumpWidget(_app(StatefulBuilder(
        builder: (_, setState) => TrocoCard(
          notas: NotaDoPedido.notasParaTroco(12.5),
          escolhida: escolhida,
          onChanged: (n) => setState(() {
            escolhida = n;
            vezes++;
          }),
        ),
      )));
      expect(find.byKey(const Key('chip_troco_certo')), findsOneWidget);
      expect(find.byKey(const Key('chip_troco_10')), findsNothing,
          reason: '10 € não chega para 12,50 €');
      expect(find.byKey(const Key('chip_troco_20')), findsOneWidget);
      expect(find.byKey(const Key('chip_troco_50')), findsOneWidget);
      expect(find.text('Com que nota vais pagar?'), findsOneWidget);

      await t.tap(find.byKey(const Key('chip_troco_20')));
      await t.pump();
      expect(escolhida, 20);
      await t.tap(find.byKey(const Key('chip_troco_certo')));
      await t.pump();
      expect(escolhida, isNull);
      expect(vezes, 2);
    });

    testWidgets('sem nenhuma nota maior, a pergunta não aparece', (t) async {
      await t.pumpWidget(_app(TrocoCard(
          notas: NotaDoPedido.notasParaTroco(60),
          escolhida: null,
          onChanged: (_) {})));
      expect(find.byKey(const Key('cartao_troco')), findsNothing);
    });
  });

  group('P3 — andar, porta ou código', () {
    test('ClientAddress lê e escreve o complemento', () {
      final a = _morada('Rua do Comércio 12', details: '2.º Dto · porta azul');
      expect(a.details, '2.º Dto · porta azul');
      expect(a.toInsertJson()['details'], '2.º Dto · porta azul');
      expect(_morada('Rua X').toInsertJson().containsKey('details'), isFalse,
          reason: 'sem complemento não se manda coluna nenhuma');
      expect(a.copyWith(isDefault: false).details, '2.º Dto · porta azul');
    });

    test('encontra o complemento da morada que está no carrinho', () {
      final guardadas = [
        _morada('Rua A 1', details: 'código 1111'),
        _morada('Rua do Comércio 12', details: '2.º Dto · código 1234', cidade: 'Guarda'),
      ];
      expect(ComplementoMorada.encontrar(guardadas, 'Rua do Comércio 12'),
          '2.º Dto · código 1234');
      expect(ComplementoMorada.encontrar(guardadas, '  rua   do comércio 12 '),
          '2.º Dto · código 1234',
          reason: 'maiúsculas e espaços a mais não contam');
      expect(ComplementoMorada.encontrar(guardadas, 'Rua do Comércio 12, Guarda'),
          '2.º Dto · código 1234');
      expect(ComplementoMorada.encontrar(guardadas, 'Outra rua 9'), isNull);
      expect(ComplementoMorada.encontrar(guardadas, ''), isNull);
    });

    test('moradas sem complemento não dão linha', () {
      expect(ComplementoMorada.encontrar([_morada('Rua Z 3')], 'Rua Z 3'), isNull);
      expect(NotaDoPedido.linhaMorada('   '), isNull);
    });

    test('normaliza: espaços, vazio e máximo de 80 caracteres', () {
      expect(ComplementoMorada.normalizar('  2.º   Dto  '), '2.º Dto');
      expect(ComplementoMorada.normalizar('   '), isNull);
      expect(ComplementoMorada.normalizar(null), isNull);
      expect(ComplementoMorada.normalizar('x' * 120)!.length, 80);
    });
  });

  group('P4 — filtros rápidos da lista de restaurantes', () {
    final lojas = [
      _loja('a', takeaway: true),
      _loja('b'),
      _loja('c', takeaway: true, online: false),
    ];
    // Segunda-feira 13:00 em Lisboa (UTC no inverno): aberto.
    final agora = DateTime.utc(2026, 11, 2, 13);

    test('a configuração lê as três chaves do JSON do painel', () {
      final c = ConfigFiltrosLojas.fromJson({
        'open_now_enabled': true,
        'takeaway_enabled': true,
        'free_delivery_enabled': false,
      });
      expect(c.abertoAgora, isTrue);
      expect(c.irBuscar, isTrue);
      expect(c.entregaGratis, isFalse);
      expect(c.algumLigado, isTrue);
      expect(ConfigFiltrosLojas.fromJson(null).algumLigado, isFalse);
      expect(ConfigFiltrosLojas.fromJson({'dietary_enabled': true}).algumLigado,
          isFalse,
          reason: 'os filtros dietéticos continuam desligados');
    });

    test('"Aberto agora" tira as lojas fechadas ou offline', () {
      final r = aplicarFiltrosRapidos(lojas,
          ativos: const FiltrosAtivos(abertoAgora: true),
          config: const ConfigFiltrosLojas(abertoAgora: true),
          agora: agora);
      expect(r.map((l) => l.id), ['a', 'b']);
    });

    test('"Ir buscar" só deixa quem tem takeaway', () {
      final r = aplicarFiltrosRapidos(lojas,
          ativos: const FiltrosAtivos(irBuscar: true),
          config: const ConfigFiltrosLojas(irBuscar: true),
          agora: agora);
      expect(r.map((l) => l.id), ['a', 'c']);
    });

    test('"Entrega grátis" usa os ids que têm entrega grátis', () {
      final r = aplicarFiltrosRapidos(lojas,
          ativos: const FiltrosAtivos(entregaGratis: true),
          config: const ConfigFiltrosLojas(entregaGratis: true),
          comEntregaGratis: {'b'},
          agora: agora);
      expect(r.map((l) => l.id), ['b']);
    });

    test('filtros combinam-se (e)', () {
      final r = aplicarFiltrosRapidos(lojas,
          ativos: const FiltrosAtivos(abertoAgora: true, irBuscar: true),
          config: const ConfigFiltrosLojas(abertoAgora: true, irBuscar: true),
          agora: agora);
      expect(r.map((l) => l.id), ['a']);
    });

    test('chip ativo cujo interruptor o admin desligou não filtra nada', () {
      final r = aplicarFiltrosRapidos(lojas,
          ativos: const FiltrosAtivos(irBuscar: true),
          config: ConfigFiltrosLojas.desligada,
          agora: agora);
      expect(r.length, 3);
    });

    testWidgets('só aparecem os chips cujo interruptor está ligado', (t) async {
      var ativos = const FiltrosAtivos();
      await t.pumpWidget(_app(StatefulBuilder(
        builder: (_, setState) => FiltrosRapidosLojas(
          config: const ConfigFiltrosLojas(abertoAgora: true, entregaGratis: true),
          ativos: ativos,
          onChanged: (f) => setState(() => ativos = f),
        ),
      )));
      expect(find.byKey(const Key('filtro_aberto_agora')), findsOneWidget);
      expect(find.byKey(const Key('filtro_ir_buscar')), findsNothing);
      expect(find.byKey(const Key('filtro_entrega_gratis')), findsOneWidget);
      await t.tap(find.byKey(const Key('filtro_entrega_gratis')));
      await t.pump();
      expect(ativos.entregaGratis, isTrue);
      await t.tap(find.byKey(const Key('filtro_entrega_gratis')));
      await t.pump();
      expect(ativos.entregaGratis, isFalse);
      // O chip tem pelo menos 44 px de altura (zona do polegar).
      expect(t.getSize(find.byKey(const Key('filtro_aberto_agora'))).height,
          greaterThanOrEqualTo(44));
    });

    testWidgets('sem nenhum interruptor ligado a fila não existe', (t) async {
      await t.pumpWidget(_app(FiltrosRapidosLojas(
          config: ConfigFiltrosLojas.desligada,
          ativos: const FiltrosAtivos(),
          onChanged: (_) {})));
      expect(find.byKey(const Key('filtros_rapidos_lojas')), findsNothing);
    });
  });

  group('P5 — "Juntar mais"', () {
    test('até 3 produtos, do mais barato para o mais caro, sem esgotados', () {
      final r = produtosParaJuntarMais([
        _prod('a', 4.5),
        _prod('b', 1.2),
        _prod('c', 0.8, disponivel: false),
        _prod('d', 2.0),
        _prod('e', 9.9),
        _prod('f', 3.0),
      ]);
      expect(r.map((p) => p.id), ['b', 'd', 'f']);
    });

    test('ignora preço zero e o prémio do check-in', () {
      final r = produtosParaJuntarMais([
        _prod('zero', 0),
        _prod('premio-checkin-1', 0.5),
        _prod('ok', 2),
      ]);
      expect(r.map((p) => p.id), ['ok']);
    });

    test('o subtítulo diz o que falta, e para quê', () {
      expect(
          subtituloJuntarMais(faltaEntregaGratis: 4.5, faltaMinimo: 2),
          'Faltam 4,50 € para a entrega grátis');
      expect(subtituloJuntarMais(faltaEntregaGratis: 0, faltaMinimo: 1.3),
          'Faltam 1,30 € para evitar a taxa de pedido pequeno');
      expect(subtituloJuntarMais(faltaEntregaGratis: 0, faltaMinimo: 0), isNull);
    });
  });

  test('interruptores: todas as chaves de P1 a P5 existem no código', () {
    expect(InterruptoresApp.talheres, 'ask_cutlery');
    expect(InterruptoresApp.troco, 'ask_cash_change');
    expect(InterruptoresApp.detalhesMorada, 'ask_address_details');
    expect(InterruptoresApp.juntarMais, 'cart_add_more_strip');
  });
}
