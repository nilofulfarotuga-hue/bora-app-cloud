import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../config/app_colors.dart';
import '../../config/app_spacing.dart';
import '../../models/tvde_plan_quote.dart';
import '../../widgets/bora/bora_screen_app_bar.dart';
import '_admin_rpc_errors.dart';

/// Bora Motorista (TVDE) — Assinaturas (conceder / ver).
///
/// Concede uma assinatura a um cliente via `admin_grant_subscription(client,
/// plano, km incluídos, rota)`. Lista as assinaturas via
/// `admin_tvde_subscriptions_list()` (RPC admin read-only, aditivo).
/// O cliente é escolhido reaproveitando `admin_list_clients` (busca já existente).
///
/// [Rota do plano · 2026-08-25] O preço do plano depende da rota do cliente.
/// Ao conceder à mão, o admin informa os km da rota, vê o orçamento real
/// (`tvde_quote_plan`, mesma conta que o cliente vê) e só então confirma.
/// Idioma: PT-BR.
class AdminTvdeSubscriptionsScreen extends StatefulWidget {
  const AdminTvdeSubscriptionsScreen({super.key});

  @override
  State<AdminTvdeSubscriptionsScreen> createState() =>
      _AdminTvdeSubscriptionsScreenState();
}

class _AdminTvdeSubscriptionsScreenState
    extends State<AdminTvdeSubscriptionsScreen> {
  late Future<List<Map<String, dynamic>>> _future;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<List<Map<String, dynamic>>> _load() async {
    final res =
        await Supabase.instance.client.rpc('admin_tvde_subscriptions_list');
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

  Future<void> _grantFlow() async {
    final client = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (_) => const _ClientPickerDialog(),
    );
    if (client == null || !mounted) return;

    final plan = await showDialog<String>(
      context: context,
      builder: (ctx) => _PlanPickerDialog(
        clientLabel: (client['bora_name'] as String?)?.trim().isNotEmpty == true
            ? client['bora_name'] as String
            : (client['email'] as String? ?? 'cliente'),
      ),
    );
    if (plan == null || !mounted) return;

    // Km da rota + orçamento real antes de confirmar — o admin vê a mesma
    // conta que o cliente veria para essa rota.
    final details = await showDialog<_GrantDetails>(
      context: context,
      builder: (_) => _GrantDetailsDialog(plan: plan),
    );
    if (details == null || !mounted) return;

    setState(() => _busy = true);
    try {
      await Supabase.instance.client.rpc('admin_grant_subscription', params: {
        'p_client_id': client['user_id'],
        'p_plan': plan,
        'p_km_included': details.kmIncluded,
        'p_origin_label': details.originLabel,
        'p_dest_label': details.destLabel,
      });
      if (!mounted) return;
      _toast(
          'Assinatura "$plan" concedida (${details.kmIncluded} km incluídos).',
          AppColors.primary);
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
        title: 'Assinaturas — Bora Motorista',
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Atualizar',
            onPressed: _refresh,
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: AppColors.primary,
        onPressed: _busy ? null : _grantFlow,
        icon: const Icon(Icons.card_membership, color: Colors.white),
        label: const Text('Conceder assinatura',
            style: TextStyle(color: Colors.white)),
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
                          child: Text(
                            'Sem assinaturas ainda.\n'
                            'Toca em "Conceder assinatura" para começar.',
                            textAlign: TextAlign.center,
                            style: TextStyle(color: AppColors.textSecondary),
                          ),
                        ),
                      ],
                    );
                  }
                  return ListView.builder(
                    padding: const EdgeInsets.fromLTRB(12, 12, 12, 90),
                    itemCount: rows.length,
                    itemBuilder: (_, i) => _SubCard(data: rows[i]),
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

class _SubCard extends StatelessWidget {
  const _SubCard({required this.data});
  final Map<String, dynamic> data;

  @override
  Widget build(BuildContext context) {
    final active = data['active'] == true;
    final name = (data['client_name'] as String?)?.trim();
    final email = (data['client_email'] as String?) ?? '—';
    final plan = (data['plan'] as String?) ?? '—';
    final total = (data['rides_total'] as num?)?.toInt() ?? 0;
    final used = (data['rides_used'] as num?)?.toInt() ?? 0;
    final daily = (data['daily_included'] as num?)?.toInt() ?? 0;
    final price = (data['price_cents'] as num?)?.toInt() ?? 0;
    final endsAt = data['ends_at'];
    final kmIncluded = (data['km_included'] as num?)?.toInt();
    final distanceKm = (data['distance_km'] as num?)?.toDouble();
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
                Expanded(
                  child: Text(
                    (name != null && name.isNotEmpty) ? name : email,
                    style: const TextStyle(
                        fontWeight: FontWeight.w700, fontSize: 15),
                  ),
                ),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: (active ? AppColors.primary : AppColors.textSubtle)
                        .withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(active ? 'Ativa' : 'Inativa',
                      style: TextStyle(
                          color:
                              active ? AppColors.primary : AppColors.textSubtle,
                          fontSize: 11,
                          fontWeight: FontWeight.w600)),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text('Plano: ${_planLabel(plan)} · €${(price / 100).toStringAsFixed(2)}',
                style: const TextStyle(
                    fontSize: 13, color: AppColors.textSecondary)),
            const SizedBox(height: 2),
            Text(
              'Km incluídos: ${kmIncluded != null ? '$kmIncluded km/viagem' : '—'}'
              '${distanceKm != null ? ' · rota de ${TvdePlanQuote.km(distanceKm)} km' : ''}',
              style: const TextStyle(
                  fontSize: 12.5, color: AppColors.textSecondary),
            ),
            Text(
              hasRoute ? 'Rota: $origin → $dest' : 'Rota: —',
              style:
                  const TextStyle(fontSize: 12.5, color: AppColors.textSubtle),
            ),
            const SizedBox(height: 8),
            LinearProgressIndicator(
              value: total == 0 ? 0 : (used / total).clamp(0, 1).toDouble(),
              backgroundColor: AppColors.textSubtle.withValues(alpha: 0.15),
              color: AppColors.primary,
              minHeight: 6,
            ),
            const SizedBox(height: 6),
            Text(
              'Corridas usadas: $used / $total · $daily/dia incluídas · '
              'termina ${_fmtDate(endsAt)}',
              style:
                  const TextStyle(fontSize: 12, color: AppColors.textSubtle),
            ),
          ],
        ),
      ),
    );
  }
}

