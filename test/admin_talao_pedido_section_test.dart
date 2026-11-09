// Talões guardados 10 anos (08/11/2026, missão m1-dinheiro-favores, adendo 1):
// no detalhe do pedido o painel mostra as fotos do talão, o valor escrito pelo
// entregador e o NIF usado; avisa "Sem talão" em pedido não-parceiro entregue
// sem foto e não desenha nada em loja parceira sem foto.
import 'package:bora_app/widgets/admin/admin_talao_pedido_section.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Widget _app(Widget w) => MaterialApp(home: Scaffold(body: SingleChildScrollView(child: w)));

Map<String, dynamic> _talao({
  Object? valor = 2995,
  Map<String, dynamic> nif = const {'nif': '292811111', 'origem': 'cliente'},
  List<Map<String, dynamic>> fotos = const [],
  String? fotoAtual,
}) =>
    {
      'ok': true,
      'valor_escrito_cents': valor,
      'foto_atual': fotoAtual,
      'nif': nif,
      'fotos': fotos,
    };

const _fotoNova = {
  'path': '2026/11/b72c4f2c-0000/f1.jpg',
  'bucket': 'receipts',
  'total_cents': 2995,
  'tirada_em': '2026-11-08T19:03:00Z',
  'recebida_em': '2026-11-08T19:05:00Z',
  'tamanho_bytes': 154000,
  'origem': 'upload-receipt',
  'copia_em': '2026-11-09T03:30:00Z',
};

const _fotoAntiga = {
  'path': 'b72c4f2c-0000.jpg',
  'bucket': 'receipts',
  'total_cents': 2995,
  'tirada_em': null,
  'recebida_em': '2026-10-20T12:00:00Z',
  'tamanho_bytes': null,
  'origem': 'antigo',
  'copia_em': null,
};

