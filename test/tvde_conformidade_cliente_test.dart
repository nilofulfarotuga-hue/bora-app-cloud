import 'package:bora_app/services/tvde_conformidade_service.dart';
import 'package:bora_app/widgets/tvde/tvde_payment_selector.dart';
import 'package:bora_app/widgets/tvde/tvde_preco_discriminado.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Conformidade TVDE (Lei 59/2026) — lado do CLIENTE.
/// Preço discriminado antes de pedir, só pagamento eletrónico e leitura dos
/// interruptores. Tudo sem rede: os widgets recebem os mapas já prontos.

Map<String, dynamic> _breakdown({
  bool combinada = false,
  num? ivaPct,
  num? ivaCents,
  num? intermPct = 20,
}) =>
    {
      'distancia_km': 9.0,
      'tarifa_base_cents': combinada ? null : 400,
      'km_incluidos': combinada ? null : 6,
      'km_extra': combinada ? null : 3,
      'preco_km_extra_cents': combinada ? null : 50,
      'preco_por_minuto_cents': 0,
      'fator_dinamico': 1.0,
      'tarifa_combinada': combinada,
      'intermediacao_cents': 110,
      'intermediacao_pct': intermPct,
      'iva_pct': ivaPct,
      'iva_cents': ivaCents,
      'total_cents': 550,
      'preco_fixo': false,
      'nota': 'Estimativa. O preço final calcula-se com a mesma tabela.',
    };

Future<void> _pumpPreco(WidgetTester tester, Map<String, dynamic> dados,
    {bool aberto = true}) async {
  await tester.pumpWidget(MaterialApp(
    home: Scaffold(
      body: SingleChildScrollView(
        child: TvdePrecoDiscriminado(dados: dados, inicialmenteAberto: aberto),
      ),
    ),
  ));
}

Future<void> _pumpSelector(WidgetTester tester, {bool? cashEnabled}) async {
  await tester.pumpWidget(MaterialApp(
    home: Scaffold(
      body: cashEnabled == null
          ? TvdePaymentSelector(
              current: 'mbway',
              cardEnabled: true,
              onChanged: (_) {},
            )
          : TvdePaymentSelector(
              current: 'mbway',
              cardEnabled: true,
              cashEnabled: cashEnabled,
              onChanged: (_) {},
            ),
    ),
  ));
}

