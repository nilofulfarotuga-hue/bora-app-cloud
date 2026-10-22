import 'dart:async';

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

/// Ecrãs dos prémios dos marcos do check-in (Bloco D, 21/10/2026):
/// a seta do cartão abre a vista do mês, o prémio novo faz festa uma vez,
/// "Os meus prémios" diz o que falta, e o carrinho da loja certa oferece o vale.

CheckinPremiosEstado _estado({
  int dias = 10,
  List<Map<String, dynamic>>? vales,
  List<String> novos = const [],
  bool ativos = true,
}) =>
    CheckinPremiosEstado.fromJson({
      'ok': true,
      'marcos_ativos': ativos,
      'ciclo_dias': 30,
      'dias_seguidos': dias,
      'dia_marco': dias,
      'hoje_feito': true,
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
    });

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

  testWidgets('cartão do check-in: a semana igual, a seta abre o mês e o prémio novo faz festa uma vez', (t) async {
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
    expect(find.byKey(const Key('checkin_dia_7')), findsOneWidget, reason: 'a semana fica como hoje');
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
    expect(find.byKey(const Key('checkin_mes_sheet')), findsOneWidget);
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
}
