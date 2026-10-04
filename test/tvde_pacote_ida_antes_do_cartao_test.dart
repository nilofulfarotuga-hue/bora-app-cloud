import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Pacote ida-e-volta pago online: a corrida de IDA nasce no servidor ANTES de
/// se abrir o cartão.
///
/// Cicatriz (04/10/2026, cliente Priscila, Safari do iPhone): a app cobrava
/// primeiro e criava a ida depois, na página que o cartão já tinha feito
/// morrer. Pagou 9,60 EUR, a ida nunca nasceu, nenhum motorista foi chamado.
///
/// Guarda sobre o código-fonte: se alguém voltar a pôr o pagamento à frente da
/// corrida, ou tirar a retoma web do pacote, este teste cai.
void main() {
  final ecra = File('lib/screens/client/tvde/tvde_request_ride_screen.dart')
      .readAsStringSync();
  final retoma =
      File('lib/services/retoma_pagamento_web.dart').readAsStringSync();

  String corpoDoPacoteOnline() {
    final a = ecra.indexOf('Future<void> _solicitarRoundtripOnline(');
    final b = ecra.indexOf('Future<void> _callReturn()');
    expect(a, greaterThan(0));
    expect(b, greaterThan(a));
    return ecra.substring(a, b);
  }

  test('a ida é pedida antes de criar o pagamento e antes de abrir o cartão',
      () {
    final corpo = corpoDoPacoteOnline();
    final ida = corpo.indexOf('store.requestRide(');
    final pagamento = corpo.indexOf('store.createRoundtripPayment(');
    final cartao = corpo.indexOf('PaymentService().processPayment(');
    expect(ida, greaterThan(0), reason: 'a ida tem de ser criada aqui');
    expect(pagamento, greaterThan(ida),
        reason: 'o PaymentIntent só nasce depois de a ida existir');
    expect(cartao, greaterThan(pagamento),
        reason: 'o cartão só abre depois de a ida existir');
    expect('store.requestRide('.allMatches(corpo).length, 1,
        reason: 'uma só ida por compra');
  });

  test('o cartão do pacote leva a ida como referência para a retoma web', () {
    final corpo = corpoDoPacoteOnline();
    final cartao = corpo.indexOf('PaymentService().processPayment(');
    final chamada = corpo.substring(cartao, corpo.indexOf(');', cartao));
    expect(chamada, contains("vertical: 'tvde-roundtrip'"));
    expect(chamada, contains('referenciaId: idaId'));
    expect(chamada, contains('paymentIntentId: paymentIntentId'));
  });

  test('folha fechada nunca cancela a ida sem perguntar ao servidor', () {
    final corpo = corpoDoPacoteOnline();
    final cartao = corpo.indexOf('PaymentService().processPayment(');
    final depois = corpo.substring(cartao);
    final pergunta = depois.indexOf('store.activateRoundtripDetailed(');
    final larga = depois.indexOf('await largarIda()');
    expect(pergunta, greaterThan(0));
    expect(larga, greaterThan(pergunta),
        reason: 'só se larga a ida depois de o servidor dizer que não pagou');
  });

  test('a retoma web conhece o pacote e nunca cancela às cegas', () {
    expect(retoma, contains("pendente.vertical == 'tvde-roundtrip'"));
    final a = retoma.indexOf('Future<void> _retomarPacote(');
    expect(a, greaterThan(0));
    final corpo = retoma.substring(a, retoma.indexOf('void _abrirAcompanhamento'));
    expect(corpo, contains('activateRoundtripDetailed('));
    // O cancelamento só existe dentro do ramo 'failed' (terminal na Stripe).
    final cancela = corpo.indexOf('store.cancelRide(');
    final falhou = corpo.indexOf("estado == 'failed'");
    expect(falhou, greaterThan(0));
    expect(cancela, greaterThan(falhou));
    expect('store.cancelRide('.allMatches(corpo).length, 1);
  });

  test('vale pago sem ida nunca mostra "Chamar a volta" à partida', () {
    expect(ecra, contains('_valeSemIda = semIda ? credit : null;'));
    expect(ecra, contains('_activeCredit = semIda ? null : credit;'));
  });

  test('a rede de segurança do servidor está no repositório', () {
    final migracoes = Directory('supabase/migrations')
        .listSync()
        .whereType<File>()
        .where((f) => f.path.contains('tvde_pacote_pago_sem_ida_reparo_e_rede'))
        .toList();
    expect(migracoes, hasLength(1));
    final sql = migracoes.single.readAsStringSync();
    expect(sql, contains('tvde_roundtrip_sweep_orfaos'));
    expect(sql, contains("cron.schedule('tvde-roundtrip-orfaos', '* * * * *'"));
    expect(sql, contains('tvde_roundtrip_credits_pi_unico'));
    expect(sql, contains('admin_tvde_pagos_sem_corrida'));
  });
}
