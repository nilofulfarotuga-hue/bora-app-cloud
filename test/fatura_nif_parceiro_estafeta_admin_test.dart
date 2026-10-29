import 'dart:io';

import 'package:bora_app/services/fatura_nif_service.dart';
import 'package:bora_app/services/partner_fatura_service.dart';
import 'package:bora_app/widgets/admin/admin_fatura_nif_section.dart';
import 'package:bora_app/widgets/driver_fiscal_card.dart';
import 'package:bora_app/widgets/partner_fatura_linha.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// FATURA COM NIF (28/10/2026) — parceiro (N2), estafeta (N3) e painel (N4).
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  /// Apanha o que vai para a área de transferência.
  List<String> apanharCopias() {
    final copias = <String>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'Clipboard.setData') {
        copias.add((call.arguments as Map)['text'] as String);
      }
      return null;
    });
    addTearDown(() => TestDefaultBinaryMessengerBinding
        .instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, null));
    return copias;
  }

  // ── N2 · Parceiro ────────────────────────────────────────────────────────
  group('PartnerFaturaService', () {
    test('só pergunta pelos pedidos que ainda não conhece', () async {
      final pedidos = <List<String>>[];
      final s = PartnerFaturaService(rpc: (f, p) async {
        expect(f, 'partner_pedidos_fatura');
        pedidos.add(List<String>.from(p['p_order_ids'] as List));
        return {
          for (final id in p['p_order_ids'] as List)
            id: {'nif': null, 'nome': null, 'valor_cents': 1240},
        };
      });

      await s.carregar(['a', 'b']);
      await s.carregar(['a', 'b', 'c']);
      await s.carregar(['a']);

      expect(pedidos, [
        ['a', 'b'],
        ['c'],
      ]);
      expect(s.de('c')?.valorCents, 1240);
    });

    test('lê NIF, nome e valor; sem NIF é consumidor final', () async {
      final s = PartnerFaturaService(rpc: (f, p) async => {
            'p1': {'nif': '123456789', 'nome': 'Ana Teste', 'valor_cents': 2350},
            'p2': {'nif': null, 'nome': null, 'valor_cents': 800},
            'p3': {'nif': '', 'nome': '  ', 'valor_cents': 0},
          });
      await s.carregar(['p1', 'p2', 'p3']);

      final p1 = s.de('p1')!;
      expect(p1.temNif, isTrue);
      expect(p1.nif, '123456789');
      expect(p1.nome, 'Ana Teste');
      expect(p1.valorEur, 23.50);
      expect(s.de('p2')!.temNif, isFalse);
      expect(s.de('p3')!.temNif, isFalse);
      expect(s.de('p3')!.nome, isNull);
      expect(s.de('nao-existe'), isNull,
          reason: 'pedido que o servidor não devolveu (não é de loja parceira)');
    });

    test('o tempo real (NIF pedido depois) volta a perguntar por esse pedido',
        () async {
      String? nif;
      final s = PartnerFaturaService(rpc: (f, p) async => {
            for (final id in p['p_order_ids'] as List)
              id: {'nif': nif, 'nome': null, 'valor_cents': 1000},
          });
      await s.carregar(['p1']);
      expect(s.de('p1')!.temNif, isFalse);

      nif = '999999990'; // o cliente pediu fatura com NIF
      var avisos = 0;
      s.addListener(() => avisos++);
      s.aoMudar('p1');
      await pumpEventQueue();

      expect(s.de('p1')!.nif, '999999990');
      expect(avisos, 1, reason: 'o cartão redesenha-se sozinho');

      // evento sem pedido: ignora
      s.aoMudar(null);
      s.aoMudar('');
      await pumpEventQueue();
      expect(avisos, 1);
    });

    test('depois de "marcar em falta", atualizar traz o valor novo', () async {
      var valor = 2000;
      final s = PartnerFaturaService(rpc: (f, p) async => {
            for (final id in p['p_order_ids'] as List)
              id: {'nif': null, 'nome': null, 'valor_cents': valor},
          });
      await s.carregar(['p1']);
      expect(s.de('p1')!.valorCents, 2000);

      valor = 1450; // o hambúrguer em falta saiu do pedido
      await s.atualizar(['p1']);
      expect(s.de('p1')!.valorCents, 1450);
    });

    test('sem rede não lança, e volta a tentar na próxima', () async {
      var falhar = true;
      var chamadas = 0;
      final s = PartnerFaturaService(rpc: (f, p) async {
        chamadas++;
        if (falhar) throw Exception('sem rede');
        return {'p1': {'nif': null, 'nome': null, 'valor_cents': 500}};
      });
      await s.carregar(['p1']);
      expect(s.de('p1'), isNull);

      falhar = false;
      await s.carregar(['p1']);
      expect(chamadas, 2);
      expect(s.de('p1')!.valorCents, 500);
    });
  });

  group('PartnerFaturaLinha (cartão e detalhe do pedido da loja)', () {
    Widget app(FaturaDoPedido? f) =>
        MaterialApp(home: Scaffold(body: PartnerFaturaLinha(fatura: f)));

    testWidgets('com NIF: valor de balcão, NIF e nome', (t) async {
      await t.pumpWidget(app(const FaturaDoPedido(
          orderId: 'p1', nif: '123456789', nome: 'Ana Teste', valorCents: 1240)));

      expect(find.text('Fatura ao cliente: 12,40 € (preço de balcão)'),
          findsOneWidget);
      expect(find.text('NIF 123 456 789 · Ana Teste'), findsOneWidget);
      expect(find.text('Consumidor final'), findsNothing);
    });

    testWidgets('com NIF e sem nome: só o NIF', (t) async {
      await t.pumpWidget(app(const FaturaDoPedido(
          orderId: 'p1', nif: '123456789', valorCents: 500)));
      expect(find.text('NIF 123 456 789'), findsOneWidget);
    });

    testWidgets('copiar leva o NIF só com dígitos', (t) async {
      final copias = apanharCopias();
      await t.pumpWidget(app(const FaturaDoPedido(
          orderId: 'p1', nif: '123456789', valorCents: 500)));

      await t.tap(find.byKey(const Key('partner_fatura_copiar')));
      await t.pump();

      expect(copias, ['123456789']);
      expect(find.text('NIF copiado.'), findsOneWidget);
    });

    testWidgets('sem NIF: "Consumidor final" e nada para copiar', (t) async {
      await t.pumpWidget(
          app(const FaturaDoPedido(orderId: 'p1', valorCents: 1240)));

      expect(find.text('Fatura ao cliente: 12,40 € (preço de balcão)'),
          findsOneWidget);
      expect(find.text('Consumidor final'), findsOneWidget);
      expect(find.byKey(const Key('partner_fatura_copiar')), findsNothing);
    });

    testWidgets('sem dados do servidor não mostra nada', (t) async {
      await t.pumpWidget(app(null));
      expect(find.byKey(const Key('partner_fatura_linha')), findsNothing);
    });

    test('o painel da loja usa a linha no cartão e no histórico, ao vivo', () {
      final src =
          File('lib/screens/partner_dashboard_screen.dart').readAsStringSync();
      // cartão do pedido
      expect(src, contains('PartnerFaturaLinha(fatura: widget.fatura)'));
      // histórico (detalhe)
      expect(src, contains('PartnerFaturaLinha(fatura: _fatura.de(o.id))'));
      // tempo real e pedido dos pedidos novos
      expect(src, contains('_fatura.ouvir(widget.restaurant.id)'));
      expect(src, contains('_fatura.carregar('));
      // depois de "marcar em falta" volta a perguntar
      expect(src, contains('onEditado: () => widget.onPedidoEditado(order)'));
      expect(src, contains('unawaited(_fatura.atualizar([o.id]))'));
    });

    test('a folha de "marcar em falta" avisa o painel quando a loja envia', () {
      final src = File('lib/widgets/order_edit/partner_order_edit_section.dart')
          .readAsStringSync();
      final propor = src.indexOf('await svc.propor(widget.order.id');
      expect(propor, greaterThan(0));
      expect(src.indexOf('widget.onEditado?.call();', propor),
          greaterThan(propor));
    });

    test('o serviço ouve order_invoice_requests em tempo real', () {
      final src =
          File('lib/services/partner_fatura_service.dart').readAsStringSync();
      expect(src, contains("table: 'order_invoice_requests'"));
      expect(src, contains("'partner_pedidos_fatura'"));
    });
  });

  // ── N3 · Estafeta ────────────────────────────────────────────────────────
  group('DriverReciboCard (recibo verde do estafeta)', () {
    Map<String, dynamic> recibo({String? cliente, String? clienteNif}) => {
          'total_a_faturar': 123.4,
          'entregas': 17,
          'cliente': cliente,
          'cliente_nif': clienteNif,
          'iva': 'IVA — regime de isenção',
          'texto_recibo': 'Serviços de entrega prestados.',
          'recibo_passado': false,
        };

    Widget app(Map<String, dynamic> r) => MaterialApp(
        home: Scaffold(
            body: SingleChildScrollView(
                child: DriverReciboCard(recibo: r, onMarcar: () {}))));

    testWidgets('com cliente_nif: "Passa o recibo à Bora, NIF …" e copiar',
        (t) async {
      final copias = apanharCopias();
      // Valores de teste: o NIF verdadeiro vem do servidor, nunca do código.
      await t.pumpWidget(app(recibo(
          cliente: 'Bora — NIF 999999990', clienteNif: '999999990')));

      expect(find.textContaining('cliente: Bora — NIF 999999990'),
          findsOneWidget);
      expect(find.text('Passa o recibo à Bora, NIF 999999990'),
          findsOneWidget);

      await t.tap(find.byKey(const Key('recibo_copiar_nif')));
      await t.pump();
      expect(copias, ['999999990']);
    });

    testWidgets('sem cliente_nif: consumidor final e sem aviso da Bora',
        (t) async {
      await t.pumpWidget(app(recibo(cliente: 'Consumidor final')));

      expect(find.textContaining('cliente: Consumidor final'), findsOneWidget);
      expect(find.byKey(const Key('recibo_nif_bora')), findsNothing);
      expect(find.textContaining('Passa o recibo'), findsNothing);
    });

    testWidgets('servidor antigo sem o campo "cliente": consumidor final',
        (t) async {
      await t.pumpWidget(app(recibo()));
      expect(find.textContaining('cliente: Consumidor final'), findsOneWidget);
    });

    test('o NIF da Bora nunca está escrito no código do cartão', () {
      final src = File('lib/widgets/driver_fiscal_card.dart').readAsStringSync();
      // Nenhum NIF/NIPC escrito no código (repositório público): o número vem
      // sempre do servidor.
      expect(RegExp(r"'\d{9}'").hasMatch(src), isFalse);
      expect(src, contains("r['cliente']"));
      expect(src, contains("r['cliente_nif']"));
    });

    test('o estafeta não lê NIF de clientes: só o da Bora, do servidor', () {
      final src = File('lib/widgets/driver_fiscal_card.dart').readAsStringSync();
      expect(src, isNot(contains('order_invoice_requests')));
      expect(src, isNot(contains('client_billing')));
    });
  });

  // ── N4 · Admin (PT-BR) ───────────────────────────────────────────────────
  group('AdminFaturaNifSection', () {
    Widget app(AdminFaturaNifSection s) =>
        MaterialApp(home: Scaffold(body: SingleChildScrollView(child: s)));

    testWidgets('mostra o NIF e o nome do pedido', (t) async {
      await t.pumpWidget(app(AdminFaturaNifSection.pedido(
        orderId: 'p1',
        carregar: () async =>
            const DadosFatura(nif: '123456789', nome: 'Ana Teste'),
        guardar: (nif, nome) async {},
      )));
      await t.pumpAndSettle();
      expect(find.text('NIF 123 456 789 · Ana Teste'), findsOneWidget);
    });

    testWidgets('sem NIF: consumidor final', (t) async {
      await t.pumpWidget(app(AdminFaturaNifSection.cliente(
        userId: 'u1',
        carregar: () async => null,
        guardar: (nif, nome) async {},
      )));
      await t.pumpAndSettle();
      expect(find.text('Sem NIF (consumidor final).'), findsOneWidget);
      expect(find.text('Dados de faturação do cliente'), findsOneWidget);
    });

    testWidgets('editar: NIF válido chega ao servidor e o cartão recarrega',
        (t) async {
      DadosFatura? guardado;
      final feitas = <(String, String)>[];
      await t.pumpWidget(app(AdminFaturaNifSection.pedido(
        orderId: 'p1',
        carregar: () async => guardado,
        guardar: (nif, nome) async {
          feitas.add((nif, nome));
          guardado = DadosFatura(nif: nif, nome: nome.isEmpty ? null : nome);
        },
      )));
      await t.pumpAndSettle();

      await t.tap(find.byKey(const Key('admin_fatura_nif_editar')));
      await t.pumpAndSettle();
      await t.enterText(
          find.byKey(const Key('admin_fatura_nif_campo')), '123456789');
      await t.enterText(
          find.byKey(const Key('admin_fatura_nome_campo')), 'Ana Teste');
      await t.tap(find.byKey(const Key('admin_fatura_salvar')));
      await t.pumpAndSettle();

      expect(feitas, [('123456789', 'Ana Teste')]);
      expect(find.text('NIF 123 456 789 · Ana Teste'), findsOneWidget);
    });

    testWidgets('NIF inválido: avisa na janela e não chama o servidor',
        (t) async {
      var chamadas = 0;
      await t.pumpWidget(app(AdminFaturaNifSection.pedido(
        orderId: 'p1',
        carregar: () async => null,
        guardar: (nif, nome) async => chamadas++,
      )));
      await t.pumpAndSettle();

      await t.tap(find.byKey(const Key('admin_fatura_nif_editar')));
      await t.pumpAndSettle();
      await t.enterText(
          find.byKey(const Key('admin_fatura_nif_campo')), '123456788');
      await t.tap(find.byKey(const Key('admin_fatura_salvar')));
      await t.pumpAndSettle();

      expect(find.text('NIF inválido (o dígito de controle não bate).'),
          findsOneWidget);
      expect(chamadas, 0);
    });

    testWidgets('NIF vazio apaga (o servidor recebe vazio)', (t) async {
      final feitas = <(String, String)>[];
      await t.pumpWidget(app(AdminFaturaNifSection.pedido(
        orderId: 'p1',
        carregar: () async => const DadosFatura(nif: '123456789'),
        guardar: (nif, nome) async => feitas.add((nif, nome)),
      )));
      await t.pumpAndSettle();

      await t.tap(find.byKey(const Key('admin_fatura_nif_editar')));
      await t.pumpAndSettle();
      await t.enterText(find.byKey(const Key('admin_fatura_nif_campo')), '');
      await t.tap(find.byKey(const Key('admin_fatura_salvar')));
      await t.pumpAndSettle();

      expect(feitas, [('', '')]);
    });

    test('o detalhe do pedido e o do cliente têm o cartão; o parceiro tem a ajuda',
        () {
      final pedido =
          File('lib/screens/admin/admin_order_detail_screen.dart')
              .readAsStringSync();
      expect(pedido, contains("AdminFaturaNifSection.pedido(orderId: order['id'] as String)"));

      final clientes =
          File('lib/screens/admin/admin_clients_screen.dart').readAsStringSync();
      expect(clientes, contains('mostrarFaturacaoDoCliente('));
      expect(clientes, contains('Dados de faturação (NIF)'));

      final servico =
          File('lib/widgets/admin/admin_fatura_nif_section.dart')
              .readAsStringSync();
      expect(servico, contains("'admin_order_invoice_set'"));
      expect(servico, contains("'admin_client_billing_set'"));

      final parceiro =
          File('lib/screens/admin/admin_partner_detail_screen.dart')
              .readAsStringSync();
      expect(parceiro, contains('Parceiros: sai só a taxa base de entrega'));
      expect(parceiro, contains('Não parceiros: sai a entrega toda.'));
      expect(parceiro,
          isNot(contains('Só vale para loja NÃO-parceira (o servidor ignora')),
          reason: 'o comentário antigo estava errado');
    });
  });
}
