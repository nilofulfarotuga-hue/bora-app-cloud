// Missão farmacias-2026-11-11 — testes sem rede dos ecrãs da receita.
import 'dart:io';

import 'package:bora_app/models/pedido_prescricao.dart';
import 'package:bora_app/screens/admin/admin_menu_registry.dart';
import 'package:bora_app/screens/farmacia/prescricao_estado_screen.dart';
import 'package:bora_app/screens/partner/farmacia/parceiro_prescricoes_screen.dart';
import 'package:bora_app/widgets/farmacia/farmacia_botoes_topo.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

PedidoPrescricao _pedido(String estado, {String tipo = 'receita', bool demo = false}) => PedidoPrescricao.fromMap({
      'id': '00000000-0000-4000-8000-000000000001',
      'created_at': '2026-11-13T10:00:00Z',
      'restaurant_id': 'farmacia-se-guarda',
      'user_id': '4f61dd31-5e9e-4a7c-a557-7d53d2ceded7',
      'tipo': tipo,
      'estado': estado,
      'receita_numero': tipo == 'receita' ? '1234567890123456789' : null,
      'receita_codigo_acesso': tipo == 'receita' ? '123456' : null,
      'descricao': tipo == 'pedido_livre' ? 'Creme para pele atópica' : null,
      'morada': 'Rua do Comércio 10, Guarda',
      'valor_medicamentos_cents': estado == 'enviado' ? null : 2350,
      'itens_disponiveis': estado == 'aceite_parcial' ? 'Só o Brufen' : null,
      'tempo_preparacao_min': 15,
      'motivo_recusa': estado == 'recusado' ? 'sem_stock' : null,
      'volta_a_ter': estado == 'recusado' ? 'sexta-feira' : null,
      'expira_em': '2026-11-13T10:30:00Z',
      'total_cents': estado == 'confirmado' ? 2950 : null,
      'taxa_servico_cents': 600,
      'metodo_pagamento': estado == 'confirmado' ? 'cash' : null,
      'codigo_levantamento': estado == 'confirmado' ? 'K7Q2MX' : null,
      'codigo_entrega': estado == 'confirmado' ? '4821' : null,
      'is_demo': demo,
      'consentimento_versao': 'v1-2026-11-11',
      'consentimento_em': '2026-11-13T10:00:00Z',
    });

Widget _app(Widget filho) => MaterialApp(home: Scaffold(body: filho));

/// Ecrã de telemóvel alto (a lista do estado não fica fora do ecrã).
void _tamanho(WidgetTester t, {double largura = 360, double altura = 1600}) {
  t.view.physicalSize = Size(largura, altura);
  t.view.devicePixelRatio = 1.0;
  addTearDown(t.view.reset);
}

