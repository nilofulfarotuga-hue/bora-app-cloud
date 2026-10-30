// Agendar também nos MERCADOS e lojas NÃO parceiras (ordem do Danilo, 30/10/2026).
//
// O que se prova, com o servidor trocado por portas de mentira:
//  1. a hora marcada vai para o servidor (`client_preparar_agendamento`) ANTES
//     de o pedido ser criado — dinheiro/MB Way (`finishOrder`) e cartão
//     (`startCardPaymentDraft`); com "Entregar agora" vai `null`; recusada,
//     o pedido não nasce; depois de criado, só se chama a reserva
//     `client_set_order_schedule` se o pedido não ficou com a hora;
//  2. a chamada verdadeira (SDK do Supabase) leva o nome e os parâmetros certos;
//  3. o seletor "Entregar agora / Agendar" aparece num mercado não parceiro
//     (decide o servidor pelas janelas, não o isPartner);
//  4. loja fechada com janelas: "Loja fechada: agenda para quando abrir", só
//     "Agendar", 1.ª janela já escolhida; sem janelas fica como dantes;
//  5. seguimento do cliente: "Agendado para …" em destaque e nunca "À procura
//     de estafeta" antes da hora.
import 'dart:convert';

import 'package:bora_app/models/cart_item.dart';
import 'package:bora_app/models/order_model.dart';
import 'package:bora_app/models/restaurant_model.dart';
import 'package:bora_app/services/agendar_pedido.dart';
import 'package:bora_app/services/agendar_pedido_service.dart';
import 'package:bora_app/stores/cart_store.dart';
import 'package:bora_app/stores/order_store.dart';
import 'package:bora_app/stores/restaurant_store.dart';
import 'package:bora_app/utils/hora_lisboa.dart';
import 'package:bora_app/widgets/agendar_pedido_seletor.dart';
import 'package:bora_app/widgets/barra_pedido_ativo.dart';
import 'package:bora_app/widgets/bora/loja_fechada.dart';
import 'package:bora_app/widgets/pedido_agendado_aviso.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:latlong2/latlong.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

// ── Portas de mentira ───────────────────────────────────────────────────────

/// Faz de servidor das janelas: com o interruptor ligado, duas janelas
/// (10:00–10:30 e 10:30–11:00) em qualquer dia pedido.
class ServidorFalso implements AgendarPedidoApi {
  ServidorFalso({this.ligado = true, this.semJanelas = false});
  final bool ligado;
  final bool semJanelas;
  final List<(String, DateTime)> pedidosDeJanelas = [];

  /// Os dias pedidos para UMA loja (os carrinhos de outros testes continuam
  /// vivos e também perguntam pelas deles).
  List<DateTime> diasPedidos(String loja) =>
      [for (final (l, d) in pedidosDeJanelas) if (l == loja) d];
  final List<(String, DateTime)> gravados = [];

  @override
  Future<ConfigAgendar> config() async => ConfigAgendar(ligado: ligado);

  @override
  Future<List<JanelaAgendada>> janelas(String restaurantId, DateTime dia) async {
    pedidosDeJanelas.add((restaurantId, dia));
    if (!ligado || semJanelas) return const [];
    JanelaAgendada j(int h, int m) {
      final ini = DateTime.utc(dia.year, dia.month, dia.day, h, m);
      return JanelaAgendada(inicio: ini, fim: ini.add(const Duration(minutes: 30)));
    }

    return [j(10, 0), j(10, 30)];
  }

  @override
  Future<void> gravar(String orderId, DateTime instante) async {
    gravados.add((orderId, instante));
  }

  @override
  Future<List<PedidoAgendado>> pedidosDoParceiro(String restaurantId) async => const [];
}

/// `client_preparar_agendamento` e a leitura do `scheduled_for`, de mentira.
/// Escreve no mesmo [log] que o OrderStore falso, para provar a ORDEM.
class MarcacaoFalsa implements AgendarMarcacaoApi {
  MarcacaoFalsa(this.log, {this.erro, this.falhasDeRede = 0, this.horaGravada});
  final List<String> log;

