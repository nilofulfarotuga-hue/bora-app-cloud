// noite-farmacia-17-11 (3.1): a janela do MB WAY do pedido espera 4 minutos, o botão
// voltar do Android não a fecha sem perguntar e só fecha como pago quando o pedido fica pago.
// Pedido 1006af87 (16/11 14:03): a janela fechou 33 s depois do envio, o pedido foi cancelado
// e o cliente pagou às 14:04:47.
import 'package:bora_app/widgets/mbway_espera_pedido_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class _Resultado {
  bool? valor;
  bool fechou = false;
}

Future<_Resultado> _abrir(WidgetTester t, {required Future<String?> Function(String) ler, int segundos = 240}) async {
  final r = _Resultado();
  await t.pumpWidget(MaterialApp(
    home: Builder(
      builder: (ctx) => Scaffold(
        body: Center(
          child: ElevatedButton(
            onPressed: () async {
              r.valor = await showDialog<bool>(
                context: ctx,
                barrierDismissible: false,
                builder: (_) => MbwayEsperaPedidoDialog(
                  orderId: 'pedido-teste',
                  amount: 12.5,
                  segundos: segundos,
                  lerEstadoPagamento: ler,
                ),
              );
              r.fechou = true;
            },
            child: const Text('pagar'),
          ),
        ),
      ),
    ),
  ));
  await t.tap(find.text('pagar'));
  await t.pump();
  return r;
}

void main() {
  test('espera 4 minutos (o MB WAY leva ~4 min a chegar)', () {
    expect(mbwayEsperaPedidoSegundos, 240);
  });

  testWidgets('botão voltar não fecha: pergunta; "Continuar à espera" mantém a janela', (t) async {
    final r = await _abrir(t, ler: (_) async => 'pending');
    expect(find.textContaining('240 s'), findsOneWidget);
    await t.binding.handlePopRoute(); // botão voltar do Android
    await t.pump();
    expect(find.byKey(const Key('mbway_cancelar_confirmar')), findsOneWidget);
    await t.tap(find.byKey(const Key('mbway_continuar_espera')));
    await t.pump();
    expect(r.fechou, isFalse);
    expect(find.byKey(const Key('mbway_segundos')), findsOneWidget);
    await t.pump(const Duration(seconds: 5));
    expect(find.textContaining('235 s'), findsOneWidget);
    // fecha o teste sem deixar temporizadores: cancela de verdade
    await t.tap(find.byKey(const Key('mbway_cancelar')));
    await t.pump();
    await t.tap(find.byKey(const Key('mbway_cancelar_sim')));
    await t.pumpAndSettle();
    expect(r.fechou, isTrue);
    expect(r.valor, isFalse);
    await t.pump(const Duration(seconds: 5)); // deixa acabar os temporizadores
  });

  testWidgets('pedido fica pago → fecha como pago, mesmo com a pergunta aberta', (t) async {
    var estado = 'pending';
    final r = await _abrir(t, ler: (_) async => estado);
    await t.tap(find.byKey(const Key('mbway_cancelar')));
    await t.pump();
    expect(find.byKey(const Key('mbway_cancelar_confirmar')), findsOneWidget);
    estado = 'paid';
    await t.pump(const Duration(seconds: 4));
    await t.pumpAndSettle();
    expect(r.fechou, isTrue);
    expect(r.valor, isTrue);
    expect(find.byKey(const Key('mbway_cancelar_confirmar')), findsNothing);
    await t.pump(const Duration(seconds: 5));
  });

  testWidgets('o tempo acaba → fecha sem pago', (t) async {
    final r = await _abrir(t, ler: (_) async => 'pending', segundos: 3);
    await t.pump(const Duration(seconds: 4));
    await t.pumpAndSettle();
    expect(r.fechou, isTrue);
    expect(r.valor, isFalse);
    await t.pump(const Duration(seconds: 5));
  });
}
