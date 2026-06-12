// Admin — 💶 Fechos Semanais (estafetas + parceiros). PT-BR (Regra 6 CEO-AI).
//
// Sessão 2026-06-12 — UI sobre backend JÁ existente (só consome, nada criado):
//   • admin_weekly_bora_totals(p_week_start)            -> jsonb (cartão topo)
//   • admin_list_settlements_for_week(p_week_start)     -> jsonb {settlements:[...]}
//   • admin_list_partner_settlements_for_week(...)      -> jsonb {settlements:[...]}
//   • admin_set_settlement_status(id, status, ref, notes)         (estafeta)
//   • admin_set_partner_settlement_status(id, status, ref, notes) (parceiro)
// Estados válidos no backend: pending | paid | received | disputed.
// Audit log é gravado DENTRO das RPCs set_status — a UI não duplica.
// Semana = segunda 00:00 Europe/Lisbon (driver_settlement_week_bounds trunca
// server-side qualquer instante passado em p_week_start).
//
// Deep link: rota '/admin/settlements' (push de 2ª-feira do run_weekly_closeout).

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../config/app_colors.dart';
import '../../config/app_spacing.dart';
import '../../widgets/bora/bora_screen_app_bar.dart';

class AdminWeeklySettlementsScreen extends StatefulWidget {
  const AdminWeeklySettlementsScreen({super.key});

  @override
  State<AdminWeeklySettlementsScreen> createState() =>
      _AdminWeeklySettlementsScreenState();
}

