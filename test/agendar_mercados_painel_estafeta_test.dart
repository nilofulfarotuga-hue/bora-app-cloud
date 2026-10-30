// Agendar nos mercados e lojas não parceiras (30/10/2026): o que o ESTAFETA vê
// ("Entrega marcada: 10:00–10:30") e o PAINEL ADMIN (PT-BR): filtro Todos /
// Parceiros / Não parceiros e etiqueta em cada linha.
import 'package:bora_app/models/order_model.dart';
import 'package:bora_app/screens/admin/admin_pedidos_agendados_screen.dart';
import 'package:bora_app/services/agendar_pedido.dart';
import 'package:bora_app/services/agendar_pedido_service.dart';
import 'package:bora_app/widgets/entrega_marcada_estafeta.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

DateTime utc(int dia, int h, [int m = 0]) => DateTime.utc(2026, 11, dia, h, m);

OrderModel pedido({DateTime? quando}) => OrderModel(
      id: 'pc-1',
      total: 30,
      serviceType: OrderServiceType.storeShopping,
      status: OrderStatus.callingDriver,
      isPartnerStore: false,
      vendorName: 'Continente',
      scheduledFor: quando,
    );

class AdminApiFalsa implements AgendarPedidoAdminApi {
  AdminApiFalsa(this.lista);
  final List<PedidoAgendado> lista;

  @override
  Future<ConfigAgendarAdmin> config() async =>
      const ConfigAgendarAdmin(ligado: true, revisorOk: true, total: 3, proximas24h: 2);

  @override
  Future<ConfigAgendarAdmin> definir(String chave, Object valor) async => config();

  @override
  Future<List<PedidoAgendado>> pedidos() async => lista;
}

