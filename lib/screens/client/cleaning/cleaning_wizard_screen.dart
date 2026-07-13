import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../config/app_colors.dart';
import '../../../config/app_spacing.dart';
import '../../../models/cleaning_models.dart';
import '../../../stores/cart_store.dart';
import '../../../stores/cleaning_store.dart';
import '../../../widgets/bora/bora.dart';
import 'cleaning_payment_flow.dart';
import 'cleaning_tracking_screen.dart';

/// LIMPEZA — wizard de 3 passos (tipo Helpling/Oscar):
///   1. Serviço (tamanho/horas, tipo, produtos, recorrência) + preço live
///   2. Quando & Onde (data/hora, morada, notas)
///   3. Profissional & Pagamento (lista disponível + resumo + confirmar)
/// Preço SEMPRE server-side (RPC cleaning_quote); aqui só se mostra.
class CleaningWizardScreen extends StatefulWidget {
  const CleaningWizardScreen({super.key});

  @override
  State<CleaningWizardScreen> createState() => _CleaningWizardScreenState();
}

class _CleaningWizardScreenState extends State<CleaningWizardScreen> {
  int _step = 0;

  // Passo 1 — serviço
  String _pricingMode = 'fixed';
  String _homeSize = 't2';
  int _hours = 2;
  int _minHours = 2;
  String _cleaningType = 'standard';
  String _productsBy = 'client';
  String _recurrence = 'single';
  CleaningQuote? _quote;
  bool _quoteLoading = false;

  // Passo 2 — quando & onde
  DateTime? _scheduledAt;
  int _leadHours = 12;
  final _streetCtrl = TextEditingController();
  final _cityCtrl = TextEditingController();
  final _postalCtrl = TextEditingController();
  final _notesCtrl = TextEditingController();
  bool _addressPrefilled = false;