/// Busca + escolhe um cliente (reaproveita `admin_list_clients`).
class _ClientPickerDialog extends StatefulWidget {
  const _ClientPickerDialog();

  @override
  State<_ClientPickerDialog> createState() => _ClientPickerDialogState();
}

class _ClientPickerDialogState extends State<_ClientPickerDialog> {
  final _ctrl = TextEditingController();
  List<Map<String, dynamic>> _results = const [];
  bool _loading = false;

  Future<void> _search() async {
    setState(() => _loading = true);
    try {
      final res = await Supabase.instance.client.rpc('admin_list_clients',
          params: {
            'p_search': _ctrl.text.trim().isEmpty ? null : _ctrl.text.trim(),
            'p_limit': 30,
          });
      final list = (res as List?) ?? const [];
      setState(() {
        _results = list
            .whereType<Map>()
            .map((e) => Map<String, dynamic>.from(e))
            .toList();
        _loading = false;
      });
    } catch (_) {
      setState(() => _loading = false);
    }
  }

  @override
  void initState() {
    super.initState();
    _search();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Escolher cliente'),
      content: SizedBox(
        width: double.maxFinite,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _ctrl,
              onSubmitted: (_) => _search(),
              decoration: InputDecoration(
                hintText: 'Buscar nome / email / telefone',
                suffixIcon: IconButton(
                  icon: const Icon(Icons.search),
                  onPressed: _search,
                ),
                border: const OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 8),
            SizedBox(
              height: 300,
              child: _loading
                  ? const Center(child: CircularProgressIndicator())
                  : _results.isEmpty
                      ? const Center(child: Text('Sem resultados.'))
                      : ListView.builder(
                          itemCount: _results.length,
                          itemBuilder: (_, i) {
                            final c = _results[i];
                            final name = (c['bora_name'] as String?)?.trim();
                            final email = (c['email'] as String?) ?? '—';
                            return ListTile(
                              dense: true,
                              leading: const Icon(Icons.person_outline),
                              title: Text(
                                  (name != null && name.isNotEmpty)
                                      ? name
                                      : email,
                                  style: const TextStyle(fontSize: 14)),
                              subtitle: Text(email,
                                  style: const TextStyle(fontSize: 12)),
                              onTap: () => Navigator.pop(context, c),
                            );
                          },
                        ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancelar'),
        ),
      ],
    );
  }
}

