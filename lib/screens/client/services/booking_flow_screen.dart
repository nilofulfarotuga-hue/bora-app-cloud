import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../config/app_colors.dart';
import '../../../config/app_spacing.dart';
import '../../../models/appointment_model.dart';
import '../../../models/provider_service_model.dart';
import '../../../models/service_provider_model.dart';
import '../../../models/staff_member_model.dart';
import '../../../services/saved_card_checkout.dart';
import '../../../stores/services_store.dart';
import '../../../widgets/bora/bora_accent_button.dart';
import '../../../widgets/bora/bora_primary_button.dart';
import '../../../widgets/bora/bora_screen_app_bar.dart';
import '../../../widgets/bora/coming_soon.dart';
import '../../../widgets/services/staff_avatar.dart';
import '../reservation/reservation_payment_method_sheet.dart';
import 'appointment_mbway_waiting_dialog.dart';
import 'booking_success_screen.dart';

import '../../../l10n/tr.dart';

/// Vertical Serviços — fluxo de marcação em 6 passos (PageView):
/// 1) serviço  2) profissional (com "Qualquer disponível")  3) dia
/// 4) hora (slots via get_available_slots)  5) confirmação + pagamento Stripe
/// 6) sucesso (ecrã próprio).
class BookingFlowScreen extends StatefulWidget {
  const BookingFlowScreen({
    super.key,
    required this.provider,
    this.preselectedService,
    this.rescheduleOf,
  });

  final ServiceProviderModel provider;
  final ProviderServiceModel? preselectedService;

  /// BLOCO E (2026-07-28) — quando preenchido, o ecrã corre em MODO
  /// REAGENDAMENTO: mesmo serviço, mesmo profissional, salta directo para a
  /// escolha do dia e, no fim, chama `client_reschedule_appointment`. NÃO cria
  /// marcação nova e NÃO passa pelo Stripe — o valor já pago fica na mesma
  /// linha (mesmo `deposit_pi`).
  final AppointmentModel? rescheduleOf;

  @override
  State<BookingFlowScreen> createState() => _BookingFlowScreenState();
}

/// Sentinela para a opção "Qualquer profissional disponível".
const String _kAnyStaffId = '__any__';

class _BookingFlowScreenState extends State<BookingFlowScreen> {
  late final PageController _pageController;
  late int _step;

  /// Índice do passo "Escolher dia" — porta de entrada do reagendamento.
  static const int _kDayStep = 2;

  // Catálogo carregado.
  late Future<void> _loadFuture;
  List<ProviderServiceModel> _services = const [];
  List<StaffMemberModel> _staff = const [];

  // Janela de marcação: lida de platform_settings (appointment_max_advance_days)
  // para o Danilo ajustar sem rebuild; default seguro = 365 dias (1 ano).
  int _maxAdvanceDays = 365;

  // Nomes completos dos meses em PT-PT (cabeçalhos de secção no passo do dia).
  static const _ptMonths = [
    'Janeiro', 'Fevereiro', 'Março', 'Abril', 'Maio', 'Junho',
    'Julho', 'Agosto', 'Setembro', 'Outubro', 'Novembro', 'Dezembro',
  ];

  // Disponibilidade do profissional escolhido — pré-marcação VISUAL dos dias
  // (o servidor continua a ser a verdade final via get_available_slots).
  // Carregada 1x ao entrar no passo do dia. _availReady só fica true após um
  // load bem-sucedido; em falha/loading, todos os dias ficam disponíveis.
  bool _loadingAvail = false;
  bool _availReady = false;
  String? _availLoadedForStaffId;
  Map<String, Set<int>> _weeklyByStaff = const {};
  Map<String, Map<String, bool>> _exceptionsByStaff = const {};

  // Seleções.
  ProviderServiceModel? _service;
  String _staffId = _kAnyStaffId; // _kAnyStaffId = "qualquer"
  DateTime? _day;
  DateTime? _slot;
  String? _resolvedStaffId; // staff concreto resolvido para o slot escolhido

  // Estado do passo de horas.
  bool _loadingSlots = false;
  String? _slotsError;
  List<_SlotOption> _slotOptions = const [];

  bool _booking = false;

  final _notesCtrl = TextEditingController();

  /// MODO REAGENDAMENTO (BLOCO E).
  bool get _isReschedule => widget.rescheduleOf != null;

