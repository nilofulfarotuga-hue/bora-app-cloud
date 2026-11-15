import 'dart:convert';
import 'dart:io';

import 'package:bora_app/l10n/strings_en.dart';
import 'package:bora_app/models/reservation_model.dart';
import 'package:bora_app/stores/partner_reservas_store.dart';
import 'package:flutter_test/flutter_test.dart';

/// fechar-tudo-15-11 (15/11/2026) — o parceiro rejeita uma reserva que o
/// cliente já pagou (pré-pagamento de 3 €) e a Bora devolve o dinheiro.
///
/// Antes: a RPC partner_decide_reservation punha a reserva em
/// 'rejected_refunded' e o ecrã dizia "Reserva rejeitada e reembolsada.", mas
/// nada era devolvido na Stripe. Agora, com pré-pagamento, a rejeição passa
/// pela Edge `partner-reject-reservation`. A lógica do dinheiro tem testes
/// próprios, sem rede, em
/// supabase/functions/partner-reject-reservation/logica_test.ts; aqui fica a
/// parte da app e a Edge lida pela fonte.
String _ler(String caminho) => File(caminho).readAsStringSync();

/// Pedaço da fonte entre [inicio] (inclusive) e [fim] (exclusive).
String _entre(String src, String inicio, String fim) {
  final a = src.indexOf(inicio);
  expect(a, isNonNegative, reason: 'não encontrei "$inicio"');
  final b = src.indexOf(fim, a + inicio.length);
  expect(b, greaterThan(a), reason: 'não encontrei "$fim" depois de "$inicio"');
  return src.substring(a, b);
}

ReservationModel _reserva({int cents = 300, String? pi = 'pi_teste'}) =>
    ReservationModel(
      id: '0b5c3e2a-1d4f-4a6b-9c8d-7e6f5a4b3c2d',
      restaurantId: 'rest-1',
      clientUserId: 'cliente-1',
      clientName: 'Cliente',
      clientPhone: '',
      people: 2,
      reservedFor: DateTime.utc(2026, 11, 20, 20),
      status: ReservationStatus.pending,
      prepaymentCents: cents,
      prepaymentPi: pi,
    );

const _ecraEmUso =
    'lib/screens/partner/reservations/partner_reservations_screen.dart';

