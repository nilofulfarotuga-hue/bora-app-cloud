import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../config/app_colors.dart';
import '../../config/app_spacing.dart';
import '../../widgets/bora/bora_screen_app_bar.dart';

/// Bora Motorista (TVDE) — Histórico de cancelamentos (PT-BR).
///
/// Espelha o histórico de cancelamentos do DELIVERY
/// (`admin_cancellations_screen.dart`), mas para corridas de passageiros.
///
/// IMPORTANTE (dinheiro): corridas TVDE são `payment_method='cash'` → NÃO houve
/// pré-pagamento → NÃO há reembolso. Por isso, onde o ecrã de delivery mostra
/// método/estado de reembolso, aqui mostramos sempre "Dinheiro — sem reembolso".
///
/// Lê a RPC `admin_tvde_cancellations(p_limit)` (read-only, aditiva). Construído
/// defensivamente: se a migration ainda não foi aplicada e a RPC não existir em
/// runtime, o FutureBuilder trata o erro e mostra um aviso amigável — nunca
/// tela branca nem crash.
class AdminTvdeCancellationsScreen extends StatefulWidget {
  const AdminTvdeCancellationsScreen({super.key});

  @override
  State<AdminTvdeCancellationsScreen> createState() =>
      _AdminTvdeCancellationsScreenState();
}

