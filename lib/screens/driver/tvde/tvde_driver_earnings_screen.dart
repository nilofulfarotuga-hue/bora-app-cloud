import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../config/app_colors.dart';
import '../../../config/app_spacing.dart';
import '../../../models/tvde_ride.dart';
import '../../../widgets/bora/bora.dart';

/// TVDE — M12 (paridade Uber Driver): ganhos do dia e da semana + histórico
/// de corridas do motorista. Lê `tvde_rides` finalizadas do próprio motorista
/// (RLS já permite; driver_id = auth uid). Read-only, sem tocar em fórmulas.
class TvdeDriverEarningsScreen extends StatefulWidget {
  const TvdeDriverEarningsScreen({super.key});

  @override
  State<TvdeDriverEarningsScreen> createState() =>
      _TvdeDriverEarningsScreenState();
}

class _TvdeDriverEarningsScreenState extends State<TvdeDriverEarningsScreen> {
  bool _loading = true;
  bool _error = false;
  List<TvdeRide> _rides = const [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final uid = Supabase.instance.client.auth.currentUser?.id;
    if (uid == null) {
      setState(() => _loading = false);
      return;
    }
    try {
      // Últimos 60 dias chegam para dia/semana + histórico recente.
      final since = DateTime.now().toUtc().subtract(const Duration(days: 60));
      final rows = await Supabase.instance.client
          .from('tvde_rides')
          .select()
          .eq('driver_id', uid)
          .eq('status', 'finalizada')
          .gte('updated_at', since.toIso8601String())
          .order('updated_at', ascending: false)
          .limit(200);
      if (!mounted) return;
      setState(() {
        _rides = [for (final r in rows) TvdeRide.fromMap(r)];
        _loading = false;
        _error = false;
      });
    } catch (_) {
      // Falha de rede ≠ "sem corridas": marca erro para a UI não fingir vazio.
      if (mounted) {
        setState(() {
          _loading = false;
          _error = true;
        });
      }
    }
  }

  int _sumCents(bool Function(DateTime) inPeriod) {
    var sum = 0;
    for (final r in _rides) {
      final t = r.createdAt;
      if (t != null && inPeriod(t.toLocal())) {
        sum += r.driverEarnCents ?? 0;
      }
    }
    return sum;
  }

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final todayStart = DateTime(now.year, now.month, now.day);
    // Semana estilo Uber: segunda-feira 00:00 local.
    final weekStart =
        todayStart.subtract(Duration(days: todayStart.weekday - 1));

    final todayCents = _sumCents((t) => !t.isBefore(todayStart));
    final weekCents = _sumCents((t) => !t.isBefore(weekStart));
    final weekRides = _rides
        .where((r) =>
            r.createdAt != null && !r.createdAt!.toLocal().isBefore(weekStart))
        .length;

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: const BoraScreenAppBar(title: 'Os teus ganhos'),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView(
                padding: const EdgeInsets.all(Spacing.md),
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: _EarnCard(
                            label: 'Hoje',
                            cents: todayCents,
                            icon: Icons.today),
                      ),
                      const SizedBox(width: Spacing.md),
                      Expanded(
                        child: _EarnCard(
                            label: 'Esta semana',
                            cents: weekCents,
                            icon: Icons.date_range,
                            sub: '$weekRides corrida${weekRides == 1 ? '' : 's'}'),
                      ),
                    ],
                  ),
                  const SizedBox(height: Spacing.lg),
                  Text('Histórico de corridas',
                      style: Theme.of(context)
                          .textTheme
                          .titleMedium
                          ?.copyWith(fontWeight: FontWeight.w800)),
                  const SizedBox(height: Spacing.sm),
                  if (_error && _rides.isEmpty)
                    Padding(
                      padding: const EdgeInsets.all(Spacing.xl),
                      child: Column(
                        children: [
                          const Icon(Icons.wifi_off,
                              size: 40, color: AppColors.textSubtle),
                          const SizedBox(height: Spacing.sm),
                          Text('Não foi possível carregar os ganhos.',
                              textAlign: TextAlign.center,
                              style:
                                  TextStyle(color: AppColors.textSecondary)),
                          const SizedBox(height: Spacing.sm),
                          TextButton.icon(
                            onPressed: () {
                              setState(() => _loading = true);
                              _load();
                            },
                            icon: const Icon(Icons.refresh),
                            label: const Text('Tentar novamente'),
                          ),
                        ],
                      ),
                    )
                  else if (_rides.isEmpty)
                    Padding(
                      padding: const EdgeInsets.all(Spacing.xl),
                      child: Center(
                        child: Text('Ainda não tens corridas finalizadas.',
                            style: TextStyle(color: AppColors.textSecondary)),
                      ),
                    )
                  else
                    ..._rides.map((r) => _RideTile(ride: r)),
                ],
              ),
            ),
    );
  }
}

