import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../config/app_colors.dart';
import '../../config/app_spacing.dart';
import '../../widgets/bora/bora_screen_app_bar.dart';
import '_admin_rpc_errors.dart';

/// Bora Motorista (TVDE) — **Corridas presas no pagamento**.
///
/// Lê `admin_tvde_stuck_payments(p_minutes)`: corridas em `solicitada` cujo
/// pagamento nunca fechou (`requires_action` / `processing` / …) há mais de N
/// minutos. Idioma: PT-BR.
///
/// Porquê este ecrã (2026-08-13): o `stripe-webhook` não conhecia corridas
/// TVDE, por isso o servidor nunca marcava `payment_status='succeeded'` e o
/// dispatch nunca arrancava. Passaram-se dias sem ninguém ver — o cliente
/// pagava, esperava, cancelava. Com o ramo TVDE no webhook isto deixa de
/// acontecer sozinho, mas a caixa fica: MB Way falhado, webhook em baixo ou
/// rede do banco lenta continuam a produzir corridas presas, e alguém tem de
/// as ver e resolver.
class AdminTvdeStuckPaymentsScreen extends StatefulWidget {
  const AdminTvdeStuckPaymentsScreen({super.key});

  @override
  State<AdminTvdeStuckPaymentsScreen> createState() =>
      _AdminTvdeStuckPaymentsScreenState();
}

