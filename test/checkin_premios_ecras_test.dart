import 'dart:async';

import 'package:bora_app/config/app_colors.dart';
import 'package:bora_app/l10n/bora_lang.dart';
import 'package:bora_app/models/order_service_type.dart';
import 'package:bora_app/screens/client/checkin_premios_screen.dart';
import 'package:bora_app/services/checkin_premios_service.dart';
import 'package:bora_app/services/checkin_service.dart';
import 'package:bora_app/stores/cart_store.dart';
import 'package:bora_app/widgets/checkin/checkin_mes_sheet.dart';
import 'package:bora_app/widgets/checkin/premio_carrinho_banner.dart';
import 'package:bora_app/widgets/home/checkin_diario_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Ecrãs dos prémios dos marcos do check-in (Bloco D, 21/10/2026):
/// a seta do cartão abre a vista do mês, o prémio novo faz festa uma vez,
/// "Os meus prémios" diz o que falta, e o carrinho da loja certa oferece o vale.

CheckinPremiosEstado _estado({
  int dias = 10,
  List<Map<String, dynamic>>? vales,
  List<String> novos = const [],
  bool ativos = true,
  bool hojeFeito = true,
  int? diaMarco,
  Map<String, dynamic>? escada,
}) =>
    CheckinPremiosEstado.fromJson(_estadoJson(
      dias: dias,
      vales: vales,
      novos: novos,
      ativos: ativos,
      hojeFeito: hojeFeito,
      diaMarco: diaMarco,
      escada: escada,
    ));

/// O JSON de `client_checkin_premios()`; sem [escada] fica como o servidor
/// antigo (sem a chave `escada`).
Map<String, dynamic> _estadoJson({
  int dias = 10,
  List<Map<String, dynamic>>? vales,
  List<String> novos = const [],
  bool ativos = true,
  bool hojeFeito = true,
  int? diaMarco,
  Map<String, dynamic>? escada,
}) =>
    {
      'ok': true,
      'marcos_ativos': ativos,
      'ciclo_dias': 30,
      'dias_seguidos': dias,
      'dia_marco': diaMarco ?? dias,
      'hoje_feito': hojeFeito,
      if (escada != null) 'escada': escada,
      'texto': 'Faz o check-in todos os dias. Aos 10 dias seguidos ganhas 2 salgados da Keli (pagas só a entrega e as taxas). Aos 15, um açaí do Goola. Aos 30, escolhes 2 horas de limpeza ou uma lavagem exterior do carro.',
      'marcos': [
        for (final m in const [
          ['semana', 7, 'tokens', 'os tokens do Dia 7'],
          ['salgados', 10, 'produto', '2 salgados da Keli'],
          ['acai', 15, 'produto', 'um açaí do Goola'],
          ['mes', 30, 'servico', '2 horas de limpeza ou uma lavagem exterior do carro'],
        ])
          {
            'chave': m[0], 'dia': m[1], 'tipo': m[2], 'titulo': m[3], 'descricao': '',
            'tokens': m[2] == 'tokens' ? 40 : null,
            'atingido': dias >= (m[1] as int),
            'faltam': dias >= (m[1] as int) ? 0 : (m[1] as int) - dias,
          },
      ],
      'proximo': {'chave': 'acai', 'dia': 15, 'titulo': 'um açaí do Goola', 'faltam': 15 - dias},
      'vales': vales ?? const [],
      'novos': novos,
    };

const _textoEscada =
    'Em cada sequência levas UM prémio: o mais alto a que chegares. Se levantares, a sequência volta ao dia 1. Se continuares, trocas por um prémio maior.';

const _guardadoSalgados = <String, dynamic>{
  'chave': 'salgados', 'dia': 10, 'titulo': '2 salgados da Keli', 'tipo': 'produto', 'descricao': '',
  'guardado_em': '2026-10-29T10:00:00+00:00', 'garantido_ate': '2026-11-28T10:00:00+00:00',
};

