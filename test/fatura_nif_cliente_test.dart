import 'dart:io';

import 'package:bora_app/models/order_model.dart';
import 'package:bora_app/screens/client_billing_screen.dart';
import 'package:bora_app/services/fatura_nif_service.dart';
import 'package:bora_app/utils/nif_pt.dart';
import 'package:bora_app/widgets/fatura_nif_card.dart';
import 'package:bora_app/widgets/fatura_nif_pedido.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// FATURA COM NIF (28/10/2026) — o lado do cliente.
///
/// O NIF é SEMPRE opcional: o interruptor nasce desligado, a validação é a do
/// servidor (`nif_pt_valido`), e o NIF nunca trava nem atrasa o pedido (só se
/// chama o servidor depois de o pedido ter id real, em segundo plano).
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // ── A validação é a do servidor ──────────────────────────────────────────
  group('nifPtValido (espelho de nif_pt_valido)', () {
    // Respostas que o servidor deu a 29/10/2026 (select nif_pt_valido(...)).
    const doServidor = <String, bool>{
      '123456789': true,
      '123456788': false,
      '999999990': true,
      '999999991': false,
      '450000001': true,
      '450000000': false,
      '000000000': false,
      '423456789': false,
      '12345678': false,
      '1234567890': false,
      'abcdefghi': false,
      '': false,
      '123 456 789': true,
      '700000008': false,
      '700000000': false,
      '100000008': false,
      '200000004': true,
      '500000000': true,
      '800000009': false,
      '900000002': false,
      '611111113': false,
      '101010105': false,
      '456789123': false,
      '719999991': false,
      '399999990': true,
    };

    doServidor.forEach((nif, esperado) {
      test('"$nif" -> $esperado', () {
        expect(nifPtValido(nif), esperado);
      });
    });

    test('null e só espaços não valem', () {
      expect(nifPtValido(null), isFalse);
      expect(nifPtValido('   '), isFalse);
    });

    test('formatarNif agrupa de três em três; soDigitosNif limpa', () {
      expect(formatarNif('123456789'), '123 456 789');
      expect(formatarNif('123 456 789'), '123 456 789');
      expect(formatarNif('1234'), '1234');
      expect(soDigitosNif(' 12a3-4 '), '1234');
      expect(formatarNif(null), '');
    });
  });

  // ── O interruptor nasce desligado ────────────────────────────────────────
  group('FaturaNifController', () {
    test('nasce desligado e sem pedido de fatura', () {
      final c = FaturaNifController();
      expect(c.ligado, isFalse);
      expect(c.pedido, isNull);
      expect(c.nifPorCorrigir, isFalse);
      c.dispose();
    });

    test('com NIF guardado vem ligado e preenchido, e pode desligar', () {
      final c = FaturaNifController();
      c.aplicarPerfil(const DadosFatura(nif: '123456789', nome: 'Ana Teste'));
      expect(c.ligado, isTrue);
      expect(c.nif.text, '123456789');
      expect(c.nome.text, 'Ana Teste');
      expect(c.pedido?.nif, '123456789');
      expect(c.pedido?.nome, 'Ana Teste');

      c.definirLigado(false);
      expect(c.ligado, isFalse);
      expect(c.pedido, isNull, reason: 'desligado = nada vai para o servidor');
      c.dispose();
    });

    test('o perfil que chega tarde não desfaz a escolha do cliente', () {
      final c = FaturaNifController();
      c.definirLigado(false); // o cliente mexeu primeiro
      c.aplicarPerfil(const DadosFatura(nif: '123456789'));
      expect(c.ligado, isFalse);
      expect(c.nif.text, isEmpty);
      c.dispose();
    });

    test('sem NIF guardado fica desligado', () {
      final c = FaturaNifController()..aplicarPerfil(null);
      expect(c.ligado, isFalse);
      c.dispose();
    });

    test('ligado com NIF que não vale: avisa antes de cobrar, sem pedido', () {
      final c = FaturaNifController()..definirLigado(true);
      c.nif.text = '123456788';
      expect(c.nifPorCorrigir, isTrue);
      expect(c.pedido, isNull);

      c.nif.text = '123456789';
      expect(c.nifPorCorrigir, isFalse);
      expect(c.pedido?.nif, '123456789');
      expect(c.pedido?.nome, isNull, reason: 'o nome é opcional');
      c.dispose();
    });

    test('carregarPerfil: falhar a ler nunca estraga o pagamento', () async {
      final c = FaturaNifController();
      final s = FaturaNifService(
          rpc: (_, __) async => throw Exception('sem rede'));
      await c.carregarPerfil(s);
      expect(c.ligado, isFalse);
      c.dispose();
    });

    test('carregarPerfil: NIF guardado liga o interruptor', () async {
      final c = FaturaNifController();
      final s = FaturaNifService(
          rpc: (f, _) async => {'nif': '999999990', 'nome': null});
      await c.carregarPerfil(s);
      expect(c.ligado, isTrue);
      expect(c.nif.text, '999999990');
      c.dispose();
    });

    test('textos de baixo do interruptor: parceira, não parceira, serviço', () {
      expect(
        FaturaNifController.textoExplicativo(OrderServiceType.restaurant, true),
        'A loja fatura os produtos e a Bora o resto, as duas com o seu NIF.',
      );
      expect(
        FaturaNifController.textoExplicativo(
            OrderServiceType.storeShopping, false),
        'A Bora fatura em seu nome; os produtos vão com o talão da loja.',
      );
      expect(
        FaturaNifController.textoExplicativo(OrderServiceType.errand, false),
        'A Bora fatura o serviço em seu nome.',
      );
    });
  });

  group('FaturaNifCard (ecrã de pagamento)', () {
    Widget app(FaturaNifController c,
            {OrderServiceType tipo = OrderServiceType.restaurant,
            bool parceira = true}) =>
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: FaturaNifCard(
                  controller: c, serviceType: tipo, lojaParceira: parceira),
            ),
          ),
        );

    testWidgets('interruptor desligado por defeito e sem campos', (t) async {
      final c = FaturaNifController();
      await t.pumpWidget(app(c));

      final sw = t.widget<SwitchListTile>(
          find.byKey(const Key('fatura_nif_interruptor')));
      expect(sw.value, isFalse);
      expect(find.text('Quero fatura com NIF'), findsOneWidget);
      expect(find.byKey(const Key('fatura_nif_campo')), findsNothing);
      expect(find.byKey(const Key('fatura_nif_nome')), findsNothing);
      c.dispose();
    });

    testWidgets('loja parceira: a frase da loja e da Bora', (t) async {
      final c = FaturaNifController();
      await t.pumpWidget(app(c, parceira: true));
      expect(
          find.text(
              'A loja fatura os produtos e a Bora o resto, as duas com o seu NIF.'),
          findsOneWidget);
      expect(
          find.text(
              'A Bora fatura em seu nome; os produtos vão com o talão da loja.'),
          findsNothing);
      c.dispose();
    });

    testWidgets('loja não parceira: a Bora fatura, produtos com o talão',
        (t) async {
      final c = FaturaNifController();
      await t.pumpWidget(app(c, tipo: OrderServiceType.storeShopping, parceira: false));
      expect(
          find.text(
              'A Bora fatura em seu nome; os produtos vão com o talão da loja.'),
          findsOneWidget);
      c.dispose();
    });

    testWidgets('ligar mostra o NIF e o nome; NIF inválido mostra o erro',
        (t) async {
      final c = FaturaNifController();
      await t.pumpWidget(app(c));

      await t.tap(find.byKey(const Key('fatura_nif_interruptor')));
      await t.pump();
      expect(c.ligado, isTrue);
      expect(find.byKey(const Key('fatura_nif_campo')), findsOneWidget);
      expect(find.text('Nome na fatura (opcional)'), findsOneWidget);

      await t.enterText(find.byKey(const Key('fatura_nif_campo')), '123456788');
      await t.pump();
      expect(find.text('NIF inválido. Confere os 9 dígitos.'), findsOneWidget);
      expect(c.pedido, isNull);

      await t.enterText(find.byKey(const Key('fatura_nif_campo')), '123456789');
      await t.pump();
      expect(find.text('NIF inválido. Confere os 9 dígitos.'), findsNothing);
      expect(c.pedido?.nif, '123456789');
      c.dispose();
    });

    testWidgets('com NIF guardado vem ligado e preenchido', (t) async {
      final c = FaturaNifController();
      await t.pumpWidget(app(c));
      c.aplicarPerfil(const DadosFatura(nif: '123456789', nome: 'Ana Teste'));
      await t.pump();

      expect(t.widget<SwitchListTile>(find.byKey(const Key('fatura_nif_interruptor'))).value,
          isTrue);
      expect(find.text('123456789'), findsOneWidget);
      expect(find.text('Ana Teste'), findsOneWidget);

      // ... e o cliente pode desligar
      await t.tap(find.byKey(const Key('fatura_nif_interruptor')));
      await t.pump();
      expect(c.ligado, isFalse);
      expect(find.byKey(const Key('fatura_nif_campo')), findsNothing);
      c.dispose();
    });
  });

  // ── O servidor só é chamado com o pedido já criado ───────────────────────
  group('FaturaNifService (pedido com id real)', () {
    test('regista o NIF no pedido e guarda no perfil', () async {
      final chamadas = <String>[];
      Map<String, dynamic>? params;
      final s = FaturaNifService(
        espera: Duration.zero,
        rpc: (f, p) async {
          chamadas.add(f);
          params = p;
          return {'ok': true};
        },
      );
      final ok = await s.pedir('ped-1', nif: '123456789', nome: 'Ana Teste');

      expect(ok, isTrue);
      expect(chamadas, ['client_set_order_invoice']);
      expect(params, {
        'p_order_id': 'ped-1',
        'p_nif': '123456789',
        'p_nome': 'Ana Teste',
        'p_guardar': true,
      });
      expect(s.pendenteDe('ped-1'), isNull);
    });

    test('falha duas vezes e à terceira regista: 3 tentativas', () async {
      var n = 0;
      final s = FaturaNifService(
        espera: Duration.zero,
        rpc: (f, p) async {
          n++;
          if (n < 3) throw Exception('sem rede');
          return {'ok': true};
        },
      );
      expect(await s.pedir('ped-2', nif: '123456789'), isTrue);
      expect(n, 3);
      expect(s.pendenteDe('ped-2'), isNull);
    });

    test('falha as 3 vezes: fica pendente (rede) para "tentar de novo"',
        () async {
      var n = 0;
      final s = FaturaNifService(
        espera: Duration.zero,
        rpc: (f, p) async {
          n++;
          throw Exception('sem rede');
        },
      );
      var avisos = 0;
      s.addListener(() => avisos++);

      expect(await s.pedir('ped-3', nif: '123456789', nome: 'Ana'), isFalse);
      expect(n, 3, reason: 'nem mais, nem menos que 3 tentativas');
      final p = s.pendenteDe('ped-3');
      expect(p?.motivo, MotivoFaturaPendente.rede);
      expect(p?.nif, '123456789');
      expect(avisos, 1, reason: 'o ecrã de acompanhamento é avisado');
    });

    test('TARDE_DEMAIS não se repete: o pedido já saiu da loja', () async {
      var n = 0;
      final s = FaturaNifService(
        espera: Duration.zero,
        rpc: (f, p) async {
          n++;
          throw Exception('TARDE_DEMAIS: o NIF tem de ser indicado antes');
        },
      );
      expect(await s.pedir('ped-4', nif: '123456789'), isFalse);
      expect(n, 1);
      expect(s.pendenteDe('ped-4')?.motivo, MotivoFaturaPendente.recusado);
    });

    test('"tentar de novo" regista e limpa o aviso', () async {
      var falhar = true;
      final s = FaturaNifService(
        espera: Duration.zero,
        rpc: (f, p) async {
          if (falhar) throw Exception('sem rede');
          return {'ok': true};
        },
      );
      await s.pedir('ped-5', nif: '123456789');
      expect(s.pendenteDe('ped-5'), isNotNull);

      falhar = false;
      expect(await s.tentarDeNovo('ped-5'), isTrue);
      expect(s.pendenteDe('ped-5'), isNull);
    });

    test('pedirEmSegundoPlano não espera nem lança', () async {
      final s = FaturaNifService(
        espera: Duration.zero,
        rpc: (f, p) async => throw Exception('sem rede'),
      );
      // Volta logo (void): quem paga não fica à espera do servidor.
      s.pedirEmSegundoPlano('ped-6', nif: '123456789');
      await pumpEventQueue(times: 50);
      expect(s.pendenteDe('ped-6')?.motivo, MotivoFaturaPendente.rede);
    });

    test('perfil: ler, guardar e apagar (NIF vazio apaga)', () async {
      final feitas = <(String, Map<String, dynamic>)>[];
      final s = FaturaNifService(rpc: (f, p) async {
        feitas.add((f, p));
        return f == 'client_billing_get' ? {'nif': '123456789', 'nome': ''} : null;
      });

      final d = await s.lerPerfil();
      expect(d?.nif, '123456789');
      expect(d?.nome, isNull, reason: 'nome vazio = sem nome');

      await s.guardarPerfil('999999990', 'Ana');
      await s.apagarPerfil();
      expect(feitas[1].$1, 'client_billing_save');
      expect(feitas[1].$2, {'p_nif': '999999990', 'p_nome': 'Ana'});
      expect(feitas[2].$1, 'client_billing_save');
      expect(feitas[2].$2, {'p_nif': '', 'p_nome': null});
    });

    test('sem NIF guardado o servidor devolve null: lerPerfil dá null',
        () async {
      final s = FaturaNifService(rpc: (f, p) async => null);
      expect(await s.lerPerfil(), isNull);
    });
  });

  group('o ecrã de pagamento só chama depois do pedido ter id', () {
    final pay =
        File('lib/screens/payment_method_screen.dart').readAsStringSync();

    test('as quatro saídas (saldo, cartão, MB Way, dinheiro) passam o NIF', () {
      expect(pay, contains('_pedirFaturaNif(saldoOrderId, faturaPedida)'));
      expect(pay, contains('_pedirFaturaNif(orderId, faturaPedida)'));
      expect(pay, contains('_pedirFaturaNif(mbwayOrderId, faturaPedida)'));
      expect(pay, contains('_pedirFaturaNif(cashOrderId, faturaPedida)'));
    });

    test('a chamada ao servidor é em segundo plano (nunca await)', () {
      expect(pay, contains('.pedirEmSegundoPlano(orderId'));
      expect(pay, isNot(contains('await FaturaNifService')));
      expect(pay, isNot(contains('await _pedirFaturaNif')));
    });

    test('o interruptor e o NIF ficam desligados por defeito no ecrã', () {
      expect(pay, contains('FaturaNifCard('));
      expect(pay, contains('_faturaNif.carregarPerfil(FaturaNifService.instance)'));
    });

    test('a validação do NIF acontece antes de cobrar, não depois', () {
      final validar = pay.indexOf('_faturaNif.nifPorCorrigir');
      final cobrar = pay.indexOf('setState(() => _isProcessing = true);');
      expect(validar, greaterThan(0));
      expect(validar, lessThan(cobrar));
    });
  });

  // ── Acompanhamento: aviso + "tentar de novo" ─────────────────────────────
  group('FaturaNifAviso (acompanhamento)', () {
    OrderModel pedido(OrderStatus st, {DateTime? levantado}) => OrderModel(
          id: 'ped-9',
          total: 10,
          serviceType: OrderServiceType.restaurant,
          status: st,
          takeawayPickedUpAt: levantado,
        );

    Future<FaturaNifService> comPendente() async {
      var falhar = true;
      final s = FaturaNifService(
        espera: Duration.zero,
        rpc: (f, p) async {
          if (falhar) throw Exception('sem rede');
          return {'ok': true};
        },
      );
      await s.pedir('ped-9', nif: '123456789');
      // guarda a "chave" para o teste poder ligar a rede
      _rede = () => falhar = false;
      return s;
    }

    Widget app(FaturaNifService s, OrderModel o) => MaterialApp(
        home: Scaffold(body: FaturaNifAviso(order: o, servico: s)));

    testWidgets('aparece com o pedido na loja e "Tentar de novo" resolve',
        (t) async {
      final s = await comPendente();
      await t.pumpWidget(app(s, pedido(OrderStatus.preparing)));

      expect(find.byKey(const Key('fatura_nif_aviso')), findsOneWidget);
      expect(find.text('O NIF ainda não ficou na fatura deste pedido.'),
          findsOneWidget);

      _rede();
      await t.tap(find.byKey(const Key('fatura_nif_tentar_de_novo')));
      await t.pumpAndSettle();

      expect(find.byKey(const Key('fatura_nif_aviso')), findsNothing);
      expect(find.text('NIF registado na fatura.'), findsOneWidget);
      expect(s.pendenteDe('ped-9'), isNull);
    });

    testWidgets('se ainda falha, o aviso fica e diz-se', (t) async {
      final s = await comPendente();
      await t.pumpWidget(app(s, pedido(OrderStatus.created)));

      await t.tap(find.byKey(const Key('fatura_nif_tentar_de_novo')));
      await t.pumpAndSettle();

      expect(find.byKey(const Key('fatura_nif_aviso')), findsOneWidget);
      expect(find.text('Ainda não deu. Tenta de novo daqui a pouco.'),
          findsOneWidget);
    });

    testWidgets('já não aparece depois de o pedido sair da loja', (t) async {
      final s = await comPendente();
      for (final st in [
        OrderStatus.pickedUp,
        OrderStatus.onTheWay,
        OrderStatus.delivered,
        OrderStatus.cancelled,
      ]) {
        await t.pumpWidget(app(s, pedido(st)));
        expect(find.byKey(const Key('fatura_nif_aviso')), findsNothing,
            reason: '$st');
      }
      // takeaway já levantado
      await t.pumpWidget(
          app(s, pedido(OrderStatus.readyForPickup, levantado: DateTime(2026))));
      expect(find.byKey(const Key('fatura_nif_aviso')), findsNothing);
    });

    testWidgets('sem pendente não mostra nada', (t) async {
      final s = FaturaNifService(rpc: (f, p) async => null);
      await t.pumpWidget(app(s, pedido(OrderStatus.preparing)));
      expect(find.byKey(const Key('fatura_nif_aviso')), findsNothing);
    });

    test('o acompanhamento usa o aviso', () {
      final src =
          File('lib/screens/order_tracking_screen.dart').readAsStringSync();
      expect(src, contains('FaturaNifAviso(order: order)'));
    });
  });

  // ── Detalhe do pedido ────────────────────────────────────────────────────
  group('FaturaNifLinha (detalhe do pedido)', () {
    Widget app(FaturaNifService s) => MaterialApp(
        home: Scaffold(body: FaturaNifLinha(orderId: 'ped-7', servico: s)));

    testWidgets('mostra "Fatura com NIF 123 456 789"', (t) async {
      final s = FaturaNifService(
          lerPedido: (id) async =>
              const DadosFatura(nif: '123456789', nome: 'Ana Teste'));
      await t.pumpWidget(app(s));
      await t.pumpAndSettle();
      expect(find.text('Fatura com NIF 123 456 789 · Ana Teste'),
          findsOneWidget);
    });

    testWidgets('sem nome, só o NIF', (t) async {
      final s = FaturaNifService(
          lerPedido: (id) async => const DadosFatura(nif: '123456789'));
      await t.pumpWidget(app(s));
      await t.pumpAndSettle();
      expect(find.text('Fatura com NIF 123 456 789'), findsOneWidget);
    });

    testWidgets('sem pedido de fatura (ou com erro) não mostra nada',
        (t) async {
      await t.pumpWidget(
          app(FaturaNifService(lerPedido: (id) async => null)));
      await t.pumpAndSettle();
      expect(find.byKey(const Key('fatura_nif_linha')), findsNothing);

      await t.pumpWidget(app(FaturaNifService(
          lerPedido: (id) async => throw Exception('sem rede'))));
      await t.pumpAndSettle();
      expect(find.byKey(const Key('fatura_nif_linha')), findsNothing);
    });

    test('o detalhe do pedido usa a linha', () {
      final src =
          File('lib/screens/order_details_screen.dart').readAsStringSync();
      expect(src, contains('FaturaNifLinha(orderId: order.id)'));
    });
  });

  // ── Perfil › Dados de faturação ──────────────────────────────────────────
  group('ClientBillingScreen (Perfil › Dados de faturação)', () {
    Widget app(FaturaNifService s) =>
        MaterialApp(home: ClientBillingScreen(servico: s));

    test('o perfil tem a entrada', () {
      final src = File('lib/screens/profile_screen.dart').readAsStringSync();
      expect(src, contains("'Dados de faturação'.tr"));
      expect(src, contains('const ClientBillingScreen()'));
    });

    testWidgets('sem NIF guardado: diz-se e não há "Apagar"', (t) async {
      final s = FaturaNifService(rpc: (f, p) async => null);
      await t.pumpWidget(app(s));
      await t.pumpAndSettle();
      expect(find.byKey(const Key('billing_sem_nif')), findsOneWidget);
      expect(find.byKey(const Key('billing_apagar')), findsNothing);
    });

    testWidgets('com NIF guardado: mostra, muda e apaga', (t) async {
      final feitas = <(String, Map<String, dynamic>)>[];
      final s = FaturaNifService(rpc: (f, p) async {
        feitas.add((f, p));
        return f == 'client_billing_get'
            ? {'nif': '123456789', 'nome': 'Ana Teste'}
            : null;
      });
      await t.pumpWidget(app(s));
      await t.pumpAndSettle();

      expect(find.text('NIF guardado: 123 456 789'), findsOneWidget);
      expect(find.text('123456789'), findsOneWidget);
      expect(find.text('Ana Teste'), findsOneWidget);

      // mudar
      await t.enterText(find.byKey(const Key('billing_nif')), '999999990');
      await t.tap(find.byKey(const Key('billing_guardar')));
      await t.pumpAndSettle();
      expect(feitas.last.$1, 'client_billing_save');
      expect(feitas.last.$2, {'p_nif': '999999990', 'p_nome': 'Ana Teste'});
      expect(find.text('NIF guardado: 999 999 990'), findsOneWidget);

      // apagar (com confirmação)
      await t.tap(find.byKey(const Key('billing_apagar')));
      await t.pumpAndSettle();
      expect(find.text('Apagar os dados de faturação?'), findsOneWidget);
      await t.tap(find.byKey(const Key('billing_confirmar_apagar')));
      await t.pumpAndSettle();
      expect(feitas.last.$1, 'client_billing_save');
      expect(feitas.last.$2, {'p_nif': '', 'p_nome': null});
      expect(find.byKey(const Key('billing_sem_nif')), findsOneWidget);
    });

    testWidgets('NIF inválido: avisa e não chama o servidor', (t) async {
      final feitas = <String>[];
      final s = FaturaNifService(rpc: (f, p) async {
        feitas.add(f);
        return null;
      });
      await t.pumpWidget(app(s));
      await t.pumpAndSettle();

      await t.enterText(find.byKey(const Key('billing_nif')), '123456788');
      await t.tap(find.byKey(const Key('billing_guardar')));
      await t.pumpAndSettle();

      expect(find.text('NIF inválido. Confere os 9 dígitos.'), findsOneWidget);
      expect(feitas, ['client_billing_get'], reason: 'nada foi guardado');
    });

    testWidgets('sem rede a ler: diz-se e deixa tentar de novo', (t) async {
      var falhar = true;
      final s = FaturaNifService(rpc: (f, p) async {
        if (falhar) throw Exception('sem rede');
        return {'nif': '123456789', 'nome': null};
      });
      await t.pumpWidget(app(s));
      await t.pumpAndSettle();
      expect(find.text('Não foi possível ler os teus dados. Tenta de novo.'),
          findsOneWidget);

      falhar = false;
      await t.tap(find.byKey(const Key('billing_tentar_de_novo')));
      await t.pumpAndSettle();
      expect(find.text('NIF guardado: 123 456 789'), findsOneWidget);
    });
  });
}

/// Liga a "rede" do servidor falso (ver `comPendente`).
void Function() _rede = () {};
