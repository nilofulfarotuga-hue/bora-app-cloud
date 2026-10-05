// LOJA FECHADA: O TRAVÃO TEM DE SE VER (PADRAO_BORA §1.27).
//
// Achado a 05/10/2026 pelo autoteste do CI (corrida #495, 08:16 UTC). O
// emulador anda em UTC e a app decide "aberta/fechada" pelo relógio do
// aparelho, por isso via a Auchan (09h00–21h00) como fechada. Na ficha do
// produto o botão "Adicionar ao carrinho · €3.54" estava activo, dizia
// "adicionado ao carrinho" e fechava a ficha — sem ter adicionado nada, porque
// o `CartStore.addItem` recusa em silêncio quando a loja está fechada. O mesmo
// silêncio vivia no "+" e na linha das variantes (`store_products_screen`) e no
// "Pedir de novo", que reconfigurava o carrinho sem a marca de fechada e
// deixava enchê-lo fora de horas.
import 'dart:convert';
import 'dart:io';

import 'package:bora_app/models/cart_item.dart';
import 'package:bora_app/models/order_model.dart';
import 'package:bora_app/models/partner_product.dart';
import 'package:bora_app/models/product_option.dart';
import 'package:bora_app/models/restaurant_model.dart';
import 'package:bora_app/screens/product_detail_screen.dart';
import 'package:bora_app/services/reorder_service.dart';
import 'package:bora_app/stores/cart_store.dart';
import 'package:bora_app/stores/restaurant_store.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

const _avisoAuchan = 'Auchan está fechada agora. Abre às 09h00.';

// A uva da captura `05-loja-produto.png` da corrida que falhou.
const _uva = PartnerProduct(
  id: 'uva-branca-500g',
  restaurantId: 'auchan',
  name: 'Uva branca sem grainha',
  description: '',
  price: 3.08,
  photoUrl: '',
  isAvailable: true,
);

// Um produto com escolha obrigatória, para o caminho `_addWithOptions`.
const _queijo = PartnerProduct(
  id: 'queijo-ao-peso',
  restaurantId: 'auchan',
  name: 'Queijo da Serra',
  description: '',
  price: 2.00,
  photoUrl: '',
  isAvailable: true,
  hasRequiredOptions: true,
);

/// O que o servidor de brincar devolve a `product_option_groups`. Vazio por
/// omissão; o teste das opções enche-o.
List<Map<String, dynamic>> _gruposDoServidor = const [];

final _grupoDoQueijo = [
  {
    'id': 'queijo-ao-peso-gq',
    'product_id': 'queijo-ao-peso',
    'name': 'Escolhe a quantidade',
    'description': '',
    'is_required': true,
    'min_choices': 1,
    'max_choices': 1,
    'sort_order': 0,
    'product_option_items': [
      {'id': 'q-200', 'name': '200 g', 'price_add': 0, 'is_available': true, 'sort_order': 0},
      {'id': 'q-400', 'name': '400 g', 'price_add': 2, 'is_available': true, 'sort_order': 1},
    ],
  }
];

/// Horário que garante loja FECHADA à hora a que o teste corre: uma janela de
/// uma hora que começa daqui a três.
BusinessHours _fechadaAgora() {
  final abre = (DateTime.now().hour + 3) % 24;
  final fecha = (abre + 1) % 24;
  return _todosOsDias(abre, fecha);
}

/// Horário que garante loja ABERTA agora, a qualquer hora do dia: abriu há uma
/// hora e fecha daqui a duas (a janela pode atravessar a meia-noite — um
/// "00:00–23:59" falhava no último minuto do dia).
BusinessHours _abertaAgora() {
  final agora = DateTime.now().hour;
  return _todosOsDias((agora + 23) % 24, (agora + 2) % 24);
}

BusinessHours _todosOsDias(int abre, int fecha) {
  final d = DayHours(
    open: '${abre.toString().padLeft(2, '0')}:00',
    close: '${fecha.toString().padLeft(2, '0')}:00',
  );
  return BusinessHours(mon: d, tue: d, wed: d, thu: d, fri: d, sat: d, sun: d);
}

RestaurantModel _loja({
  required BusinessHours horario,
  String nome = 'Auchan',
  bool parceira = false,
  BusinessCategory categoria = BusinessCategory.supermarket,
  DateTime? pausaAte,
}) =>
    RestaurantModel(
      id: 'x-$nome',
      name: nome,
      phone: '',
      address: '',
      email: '',
      photoUrl: '',
      cuisineType: '',
      isPartner: parceira,
      category: categoria,
      businessHours: horario,
      pausaAte: pausaAte,
    );

