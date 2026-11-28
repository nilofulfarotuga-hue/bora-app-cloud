// fechar-tudo-15-11 (revisão do Juiz da Claude.ai, 15/11 17:2x): o "Cancelar em
// nome" do painel de reservas chamava a RPC admin_cancel_reservation_on_behalf_of
// direto e saltava a Edge admin-cancel-reservation — cancelava "com reembolso" e
// o dinheiro nunca voltava ao cliente. Agora chama a Edge e mostra o que ela fez.
import 'dart:io';

import 'package:bora_app/screens/admin/admin_reservations_screen.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

String _ler(String caminho) =>
    File(caminho).readAsStringSync().replaceAll(String.fromCharCode(13), '');

Map<String, dynamic> _resposta({
  bool idempotent = false,
  String? result,
  int cents = 300,
  String? reason,
  String? error,
  String? stripeStatus,
  String? previousStatus,
}) =>
    <String, dynamic>{
      'success': true,
      'idempotent': idempotent,
      'reservation_id': '0b5c3e2a-1d4f-4a6b-9c8d-7e6f5a4b3c2d',
      if (!idempotent) 'new_status': 'cancelled_refunded',
      if (previousStatus != null) 'previous_status': previousStatus,
      if (result != null)
        'refund': <String, dynamic>{
          'result': result,
          'stripe_id': result == 'succeeded' ? 're_1' : null,
          'amount': cents > 0 ? cents / 100 : null,
          'amount_cents': cents,
          'error': error,
          'reason': reason,
          'stripe_status': stripeStatus,
        },
    };

