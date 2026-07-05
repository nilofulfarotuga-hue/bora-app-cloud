import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../config/app_colors.dart';
import '../../../config/app_spacing.dart';
import '../../../models/cleaning_models.dart';
import '../../../stores/cleaning_store.dart';
import '../../../widgets/bora/bora.dart';

/// LIMPEZA — acompanhamento da reserva (realtime via CleaningStore.trackBooking).
/// Timeline de estados + detalhes + ações do cliente (cancelar / confirmar /
/// avaliar). As transições são todas RPCs; aqui só se reage.
class CleaningTrackingScreen extends StatefulWidget {
  const CleaningTrackingScreen({super.key, required this.booking});

  final CleaningBooking booking;

  @override
  State<CleaningTrackingScreen> createState() => _CleaningTrackingScreenState();
}

class _CleaningTrackingScreenState extends State<CleaningTrackingScreen> {
  Map<String, dynamic>? _cleanerProfile;
  int _cancelFreeHours = 24;
  int _cancelHalfHours = 2;
  bool _rated = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      final store = context.read<CleaningStore>();
      store.trackBooking(widget.booking);
      final free = await store.getSettingInt('cleaning_cancel_free_hours', 24);
      final half = await store.getSettingInt('cleaning_cancel_half_hours', 2);
      if (!mounted) return;
      setState(() {
        _cancelFreeHours = free;
        _cancelHalfHours = half;
      });
      _loadCleanerProfile();
    });
  }

  @override
  void dispose() {
    // Não usar context aqui — o store sobrevive ao ecrã; limpar só o canal
    // é seguro via clearTracked chamado pelo próximo trackBooking.
    super.dispose();
  }

  CleaningBooking get _booking =>
      context.watch<CleaningStore>().tracked ?? widget.booking;

  /// Perfil público da profissional atribuída (RPC própria — RLS não expõe
  /// a tabela cleaners a clientes).
  Future<void> _loadCleanerProfile() async {
    final b = context.read<CleaningStore>().tracked ?? widget.booking;
    if (b.cleanerId == null) return;
    try {
      final res = await Supabase.instance.client.rpc(
        'cleaning_booking_cleaner_public',
        params: {'p_booking_id': b.id},
      );
      if (!mounted || res == null) return;
      setState(() => _cleanerProfile = Map<String, dynamic>.from(res as Map));
    } catch (e) {
      debugPrint('cleaning_booking_cleaner_public error => $e');
    }
  }

  // ── ações ────────────────────────────────────────────────────────────────

  /// Pré-visualização da taxa de cancelamento (janelas do backend; o valor
  /// final é SEMPRE decidido server-side).
  String _cancelFeePreview(CleaningBooking b) {
    final hours =
        b.scheduledAt.difference(DateTime.now()).inMinutes / 60.0;
    if (hours >= _cancelFreeHours) return 'Cancelamento grátis.';
    if (hours >= _cancelHalfHours) {
      return 'Taxa de 50% (${CleaningLabels.euro((b.totalCents * 0.5).round())}).';
    }
    return 'Taxa de 100% (${CleaningLabels.euro(b.totalCents)}).';
  }

  Future<void> _cancel() async {
    final b = _booking;
    final store = context.read<CleaningStore>();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Cancelar limpeza?'),
        content: Text(_cancelFeePreview(b)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Manter'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Cancelar limpeza',
                style: TextStyle(color: AppColors.error)),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    try {
      await store.cancelBooking(b.id);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Limpeza cancelada.')),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Não foi possível cancelar.')),
      );
    }
  }

  Future<void> _cancelSeries() async {
    final b = _booking;
    final groupId = b.recurrenceGroupId;
    if (groupId == null) return;
    final store = context.read<CleaningStore>();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Parar a recorrência?'),
        content: const Text(
            'As próximas limpezas desta série deixam de ser agendadas. '
            'A limpeza atual mantém-se.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Manter'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Parar série',
                style: TextStyle(color: AppColors.error)),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    try {
      await store.cancelSeries(groupId);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Recorrência cancelada.')),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Não foi possível parar a série.')),
      );
    }
  }

  Future<void> _confirmDone() async {
    final store = context.read<CleaningStore>();
    try {
      await store.confirmCompleted(_booking.id);
      if (!mounted) return;
      await _askRating();
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Não foi possível confirmar.')),
      );
    }
  }

  Future<void> _askRating() async {
    if (_rated) return;
    final store = context.read<CleaningStore>();
    var stars = 5;
    final commentCtrl = TextEditingController();
    final submitted = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: const Text('Como correu a limpeza?'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  for (var i = 1; i <= 5; i++)
                    IconButton(
                      onPressed: () => setDialogState(() => stars = i),
                      icon: Icon(
                        i <= stars ? Icons.star : Icons.star_border,
                        color: AppColors.warning,
                        size: 30,
                      ),
                    ),
                ],
              ),
              TextField(
                controller: commentCtrl,
                maxLines: 2,
                decoration: const InputDecoration(
                    hintText: 'Comentário (opcional)'),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Agora não'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Enviar'),
            ),
          ],
        ),
      ),
    );
    if (submitted != true || !mounted) return;
    try {
      await store.rateCleaner(_booking.id, stars,
          comment: commentCtrl.text.trim());
      if (!mounted) return;
      setState(() => _rated = true);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Obrigado pela avaliação! 💚')),
      );
    } catch (e) {
      if (!mounted) return;
      final already = e.toString().contains('already_rated');
      if (already) setState(() => _rated = true);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text(already
                ? 'Já avaliaste esta limpeza.'
                : 'Não foi possível enviar a avaliação.')),
      );
    }
  }

  // ── UI ────────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final b = _booking;
    final store = context.watch<CleaningStore>();
    // Recarrega o perfil quando a profissional é atribuída via realtime.
    if (b.cleanerId != null && _cleanerProfile == null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _loadCleanerProfile();
      });
    }

    return Scaffold(
      appBar: BoraScreenAppBar(
        title: 'Limpeza · ${b.status.labelPt}',
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(Spacing.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (b.status.isCancelled)
              _CancelledBanner(booking: b)
            else
              _StatusTimeline(status: b.status),
            const SizedBox(height: Spacing.lg),
            if (b.cleanerId != null) ...[
              _CleanerCard(profile: _cleanerProfile),
              const SizedBox(height: Spacing.lg),
            ],
            _DetailsCard(booking: b),
            const SizedBox(height: Spacing.lg),
            if (b.status == CleaningStatus.done) ...[
              BoraPrimaryButton(
                label: 'Confirmar limpeza concluída',
                icon: Icons.check_circle,
                loading: store.busy,
                onPressed: _confirmDone,
              ),
              const SizedBox(height: Spacing.sm),
              const Text(
                'Confirma para libertar o pagamento à profissional. '
                'Sem confirmação, é confirmada automaticamente em 24 h.',
                textAlign: TextAlign.center,
                style: TextStyle(color: AppColors.textSubtle, fontSize: 12),
              ),
            ],
            if (b.status == CleaningStatus.completed && !_rated)
              BoraPrimaryButton(
                label: 'Avaliar a profissional',
                icon: Icons.star,
                onPressed: _askRating,
              ),
            if (const [
              CleaningStatus.scheduled,
              CleaningStatus.accepted,
              CleaningStatus.onTheWay,
            ].contains(b.status)) ...[
              const SizedBox(height: Spacing.sm),
              TextButton(
                onPressed: store.busy ? null : _cancel,
                child: const Text('Cancelar limpeza',
                    style: TextStyle(color: AppColors.error)),
              ),
            ],
            if (b.isRecurring && b.status.isActive)
              TextButton(
                onPressed: store.busy ? null : _cancelSeries,
                child: Text('Parar recorrência (${b.recurrenceLabel})',
                    style: const TextStyle(color: AppColors.textSecondary)),
              ),
          ],
        ),
      ),
    );
  }
}