  // Passo 3 — profissional & pagamento
  List<AvailableCleaner> _cleaners = const [];
  bool _cleanersLoading = false;
  String? _requestedCleanerId; // null = primeira disponível
  String _paymentMethod = 'cash';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      final store = context.read<CleaningStore>();
      store.refreshStripeEnabled();
      _prefillAddress();
      _refreshQuote();
      final lead = await store.getSettingInt('cleaning_min_lead_hours', 12);
      final minH = await store.getSettingInt('cleaning_min_hours', 2);
      if (!mounted) return;
      setState(() {
        _leadHours = lead;
        _minHours = minH;
        if (_hours < _minHours) _hours = _minHours;
      });
    });
  }

  @override
  void dispose() {
    _streetCtrl.dispose();
    _cityCtrl.dispose();
    _postalCtrl.dispose();
    _notesCtrl.dispose();
    super.dispose();
  }

  void _prefillAddress() {
    if (_addressPrefilled) return;
    final cart = context.read<CartStore>();
    if (cart.dropoffStreet.isNotEmpty) _streetCtrl.text = cart.dropoffStreet;
    if (cart.dropoffCity.isNotEmpty) _cityCtrl.text = cart.dropoffCity;
    if (cart.dropoffPostalCode.isNotEmpty) {
      _postalCtrl.text = cart.dropoffPostalCode;
    }
    _addressPrefilled = true;
  }

  Future<void> _refreshQuote() async {
    setState(() => _quoteLoading = true);
    final quote = await context.read<CleaningStore>().quote(
          cleaningType: _cleaningType,
          pricingMode: _pricingMode,
          homeSize: _pricingMode == 'fixed' ? _homeSize : null,
          hours: _pricingMode == 'hourly' ? _hours : null,
          recurrence: _recurrence,
          productsBy: _productsBy,
        );
    if (!mounted) return;
    setState(() {
      _quote = quote;
      _quoteLoading = false;
    });
  }

  // ── navegação entre passos ────────────────────────────────────────────────

  DateTime get _earliestAllowed =>
      DateTime.now().add(Duration(hours: _leadHours));

  Future<void> _goNext() async {
    if (_step == 0) {
      if (_quote == null) {
        _snack('Sem orçamento — verifica a ligação e tenta de novo.');
        return;
      }
      setState(() => _step = 1);
      return;
    }
    if (_step == 1) {
      if (_scheduledAt == null) {
        _snack('Escolhe a data e hora da limpeza.');
        return;
      }
      if (_scheduledAt!.isBefore(_earliestAllowed)) {
        _snack('A limpeza tem de ser agendada com pelo menos '
            '$_leadHours h de antecedência.');
        return;
      }
      if (_streetCtrl.text.trim().isEmpty || _cityCtrl.text.trim().isEmpty) {
        _snack('Preenche a morada da limpeza.');
        return;
      }
      setState(() => _step = 2);
      await _loadCleaners();
      return;
    }
    await _confirm();
  }

  void _goBack() {
    if (_step == 0) {
      Navigator.pop(context);
    } else {
      setState(() => _step -= 1);
    }
  }

  Future<void> _loadCleaners() async {
    final scheduled = _scheduledAt;
    final quote = _quote;
    if (scheduled == null || quote == null) return;
    setState(() => _cleanersLoading = true);
    final cart = context.read<CartStore>();
    final loc = cart.deliveryLocation;
    final list = await context.read<CleaningStore>().listAvailableCleaners(
          scheduledAt: scheduled,
          durationMin: quote.durationMin,
          lat: loc?.latitude,
          lng: loc?.longitude,
        );
    if (!mounted) return;
    setState(() {
      _cleaners = list;
      _cleanersLoading = false;
      if (_requestedCleanerId != null &&
          !list.any((c) => c.id == _requestedCleanerId)) {
        _requestedCleanerId = null;
      }
    });
  }

  Future<void> _confirm() async {
    final store = context.read<CleaningStore>();
    final scheduled = _scheduledAt;
    if (scheduled == null) return;
    try {
      final cart = context.read<CartStore>();
      final loc = cart.deliveryLocation;
      final booking = await store.createBooking(
        cleaningType: _cleaningType,
        pricingMode: _pricingMode,
        homeSize: _pricingMode == 'fixed' ? _homeSize : null,
        hours: _pricingMode == 'hourly' ? _hours : null,
        scheduledAt: scheduled,
        recurrence: _recurrence,
        productsBy: _productsBy,
        paymentMethod: _paymentMethod,
        addressStreet: _streetCtrl.text.trim(),
        addressCity: _cityCtrl.text.trim(),
        addressPostal: _postalCtrl.text.trim(),
        lat: loc?.latitude,
        lng: loc?.longitude,
        notes: _notesCtrl.text.trim(),
        requestedCleanerId: _requestedCleanerId,
      );
      if (!mounted || booking == null) return;

      // Pagamento online ("vai" 2026-07-05): cartão retém já; MB Way cobra já.
      // Se falhar/abandonar, a reserva fica 'unpaid' e o tracking mostra o
      // banner "Pagar agora" para retomar.
      if (_paymentMethod != 'cash') {
        final paid = await CleaningPaymentFlow.pay(context, store, booking);
        if (!mounted) return;
        if (!paid) {
          _snack('Reserva criada — falta concluir o pagamento no ecrã da '
              'reserva.');
        }
      }
      if (!mounted) return;
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
            builder: (_) => CleaningTrackingScreen(booking: booking)),
      );
    } catch (e) {
      final msg = e.toString();
      String friendly = 'Não foi possível criar a reserva. Tenta de novo.';
      if (msg.contains('lead_time_too_short')) {
        friendly = 'A limpeza tem de ser agendada com mais antecedência.';
      } else if (msg.contains('card_mbway_not_yet_enabled')) {
        friendly =
            'Cartão e MB Way ficam disponíveis brevemente — usa dinheiro.';
      } else if (msg.contains('cleaning_disabled')) {
        friendly = 'As limpezas estão temporariamente indisponíveis.';
      } else if (msg.contains('cleaner_not_available')) {
        friendly = 'Essa profissional já não está disponível — escolhe outra.';
      }
      _snack(friendly);
    }
  }

  void _snack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  // ── UI ────────────────────────────────────────────────────────────────────

  static const _stepTitles = ['Serviço', 'Quando & Onde', 'Confirmar'];

  @override
  Widget build(BuildContext context) {
    final store = context.watch<CleaningStore>();
    return Scaffold(
      appBar: BoraScreenAppBar(title: 'Limpeza — ${_stepTitles[_step]}'),
      body: Column(
        children: [
          _StepHeader(step: _step, titles: _stepTitles),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(Spacing.lg),
              child: switch (_step) {
                0 => _buildStepService(),
                1 => _buildStepWhenWhere(),
                _ => _buildStepConfirm(store),
              },
            ),
          ),
          _buildBottomBar(store),
        ],
      ),
    );
  }

  Widget _buildBottomBar(CleaningStore store) {
    final isLast = _step == 2;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
            Spacing.lg, Spacing.sm, Spacing.lg, Spacing.md),
        child: Row(
          children: [
            TextButton(
              onPressed: store.busy ? null : _goBack,
              child: Text(_step == 0 ? 'Cancelar' : 'Voltar',
                  style: const TextStyle(color: AppColors.textSecondary)),
            ),
            const SizedBox(width: Spacing.md),
            Expanded(
              child: BoraPrimaryButton(
                label: isLast
                    ? 'Confirmar reserva'
                    : 'Continuar',
                icon: isLast ? Icons.check_circle : Icons.arrow_forward,
                loading: store.busy,
                onPressed: _goNext,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Passo 1: serviço ──────────────────────────────────────────────────────

  Widget _buildStepService() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionTitle('Como queres pagar a limpeza?'),
        _choiceRow([
          _choice('Por tamanho', _pricingMode == 'fixed', () {
            setState(() => _pricingMode = 'fixed');
            _refreshQuote();
          }),
          _choice('Por hora', _pricingMode == 'hourly', () {
            setState(() => _pricingMode = 'hourly');
            _refreshQuote();
          }),
        ]),
        const SizedBox(height: Spacing.lg),
        if (_pricingMode == 'fixed') ...[
          _sectionTitle('Tamanho da casa'),
          _choiceRow([
            for (final e in CleaningLabels.sizes.entries)
              _choice(e.value, _homeSize == e.key, () {
                setState(() => _homeSize = e.key);
                _refreshQuote();
              }),
          ]),
        ] else ...[
          _sectionTitle('Quantas horas? (mín. $_minHours h)'),
          Row(
            children: [
              IconButton(
                onPressed: _hours > _minHours
                    ? () {
                        setState(() => _hours -= 1);
                        _refreshQuote();
                      }
                    : null,
                icon: const Icon(Icons.remove_circle_outline),
              ),
              Text('$_hours h',
                  style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                      color: AppColors.textPrimary)),
              IconButton(
                onPressed: _hours < 12
                    ? () {
                        setState(() => _hours += 1);
                        _refreshQuote();
                      }
                    : null,
                icon: const Icon(Icons.add_circle_outline),
              ),
            ],
          ),
        ],
        const SizedBox(height: Spacing.lg),
        _sectionTitle('Tipo de limpeza'),
        _choiceRow([
          _choice('Standard', _cleaningType == 'standard', () {
            setState(() => _cleaningType = 'standard');
            _refreshQuote();
          }),
          _choice('Profunda', _cleaningType == 'deep', () {
            setState(() => _cleaningType = 'deep');
            _refreshQuote();
          }),
          _choice('Pós-obras', _cleaningType == 'post_works', () {
            setState(() => _cleaningType = 'post_works');
            _refreshQuote();
          }),
        ]),
        const SizedBox(height: Spacing.lg),
        _sectionTitle('Produtos de limpeza'),
        const Padding(
          padding: EdgeInsets.only(bottom: Spacing.sm),
          child: Text(
            'Quer que a profissional leve os produtos de limpeza, ou prefere '
            'que ela use os seus (de casa)?',
            style: TextStyle(color: AppColors.textSecondary, fontSize: 13),
          ),
        ),
        _choiceRow([
          _choice('Uso os meus (de casa)', _productsBy == 'client', () {
            setState(() => _productsBy = 'client');
            _refreshQuote();
          }),
          _choice('A profissional leva', _productsBy == 'cleaner', () {
            setState(() => _productsBy = 'cleaner');
            _refreshQuote();
          }),
        ]),
        const SizedBox(height: Spacing.lg),
        _sectionTitle('Repetir?'),
        _choiceRow([
          for (final e in CleaningLabels.recurrences.entries)
            _choice(e.value, _recurrence == e.key, () {
              setState(() => _recurrence = e.key);
              _refreshQuote();
            }),
        ]),
        if (_recurrence != 'single')
          const Padding(
            padding: EdgeInsets.only(top: Spacing.sm),
            child: Text(
              'Com recorrência tens desconto e tentamos sempre a mesma '
              'profissional.',
              style:
                  TextStyle(color: AppColors.textSecondary, fontSize: 13),
            ),
          ),
        const SizedBox(height: Spacing.xl),
        _QuoteCard(quote: _quote, loading: _quoteLoading),
      ],
    );
  }

  // ── Passo 2: quando & onde ────────────────────────────────────────────────

  Future<void> _pickDateTime() async {
    final earliest = _earliestAllowed;
    final initial = _scheduledAt ?? earliest.add(const Duration(hours: 1));
    final date = await showDatePicker(
      context: context,
      initialDate: initial.isBefore(earliest) ? earliest : initial,
      firstDate: DateTime(earliest.year, earliest.month, earliest.day),
      lastDate: DateTime.now().add(const Duration(days: 60)),
    );
    if (date == null || !mounted) return;
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(initial),
    );
    if (time == null || !mounted) return;
    setState(() {
      _scheduledAt =
          DateTime(date.year, date.month, date.day, time.hour, time.minute);
    });
  }

  Widget _buildStepWhenWhere() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionTitle('Data e hora'),
        InkWell(
          borderRadius: BorderRadius.circular(Radii.md),
          onTap: _pickDateTime,
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.all(Spacing.md),
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(Radii.md),
              border: Border.all(color: AppColors.divider),
            ),
            child: Row(
              children: [
                const Icon(Icons.event, color: AppColors.primary),
                const SizedBox(width: Spacing.md),
                Expanded(
                  child: Text(
                    _scheduledAt == null
                        ? 'Escolher data e hora'
                        : _fmtDateTime(_scheduledAt!),
                    style: TextStyle(
                      color: _scheduledAt == null
                          ? AppColors.textSecondary
                          : AppColors.textPrimary,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                const Icon(Icons.chevron_right, color: AppColors.textSubtle),
              ],
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.only(top: Spacing.xs),
          child: Text(
            'Antecedência mínima: $_leadHours h.',
            style: const TextStyle(color: AppColors.textSubtle, fontSize: 12),
          ),
        ),
        const SizedBox(height: Spacing.lg),
        _sectionTitle('Morada da limpeza'),
        TextField(
          controller: _streetCtrl,
          decoration: const InputDecoration(
              labelText: 'Rua e número', prefixIcon: Icon(Icons.home)),
        ),
        const SizedBox(height: Spacing.md),
        Row(
          children: [
            Expanded(
              flex: 3,
              child: TextField(
                controller: _cityCtrl,
                decoration: const InputDecoration(labelText: 'Cidade'),
              ),
            ),
            const SizedBox(width: Spacing.md),
            Expanded(
              flex: 2,
              child: TextField(
                controller: _postalCtrl,
                keyboardType: TextInputType.number,
                decoration:
                    const InputDecoration(labelText: 'Código postal'),
              ),
            ),
          ],
        ),
        const SizedBox(height: Spacing.lg),
        _sectionTitle('Notas para a profissional (opcional)'),
        TextField(
          controller: _notesCtrl,
          maxLines: 3,
          decoration: const InputDecoration(
            hintText: 'Ex.: tenho um cão, atenção à cozinha, campainha B…',
          ),
        ),
      ],
    );
  }

  // ── Passo 3: profissional & pagamento ─────────────────────────────────────

  Widget _buildStepConfirm(CleaningStore store) {
    final quote = _quote;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionTitle('Profissional'),
        if (_cleanersLoading)
          const Center(
            child: Padding(
              padding: EdgeInsets.all(Spacing.lg),
              child: CircularProgressIndicator(),
            ),
          )
        else ...[
          _CleanerOption(
            selected: _requestedCleanerId == null,
            onTap: () => setState(() => _requestedCleanerId = null),
            child: const Row(
              children: [
                Icon(Icons.auto_awesome, color: AppColors.primary),
                SizedBox(width: Spacing.md),
                Expanded(
                  child: Text('Primeira disponível (recomendado)',
                      style: TextStyle(
                          fontWeight: FontWeight.w600,
                          color: AppColors.textPrimary)),
                ),
              ],
            ),
          ),
          for (final c in _cleaners)
            _CleanerOption(
              selected: _requestedCleanerId == c.id,
              onTap: () => setState(() => _requestedCleanerId = c.id),
              child: Row(
                children: [
                  CircleAvatar(
                    radius: 20,
                    backgroundColor: AppColors.primaryWash,
                    backgroundImage: c.photoUrl.isNotEmpty
                        ? NetworkImage(c.photoUrl)
                        : null,
                    child: c.photoUrl.isEmpty
                        ? const Icon(Icons.person, color: AppColors.primary)
                        : null,
                  ),
                  const SizedBox(width: Spacing.md),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Flexible(
                              child: Text(c.name,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                      fontWeight: FontWeight.w600,
                                      color: AppColors.textPrimary)),
                            ),
                            if (c.isFavorite)
                              const Padding(
                                padding: EdgeInsets.only(left: Spacing.xs),
                                child: Icon(Icons.favorite,
                                    size: 14, color: AppColors.error),
                              ),
                          ],
                        ),
                        Text(
                          c.ratingsCount > 0
                              ? '★ ${c.ratingAvg.toStringAsFixed(1)} · '
                                  '${c.cleaningsDone} limpezas'
                              : c.cleaningsDone > 0
                                  ? '${c.cleaningsDone} limpezas'
                                  : 'Nova na plataforma',
                          style: const TextStyle(
                              color: AppColors.textSecondary, fontSize: 12),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          if (_cleaners.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: Spacing.sm),
              child: Text(
                'Nenhuma profissional livre neste horário — podes reservar '
                'na mesma e nós encontramos a primeira disponível.',
                style:
                    TextStyle(color: AppColors.textSecondary, fontSize: 13),
              ),
            ),
        ],
        const SizedBox(height: Spacing.lg),
        _sectionTitle('Pagamento'),
        _PaymentOption(
          icon: Icons.euro,
          label: 'Dinheiro (no local)',
          selected: _paymentMethod == 'cash',
          enabled: true,
          onTap: () => setState(() => _paymentMethod = 'cash'),
        ),
        _PaymentOption(
          icon: Icons.credit_card,
          label: store.stripeEnabled ? 'Cartão' : 'Cartão — brevemente',
          selected: _paymentMethod == 'card',
          enabled: store.stripeEnabled,
          onTap: () => setState(() => _paymentMethod = 'card'),
        ),
        _PaymentOption(
          icon: Icons.phone_iphone,
          label: store.stripeEnabled ? 'MB Way' : 'MB Way — brevemente',
          selected: _paymentMethod == 'mbway',
          enabled: store.stripeEnabled,
          onTap: () => setState(() => _paymentMethod = 'mbway'),
        ),
        const SizedBox(height: Spacing.lg),
        _sectionTitle('Resumo'),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(Spacing.lg),
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(Radii.lg),
            border: Border.all(color: AppColors.divider),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _summaryRow(
                  'Serviço',
                  '${CleaningLabels.types[_cleaningType]} · '
                      '${_pricingMode == 'hourly' ? '$_hours h' : CleaningLabels.sizes[_homeSize]}'),
              if (_scheduledAt != null)
                _summaryRow('Quando', _fmtDateTime(_scheduledAt!)),
              _summaryRow('Onde',
                  '${_streetCtrl.text.trim()}, ${_cityCtrl.text.trim()}'),
              _summaryRow(
                  'Recorrência', CleaningLabels.recurrences[_recurrence]!),
              if (quote != null) ...[
                const Divider(height: Spacing.lg),
                _summaryRow('Base', CleaningLabels.euro(quote.baseCents)),
                if (quote.typeSurchargeCents > 0)
                  _summaryRow('Suplemento tipo',
                      '+ ${CleaningLabels.euro(quote.typeSurchargeCents)}'),
                if (quote.recurringDiscountCents > 0)
                  _summaryRow('Desconto recorrência',
                      '- ${CleaningLabels.euro(quote.recurringDiscountCents)}'),
                if (quote.productsFeeCents > 0)
                  _summaryRow('Produtos',
                      '+ ${CleaningLabels.euro(quote.productsFeeCents)}'),
                const Divider(height: Spacing.lg),
                _summaryRow('Total', CleaningLabels.euro(quote.totalCents),
                    bold: true),
              ],
            ],
          ),
        ),
        const SizedBox(height: Spacing.md),
        const Text(
          'Cancelamento: grátis até 24 h antes · 50% entre 24 h e 2 h · '
          '100% a menos de 2 h.',
          style: TextStyle(color: AppColors.textSubtle, fontSize: 12),
        ),
      ],
    );
  }

  // ── helpers de UI ─────────────────────────────────────────────────────────

  Widget _sectionTitle(String text) => Padding(
        padding: const EdgeInsets.only(bottom: Spacing.sm),
        child: Text(text,
            style: const TextStyle(
                fontWeight: FontWeight.w700,
                fontSize: 15,
                color: AppColors.textPrimary)),
      );

  Widget _choiceRow(List<Widget> children) => Wrap(
        spacing: Spacing.sm,
        runSpacing: Spacing.sm,
        children: children,
      );

  Widget _choice(String label, bool selected, VoidCallback onTap) {
    return ChoiceChip(
      label: Text(label),
      selected: selected,
      onSelected: (_) => onTap(),
      selectedColor: AppColors.primaryWash,
      labelStyle: TextStyle(
        color: selected ? AppColors.primary : AppColors.textSecondary,
        fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
      ),
    );
  }

  Widget _summaryRow(String label, String value, {bool bold = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Text(label,
                style: const TextStyle(color: AppColors.textSecondary)),
          ),
          Text(
            value,
            style: TextStyle(
              color: AppColors.textPrimary,
              fontWeight: bold ? FontWeight.w800 : FontWeight.w600,
              fontSize: bold ? 16 : 14,
            ),
          ),
        ],
      ),
    );
  }

  static String _fmtDateTime(DateTime d) {
    String two(int n) => n.toString().padLeft(2, '0');
    return '${two(d.day)}/${two(d.month)}/${d.year} às '
        '${two(d.hour)}:${two(d.minute)}';
  }
}

