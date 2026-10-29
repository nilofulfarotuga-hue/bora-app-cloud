// ADENDO 4 — itens 1, 2 e 3 (29/10/2026).
//
//   1  barra fixa do pedido em curso, com tempo estimado recalculado
//   2  foto de prova da entrega visível ao cliente
//   3  oferta ao estafeta com ganho, quilómetros e paragens antes de aceitar
import 'package:bora_app/l10n/bora_lang.dart';
import 'package:bora_app/models/order_model.dart';
import 'package:bora_app/services/interruptores_app.dart';
import 'package:bora_app/widgets/barra_pedido_ativo.dart';
import 'package:bora_app/widgets/foto_prova_entrega.dart';
import 'package:bora_app/widgets/oferta_resumo_estafeta.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';

// Guarda: recolha e entrega a cerca de 2,7 km uma da outra.
const _loja = LatLng(40.5373, -7.2680);
const _casa = LatLng(40.5560, -7.2500);

OrderModel _pedido({
  OrderStatus estado = OrderStatus.created,
  String id = 'p1',
  DateTime? criado,
  int? preparacao,
  LatLng? recolha = _loja,
  LatLng? entrega = _casa,
  OrderServiceType tipo = OrderServiceType.restaurant,
  double? estafetaLat,
  double? estafetaLng,
  DateTime? prontoAs,
}) =>
    OrderModel(
      id: id,
      total: 12.5,
      serviceType: tipo,
      status: estado,
      createdAt: criado ?? DateTime.utc(2026, 10, 29, 12),
      vendorName: 'Boom! Burger',
      pickupLocation: recolha,
      destination: entrega,
      prepTimeMinutes: preparacao,
      driverLat: estafetaLat,
      driverLng: estafetaLng,
      takeawayReadyAt: prontoAs,
    );

int _minutos(String? eta) {
  final m = RegExp(r'~(\d+) min').firstMatch(eta ?? '');
  expect(m, isNotNull, reason: 'esperava "Chega em ~N min", veio: $eta');
  return int.parse(m!.group(1)!);
}