void main() {
  group('com pré-pagamento, a rejeição passa pela Edge que devolve', () {
    test('pago vai pela Edge; sem pré-pagamento, a RPC de sempre', () {
      expect(PartnerReservasStore.precisaDeDevolucao(_reserva()), isTrue);
      expect(
          PartnerReservasStore.precisaDeDevolucao(_reserva(pi: null)), isTrue);
      expect(
          PartnerReservasStore.precisaDeDevolucao(_reserva(cents: 0)), isTrue);
      expect(
          PartnerReservasStore.precisaDeDevolucao(_reserva(cents: 0, pi: null)),
          isFalse);
      expect(
          PartnerReservasStore.precisaDeDevolucao(_reserva(cents: 0, pi: '  ')),
          isFalse);
    });

    test('o nome da Edge é o da pasta a publicar', () {
      expect(PartnerReservasStore.edgeRejeitarComDevolucao,
          'partner-reject-reservation');
      expect(
          File('supabase/functions/partner-reject-reservation/index.ts')
              .existsSync(),
          isTrue);
    });

    test('se a Edge falhar, NÃO cai na RPC (rejeitar sem devolver era o erro)',
        () {
      final metodo = _entre(
          _ler('lib/stores/partner_reservas_store.dart'),
          'Future<RecusaReserva> rejectReservation',
          'Future<Map<String, dynamic>> markSeated');
      expect('decideReservation('.allMatches(metodo), hasLength(1));
      final edge = metodo.indexOf('functions.invoke(');
      expect(edge, isNonNegative);
      expect(metodo.indexOf('decideReservation('), lessThan(edge));
      final depoisDaEdge = metodo.substring(edge);
      expect(depoisDaEdge, isNot(contains('decideReservation(')));
      expect(depoisDaEdge, isNot(contains('partner_decide_reservation')));
    });
  });

  group('a resposta da Edge vira uma frase verdadeira', () {
    test('succeeded: devolução pedida, com o valor em euros de Portugal', () {
      final r = RecusaReserva.daResposta({
        'success': true,
        'refund': {'result': 'succeeded', 'amount_cents': 300, 'amount': 3},
      });
      expect(r.devolucao, DevolucaoDaReserva.pedida);
      expect(r.valorCents, 300);
      expect(r.texto,
          'Reserva rejeitada. O cliente foi avisado e a devolução de 3,00 € já foi pedida.');
    });

    test('already_refunded: a devolução já tinha sido feita', () {
      final r = RecusaReserva.daResposta({
        'refund': {'result': 'already_refunded', 'amount_cents': 300},
      });
      expect(r.devolucao, DevolucaoDaReserva.jaFeita);
      expect(r.texto,
          'Reserva rejeitada. A devolução de 3,00 € ao cliente já tinha sido feita.');
    });

    test('not_applicable e not_paid: não havia dinheiro a devolver', () {
      for (final resultado in ['not_applicable', 'not_paid']) {
        final r = RecusaReserva.daResposta({
          'refund': {'result': resultado, 'amount_cents': 0},
        });
        expect(r.devolucao, DevolucaoDaReserva.semPrePagamento,
            reason: resultado);
        expect(r.texto, 'Reserva rejeitada. O cliente foi avisado.');
      }
    });

    test('failed ou resposta estranha: a equipa trata, nunca "já devolvido"',
        () {
      for (final data in <Object?>[
        {
          'refund': {'result': 'failed', 'amount_cents': 0},
        },
        {
          'refund': {'result': 'algo_novo'},
        },
        {'success': true},
        null,
        'texto solto',
      ]) {
        final r = RecusaReserva.daResposta(data, prePagamentoCents: 300);
        expect(r.devolucao, DevolucaoDaReserva.aCargoDaEquipa,
            reason: '$data');
        expect(r.texto,
            'Reserva rejeitada. O cliente foi avisado e a equipa Bora trata da devolução.');
      }
    });

    test('sem valor na resposta, mostra o pré-pagamento da reserva', () {
      final r = RecusaReserva.daResposta({
        'refund': {'result': 'succeeded'},
      }, prePagamentoCents: 300);
      expect(r.valorCents, 300);
    });

    test('sem pré-pagamento (a RPC de sempre)', () {
      expect(
          const RecusaReserva(devolucao: DevolucaoDaReserva.semPrePagamento)
              .texto,
          'Reserva rejeitada. O cliente foi avisado.');
    });
  });

  group('Edge ainda por instalar: aviso calmo e a reserva fica como estava',
      () {
    test('404 da Supabase (função que não existe) = não instalada', () {
      expect(
          RecusaReservaFalhou.motivoDe(404, {
            'code': 'NOT_FOUND',
            'message': 'Requested function was not found',
          }),
          MotivoFalhaRecusa.naoInstalada);
      expect(RecusaReservaFalhou.motivoDe(404, null),
          MotivoFalhaRecusa.naoInstalada);
      expect(RecusaReservaFalhou.motivoDe(404, 'Function not found'),
          MotivoFalhaRecusa.naoInstalada);
    });

    test('404 da própria Edge = reserva não encontrada', () {
      expect(
          RecusaReservaFalhou.motivoDe(
              404, {'error': 'reservation_not_found'}),
          MotivoFalhaRecusa.naoEncontrada);
    });

    test('os outros códigos', () {
      expect(RecusaReservaFalhou.motivoDe(0, null), MotivoFalhaRecusa.semRede);
      expect(RecusaReservaFalhou.motivoDe(401, {'error': 'unauthorized'}),
          MotivoFalhaRecusa.sessao);
      expect(
          RecusaReservaFalhou.motivoDe(403, {'error': 'not_your_restaurant'}),
          MotivoFalhaRecusa.semAcesso);
      expect(
          RecusaReservaFalhou.motivoDe(
              409, {'error': 'reservation_not_pending'}),
          MotivoFalhaRecusa.jaDecidida);
      expect(RecusaReservaFalhou.motivoDe(500, {'error': 'internal_error'}),
          MotivoFalhaRecusa.outro);
    });

    test('a frase calma pedida', () {
      const falha = RecusaReservaFalhou(MotivoFalhaRecusa.naoInstalada);
      expect(falha.texto,
          'Esta parte ainda não está instalada; tenta mais tarde ou fala com a equipa Bora.');
      expect(falha.toString(), falha.texto);
    });

    test('o ecrã mostra-a sem vermelho', () {
      final rejeitar = _entre(_ler(_ecraEmUso), 'Future<void> _onReject',
          'Future<void> _onMarkArrival');
      expect(rejeitar, contains('MotivoFalhaRecusa.naoInstalada'));
      expect(rejeitar, contains('backgroundColor: calmo ? null : Colors.red'));
    });
  });

  group('os ecrãs deixaram de prometer o que não acontecia', () {
    test('Reservas PRO (o ecrã em uso)', () {
      final s = _ler(_ecraEmUso);
      final rejeitar =
          _entre(s, 'Future<void> _onReject', 'Future<void> _onMarkArrival');
      expect(s, isNot(contains('Reserva rejeitada e reembolsada.')));
      expect(s,
          isNot(contains('O pré-pagamento de €3 será reembolsado ao cliente.')));
      expect(rejeitar, contains('.rejectReservation('));
      expect(rejeitar, isNot(contains('decideReservation(')));
      expect(rejeitar, contains("'Ao rejeitar, o cliente é avisado.'.tr"));
    });

    test('ecrã antigo de reservas (sem ligação no menu)', () {
      final s = _ler('lib/screens/partner_reservations_screen.dart');
      expect(s.toLowerCase(), isNot(contains('reembolso automático')));
      expect(s, contains('.rejectReservation('));
    });
  });

  group('a Edge, lida pela fonte', () {
    late String edge;
    late String logica;
    setUp(() {
      edge = _ler('supabase/functions/partner-reject-reservation/index.ts');
      logica = _ler('supabase/functions/partner-reject-reservation/logica.ts');
    });

    test('chave de idempotência reserva-recusa-<id>-<n> (uma por tentativa)', () {
      expect(logica, contains(r'`reserva-recusa-${reservaId}-${'));
      expect(edge, contains('idempotencyKey: chave'));
    });

    test('a mesma RPC, a rejeitar, com o token do parceiro', () {
      expect(edge, contains("userClient.rpc('partner_decide_reservation'"));
      expect(edge, contains('p_accept: false'));
    });

    test('dono do restaurante verificado no servidor, como na RPC', () {
      expect(edge, contains(".eq('user_', userId)"));
      expect(logica, contains("error: 'not_your_restaurant'"));
    });

    test('dinheiro conferido na Stripe, na conta onde entrou', () {
      expect(edge, contains('stripeDaLinha('));
      expect(edge, contains('paymentIntents.retrieve('));
      expect(edge, contains('refunds.create('));
      expect(logica,
          contains("PROPOSITO_PREPAGAMENTO = 'reservation_prepayment'"));
    });

    test('regista como o admin e avisa a equipa se a devolução falhar', () {
      expect(edge, contains("from('admin_audit_log').insert("));
      expect(edge, contains("rpc('notify_admin_urgent_push'"));
    });

    test('segredos só por Deno.env, nunca no código', () {
      final chave =
          RegExp(r'sk_(live|test)_|rk_(live|test)_|whsec_|sb_secret_|eyJhbGci');
      expect(chave.hasMatch(edge), isFalse);
      expect(chave.hasMatch(logica), isFalse);
      expect(edge, contains("Deno.env.get('SUPABASE_URL')"));
    });
  });

  group('inglês das frases novas', () {
    const novas = [
      'Ao rejeitar, o cliente é avisado e a Bora devolve-lhe os {0} do pré-pagamento.',
      'Ao rejeitar, o cliente é avisado.',
      'Reserva rejeitada. O cliente foi avisado e a devolução de {0} já foi pedida.',
      'Reserva rejeitada. A devolução de {0} ao cliente já tinha sido feita.',
      'Reserva rejeitada. O cliente foi avisado.',
      'Reserva rejeitada. O cliente foi avisado e a equipa Bora trata da devolução.',
      'Esta parte ainda não está instalada; tenta mais tarde ou fala com a equipa Bora.',
      'Esta reserva já foi decidida. Atualiza a lista.',
      'Não tens acesso a esta reserva.',
      'Reserva não encontrada.',
      'Não foi possível concluir. Atualiza a lista e tenta de novo.',
    ];

    test('cada frase nova tem inglês, diferente do português', () {
      for (final k in novas) {
        expect(kStringsEn[k], isNotNull, reason: k);
        expect(kStringsEn[k], isNot(k), reason: k);
        expect(kStringsEn[k]!.contains('{0}'), k.contains('{0}'), reason: k);
      }
    });

    test('os mesmos pares estão no JSON (o gerador não os perde)', () {
      final json = jsonDecode(_ler(
              'tool/l10n/traducoes/pt-en-39-reserva-recusa-reembolso.json'))
          as Map<String, dynamic>;
      for (final k in novas) {
        expect(json[k], kStringsEn[k], reason: k);
      }
    });
  });
}