// ─── widgets internos ────────────────────────────────────────────────────────

class _StepHeader extends StatelessWidget {
  const _StepHeader({required this.step, required this.titles});
  final int step;
  final List<String> titles;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
          Spacing.lg, Spacing.md, Spacing.lg, 0),
      child: Row(
        children: [
          for (var i = 0; i < titles.length; i++) ...[
            Expanded(
              child: Container(
                height: 4,
                decoration: BoxDecoration(
                  color: i <= step ? AppColors.primary : AppColors.divider,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            if (i < titles.length - 1) const SizedBox(width: Spacing.xs),
          ],
        ],
      ),
    );
  }
}

class _QuoteCard extends StatelessWidget {
  const _QuoteCard({required this.quote, required this.loading});
  final CleaningQuote? quote;
  final bool loading;

  @override
  Widget build(BuildContext context) {
    final q = quote;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(Spacing.lg),
      decoration: BoxDecoration(
        color: AppColors.primaryWash,
        borderRadius: BorderRadius.circular(Radii.lg),
      ),
      child: loading || q == null
          ? const Center(
              child: SizedBox(
                width: 22,
                height: 22,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            )
          : Row(
              children: [
                const Icon(Icons.cleaning_services,
                    color: AppColors.primary, size: 28),
                const SizedBox(width: Spacing.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        CleaningLabels.euro(q.totalCents),
                        style: const TextStyle(
                            fontSize: 22,
                            fontWeight: FontWeight.w800,
                            color: AppColors.textPrimary),
                      ),
                      Text(
                        '≈ ${(q.durationMin / 60).toStringAsFixed(q.durationMin % 60 == 0 ? 0 : 1)} h de serviço',
                        style: const TextStyle(
                            color: AppColors.textSecondary, fontSize: 13),
                      ),
                    ],
                  ),
                ),
              ],
            ),
    );
  }
}