class _PlanPickerDialog extends StatelessWidget {
  const _PlanPickerDialog({required this.clientLabel});
  final String clientLabel;

  @override
  Widget build(BuildContext context) {
    // Só os nomes: quantas corridas e quanto custa quem diz é o servidor, no
    // passo seguinte (tvde_quote_plan) — nada de números fixos aqui.
    const plans = {
      'semanal': 'Semanal',
      'quinzenal': 'Quinzenal',
      'mensal': 'Mensal',
    };
    return AlertDialog(
      title: Text('Plano para $clientLabel'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: plans.entries
            .map((e) => ListTile(
                  leading: const Icon(Icons.card_membership,
                      color: AppColors.primary),
                  title: Text(e.value, style: const TextStyle(fontSize: 14)),
                  onTap: () => Navigator.pop(context, e.key),
                ))
            .toList(),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancelar'),
        ),
      ],
    );
  }
}

/// O que o admin definiu para a assinatura concedida à mão.
class _GrantDetails {
  const _GrantDetails({
    required this.kmIncluded,
    this.originLabel,
    this.destLabel,
  });
  final int kmIncluded;
  final String? originLabel;
  final String? destLabel;
}

/// Km da rota + rota (opcional) + ORÇAMENTO do servidor antes de confirmar.
/// O botão "Conceder" só acende depois de haver orçamento — o admin nunca
/// concede às cegas.
class _GrantDetailsDialog extends StatefulWidget {
  const _GrantDetailsDialog({required this.plan});
  final String plan;

  @override
  State<_GrantDetailsDialog> createState() => _GrantDetailsDialogState();
}

class _GrantDetailsDialogState extends State<_GrantDetailsDialog> {
  final _kmCtrl = TextEditingController();
  final _originCtrl = TextEditingController();
  final _destCtrl = TextEditingController();

  TvdePlanQuote? _quote;
  bool _loading = false;
  String? _error;

  @override
  void dispose() {
    _kmCtrl.dispose();
    _originCtrl.dispose();
    _destCtrl.dispose();
    super.dispose();
  }

  int? get _km {
    final v = int.tryParse(_kmCtrl.text.trim());
    return (v != null && v > 0) ? v : null;
  }