class _AdminWeeklySettlementsScreenState
    extends State<AdminWeeklySettlementsScreen>
    with SingleTickerProviderStateMixin {
  final _supabase = Supabase.instance.client;
  late final TabController _tabController;

  /// Segunda-feira 00:00 (hora local) da semana mostrada.
  late DateTime _weekStart;

  bool _loading = true;
  String? _error;

  Map<String, dynamic> _totals = const {};
  List<Map<String, dynamic>> _drivers = const [];
  List<Map<String, dynamic>> _partners = const [];

  // Range real devolvido pelas RPCs (autoridade: server, TZ Lisboa).
  String? _serverWeekStart;
  String? _serverWeekEnd;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _weekStart = _mondayOf(DateTime.now());
    _load();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  // ─── Semana ─────────────────────────────────────────────────────────────

  static DateTime _mondayOf(DateTime d) {
    final day = DateTime(d.year, d.month, d.day);
    return day.subtract(Duration(days: day.weekday - 1));
  }

  bool get _isCurrentWeek => _weekStart == _mondayOf(DateTime.now());

  /// Instante seguro dentro da semana (12:00 de segunda evita arestas de DST);
  /// o backend trunca para segunda 00:00 Lisboa.
  String get _weekAnchorIso =>
      _weekStart.add(const Duration(hours: 12)).toUtc().toIso8601String();

  void _changeWeek(int deltaWeeks) {
    final next = _weekStart.add(Duration(days: 7 * deltaWeeks));
    if (next.isAfter(_mondayOf(DateTime.now()))) return; // sem semanas futuras
    setState(() => _weekStart = next);
    _load();
  }

  // ─── Load ───────────────────────────────────────────────────────────────

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final params = {'p_week_start': _weekAnchorIso};
      final results = await Future.wait([
        _supabase.rpc('admin_weekly_bora_totals', params: params),
        _supabase.rpc('admin_list_settlements_for_week', params: params),
        _supabase.rpc('admin_list_partner_settlements_for_week',
            params: params),
      ]);

      final totals = _asMap(results[0]);
      final driversRes = _asMap(results[1]);
      final partnersRes = _asMap(results[2]);

      if (!mounted) return;
      setState(() {
        _totals = totals;
        _drivers = _asRows(driversRes['settlements']);
        _partners = _asRows(partnersRes['settlements']);
        _serverWeekStart = driversRes['week_start']?.toString() ??
            totals['week_start']?.toString();
        _serverWeekEnd = driversRes['week_end']?.toString() ??
            totals['week_end']?.toString();
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = 'Erro ao carregar fechos: $e';
        _loading = false;
      });
    }
  }

  static Map<String, dynamic> _asMap(dynamic v) =>
      v is Map ? Map<String, dynamic>.from(v) : <String, dynamic>{};

  static List<Map<String, dynamic>> _asRows(dynamic v) => v is List
      ? v.map((e) => Map<String, dynamic>.from(e as Map)).toList()
      : const [];

  // ─── Helpers de formato (linguagem simples) ─────────────────────────────

  static double _num(dynamic v) =>
      v is num ? v.toDouble() : double.tryParse(v?.toString() ?? '') ?? 0.0;

  static String _euros(num v) =>
      '€${v.toDouble().abs().toStringAsFixed(2).replaceAll('.', ',')}';

  String _fmtDate(String? iso) {
    final d = iso == null ? null : DateTime.tryParse(iso)?.toLocal();
    if (d == null) return '—';
    return '${d.day.toString().padLeft(2, '0')}/'
        '${d.month.toString().padLeft(2, '0')}';
  }

  String _fmtDateTime(String? iso) {
    final d = iso == null ? null : DateTime.tryParse(iso)?.toLocal();
    if (d == null) return '—';
    return '${d.day.toString().padLeft(2, '0')}/'
        '${d.month.toString().padLeft(2, '0')}/${d.year} '
        '${d.hour.toString().padLeft(2, '0')}:'
        '${d.minute.toString().padLeft(2, '0')}';
  }

  /// "Bora paga €X" (verde) / "Deve €X à Bora" (laranja) / "Sem saldo" (cinza).
  (String, Color) _balanceLabel(String direction, double net) {
    if (direction.startsWith('bora_pays')) {
      return ('Bora paga ${_euros(net)}', AppColors.primary);
    }
    if (direction.endsWith('_pays_bora')) {
      return ('Deve ${_euros(net)} à Bora', AppColors.accent);
    }
    return ('Sem saldo', AppColors.textSecondary);
  }

  (String, Color) _statusChip(String status) => switch (status) {
        'pending' => ('PENDENTE', AppColors.warning),
        'paid' => ('PAGO', AppColors.primary),
        'received' => ('RECEBIDO', AppColors.primary),
        'disputed' => ('EM DISPUTA', AppColors.error),
        _ => (status.toUpperCase(), AppColors.textSecondary),
      };

  void _toast(String msg, Color bg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), backgroundColor: bg),
    );
  }

  // ─── Marcar pago/recebido (dupla confirmação, padrão da casa) ───────────

  Future<void> _markSettlement({
    required Map<String, dynamic> row,
    required bool isDriver,
  }) async {
    final direction = (row['direction'] as String?) ?? 'zero';
    final net = _num(row['net_balance']);
    final name = isDriver
        ? (row['driver_name']?.toString() ?? 'Estafeta')
        : (row['partner_name']?.toString() ?? 'Parceiro');
    final settlementId = row['settlement_id']?.toString();
    if (settlementId == null) return;

    final boraPays = direction.startsWith('bora_pays');
    final newStatus = boraPays ? 'paid' : 'received';
    final actionLabel = boraPays ? 'MARCAR COMO PAGO' : 'MARCAR COMO RECEBIDO';
    final explanation = boraPays
        ? 'Você está registrando que a Bora JÁ PAGOU ${_euros(net)} '
            'a $name (MB Way/transferência).'
        : 'Você está registrando que $name JÁ ENTREGOU ${_euros(net)} '
            'à Bora (MB Way/dinheiro).';

    final refCtrl = TextEditingController();
    final firstOk = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(Radii.md)),
        title: Text(actionLabel),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(name, style: const TextStyle(fontWeight: FontWeight.w700)),
            const SizedBox(height: Spacing.xs),
            Text('Semana ${_fmtDate(_serverWeekStart)} → '
                '${_fmtDate(_serverWeekEnd)} · Valor: ${_euros(net)}'),
            const SizedBox(height: Spacing.md),
            TextField(
              controller: refCtrl,
              decoration: const InputDecoration(
                labelText: 'Referência MB Way (opcional)',
                hintText: 'ex.: transferência 12345',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: Spacing.md),
            Container(
              padding: const EdgeInsets.all(Spacing.sm + 2),
              decoration: BoxDecoration(
                color: AppColors.warning.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(Radii.sm),
                border:
                    Border.all(color: AppColors.warning.withValues(alpha: 0.4)),
              ),
              child: Row(children: [
                const Icon(Icons.warning_amber_rounded,
                    color: AppColors.warning, size: 20),
                const SizedBox(width: Spacing.sm),
                Expanded(
                  child: Text(explanation,
                      style: const TextStyle(fontSize: 12)),
                ),
              ]),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Voltar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(backgroundColor: AppColors.error),
            child: const Text('Continuar'),
          ),
        ],
      ),
    );
    if (firstOk != true || !mounted) {
      refCtrl.dispose();
      return;
    }

    final secondOk = await _askConfirmType(context, expected: 'CONFIRMAR');
    if (secondOk != true || !mounted) {
      refCtrl.dispose();
      return;
    }

    final reference = refCtrl.text.trim();
    refCtrl.dispose();
    try {
      await _supabase.rpc(
        isDriver
            ? 'admin_set_settlement_status'
            : 'admin_set_partner_settlement_status',
        params: {
          'p_settlement_id': settlementId,
          'p_new_status': newStatus,
          if (reference.isNotEmpty) 'p_payment_reference': reference,
        },
      );
      _toast(
        boraPays
            ? '✔ Pagamento registrado — $name'
            : '✔ Recebimento registrado — $name',
        AppColors.primary,
      );
      await _load();
    } catch (e) {
      _toast('Erro ao gravar: $e', AppColors.error);
    }
  }

  Future<bool?> _askConfirmType(BuildContext ctx,
      {required String expected}) async {
    final ctrl = TextEditingController();
    bool ok = false;
    final result = await showDialog<bool>(
      context: ctx,
      builder: (dialogCtx) => StatefulBuilder(
        builder: (dialogCtx, setSt) => AlertDialog(
          title: const Text('Confirmação final'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('Digite "$expected" para confirmar.'),
              const SizedBox(height: Spacing.md),
              TextField(
                controller: ctrl,
                autofocus: true,
                decoration: InputDecoration(
                  hintText: expected,
                  border: const OutlineInputBorder(),
                ),
                onChanged: (v) => setSt(() => ok = v.trim() == expected),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogCtx, false),
              child: const Text('Cancelar'),
            ),
            FilledButton(
              onPressed: ok ? () => Navigator.pop(dialogCtx, true) : null,
              style: FilledButton.styleFrom(backgroundColor: AppColors.error),
              child: const Text('Confirmar'),
            ),
          ],
        ),
      ),
    );
    ctrl.dispose();
    return result;
  }

  // ─── Breakdown por pedido (lazy, ao expandir) ───────────────────────────

  Future<List<Map<String, dynamic>>> _loadOrdersBreakdown({
    required bool isDriver,
    required String entityId,
  }) async {
    final ws = _serverWeekStart;
    final we = _serverWeekEnd;
    if (ws == null || we == null) return const [];
    var q = _supabase
        .from('orders')
        .select(
            'id, delivered_at, payment_method, driver_earnings, final_total, total, platform_commission, customer_name')
        .eq('status', 'delivered')
        .gte('delivered_at', ws)
        .lte('delivered_at', we);
    q = isDriver
        ? q.eq('assigned_driver_id', entityId)
        : q.eq('restaurant_id', entityId);
    final rows = await q.order('delivered_at', ascending: true);
    return (rows as List)
        .map((e) => Map<String, dynamic>.from(e as Map))
        .toList();
  }

  // ─── Build ──────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: BoraScreenAppBar(
        title: 'Fechos Semanais',
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Recarregar',
            onPressed: _loading ? null : _load,
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            _buildWeekSelector(),
            Expanded(child: _buildBody()),
          ],
        ),
      ),
    );
  }

  Widget _buildWeekSelector() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
          Spacing.md, Spacing.sm, Spacing.md, Spacing.xxs),
      child: Row(
        children: [
          IconButton(
            icon: const Icon(Icons.chevron_left),
            tooltip: 'Semana anterior',
            onPressed: _loading ? null : () => _changeWeek(-1),
          ),
          Expanded(
            child: Column(
              children: [
                Text(
                  'Semana ${_fmtDate(_serverWeekStart)} → ${_fmtDate(_serverWeekEnd)}',
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                      fontSize: 15, fontWeight: FontWeight.w700),
                ),
                if (_isCurrentWeek)
                  const Text('semana atual (ainda aberta)',
                      style: TextStyle(
                          fontSize: 11, color: AppColors.textSecondary)),
              ],
            ),
          ),
          IconButton(
            icon: const Icon(Icons.chevron_right),
            tooltip: 'Semana seguinte',
            onPressed:
                _loading || _isCurrentWeek ? null : () => _changeWeek(1),
          ),
        ],
      ),
    );
  }

  Widget _buildBody() {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(Spacing.xxl),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline, size: 48, color: AppColors.error),
              const SizedBox(height: Spacing.md),
              Text(_error!, textAlign: TextAlign.center),
              const SizedBox(height: Spacing.md),
              ElevatedButton(
                  onPressed: _load, child: const Text('Tentar novamente')),
            ],
          ),
        ),
      );
    }

    final pendingDrivers =
        _drivers.where((r) => r['status'] == 'pending').length;
    final pendingPartners =
        _partners.where((r) => r['status'] == 'pending').length;

    return Column(
      children: [
        _buildBoraTotalsCard(),
        TabBar(
          controller: _tabController,
          labelColor: AppColors.primary,
          unselectedLabelColor: AppColors.textSecondary,
          indicatorColor: AppColors.primary,
          tabs: [
            Tab(
                text: 'ESTAFETAS (${_drivers.length}'
                    '${pendingDrivers > 0 ? ' · $pendingDrivers ⏳' : ''})'),
            Tab(
                text: 'PARCEIROS (${_partners.length}'
                    '${pendingPartners > 0 ? ' · $pendingPartners ⏳' : ''})'),
          ],
        ),
        Expanded(
          child: TabBarView(
            controller: _tabController,
            children: [
              _buildList(_drivers, isDriver: true),
              _buildList(_partners, isDriver: false),
            ],
          ),
        ),
      ],
    );
  }

  /// Cartão "como foi a semana da Bora" — admin_weekly_bora_totals.
  Widget _buildBoraTotalsCard() {
    final revenue = _num(_totals['orders_revenue']);
    final commissions = _num(_totals['platform_commissions']);
    final serviceFees = _num(_totals['service_fees']);
    final deliveryFees = _num(_totals['delivery_fees']);
    final bagFees = _num(_totals['bag_fees']);
    final deposits = _num(_totals['appointment_deposits']);
    final ordersCount = _num(_totals['orders_count']).toInt();

    return Card(
      margin: const EdgeInsets.fromLTRB(
          Spacing.md, Spacing.xxs, Spacing.md, Spacing.xs),
      shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(Radii.lg)),
      child: Padding(
        padding: const EdgeInsets.all(Spacing.md + 2),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.storefront, size: 18, color: AppColors.primary),
                const SizedBox(width: Spacing.xs),
                Text('Totais da Bora · $ordersCount pedidos entregues',
                    style: const TextStyle(
                        fontSize: 13, fontWeight: FontWeight.w700)),
              ],
            ),
            const SizedBox(height: Spacing.sm + 2),
            Row(
              children: [
                Expanded(
                    child: _totalStat('Receita total', revenue,
                        hint: 'tudo o que os clientes pagaram')),
                Expanded(
                    child: _totalStat('Comissões', commissions,
                        hint: 'parte da Bora nos pedidos')),
              ],
            ),
            const SizedBox(height: Spacing.sm),
            Row(
              children: [
                Expanded(
                    child: _totalStat('Taxas de serviço', serviceFees,
                        hint: 'fee visível ao cliente')),
                Expanded(
                    child: _totalStat('Taxas de entrega', deliveryFees,
                        hint: 'fretes cobrados')),
              ],
            ),
            const SizedBox(height: Spacing.sm),
            Row(
              children: [
                Expanded(
                    child: _totalStat('Sacos', bagFees,
                        hint: 'taxas de saco')),
                Expanded(
                    child: _totalStat('Sinais de marcações', deposits,
                        hint: 'reservas/serviços (€3)')),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _totalStat(String label, double v, {String? hint}) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label,
              style: const TextStyle(
                  fontSize: 11, color: AppColors.textSecondary)),
          Text(_euros(v),
              style:
                  const TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
          if (hint != null)
            Text(hint,
                style: const TextStyle(
                    fontSize: 9.5, color: AppColors.textSubtle)),
        ],
      );

  Widget _buildList(List<Map<String, dynamic>> rows, {required bool isDriver}) {
    if (rows.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(Spacing.xxl),
          child: Text(
            isDriver
                ? 'Nenhum estafeta com entregas nesta semana.'
                : 'Nenhum parceiro com pedidos nesta semana.',
            style: const TextStyle(color: AppColors.textSecondary),
            textAlign: TextAlign.center,
          ),
        ),
      );
    }
    return ListView.builder(
      padding: const EdgeInsets.only(bottom: Spacing.xxl),
      itemCount: rows.length,
      itemBuilder: (_, i) =>
          _SettlementCard(
        key: ValueKey(rows[i]['settlement_id']?.toString() ?? '$i'),
        row: rows[i],
        isDriver: isDriver,
        euros: _euros,
        numOf: _num,
        fmtDateTime: _fmtDateTime,
        balanceLabel: _balanceLabel,
        statusChip: _statusChip,
        onMark: () => _markSettlement(row: rows[i], isDriver: isDriver),
        loadBreakdown: () => _loadOrdersBreakdown(
          isDriver: isDriver,
          entityId: (isDriver
                  ? rows[i]['driver_id']
                  : rows[i]['partner_id'])
              ?.toString() ??
              '',
        ),
      ),
    );
  }
}

