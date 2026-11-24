// Limpeza — regra de cancelamento de 24/11/2026 (Danilo 05:46 e 05:52):
// sem a profissional a caminho, o cliente cancela de graça; com ela a caminho,
// paga a deslocação (o maior entre o mínimo e a taxa de deslocação da vaga),
// por cada profissional a caminho; a Bora fica com a parte dela e a
// profissional recebe o resto; profissional atrasada = ninguém paga.
//
// Os números dos casos são os da prova feita no servidor pela Claude.ai
// (e2e_log 14576): a caminho na Guarda 500/400; a caminho com deslocação de
// 29 € 2900/2800; aceite (não a caminho) 0/0.
import 'dart:io';

import 'package:bora_app/models/cleaning_models.dart';
import 'package:bora_app/screens/admin/admin_cleaning_bookings_screen.dart';
import 'package:flutter_test/flutter_test.dart';

const _min = 500; // cleaning_cancel_travel_comp_cents
const _bora = 100; // cleaning_cancel_bora_cut_cents
const _atraso = 15; // cleaning_pro_late_no_fee_minutes

final _hora = DateTime.parse('2026-11-24T15:00:00Z');

CleaningBooking _vaga({
  String id = 'b1',
  String status = 'on_the_way',
  int travel = 0,
  int total = 4500,
  String? grupo,
  int slot = 1,
  String? startedAt,
}) =>
    CleaningBooking.fromSupabase({
      'id': id,
      'client_user_id': 'u1',
      'scheduled_at': _hora.toIso8601String(),
      'status': status,
      'travel_fee_cents': travel,
      'total_cents': total,
      if (grupo != null) 'team_group_id': grupo,
      if (grupo != null) 'team_size': 2,
      'team_slot': slot,
      if (startedAt != null) 'started_at': startedAt,
    });

CancelamentoLimpeza _conta(CleaningBooking b,
        {Iterable<CleaningBooking> equipa = const [], DateTime? agora}) =>
    CancelamentoLimpeza.calcular(
      principal: b,
      equipa: equipa,
      agora: agora ?? _hora.subtract(const Duration(minutes: 20)),
      minimoCents: _min,
      atrasoMinutos: _atraso,
    );

