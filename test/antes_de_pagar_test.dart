import 'dart:io';

import 'package:bora_app/stores/cart_store.dart';
import 'package:flutter_test/flutter_test.dart';

/// [melhorias-paridade 26/10, item 5] Antes de pagar: "Entregar em: … ·
/// Trocar", a nota visível no carrinho, e o painel vê se a morada foi trocada
/// no fim (Glovo e Uber mostram a morada no último ecrã; o Bora não mostrava).
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('trocar e escolher outra morada fica marcado; voltar à mesma esquece', () {
    final c = CartStore()
      ..updateDeliveryAddress(street: 'Rua A 1', city: 'Guarda', postalCode: '6300');
    c.marcarTrocaDeMorada(antes: c.dropoffStreet);
    c.updateDeliveryAddress(street: 'Rua B 2', city: 'Guarda', postalCode: '6300');
    c.confirmarTrocaDeMorada();
    expect(c.moradaAntesDaTroca, 'Rua A 1');

    final d = CartStore()
      ..updateDeliveryAddress(street: 'Rua A 1', city: 'Guarda', postalCode: '6300');
    d.marcarTrocaDeMorada(antes: d.dropoffStreet);
    d.confirmarTrocaDeMorada(); // abriu o seletor e não mudou
    expect(d.moradaAntesDaTroca, isNull);
  });

  test('a nota do carrinho é a mesma do pagamento e limpa com o carrinho', () {
    final c = CartStore()..setNotaCliente('sem cebola');
    expect(c.notaCliente, 'sem cebola');
    c.clearCart();
    expect(c.notaCliente, '');
    expect(c.moradaAntesDaTroca, isNull);
  });

  test('ecrãs: Entregar em · Trocar, nota no carrinho, painel e RPC dedicada', () {
    String ler(String p) => File(p).readAsStringSync();
    final pag = ler('lib/screens/payment_method_screen.dart');
    expect(pag.contains("'Entregar em'.tr"), isTrue);
    expect(pag.contains('abrirSeletorDeMorada(context)'), isTrue);
    expect(pag.contains('registarMoradaTrocada(orderId)'), isTrue);
    expect(pag.contains('notes: _orderNote'), isTrue,
        reason: 'a nota também segue no cartão');
    expect(ler('lib/stores/cart_store.dart').contains('customerNotes: notes,'), isTrue);
    expect(pag.contains('await cartStore.refreshRouteDistance();'), isTrue);
    expect(pag.contains('cartStore.registarMoradaTrocadaRascunho(draftId)'), isTrue,
        reason: 'adendo C: a marca segue no timeout do cartão');
    expect(ler('lib/screens/cart_screen.dart').contains('CustomerNoteField('), isTrue);
    expect(ler('lib/stores/cart_store.dart').contains('await registarMoradaTrocada(newOrderId);'),
        isTrue);
    expect(ler('lib/screens/admin/admin_order_detail_screen.dart')
        .contains("'Endereço trocado no final do pedido'"), isTrue);
    final m = ler('supabase/migrations/20261026091000_pedido_morada_trocada.sql');
    expect(m.contains('o.user_id::text = auth.uid()::text'), isTrue,
        reason: 'só o dono do pedido marca a troca');
    expect(m.contains('revoke all on function public.pedido_marcar_morada_trocada(text, text) from public, anon'),
        isTrue);
  });
}