void main() {
  group('textos', () {
    test('NIF usado: cliente, Bora e loja parceira', () {
      expect(textoNifUsado({'nif': '292811111', 'origem': 'cliente'}),
          'NIF usado: 292811111 (pedido pelo cliente)');
      expect(textoNifUsado({'nif': '519686233', 'origem': 'bora'}),
          'NIF usado: 519686233 (NIF da Bora — cliente não pediu fatura)');
      expect(textoNifUsado({'nif': null, 'origem': 'bora'}), contains(kNifBora));
      expect(textoNifUsado({'nif': null, 'origem': 'loja_parceira'}), 'Loja parceira: fatura da loja');
      expect(textoNifUsado(null), 'NIF usado: —');
    });

    test('euros e quem precisa de talão', () {
      expect(eurosDoTalao(2995), '29,95 €');
      expect(eurosDoTalao(null), '—');
      expect(talaoPrecisa('storeShopping'), isTrue);
      expect(talaoPrecisa('restaurant'), isTrue);
      expect(talaoPrecisa('errand'), isFalse);
      expect(talaoPrecisa('errand', errandHasPurchase: true), isTrue);
      expect(talaoPrecisa('tvde'), isFalse);
    });

    test('caminho da foto leva o balde à frente', () {
      expect(caminhoDaFotoDoTalao(Map<String, dynamic>.from(_fotoNova)),
          'receipts/2026/11/b72c4f2c-0000/f1.jpg');
      expect(caminhoDaFotoDoTalao({'path': 'receipts/x.jpg'}), 'receipts/x.jpg');
    });
  });

  group('cartão no detalhe do pedido', () {
    testWidgets('NIF pedido pelo cliente, valor escrito, foto com cópia no Drive', (t) async {
      final pedidos = <String>[];
      await t.pumpWidget(_app(AdminTalaoPedidoSection(
        orderId: 'b72c4f2c-0000',
        status: 'delivered',
        serviceType: 'storeShopping',
        carregar: (id) async {
          pedidos.add(id);
          return _talao(fotos: [Map<String, dynamic>.from(_fotoNova)]);
        },
      )));
      await t.pump();
      await t.pump();
      expect(pedidos, ['b72c4f2c-0000']);
      expect(find.text('Talão (foto e NIF)'), findsOneWidget);
      expect(find.text('Valor escrito pelo entregador: 29,95 €'), findsOneWidget);
      expect(find.text('NIF usado: 292811111 (pedido pelo cliente)'), findsOneWidget);
      expect(find.byKey(const Key('talao_foto_0')), findsOneWidget);
      expect(find.text('cópia no Drive ✓'), findsOneWidget);
      expect(find.text('antigo'), findsNothing);
      expect(find.byKey(const Key('talao_sem_talao')), findsNothing);
    });

    testWidgets('NIF da Bora e foto antiga com selo "antigo"', (t) async {
      await t.pumpWidget(_app(AdminTalaoPedidoSection(
        orderId: 'b72c4f2c-0000',
        status: 'delivered',
        serviceType: 'restaurant',
        carregar: (_) async => _talao(
          nif: const {'nif': '519686233', 'origem': 'bora'},
          fotos: [Map<String, dynamic>.from(_fotoNova), Map<String, dynamic>.from(_fotoAntiga)],
        ),
      )));
      await t.pump();
      await t.pump();
      expect(find.text('NIF usado: 519686233 (NIF da Bora — cliente não pediu fatura)'), findsOneWidget);
      expect(find.byKey(const Key('talao_foto_1')), findsOneWidget);
      expect(find.text('antigo'), findsOneWidget);
      expect(find.textContaining('2 fotos'), findsOneWidget);
    });

    testWidgets('não-parceiro entregue sem foto: aviso "Sem talão"', (t) async {
      await t.pumpWidget(_app(AdminTalaoPedidoSection(
        orderId: 'b72c4f2c-0000',
        status: 'delivered',
        serviceType: 'storeShopping',
        carregar: (_) async => _talao(valor: null, nif: const {'nif': '519686233', 'origem': 'bora'}),
      )));
      await t.pump();
      await t.pump();
      expect(find.byKey(const Key('admin_talao_pedido')), findsOneWidget);
      expect(find.byKey(const Key('talao_sem_talao')), findsOneWidget);
      expect(find.text('Sem talão'), findsOneWidget);
      expect(find.textContaining('ainda não escrito'), findsOneWidget);
    });

    testWidgets('em curso sem foto: sem aviso, diz que ainda não há foto', (t) async {
      await t.pumpWidget(_app(AdminTalaoPedidoSection(
        orderId: 'b72c4f2c-0000',
        status: 'onTheWay',
        serviceType: 'storeShopping',
        carregar: (_) async => _talao(valor: null),
      )));
      await t.pump();
      await t.pump();
      expect(find.byKey(const Key('talao_sem_talao')), findsNothing);
      expect(find.textContaining('Ainda sem foto do talão'), findsOneWidget);
    });

    testWidgets('loja parceira sem foto: não desenha nada', (t) async {
      await t.pumpWidget(_app(AdminTalaoPedidoSection(
        orderId: 'b72c4f2c-0000',
        status: 'delivered',
        serviceType: 'restaurant',
        carregar: (_) async => _talao(valor: null, nif: const {'nif': null, 'origem': 'loja_parceira'}),
      )));
      await t.pump();
      await t.pump();
      expect(find.byKey(const Key('admin_talao_pedido')), findsNothing);
    });

    testWidgets('Favor sem compra e sem foto: não desenha nada', (t) async {
      await t.pumpWidget(_app(AdminTalaoPedidoSection(
        orderId: 'b72c4f2c-0000',
        status: 'delivered',
        serviceType: 'errand',
        carregar: (_) async => _talao(valor: null, nif: const {'nif': '519686233', 'origem': 'bora'}),
      )));
      await t.pump();
      await t.pump();
      expect(find.byKey(const Key('admin_talao_pedido')), findsNothing);
    });

    testWidgets('servidor sem a função: mensagem gentil', (t) async {
      await t.pumpWidget(_app(AdminTalaoPedidoSection(
        orderId: 'b72c4f2c-0000',
        status: 'delivered',
        serviceType: 'storeShopping',
        carregar: (_) async =>
            throw Exception('PGRST202 Could not find the function public.admin_talao_do_pedido'),
      )));
      await t.pump();
      await t.pump();
      expect(find.textContaining(kTalaoFuncaoNaoPublicada), findsOneWidget);
    });
  });
}
