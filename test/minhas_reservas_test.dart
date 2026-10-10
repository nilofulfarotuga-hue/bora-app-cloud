// Separador "Reservas" do cliente — a função que junta e ordena os 4 tipos.
//
// Cicatriz (10/10/2026): um cliente com uma corrida marcada (paga por MB Way,
// motorista atribuído) e outro com uma limpeza (MB Way retido) abriram o
// separador "Reservas", não viram nada e julgaram a reserva perdida — o
// separador só lia as mesas de restaurante.
import 'package:bora_app/models/appointment_model.dart';
import 'package:bora_app/models/cleaning_models.dart';
import 'package:bora_app/models/reservation_model.dart';
import 'package:bora_app/models/tvde_ride.dart';
import 'package:bora_app/utils/minhas_reservas.dart';
import 'package:flutter_test/flutter_test.dart';

final _agora = DateTime.utc(2026, 10, 10, 3, 40);

TvdeRide _corrida(
  String id, {
  required DateTime? quando,
  String status = 'agendada',
  String? reserva,
  String metodo = 'cash',
  String? pagamento,
  bool volta = false,
  String? vale,
}) =>
    TvdeRide.fromMap({
      'id': id,
      'client_id': 'cli',
      'status': status,
      'reservation_status': reserva,
      'payment_method': metodo,
      'payment_status': pagamento,
      'scheduled_at': quando?.toIso8601String(),
      'is_return_leg': volta,
      'roundtrip_credit_id': vale,
      'dest_label': 'Destino $id',
      'origin_label': 'Origem $id',
    });

CleaningBooking _limpeza(
  String id, {
  required DateTime quando,
  String status = 'accepted',
  String metodo = 'mbway',
  String pagamento = 'held',
}) =>
    CleaningBooking.fromSupabase({
      'id': id,
      'client_user_id': 'cli',
      'scheduled_at': quando.toIso8601String(),
      'status': status,
      'payment_method': metodo,
      'payment_status': pagamento,
      'address_street': 'Rua $id',
    });

ReservationModel _mesa(
  String id, {
  required DateTime quando,
  String status = ReservationStatus.approved,
  int sinal = 300,
}) =>
    ReservationModel(
      id: id,
      restaurantId: 'r1',
      clientUserId: 'cli',
      clientName: 'Cliente',
      clientPhone: '910000000',
      people: 2,
      reservedFor: quando,
      status: status,
      prepaymentCents: sinal,
      restaurantName: 'Restaurante $id',
    );

AppointmentModel _marcacao(
  String id, {
  required DateTime quando,
  String status = AppointmentStatus.confirmed,
  String? deposito = 'paid',
}) =>
    AppointmentModel(
      id: id,
      providerId: 'p1',
      scheduledAt: quando,
      status: status,
      depositStatus: deposito,
      providerName: 'Barbearia $id',
    );

List<String> _ids(List<ItemReserva> l) => [for (final i in l) i.id];

