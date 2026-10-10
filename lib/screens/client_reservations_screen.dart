import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../config/app_colors.dart';
import '../models/appointment_model.dart';
import '../models/cleaning_models.dart';
import '../models/falha_de_acao.dart';
import '../models/reservation_model.dart';
import '../models/tvde_ride.dart';
import '../stores/cleaning_store.dart';
import '../stores/reservation_store.dart';
import '../stores/services_store.dart';
import '../stores/tvde_store.dart';
import '../utils/hora_lisboa.dart';
import '../utils/home_destino.dart';
import '../utils/minhas_reservas.dart';
import '../widgets/bora_support_fab.dart';
import 'client/cleaning/cleaning_tracking_screen.dart';
import 'client/reservation/reservation_details_screen.dart';
import 'client/services/my_appointments_screen.dart';
import 'client/tvde/tvde_my_reservations_screen.dart';
import 'client/tvde/tvde_ride_tracking_screen.dart';
import 'client/tvde/tvde_rides_history_screen.dart';

import '../l10n/tr.dart';

/// Separador "Reservas" do cliente — TUDO o que marcou, num sítio só
/// (padrão Uber "Atividade" / Glovo "Pedidos").
///
/// 10/10/2026: só mostrava as mesas de restaurante. Um cliente com uma corrida
/// marcada e outro com uma limpeza, ambas pagas, abriram este separador, não
/// viram nada e julgaram que a reserva se tinha perdido. Agora junta mesas,
/// corridas marcadas, limpezas e marcações (ver `utils/minhas_reservas.dart`)
/// lidas dos quatro stores que já existiam — nenhuma consulta nova.
///
/// Cancelar, reembolsar e pagar ficam nos ecrãs de cada tipo: tocar num
/// cartão abre o ecrã de detalhe que já existe. A excepção é a mesa, que já
/// tinha aqui o "Cancelar" e o "Estou aqui" (RPC client_cancel_reservation,
/// lógica de reembolso <2h) — mantêm-se tal e qual.
class ClientReservationsScreen extends StatefulWidget {
  const ClientReservationsScreen({super.key, this.ativo = true});

  /// Este separador está à vista? Vive num `IndexedStack`, por isso nasce no
  /// arranque da app: só carrega quando a pessoa o abre, e recarrega de cada
  /// vez que volta a ele (pode ter marcado alguma coisa noutro sítio).
  final bool ativo;

  static final ValueNotifier<int> _recarga = ValueNotifier<int>(0);

  /// Acabou de se marcar alguma coisa: recarrega mesmo que o separador já
  /// esteja à vista (aí o `ativo` não muda e não haveria nova ronda).
  static void pedirRecarga() => _recarga.value++;

  @override
  State<ClientReservationsScreen> createState() =>
      _ClientReservationsScreenState();
}

