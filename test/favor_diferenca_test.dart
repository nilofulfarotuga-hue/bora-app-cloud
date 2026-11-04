// Favor com a compra acima do orçado, pago por MB Way (04/11/2026, missão
// favor-diferenca-mbway-2026-11-03): o cliente vê o que falta e reenvia o MB
// Way quando expirou; o painel lista as diferenças e fecha a entrega sem
// código com motivo.
import 'package:bora_app/models/order_model.dart';
import 'package:bora_app/screens/admin/admin_favor_diferencas_screen.dart';
import 'package:bora_app/widgets/admin/admin_entregue_sem_codigo_button.dart';
import 'package:bora_app/widgets/favor_diferenca_banner.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

OrderModel _favor({PaymentMethod meio = PaymentMethod.mbway, OrderStatus estado = OrderStatus.onTheWay}) =>
    OrderModel(
      id: 'b72c4f2c-0000-4000-8000-000000000000',
      total: 13.21,
      serviceType: OrderServiceType.errand,
      status: estado,
      paymentMethod: meio,
      createdAt: DateTime.utc(2026, 11, 3, 12),
    );

Widget _app(Widget w) => MaterialApp(home: Scaffold(body: SingleChildScrollView(child: w)));

void main() {
  final agora = DateTime.utc(2026, 11, 4, 15);

  group('cliente: Pagar a diferença', () {
    testWidgets('expirou: mostra o valor e o botão; carregar pede um MB Way novo', (t) async {
      var pedidos = 0;
      await t.pumpWidget(_app(FavorDiferencaBanner(
        order: _favor(),
        agora: () => agora,
        ler: (_) async => FavorDiferenca(estado: 'expirou', valorCents: 1077, criadoEm: agora),
        pagar: (_) async {
          pedidos++;
          return {'ok': true, 'tentativa': 101};
        },
      )));
      await t.pump();
      expect(find.textContaining('10,77 €'), findsOneWidget);
      await t.tap(find.byKey(const Key('btn_pagar_diferenca')));
      await t.pump();
      await t.pump();
      expect(pedidos, 1);
      expect(find.textContaining('poucos minutos'), findsWidgets);
    });

    testWidgets('pedido vivo (< 5 min): diz para aprovar, sem botão', (t) async {
      await t.pumpWidget(_app(FavorDiferencaBanner(
        order: _favor(),
        agora: () => agora,
        ler: (_) async => FavorDiferenca(
            estado: 'pedido', valorCents: 1077, criadoEm: agora.subtract(const Duration(minutes: 2))),
      )));
      await t.pump();
      expect(find.byKey(const Key('favor_diferenca_banner')), findsOneWidget);
      expect(find.byKey(const Key('btn_pagar_diferenca')), findsNothing);
    });

    testWidgets('pedido sem resposta há 5 min conta como expirado', (t) async {
      await t.pumpWidget(_app(FavorDiferencaBanner(
        order: _favor(),
        agora: () => agora,
        ler: (_) async => FavorDiferenca(
            estado: 'pedido', valorCents: 1077, criadoEm: agora.subtract(const Duration(minutes: 6))),
      )));
      await t.pump();
      expect(find.byKey(const Key('btn_pagar_diferenca')), findsOneWidget);
    });

    testWidgets('pago, dinheiro ou sem a tabela no servidor: nada', (t) async {
      await t.pumpWidget(_app(Column(children: [
        FavorDiferencaBanner(
            order: _favor(), ler: (_) async => FavorDiferenca(estado: 'pago', valorCents: 1077, criadoEm: agora)),
        FavorDiferencaBanner(
            order: _favor(meio: PaymentMethod.cash),
            ler: (_) async => FavorDiferenca(estado: 'expirou', valorCents: 1077, criadoEm: agora)),
        FavorDiferencaBanner(order: _favor(), ler: (_) async => throw Exception('relation does not exist')),
      ])));
      await t.pump();
      expect(find.byKey(const Key('favor_diferenca_banner')), findsNothing);
    });
  });

  group('painel: Diferenças de Favor', () {
    testWidgets('lista com estado em PT-BR e reenvia', (t) async {
      final reenviados = <String>[];
      await t.pumpWidget(MaterialApp(
        home: AdminFavorDiferencasScreen(
          listar: () async => [
            {
              'pedido_id': 'b72c4f2c-aaaa',
              'cliente': 'Cliente Demo',
              'status': 'onTheWay',
              'criado_em': '2026-11-03T12:00:00Z',
              'payment_method': 'mbway',
              'devido_cents': 1077,
              'estado': 'expirou',
              'tentativas': 1,
            }
          ],
          reenviar: (id) async {
            reenviados.add(id);
            return {'ok': true, 'tentativa': 101};
          },
        ),
      ));
      await t.pump();
      expect(find.textContaining('€10.77'), findsOneWidget);
      expect(find.textContaining('Expirou'), findsOneWidget);
      await t.tap(find.byKey(const Key('reenviar_b72c4f2c-aaaa')));
      await t.pump();
      await t.pump();
      expect(reenviados, ['b72c4f2c-aaaa']);
    });
  });

  group('painel: Marcar entregue sem código', () {
    testWidgets('só aparece a caminho', (t) async {
      await t.pumpWidget(_app(AdminEntregueSemCodigoButton(orderId: 'x', status: 'pickedUp', onDone: () {})));
      expect(find.byKey(const Key('btn_entregue_sem_codigo')), findsNothing);
    });

    testWidgets('motivo curto não chama o servidor; com motivo fecha', (t) async {
      final chamadas = <String>[];
      var feito = 0;
      await t.pumpWidget(_app(AdminEntregueSemCodigoButton(
        orderId: 'x',
        status: 'onTheWay',
        onDone: () => feito++,
        marcar: (id, motivo) async {
          chamadas.add(motivo);
          return {'ok': true};
        },
      )));
      await t.tap(find.byKey(const Key('btn_entregue_sem_codigo')));
      await t.pumpAndSettle();
      await t.enterText(find.byKey(const Key('motivo_sem_codigo')), 'ok');
      await t.tap(find.byKey(const Key('confirmar_sem_codigo')));
      await t.pumpAndSettle();
      expect(chamadas, isEmpty);

      await t.tap(find.byKey(const Key('btn_entregue_sem_codigo')));
      await t.pumpAndSettle();
      await t.enterText(find.byKey(const Key('motivo_sem_codigo')), 'Estafeta esqueceu o PIN; cliente confirmou');
      await t.tap(find.byKey(const Key('confirmar_sem_codigo')));
      await t.pumpAndSettle();
      expect(chamadas, ['Estafeta esqueceu o PIN; cliente confirmou']);
      expect(feito, 1);
    });

    test('mensagens', () {
      expect(AdminEntregueSemCodigoButton.mensagem({'ok': false, 'error': 'motivo_obrigatorio'}),
          contains('motivo'));
      expect(AdminEntregueSemCodigoButton.mensagem({'ok': false, 'error': 'estado_invalido', 'status': 'pickedUp'}),
          contains('pickedUp'));
    });
  });
}
