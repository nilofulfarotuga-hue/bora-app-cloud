import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../config/app_colors.dart';
import '../../config/app_spacing.dart';
import '../../models/tvde_plan_quote.dart';
import '../../widgets/bora/bora_screen_app_bar.dart';
import '_admin_rpc_errors.dart';

/// Bora Motorista (TVDE) — Pedidos de adesão a planos (G/C4).
///
/// O cliente pede adesão na app (`tvde_request_plan`) e o pedido cai aqui.
/// O admin aprova (ativa a assinatura num clique via
/// `admin_decide_tvde_plan_request` → `admin_grant_subscription`) ou recusa.
///
/// [Rota do plano · 2026-08-25] Cada pedido mostra a ROTA que o cliente
/// escolheu, os km dessa rota e o VALOR ORÇADO — o valor é pedido ao servidor
/// (`tvde_quote_plan`), nunca calculado aqui.
/// Idioma: PT-BR.
class AdminTvdePlanRequestsScreen extends StatefulWidget {
  const AdminTvdePlanRequestsScreen({super.key});

  @override
  State<AdminTvdePlanRequestsScreen> createState() =>
      _AdminTvdePlanRequestsScreenState();
}

class _AdminTvdePlanRequestsScreenState
    extends State<AdminTvdePlanRequestsScreen> {
  late Future<List<Map<String, dynamic>>> _future;
  bool _busy = false;
  String? _statusFilter = 'pendente';

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<List<Map<String, dynamic>>> _load() async {
    final res = await Supabase.instance.client.rpc(
      'admin_tvde_plan_requests_list',
      params: {'p_status': _statusFilter},
    );
    final list = (res as List?) ?? const [];
    return list
        .whereType<Map>()
        .map((e) => Map<String, dynamic>.from(e))
        .toList();
  }

  Future<void> _refresh() async {
    setState(() => _future = _load());
    await _future;
  }

  Future<void> _decide(Map<String, dynamic> req, bool approve) async {
    final label = (req['plan_label'] as String?) ??
        _planLabel(req['plan'] as String? ?? '');
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(approve ? 'Aprovar e ativar?' : 'Recusar pedido?'),
        content: Text(approve
            ? 'Isto ativa o "$label" na conta do cliente imediatamente '
                '(concede a assinatura sem cobrança).'
            : 'O pedido será marcado como recusado.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancelar')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: Text(approve ? 'Aprovar' : 'Recusar')),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    setState(() => _busy = true);
    try {
      await Supabase.instance.client.rpc('admin_decide_tvde_plan_request',
          params: {'p_id': req['id'], 'p_approve': approve});
      if (!mounted) return;
      _toast(approve ? 'Plano aprovado e ativado.' : 'Pedido recusado.',
          approve ? AppColors.primary : AppColors.textSubtle);
      await _refresh();
    } catch (e) {
      if (!mounted) return;
      _toast(humanizeAdminRpcError(e), AppColors.error);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _toast(String msg, Color color) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), backgroundColor: color),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: BoraScreenAppBar(
        title: 'Pedidos de Plano — Bora Motorista',
        actions: [
          PopupMenuButton<String?>(
            icon: const Icon(Icons.filter_list),
            tooltip: 'Filtrar',
            initialValue: _statusFilter,
            onSelected: (v) {
              setState(() => _statusFilter = v);
              _refresh();
            },
            itemBuilder: (_) => const [
              PopupMenuItem(value: 'pendente', child: Text('Pendentes')),
              PopupMenuItem(value: 'aprovado', child: Text('Aprovados')),
              PopupMenuItem(value: 'recusado', child: Text('Recusados')),
              PopupMenuItem(value: null, child: Text('Todos')),
            ],
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Atualizar',
            onPressed: _refresh,
          ),
        ],
      ),
      body: Column(
        children: [
          if (_busy) const LinearProgressIndicator(minHeight: 2),
          Expanded(
            child: RefreshIndicator(
              onRefresh: _refresh,
              child: FutureBuilder<List<Map<String, dynamic>>>(
                future: _future,
                builder: (context, snap) {
                  if (snap.connectionState == ConnectionState.waiting) {
                    return const Center(child: CircularProgressIndicator());
                  }
                  if (snap.hasError) {
                    return ListView(
                      padding: const EdgeInsets.all(24),
                      children: [
                        const SizedBox(height: 60),
                        const Icon(Icons.error_outline,
                            size: 44, color: AppColors.error),
                        const SizedBox(height: 12),
                        Text('Erro:\n${snap.error}',
                            textAlign: TextAlign.center),
                      ],
                    );
                  }
                  final rows = snap.data ?? const [];
                  if (rows.isEmpty) {
                    return ListView(
                      children: const [
                        SizedBox(height: 120),
                        Center(
                          child: Text('Sem pedidos neste filtro.',
                              textAlign: TextAlign.center,
                              style:
                                  TextStyle(color: AppColors.textSecondary)),
                        ),
                      ],
                    );
                  }
                  return ListView.builder(
                    padding: const EdgeInsets.fromLTRB(12, 12, 12, 24),
                    itemCount: rows.length,
                    itemBuilder: (_, i) => _RequestCard(
                      data: rows[i],
                      busy: _busy,
                      onApprove: () => _decide(rows[i], true),
                      onReject: () => _decide(rows[i], false),
                    ),
                  );
                },
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _RequestCard extends StatelessWidget {
  const _RequestCard({
    required this.data,
    required this.busy,
    required this.onApprove,
    required this.onReject,
  });
  final Map<String, dynamic> data;
  final bool busy;
  final VoidCallback onApprove;
  final VoidCallback onReject;

  @override
  Widget build(BuildContext context) {
    final name = (data['client_name'] as String?)?.trim();
    final email = (data['client_email'] as String?) ?? '—';
    final phone = (data['client_phone'] as String?)?.trim();
    final plan = (data['plan'] as String?) ?? '—';
    final label = (data['plan_label'] as String?) ?? _planLabel(plan);
    final status = (data['status'] as String?) ?? 'pendente';
    final requestedAt = data['requested_at'];
    final pending = status == 'pendente';
    final distanceKm = (data['distance_km'] as num?)?.toDouble();
    final kmIncluded = (data['km_included'] as num?)?.toInt();
    final origin = (data['route_origin_label'] as String?)?.trim();
    final dest = (data['route_dest_label'] as String?)?.trim();
    final hasRoute =
        (origin?.isNotEmpty ?? false) && (dest?.isNotEmpty ?? false);

    return Card(
      elevation: 2,
      margin: const EdgeInsets.only(bottom: 12),
      shape:
          RoundedRectangleBorder(borderRadius: BorderRadius.circular(Radii.lg)),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.person_outline, color: AppColors.primary),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    (name != null && name.isNotEmpty) ? name : email,
                    style: const TextStyle(
                        fontWeight: FontWeight.w700, fontSize: 15),
                  ),
                ),
                _StatusChip(status: status),
              ],
            ),
            const SizedBox(height: 6),
            Text('Plano pedido: $label',
                style: const TextStyle(
                    fontSize: 13, color: AppColors.textSecondary)),
            Text(
              hasRoute ? 'Rota: $origin → $dest' : 'Rota: —',
              style: const TextStyle(
                  fontSize: 12.5, color: AppColors.textSecondary),
            ),
            Text(
              'Km da rota: ${distanceKm != null ? '${TvdePlanQuote.km(distanceKm)} km' : '—'}'
              '${kmIncluded != null ? ' · incluídos: $kmIncluded km/viagem' : ''}',
              style: const TextStyle(
                  fontSize: 12.5, color: AppColors.textSecondary),
            ),
            _QuotedValue(plan: plan, distanceKm: distanceKm),
            Text('$email${phone != null && phone.isNotEmpty ? ' · $phone' : ''}',
                style: const TextStyle(fontSize: 12, color: AppColors.textSubtle)),
            Text('Pedido em ${_fmtDate(requestedAt)}',
                style: const TextStyle(fontSize: 12, color: AppColors.textSubtle)),
            if (pending) ...[
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: busy ? null : onReject,
                      icon: const Icon(Icons.close, size: 18),
                      label: const Text('Recusar'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: busy ? null : onApprove,
                      style: FilledButton.styleFrom(
                          backgroundColor: AppColors.primary),
                      icon: const Icon(Icons.check, size: 18),
                      label: const Text('Aprovar e ativar'),
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Valor orçado do pedido — perguntado ao servidor (`tvde_quote_plan`) para o
/// plano + os km da rota do cliente. Sem rota não há valor a mostrar.
class _QuotedValue extends StatelessWidget {
  const _QuotedValue({required this.plan, required this.distanceKm});
  final String plan;
  final double? distanceKm;

  @override
  Widget build(BuildContext context) {
    if (distanceKm == null || distanceKm! <= 0) {
      return const Text('Valor orçado: —',
          style: TextStyle(fontSize: 12.5, color: AppColors.textSubtle));
    }
    return FutureBuilder<Object?>(
      future: Supabase.instance.client.rpc('tvde_quote_plan',
          params: {'p_plan': plan, 'p_distance_km': distanceKm}),
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return const Text('Valor orçado: calculando…',
              style: TextStyle(fontSize: 12.5, color: AppColors.textSubtle));
        }
        final res = snap.data;
        if (snap.hasError || res is! Map) {
          return const Text('Valor orçado: indisponível',
              style: TextStyle(fontSize: 12.5, color: AppColors.textSubtle));
        }
        final q = TvdePlanQuote.fromMap(Map<String, dynamic>.from(res),
            distanceKm: distanceKm!);
        final extra = q.hasExtra
            ? ' (base ${TvdePlanQuote.eur(q.basePriceCents)} + '
                '${q.extraKm} km a mais = ${TvdePlanQuote.eur(q.extraCents)})'
            : '';
        return Text(
          'Valor orçado: ${TvdePlanQuote.eur(q.priceCents)}$extra',
          style: const TextStyle(
              fontSize: 12.5,
              fontWeight: FontWeight.w600,
              color: AppColors.primary),
        );
      },
    );
  }
}

class _StatusChip extends StatelessWidget {
  const _StatusChip({required this.status});
  final String status;

  @override
  Widget build(BuildContext context) {
    final (color, txt) = switch (status) {
      'aprovado' => (AppColors.primary, 'Aprovado'),
      'recusado' => (AppColors.error, 'Recusado'),
      _ => (AppColors.accent, 'Pendente'),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(txt,
          style: TextStyle(
              color: color, fontSize: 11, fontWeight: FontWeight.w600)),
    );
  }
}

String _planLabel(String p) => switch (p) {
      'semanal' => 'Plano Semanal',
      'quinzenal' => 'Plano Quinzenal',
      'mensal' => 'Plano Mensal',
      _ => p,
    };

String _fmtDate(dynamic iso) {
  if (iso == null) return '—';
  final d = DateTime.tryParse(iso.toString());
  if (d == null) return iso.toString();
  final l = d.toLocal();
  String two(int n) => n.toString().padLeft(2, '0');
  return '${two(l.day)}/${two(l.month)}/${l.year} ${two(l.hour)}:${two(l.minute)}';
}