class _ClientReservationsScreenState extends State<ClientReservationsScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;

  /// Uma ronda de carregamento de cada vez.
  Future<void>? _emCurso;
  bool _carregouUmaVez = false;

  /// Tipos que falharam na última ronda. Os outros mostram-se na mesma.
  Set<TipoReserva> _falhas = const {};

  static const _limite = Duration(seconds: 20);

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    ClientReservationsScreen._recarga.addListener(_recarregarAPedido);
    if (widget.ativo) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _carregar());
    }
  }

  @override
  void didUpdateWidget(covariant ClientReservationsScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Depois do fotograma: os loads avisam os stores logo à entrada, e isto
    // corre a meio do build do ClientMainScreen.
    if (widget.ativo && !oldWidget.ativo) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _carregar();
      });
    }
  }

  @override
  void dispose() {
    ClientReservationsScreen._recarga.removeListener(_recarregarAPedido);
    _tabController.dispose();
    super.dispose();
  }

  void _recarregarAPedido() {
    if (!mounted) return;
    _tabController.animateTo(0);
    unawaited(_carregar());
  }

  Future<void> _carregar() => _emCurso ??= _carregarTudo().whenComplete(() {
        _emCurso = null;
      });

  /// Os quatro em paralelo, cada um com o seu try/catch e o seu limite de
  /// tempo: um store que falhe ou pendure não leva os outros três com ele.
  Future<void> _carregarTudo() async {
    if (!mounted) return;
    final mesas = context.read<ReservationStore>();
    final tvde = context.read<TvdeStore>();
    final limpeza = context.read<CleaningStore>();
    final servicos = context.read<ServicesStore>();

    // BUG OS-1 (2026-05-17) — esta lista também tem de receber os updates
    // Realtime das mesas. Idempotente.
    mesas.subscribeMyReservations();

    Future<TipoReserva?> tentar(
        TipoReserva tipo, Future<bool> Function() carga) async {
      try {
        final ok = await carga().timeout(_limite);
        return ok ? null : tipo;
      } catch (e) {
        debugPrint('[ClientReservations] $tipo falhou: $e');
        return tipo;
      }
    }

    final falhas = await Future.wait([
      tentar(TipoReserva.mesa, () async {
        await mesas.fetchMyReservations();
        return mesas.error == null;
      }),
      tentar(TipoReserva.corrida, () async {
        // As agendadas (sem limite de quantidade) e o histórico (onde estão
        // as que já passaram a motorista atribuído aos 20 min, as feitas e
        // as canceladas).
        await Future.wait([tvde.loadMyReservations(), tvde.loadHistory()]);
        return !tvde.historyFailed && !tvde.myReservationsFailed;
      }),
      tentar(TipoReserva.limpeza, () async {
        // O store não lança: diz pela bandeira.
        await limpeza.loadMyBookings();
        return !limpeza.myBookingsFailed;
      }),
      tentar(TipoReserva.marcacao, () async {
        await servicos.fetchMyAppointments();
        return servicos.appointmentsError == null;
      }),
    ]);

    if (!mounted) return;
    setState(() {
      _carregouUmaVez = true;
      _falhas = falhas.whereType<TipoReserva>().toSet();
    });
  }

  // ── Mesa: o que já cá estava (não mexer na lógica) ─────────────────────

  /// Cancela reserva via RPC client_cancel_reservation.
  /// Mantém lógica refund <2h (BR §18). Não usa F2 RPCs (cancel é F3.B scope).
  Future<void> _cancel(ReservationModel r) async {
    final reservedFor = r.reservedFor;
    final hoursUntil =
        reservedFor.difference(DateTime.now()).inMinutes / 60.0;
    final willRefund = hoursUntil >= 2.0;
    final prepaymentEur = (r.prepaymentCents / 100).toStringAsFixed(2);

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Cancelar reserva?'.tr),
        content: Text(
          willRefund
              ? 'Faltam {0}h. Reembolso de €{1} em 5–10 dias.'.trArgs([hoursUntil.toStringAsFixed(1), prepaymentEur])
              : 'Faltam apenas ${hoursUntil.toStringAsFixed(1)}h (<2h). Pré-pagamento de €$prepaymentEur NÃO é devolvido.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text('Voltar'.tr),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: willRefund ? null : Colors.red,
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(willRefund
                ? 'Cancelar com reembolso'.tr
                : 'Cancelar (perco €$prepaymentEur)'),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;

    try {
      await Supabase.instance.client.rpc(
        'client_cancel_reservation',
        params: {
          'p_reservation_id': r.id,
          'p_reason': null,
        },
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Reserva cancelada.'.tr)),
      );
      await context.read<ReservationStore>().fetchMyReservations();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Erro ao cancelar: {0}'.trArgs([e]))),
      );
    }
  }

  /// Cliente carrega "estou aqui" (RPC F2 client_arrived).
  Future<void> _markArrived(ReservationModel r) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      await context.read<ReservationStore>().markArrived(r.id);
      if (!mounted) return;
      messenger.showSnackBar(
        SnackBar(content: Text('Chegada confirmada. O parceiro foi avisado.'.tr)),
      );
    } catch (e) {
      debugPrint('[ClientReservations] markArrived error: $e');
      if (!mounted) return;
      messenger.showSnackBar(SnackBar(
          content: Text(mensagemDeFalhaDeAcao(e,
              trabalho: TrabalhoEmCurso.reserva))));
    }
  }

  // ── Abrir o ecrã de detalhe que já existe para cada tipo ───────────────

  /// Trava LOCAL contra o duplo toque enquanto se decide o ecrã da corrida
  /// (PADRÃO 3.13: nunca um `busy` de store).
  bool _aAbrir = false;

  Future<void> _abrir(ItemReserva item) async {
    if (_aAbrir) return;
    _aAbrir = true;
    try {
      final Widget? ecra = switch (item.origem) {
        final ReservationModel r => ReservationDetailsScreen(
            reservation: r,
            onCancelRequested: () => _cancel(r),
          ),
        final TvdeRide c => await _ecraDaCorrida(item, c),
        final CleaningBooking b => CleaningTrackingScreen(booking: b),
        AppointmentModel() => const MyAppointmentsScreen(),
        _ => null,
      };
      if (ecra == null || !mounted) return;
      final aberto =
          Navigator.push(context, MaterialPageRoute(builder: (_) => ecra));
      _aAbrir = false;
      await aberto;
      if (mounted) unawaited(_carregar());
    } finally {
      _aAbrir = false;
    }
  }

  /// Corrida marcada ainda à espera → "As minhas reservas" do Motorista.
  /// Já com motorista a caminho (aos 20 min) → o ecrã da corrida, pelo mesmo
  /// caminho da retoma no arranque (`retomarCorridaTvdeViva`).
  /// Já acabada ou cancelada, ou viva mas não é a corrida em curso → o
  /// histórico de corridas, que as mostra todas (o "As minhas reservas" só
  /// lista as que ainda estão 'agendada').
  Future<Widget?> _ecraDaCorrida(ItemReserva item, TvdeRide c) async {
    if (item.grupo != GrupoReserva.proximas) {
      return const TvdeRidesHistoryScreen();
    }
    if (c.status == 'agendada') return const TvdeMyReservationsScreen();
    final store = context.read<TvdeStore>();
    try {
      await store.loadActiveRide().timeout(_limite);
    } catch (e) {
      debugPrint('[ClientReservations] loadActiveRide falhou: $e');
    }
    final viva = store.activeRide;
    if (viva != null &&
        viva.id == c.id &&
        viva.isLive &&
        !viva.isAwaitingPayment) {
      return const TvdeRideTrackingScreen();
    }
    return const TvdeRidesHistoryScreen();
  }

  @override
  Widget build(BuildContext context) {
    final mesas = context.watch<ReservationStore>().myReservations;
    final tvde = context.watch<TvdeStore>();
    final limpezas = context.watch<CleaningStore>().bookings;
    final marcacoes = context.watch<ServicesStore>().myAppointments;

    // A cópia mais fresca de cada corrida vai à frente: a viva vem por
    // realtime; das outras duas listas, a que falhou a última leitura ficou
    // com cópias velhas e vai para trás.
    final agendadasPrimeiro = !tvde.myReservationsFailed;
    final dados = juntarReservas(
      mesas: mesas,
      corridas: [
        if (tvde.activeRide != null) tvde.activeRide!,
        if (agendadasPrimeiro) ...tvde.reservations,
        ...tvde.history,
        if (!agendadasPrimeiro) ...tvde.reservations,
      ],
      limpezas: limpezas,
      marcacoes: marcacoes,
      agora: DateTime.now(),
    );

    final Widget corpo;
    if (!_carregouUmaVez && dados.vazio) {
      corpo = const Center(child: CircularProgressIndicator());
    } else {
      corpo = TabBarView(
        controller: _tabController,
        children: [
          _Lista(
            itens: dados.proximas,
            falhas: _falhas,
            onRefresh: _carregar,
            onTap: _abrir,
            vazio: const _VazioProximas(),
            acoesDaMesa: _acoesDaMesa,
          ),
          _Lista(
            itens: dados.passadas,
            falhas: _falhas,
            onRefresh: _carregar,
            onTap: _abrir,
            vazio: _VazioSimples(
              icon: Icons.history,
              texto: 'Ainda não tens nada no histórico'.tr,
            ),
          ),
          _Lista(
            itens: dados.canceladas,
            falhas: _falhas,
            onRefresh: _carregar,
            onTap: _abrir,
            vazio: _VazioSimples(
              icon: Icons.cancel_outlined,
              texto: 'Nada cancelado'.tr,
            ),
          ),
        ],
      );
    }

    return Scaffold(
      floatingActionButton: const BoraSupportFab(),
      appBar: AppBar(
        title: Text('As minhas reservas'.tr),
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        elevation: 0,
        flexibleSpace: const DecoratedBox(
          decoration: BoxDecoration(gradient: AppColors.headerGradient),
        ),
        bottom: TabBar(
          controller: _tabController,
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white70,
          indicatorColor: Colors.white,
          // Em 320 px o "Canceladas" saía cortado com a folga normal.
          labelPadding: const EdgeInsets.symmetric(horizontal: 4),
          tabs: [
            Tab(text: 'Próximas'.tr),
            Tab(text: 'Passadas'.tr),
            Tab(text: 'Canceladas'.tr),
          ],
        ),
      ),
      body: corpo,
    );
  }

  /// "Estou aqui" e "Cancelar" das mesas por vir — os mesmos de antes.
  List<Widget> _acoesDaMesa(ItemReserva item) {
    final r = item.origem;
    if (r is! ReservationModel) return const [];
    return [
      if (r.isApproved && r.arrivedAt == null)
        TextButton.icon(
          onPressed: () => _markArrived(r),
          icon: const Icon(Icons.location_on, size: 18),
          label: Text('Estou aqui'.tr),
        ),
      TextButton.icon(
        onPressed: () => _cancel(r),
        icon: const Icon(Icons.cancel_outlined, size: 18),
        label: Text('Cancelar'.tr),
        style: TextButton.styleFrom(foregroundColor: AppColors.error),
      ),
    ];
  }
}