const _proximoAcai = <String, dynamic>{
  'chave': 'acai', 'dia': 15, 'titulo': 'um açaí do Goola', 'descricao': '', 'faltam': 5,
};

/// O objeto `escada` de `client_checkin_premios()` (29/10/2026).
Map<String, dynamic> _escadaJson({
  bool ativa = true,
  Map<String, dynamic>? guardado,
  String? decisao,
  bool pendente = false,
  Map<String, dynamic>? proximo,
}) =>
    {
      'ativa': ativa,
      'texto': _textoEscada,
      'guardado': guardado,
      'decisao': decisao,
      'pendente_decisao': pendente,
      'pode_continuar': guardado != null && proximo != null,
      'proximo_maior': proximo,
      'ultimo_dia': 30,
      'levantados': 0,
      'reinicio_data': null,
      'ultimo_vale_id': null,
    };

Map<String, dynamic> _vale(String id, String estado, {String chave = 'salgados', int marco = 10, String tipo = 'produto'}) => {
      'id': id, 'marco': marco, 'chave': chave, 'tipo': tipo, 'estado': estado,
      'titulo': chave == 'mes' ? '2 horas de limpeza ou uma lavagem exterior do carro' : '2 salgados da Keli',
      'loja_id': tipo == 'produto' ? 'sabores-brasil-guarda' : null,
      'loja_nome': tipo == 'produto' ? 'Sabores do Brasil - Keli Barbosa' : null,
      'produto_id': tipo == 'produto' ? 'premio-checkin-salgados' : null,
      'opcoes': tipo == 'servico' ? ['limpeza', 'lavagem'] : <String>[],
      'valido_ate': '2026-11-20T10:00:00Z',
      'ativar_em': estado == 'guardado' ? '2026-11-01' : null,
      'esperar_ate': estado == 'a_espera_pedido' ? '2026-11-20T10:00:00Z' : null,
      'usado_em': estado == 'usado' ? '2026-10-25T10:00:00Z' : null,
    };

CheckinEstado _semana() => const CheckinEstado(
      enabled: true,
      eligible: true,
      reason: null,
      alreadyDone: false,
      streakDay: 3,
      tokensToday: 10,
      nextDay: 3,
      nextReward: 10,
      rewards: [5, 5, 10, 10, 15, 15, 40],
    );

