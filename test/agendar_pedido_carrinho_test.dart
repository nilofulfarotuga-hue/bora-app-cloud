// Agendar pedidos (item 5 do adendo 5, 29/10/2026): o que o carrinho passa a
// dizer com o interruptor ligado — a loja fechada deixa de travar o "adicionar",
// o cliente TEM de escolher uma janela, e nada muda quando está desligado.
// 30/10/2026: quem diz se a loja agenda é o SERVIDOR (janelas), não o
// `isPartner` — os mercados e as lojas não parceiras passaram a agendar.
import 'package:bora_app/models/cart_item.dart';
import 'package:bora_app/models/order_service_type.dart';
import 'package:bora_app/services/agendar_pedido.dart';
import 'package:bora_app/services/agendar_pedido_service.dart';
import 'package:bora_app/stores/cart_store.dart';
import 'package:flutter_test/flutter_test.dart';

class ApiFalsa implements AgendarPedidoApi {
  ApiFalsa({this.ligado = true, this.semJanelas = false});
  bool ligado;

  /// O servidor não dá janelas a esta loja (festas, offline, sem horário…).
  final bool semJanelas;

  @override
  Future<ConfigAgendar> config() async => ConfigAgendar(ligado: ligado);

  /// Faz de servidor: com o interruptor ligado, uma janela às 19:30 de cada dia.
  @override
  Future<List<JanelaAgendada>> janelas(String restaurantId, DateTime dia) async {
    if (!ligado || semJanelas) return const [];
    final ini = DateTime.utc(dia.year, dia.month, dia.day, 19, 30);
    return [JanelaAgendada(inicio: ini, fim: ini.add(const Duration(minutes: 30)))];
  }

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

Future<void> ligar(bool v, {bool semJanelas = false}) async {
  final e = AgendarPedidoEstado.instance;
  e.reporParaTeste(ApiFalsa(ligado: v, semJanelas: semJanelas));
  await e.carregarConfig(forcar: true);
}

/// O carrinho de uma loja, já com a resposta do servidor sobre as janelas
/// (o `configureSession` pergunta; aqui espera-se pela resposta).
Future<CartStore> carrinho({
  bool fechada = true,
  bool festas = false,
  bool parceira = true,
  OrderServiceType tipo = OrderServiceType.restaurant,
}) async {
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
  await AgendarPedidoEstado.instance.verificarLoja('boom');
  return c;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  tearDown(() => AgendarPedidoEstado.instance.reporParaTeste(ApiFalsa(ligado: false)));

  group('interruptor DESLIGADO: tudo como dantes', () {
    test('loja fechada não deixa adicionar e nada pede para agendar', () async {
      await ligar(false);
      final c = await carrinho();
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
      final c = await carrinho(fechada: false);
      c.addItem(item());
      expect(c.items, hasLength(1));
      expect(c.agendamentoEmFalta, isFalse);
    });
  });

  group('interruptor LIGADO', () {
    test('loja fechada deixa adicionar, e o cliente tem de escolher uma janela', () async {
      await ligar(true);
      final c = await carrinho();
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
      final c = await carrinho();
      AgendarPedidoEstado.instance.escolher('outra-loja', janela);
      expect(c.agendamentoEmFalta, isTrue);
    });

    test('loja aberta: agendar é opcional, nunca obrigatório', () async {
      await ligar(true);
      final c = await carrinho(fechada: false);
      expect(c.agendamentoDisponivel, isTrue);
      expect(c.agendamentoObrigatorio, isFalse);
      expect(c.agendamentoEmFalta, isFalse);
    });

    test('festas, takeaway e favores continuam como dantes', () async {
      await ligar(true);
      final festas = await carrinho(festas: true);
      festas.addItem(item());
      expect(festas.items, isEmpty);
      expect(festas.lojaFechada, isTrue);
      expect(festas.agendamentoDisponivel, isFalse);

      final takeaway = await carrinho(tipo: OrderServiceType.takeaway);
      expect(takeaway.lojaFechada, isTrue);
      expect(takeaway.agendamentoDisponivel, isFalse);

      final favor = await carrinho(tipo: OrderServiceType.errand);
      expect(favor.lojaFechada, isTrue);
      expect(favor.agendamentoDisponivel, isFalse);
    });

    test('30/10: mercado não parceiro com janelas no servidor também agenda', () async {
      await ligar(true);
      final mercado = await carrinho(parceira: false, tipo: OrderServiceType.storeShopping);
      expect(mercado.lojaFechada, isFalse, reason: 'loja fechada já não trava o mercado');
      expect(mercado.agendamentoDisponivel, isTrue);
      expect(mercado.agendamentoObrigatorio, isTrue);
      mercado.addItem(item());
      expect(mercado.items, hasLength(1));
    });

    test('30/10: loja (parceira ou não) sem janelas no servidor fica como dantes', () async {
      await ligar(true, semJanelas: true);
      final parceira = await carrinho();
      expect(parceira.lojaFechada, isTrue, reason: 'decide o servidor, não o isPartner');
      expect(parceira.agendamentoDisponivel, isFalse);
      final mercado = await carrinho(parceira: false, tipo: OrderServiceType.storeShopping);
      mercado.addItem(item());
      expect(mercado.items, isEmpty);
      expect(mercado.lojaFechada, isTrue);
      expect(mercado.agendamentoDisponivel, isFalse);
    });

    test('quando a configuração chega depois, o carrinho avisa os ecrãs', () async {
      AgendarPedidoEstado.instance.reporParaTeste(ApiFalsa(ligado: true));
      final c = CartStore();
      c.configureSession(
        serviceType: OrderServiceType.restaurant,
        vendorName: 'Boom! Burger',
        vendorRestaurantId: 'boom',
        vendorFechada: true,
      );
      var avisos = 0;
      c.addListener(() => avisos++);
      expect(c.lojaFechada, isTrue, reason: 'a configuração ainda não foi lida');
      await AgendarPedidoEstado.instance.carregarConfig(forcar: true);
      // A resposta das janelas chega a seguir à configuração.
      await AgendarPedidoEstado.instance.verificarLoja('boom');
      expect(c.lojaFechada, isFalse);
      expect(avisos, greaterThan(0));
    });
  });
}