CartStore _carrinho({required bool fechada}) => CartStore()
  ..configureSession(
    serviceType: OrderServiceType.storeShopping,
    vendorName: 'Auchan',
    vendorFechada: fechada,
    vendorAvisoFechada: fechada ? _avisoAuchan : '',
  );

/// Abre a ficha de [produto] POR CIMA de um ecrã de casa, como na app: assim
/// vê-se se a ficha fecha (adicionou) ou fica aberta (loja fechada).
Future<void> _abrirFicha(
  WidgetTester tester,
  CartStore cart, {
  PartnerProduct produto = _uva,
  String esperarPor = 'Adicionar ao carrinho',
}) async {
  tester.view.physicalSize = const Size(1080, 2400);
  tester.view.devicePixelRatio = 2.6;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  final navegador = GlobalKey<NavigatorState>();
  await tester.pumpWidget(MultiProvider(
    providers: [
      ChangeNotifierProvider<CartStore>.value(value: cart),
      ChangeNotifierProvider<RestaurantStore>(create: (_) => RestaurantStore()),
    ],
    child: MaterialApp(
      navigatorKey: navegador,
      home: const Scaffold(body: Text('casa')),
    ),
  ));
  navegador.currentState!.push(MaterialPageRoute<void>(
    builder: (_) => ProductDetailScreen(product: produto, isPartnerStore: false),
  ));
  // A ficha pergunta ao servidor pelas opções do produto (cliente HTTP de
  // brincar): o pedido corre em tempo real, fora do relógio do teste.
  final alvo = find.textContaining(esperarPor);
  for (var i = 0; i < 30 && alvo.evaluate().isEmpty; i++) {
    await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 100)));
    await tester.pump();
  }
  // Deixa a transição da rota acabar, para o toque acertar no botão.
  await tester.pump(const Duration(milliseconds: 500));
  expect(alvo, findsWidgets);
}

/// Desmonta e deixa correr o que ficou agendado (avisos, lojas em tempo real),
/// como faz o teste do jiló: sem isto o arnês acusa temporizadores pendurados.
/// Só engole o ruído da desmontagem — o que interessa já foi verificado antes.
Future<void> _arrumar(WidgetTester tester) async {
  await tester.pump(const Duration(seconds: 10));
  await tester.pump(const Duration(seconds: 1));
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pump(const Duration(minutes: 5));
  tester.takeException();
}

String _ler(String caminho) => File(caminho).readAsStringSync();

/// O troço de [fonte] que vai de [inicio] até ao próximo [fim].
String _troco(String fonte, String inicio, String fim) {
  final a = fonte.indexOf(inicio);
  expect(a, isNonNegative, reason: 'não encontrei "$inicio"');
  final b = fonte.indexOf(fim, a + inicio.length);
  expect(b, isNonNegative, reason: 'não encontrei "$fim" depois de "$inicio"');
  return fonte.substring(a, b);
}