class _Lista extends StatelessWidget {
  const _Lista({
    required this.itens,
    required this.falhas,
    required this.onRefresh,
    required this.onTap,
    required this.vazio,
    this.acoesDaMesa,
  });

  final List<ItemReserva> itens;
  final Set<TipoReserva> falhas;
  final Future<void> Function() onRefresh;
  final void Function(ItemReserva) onTap;
  final Widget vazio;
  final List<Widget> Function(ItemReserva)? acoesDaMesa;

  @override
  Widget build(BuildContext context) {
    return RefreshIndicator(
      onRefresh: onRefresh,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 96),
        children: [
          if (falhas.isNotEmpty) _AvisoFalha(falhas: falhas),
          if (itens.isEmpty)
            vazio
          else
            for (final i in itens)
              _CartaoReserva(
                item: i,
                onTap: () => onTap(i),
                acoes: i.tipo == TipoReserva.mesa && acoesDaMesa != null
                    ? acoesDaMesa!(i)
                    : const [],
              ),
        ],
      ),
    );
  }
}

/// Um cartão para qualquer dos quatro tipos.
class _CartaoReserva extends StatelessWidget {
  const _CartaoReserva({
    required this.item,
    required this.onTap,
    this.acoes = const [],
  });

  final ItemReserva item;
  final VoidCallback onTap;
  final List<Widget> acoes;