void main() {
  testWidgets('vista do mês: 4 marcos, em que dia está e quanto falta', (t) async {
    await t.pumpWidget(MaterialApp(home: Scaffold(body: CheckinMesSheet(estado: _estado(), abrirPremios: () {}))));
    expect(find.byKey(const Key('checkin_marco_7')), findsOneWidget);
    expect(find.byKey(const Key('checkin_marco_10')), findsOneWidget);
    expect(find.byKey(const Key('checkin_marco_15')), findsOneWidget);
    expect(find.byKey(const Key('checkin_marco_30')), findsOneWidget);
    expect(find.text('Estás no dia 10 de 30.'), findsOneWidget);
    expect(find.text('Faltam 5 dias para ganhares um açaí do Goola.'), findsOneWidget);
    expect(find.text('Ganho'), findsNWidgets(2));
    expect(find.text('Faltam 20 dias'), findsOneWidget);
    expect(find.text('40 tokens'), findsOneWidget);
    expect(find.textContaining('Aos 10 dias seguidos ganhas 2 salgados da Keli'), findsOneWidget);
  });

  testWidgets('cartão do check-in: a semana da sequência, a seta abre o mês no cartão e o prémio novo faz festa uma vez', (t) async {
    final vistos = <String>[];
    await t.pumpWidget(MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(
          child: CheckinDiarioCard(
            carregar: () async => _semana(),
            carregarPremios: () async => _estado(vales: [_vale('v1', 'por_usar')], novos: const ['v1']),
            marcarVistos: (ids) async => vistos.addAll(ids),
            abrirPremios: (_) async {},
          ),
        ),
      ),
    ));
    await t.pump();
    await t.pump();
    // 29/10/2026: com marcos, a faixa mostra a semana atual da sequência
    // (dia 10 → Dia 8 a 14), não o "Dia 1 a 7" fixo.
    expect(find.byKey(const Key('checkin_dia_8')), findsOneWidget, reason: 'no dia 10 a faixa é a semana 8–14');
    expect(find.byKey(const Key('checkin_dia_14')), findsOneWidget);
    expect(find.byKey(const Key('checkin_dia_7')), findsNothing);
    expect(find.byKey(const Key('btn_checkin_mes')), findsOneWidget);
    expect(find.byKey(const Key('checkin_premio_novo')), findsOneWidget);
    expect(find.text('Ganhaste 2 salgados da Keli!'), findsOneWidget);
    expect(find.byKey(const Key('checkin_confete')), findsOneWidget);
    expect(vistos, ['v1']);
    await t.pump(const Duration(seconds: 2));
    await t.pump();
    expect(find.byKey(const Key('checkin_confete')), findsNothing, reason: 'o confete acaba sozinho');
    await t.tap(find.byKey(const Key('btn_checkin_mes')));
    await t.pumpAndSettle();
    // A seta abre o calendário DENTRO do cartão, nunca uma folha por cima.
    expect(find.byKey(const Key('checkin_mes_calendario')), findsOneWidget);
    expect(find.byKey(const Key('checkin_mes_sheet')), findsNothing);
  });

  testWidgets('sem marcos ligados o cartão fica exatamente como antes (sem seta)', (t) async {
    await t.pumpWidget(MaterialApp(
      home: Scaffold(
        body: CheckinDiarioCard(
          carregar: () async => _semana(),
          carregarPremios: () async => _estado(ativos: false),
        ),
      ),
    ));
    await t.pump();
    await t.pump();
    expect(find.byKey(const Key('checkin_diario_card')), findsOneWidget);
    expect(find.byKey(const Key('btn_checkin_mes')), findsNothing);
    expect(find.byKey(const Key('checkin_premio_novo')), findsNothing);
    for (var d = 1; d <= 7; d++) {
      expect(find.byKey(Key('checkin_dia_$d')), findsOneWidget, reason: 'sem marcos: Dia 1 a 7 como antes');
    }
    expect(find.byKey(const Key('checkin_mes_calendario')), findsNothing);
  });

  testWidgets('Os meus prémios: usar, guardado pelo tecto, falta 1 pedido e histórico', (t) async {
    final usados = <String>[];
    await t.pumpWidget(MaterialApp(
      home: CheckinPremiosScreen(
        carregar: () async => _estado(vales: [
          _vale('p1', 'por_usar'),
          _vale('g1', 'guardado', chave: 'mes', marco: 30, tipo: 'servico'),
          _vale('e1', 'a_espera_pedido', chave: 'mes', marco: 30, tipo: 'servico'),
          _vale('u1', 'usado'),
        ]),
        usarProduto: (_, v) async => usados.add(v.id),
        escolherServico: (_, v) async => usados.add(v.id),
      ),
    ));
    await t.pumpAndSettle();
    expect(find.text('Por usar'), findsOneWidget);
    expect(find.text('Usados e expirados'), findsOneWidget);
    expect(find.textContaining('Fica disponível a 01/11'), findsOneWidget);
    expect(find.textContaining('Falta 1 pedido para desbloquear o prémio'), findsOneWidget);
    expect(find.byKey(const Key('btn_usar_p1')), findsOneWidget);
    expect(find.byKey(const Key('btn_usar_g1')), findsNothing, reason: 'guardado não se usa ainda');
    expect(find.byKey(const Key('btn_usar_e1')), findsNothing, reason: 'falta o pedido pago');
    expect(find.byKey(const Key('btn_usar_u1')), findsNothing);
    await t.tap(find.byKey(const Key('btn_usar_p1')));
    await t.pumpAndSettle();
    expect(usados, ['p1']);
  });

  testWidgets('carrinho da loja certa: "Tens um prémio para esta loja — Aplicar"', (t) async {
    final cart = CartStore()
      ..configureSession(
        serviceType: OrderServiceType.restaurant,
        isPartnerStore: true,
        vendorName: 'Sabores do Brasil - Keli Barbosa',
        vendorRestaurantId: 'sabores-brasil-guarda',
        distanceKm: 1.0,
        pickupLocation: const LatLng(40.5323845, -7.2656677),
        deliveryLocation: const LatLng(40.5373, -7.2676),
      );
    final aplicados = <String>[];
    await t.pumpWidget(ChangeNotifierProvider<CartStore>.value(
      value: cart,
      child: MaterialApp(
        home: Scaffold(
          body: PremioCarrinhoBanner(
            carregar: () async => _estado(vales: [_vale('p1', 'por_usar')]),
            aplicar: (_, v) async {
              aplicados.add(v.id);
              return true;
            },
          ),
        ),
      ),
    ));
    await t.pumpAndSettle();
    expect(find.byKey(const Key('premio_para_aplicar')), findsOneWidget);
    await t.tap(find.byKey(const Key('btn_aplicar_premio')));
    await t.pumpAndSettle();
    expect(aplicados, ['p1']);
  });

  testWidgets('carrinho de outra loja: nada aparece', (t) async {
    final cart = CartStore()
      ..configureSession(
        serviceType: OrderServiceType.restaurant,
        isPartnerStore: true,
        vendorName: 'Outra',
        vendorRestaurantId: 'outra-loja',
        distanceKm: 1.0,
        pickupLocation: const LatLng(40.53, -7.26),
        deliveryLocation: const LatLng(40.5373, -7.2676),
      );
    await t.pumpWidget(ChangeNotifierProvider<CartStore>.value(
      value: cart,
      child: MaterialApp(
        home: Scaffold(body: PremioCarrinhoBanner(carregar: () async => _estado(vales: [_vale('p1', 'por_usar')]))),
      ),
    ));
    await t.pumpAndSettle();
    expect(find.byKey(const Key('premio_para_aplicar')), findsNothing);
    expect(find.byKey(const Key('premio_no_carrinho')), findsNothing);
    unawaited(Future<void>.value());
  });

  group('escada de prémios (29/10/2026)', () {
    setUp(() => SharedPreferences.setMockInitialValues({}));

    Widget cartao({
      required Future<CheckinPremiosEstado?> Function() premios,
      Future<CheckinEscadaResultado> Function()? levantar,
      Future<CheckinEscadaResultado> Function()? continuar,
      Future<void> Function()? festa,
    }) =>
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: CheckinDiarioCard(
                key: UniqueKey(),
                carregar: () async => _semana(),
                carregarPremios: premios,
                marcarVistos: (_) async {},
                abrirPremios: (_) async {},
                levantarEscada: levantar ?? () async => fail('não devia levantar'),
                continuarEscada: continuar ?? () async => fail('não devia continuar'),
                festaEscada: festa ?? () async {},
              ),
            ),
          ),
        );

    Finder dentro(String chave, Finder f) => find.descendant(of: find.byKey(Key(chave)), matching: f);

    testWidgets('faixa no dia 12: Dia 8 a 14, feitos marcados, hoje destacado e tokens do ciclo de 7', (t) async {
      // Tokens: hoje é o Dia 3 do ciclo (10 tokens), por fazer. Sequência: 11 feitos → hoje é o 12.
      await t.pumpWidget(cartao(premios: () async => _estado(dias: 11, hojeFeito: false)));
      await t.pump();
      await t.pump();
      for (var d = 8; d <= 14; d++) {
        expect(find.byKey(Key('checkin_dia_$d')), findsOneWidget);
      }
      expect(find.byKey(const Key('checkin_dia_7')), findsNothing);
      expect(find.byKey(const Key('checkin_dia_15')), findsNothing);
      expect(dentro('checkin_dia_11', find.byIcon(Icons.check_rounded)), findsOneWidget, reason: 'dia 11 feito');
      expect(dentro('checkin_dia_12', find.byIcon(Icons.check_rounded)), findsNothing, reason: 'hoje por fazer');
      expect(dentro('checkin_dia_12', find.text('+10')), findsOneWidget, reason: 'hoje = Dia 3 dos tokens');
      expect(dentro('checkin_dia_13', find.text('+10')), findsOneWidget, reason: 'amanhã = Dia 4');
      expect(dentro('checkin_dia_14', find.text('+15')), findsOneWidget, reason: 'Dia 5 dos tokens');
      expect(dentro('checkin_dia_8', find.text('+15')), findsOneWidget, reason: '4 dias antes = Dia 6');
      expect(dentro('checkin_dia_9', find.text('+40')), findsOneWidget, reason: '3 dias antes = Dia 7');
      // Hoje destacado: borda verde de 2 px na caixa do dia 12.
      final caixaHoje = t.widget<Container>(dentro('checkin_dia_12', find.byType(Container)).first);
      expect((caixaHoje.decoration! as BoxDecoration).border, isNotNull);
    });

    testWidgets('a seta abre e fecha o calendário do ciclo dentro do cartão', (t) async {
      await t.pumpWidget(cartao(premios: () async => _estado(dias: 11, hojeFeito: false)));
      await t.pump();
      await t.pump();
      expect(find.byKey(const Key('checkin_mes_calendario')), findsNothing);
      await t.tap(find.byKey(const Key('btn_checkin_mes')));
      await t.pumpAndSettle();
      expect(find.byKey(const Key('checkin_mes_calendario')), findsOneWidget);
      expect(find.byKey(const Key('checkin_mes_sheet')), findsNothing, reason: 'nunca uma folha por cima');
      expect(find.byKey(const Key('checkin_mes_dia_1')), findsOneWidget);
      expect(find.byKey(const Key('checkin_mes_dia_30')), findsOneWidget);
      expect(find.byKey(const Key('checkin_mes_dia_31')), findsNothing);
      for (final d in [7, 10, 15, 30]) {
        expect(find.byKey(Key('checkin_mes_marco_$d')), findsOneWidget, reason: 'marco do dia $d com o ícone');
      }
      expect(find.text('Estás no dia 12 de 30.'), findsOneWidget);
      Color cor(int d) =>
          (t.widget<Container>(find.byKey(Key('checkin_mes_dia_$d'))).decoration! as BoxDecoration).color!;
      expect(cor(11), AppColors.primary, reason: 'feito');
      expect(cor(12), isNot(AppColors.primary), reason: 'hoje, por fazer');
      expect(cor(13), Colors.white);
      await t.tap(find.byKey(const Key('btn_checkin_mes')));
      await t.pumpAndSettle();
      expect(find.byKey(const Key('checkin_mes_calendario')), findsNothing, reason: 'a mesma seta fecha');
    });

    testWidgets('chegou a um degrau: festa uma vez, os dois botões, e Continuar esconde a escolha', (t) async {
      var festas = 0;
      var continuou = 0;
      Map<String, dynamic> pendente() => _estadoJson(
          escada: _escadaJson(guardado: _guardadoSalgados, decisao: 'pendente', pendente: true, proximo: _proximoAcai));
      var estado = CheckinPremiosEstado.fromJson(pendente());
      Widget w() => cartao(
            premios: () async => estado,
            festa: () async => festas++,
            continuar: () async {
              continuou++;
              final depois = _estadoJson(
                  escada: _escadaJson(guardado: _guardadoSalgados, decisao: 'continuar', proximo: _proximoAcai));
              estado = CheckinPremiosEstado.fromJson(depois);
              return CheckinEscadaResultado.fromJson({'ok': true, 'estado': depois});
            },
          );
      await t.pumpWidget(w());
      await t.pump();
      await t.pump();
      await t.pump();
      expect(find.byKey(const Key('checkin_escada_escolha')), findsOneWidget);
      expect(find.text('Levantar agora: 2 salgados da Keli (a tua sequência volta ao dia 1)'), findsOneWidget);
      expect(find.text('Continuar: no dia 15 trocas por um açaí do Goola'), findsOneWidget);
      expect(find.text(_textoEscada), findsOneWidget, reason: 'o texto da escada por baixo');
      expect(find.byKey(const Key('checkin_confete')), findsOneWidget);
      expect(festas, 1);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('checkin_escada_festa_vista'), 'salgados|2026-10-29T10:00:00+00:00');
      await t.pumpAndSettle();

      await t.tap(find.byKey(const Key('btn_escada_continuar')));
      await t.pumpAndSettle();
      expect(continuou, 1);
      expect(find.byKey(const Key('checkin_escada_escolha')), findsNothing, reason: 'escolheu continuar');
      expect(find.byKey(const Key('checkin_escada_guardado')), findsOneWidget);
      expect(find.text('Tens guardado: 2 salgados da Keli até 28/11'), findsOneWidget);

      // Volta a abrir com o MESMO degrau por decidir: não há segunda festa.
      estado = CheckinPremiosEstado.fromJson(pendente());
      await t.pumpWidget(const SizedBox());
      await t.pumpWidget(w());
      await t.pump();
      await t.pump();
      await t.pump();
      expect(find.byKey(const Key('checkin_escada_escolha')), findsOneWidget);
      expect(festas, 1, reason: 'uma festa por guardado_em');
      await t.pumpAndSettle();
    });

    testWidgets('Levantar agora: chama levantar, a escolha some e aparece "Ganhaste… Ver"', (t) async {
      var levantou = 0;
      var estado = _estado(
          escada: _escadaJson(guardado: _guardadoSalgados, decisao: 'pendente', pendente: true, proximo: _proximoAcai));
      await t.pumpWidget(cartao(
        premios: () async => estado,
        levantar: () async {
          levantou++;
          final depois = _estadoJson(
            dias: 0,
            diaMarco: 0,
            escada: _escadaJson(proximo: {'chave': 'salgados', 'dia': 10, 'titulo': '2 salgados da Keli', 'faltam': 10}),
          );
          estado = CheckinPremiosEstado.fromJson(depois);
          return CheckinEscadaResultado.fromJson({'ok': true, 'vale': _vale('v9', 'por_usar'), 'estado': depois});
        },
      ));
      await t.pumpAndSettle();
      await t.tap(find.byKey(const Key('btn_escada_levantar')));
      await t.pumpAndSettle();
      expect(levantou, 1);
      expect(find.byKey(const Key('checkin_escada_escolha')), findsNothing);
      expect(find.byKey(const Key('checkin_escada_guardado')), findsNothing);
      expect(find.text('Ganhaste 2 salgados da Keli!'), findsOneWidget);
      expect(find.byKey(const Key('checkin_dia_1')), findsOneWidget, reason: 'a sequência volta ao Dia 1');
      expect(dentro('checkin_dia_1', find.byIcon(Icons.check_rounded)), findsNothing);
    });

    testWidgets('erro ao levantar: mensagem curta em PT-PT, sem rebentar', (t) async {
      await t.pumpWidget(cartao(
        premios: () async => _estado(
            escada: _escadaJson(guardado: _guardadoSalgados, decisao: 'continuar', proximo: _proximoAcai)),
        levantar: () async => const CheckinEscadaResultado(ok: false, reason: 'expirado'),
      ));
      await t.pumpAndSettle();
      await t.tap(find.byKey(const Key('btn_escada_levantar_guardado')));
      await t.pumpAndSettle();
      expect(find.byKey(const Key('checkin_escada_erro')), findsOneWidget);
      expect(find.text('Este prémio já expirou.'), findsOneWidget);
    });

    testWidgets('cabe em 320 px, em PT e em EN, com o calendário aberto e a escolha do degrau', (t) async {
      t.view.physicalSize = const Size(320, 1600);
      t.view.devicePixelRatio = 1.0;
      addTearDown(t.view.reset);
      addTearDown(() => BoraLang.notifier.value = AppLang.pt);
      for (final lingua in [AppLang.pt, AppLang.en]) {
        BoraLang.notifier.value = lingua;
        await t.pumpWidget(cartao(
          premios: () async => _estado(
              escada: _escadaJson(guardado: _guardadoSalgados, decisao: 'pendente', pendente: true, proximo: _proximoAcai)),
        ));
        await t.pumpAndSettle();
        await t.tap(find.byKey(const Key('btn_checkin_mes')));
        await t.pumpAndSettle();
        expect(find.byKey(const Key('checkin_mes_calendario')), findsOneWidget);
        expect(find.byKey(const Key('checkin_escada_escolha')), findsOneWidget);
        expect(t.takeException(), isNull, reason: 'sem overflow em ${lingua.name}');
      }
    });

    testWidgets('sem escada (servidor antigo) ou escada desligada: o cartão fica como antes', (t) async {
      for (final p in [
        _estado(),
        _estado(
            escada: _escadaJson(
                ativa: false, guardado: _guardadoSalgados, decisao: 'pendente', pendente: true, proximo: _proximoAcai)),
      ]) {
        var festas = 0;
        await t.pumpWidget(cartao(premios: () async => p, festa: () async => festas++));
        await t.pump();
        await t.pump();
        expect(find.byKey(const Key('checkin_diario_card')), findsOneWidget);
        expect(find.byKey(const Key('btn_checkin')), findsOneWidget);
        expect(find.byKey(const Key('checkin_escada_escolha')), findsNothing);
        expect(find.byKey(const Key('checkin_escada_guardado')), findsNothing);
        expect(find.byKey(const Key('btn_escada_levantar')), findsNothing);
        expect(festas, 0);
      }
    });

    testWidgets('Os meus prémios: a regra da escada, o guardado com Levantar e os degraus', (t) async {
      var levantou = 0;
      await t.pumpWidget(MaterialApp(
        home: CheckinPremiosScreen(
          carregar: () async => _estado(
              dias: 12,
              escada: _escadaJson(
                  guardado: _guardadoSalgados, decisao: 'continuar', proximo: {..._proximoAcai, 'faltam': 3})),
          levantarEscada: () async {
            levantou++;
            return CheckinEscadaResultado.fromJson({'ok': true, 'vale': _vale('v9', 'por_usar')});
          },
        ),
      ));
      await t.pumpAndSettle();
      expect(find.byKey(const Key('premios_escada_texto')), findsOneWidget);
      expect(find.text(_textoEscada), findsOneWidget);
      expect(find.text('Tens guardado: 2 salgados da Keli até 28/11'), findsOneWidget);
      for (final d in [10, 15, 30]) {
        expect(find.byKey(Key('degrau_$d')), findsOneWidget);
      }
      expect(find.byKey(const Key('degrau_7')), findsNothing, reason: 'os 7 dias são só tokens');
      expect(t.widget<Text>(find.byKey(const Key('degrau_10_etiqueta'))).data, 'Guardado');
      expect(t.widget<Text>(find.byKey(const Key('degrau_15_etiqueta'))).data, 'Próximo · faltam 3 dias');
      expect(find.byKey(const Key('degrau_30_etiqueta')), findsNothing);
      await t.tap(find.byKey(const Key('btn_escada_levantar_ecra')));
      await t.pumpAndSettle();
      expect(levantou, 1);
      expect(find.text('Prémio levantado! Já está em "Por usar".'), findsOneWidget);
    });
  });
}
