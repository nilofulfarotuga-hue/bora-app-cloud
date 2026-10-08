// Cartão "para onde vou" do Favor e o visualizador de fotos em ecrã inteiro
// (08/10/2026, pedido real 74dd4ecc e pedido do Danilo).
import 'dart:convert';

import 'package:bora_app/models/order_model.dart';
import 'package:bora_app/widgets/bora_foto_ecra_inteiro.dart';
import 'package:bora_app/widgets/favor_passos_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';

OrderModel _favor({int? passo, bool finalizado = false, String? foto}) {
  return OrderModel(
    id: 'teste-favor',
    total: 12.00,
    serviceType: OrderServiceType.errand,
    status: OrderStatus.driverAccepted,
    paymentMethod: PaymentMethod.cash,
    customerName: 'Cristina',
    errandDescription: 'Vai à farmácia e compra castillium 10mg',
    errandLocation: 'Farmácia Tavares, Avenida Cidade de Safed, Guarda',
    errandLocationLat: 40.542,
    errandLocationLng: -7.256,
    errandHomeStop: true,
    errandHomeStopReason: 'receita',
    errandHomeStopCashCents: 2000,
    errandPasso: passo,
    errandHasPurchase: true,
    isPurchaseFinalized: finalizado,
    finalTotal: finalizado ? 9.88 : null,
    errandRequestPhotoUrl: foto,
    pickupAddress: 'Rua do Ferrinho, Guarda',
    dropoffAddress: 'Rua Pedro Álvares Cabral 31, Guarda',
    destination: const LatLng(40.537, -7.268),
  );
}

Widget _app(Widget filho) => MaterialApp(
      home: Scaffold(body: SingleChildScrollView(child: filho)),
    );

// PNG 1×1 (para o visualizador sem rede).
final _png = base64Decode(
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg==');

void main() {
  testWidgets('passo 1: casa da cliente, motivo e dinheiro a receber',
      (tester) async {
    await tester.pumpWidget(_app(FavorPassosCard(
      order: _favor(passo: 0),
      posicaoEstafeta: const LatLng(40.530, -7.290),
    )));
    expect(find.text('PASSO 1 DE 3'), findsOneWidget);
    expect(find.text('Casa da cliente — Cristina'), findsOneWidget);
    expect(find.text('Rua Pedro Álvares Cabral 31, Guarda'), findsOneWidget);
    expect(find.text('Motivo: Buscar a receita médica'), findsOneWidget);
    expect(find.text('Recebe €20.00 em dinheiro da cliente'), findsOneWidget);
    expect(find.textContaining('de ti'), findsOneWidget);
    expect(find.textContaining('Ferrinho'), findsNothing);
    expect(find.byKey(const Key('btn_navegar_passo')), findsOneWidget);
  });

  testWidgets('passo 2 farmácia: foto grande e o que mostrar ao balcão',
      (tester) async {
    await tester.pumpWidget(_app(FavorPassosCard(
      order: _favor(passo: 1, foto: 'https://exemplo.invalido/receita.jpg'),
    )));
    expect(find.text('PASSO 2 DE 3'), findsOneWidget);
    expect(find.text('Farmácia Tavares'), findsWidgets);
    expect(
        find.text(
            'Mostra esta foto na farmácia: número da receita e código de acesso e dispensa.'),
        findsOneWidget);
    expect(
        find.text(
            'Alguns medicamentos controlados podem pedir o teu cartão de cidadão.'),
        findsOneWidget);
    expect(find.byKey(const Key('favor_foto_receita')), findsOneWidget);
  });

  testWidgets('farmácia sem foto: aviso para ligar à cliente', (tester) async {
    await tester.pumpWidget(_app(FavorPassosCard(order: _favor(passo: 1))));
    expect(find.textContaining('não mandou foto da receita'), findsOneWidget);
  });

  testWidgets('passo 3: cobrar o valor do talão (9,88), não o estimado (12)',
      (tester) async {
    await tester.pumpWidget(
        _app(FavorPassosCard(order: _favor(passo: 2, finalizado: true))));
    expect(find.text('PASSO 3 DE 3'), findsOneWidget);
    expect(find.text('Cobrar à cliente: €9.88'), findsOneWidget);
    expect(find.textContaining('12.00'), findsNothing);
  });

  testWidgets('oferta (compacto): a rota toda antes de aceitar', (tester) async {
    await tester.pumpWidget(
        _app(FavorPassosCard(order: _favor(), compacto: true)));
    expect(find.text('Casa da cliente → Farmácia Tavares → Casa da cliente'),
        findsOneWidget);
    expect(find.text('Casa da cliente — Cristina'), findsOneWidget);
    expect(find.text('Farmácia Tavares'), findsOneWidget);
    expect(find.text('Entrega à cliente — Cristina'), findsOneWidget);
    expect(find.byKey(const Key('btn_tratar_favor')), findsNothing);
  });

  testWidgets('foto em ecrã inteiro: fundo preto, zoom até 5x, fechar',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Builder(
        builder: (ctx) => Scaffold(
          body: Center(
            child: TextButton(
              onPressed: () => BoraFotoEcraInteiro.abrir(ctx,
                  imagem: MemoryImage(_png), titulo: 'Foto da receita'),
              child: const Text('abrir'),
            ),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('abrir'));
    await tester.pumpAndSettle();
    final viewer =
        tester.widget<InteractiveViewer>(find.byType(InteractiveViewer));
    expect(viewer.maxScale, 5);
    expect(viewer.minScale, 1);
    final img = tester.widget<Image>(find.byType(Image));
    expect(img.fit, BoxFit.contain);
    expect(find.text('Foto da receita'), findsOneWidget);
    // dois toques amplia
    await tester.tap(find.byType(InteractiveViewer));
    await tester.pump(const Duration(milliseconds: 50));
    await tester.tap(find.byType(InteractiveViewer));
    await tester.pumpAndSettle();
    expect(viewer.transformationController!.value.getMaxScaleOnAxis(),
        greaterThan(1.5));
    await tester.tap(find.byKey(const Key('bora_foto_fechar')));
    await tester.pumpAndSettle();
    expect(find.byType(InteractiveViewer), findsNothing);
  });
}
