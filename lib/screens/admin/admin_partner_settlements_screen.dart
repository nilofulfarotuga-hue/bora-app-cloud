import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../config/app_colors.dart';
import '../../config/app_spacing.dart';
import '../../widgets/bora/bora_screen_app_bar.dart';

/// Acerto Semanal Parceiros — agregação por restaurante dos créditos €2
/// usados (cliente já consumiu) e ainda por pagar pela Bora ao parceiro.
/// Botão "Marcar como pago" chama RPC `admin_mark_partner_credits_paid`.
class AdminPartnerSettlementsScreen extends StatefulWidget {
  const AdminPartnerSettlementsScreen({super.key});

  @override
  State<AdminPartnerSettlementsScreen> createState() =>
      _AdminPartnerSettlementsScreenState();
}

class _AdminPartnerSettlementsScreenState
    extends State<AdminPartnerSettlementsScreen> {
  bool _loading = true;
  String? _error;
  // 0 = semana atual, -1 = anterior, etc.
  int _weekOffset = 0;
  List<_PartnerRow> _rows = const [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  // Semana = segunda 00:00 (local) → segunda seguinte 00:00.
  DateTime _weekStart() {
    final now = DateTime.now().add(Duration(days: 7 * _weekOffset));
    final monday = now.subtract(Duration(days: now.weekday - 1));
    return DateTime(monday.year, monday.month, monday.day);
  }

  DateTime _weekEnd() => _weekStart().add(const Duration(days: 7));

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final supabase = Supabase.instance.client;
      final start = _weekStart();
      final end = _weekEnd();

      final creditRows = await supabase
          .from('restaurant_menu_credits')
          .select('restaurant_id, amount_cents')
          .gte('used_at', start.toIso8601String())
          .lt('used_at', end.toIso8601String())
          .not('used_at', 'is', null)
          .filter('paid_to_partner_at', 'is', null);

      final agg = <String, _PartnerRow>{};
      for (final raw in (creditRows as List)) {
        final row = Map<String, dynamic>.from(raw as Map);
        final id = row['restaurant_id'] as String;
        final cents = (row['amount_cents'] as num?)?.toInt() ?? 0;
        agg.update(
          id,
          (v) => v.copyWith(count: v.count + 1, totalCents: v.totalCents + cents),
          ifAbsent: () => _PartnerRow(
            restaurantId: id,
            restaurantName: id,
            count: 1,
            totalCents: cents,
          ),
        );
      }

      if (agg.isNotEmpty) {
        final names = await supabase
            .from('restaurants')
            .select('id, name')
            .inFilter('id', agg.keys.toList());
        for (final raw in (names as List)) {
          final row = Map<String, dynamic>.from(raw as Map);
          final id = row['id'] as String;
          final name = (row['name'] as String?) ?? id;
          if (agg.containsKey(id)) {
            agg[id] = agg[id]!.copyWith(restaurantName: name);
          }
        }
      }

      if (!mounted) return;
      setState(() {
        _rows = agg.values.toList()
          ..sort((a, b) => a.restaurantName
              .toLowerCase()
              .compareTo(b.restaurantName.toLowerCase()));
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString().replaceFirst('Exception: ', '');
        _loading = false;
      });
    }
  }

  Future<void> _markPaid(_PartnerRow row) async {
    final messenger = ScaffoldMessenger.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Marcar como pago'),
        content: Text(
          'Confirmar pagamento de ${_euros(row.totalCents)} a ${row.restaurantName}?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Confirmar'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    try {
      final result = await Supabase.instance.client.rpc(
        'admin_mark_partner_credits_paid',
        params: {
          'p_restaurant_id': row.restaurantId,
          'p_week_start': _weekStart().toIso8601String(),
          'p_week_end': _weekEnd().toIso8601String(),
        },
      );
      final data = Map<String, dynamic>.from(result as Map);
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            '${data['count']} créditos marcados — total ${_euros((data['total_cents'] as num).toInt())}',
          ),
          backgroundColor: AppColors.primary,
        ),
      );
      await _load();
    } catch (e) {
      messenger.showSnackBar(
        SnackBar(
          content: Text(e.toString().replaceFirst('Exception: ', '')),
          backgroundColor: AppColors.error,
        ),
      );
    }
  }

  String _euros(int cents) => '€${(cents / 100.0).toStringAsFixed(2)}';

  String _weekLabel() {
    final s = _weekStart();
    final e = _weekEnd().subtract(const Duration(days: 1));
    return '${_dt(s)} — ${_dt(e)}';
  }

  String _dt(DateTime d) =>
      '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}';

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: BoraScreenAppBar(
        title: 'Acerto Semanal Parceiros',
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
            const Divider(height: 1, color: AppColors.divider),
            Expanded(child: _buildBody()),
          ],
        ),
      ),
    );
  }

  Widget _buildWeekSelector() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      child: Row(
        children: [
          IconButton(
            icon: const Icon(Icons.chevron_left),
            onPressed: () {
              setState(() => _weekOffset -= 1);
              _load();
            },
          ),
          Expanded(
            child: Center(
              child: Text(
                _weekOffset == 0
                    ? 'Semana atual · ${_weekLabel()}'
                    : 'Semana ${_weekOffset.abs()} atrás · ${_weekLabel()}',
                style: const TextStyle(
                  fontWeight: FontWeight.w700,
                  color: AppColors.textPrimary,
                ),
              ),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.chevron_right),
            onPressed: _weekOffset < 0
                ? () {
                    setState(() => _weekOffset += 1);
                    _load();
                  }
                : null,
          ),
        ],
      ),
    );
  }

  Widget _buildBody() {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline, size: 48, color: AppColors.error),
              const SizedBox(height: 12),
              Text(_error!, textAlign: TextAlign.center),
              const SizedBox(height: 12),
              ElevatedButton(
                onPressed: _load,
                child: const Text('Tentar novamente'),
              ),
            ],
          ),
        ),
      );
    }
    if (_rows.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Text(
            'Nenhum crédito a acertar nesta semana.',
            style: TextStyle(color: AppColors.textSecondary),
          ),
        ),
      );
    }
    final grandTotal = _rows.fold<int>(0, (s, r) => s + r.totalCents);
    return Column(
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          color: AppColors.card,
          child: Row(
            children: [
              const Text(
                'Total a pagar esta semana',
                style: TextStyle(
                  fontWeight: FontWeight.w700,
                  color: AppColors.textPrimary,
                ),
              ),
              const Spacer(),
              Text(
                _euros(grandTotal),
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                  color: AppColors.primary,
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: ListView.separated(
            padding: const EdgeInsets.symmetric(vertical: 8),
            itemCount: _rows.length,
            separatorBuilder: (_, __) => const SizedBox(height: 4),
            itemBuilder: (_, i) => _buildRow(_rows[i]),
          ),
        ),
      ],
    );
  }

  Widget _buildRow(_PartnerRow row) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(Radii.lg),
        boxShadow: AppColors.shadowCard,
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    row.restaurantName,
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      color: AppColors.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '${row.count} ${row.count == 1 ? 'crédito usado' : 'créditos usados'} · ${_euros(row.totalCents)}',
                    style: const TextStyle(
                      fontSize: 12,
                      color: AppColors.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            FilledButton.icon(
              onPressed: () => _markPaid(row),
              icon: const Icon(Icons.check, size: 16),
              label: const Text('Marcar como pago'),
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.primary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PartnerRow {
  const _PartnerRow({
    required this.restaurantId,
    required this.restaurantName,
    required this.count,
    required this.totalCents,
  });

  final String restaurantId;
  final String restaurantName;
  final int count;
  final int totalCents;

  _PartnerRow copyWith({
    String? restaurantName,
    int? count,
    int? totalCents,
  }) =>
      _PartnerRow(
        restaurantId: restaurantId,
        restaurantName: restaurantName ?? this.restaurantName,
        count: count ?? this.count,
        totalCents: totalCents ?? this.totalCents,
      );
}