Widget _app(Widget filho) => MaterialApp(home: Scaffold(body: filho));

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    BoraLang.notifier.value = AppLang.pt;
    InterruptoresApp.instance.definirParaTeste({
      InterruptoresApp.barraPedidoAtivo: true,
      InterruptoresApp.fotoEntregaCliente: true,
      InterruptoresApp.ofertaGanhoVisivel: true,
    });
  });

  group('1 — barra do pedido em curso', () {
    test('mostra o pedido mais recente que ainda não acabou', () {
      final a = _pedido(id: 'a', criado: DateTime.utc(2026, 10, 29, 10));
      final b = _pedido(
          id: 'b',
          estado: OrderStatus.onTheWay,
          criado: DateTime.utc(2026, 10, 29, 12));
      final c = _pedido(
          id: 'c',
          estado: OrderStatus.delivered,
          criado: DateTime.utc(2026, 10, 29, 13));
      expect(escolherPedidoAtivo([a, b, c])?.id, 'b');
    });

    test('entregue, recusado e cancelado não têm barra', () {
      for (final e in [
        OrderStatus.delivered,
        OrderStatus.rejected,
        OrderStatus.cancelled,
      ]) {
        expect(escolherPedidoAtivo([_pedido(estado: e)]), isNull, reason: '$e');
      }
      expect(escolherPedidoAtivo(const []), isNull);
    });

    test('cada estado diz uma coisa diferente e legível', () {
      final textos = {
        for (final e in OrderStatus.values) tituloDoEstado(_pedido(estado: e)),
      };
      expect(textos.length, OrderStatus.values.length,
          reason: 'dois estados com o mesmo texto: o cliente não os distingue');
      expect(textos.every((t) => t.trim().length > 5), isTrue);
    });

    test('o tempo nunca é um "5-20 min" fixo: vem da distância e da preparação',
        () {
      final perto = etaDoPedido(_pedido(
          recolha: const LatLng(40.5373, -7.2680),
          entrega: const LatLng(40.5400, -7.2680)));
      final longe = etaDoPedido(_pedido(
          recolha: const LatLng(40.5373, -7.2680),
          entrega: const LatLng(40.6200, -7.1800)));
      expect(_minutos(longe), greaterThan(_minutos(perto)),
          reason: 'mais longe, mais tempo');
      expect(perto, isNot(contains('-')));
      expect(longe, isNot(contains('5-20')));
    });

    test('loja com tempo de preparação anunciado soma-o ao tempo estimado', () {
      final semTempo = _minutos(etaDoPedido(_pedido(estado: OrderStatus.preparing)));
      final com30 = _minutos(
          etaDoPedido(_pedido(estado: OrderStatus.preparing, preparacao: 30)));
      expect(com30, greaterThan(semTempo));
    });

    test('a preparar: o que já passou desconta-se, sem baixar de 5 minutos', () {
      final p = _pedido(estado: OrderStatus.preparing, preparacao: 30);
      final agora = _minutos(etaDoPedido(p));
      final vinteDepois =
          _minutos(etaDoPedido(p, naFase: const Duration(minutes: 20)));
      expect(vinteDepois, lessThan(agora));
      expect(agora - vinteDepois, greaterThanOrEqualTo(15));
      final horasDepois =
          _minutos(etaDoPedido(p, naFase: const Duration(hours: 3)));
      expect(horasDepois, 5, reason: 'nunca abaixo de 5 minutos');
      expect(horasDepois % 5, 0);
    });

    test('à espera da loja aceitar (created) não se desconta nada', () {
      final p = _pedido(estado: OrderStatus.created, preparacao: 30);
      expect(etaDoPedido(p, naFase: const Duration(minutes: 20)), etaDoPedido(p));
    });

    test('com estafeta a caminho conta a distância viva, não o relógio', () {
      // Estafeta a cerca de 1 km da casa do cliente.
      final p = _pedido(
          estado: OrderStatus.onTheWay,
          estafetaLat: 40.5560,
          estafetaLng: -7.2380);
      final perto = _minutos(etaDoPedido(p, naFase: const Duration(minutes: 30)));
      expect(perto, lessThanOrEqualTo(10));
      final longe = _pedido(
          estado: OrderStatus.onTheWay,
          estafetaLat: 40.5373,
          estafetaLng: -7.2680);
      expect(_minutos(etaDoPedido(longe)), greaterThan(perto));
    });

    test('takeaway mostra a hora a que fica pronto, não minutos de entrega', () {
      final p = _pedido(
          tipo: OrderServiceType.takeaway,
          estado: OrderStatus.preparing,
          prontoAs: DateTime.now().add(const Duration(minutes: 20)));
      expect(etaDoPedido(p), startsWith('Pronto às '));
      expect(etaDoPedido(_pedido(tipo: OrderServiceType.takeaway)), isNull);
    });

    test('sem coordenadas não se inventa número', () {
      expect(etaDoPedido(_pedido(recolha: null, entrega: null)), isNull);
    });

    test('pedido acabado não tem tempo estimado', () {
      expect(etaDoPedido(_pedido(estado: OrderStatus.delivered)), isNull);
    });

    testWidgets('a barra mostra estado e tempo, em 16 px, e abre ao tocar',
        (t) async {
      OrderModel? aberto;
      final p = _pedido(estado: OrderStatus.preparing, preparacao: 20);
      await t.pumpWidget(_app(BarraPedidoAtivoVista(
        pedido: p,
        eta: etaDoPedido(p),
        aoTocar: () => aberto = p,
      )));
      expect(find.text('A loja está a preparar'), findsOneWidget);
      final etaTexto = t.widget<Text>(find.byKey(const Key('barra_pedido_ativo_eta')));
      expect(etaTexto.data, startsWith('Chega em ~'));
      expect(etaTexto.style!.fontSize, greaterThanOrEqualTo(16));
      expect(t.getSize(find.byKey(const Key('barra_pedido_ativo'))).height,
          greaterThanOrEqualTo(56));
      await t.tap(find.byKey(const Key('barra_pedido_ativo')));
      expect(aberto, same(p));
    });

    testWidgets('sem tempo estimado só aparece o estado', (t) async {
      final p = _pedido(estado: OrderStatus.callingDriver);
      await t.pumpWidget(_app(
          BarraPedidoAtivoVista(pedido: p, eta: null, aoTocar: () {})));
      expect(find.text('À procura de estafeta'), findsOneWidget);
      expect(find.byKey(const Key('barra_pedido_ativo_eta')), findsNothing);
    });

    test('estado partilhado: ver o acompanhamento esconde a barra', () {
      BarraPedidoAtivoEstado.pedidoAVer.value = 'p1';
      expect(BarraPedidoAtivoEstado.pedidoAVer.value, 'p1');
      BarraPedidoAtivoEstado.pedidoAVer.value = null;
    });
  });

  group('1 — barra global à volta do Navigator', () {
    testWidgets(
        'o ecrã de baixo mantém o estado quando o teclado abre (a árvore não muda de forma)',
        (t) async {
      Widget montar(double teclado) => MediaQuery(
            data: MediaQueryData(viewInsets: EdgeInsets.only(bottom: teclado)),
            child: const MaterialApp(
              home: BarraPedidoAtivoHost(child: _Contador()),
            ),
          );
      await t.pumpWidget(montar(0));
      await t.tap(find.byKey(const Key('contador')));
      await t.tap(find.byKey(const Key('contador')));
      await t.pump();
      expect(find.text('2'), findsOneWidget);
      await t.pumpWidget(montar(300));
      await t.pump();
      expect(find.text('2'), findsOneWidget,
          reason: 'se a forma da árvore mudasse, o Navigator perdia a pilha');
      await t.pumpWidget(montar(0));
      await t.pump();
      expect(find.text('2'), findsOneWidget);
    });

    testWidgets('sem armazém de pedidos (arranque) não há barra e não rebenta',
        (t) async {
      await t.pumpWidget(const MaterialApp(
          home: BarraPedidoAtivoHost(child: Scaffold(body: Text('ecrã')))));
      await t.pump();
      expect(find.text('ecrã'), findsOneWidget);
      expect(find.byKey(const Key('barra_pedido_ativo')), findsNothing);
      expect(BarraPedidoAtivoEstado.visivel.value, isFalse);
    });
  });

  group('2 — foto de prova da entrega no ecrã do cliente', () {
    test('a hora da foto lê-se "Tirada às HH:mm"', () {
      final quando = DateTime(2026, 10, 29, 14, 5).toUtc();
      expect(textoHoraDaFoto(quando), 'Tirada às 14:05');
      expect(textoHoraDaFoto(null), isNull);
    });

    test('interruptor existe com a chave do painel', () {
      expect(InterruptoresApp.fotoEntregaCliente, 'feature_foto_entrega_cliente');
    });
  });

  group('3 — oferta ao estafeta: ganho, quilómetros e paragens', () {
    test('entrega normal tem 2 paragens: recolha e entrega', () {
      expect(paragensDaOferta(_pedido()), 2);
      expect(textoParagens(2), '2 paragens');
      expect(textoParagens(1), '1 paragem');
    });

    test('favor conta os passos da rota (casa, local do favor, entrega)', () {
      final semCasa = OrderModel(
        id: 'f1',
        total: 8,
        serviceType: OrderServiceType.errand,
        errandLocation: 'Farmácia Tavares',
        destination: _casa,
        dropoffAddress: 'Rua do Comércio 12',
      );
      final comCasa = OrderModel(
        id: 'f2',
        total: 8,
        serviceType: OrderServiceType.errand,
        errandLocation: 'Farmácia Tavares',
        errandHomeStop: true,
        errandHomeStopAddress: 'Rua do Comércio 12',
        destination: _casa,
        dropoffAddress: 'Rua do Comércio 12',
      );
      expect(paragensDaOferta(semCasa), 2);
      expect(paragensDaOferta(comCasa), 3);
    });

    test('quilómetros: estafeta→loja + loja→cliente quando se sabem as duas',
        () {
      const estafeta = LatLng(40.5300, -7.2700);
      final comEstafeta = kmTotalDaOferta(_pedido(), estafeta)!;
      final semEstafeta = kmTotalDaOferta(_pedido(), null)!;
      expect(comEstafeta, greaterThan(semEstafeta));
      expect(semEstafeta, closeTo(2.7, 0.6));
    });

    test('sem coordenadas cai na distância do pedido; sem nada, null', () {
      final p = OrderModel(
          id: 'x', total: 5, serviceType: OrderServiceType.restaurant, distanceKm: 3.4);
      expect(kmTotalDaOferta(p, null), 3.4);
      expect(
          kmTotalDaOferta(
              OrderModel(
                  id: 'y', total: 5, serviceType: OrderServiceType.restaurant),
              null),
          isNull);
    });

    testWidgets('mostra "Ganhas €3,80", os km e as paragens', (t) async {
      await t.pumpWidget(_app(OfertaResumoEstafeta(order: _pedido(), ganho: 3.8)));
      await t.pump();
      expect(find.text('Ganhas €3,80'), findsOneWidget);
      expect(find.text('2 paragens'), findsOneWidget);
      expect(find.textContaining('km no total'), findsOneWidget);
      final ganho = t.widget<Text>(find.text('Ganhas €3,80'));
      expect(ganho.style!.fontSize, greaterThanOrEqualTo(16));
    });

    testWidgets('ganho ainda não confirmado pelo servidor: não se inventa',
        (t) async {
      await t.pumpWidget(_app(OfertaResumoEstafeta(order: _pedido(), ganho: null)));
      await t.pump();
      expect(find.text('Ganho a confirmar'), findsOneWidget);
      expect(find.textContaining('Ganhas'), findsNothing);
    });

    testWidgets('com o interruptor desligado no painel não desenha nada',
        (t) async {
      InterruptoresApp.instance.definirParaTeste(
          {InterruptoresApp.ofertaGanhoVisivel: false});
      await t.pumpWidget(_app(OfertaResumoEstafeta(order: _pedido(), ganho: 3.8)));
      await t.pump();
      expect(find.byKey(const Key('oferta_resumo_estafeta')), findsNothing);
    });
  });
}

class _Contador extends StatefulWidget {
  const _Contador();

  @override
  State<_Contador> createState() => _ContadorState();
}

class _ContadorState extends State<_Contador> {
  int _n = 0;

  @override
  Widget build(BuildContext context) => Scaffold(
        body: Center(
          child: TextButton(
            key: const Key('contador'),
            onPressed: () => setState(() => _n++),
            child: Text('$_n'),
          ),
        ),
      );
}