  @override
  void initState() {
    super.initState();
    _service = widget.preselectedService;
    if (_isReschedule) {
      // Mesmo profissional por defeito; o serviço é resolvido no _loadCatalog
      // (só lá temos a lista para casar pelo id).
      _staffId = widget.rescheduleOf!.staffId ?? _kAnyStaffId;
    }
    // Reagendar entra directo na escolha do dia (serviço/profissional vêm da
    // marcação original). initialPage em vez de animateToPage: o PageView só
    // existe depois de _loadFuture resolver.
    _step = _isReschedule ? _kDayStep : 0;
    _pageController = PageController(initialPage: _step);
    _loadFuture = _loadCatalog();
  }

  @override
  void dispose() {
    _pageController.dispose();
    _notesCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadCatalog() async {
    final store = context.read<ServicesStore>();
    final results = await Future.wait([
      store.fetchServices(widget.provider.id),
      store.fetchStaff(widget.provider.id),
      store.fetchMaxAdvanceDays(),
    ]);
    if (!mounted) return;
    setState(() {
      _services = results[0] as List<ProviderServiceModel>;
      _staff = results[1] as List<StaffMemberModel>;
      _maxAdvanceDays = results[2] as int;
      // Se o serviço pré-seleccionado não está na lista activa, ignora.
      if (_service != null &&
          !_services.any((s) => s.id == _service!.id)) {
        _service = null;
      }
      // Reagendamento: bloqueia serviço + profissional da marcação original e
      // arranca já no passo do dia.
      final appt = widget.rescheduleOf;
      if (appt != null) {
        for (final s in _services) {
          if (s.id == appt.serviceId) _service = s;
        }
        if (appt.staffId != null &&
            _staff.any((st) => st.id == appt.staffId)) {
          _staffId = appt.staffId!;
          _resolvedStaffId = appt.staffId;
        }
      }
    });
    // Defensivo: se o serviço original já não estiver activo, o reagendamento
    // não tem base — cai no passo 0 para o cliente escolher de novo.
    if (_isReschedule && mounted && _service == null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _goTo(0);
      });
    }
  }

  /// Carrega (1x por seleção de profissional) o padrão semanal + exceções do
  /// staff escolhido — ou de TODOS, se "Qualquer disponível". Fail-safe: em
  /// erro, deixa todos os dias disponíveis (não bloqueia a marcação).
  Future<void> _loadAvailability() async {
    if (_availLoadedForStaffId == _staffId) return;
    final staffIds = _staffId == _kAnyStaffId
        ? _staff.map((s) => s.id).toList()
        : <String>[_staffId];
    if (staffIds.isEmpty) return;
    setState(() {
      _loadingAvail = true;
      _availReady = false;
    });
    final store = context.read<ServicesStore>();
    final now = DateTime.now();
    final from = DateTime(now.year, now.month, now.day);
    final to = DateTime(from.year, from.month, from.day + _maxAdvanceDays);
    try {
      final results = await Future.wait([
        store.fetchWeeklyWorkingDays(staffIds),
        store.fetchExceptionsRange(staffIds: staffIds, from: from, to: to),
      ]);
      if (!mounted) return;
      setState(() {
        _weeklyByStaff = results[0] as Map<String, Set<int>>;
        _exceptionsByStaff = results[1] as Map<String, Map<String, bool>>;
        _availLoadedForStaffId = _staffId;
        _availReady = true;
        _loadingAvail = false;
      });
    } catch (e) {
      if (!mounted) return;
      // Não bloquear: sem dados, todos os dias ficam disponíveis (como antes).
      setState(() {
        _availReady = false;
        _loadingAvail = false;
      });
    }
  }

  String _ymd(DateTime d) => '${d.year.toString().padLeft(4, '0')}-'
      '${d.month.toString().padLeft(2, '0')}-'
      '${d.day.toString().padLeft(2, '0')}';

  /// O profissional escolhido trabalha nesse dia? (pré-marcação visual)
  /// Exceção da data tem prioridade sobre o padrão semanal; "Qualquer" = pelo
  /// menos um profissional. Sem dados carregados → true (não desativa nada).
  bool _dayAvailable(DateTime day) {
    if (!_availReady) return true;
    final ymd = _ymd(day);
    final tableDow = day.weekday % 7; // Dom(7)→0 … Sáb(6)→6.
    bool worksForStaff(String sid) {
      final ex = _exceptionsByStaff[sid]?[ymd];
      if (ex != null) return ex;
      return _weeklyByStaff[sid]?.contains(tableDow) ?? false;
    }

    if (_staffId == _kAnyStaffId) {
      if (_staff.isEmpty) return true;
      return _staff.any((s) => worksForStaff(s.id));
    }
    return worksForStaff(_staffId);
  }

  // ─── Navegação entre passos ───────────────────────────────────────────────

  void _goTo(int step) {
    setState(() => _step = step);
    _pageController.animateToPage(
      step,
      duration: const Duration(milliseconds: 260),
      curve: Curves.easeInOut,
    );
  }

  void _next() => _goTo(_step + 1);

  /// Primeiro passo navegável — em reagendamento o serviço/profissional já
  /// estão fixos, por isso o passo do dia é o início.
  int get _firstStep => _isReschedule ? _kDayStep : 0;

  Future<bool> _onWillPop() async {
    if (_step <= _firstStep) return true;
    _goTo(_step - 1);
    return false;
  }

  List<String> get _titles => [
        'Escolher serviço'.tr,
        'Escolher profissional'.tr,
        'Escolher dia'.tr,
        'Escolher hora'.tr,
        _isReschedule ? 'Confirmar reagendamento' : 'Confirmar e pagar',
      ];

  // ─── Passo 3 → 4: carregar slots ───────────────────────────────────────────

  Future<void> _loadSlotsForDay(DateTime day) async {
    setState(() {
      _loadingSlots = true;
      _slotsError = null;
      _slotOptions = const [];
      _slot = null;
      _resolvedStaffId = null;
    });
    final store = context.read<ServicesStore>();
    try {
      // Para staff concreto: 1 chamada. Para "qualquer": uma chamada por
      // profissional, e cada slot é atribuído ao 1º profissional disponível.
      final staffToQuery = _staffId == _kAnyStaffId
          ? _staff
          : _staff.where((s) => s.id == _staffId).toList();

      final Map<DateTime, String> firstStaffBySlot = {};
      for (final s in staffToQuery) {
        final slots = await store.getAvailableSlots(
          staffId: s.id,
          serviceId: _service!.id,
          day: day,
        );
        for (final dt in slots) {
          firstStaffBySlot.putIfAbsent(dt, () => s.id);
        }
      }
      final options = firstStaffBySlot.entries
          .map((e) => _SlotOption(start: e.key, staffId: e.value))
          .toList()
        ..sort((a, b) => a.start.compareTo(b.start));
      if (!mounted) return;
      setState(() => _slotOptions = options);
    } catch (e) {
      if (!mounted) return;
      setState(() =>
          _slotsError = e.toString().replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _loadingSlots = false);
    }
  }

  // ─── Passo 5: marcar + pagar ────────────────────────────────────────────────

  /// FIM DO SINAL (2026-08-03) — a marcação cobra SEMPRE o preço cheio do
  /// serviço escolhido. Espelha o que o servidor grava em
  /// `appointments.deposit_cents` (a chave da RPC manteve o nome antigo, mas o
  /// valor é o total do serviço); a Edge `create-appointment-payment-intent`
  /// cobra esse valor.
  double get _amountDueEur => (_service?.priceCents ?? 0) / 100.0;

  String get _amountDueLabel => '€${_amountDueEur.toStringAsFixed(2)}';

  Future<void> _confirmAndPay() async {
    if (_booking || _slot == null || _service == null) return;
    // "Em breve": nunca chegar ao Stripe. O servidor rejeita na mesma
    // (STORE_COMING_SOON) antes de criar o PaymentIntent.
    if (widget.provider.comingSoon) {
      showComingSoonBlockedSnackBar(context);
      return;
    }
    final staffId = _resolvedStaffId;
    if (staffId == null) return;

    // M7: paridade com reservas — escolha Cartão | MBWay, NUNCA dinheiro.
    final choice = await showModalBottomSheet<ReservationPaymentChoice>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => ReservationPaymentMethodSheet(
        amountEur: _amountDueEur,
        title: 'Pagamento da marcação'.tr,
      ),
    );
    if (choice == null || !mounted) return;

    setState(() => _booking = true);
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    try {
      if (choice.method == ReservationPaymentMethod.mbway) {
        await _payWithMbway(choice.mbwayPhone!, staffId, messenger, navigator);
        return;
      }
      // Carteira Unica (2026-07-21): cartao padrao + digital/rosto antes de
      // criar a marcacao e o PaymentIntent. Recusar nao cobra nada.
      final auth =
          await SavedCardCheckout.instance.authorize(amountEur: _amountDueEur);
      if (!mounted) return;
      if (auth.cancelled) {
        messenger.showSnackBar(SnackBar(
            content: Text('Pagamento cancelado. Não foi cobrado nada.'.tr)));
        return;
      }
      final result = await context.read<ServicesStore>().bookAndPay(
            serviceId: _service!.id,
            staffId: staffId,
            scheduledAt: _slot!,
            notes: _notesCtrl.text.trim().isEmpty
                ? null
                : _notesCtrl.text.trim(),
            context: context,
            savedPmId: auth.savedPmId,
          );
      if (!mounted) return;
      if (result.success) {
        navigator.pushReplacement(
          MaterialPageRoute(
            builder: (_) => BookingSuccessScreen(
              providerName: widget.provider.name,
              serviceName: _service!.name,
              scheduledAt: _slot!,
              paidCents: _service!.priceCents,
            ),
          ),
        );
        return;
      }
      // Cancelamento ou erro → snackbar (mantém-se no passo).
      messenger.showSnackBar(
        SnackBar(
          content: Text(result.errorMessage ?? 'Não foi possível concluir.'),
          backgroundColor:
              result.cancelled ? AppColors.accent : AppColors.error,
        ),
      );
    } finally {
      if (mounted) setState(() => _booking = false);
    }
  }

  /// BLOCO E (2026-07-28) — confirma o REAGENDAMENTO. Uma única chamada à RPC
  /// `client_reschedule_appointment`: sem marcação nova, sem PaymentIntent,
  /// sem Stripe. O `deposit_pi` da marcação original fica intacto.
  Future<void> _confirmReschedule() async {
    final appt = widget.rescheduleOf;
    if (_booking || _slot == null || appt == null) return;
    setState(() => _booking = true);
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    try {
      final result = await context.read<ServicesStore>().rescheduleAppointment(
            appointmentId: appt.id,
            newScheduledAt: _slot!,
            staffId: _resolvedStaffId,
          );
      if (!mounted) return;
      final left = (result['reschedules_left'] as num?)?.toInt();
      final extra = switch (left) {
        0 => '\nJá não podes reagendar esta marcação.'.tr,
        1 => '\nPodes reagendar mais 1 vez.'.tr,
        _ => '',
      };
      navigator.pop(true);
      messenger.showSnackBar(
        SnackBar(
          backgroundColor: AppColors.success,
          duration: const Duration(seconds: 6),
          content: Text(
            'Marcação reagendada para {0} às {1}. Não há nada a pagar — o valor já está reservado.{2}'.trArgs([_formatDayLong(_slot!), _formatTime(_slot!), extra]),
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      messenger.showSnackBar(SnackBar(
        content: Text(e.toString().replaceFirst('Exception: ', '')),
        backgroundColor: AppColors.error,
      ));
    } finally {
      if (mounted) setState(() => _booking = false);
    }
  }

  /// Ramo MBWay (M7): cria a marcação + PI mb_way (push para o telemóvel) e
  /// aguarda a confirmação no AppointmentMBWayWaitingDialog. Em timeout ou
  /// cancelamento, cancela a marcação órfã (best-effort).
  Future<void> _payWithMbway(
    String mbwayPhone,
    String staffId,
    ScaffoldMessengerState messenger,
    NavigatorState navigator,
  ) async {
    final store = context.read<ServicesStore>();
    final result = await store.bookMbway(
      serviceId: _service!.id,
      staffId: staffId,
      scheduledAt: _slot!,
      mbwayPhone: mbwayPhone,
      notes: _notesCtrl.text.trim().isEmpty ? null : _notesCtrl.text.trim(),
    );
    if (!mounted) return;
    if (!result.success || result.appointmentId == null) {
      messenger.showSnackBar(
        SnackBar(
          content: Text(result.errorMessage ?? 'Não foi possível concluir.'),
          backgroundColor: AppColors.error,
        ),
      );
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => AppointmentMBWayWaitingDialog(
        appointmentId: result.appointmentId!,
        amount: _amountDueEur,
      ),
    );
    if (!mounted) return;

    if (confirmed == true) {
      navigator.pushReplacement(
        MaterialPageRoute(
          builder: (_) => BookingSuccessScreen(
            providerName: widget.provider.name,
            serviceName: _service!.name,
            scheduledAt: _slot!,
            paidCents: _service!.priceCents,
          ),
        ),
      );
      return;
    }

    // Timeout/cancelado — liberta o slot cancelando a marcação pendente.
    try {
      await store.cancelAppointment(result.appointmentId!,
          reason: 'mbway_nao_confirmado');
    } catch (_) {}
    messenger.showSnackBar(
      SnackBar(
        content: Text('Pagamento MBWay não confirmado ou expirou.'.tr),
        backgroundColor: AppColors.error,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: _step <= _firstStep,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _onWillPop();
      },
      child: Scaffold(
        backgroundColor: AppColors.background,
        appBar: BoraScreenAppBar(title: _titles[_step]),
        body: SafeArea(
          child: FutureBuilder<void>(
            future: _loadFuture,
            builder: (context, snap) {
              if (snap.connectionState == ConnectionState.waiting) {
                return const Center(child: CircularProgressIndicator());
              }
              if (snap.hasError) {
                return _LoadError(
                  message: snap.error.toString().replaceFirst('Exception: ', ''),
                  onRetry: () => setState(() => _loadFuture = _loadCatalog()),
                );
              }
              return Column(
                children: [
                  _StepIndicator(step: _step, total: _titles.length),
                  Expanded(
                    child: PageView(
                      controller: _pageController,
                      physics: const NeverScrollableScrollPhysics(),
                      children: [
                        _serviceStep(),
                        _staffStep(),
                        _dayStep(),
                        _timeStep(),
                        _confirmStep(),
                      ],
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }

  // ─── Passo 1: serviço ────────────────────────────────────────────────────

  Widget _serviceStep() {
    if (_services.isEmpty) {
      return _EmptyStep(
        icon: Icons.content_cut,
        text: 'Este prestador ainda não tem serviços.'.tr,
      );
    }
    return ListView.separated(
      padding: const EdgeInsets.all(Spacing.lg),
      itemCount: _services.length,
      separatorBuilder: (_, __) => const SizedBox(height: Spacing.sm),
      itemBuilder: (_, i) {
        final s = _services[i];
        final selected = _service?.id == s.id;
        return _SelectableCard(
          selected: selected,
          onTap: () {
            setState(() => _service = s);
            _next();
          },
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      s.name,
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: AppColors.textPrimary,
                      ),
                    ),
                    const SizedBox(height: Spacing.xxs),
                    Text(
                      s.durationLabel,
                      style: const TextStyle(
                        fontSize: 12,
                        color: AppColors.textSubtle,
                      ),
                    ),
                  ],
                ),
              ),
              Text(
                s.priceLabel,
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w800,
                  color: AppColors.primary,
                  fontFeatures: [FontFeature.tabularFigures()],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  // ─── Passo 2: profissional ─────────────────────────────────────────────────

  Widget _staffStep() {
    return ListView(
      padding: const EdgeInsets.all(Spacing.lg),
      children: [
        _SelectableCard(
          selected: _staffId == _kAnyStaffId,
          onTap: () {
            setState(() => _staffId = _kAnyStaffId);
            _loadAvailability();
            _next();
          },
          child: Row(
            children: [
              const CircleAvatar(
                radius: 22,
                backgroundColor: AppColors.primaryLight,
                child: Icon(Icons.groups_outlined, color: AppColors.primary),
              ),
              const SizedBox(width: Spacing.md),
              Expanded(
                child: Text(
                  'Qualquer disponível'.tr,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textPrimary,
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: Spacing.sm),
        for (final st in _staff) ...[
          _SelectableCard(
            selected: _staffId == st.id,
            onTap: () {
              setState(() => _staffId = st.id);
              _loadAvailability();
              _next();
            },
            child: Row(
              children: [
                StaffAvatar(staff: st),
                const SizedBox(width: Spacing.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        st.name,
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                          color: AppColors.textPrimary,
                        ),
                      ),
                      if (st.specialties.isNotEmpty) ...[
                        const SizedBox(height: Spacing.xxs),
                        Text(
                          st.specialties.join(' · '),
                          style: const TextStyle(
                            fontSize: 12,
                            color: AppColors.textSecondary,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: Spacing.sm),
        ],
      ],
    );
  }

  // ─── Passo 3: dia ──────────────────────────────────────────────────────────

  Widget _dayStep() {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    // Aritmética de calendário (não Duration) → imune a mudanças de hora (DST).
    final span = (_maxAdvanceDays - 1).clamp(0, 3660);
    final lastDay = DateTime(today.year, today.month, today.day + span);

    // Agrupa os dias por mês (de hoje até ao limite). Cada mês é uma secção com
    // cabeçalho "Mês Ano" seguido da grelha de 4 colunas de _DayCell.
    final sections = <_MonthSection>[];
    var cursor = DateTime(today.year, today.month, 1);
    final lastMonth = DateTime(lastDay.year, lastDay.month, 1);
    while (!cursor.isAfter(lastMonth)) {
      final monthEnd = DateTime(cursor.year, cursor.month + 1, 0);
      final rangeStart = today.isAfter(cursor) ? today : cursor;
      final rangeEnd = lastDay.isBefore(monthEnd) ? lastDay : monthEnd;
      final days = <DateTime>[
        for (var d = rangeStart;
            !d.isAfter(rangeEnd);
            d = DateTime(d.year, d.month, d.day + 1))
          d,
      ];
      if (days.isNotEmpty) {
        sections.add(_MonthSection(
          label: '${_ptMonths[cursor.month - 1]} ${cursor.year}',
          days: days,
        ));
      }
      cursor = DateTime(cursor.year, cursor.month + 1, 1);
    }

    return CustomScrollView(
      slivers: [
        if (_loadingAvail)
          SliverToBoxAdapter(
            child: Padding(
              padding:
                  const EdgeInsets.fromLTRB(Spacing.lg, Spacing.sm, Spacing.lg, 0),
              child: Row(
                children: [
                  const SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                  const SizedBox(width: Spacing.sm),
                  Text(
                    'A verificar disponibilidade…'.tr,
                    style:
                        const TextStyle(fontSize: 12, color: AppColors.textSecondary),
                  ),
                ],
              ),
            ),
          ),
        for (final section in sections) ...[
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(
                Spacing.lg, Spacing.lg, Spacing.lg, Spacing.sm),
            sliver: SliverToBoxAdapter(
              child: Text(
                section.label,
                style: const TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w800,
                  color: AppColors.textPrimary,
                ),
              ),
            ),
          ),
          SliverPadding(
            padding: const EdgeInsets.symmetric(horizontal: Spacing.lg),
            sliver: SliverGrid(
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 4,
                crossAxisSpacing: Spacing.sm,
                mainAxisSpacing: Spacing.sm,
                childAspectRatio: 0.82,
              ),
              delegate: SliverChildBuilderDelegate(
                (context, i) {
                  final d = section.days[i];
                  final selected = _day != null &&
                      d.year == _day!.year &&
                      d.month == _day!.month &&
                      d.day == _day!.day;
                  final available = _dayAvailable(d);
                  return _DayCell(
                    date: d,
                    selected: selected,
                    available: available,
                    onTap: available
                        ? () {
                            setState(() => _day = d);
                            _next();
                            _loadSlotsForDay(d);
                          }
                        : null,
                  );
                },
                childCount: section.days.length,
              ),
            ),
          ),
        ],
        const SliverToBoxAdapter(child: SizedBox(height: Spacing.xxxl)),
      ],
    );
  }

  // ─── Passo 4: hora ─────────────────────────────────────────────────────────

  Widget _timeStep() {
    // "Em breve": não deixa escolher horário nem avançar para pagamento.
    // (O reagendamento de uma marcação já paga não passa por aqui.)
    if (widget.provider.comingSoon && !_isReschedule) {
      return const _EmptyStep(
        icon: Icons.schedule,
        text: kComingSoonBlockedMessage,
      );
    }
    if (_loadingSlots) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_slotsError != null) {
      return _LoadError(
        message: _slotsError!,
        onRetry: () => _day == null ? null : _loadSlotsForDay(_day!),
      );
    }
    if (_slotOptions.isEmpty) {
      return _EmptyStep(
        icon: Icons.event_busy,
        text: 'Sem horários disponíveis neste dia.\nEscolhe outro dia.'.tr,
        actionLabel: 'Mudar dia'.tr,
        onAction: () => _goTo(2),
      );
    }
    return SingleChildScrollView(
      padding: const EdgeInsets.all(Spacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            _formatDayLong(_day!),
            style: const TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w700,
              color: AppColors.textPrimary,
            ),
          ),
          const SizedBox(height: Spacing.md),
          Wrap(
            spacing: Spacing.sm,
            runSpacing: Spacing.sm,
            children: [
              for (final opt in _slotOptions)
                _SlotChip(
                  label: _formatTime(opt.start),
                  selected: _slot == opt.start,
                  onTap: () {
                    setState(() {
                      _slot = opt.start;
                      _resolvedStaffId = opt.staffId;
                    });
                    _next();
                  },
                ),
            ],
          ),
        ],
      ),
    );
  }

  // ─── Passo 5: confirmação + pagamento ────────────────────────────────────

  Widget _confirmStep() {
    final s = _service;
    final slot = _slot;
    if (s == null || slot == null) {
      return _EmptyStep(
        icon: Icons.info_outline,
        text: 'Faltam dados. Volta atrás e completa a marcação.'.tr,
      );
    }
    final staffName = _staffId == _kAnyStaffId
        ? 'Qualquer disponível'.tr
        : (_staff
                .where((st) => st.id == _resolvedStaffId)
                .map((st) => st.name)
                .cast<String?>()
                .firstWhere((_) => true, orElse: () => null) ??
            'Profissional');

    return Column(
      children: [
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(Spacing.lg),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _summaryCard(
                  service: s.name,
                  staff: staffName,
                  slot: slot,
                  price: s.priceLabel,
                ),
                const SizedBox(height: Spacing.lg),
                TextField(
                  controller: _notesCtrl,
                  maxLines: 3,
                  maxLength: 300,
                  decoration: InputDecoration(
                    labelText: 'Notas (opcional)'.tr,
                    hintText: 'Algo que o profissional deva saber...'.tr,
                    border: const OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: Spacing.sm),
                _paymentInfoCard(),
              ],
            ),
          ),
        ),
        // CTA laranja único do ecrã.
        SafeArea(
          top: false,
          minimum: const EdgeInsets.fromLTRB(
              Spacing.lg, Spacing.sm, Spacing.lg, Spacing.lg),
          child: BoraAccentButton(
            label: _isReschedule ? 'Confirmar Reagendamento' : 'Confirmar e Pagar',
            icon: _isReschedule ? Icons.event_repeat : Icons.lock,
            loading: _booking,
            onPressed:
                _booking ? null : (_isReschedule ? _confirmReschedule : _confirmAndPay),
          ),
        ),
      ],
    );
  }

  Widget _summaryCard({
    required String service,
    required String staff,
    required DateTime slot,
    required String price,
  }) {
    return Container(
      padding: const EdgeInsets.all(Spacing.lg),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(Radii.lg),
        boxShadow: AppColors.shadowCard,
      ),
      child: Column(
        children: [
          _summaryRow(Icons.content_cut, 'Serviço'.tr, service),
          const Divider(height: Spacing.xl, color: AppColors.divider),
          _summaryRow(Icons.person_outline, 'Profissional'.tr, staff),
          const Divider(height: Spacing.xl, color: AppColors.divider),
          _summaryRow(
              Icons.event, 'Data'.tr, '${_formatDayLong(slot)} · ${_formatTime(slot)}'),
          const Divider(height: Spacing.xl, color: AppColors.divider),
          _summaryRow(Icons.euro, 'Preço'.tr, price, emphasize: true),
        ],
      ),
    );
  }

  Widget _summaryRow(IconData icon, String label, String value,
      {bool emphasize = false}) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 18, color: AppColors.primary),
        const SizedBox(width: Spacing.md),
        Text(
          label,
          style: const TextStyle(fontSize: 14, color: AppColors.textSecondary),
        ),
        const Spacer(),
        Flexible(
          child: Text(
            value,
            textAlign: TextAlign.right,
            style: TextStyle(
              fontSize: emphasize ? 16 : 14,
              fontWeight: emphasize ? FontWeight.w800 : FontWeight.w600,
              color: emphasize ? AppColors.primary : AppColors.textPrimary,
            ),
          ),
        ),
      ],
    );
  }

  /// Explicação do que vai ser cobrado. Dois textos possíveis:
  ///   • reagendamento → nada a pagar (o valor já pago acompanha a marcação);
  ///   • marcação nova → paga já o valor TOTAL do serviço (fim do sinal).
  Widget _paymentInfoCard() {
    final String text;
    if (_isReschedule) {
      text = 'Não há nada a pagar — o valor que já pagaste fica reservado para esta marcação.'.tr;
    } else {
      text = 'Paga agora o valor total do serviço: {0}.\nNão há mais nada a pagar na loja.'.trArgs([_amountDueLabel]);
    }
    return Container(
      padding: const EdgeInsets.all(Spacing.md),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(Radii.md),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.info_outline, size: 18, color: AppColors.info),
          const SizedBox(width: Spacing.sm),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(
                fontSize: 13,
                height: 1.4,
                color: AppColors.textSecondary,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ─── Formatadores (PT-PT sem intl) ─────────────────────────────────────────

  static String _formatTime(DateTime dt) =>
      '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';

  static String _formatDayLong(DateTime d) {
    const weekdays = ['Seg', 'Ter', 'Qua', 'Qui', 'Sex', 'Sáb', 'Dom'];
    const months = [
      'jan', 'fev', 'mar', 'abr', 'mai', 'jun',
      'jul', 'ago', 'set', 'out', 'nov', 'dez',
    ];
    final wd = weekdays[(d.weekday - 1).clamp(0, 6)];
    final mo = months[(d.month - 1).clamp(0, 11)];
    return '$wd, ${d.day} $mo';
  }
}

/// Slot + o profissional concreto que o oferece.
class _SlotOption {
  _SlotOption({required this.start, required this.staffId});
  final DateTime start;
  final String staffId;
}

/// Secção de um mês no passo "Escolher dia" (cabeçalho + dias desse mês).
class _MonthSection {
  _MonthSection({required this.label, required this.days});
  final String label;
  final List<DateTime> days;
}

// ─── Widgets de apoio ────────────────────────────────────────────────────────

class _StepIndicator extends StatelessWidget {
  const _StepIndicator({required this.step, required this.total});
  final int step;
  final int total;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
          Spacing.lg, Spacing.md, Spacing.lg, Spacing.xs),
      child: Row(
        children: [
          for (var i = 0; i < total; i++) ...[
            Expanded(
              child: Container(
                height: 4,
                decoration: BoxDecoration(
                  color: i <= step ? AppColors.primary : AppColors.divider,
                  borderRadius: BorderRadius.circular(Radii.pill),
                ),
              ),
            ),
            if (i != total - 1) const SizedBox(width: Spacing.xs),
          ],
        ],
      ),
    );
  }
}

class _SelectableCard extends StatelessWidget {
  const _SelectableCard({
    required this.child,
    required this.onTap,
    required this.selected,
  });
  final Widget child;
  final VoidCallback onTap;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(Radii.lg),
      child: Container(
        padding: const EdgeInsets.all(Spacing.md),
        decoration: BoxDecoration(
          color: AppColors.card,
          borderRadius: BorderRadius.circular(Radii.lg),
          boxShadow: AppColors.shadowCard,
          border: selected
              ? Border.all(color: AppColors.primary, width: 2)
              : null,
        ),
        child: child,
      ),
    );
  }
}

class _DayCell extends StatelessWidget {
  const _DayCell({
    required this.date,
    required this.selected,
    required this.onTap,
    this.available = true,
  });
  final DateTime date;
  final bool selected;
  final VoidCallback? onTap;
  final bool available;

  static const _weekdays = ['Seg', 'Ter', 'Qua', 'Qui', 'Sex', 'Sáb', 'Dom'];

  @override
  Widget build(BuildContext context) {
    final wd = _weekdays[(date.weekday - 1).clamp(0, 6)];

    // Dia em que o profissional não trabalha: cinza, número esbatido, rótulo
    // "Indisponível" e SEM toque (onTap ignorado).
    if (!available) {
      return Container(
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(Radii.md),
          border: Border.all(color: AppColors.divider),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              wd,
              style: const TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: AppColors.textSubtle,
              ),
            ),
            const SizedBox(height: Spacing.xxs),
            Text(
              '${date.day}',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w700,
                color: AppColors.textSubtle.withValues(alpha: 0.6),
              ),
            ),
            const SizedBox(height: 2),
            Text(
              'Indisponível'.tr,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 8.5,
                fontWeight: FontWeight.w600,
                color: AppColors.textSubtle,
              ),
            ),
          ],
        ),
      );
    }

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(Radii.md),
      child: Container(
        decoration: BoxDecoration(
          color: selected ? AppColors.primary : AppColors.card,
          borderRadius: BorderRadius.circular(Radii.md),
          boxShadow: selected ? null : AppColors.shadowSm,
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              wd,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: selected ? Colors.white70 : AppColors.textSubtle,
              ),
            ),
            const SizedBox(height: Spacing.xxs),
            Text(
              '${date.day}',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w800,
                color: selected ? Colors.white : AppColors.textPrimary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SlotChip extends StatelessWidget {
  const _SlotChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(Radii.md),
      child: Container(
        padding:
            const EdgeInsets.symmetric(horizontal: Spacing.lg, vertical: Spacing.md),
        decoration: BoxDecoration(
          color: selected ? AppColors.primary : AppColors.card,
          borderRadius: BorderRadius.circular(Radii.md),
          border: Border.all(
            color: selected ? AppColors.primary : AppColors.divider,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w700,
            color: selected ? Colors.white : AppColors.textPrimary,
          ),
        ),
      ),
    );
  }
}

class _EmptyStep extends StatelessWidget {
  const _EmptyStep({
    required this.icon,
    required this.text,
    this.actionLabel,
    this.onAction,
  });
  final IconData icon;
  final String text;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(Spacing.xxxl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 56, color: AppColors.textSubtle),
            const SizedBox(height: Spacing.lg),
            Text(
              text,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: AppColors.textSecondary,
                fontSize: 15,
              ),
            ),
            if (actionLabel != null && onAction != null) ...[
              const SizedBox(height: Spacing.lg),
              BoraPrimaryButton(
                label: actionLabel!,
                expanded: false,
                onPressed: onAction,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _LoadError extends StatelessWidget {
  const _LoadError({required this.message, required this.onRetry});
  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(Spacing.xxxl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline, size: 48, color: AppColors.error),
            const SizedBox(height: Spacing.md),
            Text(message, textAlign: TextAlign.center),
            const SizedBox(height: Spacing.lg),
            BoraPrimaryButton(
              label: 'Tentar de novo'.tr,
              expanded: false,
              onPressed: onRetry,
            ),
          ],
        ),
      ),
    );
  }
}