class _AdminTvdeStuckPaymentsScreenState
    extends State<AdminTvdeStuckPaymentsScreen> {
  /// Janela mínima antes de considerar "presa". 5 min = o pedido do Danilo.
  int _minutes = 5;
  late Future<List<Map<String, dynamic>>> _future;
  String? _busyRideId;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<List<Map<String, dynamic>>> _load() async {
    final res = await Supabase.instance.client
        .rpc('admin_tvde_stuck_payments', params: {'p_minutes': _minutes});
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

  void _toast(String msg, {bool erro = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg),
      backgroundColor: erro ? AppColors.error : null,
    ));
  }

  /// Relê o PaymentIntent na Stripe e grava o estado real na corrida.
  /// Se der `succeeded`, o trigger `tr_tvde_dispatch_on_paid` despacha sozinho.
  Future<void> _reconferir(Map<String, dynamic> row) async {
    final id = row['id'].toString();
    setState(() => _busyRideId = id);
    try {
      final res = await Supabase.instance.client.functions.invoke(
        'tvde-payment',
        body: {'action': 'confirm_ride_payment', 'ride_id': id},
      );
      final data = res.data;
      final status = (data is Map ? data['payment_status'] : null) ?? '?';
      final ok = data is Map && data['succeeded'] == true;
      _toast(ok
          ? 'Pagamento confirmado — motorista sendo chamado.'
          : 'Stripe diz: $status (ainda não pago).');
    } catch (e) {
      _toast(humanizeAdminRpcError(e), erro: true);
    } finally {
      if (mounted) setState(() => _busyRideId = null);
      await _refresh();
    }
  }

  Future<void> _cancelar(Map<String, dynamic> row) async {
    final id = row['id'].toString();
    final ok = await _confirmar(
      titulo: 'Cancelar corrida?',
      corpo: 'A corrida vai para `cancelada_cliente`. Como nenhum motorista foi '
          'envolvido, a taxa de cancelamento será €0,00.',
      acao: 'Cancelar corrida',
    );
    if (ok != true) return;
    setState(() => _busyRideId = id);
    try {
      await Supabase.instance.client.rpc('tvde_cancel_ride', params: {
        'p_ride_id': id,
        'p_actor': 'cliente',
        'p_reason': 'admin_stuck_payment',
      });
      _toast('Corrida cancelada.');
    } catch (e) {
      _toast(humanizeAdminRpcError(e), erro: true);
    } finally {
      if (mounted) setState(() => _busyRideId = null);
      await _refresh();
    }
  }

  Future<void> _reembolsar(Map<String, dynamic> row) async {
    final id = row['id'].toString();
    final cents = (row['est_fare_cents'] as num?)?.toInt() ?? 0;
    final ok = await _confirmar(
      titulo: 'Reembolsar?',
      corpo: 'Devolve até €${(cents / 100).toStringAsFixed(2)} na Stripe, menos '
          'a taxa de cancelamento gravada na corrida. Se o valor a devolver '
          'for €0,00, nada é chamado na Stripe e o estado fica '
          '`kept_cancel_fee` (nunca `refunded` — o registro não mente).',
      acao: 'Reembolsar',
    );
    if (ok != true) return;
    setState(() => _busyRideId = id);
    try {
      final res = await Supabase.instance.client.functions.invoke(
        'tvde-payment',
        body: {'action': 'refund', 'ride_id': id},
      );
      final data = res.data;
      final refunded = (data is Map ? data['refundCents'] as num? : null) ?? 0;
      _toast(refunded > 0
          ? 'Reembolsado €${(refunded / 100).toStringAsFixed(2)}.'
          : 'Nada a devolver (taxa reteve o valor todo).');
    } catch (e) {
      _toast(humanizeAdminRpcError(e), erro: true);
    } finally {
      if (mounted) setState(() => _busyRideId = null);
      await _refresh();
    }
  }

  Future<bool?> _confirmar({
    required String titulo,
    required String corpo,
    required String acao,
  }) =>
      showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text(titulo),
          content: Text(corpo),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Voltar')),
            TextButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: Text(acao)),
          ],
        ),
      );

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: BoraScreenAppBar(
        title: 'Corridas presas no pagamento',
        actions: [
          PopupMenuButton<int>(
            tooltip: 'Janela',
            icon: const Icon(Icons.timer_outlined),
            initialValue: _minutes,
            onSelected: (v) {
              setState(() => _minutes = v);
              _refresh();
            },
            itemBuilder: (_) => const [
              PopupMenuItem(value: 5, child: Text('Presas há +5 min')),
              PopupMenuItem(value: 15, child: Text('Presas há +15 min')),
              PopupMenuItem(value: 60, child: Text('Presas há +1 h')),
              PopupMenuItem(value: 1440, child: Text('Presas há +1 dia')),
            ],
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Atualizar',
            onPressed: _refresh,
          ),
        ],
      ),
      body: RefreshIndicator(
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
                  Text(humanizeAdminRpcError(snap.error!),
                      textAlign: TextAlign.center),
                ],
              );
            }
            final rows = snap.data ?? const [];
            if (rows.isEmpty) {
              return ListView(
                children: [
                  const SizedBox(height: 120),
                  Center(
                    child: Text(
                      'Nenhuma corrida presa há mais de $_minutes min. 👍',
                      textAlign: TextAlign.center,
                      style:
                          const TextStyle(color: AppColors.textSecondary),
                    ),
                  ),
                ],
              );
            }
            return ListView.builder(
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 24),
              itemCount: rows.length,
              itemBuilder: (_, i) => _StuckCard(
                data: rows[i],
                busy: _busyRideId == rows[i]['id'].toString(),
                anyBusy: _busyRideId != null,
                onReconferir: () => _reconferir(rows[i]),
                onCancelar: () => _cancelar(rows[i]),
                onReembolsar: () => _reembolsar(rows[i]),
              ),
            );
          },
        ),
      ),
    );
  }
}

class _StuckCard extends StatelessWidget {
  const _StuckCard({
    required this.data,
    required this.busy,
    required this.anyBusy,
    required this.onReconferir,
    required this.onCancelar,
    required this.onReembolsar,
  });

  final Map<String, dynamic> data;
  final bool busy;
  final bool anyBusy;
  final VoidCallback onReconferir;
  final VoidCallback onCancelar;
  final VoidCallback onReembolsar;

