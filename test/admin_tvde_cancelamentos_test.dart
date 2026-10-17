// Painel admin (PT-BR) — cancelamento tardio TVDE (17/10/2026).
//
// O ecrã "Cancelamentos — Bora Motorista" passa a juntar às corridas canceladas
// as compensações ao motorista (`admin_tvde_cancel_comps`), com um resumo no
// topo, o botão "Compensar motorista" e o CSV. Estes testes prendem:
//  (iv) a junção cancelamentos + compensações e os totais;
//  (v)  o CSV (separador ";", euros com vírgula);
//  e os textos PT-BR (cobrança, semana, pagamento, regra, erros do botão), a
//  leitura do valor em euros, e a lista de corridas (resumo financeiro e
//  "nada a devolver" quando a corrida foi cobrada por inteiro).
import 'dart:io';

import 'package:bora_app/screens/admin/admin_platform_settings_screen.dart'
    show erroValorEmCentimos;
import 'package:bora_app/screens/admin/admin_tvde_cancellations_screen.dart';
import 'package:bora_app/screens/admin/admin_tvde_pagamentos_screen.dart'
    show ficouComTudo;
import 'package:bora_app/screens/admin/admin_tvde_rides_screen.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

Map<String, dynamic> _comp(String ride,
        {int fee = 700,
        int driver = 375,
        String via = 'carteira',
        String origem = 'regra',
        String? semana}) =>
    {
      'ride_id': ride,
      'created_at': '2026-10-17T14:00:00+00:00',
      'driver_id': 'd-$ride',
      'driver_name': 'Ney',
      'client_name': 'Cliente $ride',
      'fee_cents': fee,
      'driver_cents': driver,
      'bora_cents': fee - driver,
      'collected_via': via,
      'payment_method': via == 'pagamento_retido' ? 'mbway' : 'cash',
      'origem': origem,
      'reason': 'motivo',
      'ride_status': 'cancelada_cliente',
      'payment_status': via == 'pagamento_retido' ? 'kept_cancel_fee' : null,
      'est_fare_cents': fee,
      'client_wallet_cents': -700,
      'week_status': semana,
    };