  /// Código que o servidor devolve ao marcar (ex.: schedule_window_invalid).
  final String? erro;
  int falhasDeRede;

  /// O `scheduled_for` que o pedido ficou a ter depois de criado.
  final DateTime? horaGravada;
  final List<DateTime?> preparados = [];

  @override
  Future<void> preparar(String restaurantId, DateTime? instante) async {
    log.add('preparar:$restaurantId:${instante?.toIso8601String()}');
    preparados.add(instante);
    if (falhasDeRede > 0) {
      falhasDeRede--;
      throw Exception('SocketException: sem rede');
    }
    if (erro != null) throw PostgrestException(message: erro!, code: 'P0001');
  }

  @override
  Future<DateTime?> horaDoPedido(String orderId) async {
    log.add('hora:$orderId');
    return horaGravada;
  }
}

/// O `create_order` (zona vermelha, não se mexe) de mentira: só regista.
class OrderStoreFalso extends ChangeNotifier implements OrderStore {
  OrderStoreFalso(this.log);
  final List<String> log;

  @override
  dynamic noSuchMethod(Invocation i) {
    if (i.memberName == #createOrder) {
      log.add('createOrder');
      return Future<bool>.value(true);
    }
    if (i.memberName == #startCardPaymentDraft) {
      log.add('startCardPaymentDraft');
      return Future<Map<String, dynamic>?>.value({'draftId': 'rascunho-1'});
    }
    if (i.memberName == #lastCreatedOrderId) return 'pedido-1';
    return null;
  }
}

class RestaurantStoreFalso extends ChangeNotifier implements RestaurantStore {
  RestaurantStoreFalso(this.loja);
  final RestaurantModel loja;

  @override
  RestaurantModel? restaurantById(String? id) => id == loja.id ? loja : null;

  @override
  dynamic noSuchMethod(Invocation i) => null;
}

// ── Dados ───────────────────────────────────────────────────────────────────

const _oitoAsVinteDuas = DayHours(open: '08:00', close: '22:00');
const _semprAberto = BusinessHours(
  mon: _oitoAsVinteDuas,
  tue: _oitoAsVinteDuas,
  wed: _oitoAsVinteDuas,
  thu: _oitoAsVinteDuas,
  fri: _oitoAsVinteDuas,
  sat: _oitoAsVinteDuas,
  sun: _oitoAsVinteDuas,
);
const _fechadoSempre = DayHours(closed: true);
const _horarioFechado = BusinessHours(
  mon: _fechadoSempre,
  tue: _fechadoSempre,
  wed: _fechadoSempre,
  thu: _fechadoSempre,
  fri: _fechadoSempre,
  sat: _fechadoSempre,
  sun: _fechadoSempre,
);

RestaurantModel continente({BusinessHours horas = _semprAberto}) => RestaurantModel(
      id: 'continente',
      name: 'Continente',
      phone: '',
      address: 'Guarda',
      email: '',
      photoUrl: '',
      cuisineType: '',
      isPartner: false,
      category: BusinessCategory.supermarket,
      businessHours: horas,
    );

CartItem leite() => CartItem(productId: 'leite', name: 'Leite', price: 0.89, quantity: 2);

/// Terça 3/11/2026 às 10:00 de Lisboa (inverno: Lisboa == UTC).
final janela = JanelaAgendada(
  inicio: DateTime.utc(2026, 11, 3, 10),
  fim: DateTime.utc(2026, 11, 3, 10, 30),
);

AgendarPedidoEstado get estado => AgendarPedidoEstado.instance;

Future<void> servidor(ServidorFalso api, MarcacaoFalsa marcacao) async {
  estado.reporParaTeste(api, novaMarcacao: marcacao);
  await estado.carregarConfig(forcar: true);
}

/// Carrinho de um mercado NÃO parceiro (compra em loja, com entrega), já com a
/// resposta do servidor sobre as janelas.
Future<CartStore> carrinhoDoContinente({bool fechada = false}) async {
  final c = CartStore();
  c.configureSession(
    serviceType: OrderServiceType.storeShopping,
    isPartnerStore: false,
    vendorName: 'Continente',
    vendorRestaurantId: 'continente',
    vendorFechada: fechada,
    vendorAvisoFechada: 'O Continente está fechado agora.',
    pickupLocation: const LatLng(40.5373, -7.2676),
    deliveryLocation: const LatLng(40.5420, -7.2700),
    dropoffStreet: 'Rua do Comércio 1',
    dropoffCity: 'Guarda',
  );
  await estado.verificarLoja('continente');
  return c;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => SharedPreferences.setMockInitialValues(<String, Object>{}));
  tearDown(() => estado.reporParaTeste(ServidorFalso(ligado: false)));