void main() {
  group('estafeta: "Entrega marcada"', () {
    test('o texto, hoje e noutro dia (sempre em português)', () {
      final hoje = utc(3, 9, 35); // terça 09:35
      expect(textoEntregaMarcada(utc(3, 10), hoje), 'Entrega marcada: 10:00–10:30');
      expect(textoEntregaMarcada(utc(4, 19, 30), hoje),
          'Entrega marcada: qua 04/11, 19:30–20:00');
      expect(textoEntregaMarcada(null, hoje), isNull);
    });

    testWidgets('aparece em destaque com scheduled_for e some sem ele', (t) async {
      await t.pumpWidget(MaterialApp(
        home: Scaffold(
          body: Column(children: [
            EntregaMarcadaEstafeta(order: pedido(quando: utc(3, 10)), agora: utc(3, 9, 35)),
            EntregaMarcadaEstafeta(order: pedido(), agora: utc(3, 9, 35)),
          ]),
        ),
      ));
      expect(find.text('Entrega marcada: 10:00–10:30'), findsOneWidget);
      expect(find.byKey(const Key('entrega-marcada-estafeta')), findsOneWidget);
    });

    test('lado do cliente: à espera da hora até 30 min antes, depois já não', () {
      final p = pedido(quando: utc(3, 10));
      expect(aEsperaDaHoraMarcada(p, utc(3, 9, 29)), isTrue);
      expect(aEsperaDaHoraMarcada(p, utc(3, 9, 30)), isFalse);
    });
  });

  group('painel: pedidos agendados de parceiros e não parceiros', () {
    PedidoAgendado linha(String id, String loja, bool? parceiro, String tipo,
            {String estado = 'preparing'}) =>
        PedidoAgendado(
          id: id,
          estado: estado,
          quando: utc(3, 10),
          lojaNome: loja,
          clienteNome: 'Ana',
          totalEur: 20,
          metodo: 'cash',
          parceiro: parceiro,
          tipoServico: tipo,
        );

    final lista = [
      linha('ped-aaaa1111', 'Boom! Burger', true, 'restaurant'),
      linha('ped-bbbb2222', 'Continente', false, 'storeShopping'),
      linha('ped-cccc3333', 'Tasca do Zé', false, 'restaurant', estado: 'created'),
    ];

    void ecraAlto(WidgetTester t) {
      t.view.physicalSize = const Size(900, 2400);
      t.view.devicePixelRatio = 1.0;
      addTearDown(t.view.resetPhysicalSize);
      addTearDown(t.view.resetDevicePixelRatio);
    }

    testWidgets('filtro Todos / Parceiros / Não parceiros, com etiqueta em cada linha',
        (t) async {
      ecraAlto(t);
      await t.pumpWidget(MaterialApp(
        home: AdminPedidosAgendadosScreen(api: AdminApiFalsa(lista), relogio: () => utc(2, 21)),
      ));
      await t.pumpAndSettle();

      // Todos
      expect(find.byKey(const Key('agendados-filtro')), findsOneWidget);
      expect(find.byKey(const Key('agendado-admin-ped-aaaa1111')), findsOneWidget);
      expect(find.byKey(const Key('agendado-admin-ped-bbbb2222')), findsOneWidget);
      expect(find.byKey(const Key('agendado-admin-ped-cccc3333')), findsOneWidget);
      expect(find.text('Parceiro'), findsOneWidget);
      expect(find.text('Não parceiro · Mercado/loja'), findsOneWidget);
      expect(find.text('Não parceiro'), findsOneWidget);
      // Não parceiro em preparo = à espera da hora, sem estafeta.
      expect(find.textContaining('Aguardando a hora (sem estafeta ainda)'), findsOneWidget);
      expect(find.textContaining('Aceito, em preparo'), findsOneWidget);

      await t.tap(find.byKey(const Key('agendados-filtro-nao-parceiros')));
      await t.pumpAndSettle();
      expect(find.byKey(const Key('agendado-admin-ped-aaaa1111')), findsNothing);
      expect(find.byKey(const Key('agendado-admin-ped-bbbb2222')), findsOneWidget);
      expect(find.byKey(const Key('agendado-admin-ped-cccc3333')), findsOneWidget);

      await t.tap(find.byKey(const Key('agendados-filtro-parceiros')));
      await t.pumpAndSettle();
      expect(find.byKey(const Key('agendado-admin-ped-aaaa1111')), findsOneWidget);
      expect(find.byKey(const Key('agendado-admin-ped-bbbb2222')), findsNothing);
      expect(find.byKey(const Key('agendado-admin-ped-cccc3333')), findsNothing);

      await t.tap(find.byKey(const Key('agendados-filtro-todos')));
      await t.pumpAndSettle();
      expect(find.byKey(const Key('agendado-admin-ped-cccc3333')), findsOneWidget);
    });

    testWidgets('filtro sem nenhum pedido diz que está vazio', (t) async {
      ecraAlto(t);
      await t.pumpWidget(MaterialApp(
        home: AdminPedidosAgendadosScreen(
            api: AdminApiFalsa([lista.first]), relogio: () => utc(2, 21)),
      ));
      await t.pumpAndSettle();
      await t.tap(find.byKey(const Key('agendados-filtro-nao-parceiros')));
      await t.pumpAndSettle();
      expect(find.byKey(const Key('agendados-admin-vazio-filtro')), findsOneWidget);
    });

    test('o servidor manda is_partner_store e service_type; sem eles fica "não se sabe"', () {
      final j = <String, dynamic>{
        'id': 'ped-1',
        'status': 'preparing',
        'scheduled_for': '2026-11-03T10:00:00+00:00',
        'is_partner_store': false,
        'service_type': 'storeShopping',
      };
      final p = PedidoAgendado.fromJson(j);
      expect(p.parceiro, isFalse);
      expect(p.tipoServico, 'storeShopping');
      final antigo = PedidoAgendado.fromJson({...j}
        ..remove('is_partner_store')
        ..remove('service_type'));
      expect(antigo.parceiro, isNull);
      expect(filtrarAgendados([p, antigo], FiltroAgendados.naoParceiros), [p]);
      expect(filtrarAgendados([p, antigo], FiltroAgendados.parceiros), isEmpty);
      expect(filtrarAgendados([p, antigo], FiltroAgendados.todos), hasLength(2));
    });
  });
}
