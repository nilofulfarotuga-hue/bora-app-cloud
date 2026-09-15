// BLOCO D5 (2026-09-04) — quadro "Marcações presas".
//
// Lê `admin_stuck_reservations(p_minutes)`: reservas em pending/pending_payment
// há mais de N minutos (migration 20260904230000). O botão "Libertar" chama
// `admin_release_stuck_reservation`, que só muda o status para
// `cancelled_by_admin` quando NÃO há nenhum PaymentIntent associado
// (prepayment_pi IS NULL) — ou seja, nunca há dinheiro em jogo. Se a reserva
// já tiver um pagamento associado, a RPC recusa (`requires_refund_manual_review`)
// e este ecrã mostra "CONFIRMAÇÃO NECESSÁRIA" em vez de decidir sozinho —
// isso é Lista Vermelha (reembolso) e fica para revisão humana manual.
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../config/app_colors.dart';
import '../../config/app_spacing.dart';
import '../../widgets/bora/bora_screen_app_bar.dart';

class AdminStuckReservationsScreen extends StatefulWidget {
  const AdminStuckReservationsScreen({super.key});

  @override
  State<AdminStuckReservationsScreen> createState() =>
      _AdminStuckReservationsScreenState();
}

class _AdminStuckReservationsScreenState
    extends State<AdminStuckReservationsScreen> {
  int _minutes = 60;
  late Future<List<Map<String, dynamic>>> _future;
  String? _busyId;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<List<Map<String, dynamic>>> _load() async {
    final res = await Supabase.instance.client
        .rpc('admin_stuck_reservations', params: {'p_minutes': _minutes});
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

  Future<void> _confirmacaoNecessaria(String piId) => showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('⚠️ Confirmação necessária'),
          content: Text(
            'Esta reserva tem um pagamento associado (PaymentIntent $piId). '
            'Não é seguro libertar automaticamente — pode já ter sido cobrado '
            'ao cliente. Confirme na Stripe se foi mesmo cobrado e, se sim, '
            'trate o reembolso manualmente antes de cancelar (isto é dinheiro '
            'real — a Trava não deixa o robô decidir sozinho aqui).',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Entendi'),
            ),
          ],
        ),
      );

  Future<void> _libertar(Map<String, dynamic> row) async {
    final id = row['id'].toString();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Libertar reserva presa?'),
        content: const Text(
          'A reserva passa a `cancelled_by_admin`. Isto NÃO reembolsa nem '
          'cobra nada — só é permitido quando a reserva não tem nenhum '
          'pagamento associado.',
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Voltar')),
          TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Libertar')),
        ],
      ),
    );
    if (ok != true) return;

    setState(() => _busyId = id);
    try {
      await Supabase.instance.client.rpc(
        'admin_release_stuck_reservation',
        params: {
          'p_reservation_id': id,
          'p_reason': 'Libertada via quadro de marcações presas (admin)',
        },
      );
      _toast('Reserva libertada.');
    } on PostgrestException catch (e) {
      if (e.message.startsWith('requires_refund_manual_review')) {
        final pi = (row['prepayment_pi'] as String?) ?? '—';
        if (mounted) await _confirmacaoNecessaria(pi);
      } else {
        _toast('Erro: ${e.message}', erro: true);
      }
    } catch (e) {
      _toast('Erro: $e', erro: true);
    } finally {
      if (mounted) setState(() => _busyId = null);
      await _refresh();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: BoraScreenAppBar(
        title: 'Marcações presas',
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
              PopupMenuItem(value: 15, child: Text('Presas há +15 min')),
              PopupMenuItem(value: 60, child: Text('Presas há +1 h')),
              PopupMenuItem(value: 360, child: Text('Presas há +6 h')),
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
                  Text('Erro: ${snap.error}', textAlign: TextAlign.center),
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
                      'Nenhuma marcação presa há mais de $_minutes min. 👍',
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
              itemBuilder: (_, i) => _StuckReservationCard(
                data: rows[i],
                busy: _busyId == rows[i]['id'].toString(),
                anyBusy: _busyId != null,
                onLibertar: () => _libertar(rows[i]),
              ),
            );
          },
        ),
      ),
    );
  }
}

class _StuckReservationCard extends StatelessWidget {
  const _StuckReservationCard({
    required this.data,
    required this.busy,
    required this.anyBusy,
    required this.onLibertar,
  });

  final Map<String, dynamic> data;
  final bool busy;
  final bool anyBusy;
  final VoidCallback onLibertar;

  @override
  Widget build(BuildContext context) {
    final minutes = (data['minutes_stuck'] as num?)?.toInt() ?? 0;
    final people = (data['people'] as num?)?.toInt() ?? 0;
    final status = (data['status'] as String?) ?? '—';
    final restaurantName = (data['restaurant_name'] as String?) ??
        (data['restaurant_id'] as String?) ??
        '—';
    final hasPayment = data['prepayment_pi'] != null;
    final prepaymentCents = (data['prepayment_cents'] as num?)?.toInt() ?? 0;

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
                  child: Text('$restaurantName · $people pessoas',
                      style: const TextStyle(
                          fontWeight: FontWeight.w800, fontSize: 15)),
                ),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: AppColors.accent.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(status,
                      style: const TextStyle(
                          color: AppColors.accent,
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
            _line('Cliente', (data['client_name'] as String?) ?? '—'),
            _line('Telefone', (data['client_phone'] as String?) ?? '—'),
            _line('Para quando', _fmtDateTime(data['reserved_for'])),
            _line('Criada em', _fmtDateTime(data['created_at'])),
            _line(
              'Pagamento',
              hasPayment
                  ? '€${(prepaymentCents / 100).toStringAsFixed(2)} associado — precisa revisão manual'
                  : 'nenhum — seguro libertar',
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
              Align(
                alignment: Alignment.centerRight,
                child: TextButton.icon(
                  onPressed: anyBusy ? null : onLibertar,
                  icon: Icon(hasPayment ? Icons.warning_amber : Icons.lock_open,
                      size: 18),
                  label: Text(hasPayment ? 'Ver aviso' : 'Libertar'),
                  style: TextButton.styleFrom(
                      foregroundColor:
                          hasPayment ? AppColors.error : AppColors.primary),
                ),
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