  // ── 1. A marcação antes de criar o pedido ────────────────────────────────
  group('client_preparar_agendamento ANTES de criar o pedido', () {
    test('"Agendar" (dinheiro): marca a hora, cria, e não chama a reserva', () async {
      final log = <String>[];
      final api = ServidorFalso();
      await servidor(api, MarcacaoFalsa(log, horaGravada: janela.instante));
      final c = await carrinhoDoContinente(fechada: true);
      c.addItem(leite());
      estado.escolher('continente', janela);

      final ok = await c.finishOrder(OrderStoreFalso(log),
          paymentMethod: PaymentMethod.cash, paymentStatus: PaymentStatus.paid);

      expect(ok, isTrue);
      expect(log, [
        'preparar:continente:2026-11-03T10:00:00.000Z',
        'createOrder',
        'hora:pedido-1',
      ]);
      expect(api.gravados, isEmpty,
          reason: 'o servidor já gravou a hora ao criar: a reserva não é chamada');
      expect(c.erroAgendamento, isNull);
      expect(estado.escolha, isNull, reason: 'o carrinho foi-se');
    });

    test('"Entregar agora": apaga a marcação velha (null) antes de criar', () async {
      final log = <String>[];
      final marcacao = MarcacaoFalsa(log);
      await servidor(ServidorFalso(), marcacao);
      final c = await carrinhoDoContinente();
      c.addItem(leite());

      final ok = await c.finishOrder(OrderStoreFalso(log),
          paymentMethod: PaymentMethod.cash, paymentStatus: PaymentStatus.paid);

      expect(ok, isTrue);
      expect(log, ['preparar:continente:null', 'createOrder']);
      expect(marcacao.preparados, [null]);
    });

    test('cartão: a hora é marcada antes do rascunho do pagamento', () async {
      final log = <String>[];
      await servidor(ServidorFalso(), MarcacaoFalsa(log));
      final c = await carrinhoDoContinente();
      c.addItem(leite());
      estado.escolher('continente', janela);

      final draft = await c.startCardPaymentDraft(OrderStoreFalso(log));

      expect(draft, isNotNull);
      expect(log, ['preparar:continente:2026-11-03T10:00:00.000Z', 'startCardPaymentDraft']);
    });

    test('hora recusada pelo servidor: o pedido NÃO é criado e o carrinho fica', () async {
      final log = <String>[];
      await servidor(ServidorFalso(), MarcacaoFalsa(log, erro: 'schedule_window_invalid'));
      final c = await carrinhoDoContinente(fechada: true);
      c.addItem(leite());
      estado.escolher('continente', janela);

      final ok = await c.finishOrder(OrderStoreFalso(log),
          paymentMethod: PaymentMethod.cash, paymentStatus: PaymentStatus.paid);

      expect(ok, isFalse);
      expect(log, ['preparar:continente:2026-11-03T10:00:00.000Z'],
          reason: 'sem hora marcada o pedido nasceria "para agora"');
      expect(c.erroAgendamento, 'schedule_window_invalid');
      expect(c.items, hasLength(1));
      expect(await c.startCardPaymentDraft(OrderStoreFalso(log)), isNull);
      expect(log.where((l) => l == 'startCardPaymentDraft'), isEmpty);
    });

    test('sem rede: tenta 2 vezes, devolve "rede" e não deixa criar', () async {
      final log = <String>[];
      final marcacao = MarcacaoFalsa(log, falhasDeRede: 9);
      await servidor(ServidorFalso(), marcacao);
      estado.escolher('continente', janela);
      final r = await estado.prepararAntesDeCriar(
          restaurantId: 'continente',
          tipo: OrderServiceType.storeShopping,
          pausa: Duration.zero);
      expect(r, kErroAgendarRede);
      expect(marcacao.preparados, hasLength(2));
    });

    test('pedido criado SEM a hora: chama a reserva client_set_order_schedule', () async {
      final log = <String>[];
      final api = ServidorFalso();
      await servidor(api, MarcacaoFalsa(log)); // horaGravada: null
      final c = await carrinhoDoContinente();
      c.addItem(leite());
      estado.escolher('continente', janela);

      expect(
          await c.finishOrder(OrderStoreFalso(log),
              paymentMethod: PaymentMethod.cash, paymentStatus: PaymentStatus.paid),
          isTrue);
      expect(log, [
        'preparar:continente:2026-11-03T10:00:00.000Z',
        'createOrder',
        'hora:pedido-1',
      ]);
      expect(api.gravados, [('pedido-1', DateTime.utc(2026, 11, 3, 10))]);
    });

    test('favores, envios e recolha não marcam nada', () async {
      final log = <String>[];
      await servidor(ServidorFalso(), MarcacaoFalsa(log));
      estado.escolher('continente', janela);
      for (final tipo in [
        OrderServiceType.errand,
        OrderServiceType.sendPackage,
        OrderServiceType.takeaway,
      ]) {
        expect(
            await estado.prepararAntesDeCriar(restaurantId: 'continente', tipo: tipo),
            isNull);
      }
      expect(await estado.prepararAntesDeCriar(
              restaurantId: null, tipo: OrderServiceType.storeShopping),
          isNull);
      expect(log, isEmpty);
    });

    test('interruptor desligado: "Entregar agora" não chama nada', () async {
      final log = <String>[];
      await servidor(ServidorFalso(ligado: false), MarcacaoFalsa(log));
      expect(
          await estado.prepararAntesDeCriar(
              restaurantId: 'continente', tipo: OrderServiceType.storeShopping),
          isNull);
      expect(log, isEmpty);
    });
  });

