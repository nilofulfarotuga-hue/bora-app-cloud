import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../config/app_colors.dart';
import '../widgets/bora/bora_screen_app_bar.dart';

import '../l10n/tr.dart';

/// Lista pública de avaliações de um restaurante (BR §44).
///
/// Chama get_restaurant_ratings_summary(p_restaurant_id) — devolve avg, count,
/// distribuição 1-5 e até 20 ratings recentes não-privados nem flagged. Cliente
/// abre via card do restaurante; partner via deep link da push notification.
class RestaurantRatingsListScreen extends StatefulWidget {
  const RestaurantRatingsListScreen({
    super.key,
    required this.restaurantId,
    required this.restaurantName,
  });

  final String restaurantId;
  final String restaurantName;

  @override
  State<RestaurantRatingsListScreen> createState() =>
      _RestaurantRatingsListScreenState();
}

class _RestaurantRatingsListScreenState
    extends State<RestaurantRatingsListScreen> {
  late Future<Map<String, dynamic>> _future;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<Map<String, dynamic>> _load() async {
    final res = await Supabase.instance.client.rpc(
      'get_restaurant_ratings_summary',
      params: {'p_restaurant_id': widget.restaurantId},
    );
    if (res is Map<String, dynamic>) return res;
    if (res is Map) return Map<String, dynamic>.from(res);
    return <String, dynamic>{};
  }

  Future<void> _refresh() async {
    setState(() => _future = _load());
    await _future;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: BoraScreenAppBar(title: 'Avaliações de {0}'.trArgs([widget.restaurantName])),
      body: RefreshIndicator(
        onRefresh: _refresh,
        child: FutureBuilder<Map<String, dynamic>>(
          future: _future,
          builder: (context, snap) {
            if (snap.connectionState != ConnectionState.done) {
              return const Center(child: CircularProgressIndicator());
            }
            if (snap.hasError) {
              return ListView(
                children: [
                  const SizedBox(height: 80),
                  Center(child: Text('Erro: {0}'.trArgs([snap.error]))),
                ],
              );
            }
            final data = snap.data ?? const <String, dynamic>{};
            final total = (data['total'] as num?)?.toInt() ?? 0;
            final avg = (data['avg_stars'] as num?)?.toDouble();
            final dist = (data['distribution'] as Map?) ?? const {};
            final recent = (data['recent'] as List?) ?? const [];
            return ListView(
              padding: const EdgeInsets.all(16),
              children: [
                _SummaryCard(avg: avg, total: total, distribution: dist),
                const SizedBox(height: 16),
                if (recent.isEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 24),
                    child: Center(
                      child: Text(
                        'Ainda sem avaliações públicas.'.tr,
                        style: const TextStyle(color: Colors.grey),
                      ),
                    ),
                  )
                else
                  ...recent.map((r) => _RatingCard(
                        data: Map<String, dynamic>.from(r as Map),
                      )),
                const SizedBox(height: 32),
              ],
            );
          },
        ),
      ),
    );
  }
}

/// Lista pública de avaliações de um estafeta — chama
/// get_driver_ratings_summary(p_driver_id).
class DriverRatingsListScreen extends StatefulWidget {
  const DriverRatingsListScreen({
    super.key,
    required this.driverId,
    required this.driverName,
  });

  final String driverId;
  final String driverName;

  @override
  State<DriverRatingsListScreen> createState() =>
      _DriverRatingsListScreenState();
}

class _DriverRatingsListScreenState extends State<DriverRatingsListScreen> {
  late Future<Map<String, dynamic>> _future;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<Map<String, dynamic>> _load() async {
    final res = await Supabase.instance.client.rpc(
      'get_driver_ratings_summary',
      params: {'p_driver_id': widget.driverId},
    );
    if (res is Map<String, dynamic>) return res;
    if (res is Map) return Map<String, dynamic>.from(res);
    return <String, dynamic>{};
  }