void main() {
  testWidgets('cliente: aceite mostra valores e os três pagamentos', (t) async {
    _tamanho(t);
    await t.pumpWidget(_app(PrescricaoEstadoCorpo(
      pedido: _pedido('aceite'),
      taxaServicoCents: 600,
      farmaciaNome: 'Farmácia da Sé',
      agora: () => DateTime.parse('2026-11-13T10:05:00Z'),
    )));
    expect(find.text('A farmácia tem os seus medicamentos'), findsOneWidget);
    expect(find.text('23,50 €'), findsOneWidget);
    expect(find.text('29,50 €'), findsOneWidget);
    expect(find.text('Cartão'), findsOneWidget);
    expect(find.text('MB Way'), findsOneWidget);
    expect(find.text('Dinheiro na entrega'), findsOneWidget);
    expect(find.text('Confirmar e pagar'), findsOneWidget);
    expect(t.takeException(), isNull);
  });

  testWidgets('cliente: parcial pede "Quero só o que há"', (t) async {
    _tamanho(t);
    await t.pumpWidget(_app(PrescricaoEstadoCorpo(pedido: _pedido('aceite_parcial'), taxaServicoCents: 600, farmaciaNome: 'Farmácia da Sé')));
    expect(find.text('A farmácia tem parte do seu pedido'), findsOneWidget);
    expect(find.textContaining('Só o Brufen'), findsOneWidget);
    expect(find.text('Quero só o que há'), findsOneWidget);
  });

  testWidgets('cliente: recusado diz o motivo e que nada foi cobrado', (t) async {
    _tamanho(t);
    await t.pumpWidget(_app(PrescricaoEstadoCorpo(pedido: _pedido('recusado'), taxaServicoCents: 600, farmaciaNome: 'Farmácia da Sé')));
    expect(find.text('A farmácia não tem o seu pedido'), findsOneWidget);
    expect(find.textContaining('Sem stock'), findsOneWidget);
    expect(find.textContaining('Não foi cobrado nada.'), findsOneWidget);
    expect(find.textContaining('sexta-feira'), findsOneWidget);
  });

  testWidgets('cliente: confirmado em demonstração mostra a faixa e o código de 4 dígitos', (t) async {
    _tamanho(t);
    await t.pumpWidget(_app(PrescricaoEstadoCorpo(pedido: _pedido('confirmado', demo: true), taxaServicoCents: 600, farmaciaNome: 'Farmácia da Sé')));
    expect(find.textContaining('Demonstração: nada foi cobrado'), findsOneWidget);
    expect(find.text('4821'), findsOneWidget);
    expect(find.textContaining('K7Q2MX'), findsOneWidget);
    expect(find.text('Repetir todos os meses'), findsOneWidget);
  });

  testWidgets('cliente: à espera mostra o tempo e o cancelar, sem estouros a 360 px', (t) async {
    _tamanho(t);
    await t.pumpWidget(_app(PrescricaoEstadoCorpo(
      pedido: _pedido('enviado'),
      taxaServicoCents: 600,
      farmaciaNome: 'Farmácia Teixeira',
      agora: () => DateTime.parse('2026-11-13T10:05:00Z'),
    )));
    expect(find.text('Enviado à Farmácia Teixeira'), findsOneWidget);
    expect(find.textContaining('25 min'), findsOneWidget);
    expect(find.text('Cancelar pedido'), findsOneWidget);
    expect(t.takeException(), isNull);
  });

  testWidgets('botões do topo: escondidos não desenham nada; visíveis mostram os três', (t) async {
    _tamanho(t);
    await t.pumpWidget(_app(const FarmaciaBotoesTopo(restaurantId: 'x', storeName: 'Farmácia da Sé', visivelParaTeste: false)));
    expect(find.text('Tenho receita'), findsNothing);
    await t.pumpWidget(_app(const FarmaciaBotoesTopo(key: ValueKey('v'), restaurantId: 'x', storeName: 'Farmácia da Sé', visivelParaTeste: true)));
    expect(find.text('Tenho receita'), findsOneWidget);
    expect(find.text('Não encontra o produto? Peça aqui'), findsOneWidget);
    expect(find.text('Repetir todos os meses'), findsOneWidget);
    expect(t.takeException(), isNull);
  });

  testWidgets('farmácia: à espera tem os dois botões e "Tenho, aceito" abre o valor', (t) async {
    _tamanho(t, largura: 390);
    await t.pumpWidget(_app(ParceiroPrescricaoCorpo(pedido: _pedido('enviado'), semImagens: true)));
    expect(find.text('Tenho, aceito'), findsOneWidget);
    expect(find.text('Não tenho'), findsOneWidget);
    expect(find.text('1234567890123456789'), findsOneWidget);
    await t.tap(find.text('Tenho, aceito'));
    await t.pumpAndSettle();
    expect(find.text('Valor total a pagar pelo cliente (€)'), findsOneWidget);
    expect(find.text('Enviar ao cliente'), findsOneWidget);
  });

  testWidgets('farmácia: "Não tenho" abre os motivos', (t) async {
    _tamanho(t, largura: 390);
    await t.pumpWidget(_app(ParceiroPrescricaoCorpo(pedido: _pedido('enviado'), semImagens: true)));
    await t.tap(find.text('Não tenho'));
    await t.pumpAndSettle();
    expect(find.text('Sem stock'), findsOneWidget);
    expect(find.text('Receita inválida ou caducada'), findsOneWidget);
    expect(find.text('Avisar o cliente'), findsOneWidget);
  });

  testWidgets('farmácia: confirmado mostra o código de levantamento e a faixa de demonstração', (t) async {
    _tamanho(t, largura: 390);
    await t.pumpWidget(_app(ParceiroPrescricaoCorpo(pedido: _pedido('confirmado', demo: true), semImagens: true)));
    expect(find.text('O cliente confirmou'), findsOneWidget);
    expect(find.text('K7Q2MX'), findsOneWidget);
    expect(find.textContaining('Demonstração: nenhum estafeta'), findsOneWidget);
    expect(find.text('Tenho, aceito'), findsNothing);
  });

  test('valor escrito pela farmácia vira cêntimos certos', () {
    expect(centsDeTexto('23,50'), 2350);
    expect(centsDeTexto('23.5'), 2350);
    expect(centsDeTexto('12'), 1200);
    expect(centsDeTexto('12,345'), 1235);
    expect(centsDeTexto(''), isNull);
    expect(centsDeTexto('abc'), isNull);
    expect(centsDeTexto('0'), isNull);
  });

  test('euros em PT-PT', () {
    expect(eurosDeCents(2950), '29,50 €');
    expect(eurosDeCents(5), '0,05 €');
    expect(eurosDeCents(null), '—');
  });

  test('o painel admin tem Farmácias e Pedidos de receita na busca', () {
    final todos = adminMenuAllItems();
    for (final q in ['farmacia', 'receita', 'teixeira']) {
      expect(todos.where((i) => i.matches(q)).map((i) => i.id), contains('farmacias'), reason: q);
    }
    expect(todos.where((i) => i.matches('receita')).map((i) => i.id), contains('pedidos_receita'));
  });

  test('os avisos da receita estão na lista de avisos persistentes', () {
    final s = File('lib/services/notification_service.dart').readAsStringSync();
    for (final tipo in ['prescricao_nova', 'prescricao_lembrete', 'prescricao_resposta', 'farmacia_lembrete_mensal']) {
      expect(s.contains("'$tipo'"), isTrue, reason: tipo);
    }
    expect(s.contains('..._kTiposFarmacia'), isTrue);
  });
}
