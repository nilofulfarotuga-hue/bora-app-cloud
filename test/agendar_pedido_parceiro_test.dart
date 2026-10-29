// Agendar pedidos (item 5 do adendo 5, 29/10/2026): o separador "Agendados" do
// parceiro e o atalho do painel. Servidor de mentira, relógio mexível, sem som.
import 'package:bora_app/models/restaurant_model.dart';
import 'package:bora_app/screens/partner/partner_agendados_screen.dart';
import 'package:bora_app/services/agendar_pedido.dart';
import 'package:bora_app/services/agendar_pedido_service.dart';
import 'package:bora_app/widgets/partner/partner_agendados_atalho.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

const loja = RestaurantModel(
  id: 'boom',
  name: 'Boom! Burger',
  phone: '',
  address: '',
  email: '',
  photoUrl: '',
  cuisineType: 'Hambúrgueres',
  isPartner: true,
  category: BusinessCategory.restaurant,
);

/// Novembro de 2026: Lisboa == UTC.
DateTime utc(int dia, int h, [int m = 0]) => DateTime.utc(2026, 11, dia, h, m);

PedidoAgendado pedido(
  String id,
  DateTime quando, {
  String estado = 'created',
  String? cliente = 'Ana',
  int? prep,
  String metodo = 'cash',
  String pagamento = 'pending',
  double total = 12.5,
  String itens = '2× Hambúrguer',
  String? notas,
}) =>
    PedidoAgendado(
      id: id,
      estado: estado,
      quando: quando,
      clienteNome: cliente,
      prepMin: prep,
      metodo: metodo,
      pagamento: pagamento,
      totalEur: total,
      itens: itens,
      notas: notas,
    );

class ApiFalsa implements AgendarPedidoApi {
  ApiFalsa({this.lista = const [], this.ligado = true, this.falha = false});
  List<PedidoAgendado> lista;
  final bool ligado;
  bool falha;
  int leituras = 0;

  @override
  Future<ConfigAgendar> config() async => ConfigAgendar(ligado: ligado);

  @override
  Future<List<PedidoAgendado>> pedidosDoParceiro(String restaurantId) async {
    leituras++;
    if (falha) throw Exception('sem rede');
    return lista;
  }

  @override
  Future<List<JanelaAgendada>> janelas(String restaurantId, DateTime dia) async => const [];

  @override
  Future<void> gravar(String orderId, DateTime instante) async {}
}

void ecraAlto(WidgetTester t) {
  t.view.physicalSize = const Size(900, 2400);
  t.view.devicePixelRatio = 1.0;
  addTearDown(t.view.resetPhysicalSize);
  addTearDown(t.view.resetDevicePixelRatio);
}