  Future<void> _refresh() async {
    setState(() => _future = _load());
    await _future;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: BoraScreenAppBar(title: 'Avaliações de {0}'.trArgs([widget.driverName])),
      body: RefreshIndicator(
        onRefresh: _refresh,
        child: FutureBuilder<Map<String, dynamic>>(
          future: _future,
          builder: (context, snap) {
            if (snap.connectionState != ConnectionState.done) {
              return const Center(child: CircularProgressIndicator());
            }
            if (snap.hasError) {
              return ListView(
                children: [
                  const SizedBox(height: 80),
                  Center(child: Text('Erro: {0}'.trArgs([snap.error]))),
                ],
              );
            }
            final data = snap.data ?? const <String, dynamic>{};
            final total = (data['total'] as num?)?.toInt() ?? 0;
            final avg = (data['avg_stars'] as num?)?.toDouble();
            final dist = (data['distribution'] as Map?) ?? const {};
            final recent = (data['recent'] as List?) ?? const [];
            return ListView(
              padding: const EdgeInsets.all(16),
              children: [
                _SummaryCard(avg: avg, total: total, distribution: dist),
                const SizedBox(height: 16),
                if (recent.isEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 24),
                    child: Center(
                      child: Text(
                        'Ainda sem avaliações públicas.'.tr,
                        style: const TextStyle(color: Colors.grey),
                      ),
                    ),
                  )
                else
                  ...recent.map((r) => _RatingCard(
                        data: Map<String, dynamic>.from(r as Map),
                      )),
                const SizedBox(height: 32),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _SummaryCard extends StatelessWidget {
  const _SummaryCard({
    required this.avg,
    required this.total,
    required this.distribution,
  });

  final double? avg;
  final int total;
  final Map distribution;

  @override
  Widget build(BuildContext context) {
    final avgStr = avg == null ? '—' : avg!.toStringAsFixed(1);
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.star, color: AppColors.warning, size: 36),
                const SizedBox(width: 12),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      avgStr,
                      style: const TextStyle(
                        fontSize: 28,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    Text(
                      total == 1 ? '$total avaliação' : '$total avaliações',
                      style: const TextStyle(color: Colors.grey),
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 16),
            for (final s in [5, 4, 3, 2, 1])
              _DistBar(
                stars: s,
                count: (distribution['$s'] as num?)?.toInt() ?? 0,
                total: total,
              ),
          ],
        ),
      ),
    );
  }
}

class _DistBar extends StatelessWidget {
  const _DistBar(
      {required this.stars, required this.count, required this.total});

  final int stars;
  final int count;
  final int total;

  @override
  Widget build(BuildContext context) {
    final pct = total > 0 ? count / total : 0.0;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          SizedBox(
            width: 26,
            child: Text('$stars★', style: const TextStyle(fontSize: 12)),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: Container(
                height: 8,
                color: Colors.grey.shade200,
                child: FractionallySizedBox(
                  alignment: Alignment.centerLeft,
                  widthFactor: pct,
                  child: Container(color: AppColors.warning),
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          SizedBox(
            width: 36,
            child: Text(
              '$count',
              style: const TextStyle(fontSize: 12),
              textAlign: TextAlign.end,
            ),
          ),
        ],
      ),
    );
  }
}

class _RatingCard extends StatelessWidget {
  const _RatingCard({required this.data});
  final Map<String, dynamic> data;

  String _formatDate(dynamic raw) {
    if (raw == null) return '';
    final dt = DateTime.tryParse(raw.toString())?.toLocal();
    if (dt == null) return '';
    final dd = dt.day.toString().padLeft(2, '0');
    final mm = dt.month.toString().padLeft(2, '0');
    return '$dd/$mm/${dt.year}';
  }

  @override
  Widget build(BuildContext context) {
    final stars = (data['stars'] as num?)?.toInt() ?? 0;
    final comment = (data['comment'] as String?) ?? '';
    final tags = (data['tags'] as List?)?.cast<String>() ?? const [];
    final response = (data['response_text'] as String?) ?? '';
    return Card(
      elevation: 1,
      margin: const EdgeInsets.only(bottom: 10),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Row(
                  children: List.generate(5, (i) {
                    return Icon(
                      i < stars ? Icons.star : Icons.star_border,
                      size: 16,
                      color: AppColors.warning,
                    );
                  }),
                ),
                const Spacer(),
                Text(
                  _formatDate(data['created_at']),
                  style: const TextStyle(fontSize: 11, color: Colors.grey),
                ),
              ],
            ),
            if (comment.isNotEmpty) ...[
              const SizedBox(height: 6),
              Text(comment),
            ],
            if (tags.isNotEmpty) ...[
              const SizedBox(height: 6),
              Wrap(
                spacing: 6,
                runSpacing: 4,
                children: tags
                    .map((t) => Chip(
                          label: Text(t,
                              style: const TextStyle(fontSize: 10)),
                          materialTapTargetSize:
                              MaterialTapTargetSize.shrinkWrap,
                          padding: EdgeInsets.zero,
                          visualDensity: VisualDensity.compact,
                        ))
                    .toList(),
              ),
            ],
            if (response.isNotEmpty) ...[
              const SizedBox(height: 10),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: AppColors.primaryLight,
                  borderRadius: BorderRadius.circular(8),
                  border: const Border(
                    left: BorderSide(color: AppColors.primary, width: 3),
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Resposta do parceiro:'.tr,
                      style: const TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 12,
                        color: AppColors.primary,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(response, style: const TextStyle(fontSize: 13)),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