  @override
  Widget build(BuildContext context) {
    final estado = _estado(item);
    final pagamento =
        item.grupo == GrupoReserva.canceladas ? null : _pagamento(item);
    final linhas = _linhas(item);

    return Card(
      margin: const EdgeInsets.symmetric(vertical: 6),
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: const BorderSide(color: AppColors.divider),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: AppColors.primaryLight,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(_icone(item.tipo),
                        color: AppColors.primary, size: 24),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _nomeDoTipo(item.tipo),
                          style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            color: AppColors.primary,
                            letterSpacing: 0.2,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          _quando(item.quando),
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w800,
                            color: AppColors.textPrimary,
                          ),
                        ),
                        for (final l in linhas) ...[
                          const SizedBox(height: 2),
                          Text(
                            l,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 13,
                              color: AppColors.textSecondary,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  const Icon(Icons.chevron_right,
                      color: AppColors.textSubtle),
                ],
              ),
              const SizedBox(height: 10),
              Wrap(
                spacing: 8,
                runSpacing: 6,
                children: [
                  _Selo(texto: estado.$1, cor: estado.$2),
                  if (pagamento != null)
                    _Selo(texto: pagamento.$1, cor: pagamento.$2),
                ],
              ),
              if (acoes.isNotEmpty) ...[
                const SizedBox(height: 4),
                Wrap(spacing: 4, children: acoes),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _Selo extends StatelessWidget {
  const _Selo({required this.texto, required this.cor});
  final String texto;
  final Color cor;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: cor.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        texto,
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w700,
          color: cor,
        ),
      ),
    );
  }
}

class _AvisoFalha extends StatelessWidget {
  const _AvisoFalha({required this.falhas});
  final Set<TipoReserva> falhas;

