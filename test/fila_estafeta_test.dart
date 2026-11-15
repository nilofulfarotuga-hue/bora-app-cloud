// Fila do estafeta (adenda 1 do Danilo, 14/11/2026). Os mesmos cenários estão
// provados no gémeo do servidor (public.fila_do_estafeta) em
// supabase/tests/compra_guardada_fila_prova.mjs.

import 'package:bora_app/models/order_model.dart';
import 'package:bora_app/services/fila_estafeta.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

OrderModel pedido(
  String id, {
  String tipo = 'storeShopping',
  String status = 'driverAccepted',
  String? aceite,
  String? velocidade,
  String? loja,
}) =>
    OrderModel.fromSupabase({
      'id': id,
      'status': status,
      'service_type': tipo,
      'payment_method': 'cash',
      'price': 10,
      'items': const [],
      'created_at': '2026-11-14T10:00:00Z',
      if (aceite != null) 'driver_assigned_at': '2026-11-14T$aceite:00Z',
      if (velocidade != null) 'errand_speed': velocidade,
      if (loja != null) 'restaurant_id': loja,
      'vendor_name': id,
    });

List<String> ids(List<OrderModel> l) => l.map((o) => o.id).toList();

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    FilaEstafeta.limparParaTeste();
  });

  test('o caso de 14/11: Auchan a meio da compra + Favor aceite por cima', () {
    final meus = [
      pedido('favor', tipo: 'errand', velocidade: 'normal', aceite: '16:32'),
      pedido('auchan', aceite: '14:52', loja: 'auchan-guarda'),
    ];
    for (final f in [
      FilaEstafeta.calcular(meus, emCursoId: 'auchan'),
      FilaEstafeta.calcular(meus), // sem servidor: a regra de recurso dá o mesmo
    ]) {
      expect(ids(f.ativos), ['auchan']);
      expect(ids(f.emEspera), ['favor']);
    }
  });

  test('entregou o Auchan: o Favor passa a ativo', () {
    final f = FilaEstafeta.calcular([
      pedido('favor', tipo: 'errand', velocidade: 'normal', aceite: '16:32'),
      pedido('auchan', status: 'delivered', aceite: '14:52'),
    ], emCursoId: 'auchan');
    expect(ids(f.ativos), ['favor']);
    expect(f.emEspera, isEmpty);
  });

  test('Favor urgente fica logo a seguir ao em curso, nunca por cima', () {
    final meus = [
      pedido('atual', aceite: '10:00', loja: 'a'),
      pedido('entrega', tipo: 'restaurant', aceite: '10:05', loja: 'b'),
      pedido('favorNormal', tipo: 'errand', velocidade: 'normal', aceite: '10:01'),
      pedido('favorUrgente', tipo: 'errand', velocidade: 'express', aceite: '10:10'),
    ];
    final f = FilaEstafeta.calcular(meus, emCursoId: 'atual');
    expect(ids(f.ativos), ['atual']);
    expect(ids(f.emEspera), ['favorUrgente', 'entrega', 'favorNormal']);
  });

  test('entregou o em curso: abre o urgente, depois entrega, Favor normal no fim', () {
    final f = FilaEstafeta.calcular([
      pedido('atual', status: 'delivered', aceite: '10:00', loja: 'a'),
      pedido('entrega', tipo: 'restaurant', aceite: '10:05', loja: 'b'),
      pedido('favorNormal', tipo: 'errand', velocidade: 'normal', aceite: '10:01'),
      pedido('favorUrgente', tipo: 'errand', velocidade: 'express', aceite: '10:10'),
    ], emCursoId: 'atual');
    expect(ids(f.ativos), ['favorUrgente']);
    expect(ids(f.emEspera), ['entrega', 'favorNormal']);
  });

  test('Favor já em curso: a entrega aceite depois espera por ele', () {
    final f = FilaEstafeta.calcular([
      pedido('favor', tipo: 'errand', velocidade: 'normal', aceite: '08:00'),
      pedido('entrega', tipo: 'restaurant', aceite: '08:30', loja: 'x'),
    ], emCursoId: 'favor');
    expect(ids(f.ativos), ['favor']);
    expect(ids(f.emEspera), ['entrega']);
  });

  test('entregas em espera pela ordem de aceitação', () {
    final f = FilaEstafeta.calcular([
      pedido('atual', aceite: '10:00', loja: 'a'),
      pedido('d2', tipo: 'restaurant', aceite: '10:20', loja: 'c'),
      pedido('d1', tipo: 'sendPackage', aceite: '10:10'),
    ], emCursoId: 'atual');
    expect(ids(f.emEspera), ['d1', 'd2']);
  });

  test('mesma loja segue junta (agrupamento que já existia)', () {
    final f = FilaEstafeta.calcular([
      pedido('mc1', tipo: 'restaurant', aceite: '12:00', loja: 'mcd'),
      pedido('mc2', tipo: 'restaurant', aceite: '12:03', loja: 'mcd'),
      pedido('outra', tipo: 'restaurant', aceite: '12:01', loja: 'kfc'),
    ], emCursoId: 'mc1');
    expect(ids(f.ativos), ['mc1', 'mc2']);
    expect(ids(f.emEspera), ['outra']);
  });

  test('entregou um da volta: o outro da mesma loja continua antes da fila', () {
    final f = FilaEstafeta.calcular([
      pedido('urgente', tipo: 'errand', velocidade: 'express', aceite: '12:02'),
      pedido('mc2', tipo: 'restaurant', aceite: '12:03', loja: 'mcd'),
    ], emCursoId: 'mc1', lojaAnterior: 'mcd');
    expect(ids(f.ativos), ['mc2']);
    expect(ids(f.emEspera), ['urgente']);
  });

  test('o que já foi recolhido nunca se esconde', () {
    final f = FilaEstafeta.calcular([
      pedido('primeiro', aceite: '09:00', loja: 'a'),
      pedido('recolhido', tipo: 'restaurant', status: 'pickedUp', aceite: '09:30', loja: 'b'),
    ], emCursoId: 'primeiro');
    expect(ids(f.ativos), ['primeiro', 'recolhido']);
    expect(f.emEspera, isEmpty);
  });

  test('sem em curso conhecido: o recolhido passa a em curso', () {
    final f = FilaEstafeta.calcular([
      pedido('primeiro', aceite: '09:00', loja: 'a'),
      pedido('recolhido', tipo: 'restaurant', status: 'pickedUp', aceite: '09:30', loja: 'b'),
    ]);
    expect(ids(f.ativos), ['recolhido']);
    expect(ids(f.emEspera), ['primeiro']);
  });

  test('app reiniciada sem servidor: a compra começada continua em curso', () {
    final f = FilaEstafeta.calcular([
      pedido('auchan', aceite: '14:52', loja: 'auchan-guarda'),
      pedido('urgente', tipo: 'errand', velocidade: 'express', aceite: '15:00'),
    ], compraComecada: (id) => id == 'auchan');
    expect(ids(f.ativos), ['auchan']);
    expect(ids(f.emEspera), ['urgente']);
  });

  test('pedido sem loja não passa à frente do urgente', () {
    final f = FilaEstafeta.calcular([
      pedido('encomenda', tipo: 'sendPackage', aceite: '09:05'),
      pedido('urgente', tipo: 'errand', velocidade: 'express', aceite: '09:10'),
    ], emCursoId: 'kfc-entregue', lojaAnterior: 'kfc');
    expect(ids(f.ativos), ['urgente']);
    expect(ids(f.emEspera), ['encomenda']);
  });

  test('o telemóvel lembra-se do em curso entre desenhos', () {
    final favor = pedido('favor', tipo: 'errand', velocidade: 'normal', aceite: '08:00');
    expect(ids(FilaEstafeta.doEstafeta([favor]).ativos), ['favor']);
    // aceitou uma entrega por cima: o Favor continua em curso
    final f = FilaEstafeta.doEstafeta(
        [favor, pedido('entrega', tipo: 'restaurant', aceite: '08:30', loja: 'x')]);
    expect(ids(f.ativos), ['favor']);
    expect(ids(f.emEspera), ['entrega']);
  });

  test('um só pedido = sem fila; nenhum = vazio', () {
    final f = FilaEstafeta.calcular([pedido('so')]);
    expect(ids(f.ativos), ['so']);
    expect(f.emEspera, isEmpty);
    expect(FilaEstafeta.calcular(const []).ativos, isEmpty);
  });
}