void main() {
  group('PartnerAgendadosScreen', () {
    testWidgets('sem pedidos: diz que não há nenhum', (t) async {
      ecraAlto(t);
      await t.pumpWidget(MaterialApp(
        home: PartnerAgendadosScreen(
          restaurant: loja,
          api: ApiFalsa(),
          relogio: () => utc(3, 12),
          aoAvisar: (_) {},
          intervalo: const Duration(hours: 1),
        ),
      ));
      await t.pumpAndSettle();
      expect(find.text('Pedidos agendados'), findsOneWidget);
      expect(find.byKey(const Key('agendados-vazio')), findsOneWidget);
      expect(find.byKey(const Key('agendados-alerta')), findsNothing);
      await t.pumpWidget(const SizedBox());
    });

    testWidgets('lista por ordem, com a hora, "faltam X min" e o estado de cada um', (t) async {
      ecraAlto(t);
      final api = ApiFalsa(lista: [
        pedido('ped-aaaa1111', utc(3, 12, 25), estado: 'created'), // daqui a 25 min
        pedido('ped-bbbb2222', utc(3, 14, 30),
            estado: 'preparing', prep: 20, metodo: 'card', pagamento: 'paid', cliente: 'Rui'),
        pedido('ped-cccc3333', utc(4, 19, 30), notas: 'Sem cebola'), // amanhã
        pedido('ped-dddd4444', utc(7, 13), cliente: null), // sábado
      ]);
      await t.pumpWidget(MaterialApp(
        home: PartnerAgendadosScreen(
          restaurant: loja,
          api: api,
          relogio: () => utc(3, 12),
          aoAvisar: (_) {},
          intervalo: const Duration(hours: 1),
        ),
      ));
      await t.pumpAndSettle();

      // Títulos de dia
      expect(find.text('Hoje'), findsOneWidget);
      expect(find.text('Amanhã'), findsOneWidget);
      expect(find.text('sábado 07/11'), findsOneWidget);
      // Horas (janela de 30 min) e "faltam"
      expect(find.text('12:25–12:55'), findsOneWidget);
      expect(find.text('14:30–15:00'), findsOneWidget);
      expect(find.text('19:30–20:00'), findsOneWidget);
      expect(find.byKey(const Key('agendado-falta-ped-aaaa1111')), findsOneWidget);
      expect(t.widget<Text>(find.byKey(const Key('agendado-falta-ped-aaaa1111'))).data, 'faltam 25 min');
      expect(t.widget<Text>(find.byKey(const Key('agendado-falta-ped-bbbb2222'))).data, 'faltam 2 h 30 min');
      expect(t.widget<Text>(find.byKey(const Key('agendado-falta-ped-cccc3333'))).data, 'faltam 1 dia 7 h');
      // Estado de cada pedido
      expect(t.widget<Text>(find.byKey(const Key('agendado-estado-ped-aaaa1111'))).data,
          'Por aceitar — aceita no ecrã principal');
      expect(t.widget<Text>(find.byKey(const Key('agendado-estado-ped-bbbb2222'))).data,
          'Aceite · preparação 20 min');
      // Cliente, itens, pagamento
      expect(find.text('Rui'), findsOneWidget);
      expect(find.text('12,50 € · Cartão · pago'), findsOneWidget);
      expect(find.text('12,50 € · Dinheiro'), findsNWidgets(3));
      expect(find.text('Sem cebola'), findsOneWidget);
      await t.pumpWidget(const SizedBox());
    });

    testWidgets('a 30 min ou menos: banner de alerta e o som toca UMA vez por pedido', (t) async {
      ecraAlto(t);
      final avisados = <String>[];
      final api = ApiFalsa(lista: [
        pedido('ped-aaaa1111', utc(3, 12, 25)), // 25 min → alerta
        pedido('ped-bbbb2222', utc(3, 14)), // 2 h → sem alerta
      ]);
      await t.pumpWidget(MaterialApp(
        home: PartnerAgendadosScreen(
          restaurant: loja,
          api: api,
          relogio: () => utc(3, 12),
          aoAvisar: (p) => avisados.add(p.id),
          intervalo: const Duration(seconds: 30),
        ),
      ));
      await t.pumpAndSettle();

      expect(find.byKey(const Key('agendados-alerta')), findsOneWidget);
      expect(find.textContaining('Pedido agendado: faltam 25 min'), findsOneWidget);
      expect(avisados, ['ped-aaaa1111']);

      // Passam dois ciclos do relógio: não volta a tocar para o mesmo pedido.
      await t.pump(const Duration(seconds: 30));
      await t.pump(const Duration(seconds: 30));
      expect(avisados, ['ped-aaaa1111']);
      await t.pumpWidget(const SizedBox());
    });

    testWidgets('um pedido que entra nos 30 min com o ecrã aberto dispara o alerta', (t) async {
      ecraAlto(t);
      var agora = utc(3, 12);
      final avisados = <String>[];
      await t.pumpWidget(MaterialApp(
        home: PartnerAgendadosScreen(
          restaurant: loja,
          api: ApiFalsa(lista: [pedido('ped-aaaa1111', utc(3, 12, 45))]),
          relogio: () => agora,
          aoAvisar: (p) => avisados.add(p.id),
          intervalo: const Duration(seconds: 30),
        ),
      ));
      await t.pumpAndSettle();
      expect(avisados, isEmpty);
      expect(find.byKey(const Key('agendados-alerta')), findsNothing);

      agora = utc(3, 12, 20); // faltam 25 min
      await t.pump(const Duration(seconds: 30));
      expect(avisados, ['ped-aaaa1111']);
      expect(find.byKey(const Key('agendados-alerta')), findsOneWidget);
      expect(t.widget<Text>(find.byKey(const Key('agendado-falta-ped-aaaa1111'))).data, 'faltam 25 min');
      await t.pumpWidget(const SizedBox());
    });

    testWidgets('erro de rede: mostra a mensagem em vez de rebentar', (t) async {
      ecraAlto(t);
      await t.pumpWidget(MaterialApp(
        home: PartnerAgendadosScreen(
          restaurant: loja,
          api: ApiFalsa(falha: true),
          relogio: () => utc(3, 12),
          aoAvisar: (_) {},
          intervalo: const Duration(hours: 1),
        ),
      ));
      await t.pumpAndSettle();
      expect(find.byKey(const Key('agendados-erro')), findsOneWidget);
      await t.pumpWidget(const SizedBox());
    });
  });

  group('PartnerAgendadosAtalho', () {
    testWidgets('desligado: não ocupa espaço', (t) async {
      final estado = AgendarPedidoEstado.paraTeste(ApiFalsa(ligado: false));
      await t.pumpWidget(MaterialApp(
        home: Scaffold(body: PartnerAgendadosAtalho(restaurant: loja, estado: estado)),
      ));
      await t.pumpAndSettle();
      expect(find.byKey(const Key('atalho-agendados')), findsNothing);
    });

    testWidgets('ligado: mostra quantos há e quando é o próximo', (t) async {
      final estado = AgendarPedidoEstado.paraTeste(ApiFalsa(lista: [
        pedido('ped-aaaa1111', utc(3, 12, 40)),
        pedido('ped-bbbb2222', utc(4, 19)),
      ]));
      await t.pumpWidget(MaterialApp(
        home: Scaffold(
          body: PartnerAgendadosAtalho(restaurant: loja, estado: estado, relogio: () => utc(3, 12)),
        ),
      ));
      await t.pumpAndSettle();
      expect(find.byKey(const Key('atalho-agendados')), findsOneWidget);
      expect(find.text('Pedidos agendados'), findsOneWidget);
      expect(t.widget<Text>(find.byKey(const Key('atalho-agendados-texto'))).data,
          '2 agendados · próximo: faltam 40 min.');
    });
  });
}