  // ── 2. A chamada verdadeira ao servidor ──────────────────────────────────
  group('AgendarMarcacaoSupabase (SDK verdadeiro, servidor falso)', () {
    test('client_preparar_agendamento com a hora e com null; erro com código', () async {
      final pedidos = <(String, Object?)>[];
      var recusar = false;
      final cliente = SupabaseClient(
        'http://127.0.0.1:1',
        'teste',
        httpClient: MockClient((r) async {
          pedidos.add((r.url.path, r.body.isEmpty ? null : jsonDecode(r.body)));
          if (recusar) {
            return http.Response(
                jsonEncode({'message': 'schedule_window_invalid', 'code': 'P0001'}), 400,
                headers: {'content-type': 'application/json'}, request: r);
          }
          return http.Response(jsonEncode({'ok': true, 'agendado': true}), 200,
              headers: {'content-type': 'application/json'}, request: r);
        }),
        authOptions: const AuthClientOptions(autoRefreshToken: false),
      );
      final m = AgendarMarcacaoSupabase(cliente);

      await m.preparar('continente', DateTime.utc(2026, 11, 3, 10));
      await m.preparar('continente', null);

      expect(pedidos[0].$1, endsWith('/rpc/client_preparar_agendamento'));
      expect(pedidos[0].$2,
          {'p_restaurant_id': 'continente', 'p_scheduled_for': '2026-11-03T10:00:00.000Z'});
      expect(pedidos[1].$2, {'p_restaurant_id': 'continente', 'p_scheduled_for': null});

      recusar = true;
      Object? erro;
      try {
        await m.preparar('continente', DateTime.utc(2026, 11, 3, 10));
      } catch (e) {
        erro = e;
      }
      expect(erro, isNotNull);
      expect(codigoErroAgendar(erro!), 'schedule_window_invalid');
    });
  });