  @override
  Widget build(BuildContext context) {
    final nomes = [
      for (final t in TipoReserva.values)
        if (falhas.contains(t)) _nomeNoPlural(t),
    ].join(', ');
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.warning.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          const Icon(Icons.wifi_off_rounded, color: AppColors.warning),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'Não conseguimos carregar: {0}. Puxa para baixo para tentar de novo.'
                  .trArgs([nomes]),
              style: const TextStyle(
                  fontSize: 13, color: AppColors.textPrimary),
            ),
          ),
        ],
      ),
    );
  }
}

/// Próximas vazia: texto genérico e atalhos para marcar alguma coisa.
class _VazioProximas extends StatelessWidget {
  const _VazioProximas();

  @override
  Widget build(BuildContext context) {
    Widget atalho(IconData icon, String texto, String categoria) =>
        OutlinedButton.icon(
          onPressed: () => abrirCategoria(context, categoria),
          icon: Icon(icon, size: 18),
          label: Text(texto),
          style: OutlinedButton.styleFrom(
            foregroundColor: AppColors.primary,
            side: const BorderSide(color: AppColors.primary),
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12)),
          ),
        );

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 56, 20, 0),
      child: Column(
        children: [
          const Icon(Icons.event_available_outlined,
              size: 56, color: AppColors.textSubtle),
          const SizedBox(height: 16),
          Text(
            'Ainda não tens nada marcado'.tr,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 17,
              fontWeight: FontWeight.w700,
              color: AppColors.textPrimary,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'Mesas, corridas para mais tarde, limpezas e marcações aparecem todas aqui.'
                .tr,
            textAlign: TextAlign.center,
            style: const TextStyle(
                fontSize: 14, color: AppColors.textSecondary),
          ),
          const SizedBox(height: 20),
          Wrap(
            alignment: WrapAlignment.center,
            spacing: 8,
            runSpacing: 8,
            children: [
              atalho(Icons.restaurant, 'Restaurantes'.tr, 'restaurantes'),
              atalho(Icons.local_taxi_outlined, 'Motorista'.tr, 'motorista'),
              atalho(Icons.cleaning_services_outlined, 'Limpeza'.tr,
                  'limpeza'),
              atalho(Icons.content_cut, 'Serviços'.tr, 'servicos'),
            ],
          ),
        ],
      ),
    );
  }
}

class _VazioSimples extends StatelessWidget {
  const _VazioSimples({required this.icon, required this.texto});
  final IconData icon;
  final String texto;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(32, 80, 32, 0),
      child: Column(
        children: [
          Icon(icon, size: 56, color: AppColors.textSubtle),
          const SizedBox(height: 16),
          Text(
            texto,
            textAlign: TextAlign.center,
            style:
                const TextStyle(color: AppColors.textSecondary, fontSize: 15),
          ),
        ],
      ),
    );
  }
}

// ── Textos (PT-PT, pelo .tr) ──────────────────────────────────────────────

IconData _icone(TipoReserva t) => switch (t) {
      TipoReserva.mesa => Icons.restaurant,
      TipoReserva.corrida => Icons.local_taxi,
      TipoReserva.limpeza => Icons.cleaning_services,
      TipoReserva.marcacao => Icons.content_cut,
    };

String _nomeDoTipo(TipoReserva t) => switch (t) {
      TipoReserva.mesa => 'Mesa'.tr,
      TipoReserva.corrida => 'Corrida marcada'.tr,
      TipoReserva.limpeza => 'Limpeza'.tr,
      TipoReserva.marcacao => 'Marcação'.tr,
    };

String _nomeNoPlural(TipoReserva t) => switch (t) {
      TipoReserva.mesa => 'mesas'.tr,
      TipoReserva.corrida => 'corridas'.tr,
      TipoReserva.limpeza => 'limpezas'.tr,
      TipoReserva.marcacao => 'marcações'.tr,
    };