void main() {
  group('(iv) junção e totais', () {
    final cancelamentos = [
      {'id': 'r1', 'status': 'cancelada_cliente', 'cancel_fee_cents': 700},
      {'id': 'r2', 'status': 'cancelada_motorista', 'cancel_fee_cents': 0},
      {'id': 'r3', 'status': 'no_show', 'cancel_fee_cents': 0},
    ];

    test('cada corrida recebe a SUA compensação, pelo id', () {
      final juntas = juntarCancelamentosECompensacoes(cancelamentos, [
        _comp('r1'),
        _comp('r3', fee: 0, driver: 250, via: 'admin', origem: 'admin'),
        _comp('r9'), // fora da lista de cima: não aparece em lado nenhum aqui
      ]);
      expect(juntas.length, 3);
      expect((juntas[0]['_comp'] as Map)['driver_cents'], 375);
      expect(juntas[1].containsKey('_comp'), isFalse);
      expect((juntas[2]['_comp'] as Map)['origem'], 'admin');
      expect(juntas[0]['id'], 'r1', reason: 'a ordem da lista não muda');
      // Sem compensações (a segunda RPC falhou): fica tudo como hoje.
      expect(juntarCancelamentosECompensacoes(cancelamentos, const []),
          cancelamentos);
    });

    test('resumo: cobrado, pago aos motoristas, Bora (com sinal) e NÃO COBRADO',
        () {
      final r = resumirCompensacoes([
        _comp('a', fee: 700, driver: 375), // carteira: Bora +3,25
        _comp('b', fee: 300, driver: 375, via: 'pagamento_retido'), // Bora −0,75
        _comp('c', fee: 900, driver: 375, via: 'nao_cobrado'), // Bora −3,75
        _comp('d', fee: 0, driver: 200, via: 'admin', origem: 'admin'), // −2,00
      ]);
      expect(r.n, 4);
      expect(r.cobradoCents, 1000, reason: 'só o que entrou mesmo');
      expect(r.motoristasCents, 1325);
      expect(r.boraCents, -325, reason: 'pode ser negativo');
      expect(r.naoCobradas, 1);
      final vazio = resumirCompensacoes(const []);
      expect([vazio.n, vazio.cobradoCents, vazio.boraCents], [0, 0, 0]);
    });

    test('valores em euros com sinal', () {
      expect(eurosBr(375), '3,75 €');
      expect(eurosBr(-325), '−3,25 €');
      expect(eurosBr(0), '0,00 €');
    });
  });

  group('(v) CSV', () {
    test('separador ";", euros com vírgula, compensação na linha certa', () {
      final juntas = juntarCancelamentosECompensacoes([
        {
          'id': 'r1',
          'status': 'cancelada_cliente',
          'cancel_reason': 'mudei de ideias; desculpa',
          'cancel_fee_cents': 700,
          'est_fare_cents': 700,
          'created_at': '2026-10-17T14:00:00+00:00',
          '_pag_metodo': 'cash',
        },
        {
          'id': 'r2',
          'status': 'cancelada_motorista',
          'cancel_fee_cents': 0,
          'est_fare_cents': 520,
          'created_at': '2026-10-17T15:00:00+00:00',
        },
      ], [
        _comp('r1')
      ]);
      final csv = csvCancelamentos(juntas);
      final linhas = csv.trim().split('\n');
      expect(linhas.length, 3);
      expect(linhas.first.split(';').first, 'Corrida');
      expect(linhas.first, contains('Compensação ao motorista (€)'));
      expect(linhas[1], startsWith('r1;'));
      expect(linhas[1], contains(';7,00;'));
      expect(linhas[1], contains(';3,75;'));
      expect(linhas[1], contains('Debitado na carteira'));
      expect(linhas[1], contains('"mudei de ideias; desculpa"'),
          reason: 'o ";" do motivo vai entre aspas');
      expect(linhas[2], startsWith('r2;'));
      expect(linhas[2], contains(';5,20;'));
    });
  });

  group('textos PT-BR', () {
    test('como foi cobrado e estado da semana', () {
      expect(rotuloCobranca('pagamento_retido'), 'Pagamento online retido');
      expect(rotuloCobranca('carteira'), 'Debitado na carteira');
      expect(rotuloCobranca('nao_cobrado'), 'NÃO COBRADO (carteira no limite)');
      expect(rotuloCobranca('admin'), 'Compensação manual do admin');
      expect(rotuloSemana(null), contains('ainda aberta'));
      expect(rotuloSemana('paid'), contains('paga'));
      expect(rotuloSemana('pending'), contains('pendente'));
    });

    test('pagamento só aparece quando há dados', () {
      expect(rotuloPagamento(null, null), isNull);
      expect(rotuloPagamento('cash', null), 'Dinheiro');
      expect(rotuloPagamento('mbway', 'kept_cancel_fee'),
          'MB Way · valor retido (taxa de cancelamento)');
      expect(rotuloPagamento('card', 'refunded'), startsWith('Cartão · devolvido'));
    });

    test('frase da regra com os valores das definições', () {
      expect(
          fraseDaRegra(const RegraCancelamento(
              ligada: true,
              graceSeconds: 180,
              driverFeeCents: 375,
              fixedFeeCents: 250)),
          allOf(contains('mais de 3 min'), contains('3,75 €'),
              contains('2,50 €'), contains('corrida inteira')));
      expect(
          fraseDaRegra(const RegraCancelamento(
              ligada: false,
              graceSeconds: 180,
              driverFeeCents: 375,
              fixedFeeCents: 250)),
          contains('DESLIGADA'));
    });

    test('Definições: chave em cêntimos só aceita número inteiro', () {
      expect(erroValorEmCentimos('tvde_cancel_driver_fee_cents', 3.75),
          contains('375 = 3,75 €'));
      expect(erroValorEmCentimos('tvde_cancel_driver_fee_cents', 4),
          contains('euros'));
      expect(erroValorEmCentimos('tvde_cancel_driver_fee_cents', 375), isNull);
      expect(erroValorEmCentimos('tvde_cancel_driver_fee_cents', 0), isNull,
          reason: '0 desliga a compensação');
      expect(erroValorEmCentimos('cancel_fee_before_dispatch_cents', 2.5),
          isNotNull);
      expect(erroValorEmCentimos('cancel_grace_seconds', 90.5), isNull);
      expect(erroValorEmCentimos('cancel_fee_after_pickup_ratio', 0.5), isNull);
    });

    test('valor em euros escrito pelo admin', () {
      expect(centsDoTexto('3,75'), 375);
      expect(centsDoTexto('3.75'), 375);
      expect(centsDoTexto(' 50 '), 5000);
      expect(centsDoTexto('0,01'), 1);
      expect(centsDoTexto('0'), isNull);
      expect(centsDoTexto('50,01'), isNull);
      expect(centsDoTexto('abc'), isNull);
      expect(centsDoTexto(''), isNull);
    });

    test('cada erro do servidor tem frase própria', () {
      PostgrestException e(String m, [String? c]) =>
          PostgrestException(message: m, code: c);
      expect(erroDaCompensacao(e('reason_required')), contains('motivo'));
      expect(erroDaCompensacao(e('invalid_value')), contains('0,01'));
      expect(erroDaCompensacao(e('ride_not_found')), contains('não encontrada'));
      expect(erroDaCompensacao(e('ride_without_driver')),
          contains('não tem motorista'));
      expect(
          erroDaCompensacao(
              e('ride_not_cancelled_by_client: cancelada_motorista')),
          contains('cancelada_motorista'));
      expect(erroDaCompensacao(e('compensation_already_exists')),
          contains('já tem compensação'));
      expect(erroDaCompensacao(e('admin_required', '42501')),
          contains('admin'));
      expect(erroDaCompensacao(Exception('rede')), contains('rede'));
    });

    test('o botão só aparece onde a compensação é aceite pelo servidor', () {
      Map<String, dynamic> r(String st, {String? motorista = 'd1', bool comp = false}) => {
            'status': st,
            'driver_id': motorista,
            if (comp) '_comp': _comp('x'),
          };
      expect(podeCompensar(r('cancelada_cliente'), compensacoesOk: true), isTrue);
      expect(podeCompensar(r('no_show'), compensacoesOk: true), isTrue);
      expect(podeCompensar(r('cancelada_motorista'), compensacoesOk: true),
          isFalse);
      expect(
          podeCompensar(r('cancelada_cliente', motorista: null),
              compensacoesOk: true),
          isFalse);
      expect(
          podeCompensar(r('cancelada_cliente', comp: true),
              compensacoesOk: true),
          isFalse);
      expect(podeCompensar(r('cancelada_cliente'), compensacoesOk: false),
          isFalse,
          reason: 'sem saber se já existe, não se oferece o botão');
    });

    test('texto antigo do "sempre dinheiro, sem reembolso" saiu', () {
      final ecra = File('lib/screens/admin/admin_tvde_cancellations_screen.dart')
          .readAsStringSync();
      expect(ecra.contains('Dinheiro — sem reembolso'), isFalse);
      expect(ecra.contains('sem pré-pagamento, logo sem reembolso'), isFalse);
      expect(ecra.contains('janela de cortesia (180s)'), isFalse);
      expect(ecra, contains("'admin_tvde_cancel_comps'"));
      expect(ecra, contains("'admin_tvde_cancel_comp_grant'"));
      expect(ecra, contains('Vai para o acerto semanal do motorista. Não cobra nada ao cliente.'));
    });
  });

  group('lista de corridas (financeiro e reembolso)', () {
    test('o resumo tira à Bora o que foi para o motorista', () {
      final t = totaisDaLista([
        {
          'id': 'f1',
          'status': 'finalizada',
          'final_fare_cents': 1000,
          'driver_earn_cents': 750,
          'bora_cut_cents': 250,
        },
        {'id': 'c1', 'status': 'cancelada_cliente', 'cancel_fee_cents': 700},
        {'id': 'c2', 'status': 'cancelada_cliente', 'cancel_fee_cents': 250},
      ], {
        'c1': _comp('c1', fee: 700, driver: 375),
      });
      expect(t.fare, 1000);
      expect(t.driver, 750 + 375);
      expect(t.bora, 250 + 700 + 250 - 375);
      expect(t.cancelled, 2);
      expect(t.finished, 1);
      // [Revisão 17/10] Cobrança falhada (carteira no limite): a taxa não
      // entrou — a Bora fica só com o −3,75 € da compensação, como no cartão.
      final falhada = totaisDaLista([
        {'id': 'c9', 'status': 'cancelada_cliente', 'cancel_fee_cents': 900},
      ], {
        'c9': _comp('c9', fee: 900, driver: 375, via: 'nao_cobrado'),
      });
      expect(falhada.bora, -375);
      expect(
          linhaDaCompensacao(
              _comp('c9', fee: 900, driver: 375, via: 'nao_cobrado'),
              corrida: {'cancel_fee_cents': 900}),
          endsWith('a Bora fica com −3,75 €'));
      // Compensação manual numa corrida que pagou a taxa fixa de 2,50 €.
      expect(
          linhaDaCompensacao(
              _comp('c8', fee: 0, driver: 200, via: 'admin', origem: 'admin'),
              corrida: {'cancel_fee_cents': 250}),
          endsWith('a Bora fica com 0,50 €'));
      // Sem compensações carregadas: as contas de sempre.
      expect(totaisDaLista([
        {'id': 'c1', 'status': 'cancelada_cliente', 'cancel_fee_cents': 700},
      ], const {}).bora, 700);
    });

    test('corrida cobrada por inteiro: nada a devolver, sem botão', () {
      expect(
          cobradaPorInteiro({
            'reembolso_estado': 'pendente',
            'cancel_fee_cents': 700,
            'est_fare_cents': 700,
          }),
          isTrue);
      expect(
          cobradaPorInteiro({
            'reembolso_estado': 'so_taxa',
            'cancel_fee_cents': 820,
            'final_fare_cents': 820,
            'est_fare_cents': 700,
          }),
          isTrue);
      expect(
          cobradaPorInteiro({
            'reembolso_estado': 'pendente',
            'cancel_fee_cents': 250,
            'est_fare_cents': 700,
          }),
          isFalse,
          reason: 'taxa fixa: há 4,50 € por devolver');
      expect(
          cobradaPorInteiro({
            'reembolso_estado': 'falhou',
            'cancel_fee_cents': 700,
            'est_fare_cents': 700,
          }),
          isFalse,
          reason: 'falhou continua a pedir atenção');
      expect(
          cobradaPorInteiro({'reembolso_estado': 'pendente', 'cancel_fee_cents': 0}),
          isFalse);
      // Pagamentos TVDE: "Já estornado" não se diz de uma corrida que ficou
      // com o valor todo.
      expect(
          ficouComTudo({
            'payment_status': 'kept_cancel_fee',
            'cancel_fee_cents': 700,
            'est_fare_cents': 700,
          }),
          isTrue);
      expect(
          ficouComTudo({
            'payment_status': 'kept_cancel_fee',
            'cancel_fee_cents': 250,
            'est_fare_cents': 700,
          }),
          isFalse);
      expect(
          ficouComTudo({
            'payment_status': 'refunded',
            'cancel_fee_cents': 700,
            'est_fare_cents': 700,
          }),
          isFalse);
      expect(linhaDaCompensacao(_comp('c1', fee: 700, driver: 375)),
          'Cancelamento tardio · compensação ao motorista 3,75 € · a Bora fica com 3,25 €');
      expect(
          linhaDaCompensacao(_comp('c1', fee: 700, driver: 375, via: 'nao_cobrado')),
          'Cancelamento tardio · compensação ao motorista 3,75 € · a Bora fica com −3,75 €');
    });
  });
}