class _AdminTvdeCancellationsScreenState
    extends State<AdminTvdeCancellationsScreen> {
  late Future<List<Map<String, dynamic>>> _future;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<List<Map<String, dynamic>>> _load() async {
    final res = await Supabase.instance.client
        .rpc('admin_tvde_cancellations', params: {'p_limit': 100});
    final list = (res as List?) ?? const [];
    return list
        .whereType<Map>()
        .map((e) => Map<String, dynamic>.from(e))
        .toList();
  }

  Future<void> _refresh() async {
    setState(() => _future = _load());
    await _future.catchError((_) => <Map<String, dynamic>>[]);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: const BoraScreenAppBar(title: 'Cancelamentos — Bora Motorista'),
      body: RefreshIndicator(
        onRefresh: _refresh,
        child: FutureBuilder<List<Map<String, dynamic>>>(
          future: _future,
          builder: (ctx, snap) {
            if (snap.connectionState != ConnectionState.done) {
              return const Center(child: CircularProgressIndicator());
            }
            if (snap.hasError) {
              return _errorView('${snap.error}');
            }
            final rows = snap.data ?? const [];
            if (rows.isEmpty) {
              return ListView(
                children: const [
                  SizedBox(height: 90),
                  Icon(Icons.check_circle_outline,
                      size: 44, color: AppColors.primary),
                  SizedBox(height: 12),
                  Center(child: Text('Sem cancelamentos de corridas.')),
                ],
              );
            }
            return ListView(
              padding: const EdgeInsets.all(12),
              children: [
                _headerNote(rows.length),
                const SizedBox(height: 10),
                ...rows.map((r) => _CancelCard(data: r)),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _headerNote(int count) {
    return Card(
      elevation: 0,
      color: AppColors.primary.withValues(alpha: 0.08),
      shape:
          RoundedRectangleBorder(borderRadius: BorderRadius.circular(Radii.lg)),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          children: [
            const Icon(Icons.info_outline, color: AppColors.primary, size: 20),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                '$count cancelamento(s) · corridas em dinheiro '
                '(sem pré-pagamento, logo sem reembolso).',
                style: const TextStyle(
                    fontSize: 12.5, fontWeight: FontWeight.w600),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Fallback amigável — cobre também o caso da RPC ainda não existir em runtime
  /// (migration nova ainda por aplicar). Nunca crasha; oferece "Tentar de novo".
  Widget _errorView(String error) {
    final missingRpc = error.contains('admin_tvde_cancellations') ||
        error.contains('PGRST202') ||
        error.contains('42883') ||
        error.contains('Could not find the function') ||
        error.contains('does not exist');
    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        const SizedBox(height: 60),
        Icon(missingRpc ? Icons.hourglass_empty : Icons.error_outline,
            size: 44,
            color: missingRpc ? AppColors.warning : AppColors.error),
        const SizedBox(height: 12),
        Text(
          missingRpc
              ? 'Histórico ainda não disponível.\n'
                  'A base de dados desta funcionalidade ainda não foi aplicada '
                  '(migration pendente). Assim que for aplicada, os '
                  'cancelamentos aparecem aqui.'
              : 'Erro ao carregar:\n$error',
          textAlign: TextAlign.center,
          style: const TextStyle(color: AppColors.textSecondary),
        ),
        const SizedBox(height: 16),
        Center(
          child: FilledButton.icon(
            onPressed: _refresh,
            icon: const Icon(Icons.refresh),
            label: const Text('Tentar de novo'),
          ),
        ),
      ],
    );
  }
}

class _CancelCard extends StatelessWidget {
  const _CancelCard({required this.data});
  final Map<String, dynamic> data;

  @override
  Widget build(BuildContext context) {
    final status = data['status'] as String?;
    final (statusLabel, statusColor) = _statusStyle(status);
    final reason = (data['cancel_reason'] as String?)?.trim();
    final feeCents = (data['cancel_fee_cents'] as num?)?.toInt() ?? 0;
    final fareCents = (data['est_fare_cents'] as num?)?.toInt() ?? 0;
    final elapsed = _elapsed(data['created_at'], data['updated_at']);

    return Card(
      elevation: 2,
      margin: const EdgeInsets.only(bottom: 10),
      shape:
          RoundedRectangleBorder(borderRadius: BorderRadius.circular(Radii.lg)),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Estado + taxa cobrada
            Row(
              children: [
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: statusColor.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(statusLabel,
                      style: TextStyle(
                          color: statusColor,
                          fontSize: 11,
                          fontWeight: FontWeight.w600)),
                ),
                const Spacer(),
                Text(
                  feeCents > 0 ? 'Taxa ${_eur(feeCents)}' : 'Grátis',
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 14,
                    color:
                        feeCents > 0 ? AppColors.textPrimary : AppColors.primary,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            // Motivo
            if (reason != null && reason.isNotEmpty)
              _kv(Icons.chat_bubble_outline, 'Motivo', reason),
            // Valor da corrida
            _kv(Icons.route, 'Valor da corrida', _eur(fareCents)),
            // Tempo até cancelar (janela de graça = 180s)
            if (elapsed != null)
              _kv(
                elapsed.withinGrace
                    ? Icons.verified_outlined
                    : Icons.timer_outlined,
                'Tempo até cancelar',
                'cancelada ${elapsed.label} após o pedido'
                    '${elapsed.withinGrace ? ' · dentro da janela de cortesia (180s)' : ''}',
                valueColor:
                    elapsed.withinGrace ? AppColors.primary : null,
              ),
            // Reembolso (sempre dinheiro, sem reembolso)
            _kv(Icons.payments_outlined, 'Reembolso',
                'Dinheiro — sem reembolso'),
            const SizedBox(height: 6),
            Text(_fmtDateTime(data['created_at']),
                style: const TextStyle(
                    fontSize: 11, color: AppColors.textSubtle)),
          ],
        ),
      ),
    );
  }

  Widget _kv(IconData icon, String key, String value, {Color? valueColor}) {
    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 15, color: AppColors.textSubtle),
          const SizedBox(width: 6),
          Text('$key: ',
              style:
                  const TextStyle(fontSize: 12.5, color: AppColors.textSubtle)),
          Expanded(
            child: Text(
              value,
              style: TextStyle(
                fontSize: 12.5,
                color: valueColor ?? AppColors.textPrimary,
                fontWeight:
                    valueColor != null ? FontWeight.w600 : FontWeight.w400,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Helpers ──

(String, Color) _statusStyle(String? s) => switch (s) {
      'cancelada_cliente' =>
        ('Cancelada pelo cliente', AppColors.error),
      'cancelada_motorista' =>
        ('Cancelada pelo motorista', AppColors.error),
      'no_show' => ('Não compareceu (no-show)', Colors.deepOrange),
      _ => (s ?? '—', AppColors.textSecondary),
    };

String _eur(int cents) => '€${(cents / 100).toStringAsFixed(2)}';

/// Diferença entre `updated_at` (momento do cancelamento) e `created_at`
/// (momento do pedido). `withinGrace` = dentro dos 180s da janela de cortesia.
({String label, bool withinGrace})? _elapsed(dynamic created, dynamic updated) {
  final c = DateTime.tryParse('${created ?? ''}');
  final u = DateTime.tryParse('${updated ?? ''}');
  if (c == null || u == null) return null;
  var secs = u.difference(c).inSeconds;
  if (secs < 0) secs = 0;
  final withinGrace = secs <= 180;
  String label;
  if (secs < 60) {
    label = '$secs s';
  } else if (secs < 3600) {
    label = '${secs ~/ 60} min';
  } else {
    final h = secs ~/ 3600;
    final m = (secs % 3600) ~/ 60;
    label = m > 0 ? '$h h $m min' : '$h h';
  }
  return (label: label, withinGrace: withinGrace);
}

String _fmtDateTime(dynamic iso) {
  if (iso == null) return '—';
  final d = DateTime.tryParse(iso.toString());
  if (d == null) return iso.toString();
  final l = d.toLocal();
  String two(int n) => n.toString().padLeft(2, '0');
  return '${two(l.day)}/${two(l.month)} ${two(l.hour)}:${two(l.minute)}';
}