void main() {
  test('Cancelar em nome chama a Edge que devolve, não a RPC sozinha', () {
    final fonte = _ler('lib/screens/admin/admin_reservations_screen.dart');
    final i = fonte.indexOf('Future<void> _showCancelOnBehalfSheet');
    final fim = fonte.indexOf('Future<void> _showWalkInSheet', i);
    expect(i, greaterThan(0));
    expect(fim, greaterThan(i));
    final folha = fonte.substring(i, fim);
    expect(folha, contains('functions'));
    expect(folha, contains(".invoke("));
    expect(folha, contains("'admin-cancel-reservation'"));
    expect(folha, contains("'reservation_id': reservationIdCtrl.text.trim()"));
    expect(folha, contains("'reason': reasonCtrl.text.trim()"));
    expect(folha, contains('resumoCancelamentoReserva(res.data)'));
    expect(folha, contains('erroCancelamentoReserva(e)'));
    expect(folha, isNot(contains('.rpc(')),
        reason: 'a RPC direta cancela mas não devolve o dinheiro');
    expect(fonte, isNot(contains("'admin_cancel_reservation_on_behalf_of'")));
    expect(folha, isNot(contains(r"Text('Erro: $e')")),
        reason: 'o painel mostra o erro em PT-BR, não o objeto cru');
  });

  group('resumo da resposta da Edge (PT-BR)', () {
    test('cancelada com reembolso pedido à Stripe', () {
      final r = resumoCancelamentoReserva(
          _resposta(result: 'succeeded', stripeStatus: 'succeeded'));
      expect(r.ok, isTrue);
      expect(r.texto, contains('Reserva cancelada'));
      expect(r.texto, contains('3,00 €'));
      expect(r.texto, contains('Stripe'));
      expect(r.texto, isNot(contains('processamento')));
    });

    test('reembolso a caminho: diz que está em processamento', () {
      final r = resumoCancelamentoReserva(
          _resposta(result: 'succeeded', stripeStatus: 'pending'));
      expect(r.ok, isTrue);
      expect(r.texto, contains('em processamento'));
    });

    test('nova tentativa numa já cancelada: o reembolso que faltava', () {
      final r = resumoCancelamentoReserva(_resposta(
          idempotent: true,
          result: 'succeeded',
          previousStatus: 'cancelled_refunded',
          stripeStatus: 'succeeded'));
      expect(r.ok, isTrue);
      expect(r.texto, contains('já estava cancelada'));
      expect(r.texto, contains('que faltava'));
      expect(r.texto, contains('3,00 €'));
    });

    test('já devolvido antes', () {
      final r = resumoCancelamentoReserva(_resposta(
          idempotent: true,
          result: 'already_refunded',
          previousStatus: 'cancelled_refunded'));
      expect(r.ok, isTrue);
      expect(r.texto, contains('já tinha sido devolvido'));
      expect(r.texto, contains('3,00 €'));
    });

    test('dentro do prazo: a Bora retém, sem reembolso', () {
      final r =
          resumoCancelamentoReserva(_resposta(result: 'forfeited_window', cents: 0));
      expect(r.ok, isTrue);
      expect(r.texto, contains('sem reembolso'));
    });

    test('reembolso que não saiu: vermelho, com o porquê e a equipe avisada', () {
      final recusado = resumoCancelamentoReserva(_resposta(
          result: 'failed', cents: 0, reason: 'refund_failed', error: 'refund_failed'));
      expect(recusado.ok, isFalse);
      expect(recusado.texto, contains('NÃO saiu'));
      expect(recusado.texto, contains('a Stripe recusou o reembolso'));
      expect(recusado.texto, contains('equipe foi avisada'));
      final erroStripe = resumoCancelamentoReserva(_resposta(
          result: 'failed', cents: 0, reason: 'stripe_error', error: 'charge_disputed'));
      expect(erroStripe.ok, isFalse);
      expect(erroStripe.texto, contains('charge_disputed'));
      final semPagamento = resumoCancelamentoReserva(
          _resposta(result: 'no_payment_intent', cents: 0, reason: 'no_payment_intent'));
      expect(semPagamento.ok, isFalse);
      expect(semPagamento.texto, contains('confira se o cliente pagou'));
    });

    test('já cancelada sem direito (resposta da v21, sem bloco refund): nada mudou', () {
      final r = resumoCancelamentoReserva(
          _resposta(idempotent: true, previousStatus: 'no_show'));
      expect(r.ok, isTrue);
      expect(r.texto, contains('já estava fechada'));
      expect(r.texto, contains('cliente não apareceu'));
      expect(r.texto, contains('Nada mudou'));
    });

    test('resposta estranha não passa por sucesso', () {
      expect(resumoCancelamentoReserva(null).ok, isFalse);
      expect(resumoCancelamentoReserva('ok').ok, isFalse);
      expect(resumoCancelamentoReserva(<String, dynamic>{'success': false}).ok,
          isFalse);
    });
  });

  group('erros da Edge (PT-BR)', () {
    test('estado que não deixa cancelar, com o estado em palavras', () {
      final t = erroCancelamentoReserva(const FunctionException(
        status: 409,
        details: {
          'error': 'rpc_error',
          'detail': 'cannot_cancel_status: pending_payment',
        },
      ));
      expect(t, contains('não pode ser cancelada'));
      expect(t, contains('esperando pagamento'));
    });

    test('reserva que não existe e id inválido', () {
      expect(
        erroCancelamentoReserva(const FunctionException(
          status: 404,
          details: {'error': 'rpc_error', 'detail': 'reservation_not_found'},
        )),
        'Reserva não encontrada. Confira o ID.',
      );
      expect(
        erroCancelamentoReserva(const FunctionException(
          status: 400,
          details: {'error': 'invalid_reservation_id'},
        )),
        contains('ID da reserva inválido'),
      );
    });

    test('sem permissão, sessão expirada e sem rede', () {
      expect(
        erroCancelamentoReserva(const FunctionException(
          status: 403,
          details: {'error': 'admin_required'},
        )),
        contains('Sem permissão de admin'),
      );
      expect(
        erroCancelamentoReserva(const FunctionException(
          status: 401,
          details: {'error': 'unauthorized'},
        )),
        contains('Sessão de admin expirada'),
      );
      expect(
        erroCancelamentoReserva(const FunctionException(status: 0)),
        contains('Sem conexão'),
      );
    });
  });
}