// ─── widgets internos ────────────────────────────────────────────────────────

class _StatusTimeline extends StatelessWidget {
  const _StatusTimeline({required this.status});
  final CleaningStatus status;

  static const _steps = [
    (CleaningStatus.scheduled, 'Agendada', Icons.event_available),
    (CleaningStatus.accepted, 'Confirmada', Icons.how_to_reg),
    (CleaningStatus.onTheWay, 'A caminho', Icons.directions_walk),
    (CleaningStatus.inProgress, 'Em curso', Icons.cleaning_services),
    (CleaningStatus.completed, 'Concluída', Icons.check_circle),
  ];

  int get _currentIndex {
    switch (status) {
      case CleaningStatus.scheduled:
        return 0;
      case CleaningStatus.accepted:
        return 1;
      case CleaningStatus.onTheWay:
        return 2;
      case CleaningStatus.inProgress:
        return 3;
      case CleaningStatus.done:
      case CleaningStatus.completed:
        return 4;
      default:
        return 0;
    }
  }

  @override
  Widget build(BuildContext context) {
    final current = _currentIndex;
    return Container(
      padding: const EdgeInsets.all(Spacing.lg),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(Radii.lg),
        border: Border.all(color: AppColors.divider),
      ),
      child: Column(
        children: [
          for (var i = 0; i < _steps.length; i++)
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Column(
                  children: [
                    Icon(
                      _steps[i].$3,
                      size: 22,
                      color: i <= current
                          ? AppColors.primary
                          : AppColors.textSubtle,
                    ),
                    if (i < _steps.length - 1)
                      Container(
                        width: 2,
                        height: 22,
                        color: i < current
                            ? AppColors.primary
                            : AppColors.divider,
                      ),
                  ],
                ),
                const SizedBox(width: Spacing.md),
                Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Text(
                    _steps[i].$2,
                    style: TextStyle(
                      color: i <= current
                          ? AppColors.textPrimary
                          : AppColors.textSubtle,
                      fontWeight:
                          i == current ? FontWeight.w800 : FontWeight.w500,
                    ),
                  ),
                ),
              ],
            ),
        ],
      ),
    );
  }
}