void main() {
  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await Supabase.initialize(
      url: 'http://127.0.0.1:1',
      anonKey: 'teste',
      debug: false,
      httpClient: MockClient((req) async {
        final corpo = req.url.path.endsWith('/product_option_groups')
            ? jsonEncode(_gruposDoServidor)
            : '[]';
        return http.Response(corpo, 200,
            request: req,
            headers: {'content-type': 'application/json; charset=utf-8'});
      }),
    );
  });

  // O carrinho grava-se nas preferências: cada teste começa de vazio, para um
  // artigo adicionado num teste não aparecer no carrinho do seguinte.
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    _gruposDoServidor = const [];
  });

  group('ficha do produto', () {
    testWidgets(
        'loja FECHADA: diz que está fechada, não diz "adicionado" e fica '
        'aberta', (tester) async {
      final cart = _carrinho(fechada: true);
      await _abrirFicha(tester, cart);

      await tester.tap(find.textContaining('Adicionar ao carrinho'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 600));

      // É por esta frase que o autoteste do CI reconhece a loja fechada.
      expect(find.textContaining('está fechada'), findsOneWidget);
      expect(find.text(_avisoAuchan), findsOneWidget);
      expect(find.textContaining('adicionado ao carrinho'), findsNothing);
      expect(cart.items, isEmpty);
      expect(find.byType(ProductDetailScreen), findsOneWidget,
          reason: 'a ficha fechou-se como se tivesse adicionado');
      expect(tester.takeException(), isNull);
      await _arrumar(tester);
    });

    testWidgets('loja ABERTA: adiciona, diz "adicionado" e fecha a ficha',
        (tester) async {
      final cart = _carrinho(fechada: false);
      await _abrirFicha(tester, cart);

      await tester.tap(find.textContaining('Adicionar ao carrinho'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 600));

      expect(cart.items, hasLength(1));
      expect(cart.items.single.productId, _uva.id);
      expect(find.textContaining('adicionado ao carrinho'), findsOneWidget);
      expect(find.textContaining('está fechada'), findsNothing);
      expect(find.byType(ProductDetailScreen), findsNothing);
      expect(tester.takeException(), isNull);
      await _arrumar(tester);
    });

    testWidgets(
        'loja FECHADA, produto com escolha obrigatória: o mesmo aviso e '
        'carrinho vazio', (tester) async {
      _gruposDoServidor = _grupoDoQueijo;
      final cart = _carrinho(fechada: true);
      await _abrirFicha(tester, cart,
          produto: _queijo, esperarPor: 'Escolhe a quantidade');

      await tester.ensureVisible(find.text('400 g'));
      await tester.tap(find.text('400 g'));
      await tester.pump();
      final botao = find.textContaining('Adicionar ao carrinho · €');
      expect(botao, findsOneWidget);
      await tester.ensureVisible(botao);
      await tester.tap(botao);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 600));

      expect(find.text(_avisoAuchan), findsOneWidget);
      expect(find.textContaining('adicionado ao carrinho'), findsNothing);
      expect(cart.items, isEmpty);
      expect(find.byType(ProductDetailScreen), findsOneWidget);
      expect(tester.takeException(), isNull);
      await _arrumar(tester);
    });

    test('os três caminhos de adicionar passam pelo aviso de loja fechada', () {
      // O caminho das variantes não tem dados para um teste de ecrã (a tabela
      // de variantes está vazia): fica guardado pela fonte.
      final fonte = _ler('lib/screens/product_detail_screen.dart');
      expect('.addItem('.allMatches(fonte), hasLength(3));
      for (final cabecalho in [
        'void _addToCart(BuildContext context, ProductVariant v) {',
        'void _addNoVariantToCart(BuildContext context) {',
        'void _addWithOptions(BuildContext context) {',
      ]) {
        final corpo = _troco(fonte, cabecalho, '.addItem(');
        expect(corpo, contains('if (_lojaFechadaAvisa()) return;'),
            reason: '$cabecalho mete no carrinho sem ver se a loja está fechada');
      }
    });
  });

  group('lojas com variantes (store_products_screen)', () {
    final fonte = _ler('lib/screens/store_products_screen.dart');

    test('o "+" fica cinzento e mostra o aviso da loja', () {
      final botao = _troco(fonte, 'class _QtyButton extends StatelessWidget',
          'class _CartBadge extends StatelessWidget');
      // Só o "+" trava: o "-" tem de continuar a tirar do carrinho.
      expect(botao,
          contains('icon == Icons.add && context.watch<CartStore>().lojaFechada'));
      expect(botao, contains('showLojaFechadaSnackBar(context, avisoFechada)'));
    });

    test('tocar na linha da variante também avisa antes de adicionar', () {
      // A linha inteira é um InkWell que chama `_addToCart`: o travão do "+"
      // não chegava.
      final adicionar = _troco(
          fonte,
          'class _VariantMiniCard extends StatelessWidget',
          'Widget build(BuildContext context)');
      final guarda = adicionar.indexOf('if (cartStore.lojaFechada) {');
      final mete = adicionar.indexOf('.addItem(');
      expect(guarda, isNonNegative,
          reason: 'a linha da variante mete no carrinho com a loja fechada');
      expect(mete, greaterThan(guarda));
      final travao = adicionar.substring(guarda, mete);
      expect(travao,
          contains('showLojaFechadaSnackBar(context, cartStore.avisoLojaFechada);'));
      expect(travao, contains('return;'));
    });
  });

  group('"Pedir de novo" obedece ao mesmo travão', () {
    test('supermercado NÃO parceiro e fechado: encontra a loja e trava', () {
      // 22 das 27 lojas não são parceiras (todos os mercados incluídos): a
      // procura só-parceiros (`restaurantByName`) deixava-as passar.
      final lojas = [
        _loja(nome: 'Goola Açaí', parceira: true, horario: _abertaAgora()),
        _loja(nome: 'Auchan', horario: _fechadaAgora()),
      ];
      final loja = ReorderService.lojaDoPedido('Auchan', lojas);
      expect(loja, isNotNull);
      expect(loja!.isPartner, isFalse);
      expect(ReorderService.lojaFechada(loja), isTrue);
      expect(loja.avisoLojaFechada, contains('Auchan está fechada agora'));
    });

    test('a loja do pedido encontra-se sem olhar a maiúsculas', () {
      final lojas = [_loja(nome: 'Pingo Doce', horario: _abertaAgora())];
      expect(ReorderService.lojaDoPedido('pingo doce', lojas), isNotNull);
      expect(ReorderService.lojaDoPedido('PINGO DOCE', lojas), isNotNull);
    });

    test('loja que já não existe, ou pedido sem loja: não inventa', () {
      final lojas = [_loja(nome: 'Auchan', horario: _fechadaAgora())];
      expect(ReorderService.lojaDoPedido('Loja Antiga', lojas), isNull);
      expect(ReorderService.lojaDoPedido(null, lojas), isNull);
      expect(ReorderService.lojaFechada(null), isFalse);
    });

    test('loja aberta → segue', () {
      expect(ReorderService.lojaFechada(_loja(horario: _abertaAgora())), isFalse);
    });

    test('loja em pausa → fechada, mesmo dentro do horário', () {
      final loja = _loja(
        horario: _abertaAgora(),
        pausaAte: DateTime.now().add(const Duration(minutes: 30)),
      );
      expect(ReorderService.lojaFechada(loja), isTrue);
    });

    test('casa de festas fora de horas → segue (vende por encomenda)', () {
      final festas = _loja(
        horario: _fechadaAgora(),
        categoria: BusinessCategory.festas,
      );
      expect(ReorderService.lojaFechada(festas), isFalse);
    });

    test('casa de festas em pausa → fechada', () {
      final festas = _loja(
        horario: _abertaAgora(),
        categoria: BusinessCategory.festas,
        pausaAte: DateTime.now().add(const Duration(minutes: 30)),
      );
      expect(ReorderService.lojaFechada(festas), isTrue);
    });

    test('as escolhas do cliente voltam com a linha (menu com bebida)', () {
      // Abrir o "Pedir de novo" às não-parceiras abre-o aos menus do Burger
      // King, do McDonald's e do KFC: sem as escolhas o pedido repetia-se sem
      // bebida nem acompanhamento.
      final cart = CartStore();
      final pedido = OrderModel(
        total: 18.38,
        serviceType: OrderServiceType.restaurant,
        vendorName: 'Burger King',
        items: [
          CartItem(
            productId: 'menu-whopper',
            name: 'Menu Whopper',
            price: 9.19,
            basePrice: 7.99,
            quantity: 2,
            selectedOptions: const [
              SelectedOption(group: 'Bebidas', items: ['Coca-Cola Zero']),
              SelectedOption(group: 'Acompanhamentos', items: ['Batatas']),
            ],
          ),
        ],
      );

      final mudaram = ReorderService.applyTo(cart: cart, order: pedido);

      expect(mudaram, isEmpty);
      final linha = cart.items.single;
      expect(linha.productId, 'menu-whopper');
      expect(linha.quantity, 2);
      expect(linha.price, 9.19);
      expect(linha.basePrice, 7.99);
      expect(
          linha.selectedOptions
              .map((o) => '${o.group}=${o.items.join(",")}')
              .toList(),
          ['Bebidas=Coca-Cola Zero', 'Acompanhamentos=Batatas']);
    });

    test('linha com escolhas não se compara com o preço de menu', () {
      // O preço guardado inclui os extras e o do menu é só a base: comparar
      // os dois dava um falso "preço atualizado" e deitava os extras fora.
      // (O ramo dos parceiros precisa das lojas carregadas; guarda de fonte.)
      final ciclo = _troco(_ler('lib/services/reorder_service.dart'),
          'for (final it in order.items) {', 'cart.addItem(CartItem(');
      expect(ciclo,
          contains('if (liveProducts != null && it.selectedOptions.isEmpty) {'));
    });

    test('os dois ecrãs perguntam ANTES de mexer no carrinho, e saem', () {
      // Os ecrãs não se montam num teste (precisam da lista de pedidos e da
      // conta): a ligação fica guardada pela fonte, a regra pelos testes acima.
      for (final (caminho, cabecalho) in [
        ('lib/screens/orders_screen.dart', 'Future<void> _pedirDeNovo(OrderModel order) async {'),
        ('lib/widgets/market/market_reorder_tab.dart', 'void _reorder(BuildContext context, OrderModel order) {'),
      ]) {
        final antes = _troco(_ler(caminho), cabecalho, 'ReorderService.applyTo(');
        expect(antes, contains('ReorderService.lojaDoPedido('),
            reason: '$caminho procura a loja só entre as parceiras');
        expect(antes, isNot(contains('restaurantByName(')),
            reason: '$caminho procura a loja só entre as parceiras');
        final guarda = antes.indexOf('ReorderService.lojaFechada(loja)');
        expect(guarda, isNonNegative,
            reason: '$caminho enche o carrinho sem ver se a loja está fechada');
        final travao = antes.substring(guarda);
        expect(travao,
            contains('showLojaFechadaSnackBar(context, loja.avisoLojaFechada);'),
            reason: '$caminho trava mas não diz porquê');
        expect(travao, contains('return;'),
            reason: '$caminho avisa mas enche o carrinho na mesma');
      }
    });
  });
}