  Future<void> _quotar() async {
    final km = _km;
    if (km == null) {
      setState(() => _error = 'Informe os km da rota (número inteiro > 0).');
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
      _quote = null;
    });
    try {
      final res = await Supabase.instance.client.rpc('tvde_quote_plan',
          params: {'p_plan': widget.plan, 'p_distance_km': km});
      if (!mounted) return;
      if (res is Map) {
        setState(() {
          _quote = TvdePlanQuote.fromMap(Map<String, dynamic>.from(res),
              distanceKm: km.toDouble());
          _loading = false;
        });
      } else {
        setState(() {
          _error = 'O servidor não devolveu orçamento para este plano.';
          _loading = false;
        });
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = humanizeAdminRpcError(e);
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final q = _quote;
    return AlertDialog(
      title: Text('Km e orçamento — ${_planLabel(widget.plan)}'),
      content: SizedBox(
        width: double.maxFinite,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'O preço do plano depende da rota do cliente. Informe os km da '
                'rota habitual dele — é esse o limite incluído por viagem.',
                style: TextStyle(fontSize: 12.5, color: AppColors.textSecondary),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _kmCtrl,
                keyboardType: TextInputType.number,
                onChanged: (_) => setState(() => _quote = null),
                decoration: const InputDecoration(
                  labelText: 'Km da rota (incluídos por viagem)',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _originCtrl,
                decoration: const InputDecoration(
                  labelText: 'Origem (opcional)',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _destCtrl,
                decoration: const InputDecoration(
                  labelText: 'Destino (opcional)',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 10),
              OutlinedButton.icon(
                onPressed: _loading ? null : _quotar,
                icon: const Icon(Icons.calculate_outlined, size: 18),
                label: Text(_loading ? 'Calculando…' : 'Ver orçamento'),
              ),
              if (_error != null) ...[
                const SizedBox(height: 8),
                Text(_error!,
                    style: const TextStyle(
                        fontSize: 12.5, color: AppColors.error)),
              ],
              if (q != null) ...[
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: AppColors.primaryWash,
                    borderRadius: BorderRadius.circular(Radii.md),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      for (final l in _adminBreakdown(q, widget.plan))
                        Padding(
                          padding: const EdgeInsets.only(bottom: 3),
                          child: Text(l,
                              style: const TextStyle(
                                  fontSize: 12.5,
                                  color: AppColors.textSecondary)),
                        ),
                      const SizedBox(height: 4),
                      Text('TOTAL: ${TvdePlanQuote.eur(q.priceCents)}',
                          style: const TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w700,
                              color: AppColors.primary)),
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancelar'),
        ),
        FilledButton(
          onPressed: q == null
              ? null
              : () => Navigator.pop(
                    context,
                    _GrantDetails(
                      kmIncluded: _km!,
                      originLabel: _originCtrl.text.trim().isEmpty
                          ? null
                          : _originCtrl.text.trim(),
                      destLabel: _destCtrl.text.trim().isEmpty
                          ? null
                          : _destCtrl.text.trim(),
                    ),
                  ),
          style: FilledButton.styleFrom(backgroundColor: AppColors.primary),
          child: const Text('Conceder'),
        ),
      ],
    );
  }
}

/// A mesma conta que o cliente vê, escrita em PT-BR para o painel.
List<String> _adminBreakdown(TvdePlanQuote q, String plan) => [
      'Plano ${_planLabel(plan)}: ${TvdePlanQuote.eur(q.basePriceCents)}',
      'Inclui ${q.ridesTotal} viagens (${q.ridesPerDay} por dia, seg-sex)',
      'Distância incluída: até ${q.baseKm} km por viagem',
      'Rota informada: ${TvdePlanQuote.km(q.distanceKm)} km',
      if (q.hasExtra)
        '${q.extraKm} km a mais × ${TvdePlanQuote.eur(q.perKmCents)} × '
            '${q.ridesTotal} viagens = ${TvdePlanQuote.eur(q.extraCents)}',
    ];

String _planLabel(String p) => switch (p) {
      'semanal' => 'Semanal',
      'quinzenal' => 'Quinzenal',
      'mensal' => 'Mensal',
      _ => p,
    };

String _fmtDate(dynamic iso) {
  if (iso == null) return '—';
  final d = DateTime.tryParse(iso.toString());
  if (d == null) return iso.toString();
  final l = d.toLocal();
  String two(int n) => n.toString().padLeft(2, '0');
  return '${two(l.day)}/${two(l.month)}/${l.year}';
}
