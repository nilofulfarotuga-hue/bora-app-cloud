// M10 b2-nif (09/11/2026) — NIF na caixa, lado do estafeta.
// Ordem do Danilo (04/11, caso do pedido do Auchan: o estafeta nunca viu o NIF
// que o cliente pediu) e regra de 08/11 ("Não pode esquecer do NIF").
//  - cartão laranja "NIF PARA A FATURA" com o número em grande e "Copiar";
//  - caixa "Dei este NIF na caixa e está no talão" OU "Não consegui" com motivo
//    ANTES de finalizar a compra (folha do talão e folha do Favor);
//  - a resposta sobe em segundo plano (3 tentativas) e NUNCA trava a entrega;
//  - sem rede / loja parceira: nada aparece e nada trava.
import 'dart:async';
import 'dart:convert';
import 'dart:io' as io;

import 'package:bora_app/screens/driver_map_screen.dart';
import 'package:bora_app/widgets/driver_invoice_nif_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

const _canalCamara = MethodChannel('plugins.flutter.io/image_picker');
final _png = base64Decode(
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg==');

Map<String, dynamic> _bora({Map<String, dynamic>? confirmado}) => {
      'ok': true,
      'mostrar': true,
      'pediu_fatura': false,
      'tipo': 'bora',
      'nif': '519686233',
      'confirmado': confirmado,
    };

Map<String, dynamic> _cliente({Map<String, dynamic>? confirmado}) => {
      'ok': true,
      'mostrar': true,
      'pediu_fatura': true,
      'tipo': 'cliente',
      'nif': '265148502',
      'nome': 'Ana Teste',
      'confirmado': confirmado,
    };

NifRpc _responde(Object? r) => (f, p) async {
      expect(f, 'driver_order_invoice_nif');
      expect(p, {'p_order_id': 'p1'});
      return r;
    };

Widget _cartao(NifRpc rpc, {NifCaixaController? caixa}) => MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(
          child: DriverInvoiceNifCard(orderId: 'p1', rpc: rpc, caixa: caixa),
        ),
      ),
    );

