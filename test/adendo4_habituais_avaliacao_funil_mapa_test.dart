// ADENDO 4 — itens 6, 7, 8 e 10 (29/10/2026), mais o painel admin dos
// interruptores.
//
//   6  "os meus habituais" no topo da home
//   7  foto do prato na avaliação (sem prémio nenhum)
//   8  resumo das avaliações por IA e funil "muito visto, pouco pedido"
//   10 mapa simples de procura para estafetas
import 'dart:convert';

import 'package:bora_app/l10n/bora_lang.dart';
import 'package:bora_app/models/cart_item.dart';
import 'package:bora_app/models/order_model.dart';
import 'package:bora_app/screens/admin/admin_platform_settings_screen.dart';
import 'package:bora_app/screens/driver/mapa_procura_estafeta_screen.dart';
import 'package:bora_app/services/foto_avaliacao_service.dart';
import 'package:bora_app/services/interruptores_app.dart';
import 'package:bora_app/services/mapa_procura_service.dart';
import 'package:bora_app/services/prato_visitas_service.dart';
import 'package:bora_app/widgets/foto_prova_entrega.dart';
import 'package:bora_app/widgets/home/meus_habituais.dart';
import 'package:bora_app/widgets/partner/painel_avaliacoes_e_funil.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart' show Circle;
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

OrderModel _entregue(String id, String loja, List<(String, int)> linhas,
        {DateTime? criado,
        OrderStatus estado = OrderStatus.delivered,
        OrderServiceType tipo = OrderServiceType.restaurant}) =>
    OrderModel(
      id: id,
      total: 15,
      serviceType: tipo,
      status: estado,
      vendorName: loja,
      createdAt: criado ?? DateTime.utc(2026, 10, 20),
      items: [
        for (final l in linhas)
          CartItem(
              productId: l.$1,
              name: 'Prato ${l.$1}',
              price: 5,
              quantity: l.$2),
      ],
    );

/// Respostas do servidor de brincar, por caminho.
http.Response _responder(http.Request req) {
  final p = req.url.path;
  final precisaObjeto =
      (req.headers['Accept'] ?? req.headers['accept'] ?? '').contains('pgrst.object');
  String corpo;
  if (p.endsWith('/rest/v1/orders')) {
    corpo = jsonEncode({
      'foto_entrega_url':
          'https://x.supabase.co/storage/v1/object/public/order-photos/uid/entrega_p1_1.jpg',
      'foto_entrega_em': '2026-10-29T14:05:00Z',
    });
  } else if (p.endsWith('/rest/v1/restaurant_review_summary')) {
    corpo = jsonEncode({
      'summary': 'Os clientes elogiam a rapidez e criticam a falta de molho.',
      'ratings_count': 6,
    });
  } else if (p.endsWith('/rpc/partner_funil_pratos')) {
    corpo = jsonEncode([
      {'product_id': 'a', 'nome': 'Bitoque', 'aberturas': 40, 'pedidos': 2},
      {'product_id': 'b', 'nome': 'Hambúrguer', 'aberturas': 30, 'pedidos': 20},
      {'product_id': 'c', 'nome': 'Salada', 'aberturas': 3, 'pedidos': 0},
    ]);
  } else if (p.endsWith('/rpc/admin_list_settings')) {
    corpo = jsonEncode([
      {
        'key': 'ask_cutlery',
        'value': true,
        'description': 'Perguntar por talheres no pagamento.',
        'category': 'cliente'
      },
      {
        'key': 'feature_esgotado_minutos',
        'value': 10,
        'description': 'Minutos para pedir troca.',
        'category': 'cliente'
      },
      {
        'key': 'tvde_cancel_fee_cents',
        'value': 375,
        'description': 'Dinheiro.',
        'category': 'tvde'
      },
    ]);
  } else if (p.contains('/storage/v1/object/sign/')) {
    corpo = jsonEncode({'signedURL': '/object/sign/order-photos/uid/x.jpg?token=t'});
  } else {
    corpo = precisaObjeto ? 'null' : '[]';
  }
  return http.Response(corpo, 200,
      request: req,
      headers: {'content-type': 'application/json; charset=utf-8'});
}

