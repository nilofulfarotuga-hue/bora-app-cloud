// O separador de baixo do cliente que reúne mesas, corridas marcadas, limpezas
// e marcações chama-se "Reservas" (plural) desde 21/10/2026 — antes dizia
// "Reserva", herdado do tempo em que só tinha as mesas (bloco A3 da
// super-missão fechar-pendencias-2026-10-20).
import 'package:bora_app/widgets/bora/bora_bottom_nav_v2.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('o separador das reservas chama-se "Reservas" (plural)',
      (t) async {
    await t.pumpWidget(MaterialApp(
      home: Scaffold(
        bottomNavigationBar: BoraBottomNavV2(
          current: BoraNavTab.home,
          onTabChanged: (_) {},
        ),
      ),
    ));
    expect(find.text('Reservas'), findsOneWidget);
    expect(find.text('Reserva'), findsNothing);
  });
}