  // ── 3. Quem tem agendar: o servidor (janelas) ────────────────────────────
  group('verificarLoja', () {
    test('com janelas: sabe-se o 1.º dia; sem janelas: não agenda', () async {
      final api = ServidorFalso();
      await servidor(api, MarcacaoFalsa([]));
      final agora = DateTime.utc(2026, 11, 2, 21, 30);
      // Uma loja que nenhum carrinho de outro teste esteja a perguntar.
      expect(await estado.verificarLoja('intermarche', agora: agora), isTrue);
      expect(estado.lojaTemJanelas('intermarche'), isTrue);
      expect(estado.primeiroDiaComJanelas('intermarche'), DateTime.utc(2026, 11, 2));
      expect(api.diasPedidos('intermarche'), [DateTime.utc(2026, 11, 2)],
          reason: 'pára no 1.º dia com janelas');

      final semJanelas = ServidorFalso(semJanelas: true);
      await servidor(semJanelas, MarcacaoFalsa([]));
      expect(await estado.verificarLoja('festas-x', agora: agora), isFalse);
      expect(estado.lojaTemJanelas('festas-x'), isFalse);
      expect(semJanelas.diasPedidos('festas-x'), hasLength(8),
          reason: 'hoje + 7 dias, todos vazios');
    });

    test('interruptor desligado: nem pergunta pelas janelas', () async {
      final api = ServidorFalso(ligado: false);
      await servidor(api, MarcacaoFalsa([]));
      expect(await estado.verificarLoja('continente'), isFalse);
      expect(api.pedidosDeJanelas, isEmpty);
      expect(estado.lojaTemJanelas('continente'), isNull);
    });
  });

