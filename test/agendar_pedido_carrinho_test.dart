// Agendar pedidos (item 5 do adendo 5, 29/10/2026): o que o carrinho passa a
// dizer com o interruptor ligado — a loja fechada deixa de travar o "adicionar",
// o cliente TEM de escolher uma janela, e nada muda quando está desligado.
import 'package:bora_app/models/cart_item.dart';
import 'package:bora_app/models/order_service_type.dart';
import 'package:bora_app/services/agendar_pedido.dart';
import 'package:bora_app/services/agendar_pedido_service.dart';
import 'package:bora_app/stores/cart_store.dart';
import 'package:flutter_test/flutter_test.dart';

class ApiFalsa implements AgendarPedidoApi {
  ApiFalsa({this.ligado = true});
  bool ligado;

  @override
  Future<ConfigAgendar> config() async => ConfigAgendar(ligado: ligado);

  @override
  Future<List<JanelaAgendada>> janelas(String restaurantId, DateTime dia) async => const [];

  @override
  Future<void> gravar(String orderId, DateTime instante) async {}

  @override
  Future<List<PedidoAgendado>> pedidosDoParceiro(String restaurantId) async => const [];
}

CartItem item() => CartItem(productId: 'p1', name: 'Hambúrguer', price: 9.5, quantity: 1);

final janela = JanelaAgendada(
  inicio: DateTime.utc(2026, 11, 3, 19, 30),
  fim: DateTime.utc(2026, 11, 3, 20),
);

Future<void> ligar(bool v) async {
  final e = AgendarPedidoEstado.instance;
  e.reporParaTeste(ApiFalsa(ligado: v));
  await e.carregarConfig(forcar: true);
}

CartStore carrinho({
  bool fechada = true,
  bool festas = false,
  bool parceira = true,
  OrderServiceType tipo = OrderServiceType.restaurant,
}) {
  final c = CartStore();
  c.configureSession(
    serviceType: tipo,
    isPartnerStore: parceira,
    vendorName: 'Boom! Burger',
    vendorRestaurantId: 'boom',
    vendorIsFestas: festas,
    vendorFechada: fechada,
    vendorAvisoFechada: 'Boom! Burger está fechada agora. Abre às 19h15.',
  );
  return c;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  tearDown(() => AgendarPedidoEstado.instance.reporParaTeste(ApiFalsa(ligado: false)));

  group('interruptor DESLIGADO: tudo como dantes', () {
    test('loja fechada não deixa adicionar e nada pede para agendar', () async {
      await ligar(false);
      final c = carrinho();
      c.addItem(item());
      expect(c.items, isEmpty);
      expect(c.lojaFechada, isTrue);
      expect(c.lojaFechadaAgora, isTrue);
      expect(c.agendamentoDisponivel, isFalse);
      expect(c.agendamentoObrigatorio, isFalse);
      expect(c.agendamentoEmFalta, isFalse);
    });

    test('loja aberta adiciona e não pede nada', () async {
      await ligar(false);
      final c = carrinho(fechada: false);
      c.addItem(item());
      expect(c.items, hasLength(1));
      expect(c.agendamentoEmFalta, isFalse);
    });
  });

  group('interruptor LIGADO', () {
    test('loja fechada deixa adicionar, e o cliente tem de escolher uma janela', () async {
      await ligar(true);
      final c = carrinho();
      expect(c.lojaFechadaAgora, isTrue);
      expect(c.lojaFechada, isFalse, reason: 'já não trava o carrinho');
      c.addItem(item());
      expect(c.items, hasLength(1));
      expect(c.agendamentoDisponivel, isTrue);
      expect(c.agendamentoObrigatorio, isTrue);
      expect(c.agendamentoEmFalta, isTrue, reason: 'ainda não escolheu a janela');

      AgendarPedidoEstado.instance.escolher('boom', janela);
      expect(c.agendamentoEmFalta, isFalse);
    });

    test('a escolha de outra loja não serve a esta', () async {
      await ligar(true);
      final c = carrinho();
      AgendarPedidoEstado.instance.escolher('outra-loja', janela);
      expect(c.agendamentoEmFalta, isTrue);
    });

    test('loja aberta: agendar é opcional, nunca obrigatório', () async {
      await ligar(true);
      final c = carrinho(fechada: false);
      expect(c.agendamentoDisponivel, isTrue);
      expect(c.agendamentoObrigatorio, isFalse);
      expect(c.agendamentoEmFalta, isFalse);
    });

    test('festas, mercado não parceiro e takeaway continuam como dantes', () async {
      await ligar(true);
      final festas = carrinho(festas: true);
      festas.addItem(item());
      expect(festas.items, isEmpty);
      expect(festas.lojaFechada, isTrue);
      expect(festas.agendamentoDisponivel, isFalse);

      final mercado = carrinho(parceira: false, tipo: OrderServiceType.storeShopping);
      expect(mercado.lojaFechada, isTrue);
      expect(mercado.agendamentoDisponivel, isFalse);

      final takeaway = carrinho(tipo: OrderServiceType.takeaway);
      expect(takeaway.lojaFechada, isTrue);
      expect(takeaway.agendamentoDisponivel, isFalse);
    });

    test('quando a configuração chega depois, o carrinho avisa os ecrãs', () async {
      AgendarPedidoEstado.instance.reporParaTeste(ApiFalsa(ligado: true));
      final c = carrinho();
      var avisos = 0;
      c.addListener(() => avisos++);
      expect(c.lojaFechada, isTrue, reason: 'a configuração ainda não foi lida');
      await AgendarPedidoEstado.instance.carregarConfig(forcar: true);
      expect(c.lojaFechada, isFalse);
      expect(avisos, greaterThan(0));
    });
  });
}
