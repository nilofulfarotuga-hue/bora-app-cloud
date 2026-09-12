import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../config/app_colors.dart';
import '../../../models/notify_entry.dart';
import '../../../models/waitlist_entry.dart';
import '../../../stores/reservation_store.dart';

import '../../../l10n/tr.dart';

/// Reservas PRO F3.C — listagem das entries do cliente em
/// fila de espera + lista "avisar se vagar".
///
/// 2 tabs com FutureBuilder (late Future em initState para evitar
/// re-fetch em cada rebuild).
class MyReservationListsScreen extends StatefulWidget {
  const MyReservationListsScreen({super.key});

  @override
  State<MyReservationListsScreen> createState() =>
      _MyReservationListsScreenState();
}

class _MyReservationListsScreenState extends State<MyReservationListsScreen> {
  late Future<List<WaitlistEntry>> _waitlistFuture;
  late Future<List<NotifyEntry>> _notifyFuture;

  @override
  void initState() {
    super.initState();
    final store = context.read<ReservationStore>();
    // 2026-05-14 — H1 fix: garantir stream realtime ligado (idempotente).
    store.subscribeMyReservations();
    _waitlistFuture = store.fetchMyWaitlist();
    _notifyFuture = store.fetchMyNotify();
  }

  void _refreshAll() {
    final store = context.read<ReservationStore>();
    setState(() {
      _waitlistFuture = store.fetchMyWaitlist();
      _notifyFuture = store.fetchMyNotify();
    });
  }