  // ── 4. O seletor no carrinho de um mercado não parceiro ──────────────────
  Widget carrinhoNoEcra(CartStore c, RestaurantModel loja, {Widget? filho}) => MultiProvider(
        providers: [
          ChangeNotifierProvider<CartStore>.value(value: c),
          ChangeNotifierProvider<RestaurantStore>.value(value: RestaurantStoreFalso(loja)),
        ],
        child: MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(child: filho ?? const AgendarPedidoNoCarrinho()),
          ),
        ),
      );

  void ecraLargo(WidgetTester t) {
    t.view.physicalSize = const Size(1000, 1600);
    t.view.devicePixelRatio = 1.0;
    addTearDown(t.view.resetPhysicalSize);
    addTearDown(t.view.resetDevicePixelRatio);
  }

  group('seletor numa loja NÃO parceira', () {
    testWidgets('mercado aberto: "Entregar agora" ou "Agendar", com as janelas do servidor',
        (t) async {
      ecraLargo(t);
      await servidor(ServidorFalso(), MarcacaoFalsa([]));
      final c = await carrinhoDoContinente();
      expect(c.isPartnerStore, isFalse);
      expect(c.agendamentoDisponivel, isTrue);

      await t.pumpWidget(carrinhoNoEcra(c, continente()));
      await t.pumpAndSettle();

      expect(find.byKey(const Key('agendar-seletor')), findsOneWidget);
      expect(find.text('Entregar agora'), findsOneWidget);
      expect(find.text('Agendar'), findsOneWidget);
      final modo = t.widget<SegmentedButton<bool>>(find.byKey(const Key('agendar-modo')));
      expect(modo.segments.first.enabled, isTrue);
      expect(modo.selected, {false});
      expect(find.byKey(const Key('agendar-fechada')), findsNothing);

      await t.tap(find.text('Agendar'));
      await t.pumpAndSettle();
      expect(find.byKey(const Key('agendar-janela-10:00–10:30')), findsOneWidget);
      await t.tap(find.byKey(const Key('agendar-janela-10:30–11:00')));
      await t.pumpAndSettle();
      expect(estado.escolhaPara('continente'), isTrue);
      expect(find.byKey(const Key('agendar-resumo')), findsOneWidget);
    });

    testWidgets('mercado FECHADO com janelas: "Loja fechada: agenda para quando abrir", só Agendar',
        (t) async {
      ecraLargo(t);
      await servidor(ServidorFalso(), MarcacaoFalsa([]));
      final c = await carrinhoDoContinente(fechada: true);
      expect(c.lojaFechada, isFalse, reason: 'já não trava o carrinho');
      c.addItem(leite());
      expect(c.items, hasLength(1));
      expect(c.agendamentoObrigatorio, isTrue);

      await t.pumpWidget(carrinhoNoEcra(c, continente()));
      await t.pumpAndSettle();

      expect(find.text('Loja fechada: agenda para quando abrir'), findsOneWidget);
      final modo = t.widget<SegmentedButton<bool>>(find.byKey(const Key('agendar-modo')));
      expect(modo.segments.first.enabled, isFalse, reason: '"Entregar agora" desligado');
      expect(modo.selected, {true});
      // 1.ª janela do 1.º dia que o servidor deu, já escolhida (o cliente pode mudar).
      final primeiro = estado.primeiroDiaComJanelas('continente')!;
      expect(estado.escolhaPara('continente'), isTrue);
      expect(estado.escolha!.dia, primeiro);
      expect(estado.escolha!.horas, '10:00–10:30');
      expect(find.text('Agendado para ${diaComData(primeiro)}, 10:00–10:30'), findsOneWidget);
      expect(c.agendamentoEmFalta, isFalse);

      await t.tap(find.byKey(const Key('agendar-janela-10:30–11:00')));
      await t.pumpAndSettle();
      expect(estado.escolha!.horas, '10:30–11:00');
    });

    testWidgets('mercado fechado SEM janelas: fica como hoje (sem seletor, não deixa adicionar)',
        (t) async {
      ecraLargo(t);
      await servidor(ServidorFalso(semJanelas: true), MarcacaoFalsa([]));
      final c = await carrinhoDoContinente(fechada: true);
      c.addItem(leite());
      expect(c.items, isEmpty);
      expect(c.lojaFechada, isTrue);

      await t.pumpWidget(carrinhoNoEcra(c, continente()));
      await t.pumpAndSettle();
      expect(find.byKey(const Key('agendar-seletor')), findsNothing);
      expect(find.text('Loja fechada: agenda para quando abrir'), findsNothing);
    });

    testWidgets('loja que ainda não está na lista: o seletor aparece com os dias do servidor',
        (t) async {
      ecraLargo(t);
      await servidor(ServidorFalso(), MarcacaoFalsa([]));
      final c = await carrinhoDoContinente(fechada: true);
      // RestaurantStore sem esta loja: nada de "Finalizar" preso sem seletor.
      const outra = RestaurantModel(
        id: 'outra',
        name: 'Outra',
        phone: '',
        address: '',
        email: '',
        photoUrl: '',
        cuisineType: '',
        isPartner: false,
        category: BusinessCategory.supermarket,
      );
      await t.pumpWidget(carrinhoNoEcra(c, outra));
      await t.pumpAndSettle();
      expect(find.byKey(const Key('agendar-seletor')), findsOneWidget);
      expect(estado.escolha?.horas, '10:00–10:30');
    });

    testWidgets('faixa da loja fechada diz "agenda para quando abrir" (só com janelas)',
        (t) async {
      ecraLargo(t);
      await servidor(ServidorFalso(), MarcacaoFalsa([]));
      final c = await carrinhoDoContinente(fechada: true);
      final fechada = continente(horas: _horarioFechado);
      expect(fechada.fechadaParaCliente, isTrue);

      await t.pumpWidget(carrinhoNoEcra(c, fechada, filho: FaixaLojaFechada(loja: fechada)));
      await t.pumpAndSettle();
      expect(find.byKey(const Key('faixa-fechada-agendar')), findsOneWidget);

      // Sem carrinho no ecrã (outros ecrãs/testes): a faixa de sempre.
      await t.pumpWidget(MaterialApp(home: Scaffold(body: FaixaLojaFechada(loja: fechada))));
      await t.pumpAndSettle();
      expect(find.text(fechada.faixaFechada), findsOneWidget);
      expect(find.byKey(const Key('faixa-fechada-agendar')), findsNothing);
    });
  });

  // ── 5. Seguimento do pedido (cliente) ─────────────────────────────────────
  group('seguimento: "Agendado para…"', () {
    OrderModel pedido(OrderStatus s, {DateTime? quando}) => OrderModel(
          id: 'pc-1',
          total: 30,
          serviceType: OrderServiceType.storeShopping,
          status: s,
          isPartnerStore: false,
          vendorName: 'Continente',
          createdAt: DateTime.utc(2026, 11, 2, 21),
          scheduledFor: quando,
        );
    final hora = DateTime.utc(2026, 11, 3, 10); // terça 10:00 Lisboa
    final noiteAntes = DateTime.utc(2026, 11, 2, 21, 30);

    testWidgets('em destaque, e o título nunca diz "À procura de estafeta" antes da hora',
        (t) async {
      final p = pedido(OrderStatus.preparing, quando: hora);
      await t.pumpWidget(MaterialApp(
        home: Scaffold(
          body: Column(children: [
            Text(tituloDoSeguimento(p, noiteAntes)),
            AvisoPedidoAgendado(order: p, agora: noiteAntes),
          ]),
        ),
      ));
      expect(find.byKey(const Key('pedido-agendado-aviso')), findsOneWidget);
      expect(find.text('Agendado para ter 03/11, 10:00–10:30'), findsOneWidget);
      expect(find.text('Pedido agendado'), findsOneWidget);
      expect(find.text('Chamamos o estafeta perto da hora marcada.'), findsOneWidget);
      expect(find.textContaining('procura de estafeta'), findsNothing);
      expect(find.text('Aguardando estafeta'), findsNothing);
    });

    test('callingDriver na memória da app antes da hora (o servidor segura): "Pedido agendado"',
        () {
      final p = pedido(OrderStatus.callingDriver, quando: hora);
      expect(tituloDoSeguimento(p, noiteAntes), 'Pedido agendado');
      expect(tituloDoEstado(p, agora: noiteAntes), 'Pedido agendado');
      // 09:40: o servidor já chamou o estafeta (30 min antes) — volta o de sempre.
      final perto = DateTime.utc(2026, 11, 3, 9, 40);
      expect(tituloDoSeguimento(p, perto), OrderStatus.callingDriver.label);
      expect(tituloDoEstado(p, agora: perto), 'À procura de estafeta');
    });

    test('sem hora marcada nada muda', () {
      final p = pedido(OrderStatus.callingDriver);
      expect(aEsperaDaHoraMarcada(p, noiteAntes), isFalse);
      expect(tituloDoSeguimento(p, noiteAntes), OrderStatus.callingDriver.label);
      expect(tituloDoEstado(p, agora: noiteAntes), 'À procura de estafeta');
    });

    test('a barra do pedido mostra a hora marcada, não "chega em ~20 min"', () {
      final p = horaLisboa(DateTime.now().add(const Duration(days: 2)));
      final quando = instanteDeLisboa(DateTime.utc(p.year, p.month, p.day, 10));
      final o = pedido(OrderStatus.preparing, quando: quando);
      expect(etaDoPedido(o), textoAgendadoPara(janelaDoInstante(quando)));
    });

    testWidgets('sem scheduled_for o aviso não aparece', (t) async {
      await t.pumpWidget(MaterialApp(
          home: Scaffold(body: AvisoPedidoAgendado(order: pedido(OrderStatus.preparing)))));
      expect(find.byKey(const Key('pedido-agendado-aviso')), findsNothing);
    });
  });
}