class _EarnCard extends StatelessWidget {
  const _EarnCard(
      {required this.label, required this.cents, required this.icon, this.sub});
  final String label;
  final int cents;
  final IconData icon;
  final String? sub;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(Spacing.lg),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(Radii.lg),
        boxShadow: const [BoxShadow(color: Color(0x14000000), blurRadius: 8)],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: AppColors.primary, size: 20),
          const SizedBox(height: Spacing.sm),
          Text('€${(cents / 100).toStringAsFixed(2)}',
              style: const TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w800,
                  color: AppColors.textPrimary)),
          Text(label,
              style: TextStyle(color: AppColors.textSecondary, fontSize: 12.5)),
          if (sub != null)
            Text(sub!,
                style:
                    TextStyle(color: AppColors.textSubtle, fontSize: 11.5)),
        ],
      ),
    );
  }
}

class _RideTile extends StatelessWidget {
  const _RideTile({required this.ride});
  final TvdeRide ride;

  @override
  Widget build(BuildContext context) {
    final t = ride.createdAt?.toLocal();
    final when = t == null
        ? ''
        : '${t.day.toString().padLeft(2, '0')}/${t.month.toString().padLeft(2, '0')} '
            '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';
    final earn = ((ride.driverEarnCents ?? 0) / 100).toStringAsFixed(2);
    final km = (ride.finalDistanceKm ?? ride.estDistanceKm).toStringAsFixed(1);
    return Container(
      margin: const EdgeInsets.only(bottom: Spacing.sm),
      padding: const EdgeInsets.all(Spacing.md),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(Radii.md),
      ),
      child: Row(
        children: [
          const Icon(Icons.local_taxi, color: AppColors.primary, size: 20),
          const SizedBox(width: Spacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${ride.originLabel ?? 'Recolha'} → ${ride.destLabel ?? 'Destino'}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 13.5,
                      color: AppColors.textPrimary),
                ),
                Text('$when · $km km',
                    style: TextStyle(
                        color: AppColors.textSecondary, fontSize: 12)),
                // PART2 — breakdown do dinheiro: quanto cobrou ao passageiro e
                // quanto fica para a Bora (o €earn à direita é o ganho dele).
                Builder(builder: (_) {
                  if (ride.usedSubscriptionRide) {
                    return const Text('Coberta pelo plano · dinheiro',
                        style: TextStyle(
                            color: AppColors.textSecondary, fontSize: 11.5));
                  }
                  final grossCents = ride.finalFareCents ?? ride.estFareCents;
                  final gross = (grossCents / 100).toStringAsFixed(2);
                  final cut = ((grossCents - (ride.driverEarnCents ?? 0)) / 100)
                      .toStringAsFixed(2);
                  return Text('Cobrado €$gross · Bora €$cut',
                      style: const TextStyle(
                          color: AppColors.textSecondary, fontSize: 11.5));
                }),
              ],
            ),
          ),
          Text('€$earn',
              style: const TextStyle(
                  fontWeight: FontWeight.w800,
                  fontSize: 15,
                  color: AppColors.primary)),
        ],
      ),
    );
  }
}
