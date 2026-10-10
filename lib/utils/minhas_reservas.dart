// Tudo o que o cliente marcou, num sítio só (10/10/2026).
//
// Cicatriz: dois clientes reais (uma corrida marcada e uma limpeza, ambas
// pagas) escreveram "fiz uma reserva mas não aparece". O separador
// "Reservas" só lia as mesas de restaurante; as corridas marcadas viviam em
// Motorista → "As minhas reservas", as limpezas no quadrado Limpeza e as
// marcações no Perfil. O cliente ia ao separador certo e não via nada.
//
// Este ficheiro só JUNTA e ORDENA o que os quatro stores já carregam — não
// lê a base de dados, não decide dinheiro e não sabe nada de ecrãs. O relógio
// entra por argumento ([agora]) para a função ser pura e testável.

import '../models/appointment_model.dart';
import '../models/cleaning_models.dart';
import '../models/reservation_model.dart';
import '../models/tvde_ride.dart';
import 'hora_lisboa.dart';

/// Quantos dias de calendário vão de [agora] a [instante], no relógio de
/// Lisboa (0 = hoje, 1 = amanhã, -1 = ontem) — nunca no fuso do telemóvel.
int diasDeDiferencaEmLisboa(DateTime instante, DateTime agora) {
  final a = paredeLisboa(instante);
  final h = paredeLisboa(agora);
  return DateTime.utc(a.year, a.month, a.day)
      .difference(DateTime.utc(h.year, h.month, h.day))
      .inDays;
}

/// Os quatro tipos de coisa marcada.
enum TipoReserva { mesa, corrida, limpeza, marcacao }

/// Em que aba aparece.
enum GrupoReserva { proximas, passadas, canceladas }

/// Estado para o cliente, já sem o nome técnico da base (PADRÃO 1.16).
/// O texto em português vive no ecrã, para passar pelo `.tr`.
enum EstadoReserva {
  aguardaPagamento,
  aguardaConfirmacao,
  agendada,
  procuraMotorista,
  confirmada,
  motoristaConfirmado,
  aCaminho,
  motoristaChegou,
  emCurso,
  porConfirmarFim,
  concluida,
  naoCompareceu,
  cancelada,
  semPrestador,
}

/// O que se diz sobre o pagamento. Só lê o que o servidor gravou.
enum PagamentoReserva {
  pago,
  porPagar,
  emDinheiro,
  noPacote,
  noPlano,
  semPagamento,
  desconhecido,
}

/// Uma linha da lista, seja de que tipo for.
class ItemReserva {
  const ItemReserva({
    required this.tipo,
    required this.id,
    required this.quando,
    required this.sitio,
    required this.estado,
    required this.pagamento,
    required this.grupo,
    required this.origem,
  });

  final TipoReserva tipo;
  final String id;

  /// Instante marcado (comparável; para LER usa-se `paredeLisboa`).
  final DateTime quando;

  /// Loja, destino ou morada. Nulo quando a linha não o traz.
  final String? sitio;
  final EstadoReserva estado;
  final PagamentoReserva pagamento;
  final GrupoReserva grupo;

  /// O modelo original — é com ele que se abre o ecrã de detalhe que já
  /// existe para o tipo.
  final Object origem;
}

/// As três abas, já ordenadas.
class MinhasReservas {
  const MinhasReservas({
    required this.proximas,
    required this.passadas,
    required this.canceladas,
  });

  /// Da mais perto para a mais longe.
  final List<ItemReserva> proximas;

  /// Da mais recente para a mais antiga.
  final List<ItemReserva> passadas;

  /// Da mais recente para a mais antiga.
  final List<ItemReserva> canceladas;

  bool get vazio => proximas.isEmpty && passadas.isEmpty && canceladas.isEmpty;
}

/// Junta as quatro listas e reparte-as pelas três abas.
///
/// [corridas] pode trazer corridas imediatas e repetidas (vem de mais do que
/// uma lista do `TvdeStore`): só entram as que têm hora marcada, uma vez cada
/// — a primeira que aparece com aquele id ganha, por isso põe-se à frente a
/// cópia mais fresca.
MinhasReservas juntarReservas({
  Iterable<ReservationModel> mesas = const [],
  Iterable<TvdeRide> corridas = const [],
  Iterable<CleaningBooking> limpezas = const [],
  Iterable<AppointmentModel> marcacoes = const [],
  required DateTime agora,
}) {
  final itens = <ItemReserva>[
    for (final r in mesas) _mesa(r, agora),
    ..._corridasUnicas(corridas).map(_corrida),
    for (final b in limpezas) _limpeza(b),
    for (final a in marcacoes) _marcacao(a, agora),
  ];

  int crescente(ItemReserva a, ItemReserva b) {
    final c = a.quando.compareTo(b.quando);
    return c != 0 ? c : a.id.compareTo(b.id);
  }

  int decrescente(ItemReserva a, ItemReserva b) => crescente(b, a);

  List<ItemReserva> doGrupo(GrupoReserva g) =>
      itens.where((i) => i.grupo == g).toList();

  return MinhasReservas(
    proximas: doGrupo(GrupoReserva.proximas)..sort(crescente),
    passadas: doGrupo(GrupoReserva.passadas)..sort(decrescente),
    canceladas: doGrupo(GrupoReserva.canceladas)..sort(decrescente),
  );
}