void main() {
  group('os dois casos reais de 10/10 aparecem em Próximas', () {
    test('corrida marcada paga por MB Way, com motorista atribuído', () {
      final r = juntarReservas(agora: _agora, corridas: [
        _corrida('corrida-paga',
            quando: DateTime.utc(2026, 10, 10, 4),
            reserva: 'atribuida',
            metodo: 'mbway',
            pagamento: 'succeeded'),
      ]);
      expect(_ids(r.proximas), ['corrida-paga']);
      final i = r.proximas.single;
      expect(i.tipo, TipoReserva.corrida);
      expect(i.estado, EstadoReserva.motoristaConfirmado);
      expect(i.pagamento, PagamentoReserva.pago);
      expect(i.sitio, 'Destino corrida-paga');
    });

    test('limpeza aceite com MB Way retido', () {
      final r = juntarReservas(agora: _agora, limpezas: [
        _limpeza('limpeza-retida', quando: DateTime.utc(2026, 10, 10, 12, 30)),
      ]);
      expect(_ids(r.proximas), ['limpeza-retida']);
      expect(r.proximas.single.estado, EstadoReserva.confirmada);
      expect(r.proximas.single.pagamento, PagamentoReserva.pago);
    });
  });

  test(
      'lição de 20/08: corrida que já passou a motorista atribuído / a caminho '
      'continua em Próximas até acabar', () {
    final hora = DateTime.utc(2026, 10, 10, 3, 55);
    final r = juntarReservas(agora: _agora, corridas: [
      _corrida('atribuido', quando: hora, status: 'motorista_atribuido'),
      _corrida('caminho', quando: hora, status: 'motorista_a_caminho'),
      _corrida('chegou', quando: hora, status: 'motorista_chegou'),
      // Já depois da hora marcada e ainda a decorrer: não é "passada".
      _corrida('andamento',
          quando: DateTime.utc(2026, 10, 10, 3, 20), status: 'em_andamento'),
    ]);
    expect(r.passadas, isEmpty);
    expect(r.canceladas, isEmpty);
    // Ordem: a hora, e a mesma hora desempata pelo id.
    expect(_ids(r.proximas), ['andamento', 'atribuido', 'caminho', 'chegou']);
    expect(r.proximas.map((i) => i.estado), [
      EstadoReserva.emCurso,
      EstadoReserva.motoristaConfirmado,
      EstadoReserva.aCaminho,
      EstadoReserva.motoristaChegou,
    ]);
  });

  test('Próximas junta os 4 tipos, da mais perto para a mais longe', () {
    final r = juntarReservas(
      agora: _agora,
      mesas: [_mesa('mesa', quando: DateTime.utc(2026, 10, 12, 20))],
      corridas: [
        _corrida('corrida', quando: DateTime.utc(2026, 10, 10, 4)),
      ],
      limpezas: [
        _limpeza('limpeza', quando: DateTime.utc(2026, 10, 11, 9)),
      ],
      marcacoes: [
        _marcacao('marcacao', quando: DateTime.utc(2026, 10, 10, 15)),
      ],
    );
    expect(_ids(r.proximas), ['corrida', 'marcacao', 'limpeza', 'mesa']);
    expect(r.proximas.map((i) => i.tipo).toSet(), TipoReserva.values.toSet());
  });

  test('Passadas e Canceladas vêm da mais recente para a mais antiga', () {
    final r = juntarReservas(
      agora: _agora,
      mesas: [
        _mesa('mesa-velha', quando: DateTime.utc(2026, 9, 1, 20)),
        _mesa('mesa-cancelada',
            quando: DateTime.utc(2026, 10, 20, 20),
            status: ReservationStatus.cancelledByClient),
      ],
      corridas: [
        _corrida('corrida-feita',
            quando: DateTime.utc(2026, 10, 5, 8), status: 'finalizada'),
        _corrida('corrida-cancelada',
            quando: DateTime.utc(2026, 10, 15, 8),
            status: 'cancelada_cliente',
            reserva: 'cancelada'),
      ],
      limpezas: [
        _limpeza('limpeza-feita',
            quando: DateTime.utc(2026, 10, 8, 9), status: 'completed'),
        _limpeza('limpeza-cancelada',
            quando: DateTime.utc(2026, 10, 1, 9),
            status: 'cancelled_client'),
      ],
      marcacoes: [
        _marcacao('marcacao-passada', quando: DateTime.utc(2026, 10, 9, 15)),
        _marcacao('marcacao-cancelada',
            quando: DateTime.utc(2026, 10, 18, 15),
            status: AppointmentStatus.cancelled),
      ],
    );
    expect(r.proximas, isEmpty);
    expect(_ids(r.passadas),
        ['marcacao-passada', 'limpeza-feita', 'corrida-feita', 'mesa-velha']);
    expect(_ids(r.canceladas), [
      'mesa-cancelada',
      'marcacao-cancelada',
      'corrida-cancelada',
      'limpeza-cancelada',
    ]);
    expect(r.passadas.map((i) => i.estado).toSet(), {EstadoReserva.concluida});
  });

  test('ninguém disponível vai para Canceladas; falta do cliente para Passadas',
      () {
    final r = juntarReservas(
      agora: _agora,
      corridas: [
        _corrida('sem-motorista',
            quando: DateTime.utc(2026, 10, 9, 8),
            status: 'sem_motorista',
            reserva: 'sem_motorista'),
        _corrida('faltou',
            quando: DateTime.utc(2026, 10, 8, 8), status: 'no_show'),
      ],
      limpezas: [
        _limpeza('sem-profissional',
            quando: DateTime.utc(2026, 10, 7, 9),
            status: 'cancelled_no_cleaner'),
      ],
    );
    expect(_ids(r.canceladas), ['sem-motorista', 'sem-profissional']);
    expect(r.canceladas.map((i) => i.estado).toSet(),
        {EstadoReserva.semPrestador});
    expect(_ids(r.passadas), ['faltou']);
    expect(r.passadas.single.estado, EstadoReserva.naoCompareceu);
  });

  test('corridas: só as marcadas, cada uma uma vez (a primeira ganha)', () {
    final r = juntarReservas(agora: _agora, corridas: [
      _corrida('x',
          quando: DateTime.utc(2026, 10, 10, 4), status: 'motorista_a_caminho'),
      _corrida('x', quando: DateTime.utc(2026, 10, 10, 4)), // cópia velha
      _corrida('imediata', quando: null, status: 'solicitada'),
    ]);
    expect(_ids(r.proximas), ['x']);
    expect(r.proximas.single.estado, EstadoReserva.aCaminho);
  });

  test('pagamento: só diz o que o servidor gravou', () {
    final r = juntarReservas(
      agora: _agora,
      corridas: [
        _corrida('dinheiro', quando: DateTime.utc(2026, 10, 11, 8)),
        _corrida('volta-do-pacote',
            quando: DateTime.utc(2026, 10, 11, 9), volta: true, vale: 'v1'),
        _corrida('mbway-por-confirmar',
            quando: DateTime.utc(2026, 10, 11, 10),
            reserva: 'aguarda_pagamento',
            metodo: 'mbway',
            pagamento: 'requires_action'),
      ],
      limpezas: [
        _limpeza('limpeza-por-pagar',
            quando: DateTime.utc(2026, 10, 11, 11), pagamento: 'unpaid'),
        _limpeza('limpeza-dinheiro',
            quando: DateTime.utc(2026, 10, 11, 12),
            metodo: 'cash',
            pagamento: 'unpaid'),
      ],
      mesas: [
        _mesa('mesa-por-pagar',
            quando: DateTime.utc(2026, 10, 11, 13),
            status: ReservationStatus.pendingPayment),
        _mesa('mesa-sem-sinal', quando: DateTime.utc(2026, 10, 11, 14), sinal: 0),
      ],
      marcacoes: [
        _marcacao('marcacao-por-pagar',
            quando: DateTime.utc(2026, 10, 11, 15),
            status: AppointmentStatus.pendingPayment,
            deposito: 'pending'),
      ],
    );
    final porId = {for (final i in r.proximas) i.id: i};
    expect(porId['dinheiro']!.pagamento, PagamentoReserva.emDinheiro);
    expect(porId['volta-do-pacote']!.pagamento, PagamentoReserva.noPacote);
    expect(porId['mbway-por-confirmar']!.pagamento, PagamentoReserva.porPagar);
    expect(porId['mbway-por-confirmar']!.estado,
        EstadoReserva.aguardaPagamento);
    expect(porId['limpeza-por-pagar']!.pagamento, PagamentoReserva.porPagar);
    expect(porId['limpeza-dinheiro']!.pagamento, PagamentoReserva.emDinheiro);
    expect(porId['mesa-por-pagar']!.pagamento, PagamentoReserva.porPagar);
    expect(porId['mesa-sem-sinal']!.pagamento, PagamentoReserva.semPagamento);
    expect(porId['marcacao-por-pagar']!.pagamento, PagamentoReserva.porPagar);
    expect(porId['marcacao-por-pagar']!.estado,
        EstadoReserva.aguardaPagamento);
  });

  test('limpeza concluída paga online fica "Pago" (payment_status released)',
      () {
    final r = juntarReservas(agora: _agora, limpezas: [
      _limpeza('feita',
          quando: DateTime.utc(2026, 10, 3, 9),
          status: 'completed',
          pagamento: 'released'),
    ]);
    expect(r.passadas.single.pagamento, PagamentoReserva.pago);
  });

  test('mesa com estado que o modelo não conhece nunca diz "Confirmada"', () {
    final r = juntarReservas(agora: _agora, mesas: [
      _mesa('outra-hora',
          quando: DateTime.utc(2026, 10, 12, 20),
          status: ReservationStatus.suggestedOtherTime),
    ]);
    expect(r.proximas.single.estado, EstadoReserva.aguardaConfirmacao);
  });

  test('sem nada marcado: as três abas vazias', () {
    final r = juntarReservas(agora: _agora);
    expect(r.vazio, isTrue);
  });

  group('dias no relógio de Lisboa, nunca no do telemóvel', () {
    test('verão: 23:30 UTC já é amanhã em Lisboa', () {
      expect(
          diasDeDiferencaEmLisboa(DateTime.utc(2026, 7, 10, 23, 30),
              DateTime.utc(2026, 7, 10, 12)),
          1);
    });
    test('inverno: 23:30 UTC ainda é hoje em Lisboa', () {
      expect(
          diasDeDiferencaEmLisboa(DateTime.utc(2026, 12, 10, 23, 30),
              DateTime.utc(2026, 12, 10, 12)),
          0);
    });
    test('ontem', () {
      expect(
          diasDeDiferencaEmLisboa(DateTime.utc(2026, 10, 9, 20),
              DateTime.utc(2026, 10, 10, 8)),
          -1);
    });
  });
}