  Future<void> _onLeaveWaitlist(String id) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Sair da fila?'.tr),
        content: Text('Vais perder a tua posição actual.'.tr),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text('Não'.tr),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text('Sair'.tr),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    try {
      await context.read<ReservationStore>().leaveWaitlist(id);
      if (!mounted) return;
      _refreshAll();
      messenger.showSnackBar(
        SnackBar(content: Text('Saíste da fila.'.tr)),
      );
    } catch (e) {
      if (!mounted) return;
      messenger.showSnackBar(
        SnackBar(
          content: Text(e.toString().replaceFirst('Exception: ', '')),
        ),
      );
    }
  }

  Future<void> _onLeaveNotify(String id) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Cancelar aviso?'.tr),
        content: Text('Não vais receber notificação se vagar.'.tr),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text('Não'.tr),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text('Cancelar aviso'.tr),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    try {
      await context.read<ReservationStore>().leaveNotify(id);
      if (!mounted) return;
      _refreshAll();
      messenger.showSnackBar(
        SnackBar(content: Text('Aviso cancelado.'.tr)),
      );
    } catch (e) {
      if (!mounted) return;
      messenger.showSnackBar(
        SnackBar(
          content: Text(e.toString().replaceFirst('Exception: ', '')),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        backgroundColor: AppColors.background,
        appBar: AppBar(
          backgroundColor: AppColors.primary,
          elevation: 0,
          foregroundColor: Colors.white,
          iconTheme: const IconThemeData(color: Colors.white),
          flexibleSpace: const DecoratedBox(
            decoration: BoxDecoration(gradient: AppColors.headerGradient),
          ),
          title: Text(
            'Minhas Listas'.tr,
            style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
          ),
          bottom: TabBar(
            labelColor: Colors.white,
            unselectedLabelColor: Colors.white70,
            indicatorColor: Colors.white,
            tabs: [
              Tab(text: 'Fila de espera'.tr),
              Tab(text: 'Avisar se vagar'.tr),
            ],
          ),
        ),
        body: TabBarView(
          children: [
            _buildWaitlistTab(),
            _buildNotifyTab(),
          ],
        ),
      ),
    );
  }

  Widget _buildWaitlistTab() {
    return FutureBuilder<List<WaitlistEntry>>(
      future: _waitlistFuture,
      builder: (context, snap) {
        if (snap.connectionState != ConnectionState.done) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snap.hasError) {
          return _buildError(snap.error);
        }
        final list = snap.data ?? const [];
        if (list.isEmpty) {
          return _emptyState(
            'Sem entradas na fila'.tr,
            'Procura uma mesa noutro restaurante.'.tr,
          );
        }
        return RefreshIndicator(
          onRefresh: () async => _refreshAll(),
          child: ListView.builder(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.symmetric(vertical: 8),
            itemCount: list.length,
            itemBuilder: (_, i) => _waitlistCard(list[i]),
          ),
        );
      },
    );
  }

  Widget _buildNotifyTab() {
    return FutureBuilder<List<NotifyEntry>>(
      future: _notifyFuture,
      builder: (context, snap) {
        if (snap.connectionState != ConnectionState.done) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snap.hasError) {
          return _buildError(snap.error);
        }
        final list = snap.data ?? const [];
        if (list.isEmpty) {
          return _emptyState(
            'Sem avisos activos'.tr,
            'Activa um aviso quando não houver mesa.'.tr,
          );
        }
        return RefreshIndicator(
          onRefresh: () async => _refreshAll(),
          child: ListView.builder(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.symmetric(vertical: 8),
            itemCount: list.length,
            itemBuilder: (_, i) => _notifyCard(list[i]),
          ),
        );
      },
    );
  }

  Widget _buildError(Object? err) {
    final msg = err.toString().replaceFirst('Exception: ', '');
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline, size: 48, color: Colors.red),
            const SizedBox(height: 12),
            Text(msg, textAlign: TextAlign.center),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: _refreshAll,
              child: Text('Tentar de novo'.tr),
            ),
          ],
        ),
      ),
    );
  }

  Widget _waitlistCard(WaitlistEntry e) {
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _Thumb(photoUrl: e.restaurantPhotoUrl),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        e.restaurantName ?? 'Restaurante',
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                          color: AppColors.textPrimary,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        _formatDatePt(e.targetDate),
                        style: const TextStyle(
                          fontSize: 13,
                          color: AppColors.textSecondary,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        _waitlistTimeLabel(e),
                        style: const TextStyle(
                          fontSize: 13,
                          color: AppColors.textSecondary,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        e.people == 1 ? '1 pessoa' : '${e.people} pessoas',
                        style: const TextStyle(
                          fontSize: 13,
                          color: AppColors.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
                _waitlistBadge(e),
              ],
            ),
            if (e.notes != null && e.notes!.isNotEmpty) ...[
              const SizedBox(height: 8),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                decoration: BoxDecoration(
                  color: AppColors.surface,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  'Notas: {0}'.trArgs([e.notes]),
                  style: const TextStyle(
                    fontSize: 12,
                    color: AppColors.textSecondary,
                  ),
                ),
              ),
            ],
            if (e.isActive) ...[
              const SizedBox(height: 10),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: () => _onLeaveWaitlist(e.id),
                  icon: const Icon(Icons.exit_to_app, color: Colors.red),
                  label: Text(
                    'Sair da fila'.tr,
                    style: const TextStyle(color: Colors.red),
                  ),
                  style: OutlinedButton.styleFrom(
                    side: const BorderSide(color: Colors.red),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  String _waitlistTimeLabel(WaitlistEntry e) {
    final start = e.targetTimeStart;
    final end = e.targetTimeEnd;
    if (start == null && end == null) return 'Dia todo'.tr;
    final s = start != null ? start.substring(0, 5) : '—';
    final ed = end != null ? end.substring(0, 5) : '—';
    return '$s – $ed';
  }

  Widget _waitlistBadge(WaitlistEntry e) {
    String label;
    Color color;
    switch (e.status) {
      case 'waiting':
        label = e.position != null ? 'Em espera #${e.position}' : 'Em espera';
        color = AppColors.primary;
        break;
      case 'notified':
        label = 'Mesa pronta!'.tr;
        color = AppColors.accent;
        break;
      case 'seated':
        label = 'Sentado'.tr;
        color = Colors.grey;
        break;
      case 'cancelled_refund_pending':
        label = 'Cancelado (reembolso a processar)'.tr;
        color = Colors.orange;
        break;
      case 'cancelled':
        label = 'Cancelado'.tr;
        color = Colors.grey;
        break;
      case 'expired':
        label = 'Expirado'.tr;
        color = Colors.grey;
        break;
      default:
        label = e.status;
        color = Colors.grey;
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          color: color,
        ),
      ),
    );
  }

  Widget _notifyCard(NotifyEntry e) {
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _Thumb(photoUrl: e.restaurantPhotoUrl),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        e.restaurantName ?? 'Restaurante',
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                          color: AppColors.textPrimary,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '${_formatDatePt(e.targetDate)} • ${e.targetTime.substring(0, 5)}',
                        style: const TextStyle(
                          fontSize: 13,
                          color: AppColors.textSecondary,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'Flexibilidade: {0} min'.trArgs([e.flexibilityMinutes]),
                        style: const TextStyle(
                          fontSize: 13,
                          color: AppColors.textSecondary,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        e.people == 1 ? '1 pessoa' : '${e.people} pessoas',
                        style: const TextStyle(
                          fontSize: 13,
                          color: AppColors.textSecondary,
                        ),
                      ),
                      if (e.isActive) ...[
                        const SizedBox(height: 4),
                        Text(
                          _expiryLabel(e.expiresAt),
                          style: const TextStyle(
                            fontSize: 12,
                            color: AppColors.textSecondary,
                            fontStyle: FontStyle.italic,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                _notifyBadge(e),
              ],
            ),
            if (e.isActive) ...[
              const SizedBox(height: 10),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: () => _onLeaveNotify(e.id),
                  icon: const Icon(Icons.cancel_outlined, color: Colors.red),
                  label: Text(
                    'Cancelar aviso'.tr,
                    style: const TextStyle(color: Colors.red),
                  ),
                  style: OutlinedButton.styleFrom(
                    side: const BorderSide(color: Colors.red),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  String _expiryLabel(DateTime expiresAt) {
    final left = expiresAt.difference(DateTime.now());
    if (left.isNegative) return 'Expirado'.tr;
    if (left.inHours > 0) {
      return 'Expira em {0}h {1}m'.trArgs([left.inHours, left.inMinutes.remainder(60)]);
    }
    if (left.inMinutes > 0) {
      return 'Expira em {0}m'.trArgs([left.inMinutes]);
    }
    return 'A expirar'.tr;
  }

  Widget _notifyBadge(NotifyEntry e) {
    String label;
    Color color;
    switch (e.status) {
      case 'active':
        label = 'Activo'.tr;
        color = AppColors.primary;
        break;
      case 'notified':
        label = 'Mesa vagou!'.tr;
        color = AppColors.accent;
        break;
      case 'converted':
        label = 'Convertido'.tr;
        color = Colors.blue;
        break;
      case 'expired':
        label = 'Expirado'.tr;
        color = Colors.grey;
        break;
      case 'cancelled_refund_pending':
        label = 'Cancelado (reembolso a processar)'.tr;
        color = Colors.orange;
        break;
      case 'cancelled':
        label = 'Cancelado'.tr;
        color = Colors.grey;
        break;
      default:
        label = e.status;
        color = Colors.grey;
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          color: color,
        ),
      ),
    );
  }

  Widget _emptyState(String title, String subtitle) {
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      children: [
        const SizedBox(height: 80),
        const Icon(Icons.inbox_outlined, size: 64, color: Colors.grey),
        const SizedBox(height: 16),
        Center(
          child: Text(
            title,
            style: const TextStyle(
              fontSize: 17,
              fontWeight: FontWeight.w700,
              color: AppColors.textPrimary,
            ),
          ),
        ),
        const SizedBox(height: 6),
        Center(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 32),
            child: Text(
              subtitle,
              textAlign: TextAlign.center,
              style: const TextStyle(color: AppColors.textSecondary),
            ),
          ),
        ),
        const SizedBox(height: 20),
        Center(
          child: FilledButton.icon(
            onPressed: () => Navigator.pop(context),
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.primary,
              foregroundColor: Colors.white,
            ),
            icon: const Icon(Icons.search),
            label: Text('Procurar mesa'.tr),
          ),
        ),
      ],
    );
  }

  static String _formatDatePt(DateTime d) {
    const weekdays = [
      'Seg',
      'Ter',
      'Qua',
      'Qui',
      'Sex',
      'Sáb',
      'Dom',
    ];
    const months = [
      'jan',
      'fev',
      'mar',
      'abr',
      'mai',
      'jun',
      'jul',
      'ago',
      'set',
      'out',
      'nov',
      'dez',
    ];
    final wd = weekdays[(d.weekday - 1).clamp(0, 6)];
    final mo = months[(d.month - 1).clamp(0, 11)];
    return '$wd, ${d.day} $mo';
  }
}

class _Thumb extends StatelessWidget {
  const _Thumb({required this.photoUrl});
  final String? photoUrl;

  @override
  Widget build(BuildContext context) {
    final hasPhoto = photoUrl != null && photoUrl!.isNotEmpty;
    return ClipRRect(
      borderRadius: BorderRadius.circular(10),
      child: SizedBox(
        width: 56,
        height: 56,
        child: hasPhoto
            ? Image.network(
                photoUrl!,
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => const _ThumbFallback(),
                loadingBuilder: (_, child, prog) =>
                    prog == null ? child : const _ThumbFallback(),
              )
            : const _ThumbFallback(),
      ),
    );
  }
}

class _ThumbFallback extends StatelessWidget {
  const _ThumbFallback();

  @override
  Widget build(BuildContext context) {
    return Container(
      color: AppColors.surface,
      alignment: Alignment.center,
      child: const Icon(
        Icons.restaurant_outlined,
        color: AppColors.primary,
        size: 28,
      ),
    );
  }
}