// ─── Cartão de 1 fecho (expansível com breakdown por pedido) ──────────────

class _SettlementCard extends StatefulWidget {
  const _SettlementCard({
    super.key,
    required this.row,
    required this.isDriver,
    required this.euros,
    required this.numOf,
    required this.fmtDateTime,
    required this.balanceLabel,
    required this.statusChip,
    required this.onMark,
    required this.loadBreakdown,
  });

  final Map<String, dynamic> row;
  final bool isDriver;
  final String Function(num) euros;
  final double Function(dynamic) numOf;
  final String Function(String?) fmtDateTime;
  final (String, Color) Function(String, double) balanceLabel;
  final (String, Color) Function(String) statusChip;
  final VoidCallback onMark;
  final Future<List<Map<String, dynamic>>> Function() loadBreakdown;

  @override
  State<_SettlementCard> createState() => _SettlementCardState();
}

class _SettlementCardState extends State<_SettlementCard> {
  bool _expanded = false;
  Future<List<Map<String, dynamic>>>? _breakdownFuture;

  @override
  Widget build(BuildContext context) {
    final r = widget.row;
    final isDriver = widget.isDriver;
    final name = isDriver
        ? (r['driver_name']?.toString() ?? 'Estafeta')
        : (r['partner_name']?.toString() ?? 'Parceiro');
    final count = widget.numOf(
        isDriver ? r['total_deliveries'] : r['total_orders']).toInt();
    final mainAmount =
        widget.numOf(isDriver ? r['total_earnings'] : r['gross_sales']);
    final cash = widget.numOf(
        isDriver ? r['total_cash_received'] : r['cash_kept_by_partner']);
    final net = widget.numOf(r['net_balance']);
    final direction = (r['direction'] as String?) ?? 'zero';
    final status = (r['status'] as String?) ?? 'pending';
    final paidAt = r['paid_at']?.toString();
    final reference = r['payment_reference']?.toString();
    final mbway = isDriver ? r['mbway_phone']?.toString() : null;

    final (balanceText, balanceColor) = widget.balanceLabel(direction, net);
    final (chipText, chipColor) =
        direction == 'zero' && status == 'pending'
            ? ('FECHADO', AppColors.textSecondary)
            : widget.statusChip(status);
    final canMark = status == 'pending' && direction != 'zero';

    return Card(
      margin: const EdgeInsets.symmetric(
          horizontal: Spacing.md, vertical: Spacing.xxs),
      shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(Radii.lg)),
      child: InkWell(
        borderRadius: BorderRadius.circular(Radii.lg),
        onTap: () {
          setState(() {
            _expanded = !_expanded;
            _breakdownFuture ??= widget.loadBreakdown();
          });
        },
        child: Padding(
          padding: const EdgeInsets.all(Spacing.md),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(name,
                        style: const TextStyle(
                            fontSize: 14, fontWeight: FontWeight.w700)),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: Spacing.xs + 2, vertical: Spacing.xxs),
                    decoration: BoxDecoration(
                      color: chipColor.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      chipText,
                      style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                          color: chipColor),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: Spacing.xxs),
              Text(
                isDriver
                    ? '$count entregas · Ganhos ${widget.euros(mainAmount)} · '
                        'Cash recebido ${widget.euros(cash)}'
                    : '$count pedidos · Vendas ${widget.euros(mainAmount)} · '
                        'Cash retido ${widget.euros(cash)}',
                style: const TextStyle(
                    fontSize: 12, color: AppColors.textSecondary),
              ),
              if (mbway != null && mbway.isNotEmpty)
                Text('MB Way: $mbway',
                    style: const TextStyle(
                        fontSize: 11, color: AppColors.textSubtle)),
              const SizedBox(height: Spacing.xs),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      balanceText,
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                        color: balanceColor,
                      ),
                    ),
                  ),
                  Icon(
                    _expanded ? Icons.expand_less : Icons.expand_more,
                    color: AppColors.textSecondary,
                  ),
                ],
              ),
              if (paidAt != null && status != 'pending')
                Text(
                  '${status == 'paid' ? 'Pago' : 'Recebido'} em '
                  '${widget.fmtDateTime(paidAt)}'
                  '${reference != null && reference.isNotEmpty ? ' · ref: $reference' : ''}',
                  style: const TextStyle(
                      fontSize: 11, color: AppColors.textSubtle),
                ),
              if (_expanded) ...[
                const Divider(height: Spacing.lg),
                _buildEquation(isDriver, mainAmount, cash, net, direction),
                const SizedBox(height: Spacing.xs),
                _buildBreakdown(),
              ],
              if (canMark) ...[
                const SizedBox(height: Spacing.sm),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: widget.onMark,
                    icon: const Icon(Icons.check_circle, size: 18),
                    label: Text(direction.startsWith('bora_pays')
                        ? 'MARCAR COMO PAGO'
                        : 'MARCAR COMO RECEBIDO'),
                    style: FilledButton.styleFrom(
                      backgroundColor: direction.startsWith('bora_pays')
                          ? AppColors.primary
                          : AppColors.accent,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  /// A conta da semana em linguagem simples.
  Widget _buildEquation(
      bool isDriver, double main, double cash, double net, String direction) {
    final String text;
    if (isDriver) {
      final tail = direction == 'driver_pays_bora'
          ? 'O estafeta entrega ${widget.euros(net)} à Bora.'
          : direction == 'bora_pays_driver'
              ? 'A Bora paga ${widget.euros(net)} ao estafeta.'
              : 'Ninguém deve nada esta semana.';
      text = 'Ganhos da semana ${widget.euros(main)} − dinheiro que recebeu '
          'em mãos ${widget.euros(cash)} = saldo ${widget.euros(net)}.\n$tail';
    } else {
      final tail = direction == 'partner_pays_bora'
          ? 'O parceiro entrega ${widget.euros(net)} à Bora.'
          : direction == 'bora_pays_partner'
              ? 'A Bora paga ${widget.euros(net)} ao parceiro.'
              : 'Ninguém deve nada esta semana.';
      text = 'Vendas ${widget.euros(main)} − comissão da Bora − dinheiro já '
          'retido ${widget.euros(cash)} = saldo ${widget.euros(net)}.\n$tail';
    }
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(Spacing.sm + 2),
      decoration: BoxDecoration(
        color: AppColors.surface2,
        borderRadius: BorderRadius.circular(Radii.sm),
      ),
      child: Text(text, style: const TextStyle(fontSize: 12, height: 1.4)),
    );
  }

  Widget _buildBreakdown() {
    return FutureBuilder<List<Map<String, dynamic>>>(
      future: _breakdownFuture,
      builder: (context, snap) {
        if (snap.connectionState != ConnectionState.done) {
          return const Padding(
            padding: EdgeInsets.all(Spacing.sm),
            child: Center(
              child: SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            ),
          );
        }
        if (snap.hasError) {
          return Text('Não foi possível carregar os pedidos: ${snap.error}',
              style: const TextStyle(fontSize: 11, color: AppColors.error));
        }
        final orders = snap.data ?? const [];
        if (orders.isEmpty) {
          return const Text('Sem pedidos individuais para mostrar.',
              style: TextStyle(
                  fontSize: 11, color: AppColors.textSecondary));
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Pedido a pedido:',
                style:
                    TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
            const SizedBox(height: Spacing.xs),
            ...orders.map(_orderLine),
          ],
        );
      },
    );
  }

  Widget _orderLine(Map<String, dynamic> o) {
    final id = o['id']?.toString() ?? '';
    final shortId = id.length >= 4
        ? id.substring(id.length - 4).toUpperCase()
        : id.toUpperCase();
    final when = widget.fmtDateTime(o['delivered_at']?.toString());
    final total = widget.numOf(o['final_total'] != null &&
            widget.numOf(o['final_total']) > 0
        ? o['final_total']
        : o['total']);
    final isCash = (o['payment_method']?.toString() ?? '') == 'cash';

    final String line;
    if (widget.isDriver) {
      final earned = widget.numOf(o['driver_earnings']);
      line = '#$shortId · $when · ganhou ${widget.euros(earned)}'
          '${isCash ? ' · cliente pagou ${widget.euros(total)} em dinheiro (ficou com o estafeta)' : ''}';
    } else {
      final commission = widget.numOf(o['platform_commission']);
      line = '#$shortId · $when · venda ${widget.euros(total)}'
          '${commission > 0 ? ' · comissão Bora ${widget.euros(commission)}' : ''}'
          '${isCash ? ' · pago em dinheiro' : ''}';
    }
    return Padding(
      padding: const EdgeInsets.only(bottom: Spacing.xxs),
      child: Text('• $line',
          style: const TextStyle(fontSize: 11, height: 1.35)),
    );
  }
}