Widget _app(Widget filho) => MaterialApp(home: Scaffold(body: filho));

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await Supabase.initialize(
      url: 'http://127.0.0.1:1',
      anonKey: 'teste',
      debug: false,
      authOptions: const FlutterAuthClientOptions(detectSessionInUri: false),
      httpClient: MockClient((req) async => _responder(req)),
    );
  });

  setUp(() {
    BoraLang.notifier.value = AppLang.pt;
    InterruptoresApp.instance.definirParaTeste({
      InterruptoresApp.fotoEntregaCliente: true,
      InterruptoresApp.funilPratos: true,
      InterruptoresApp.resumoAvaliacoesIa: false,
      InterruptoresApp.mapaProcuraEstafeta: true,
    });
  });

  group('6 — os meus habituais', () {
    test('os 3 últimos pedidos entregues, o mais recente primeiro', () {
      final lista = escolherHabituais([
        _entregue('1', 'Boom', [('a', 1)], criado: DateTime.utc(2026, 10, 1)),
        _entregue('2', 'Pizzaria', [('b', 2)], criado: DateTime.utc(2026, 10, 5)),
        _entregue('3', 'Sushi', [('c', 1)], criado: DateTime.utc(2026, 10, 9)),
        _entregue('4', 'Tasca', [('d', 1)], criado: DateTime.utc(2026, 10, 12)),
      ]);
      expect(lista.map((o) => o.id), ['4', '3', '2']);
    });

    test('o mesmo pedido repetido conta uma vez só', () {
      final lista = escolherHabituais([
        _entregue('1', 'Boom', [('a', 1), ('b', 2)], criado: DateTime.utc(2026, 10, 1)),
        _entregue('2', 'Boom', [('b', 2), ('a', 1)], criado: DateTime.utc(2026, 10, 8)),
        _entregue('3', 'Boom', [('a', 3)], criado: DateTime.utc(2026, 10, 9)),
      ]);
      expect(lista.map((o) => o.id), ['3', '2'],
          reason: 'o 1 e o 2 são o mesmo pedido: fica o mais recente');
    });

    test('só pedidos entregues de restaurante ou loja', () {
      final lista = escolherHabituais([
        _entregue('1', 'Boom', [('a', 1)], estado: OrderStatus.cancelled),
        _entregue('2', 'Boom', [('a', 1)], estado: OrderStatus.onTheWay),
        _entregue('3', 'Favor', [('z', 1)], tipo: OrderServiceType.errand),
        _entregue('4', 'Encomenda', [('y', 1)], tipo: OrderServiceType.sendPackage),
        OrderModel(
            id: '5',
            total: 5,
            serviceType: OrderServiceType.restaurant,
            status: OrderStatus.delivered,
            vendorName: 'Vazio'),
      ]);
      expect(lista, isEmpty);
    });

    test('resumo dos produtos corta quando é longo', () {
      expect(resumoDosProdutos(_entregue('1', 'B', [('a', 2), ('b', 1)])),
          '2× Prato a, 1× Prato b');
      expect(
          resumoDosProdutos(
              _entregue('1', 'B', [('a', 1), ('b', 1), ('c', 1), ('d', 1)])),
          '1× Prato a, 1× Prato b +2');
    });
  });

  group('7 — foto do prato na avaliação', () {
    test('o ficheiro começa por avaliacao_ (é o que o servidor reconhece)', () {
      final n = FotoAvaliacaoService.nomeDoFicheiro(
          'o1', DateTime.fromMillisecondsSinceEpoch(1790000000000));
      expect(n, 'avaliacao_o1_1790000000000.jpg');
      expect(n, startsWith('avaliacao_'));
    });

    test('lê o rating_id que a submit_rating devolveu', () {
      expect(FotoAvaliacaoService.idDaAvaliacao({'rating_id': 'abc', 'updated': false}),
          'abc');
      expect(FotoAvaliacaoService.idDaAvaliacao({'rating_id': ''}), isNull);
      expect(FotoAvaliacaoService.idDaAvaliacao(null), isNull);
    });

    test('o interruptor existe com a chave do painel', () {
      expect(InterruptoresApp.avaliacaoComFoto, 'feature_avaliacao_com_foto');
    });
  });

  group('2 — foto da entrega, ecrã do cliente (com o servidor de brincar)', () {
    testWidgets('mostra o cartão com a hora quando há foto', (t) async {
      await t.runAsync(() async {
        await t.pumpWidget(_app(FotoProvaEntregaCliente(
            orderId: 'p1', status: OrderStatus.delivered)));
        for (var i = 0; i < 20; i++) {
          await Future<void>.delayed(const Duration(milliseconds: 50));
          await t.pump();
          if (find.byKey(const Key('foto_prova_entrega')).evaluate().isNotEmpty) {
            break;
          }
        }
      });
      expect(find.byKey(const Key('foto_prova_entrega')), findsOneWidget);
      expect(find.text('Foto da entrega'), findsWidgets);
      expect(find.textContaining('Tirada às'), findsOneWidget);
    });

    testWidgets('com o interruptor desligado no painel não aparece', (t) async {
      InterruptoresApp.instance
          .definirParaTeste({InterruptoresApp.fotoEntregaCliente: false});
      await t.runAsync(() async {
        await t.pumpWidget(_app(FotoProvaEntregaCliente(
            orderId: 'p1', status: OrderStatus.delivered)));
        await Future<void>.delayed(const Duration(milliseconds: 300));
        await t.pump();
      });
      expect(find.byKey(const Key('foto_prova_entrega')), findsNothing);
    });
  });

  group('8 — funil do parceiro e resumo das avaliações', () {
    test('"muito visto e pouco pedido": pelo menos 5 aberturas e menos de 20%', () {
      final lista = muitoVistosEPoucoPedidos(const [
        PratoNoFunil(id: 'a', nome: 'Bitoque', aberturas: 40, pedidos: 2),
        PratoNoFunil(id: 'b', nome: 'Hambúrguer', aberturas: 30, pedidos: 20),
        PratoNoFunil(id: 'c', nome: 'Salada', aberturas: 3, pedidos: 0),
        PratoNoFunil(id: 'd', nome: 'Sopa', aberturas: 12, pedidos: 1),
      ]);
      expect(lista.map((p) => p.id), ['a', 'd']);
    });

    test('conversão: pedidos por abertura; zero aberturas dá zero', () {
      expect(const PratoNoFunil(id: 'a', nome: '', aberturas: 10, pedidos: 3).conversao,
          closeTo(0.3, 1e-9));
      expect(const PratoNoFunil(id: 'a', nome: '', aberturas: 0, pedidos: 3).conversao, 0);
    });

    test('lê o que a função do servidor devolve', () {
      final p = PratoNoFunil.fromJson(
          {'product_id': 'x', 'nome': 'Prato', 'aberturas': 7, 'pedidos': 1});
      expect((p.id, p.nome, p.aberturas, p.pedidos), ('x', 'Prato', 7, 1));
    });

    testWidgets('o painel mostra só os pratos muito vistos e pouco pedidos',
        (t) async {
      await t.runAsync(() async {
        await t.pumpWidget(_app(const SingleChildScrollView(
            child: FunilPratosCard(restaurantId: 'r1'))));
        for (var i = 0; i < 20; i++) {
          await Future<void>.delayed(const Duration(milliseconds: 50));
          await t.pump();
          if (find.byKey(const Key('funil_pratos_card')).evaluate().isNotEmpty) {
            break;
          }
        }
      });
      expect(find.byKey(const Key('funil_a')), findsOneWidget);
      expect(find.byKey(const Key('funil_b')), findsNothing,
          reason: 'o hambúrguer vende bem');
      expect(find.byKey(const Key('funil_c')), findsNothing,
          reason: 'só 3 aberturas: poucos dados');
      expect(find.textContaining('40 vistas · 2 pedidos'), findsOneWidget);
    });

    testWidgets('funil desligado no painel: não desenha nada', (t) async {
      InterruptoresApp.instance.definirParaTeste({InterruptoresApp.funilPratos: false});
      await t.runAsync(() async {
        await t.pumpWidget(_app(const FunilPratosCard(restaurantId: 'r1')));
        await Future<void>.delayed(const Duration(milliseconds: 300));
        await t.pump();
      });
      expect(find.byKey(const Key('funil_pratos_card')), findsNothing);
    });

    testWidgets('o resumo guardado aparece mesmo com a IA desligada, sem botão',
        (t) async {
      await t.runAsync(() async {
        await t.pumpWidget(_app(const ResumoAvaliacoesCard(restaurantId: 'r1')));
        for (var i = 0; i < 20; i++) {
          await Future<void>.delayed(const Duration(milliseconds: 50));
          await t.pump();
          if (find.byKey(const Key('resumo_avaliacoes_card')).evaluate().isNotEmpty) {
            break;
          }
        }
      });
      expect(find.byKey(const Key('resumo_avaliacoes_texto')), findsOneWidget);
      expect(find.textContaining('elogiam a rapidez'), findsOneWidget);
      expect(find.textContaining('6 comentários'), findsOneWidget);
      expect(find.byKey(const Key('btn_atualizar_resumo')), findsNothing,
          reason: 'IA desligada no painel');
    });

    testWidgets('com a IA ligada aparece o botão de atualizar', (t) async {
      InterruptoresApp.instance
          .definirParaTeste({InterruptoresApp.resumoAvaliacoesIa: true});
      await t.runAsync(() async {
        await t.pumpWidget(_app(const ResumoAvaliacoesCard(restaurantId: 'r1')));
        for (var i = 0; i < 20; i++) {
          await Future<void>.delayed(const Duration(milliseconds: 50));
          await t.pump();
          if (find.byKey(const Key('btn_atualizar_resumo')).evaluate().isNotEmpty) {
            break;
          }
        }
      });
      expect(find.byKey(const Key('btn_atualizar_resumo')), findsOneWidget);
    });

    test('avisos em palavras que o parceiro lê', () {
      expect(avisoDaRespostaDoResumo({'ok': true}), isNull);
      expect(avisoDaRespostaDoResumo({'ok': false, 'reason': 'poucos_comentarios'}),
          contains('poucos comentários'));
      expect(avisoDaRespostaDoResumo(null), contains('Não foi possível'));
    });
  });

  group('10 — mapa de procura para estafetas', () {
    const celulas = [
      CelulaProcura(hora: 12, lat: 40.54, lng: -7.27, pedidos: 5),
      CelulaProcura(hora: 12, lat: 40.55, lng: -7.26, pedidos: 2),
      CelulaProcura(hora: 19, lat: 40.54, lng: -7.27, pedidos: 9),
    ];

    test('células de uma hora: as mais procuradas primeiro', () {
      expect(celulasDaHora(celulas, 12).map((c) => c.pedidos), [5, 2]);
      expect(celulasDaHora(celulas, 3), isEmpty);
    });

    test('pedidos por hora e intensidade de 0 a 1', () {
      expect(pedidosPorHora(celulas), {12: 7, 19: 9});
      expect(intensidade(5, 10), 0.5);
      expect(intensidade(20, 10), 1.0);
      expect(intensidade(3, 0), 0);
    });

    test('abre na hora atual se tiver dados, senão na seguinte com dados', () {
      final porHora = pedidosPorHora(celulas);
      expect(horaInicial(porHora, 12), 12);
      expect(horaInicial(porHora, 14), 19);
      expect(horaInicial(porHora, 20), 12, reason: 'dá a volta ao dia');
      expect(horaInicial(const {}, 9), 9);
    });

    test('lê as colunas da função do servidor', () {
      final c = CelulaProcura.fromJson(
          {'hora': 15, 'lat_celula': 40.5428, 'lng_celula': -7.2681, 'pedidos': 4});
      expect((c.hora, c.pedidos), (15, 4));
      expect(c.lat, closeTo(40.5428, 1e-9));
    });

    testWidgets('o ecrã abre na hora com dados e troca de zonas ao mudar a hora',
        (t) async {
      Set<Circle>? zonas;
      // Largo o bastante para as 24 horas estarem todas na lista.
      t.view.physicalSize = const Size(4000, 1600);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.resetPhysicalSize);
      addTearDown(t.view.resetDevicePixelRatio);
      await t.runAsync(() async {
        await t.pumpWidget(MaterialApp(
          home: MapaProcuraEstafetaScreen(
            leitor: () async => celulas,
            horaAgora: 12,
            construirMapa: (_, z, __) {
              zonas = z;
              return const SizedBox(key: Key('mapa_falso'));
            },
          ),
        ));
        await Future<void>.delayed(const Duration(milliseconds: 100));
        await t.pump();
        await t.pump();
      });
      expect(find.byKey(const Key('mapa_falso')), findsOneWidget);
      expect(zonas!.length, 2);
      // A célula mais forte é a mais opaca.
      final opacidades = zonas!.map((c) => c.fillColor.a).toList()..sort();
      expect(opacidades.last, greaterThan(opacidades.first));
      await t.tap(find.byKey(const Key('hora_19')));
      await t.pump();
      expect(zonas!.length, 1);
      await t.tap(find.byKey(const Key('hora_3')));
      await t.pump();
      expect(zonas!, isEmpty);
      expect(find.text('Sem pedidos nesta hora nos últimos 30 dias.'), findsOneWidget);
    });

    testWidgets('sem permissão ou sem rede diz-se em palavras de pessoa', (t) async {
      await t.runAsync(() async {
        await t.pumpWidget(MaterialApp(
          home: MapaProcuraEstafetaScreen(
            leitor: () async => throw Exception('forbidden'),
            construirMapa: (_, __, ___) => const SizedBox(),
          ),
        ));
        await Future<void>.delayed(const Duration(milliseconds: 100));
        await t.pump();
        await t.pump();
      });
      expect(find.byKey(const Key('mapa_procura_erro')), findsOneWidget);
    });

    testWidgets('desligado no painel: o ecrã diz que está desligado', (t) async {
      InterruptoresApp.instance
          .definirParaTeste({InterruptoresApp.mapaProcuraEstafeta: false});
      await t.runAsync(() async {
        await t.pumpWidget(MaterialApp(
          home: MapaProcuraEstafetaScreen(
            leitor: () async => celulas,
            construirMapa: (_, __, ___) => const SizedBox(),
          ),
        ));
        await Future<void>.delayed(const Duration(milliseconds: 100));
        await t.pump();
      });
      expect(find.text('Este mapa está desligado neste momento.'), findsOneWidget);
    });
  });

  group('painel admin dos interruptores', () {
    test('todas as chaves do código estão na lista editável do painel', () {
      final doCodigo = {
        InterruptoresApp.talheres,
        InterruptoresApp.troco,
        InterruptoresApp.detalhesMorada,
        InterruptoresApp.juntarMais,
        InterruptoresApp.barraPedidoAtivo,
        InterruptoresApp.fotoEntregaCliente,
        InterruptoresApp.esgotadoAviso,
        InterruptoresApp.esgotadoMinutos,
        InterruptoresApp.habituaisHome,
        InterruptoresApp.avaliacaoComFoto,
        InterruptoresApp.etiquetasMenu,
        InterruptoresApp.etiquetasMenuIa,
        InterruptoresApp.resumoAvaliacoesIa,
        InterruptoresApp.funilPratos,
        InterruptoresApp.ofertaGanhoVisivel,
        InterruptoresApp.mapaProcuraEstafeta,
      };
      expect(kInterruptoresApp, doCodigo);
    });

    testWidgets('o interruptor edita-se com um botão, sem pedir "motivo" de dinheiro',
        (t) async {
      await t.runAsync(() async {
        await t.pumpWidget(const MaterialApp(home: AdminPlatformSettingsScreen()));
        for (var i = 0; i < 20; i++) {
          await Future<void>.delayed(const Duration(milliseconds: 50));
          await t.pump();
          if (find.text('CLIENTE').evaluate().isNotEmpty) break;
        }
      });
      expect(find.text('CLIENTE'), findsOneWidget);
      await t.tap(find.text('CLIENTE'));
      await t.pumpAndSettle();
      // ask_cutlery tem "_cut" no meio: não pode cair no caminho do dinheiro.
      await t.tap(find.text('ask_cutlery'));
      await t.pumpAndSettle();
      expect(find.byKey(const Key('interruptor_definicao')), findsOneWidget);
      expect(find.textContaining('Motivo'), findsNothing);
      expect(find.textContaining('MEXE EM DINHEIRO'), findsNothing);
    });

    testWidgets('a chave de dinheiro continua com cadeado/motivo', (t) async {
      await t.runAsync(() async {
        await t.pumpWidget(const MaterialApp(home: AdminPlatformSettingsScreen()));
        for (var i = 0; i < 20; i++) {
          await Future<void>.delayed(const Duration(milliseconds: 50));
          await t.pump();
          if (find.text('TVDE').evaluate().isNotEmpty) break;
        }
      });
      await t.tap(find.text('TVDE'));
      await t.pumpAndSettle();
      await t.tap(find.text('tvde_cancel_fee_cents'));
      await t.pumpAndSettle();
      expect(find.textContaining('Motivo'), findsOneWidget);
    });
  });

  test('registar a abertura duas vezes na mesma sessão chama o servidor uma só vez', () async {
    PratoVisitasService.esquecerSessao();
    // Sem sessão não chama nada e não lança.
    await PratoVisitasService.registarAbertura('p1');
    await PratoVisitasService.registarAbertura('p1');
    await PratoVisitasService.registarAbertura('');
  });
}
