import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../config/app_colors.dart';
import '../../../config/app_spacing.dart';
import '../../../models/tvde_fare_view.dart';
import '../../../models/tvde_ride.dart';
import '../../../stores/tvde_store.dart';
import '../../../widgets/bora/bora.dart';
import '../../../widgets/tvde/tvde_roundtrip_driver_notice.dart';

import '../../../l10n/tr.dart';

/// TVDE — Avaliação do motorista pelo passageiro (tvde_rate, subject 'driver').
class TvdeRateScreen extends StatefulWidget {
  const TvdeRateScreen({super.key, required this.ride});
  final TvdeRide ride;

  @override
  State<TvdeRateScreen> createState() => _TvdeRateScreenState();
}

class _TvdeRateScreenState extends State<TvdeRateScreen> {
  int _stars = 5;
  final _comment = TextEditingController();
  int _packageCents = TvdeRoundtripPrice.fallbackCents;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final pkg = await TvdeRoundtripPrice.loadForRide(
          context.read<TvdeStore>(), widget.ride);
      if (mounted) setState(() => _packageCents = pkg);
    });
  }

  @override
  void dispose() {
    _comment.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final store = context.read<TvdeStore>();
    try {
      await store.rateDriver(widget.ride.id, _stars,
          comment: _comment.text.trim().isEmpty ? null : _comment.text.trim());
    } catch (_) {
      // Avaliação é best-effort; não bloqueia o fecho.
    }
    if (!mounted) return;
    store.clearActiveRide();
    Navigator.pop(context);
  }

  void _skip() {
    context.read<TvdeStore>().clearActiveRide();
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final store = context.watch<TvdeStore>();
    final fareView =
        TvdeFareView.of(widget.ride, packageCents: _packageCents);
    final covered = fareView.clientTotalCents == 0;
    final fare = fareView.clientTotalCents / 100;

    return Scaffold(
      appBar: BoraScreenAppBar(title: 'Avaliar viagem'.tr),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(Spacing.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SizedBox(height: Spacing.lg),
            const Icon(Icons.check_circle, size: 64, color: AppColors.primary),
            const SizedBox(height: Spacing.md),
            Text('Viagem concluída'.tr,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: AppColors.textPrimary)),
            const SizedBox(height: Spacing.xs),
            Text(
                covered
                    ? (widget.ride.isRoundtripLeg
                        ? 'Volta incluída no pacote — não pagaste nada.'.tr
                        : 'Corrida incluída no teu plano — não pagaste nada.')
                    : 'Pagaste €{0}{1}'.trArgs([fare.toStringAsFixed(2), fareView.isPaidOnline ? ' no app.' : ' em dinheiro.']),
                textAlign: TextAlign.center,
                style: const TextStyle(color: AppColors.textSecondary)),
            const SizedBox(height: Spacing.xl),
            Text('Como foi o motorista?'.tr,
                textAlign: TextAlign.center,
                style: const TextStyle(
                    fontWeight: FontWeight.w600,
                    color: AppColors.textPrimary)),
            const SizedBox(height: Spacing.md),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: List.generate(5, (i) {
                final star = i + 1;
                return IconButton(
                  iconSize: 40,
                  onPressed: () => setState(() => _stars = star),
                  icon: Icon(
                    star <= _stars ? Icons.star : Icons.star_border,
                    color: AppColors.accent,
                  ),
                );
              }),
            ),
            const SizedBox(height: Spacing.md),
            TextField(
              controller: _comment,
              maxLines: 3,
              decoration: InputDecoration(
                labelText: 'Comentário (opcional)'.tr,
                alignLabelWithHint: true,
              ),
            ),
            const SizedBox(height: Spacing.xl),
            BoraPrimaryButton(
              label: 'Enviar avaliação'.tr,
              icon: Icons.send,
              loading: store.busy,
              onPressed: _submit,
            ),
            const SizedBox(height: Spacing.sm),
            TextButton(onPressed: _skip, child: Text('Agora não'.tr)),
          ],
        ),
      ),
    );
  }
}