/// Dia e hora em hora de Lisboa ("Hoje às 05:00", "Amanhã às 13:30",
/// "15/10 às 13:30").
String _quando(DateTime instante) {
  final p = paredeLisboa(instante);
  final hora =
      '${p.hour.toString().padLeft(2, '0')}:${p.minute.toString().padLeft(2, '0')}';
  switch (diasDeDiferencaEmLisboa(instante, DateTime.now())) {
    case 0:
      return 'Hoje às {0}'.trArgs([hora]);
    case 1:
      return 'Amanhã às {0}'.trArgs([hora]);
    case -1:
      return 'Ontem às {0}'.trArgs([hora]);
  }
  final hoje = paredeLisboa(DateTime.now());
  var data =
      '${p.day.toString().padLeft(2, '0')}/${p.month.toString().padLeft(2, '0')}';
  if (p.year != hoje.year) data = '$data/${p.year}';
  return '{0} às {1}'.trArgs([data, hora]);
}

/// Loja, destino ou morada, e um pormenor por baixo.
List<String> _linhas(ItemReserva item) {
  final o = item.origem;
  final sitio = item.sitio?.trim();
  switch (o) {
    case final ReservationModel r:
      return [
        (sitio == null || sitio.isEmpty) ? 'Restaurante'.tr : sitio,
        r.people == 1 ? '1 pessoa'.tr : '{0} pessoas'.trArgs([r.people]),
      ];
    case final TvdeRide c:
      return [
        if (sitio != null && sitio.isNotEmpty) 'Para {0}'.trArgs([sitio]),
        if ((c.originLabel ?? '').trim().isNotEmpty)
          'De {0}'.trArgs([c.originLabel!.trim()]),
      ];
    case final CleaningBooking b:
      return [
        if (sitio != null && sitio.isNotEmpty) sitio,
        b.typeLabel.tr,
      ];
    case final AppointmentModel a:
      return [
        (sitio == null || sitio.isEmpty) ? 'Serviço'.tr : sitio,
        if ((a.serviceName ?? '').trim().isNotEmpty) a.serviceName!.trim(),
      ];
  }
  return [if (sitio != null && sitio.isNotEmpty) sitio];
}

(String, Color) _estado(ItemReserva item) {
  const verde = AppColors.success;
  const cinza = AppColors.textSecondary;
  const vermelho = AppColors.error;
  const amarelo = AppColors.warning;
  return switch (item.estado) {
    EstadoReserva.aguardaPagamento => ('A aguardar pagamento'.tr, amarelo),
    EstadoReserva.aguardaConfirmacao => ('A aguardar confirmação'.tr, cinza),
    EstadoReserva.agendada => ('Agendada'.tr, cinza),
    EstadoReserva.procuraMotorista => ('À procura de motorista'.tr, cinza),
    EstadoReserva.confirmada => ('Confirmada'.tr, verde),
    EstadoReserva.motoristaConfirmado => ('Motorista confirmado'.tr, verde),
    EstadoReserva.aCaminho => ('A caminho'.tr, verde),
    EstadoReserva.motoristaChegou => ('O motorista chegou'.tr, verde),
    EstadoReserva.emCurso => ('Em curso'.tr, verde),
    EstadoReserva.porConfirmarFim => ('Concluída — confirma'.tr, amarelo),
    EstadoReserva.concluida => ('Concluída'.tr, cinza),
    EstadoReserva.naoCompareceu => ('Não compareceu'.tr, vermelho),
    EstadoReserva.cancelada => ('Cancelada'.tr, vermelho),
    EstadoReserva.semPrestador => item.tipo == TipoReserva.corrida
        ? ('Sem motoristas disponíveis'.tr, vermelho)
        : ('Sem profissional disponível'.tr, vermelho),
  };
}

(String, Color)? _pagamento(ItemReserva item) => switch (item.pagamento) {
      PagamentoReserva.pago => ('Pago'.tr, AppColors.success),
      // Amarelo, não laranja: o laranja do ecrã é o botão de suporte.
      PagamentoReserva.porPagar => ('Por pagar'.tr, AppColors.warning),
      PagamentoReserva.emDinheiro => item.tipo == TipoReserva.corrida
          ? ('Pagas em dinheiro ao motorista'.tr, AppColors.textSecondary)
          : ('Pagas em dinheiro'.tr, AppColors.textSecondary),
      PagamentoReserva.noPacote =>
        ('Incluída no pacote ida e volta'.tr, AppColors.success),
      PagamentoReserva.noPlano => ('Incluída no plano'.tr, AppColors.success),
      PagamentoReserva.semPagamento =>
        ('Sem pagamento antecipado'.tr, AppColors.textSecondary),
      PagamentoReserva.desconhecido => null,
    };