  @override
  Widget build(BuildContext context) {
    final minutes = (data['minutes_stuck'] as num?)?.toInt() ?? 0;
    final fare = (data['est_fare_cents'] as num?)?.toInt() ?? 0;
    final payStatus = (data['payment_status'] as String?) ?? '—';
    final method = (data['payment_method'] as String?) ?? '—';
    final tokens = (data['tokens_applied_count'] as num?)?.toInt() ?? 0;
    final tokensCents =
        (data['tokens_applied_value_cents'] as num?)?.toInt() ?? 0;
    final tokensConsumed = data['tokens_consumed_at'] != null;

    final (label, color) = switch (payStatus) {
      'requires_action' => ('Esperando o cliente confirmar', AppColors.accent),
      'processing' => ('Liquidando no banco', AppColors.accent),
      'requires_payment_method' => ('Pagamento falhou', AppColors.error),
      'requires_confirmation' => ('Por confirmar', AppColors.accent),
      _ => (payStatus, AppColors.textSubtle),
    };

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
                  child: Text('€${(fare / 100).toStringAsFixed(2)}  ·  $method',
                      style: const TextStyle(
                          fontWeight: FontWeight.w800, fontSize: 17)),
                ),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(label,
                      style: TextStyle(
                          color: color,
                          fontSize: 11,
                          fontWeight: FontWeight.w600)),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text('Presa há $minutes min',
                style: const TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w700,
                    color: AppColors.error)),
            const SizedBox(height: 8),
            _line('Cliente', (data['client_email'] as String?) ?? '—'),
            _line('Trajeto',
                '${data['origin_label'] ?? '—'} → ${data['dest_label'] ?? '—'}'),
            _line('Pedida em', _fmtDateTime(data['created_at'])),
            _line('PaymentIntent', (data['payment_intent_id'] as String?) ?? '—'),
            // Coluna de tokens — pedido explícito do Danilo. `descontados`
            // distingue "desconto dado" de "saldo do cliente já baixou".
            _line(
              'Bora Tokens',
              tokens <= 0
                  ? 'nenhum'
                  : '$tokens tokens · −€${(tokensCents / 100).toStringAsFixed(2)}'
                      ' · ${tokensConsumed ? 'descontados' : 'ainda NÃO descontados'}',
            ),
            const SizedBox(height: 10),
            if (busy)
              const Center(
                child: Padding(
                  padding: EdgeInsets.symmetric(vertical: 6),
                  child: SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2)),
                ),
              )
            else
              Wrap(
                spacing: 8,
                runSpacing: 4,
                children: [
                  TextButton.icon(
                    onPressed: anyBusy ? null : onReconferir,
                    icon: const Icon(Icons.sync, size: 18),
                    label: const Text('Reconferir na Stripe'),
                  ),
                  TextButton.icon(
                    onPressed: anyBusy ? null : onReembolsar,
                    icon: const Icon(Icons.undo, size: 18),
                    label: const Text('Reembolsar'),
                  ),
                  TextButton.icon(
                    onPressed: anyBusy ? null : onCancelar,
                    icon: const Icon(Icons.close, size: 18),
                    label: const Text('Cancelar'),
                    style: TextButton.styleFrom(
                        foregroundColor: AppColors.error),
                  ),
                ],
              ),
          ],
        ),
      ),
    );
  }

  Widget _line(String label, String value) => Padding(
        padding: const EdgeInsets.only(bottom: 2),
        child: Text('$label: $value',
            style: const TextStyle(
                fontSize: 12, color: AppColors.textSecondary)),
      );
}

String _fmtDateTime(dynamic iso) {
  if (iso == null) return '—';
  final d = DateTime.tryParse(iso.toString());
  if (d == null) return iso.toString();
  final l = d.toLocal();
  String two(int n) => n.toString().padLeft(2, '0');
  return '${two(l.day)}/${two(l.month)}/${l.year} ${two(l.hour)}:${two(l.minute)}';
}