void main() {
  group('TvdePrecoDiscriminado', () {
    testWidgets('mostra as linhas da tarifa normal', (tester) async {
      await _pumpPreco(tester, _breakdown());
      expect(find.text('Tarifa base (até 6 km)'), findsOneWidget);
      expect(find.text('€4.00'), findsOneWidget);
      expect(find.text('Km extra: 3 × €0.50/km'), findsOneWidget);
      expect(find.text('€1.50'), findsOneWidget);
      expect(find.text('Preço por tempo'), findsOneWidget);
      expect(find.text('o preço não depende do tempo'), findsOneWidget);
      expect(find.text('Tarifa dinâmica'), findsOneWidget);
      expect(find.text('sem tarifa dinâmica'), findsOneWidget);
      expect(find.text('Total estimado'), findsOneWidget);
      expect(find.text('€5.50'), findsOneWidget);
      expect(find.byKey(const Key('tvde_preco_combinado')), findsNothing);
    });

    testWidgets('taxa de intermediação em % e em €', (tester) async {
      await _pumpPreco(tester, _breakdown());
      expect(find.text('Taxa de intermediação (20 %)'), findsOneWidget);
      expect(find.text('€1.10'), findsOneWidget);
    });

    testWidgets('percentagem com casa decimal', (tester) async {
      await _pumpPreco(tester, _breakdown(intermPct: 12.5));
      expect(find.text('Taxa de intermediação (12.5 %)'), findsOneWidget);
    });

    testWidgets('sem iva_pct → sem linha de IVA', (tester) async {
      await _pumpPreco(tester, _breakdown());
      expect(find.byKey(const Key('tvde_preco_iva')), findsNothing);
      expect(find.textContaining('IVA'), findsNothing);
    });

    testWidgets('com iva_pct → linha de IVA com % e €', (tester) async {
      await _pumpPreco(tester, _breakdown(ivaPct: 6, ivaCents: 31));
      expect(find.byKey(const Key('tvde_preco_iva')), findsOneWidget);
      expect(find.text('IVA incluído (6 %)'), findsOneWidget);
      expect(find.text('€0.31'), findsOneWidget);
    });

    testWidgets('tarifa combinada → "Preço combinado para ti" sem base/km',
        (tester) async {
      await _pumpPreco(tester, _breakdown(combinada: true));
      expect(find.text('Preço combinado para ti'), findsOneWidget);
      expect(find.byKey(const Key('tvde_preco_base')), findsNothing);
      expect(find.byKey(const Key('tvde_preco_km_extra')), findsNothing);
    });

    testWidgets('nasce fechado e abre com "Ver como é calculado"',
        (tester) async {
      await _pumpPreco(tester, _breakdown(), aberto: false);
      expect(find.text('Ver como é calculado'), findsOneWidget);
      expect(find.text('Total estimado'), findsNothing);
      await tester.tap(find.byKey(const Key('tvde_preco_discriminado_abrir')));
      await tester.pump();
      expect(find.text('Total estimado'), findsOneWidget);
    });
  });

  group('TvdePaymentSelector · só pagamento eletrónico', () {
    testWidgets('cashEnabled:false → sem Dinheiro', (tester) async {
      await _pumpSelector(tester, cashEnabled: false);
      expect(find.byKey(const Key('tvde_pay_cash')), findsNothing);
      expect(find.byKey(const Key('tvde_pay_card')), findsOneWidget);
      expect(find.byKey(const Key('tvde_pay_mbway')), findsOneWidget);
    });

    testWidgets('por defeito (sem o parâmetro) → Dinheiro continua',
        (tester) async {
      await _pumpSelector(tester);
      expect(find.byKey(const Key('tvde_pay_cash')), findsOneWidget);
      expect(find.byKey(const Key('tvde_pay_so_eletronico')), findsNothing);
    });
  });

  group('TvdeConformidadeConfig.fromMap', () {
    test('lê todos os interruptores', () {
      final c = TvdeConformidadeConfig.fromMap({
        'mestre': true,
        'so_pagamento_eletronico': true,
        'avaliar_passageiro_desativado': true,
        'limite_horas_ativo': true,
        'bloqueio_ativo': true,
        'opcoes_cliente': true,
        'iva_discriminar': true,
        'limite_horas': 12,
        'livro_reclamacoes_url': 'https://exemplo.pt/livro',
        'email_contacto': 'geral@exemplo.pt',
      });
      expect(c.mestre, isTrue);
      expect(c.soPagamentoEletronico, isTrue);
      expect(c.avaliarPassageiroDesativado, isTrue);
      expect(c.limiteHorasAtivo, isTrue);
      expect(c.bloqueioAtivo, isTrue);
      expect(c.opcoesCliente, isTrue);
      expect(c.ivaDiscriminar, isTrue);
      expect(c.limiteHoras, 12);
      expect(c.livroReclamacoesUrl, 'https://exemplo.pt/livro');
      expect(c.emailContacto, 'geral@exemplo.pt');
    });

    test('mapa vazio → tudo desligado (o comportamento de sempre)', () {
      final c = TvdeConformidadeConfig.fromMap(const {});
      expect(c.mestre, isFalse);
      expect(c.soPagamentoEletronico, isFalse);
      expect(c.opcoesCliente, isFalse);
      expect(c.ivaDiscriminar, isFalse);
      expect(c.limiteHoras, 10);
      expect(c.livroReclamacoesUrl, 'https://www.livroreclamacoes.pt/Inicio/');
      expect(c.emailContacto, isNull);
    });

    test('valores não-booleanos não ligam interruptores', () {
      final c = TvdeConformidadeConfig.fromMap(
          {'so_pagamento_eletronico': 'true', 'opcoes_cliente': 1});
      expect(c.soPagamentoEletronico, isFalse);
      expect(c.opcoesCliente, isFalse);
    });
  });
}