Iterable<TvdeRide> _corridasUnicas(Iterable<TvdeRide> corridas) sync* {
  final vistos = <String>{};
  for (final c in corridas) {
    if (c.scheduledAt == null) continue;
    if (vistos.add(c.id)) yield c;
  }
}

// ── Mesa (reservations) ───────────────────────────────────────────────────
// Espelha ReservationModel.isUpcoming/isPast, com o relógio por argumento.
ItemReserva _mesa(ReservationModel r, DateTime agora) {
  final GrupoReserva grupo;
  if (r.isCancelled) {
    grupo = GrupoReserva.canceladas;
  } else if (!r.isNoShow && !r.isFinished && r.reservedFor.isAfter(agora)) {
    grupo = GrupoReserva.proximas;
  } else {
    grupo = GrupoReserva.passadas;
  }

  final EstadoReserva estado;
  if (r.isCancelled) {
    estado = EstadoReserva.cancelada;
  } else if (r.isNoShow) {
    estado = EstadoReserva.naoCompareceu;
  } else if (r.isFinished) {
    estado = EstadoReserva.concluida;
  } else if (r.status == ReservationStatus.pendingPayment) {
    estado = EstadoReserva.aguardaPagamento;
  } else if (r.status == ReservationStatus.pending) {
    estado = EstadoReserva.aguardaConfirmacao;
  } else if (grupo == GrupoReserva.passadas) {
    estado = EstadoReserva.concluida;
  } else if (r.isArrived) {
    estado = EstadoReserva.emCurso;
  } else if (r.isApproved) {
    estado = EstadoReserva.confirmada;
  } else {
    // Estado que o modelo não conhece (ex.: 'suggested_other_time', a loja
    // propôs outra hora): nunca dizer "Confirmada" sem o ser.
    estado = EstadoReserva.aguardaConfirmacao;
  }

  final PagamentoReserva pagamento;
  if (r.prepaymentCents <= 0) {
    pagamento = PagamentoReserva.semPagamento;
  } else if (r.status == ReservationStatus.pendingPayment) {
    pagamento = PagamentoReserva.porPagar;
  } else {
    pagamento = PagamentoReserva.pago;
  }

  return ItemReserva(
    tipo: TipoReserva.mesa,
    id: r.id,
    quando: r.reservedFor,
    sitio: r.restaurantName,
    estado: estado,
    pagamento: pagamento,
    grupo: grupo,
    origem: r,
  );
}

// ── Corrida marcada (tvde_rides com scheduled_at) ─────────────────────────
// Lição de 20/08: aos 20 min a reserva passa de 'agendada' a motorista
// atribuído / a caminho. Filtrar só por 'agendada' fazia-a desaparecer antes
// de começar. Aqui conta como próxima enquanto não acabar.
ItemReserva _corrida(TvdeRide c) {
  final GrupoReserva grupo;
  final EstadoReserva estado;
  final reserva = c.reservationStatus;

  if (c.status == 'no_show') {
    grupo = GrupoReserva.passadas;
    estado = EstadoReserva.naoCompareceu;
  } else if (c.isCancelled || reserva == 'cancelada') {
    grupo = GrupoReserva.canceladas;
    estado = EstadoReserva.cancelada;
  } else if (c.isNoDriver || reserva == 'sem_motorista') {
    grupo = GrupoReserva.canceladas;
    estado = EstadoReserva.semPrestador;
  } else if (c.isFinished) {
    grupo = GrupoReserva.passadas;
    estado = EstadoReserva.concluida;
  } else {
    grupo = GrupoReserva.proximas;
    estado = _estadoCorridaViva(c);
  }

  final PagamentoReserva pagamento;
  if (c.isReturnLeg && c.roundtripCreditId != null) {
    pagamento = PagamentoReserva.noPacote;
  } else if (c.usedSubscriptionRide) {
    pagamento = PagamentoReserva.noPlano;
  } else if (!c.isPaidOnline) {
    pagamento = PagamentoReserva.emDinheiro;
  } else if (c.paymentStatus == 'succeeded') {
    pagamento = PagamentoReserva.pago;
  } else if (c.paymentStatus == 'refunded') {
    pagamento = PagamentoReserva.desconhecido;
  } else {
    pagamento = PagamentoReserva.porPagar;
  }

  return ItemReserva(
    tipo: TipoReserva.corrida,
    id: c.id,
    quando: c.scheduledAt!,
    sitio: c.destLabel,
    estado: estado,
    pagamento: pagamento,
    grupo: grupo,
    origem: c,
  );
}