void main() {
  test('lê da linha a compensação e o início da limpeza', () {
    final b = CleaningBooking.fromSupabase({
      'id': 'x',
      'client_user_id': 'u',
      'scheduled_at': '2026-11-24T15:00:00Z',
      'status': 'cancelled_client',
      'cleaner_compensation_cents': 400,
      'started_at': '2026-11-24T15:02:00Z',
    });
    expect(b.cleanerCompensationCents, 400);
    expect(b.startedAt, isNotNull);
    expect(_vaga().cleanerCompensationCents, 0);
  });

  test('aceite, ainda não a caminho: grátis', () {
    final p = _conta(_vaga(status: 'accepted'));
    expect(p.gratis, isTrue);
    expect(p.taxaClienteCents, 0);
    expect(p.profissionaisACaminho, 0);
    expect(_conta(_vaga(status: 'scheduled')).gratis, isTrue);
  });

  test('a caminho na Guarda (sem deslocação): taxa 5 €, profissional 4 €', () {
    final p = _conta(_vaga());
    expect(p.taxaClienteCents, 500);
    expect(p.profissionaisACaminho, 1);
    expect(CancelamentoLimpeza.compensacaoProfissional(500, _bora), 400);
  });

  test('a caminho com deslocação de 29 €: vale a maior', () {
    final p = _conta(_vaga(travel: 2900, total: 9000));
    expect(p.taxaClienteCents, 2900);
    expect(CancelamentoLimpeza.compensacaoProfissional(2900, _bora), 2800);
    // Deslocação de 3 € (menor que o mínimo): paga-se o mínimo.
    expect(_conta(_vaga(travel: 300)).taxaClienteCents, 500);
  });

  test('profissional atrasada mais de 15 min sem começar: ninguém paga', () {
    final atrasada =
        _conta(_vaga(), agora: _hora.add(const Duration(minutes: 16)));
    expect(atrasada.profissionalAtrasada, isTrue);
    expect(atrasada.taxaClienteCents, 0);
    // Aos 15 minutos certos ainda não conta como atraso.
    final noLimite =
        _conta(_vaga(), agora: _hora.add(const Duration(minutes: 15)));
    expect(noLimite.profissionalAtrasada, isFalse);
    expect(noLimite.taxaClienteCents, 500);
  });

  test('já começou: não é "a caminho", sem taxa', () {
    final p = _conta(_vaga(startedAt: '2026-11-24T14:58:00Z'));
    expect(p.taxaClienteCents, 0);
  });

  test('equipa: soma a deslocação de cada profissional a caminho', () {
    final v1 = _vaga(id: 'v1', grupo: 'g', slot: 1, travel: 800);
    final v2 = _vaga(id: 'v2', grupo: 'g', slot: 2, travel: 800, total: 0);
    final v3 = _vaga(
        id: 'v3', grupo: 'g', slot: 3, status: 'accepted', travel: 800, total: 0);
    final p = _conta(v1, equipa: [v1, v2, v3]);
    expect(p.taxaClienteCents, 1600);
    expect(p.profissionaisACaminho, 2);
    // Só a vaga 2 a caminho: o cliente paga a dela.
    final soV2 =
        _conta(_vaga(id: 'v1', grupo: 'g', status: 'accepted'), equipa: [v2]);
    expect(soV2.taxaClienteCents, 800);
  });

  test('cartão/MB Way: volta o total menos a taxa, nunca negativo', () {
    expect(CancelamentoLimpeza.devolvidoCents(4500, 500), 4000);
    expect(CancelamentoLimpeza.devolvidoCents(4500, 0), 4500);
    expect(CancelamentoLimpeza.devolvidoCents(400, 500), 0);
  });

  test('painel: taxa do cliente, compensação e parte da Bora', () {
    final r = resumoCancelamentoClienteLimpeza({
      'status': 'cancelled_client',
      'cancelled_by': 'client',
      'cancel_fee_cents': 500,
      'cleaner_compensation_cents': 400,
    });
    expect(r, isNotNull);
    expect(r!.clienteCents, 500);
    expect(r.profissionalCents, 400);
    expect(r.boraCents, 100);

    // Equipa: a parte da Bora soma-se vaga a vaga (não se adivinha daqui).
    final eq = resumoCancelamentoClienteLimpeza({
      'status': 'cancelled_client',
      'cancelled_by': 'client',
      'team_group_id': 'g',
      'cancel_fee_cents': 1000,
      'cleaner_compensation_cents': 400,
    });
    expect(eq!.boraCents, isNull);

    // Sem dinheiro, ou não cancelada pelo cliente: nada a mostrar.
    expect(
        resumoCancelamentoClienteLimpeza({
          'status': 'cancelled_client',
          'cancelled_by': 'client',
          'cancel_fee_cents': 0,
        }),
        isNull);
    expect(
        resumoCancelamentoClienteLimpeza({
          'status': 'cancelled_client',
          'cancelled_by': 'cleaner',
          'cancel_fee_cents': 4500,
        }),
        isNull);
  });

  test('os textos da regra antiga saíram da app do cliente', () {
    final ecras = [
      'lib/screens/client/cleaning/cleaning_tracking_screen.dart',
      'lib/screens/client/cleaning/cleaning_wizard_screen.dart',
    ].map((f) => File(f).readAsStringSync()).join('\n');
    expect(ecras, isNot(contains('Taxa de 50%')));
    expect(ecras, isNot(contains('Taxa de 100%')));
    expect(ecras, isNot(contains('50% entre 24 h e 2 h')));
    expect(ecras, isNot(contains('cleaning_cancel_half_hours')));
    expect(ecras, contains('cleaning_cancel_travel_comp_cents'));
  });
}