void main() {
  final rpcOriginal = NifCaixaEnvio.rpc;
  final esperaOriginal = NifCaixaEnvio.espera;
  setUp(() => NifCaixaEnvio.espera = (_) => Duration.zero);
  tearDown(() {
    NifCaixaEnvio.rpc = rpcOriginal;
    NifCaixaEnvio.espera = esperaOriginal;
  });

  group('Cartão "NIF PARA A FATURA"', () {
    // Regra de 10/11/2026 (Danilo, fechada com o contabilista): sem NIF do
    // cliente o talão é consumidor final e o NIF da Bora nunca vai na caixa.
    // Mesmo que um servidor antigo devolva o da Bora, o cartão não aparece e a
    // caixa não obriga a responder.
    testWidgets('servidor antigo com o NIF da Bora: nem cartão nem caixa obrigatória',
        (t) async {
      final caixa = NifCaixaController();
      await t.pumpWidget(_cartao(_responde(_bora()), caixa: caixa));
      await t.pumpAndSettle();
      expect(find.byKey(const Key('driver_invoice_nif_card')), findsNothing);
      expect(find.text('519 686 233'), findsNothing);
      expect(find.textContaining('Da Bora'), findsNothing);
      expect(find.byKey(const Key('nif_caixa_dei')), findsNothing);
      expect(caixa.aplica, isFalse);
      expect(caixa.porResponder, isFalse);
    });

    testWidgets('cartão do cliente: laranja Bora, só informação sem controlador',
        (t) async {
      await t.pumpWidget(_cartao(_responde(_cliente())));
      await t.pumpAndSettle();
      expect(find.text('NIF PARA A FATURA'), findsOneWidget);
      expect(find.text('Diz este NIF na caixa ANTES de pagar.'), findsOneWidget);
      expect(find.byKey(const Key('nif_caixa_dei')), findsNothing);
      final caixa = t.widget<Container>(
          find.byKey(const Key('driver_invoice_nif_card')));
      final borda = (caixa.decoration! as BoxDecoration).border! as Border;
      expect(borda.top.color, const Color(0xFFF97316), reason: 'laranja Bora');
    });

    testWidgets('cliente pediu fatura: o NIF dele, o nome e Copiar só dígitos',
        (t) async {
      final copias = <String>[];
      t.binding.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, (call) async {
        if (call.method == 'Clipboard.setData') {
          copias.add((call.arguments as Map)['text'] as String);
        }
        return null;
      });
      addTearDown(() => t.binding.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, null));

      await t.pumpWidget(_cartao(_responde(_cliente())));
      await t.pumpAndSettle();
      expect(find.text('265 148 502'), findsOneWidget);
      expect(find.text('Do cliente — pediu fatura'), findsOneWidget);
      expect(find.text('Nome na fatura: Ana Teste'), findsOneWidget);

      await t.tap(find.byKey(const Key('nif_caixa_copiar')));
      await t.pumpAndSettle();
      expect(copias, ['265148502']);
      expect(find.text('Copiado'), findsOneWidget);
    });

    testWidgets('servidor de antes (M1, sem "tipo"): lê pediu_fatura', (t) async {
      await t.pumpWidget(_cartao(_responde({
        'ok': true,
        'mostrar': true,
        'pediu_fatura': true,
        'nif': '265148502',
        'texto': 'Cliente pediu fatura com NIF 265148502',
      })));
      await t.pumpAndSettle();
      expect(find.text('Do cliente — pediu fatura'), findsOneWidget);
    });

    testWidgets('loja parceira, erro ou sem rede: nada aparece e nada trava',
        (t) async {
      for (final rpc in <NifRpc>[
        _responde({'ok': true, 'mostrar': false, 'loja_parceira': true}),
        _responde({'ok': false, 'error': 'nao_e_o_teu_pedido'}),
        (f, p) async => throw const io.SocketException('sem rede'),
      ]) {
        final caixa = NifCaixaController();
        await t.pumpWidget(_cartao(rpc, caixa: caixa));
        await t.pumpAndSettle();
        expect(find.byKey(const Key('driver_invoice_nif_card')), findsNothing);
        expect(caixa.aplica, isFalse);
        expect(caixa.porResponder, isFalse);
        expect(caixa.motivoBloqueio, isNull);
        await t.pumpWidget(const SizedBox());
      }
    });
  });

  group('Caixa obrigatória', () {
    testWidgets('marcar "Dei este NIF" responde; "Não consegui" pede o motivo',
        (t) async {
      final caixa = NifCaixaController();
      await t.pumpWidget(_cartao(_responde(_cliente()), caixa: caixa));
      await t.pumpAndSettle();
      expect(caixa.aplica, isTrue);
      expect(caixa.porResponder, isTrue);
      expect(caixa.motivoBloqueio, kAvisoNifPorResponder);
      expect(find.text('Dei este NIF na caixa e está no talão'), findsOneWidget);

      await t.tap(find.byKey(const Key('nif_caixa_dei')));
      await t.pump();
      expect(caixa.resposta, const NifCaixaResposta.dado());
      expect(caixa.porResponder, isFalse);

      // "Não consegui" desmarca a caixa e fica por responder até ao motivo.
      await t.tap(find.byKey(const Key('nif_caixa_nao_consegui')));
      await t.pump();
      expect(caixa.resposta, isNull);
      expect(find.text('A loja não aceitou'), findsOneWidget);
      expect(find.text('Esqueci-me'), findsOneWidget);
      expect(find.text('Outro'), findsOneWidget);

      await t.tap(find.byKey(const Key('nif_motivo_0')));
      await t.pump();
      expect(caixa.resposta, const NifCaixaResposta.naoDado('A loja não aceitou'));

      // "Outro" só conta com o motivo escrito.
      await t.tap(find.byKey(const Key('nif_motivo_2')));
      await t.pump();
      expect(caixa.resposta, isNull);
      await t.enterText(find.byKey(const Key('nif_motivo_outro')), 'Caixa automática');
      await t.pump();
      expect(caixa.resposta,
          const NifCaixaResposta.naoDado('Outro: Caixa automática'));
    });

    testWidgets('reabrir a folha traz a resposta que já está no servidor',
        (t) async {
      final dado = NifCaixaController();
      await t.pumpWidget(_cartao(
          _responde(_cliente(confirmado: {'dado': true, 'motivo': null})),
          caixa: dado));
      await t.pumpAndSettle();
      expect(dado.resposta, const NifCaixaResposta.dado());

      await t.pumpWidget(const SizedBox());
      final naoDado = NifCaixaController();
      await t.pumpWidget(_cartao(
          _responde(_cliente(confirmado: {'dado': false, 'motivo': 'Esqueci-me'})),
          caixa: naoDado));
      await t.pumpAndSettle();
      expect(naoDado.resposta, const NifCaixaResposta.naoDado('Esqueci-me'));
    });
  });

  testWidgets('outro pedido no mesmo cartão: a resposta volta a zero, sem erro no build',
      (t) async {
    final caixa = NifCaixaController();
    var pedido = 'p1';
    late StateSetter mudar;
    var redesenhos = 0;
    await t.pumpWidget(MaterialApp(
      home: Scaffold(
        body: StatefulBuilder(builder: (ctx, setState) {
          mudar = setState;
          // Como a folha do talão: o pai redesenha quando o controlador muda.
          caixa.addListener(() {
            if (ctx.mounted) setState(() => redesenhos++);
          });
          return SingleChildScrollView(
            child: DriverInvoiceNifCard(
              orderId: pedido,
              caixa: caixa,
              rpc: (f, p) async => _cliente(),
            ),
          );
        }),
      ),
    ));
    await t.pumpAndSettle();
    await t.tap(find.byKey(const Key('nif_caixa_dei')));
    await t.pumpAndSettle();
    expect(caixa.resposta, const NifCaixaResposta.dado());

    mudar(() => pedido = 'p2');
    await t.pumpAndSettle();
    expect(t.takeException(), isNull);
    expect(caixa.resposta, isNull, reason: 'pedido novo, caixa por responder');
    expect(caixa.porResponder, isTrue);
    expect(redesenhos, greaterThan(0));
  });

  group('Envio em segundo plano (estafeta_confirmar_nif_caixa)', () {
    test('falha duas vezes e grava à terceira, com os parâmetros certos',
        () async {
      final chamadas = <Map<String, dynamic>>[];
      NifCaixaEnvio.rpc = (f, p) async {
        expect(f, 'estafeta_confirmar_nif_caixa');
        chamadas.add(p);
        if (chamadas.length < 3) throw Exception('sem rede');
        return {'ok': true, 'aplica': true};
      };
      final ok = await NifCaixaEnvio.enviar(
          'p1', const NifCaixaResposta.naoDado('Esqueci-me'));
      expect(ok, isTrue);
      expect(chamadas, hasLength(3));
      expect(chamadas.last,
          {'p_order_id': 'p1', 'p_dado': false, 'p_motivo': 'Esqueci-me'});
    });

    test('três falhas: desiste sem lançar', () async {
      var n = 0;
      NifCaixaEnvio.rpc = (f, p) async {
        n++;
        throw Exception('sem rede');
      };
      expect(await NifCaixaEnvio.enviar('p1', const NifCaixaResposta.dado()),
          isFalse);
      expect(n, NifCaixaEnvio.tentativas);
      expect(n, 3);
    });

    test('recusa do servidor (não é o teu pedido): não repete', () async {
      var n = 0;
      NifCaixaEnvio.rpc = (f, p) async {
        n++;
        return {'ok': false, 'error': 'nao_e_o_teu_pedido'};
      };
      expect(await NifCaixaEnvio.enviar('p1', const NifCaixaResposta.dado()),
          isFalse);
      expect(n, 1);
    });

    test('emSegundoPlano não espera pelo servidor', () {
      final nunca = Completer<dynamic>();
      var chamou = false;
      NifCaixaEnvio.rpc = (f, p) {
        chamou = true;
        return nunca.future;
      };
      NifCaixaEnvio.emSegundoPlano('p1', const NifCaixaResposta.dado());
      expect(chamou, isTrue, reason: 'já foi pedido, mas ninguém ficou à espera');
    });
  });

  group('Folha do talão das compras ("Quanto pagaste na caixa?")', () {
    late String foto;
    setUpAll(() {
      foto = (io.File('${io.Directory.systemTemp.path}'
              '${io.Platform.pathSeparator}talao_m10_nif.png')
            ..writeAsBytesSync(_png))
          .path;
    });

    Future<void> abrir(WidgetTester t, NifRpc nifRpc,
        {required void Function() aoFechar}) async {
      await t.binding.setSurfaceSize(const Size(800, 1600));
      addTearDown(() => t.binding.setSurfaceSize(null));
      t.binding.defaultBinaryMessenger
          .setMockMethodCallHandler(_canalCamara, (call) async {
        if (call.method == 'pickImage') return foto;
        return null;
      });
      addTearDown(() => t.binding.defaultBinaryMessenger
          .setMockMethodCallHandler(_canalCamara, null));
      await t.pumpWidget(MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (ctx) => ElevatedButton(
              onPressed: () async {
                await showModalBottomSheet<Object?>(
                  context: ctx,
                  isScrollControlled: true,
                  builder: (_) => ReceiptCaptureSheet(
                      isCash: false, orderId: 'p1', nifRpc: nifRpc),
                );
                aoFechar();
              },
              child: const Text('abrir folha'),
            ),
          ),
        ),
      ));
      await t.tap(find.text('abrir folha'));
      await t.pumpAndSettle();
      await t.tap(find.text('Foto do talão (ou da conta / do saco)'));
      await t.pumpAndSettle();
      await t.enterText(find.byKey(const Key('fld_valor_talao')), '7,88');
      await t.pumpAndSettle();
    }

    VoidCallback? botaoConfirmar(WidgetTester t) => t
        .widget<ButtonStyleButton>(find.ancestor(
            of: find.text('Confirmar'),
            matching: find.byWidgetPredicate((w) => w is ElevatedButton)))
        .onPressed;

    testWidgets('Confirmar desligado até responder; depois fecha e envia o "dado"',
        (t) async {
      final enviados = <Map<String, dynamic>>[];
      NifCaixaEnvio.rpc = (f, p) async {
        enviados.add(p);
        return {'ok': true};
      };
      var fechou = false;
      await abrir(t, _responde(_cliente()), aoFechar: () => fechou = true);

      expect(find.text('NIF PARA A FATURA'), findsOneWidget);
      expect(botaoConfirmar(t), isNull, reason: 'foto e valor não chegam');
      expect(find.text(kAvisoNifPorResponder), findsOneWidget);

      await t.ensureVisible(find.byKey(const Key('nif_caixa_dei')));
      await t.tap(find.byKey(const Key('nif_caixa_dei')));
      await t.pumpAndSettle();
      expect(botaoConfirmar(t), isNotNull);

      await t.tap(find.text('Confirmar'));
      await t.pumpAndSettle();
      expect(fechou, isTrue);
      expect(enviados, [
        {'p_order_id': 'p1', 'p_dado': true, 'p_motivo': null},
      ]);
    });

    testWidgets('"Não consegui" + motivo também deixa seguir', (t) async {
      final enviados = <Map<String, dynamic>>[];
      NifCaixaEnvio.rpc = (f, p) async {
        enviados.add(p);
        return {'ok': true};
      };
      var fechou = false;
      await abrir(t, _responde(_cliente()), aoFechar: () => fechou = true);

      await t.ensureVisible(find.byKey(const Key('nif_caixa_nao_consegui')));
      await t.tap(find.byKey(const Key('nif_caixa_nao_consegui')));
      await t.pumpAndSettle();
      expect(botaoConfirmar(t), isNull, reason: 'falta o motivo');
      await t.ensureVisible(find.byKey(const Key('nif_motivo_1')));
      await t.tap(find.byKey(const Key('nif_motivo_1')));
      await t.pumpAndSettle();
      expect(botaoConfirmar(t), isNotNull);

      await t.ensureVisible(find.text('Confirmar'));
      await t.tap(find.text('Confirmar'));
      await t.pumpAndSettle();
      expect(fechou, isTrue);
      expect(enviados.single['p_dado'], isFalse);
      expect(enviados.single['p_motivo'], 'Esqueci-me');
    });

    testWidgets('o envio falha sempre: a folha fecha na mesma (nunca trava)',
        (t) async {
      var tentativas = 0;
      NifCaixaEnvio.rpc = (f, p) async {
        tentativas++;
        throw Exception('sem rede');
      };
      var fechou = false;
      await abrir(t, _responde(_cliente()), aoFechar: () => fechou = true);
      await t.ensureVisible(find.byKey(const Key('nif_caixa_dei')));
      await t.tap(find.byKey(const Key('nif_caixa_dei')));
      await t.pumpAndSettle();
      await t.tap(find.text('Confirmar'));
      await t.pumpAndSettle();
      expect(fechou, isTrue);
      expect(tentativas, 3);
    });

    testWidgets('sem rede para ler o NIF: não há caixa e o Confirmar liga',
        (t) async {
      var fechou = false;
      await abrir(t, (f, p) async => throw Exception('sem rede'),
          aoFechar: () => fechou = true);
      expect(find.text('NIF PARA A FATURA'), findsNothing);
      expect(botaoConfirmar(t), isNotNull);
      await t.tap(find.text('Confirmar'));
      await t.pumpAndSettle();
      expect(fechou, isTrue);
    });
  });

  group('Folha do Favor e mapa (pela fonte)', () {
    final folha =
        io.File('lib/widgets/errand_execution_sheet.dart').readAsStringSync();

    test('o "Confirmar compra" fica desligado com a caixa do NIF por responder',
        () {
      expect(folha, contains('DriverInvoiceNifCard(orderId: o.id, caixa: _nifCaixa)'));
      expect(folha,
          contains('Listenable.merge([_tetoCtrl, _talaoTotalCtrl, _nifCaixa])'));
      expect(folha, contains('_nifCaixa.motivoBloqueio'));
      expect(folha,
          contains('_busy || motivo != null ? null : _confirmarCompraComNif'));
      expect(folha, contains('NifCaixaEnvio.emSegundoPlano(widget.order.id, nif)'));
    });

    test('o fecho da compra (_finalizePurchase) não mudou: não fala de NIF', () {
      final i = folha.indexOf('Future<void> _finalizePurchase() async {');
      final fim = folha.indexOf('/// M10 09/11/2026: a resposta à caixa do NIF');
      expect(i, greaterThan(0));
      expect(fim, greaterThan(i));
      final corpo = folha.substring(i, fim).toLowerCase();
      expect(corpo, isNot(contains('nif')));
      expect(corpo, contains("'finalize_errand_purchase'"));
    });

    test('mapa: Favor com compra mostra o NIF até fechar o talão', () {
      final mapa =
          io.File('lib/screens/driver_map_screen.dart').readAsStringSync();
      expect(mapa, contains('focusOrder.errandHasPurchase &&'));
      expect(mapa, contains("key: ValueKey('nif_favor_\${focusOrder.id}')"));
      expect(mapa, contains('caixa: _nifCaixa,'));
      expect(mapa, contains('NifCaixaEnvio.emSegundoPlano(widget.orderId!, nif)'));
    });
  });
}