class _CancelledBanner extends StatelessWidget {
  const _CancelledBanner({required this.booking});
  final CleaningBooking booking;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(Spacing.lg),
      decoration: BoxDecoration(
        color: AppColors.error.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(Radii.lg),
        border: Border.all(color: AppColors.error.withValues(alpha: 0.4)),
      ),
      child: Row(
        children: [
          const Icon(Icons.cancel, color: AppColors.error, size: 30),
          const SizedBox(width: Spacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(booking.status.labelPt,
                    style: const TextStyle(
                        fontWeight: FontWeight.w700,
                        color: AppColors.textPrimary)),
                if (booking.cancelFeeCents > 0)
                  Text(
                    'Taxa de cancelamento: '
                    '${CleaningLabels.euro(booking.cancelFeeCents)}',
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

class _CleanerCard extends StatelessWidget {
  const _CleanerCard({required this.profile});
  final Map<String, dynamic>? profile;

  @override
  Widget build(BuildContext context) {
    final p = profile;
    final name = p?['name'] as String? ?? 'A tua profissional';
    final photo = p?['photo_url'] as String? ?? '';
    final rating = (p?['rating_avg'] as num?)?.toDouble() ?? 0;
    final count = (p?['ratings_count'] as num?)?.toInt() ?? 0;

    return Container(
      padding: const EdgeInsets.all(Spacing.md),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(Radii.lg),
        border: Border.all(color: AppColors.divider),
      ),
      child: Row(
        children: [
          CircleAvatar(
            radius: 24,
            backgroundColor: AppColors.primaryWash,
            backgroundImage: photo.isNotEmpty ? NetworkImage(photo) : null,
            child: photo.isEmpty
                ? const Icon(Icons.person, color: AppColors.primary)
                : null,
          ),
          const SizedBox(width: Spacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(name,
                    style: const TextStyle(
                        fontWeight: FontWeight.w700,
                        color: AppColors.textPrimary)),
                if (count > 0)
                  Text('★ ${rating.toStringAsFixed(1)} ($count avaliações)',
                      style: const TextStyle(
                          color: AppColors.textSecondary, fontSize: 13)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _DetailsCard extends StatelessWidget {
  const _DetailsCard({required this.booking});
  final CleaningBooking booking;

  @override
  Widget build(BuildContext context) {
    final b = booking;
    return Container(
      padding: const EdgeInsets.all(Spacing.lg),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(Radii.lg),
        border: Border.all(color: AppColors.divider),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _row('Serviço', '${b.typeLabel} · ${b.sizeLabel}'),
          _row('Quando', _fmtDateTime(b.scheduledAt)),
          _row('Onde',
              '${b.addressStreet}, ${b.addressCity} ${b.addressPostal}'),
          _row('Produtos',
              b.productsBy == 'cleaner' ? 'A profissional traz' : 'Do cliente'),
          if (b.isRecurring) _row('Recorrência', b.recurrenceLabel),
          _row(
              'Pagamento',
              switch (b.paymentMethod) {
                'card' => 'Cartão',
                'mbway' => 'MB Way',
                _ => 'Dinheiro',
              }),
          if (b.notes.isNotEmpty) _row('Notas', b.notes),
          const Divider(height: Spacing.lg),
          _row('Base', CleaningLabels.euro(b.baseCents)),
          if (b.typeSurchargeCents > 0)
            _row('Suplemento', '+ ${CleaningLabels.euro(b.typeSurchargeCents)}'),
          if (b.recurringDiscountCents > 0)
            _row('Desconto',
                '- ${CleaningLabels.euro(b.recurringDiscountCents)}'),
          if (b.productsFeeCents > 0)
            _row('Produtos', '+ ${CleaningLabels.euro(b.productsFeeCents)}'),
          _row('Total', CleaningLabels.euro(b.totalCents), bold: true),
        ],
      ),
    );
  }

  Widget _row(String label, String value, {bool bold = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 110,
            child:
                Text(label, style: const TextStyle(color: AppColors.textSecondary)),
          ),
          Expanded(
            child: Text(
              value,
              style: TextStyle(
                color: AppColors.textPrimary,
                fontWeight: bold ? FontWeight.w800 : FontWeight.w600,
              ),
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