class _CleanerOption extends StatelessWidget {
  const _CleanerOption({
    required this.selected,
    required this.onTap,
    required this.child,
  });
  final bool selected;
  final VoidCallback onTap;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: Spacing.sm),
      child: InkWell(
        borderRadius: BorderRadius.circular(Radii.md),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(Spacing.md),
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(Radii.md),
            border: Border.all(
              color: selected ? AppColors.primary : AppColors.divider,
              width: selected ? 2 : 1,
            ),
          ),
          child: child,
        ),
      ),
    );
  }
}

class _PaymentOption extends StatelessWidget {
  const _PaymentOption({
    required this.icon,
    required this.label,
    required this.selected,
    required this.enabled,
    required this.onTap,
  });
  final IconData icon;
  final String label;
  final bool selected;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final color = enabled
        ? (selected ? AppColors.primary : AppColors.textSecondary)
        : AppColors.textSubtle;
    return Padding(
      padding: const EdgeInsets.only(bottom: Spacing.sm),
      child: InkWell(
        borderRadius: BorderRadius.circular(Radii.md),
        onTap: enabled ? onTap : null,
        child: Container(
          padding: const EdgeInsets.all(Spacing.md),
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(Radii.md),
            border: Border.all(
              color: selected && enabled
                  ? AppColors.primary
                  : AppColors.divider,
              width: selected && enabled ? 2 : 1,
            ),
          ),
          child: Row(
            children: [
              Icon(icon, color: color),
              const SizedBox(width: Spacing.md),
              Expanded(
                child: Text(label,
                    style: TextStyle(
                        color: enabled
                            ? AppColors.textPrimary
                            : AppColors.textSubtle,
                        fontWeight: FontWeight.w600)),
              ),
              if (selected && enabled)
                const Icon(Icons.check_circle, color: AppColors.primary),
            ],
          ),
        ),
      ),
    );
  }
}