EstadoReserva _estadoCorridaViva(TvdeRide c) {
  switch (c.status) {
    case 'agendada':
      switch (c.reservationStatus) {
        case 'aguarda_pagamento':
          return EstadoReserva.aguardaPagamento;
        case 'atribuida':
          return EstadoReserva.motoristaConfirmado;
        case 'a_procurar':
          return EstadoReserva.procuraMotorista;
      }
      return c.reservationDriverId != null
          ? EstadoReserva.motoristaConfirmado
          : EstadoReserva.procuraMotorista;
    case 'aguarda_pagamento':
      return EstadoReserva.aguardaPagamento;
    case 'solicitada':
      return c.isPaymentPending
          ? EstadoReserva.aguardaPagamento
          : EstadoReserva.procuraMotorista;
    case 'motorista_atribuido':
      return EstadoReserva.motoristaConfirmado;
    case 'motorista_a_caminho':
      return EstadoReserva.aCaminho;
    case 'motorista_chegou':
      return EstadoReserva.motoristaChegou;
    case 'em_andamento':
      return EstadoReserva.emCurso;
  }
  return EstadoReserva.agendada;
}

// ── Limpeza (cleaning_bookings) ───────────────────────────────────────────
// Mesma divisão do CleaningStore (activeBookings / pastBookings): uma limpeza
// feita à espera de o cliente confirmar ainda é coisa por fechar.
ItemReserva _limpeza(CleaningBooking b) {
  final s = b.status;
  final GrupoReserva grupo = s.isCancelled
      ? GrupoReserva.canceladas
      : s.isActive
          ? GrupoReserva.proximas
          : GrupoReserva.passadas;

  final EstadoReserva estado;
  switch (s) {
    case CleaningStatus.scheduled:
      estado = EstadoReserva.agendada;
    case CleaningStatus.accepted:
      estado = EstadoReserva.confirmada;
    case CleaningStatus.onTheWay:
      estado = EstadoReserva.aCaminho;
    case CleaningStatus.inProgress:
      estado = EstadoReserva.emCurso;
    case CleaningStatus.done:
      estado = EstadoReserva.porConfirmarFim;
    case CleaningStatus.completed:
      estado = EstadoReserva.concluida;
    case CleaningStatus.cancelledClient:
    case CleaningStatus.cancelledCleaner:
      estado = EstadoReserva.cancelada;
    case CleaningStatus.cancelledNoCleaner:
      estado = EstadoReserva.semPrestador;
  }

  // Valores do CHECK de cleaning_bookings.payment_status: unpaid, held,
  // released, estornado, cash_pending, cash_settled. 'held' = cobrado e
  // retido; 'released' = entregue à profissional depois de concluída.
  final PagamentoReserva pagamento;
  if (b.paymentMethod == 'cash') {
    pagamento = PagamentoReserva.emDinheiro;
  } else if (const {'held', 'released'}.contains(b.paymentStatus)) {
    pagamento = PagamentoReserva.pago;
  } else if (b.paymentStatus == 'unpaid') {
    pagamento = PagamentoReserva.porPagar;
  } else {
    pagamento = PagamentoReserva.desconhecido;
  }

  final rua = b.addressStreet.trim();
  return ItemReserva(
    tipo: TipoReserva.limpeza,
    id: b.id,
    quando: b.scheduledAt,
    sitio: rua.isEmpty ? null : rua,
    estado: estado,
    pagamento: pagamento,
    grupo: grupo,
    origem: b,
  );
}

// ── Marcação (appointments) ───────────────────────────────────────────────
// Espelha AppointmentModel.isUpcoming/isPast, com o relógio por argumento.
ItemReserva _marcacao(AppointmentModel a, DateTime agora) {
  final GrupoReserva grupo;
  if (a.isCancelled) {
    grupo = GrupoReserva.canceladas;
  } else if (!a.isNoShow &&
      !a.isCompleted &&
      (a.isConfirmed || a.isPendingPayment) &&
      a.scheduledAt.isAfter(agora)) {
    grupo = GrupoReserva.proximas;
  } else {
    grupo = GrupoReserva.passadas;
  }

  final EstadoReserva estado;
  if (a.isCancelled) {
    estado = EstadoReserva.cancelada;
  } else if (a.isNoShow) {
    estado = EstadoReserva.naoCompareceu;
  } else if (a.isPendingPayment) {
    estado = EstadoReserva.aguardaPagamento;
  } else if (grupo == GrupoReserva.passadas) {
    estado = EstadoReserva.concluida;
  } else {
    estado = EstadoReserva.confirmada;
  }

  final PagamentoReserva pagamento;
  if (a.depositStatus == 'paid' || a.fullPaymentStatus == 'paid') {
    pagamento = PagamentoReserva.pago;
  } else if (a.depositStatus == 'waived') {
    pagamento = PagamentoReserva.semPagamento;
  } else if (a.isPendingPayment || a.depositStatus == 'pending') {
    pagamento = PagamentoReserva.porPagar;
  } else {
    pagamento = PagamentoReserva.desconhecido;
  }

  return ItemReserva(
    tipo: TipoReserva.marcacao,
    id: a.id,
    quando: a.scheduledAt,
    sitio: a.providerName,
    estado: estado,
    pagamento: pagamento,
    grupo: grupo,
    origem: a,
  );
}
