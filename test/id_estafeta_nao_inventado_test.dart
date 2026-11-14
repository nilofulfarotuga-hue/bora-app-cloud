// Missão fechar-app-15-11, Bloco 3b — a app deixou de inventar o id do
// estafeta. Antes, sem sessão, fazia `driver-<telefone>`; a 14/11 18:19 o
// telemóvel saiu das duas contas guardadas e ficou a pedir ofertas e pedidos
// por um id que não existe (o `user_id` é que manda em tudo o que o estafeta
// vê). Agora, sem id dado e sem sessão, fica a marca "sem estafeta", que o
// resto da app já trata como "não é um estafeta a sério".
import 'dart:io';

import 'package:bora_app/stores/driver_store.dart';
import 'package:flutter_test/flutter_test.dart';

const _uid = '4f61dd31-0000-4000-8000-000000000001';

void main() {
  test('com id dado, é esse', () {
    expect(
      DriverStore.resolverIdDoEstafeta(driverId: _uid, authUid: 'outro'),
      _uid,
    );
  });

  test('sem id dado, é o da sessão aberta', () {
    expect(DriverStore.resolverIdDoEstafeta(authUid: _uid), _uid);
    expect(DriverStore.resolverIdDoEstafeta(driverId: '', authUid: _uid), _uid);
  });

  test('sem id e sem sessão NÃO inventa: fica "sem estafeta"', () {
    for (final id in [
      DriverStore.resolverIdDoEstafeta(),
      DriverStore.resolverIdDoEstafeta(driverId: '', authUid: ''),
    ]) {
      expect(id, DriverStore.semEstafeta);
      expect(id, 'driver-main');
    }
  });

  test('pela fonte: o id feito do telemóvel saiu', () {
    final fonte = File('lib/stores/driver_store.dart').readAsStringSync();
    expect(fonte.contains(r"'driver-${"), isFalse);
    expect(fonte.contains('phone.replaceAll(RegExp('), isFalse);
    // E quem decide "é um estafeta a sério" continua a olhar para a mesma marca.
    final pedidos = File('lib/stores/order_store.dart').readAsStringSync();
    expect(pedidos.contains("newId != 'driver-main'"), isTrue);
  });
}
