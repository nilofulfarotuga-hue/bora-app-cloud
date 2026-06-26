import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../config/app_colors.dart';
import '../../../config/app_spacing.dart';
import '../../../models/tvde_ride.dart';
import '../../../stores/tvde_driver_store.dart';
import '../../../widgets/bora/bora.dart';

/// TVDE — Avaliação do passageiro pelo motorista no fim da corrida
/// (tvde_rate → subject_type='tvde_passenger'). Mostra o ganho do motorista.
class TvdeDriverRateScreen extends StatefulWidget {
  const TvdeDriverRateScreen({super.key, required this.ride});
  final TvdeRide ride;

  @override
  State<TvdeDriverRateScreen> createState() => _TvdeDriverRateScreenState();
}

class _TvdeDriverRateScreenState extends State<TvdeDriverRateScreen> {
  int _stars = 5;
  final _comment = TextEditingController();

  @override
  void dispose() {
    _comment.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final store = context.read<TvdeDriverStore>();
    try {
      await store.ratePassenger(widget.ride.id, _stars,
          comment: _comment.text.trim().isEmpty ? null : _comment.text.trim());
    } catch (_) {
      // Best-effort — não bloqueia o fecho.
    }
    if (!mounted) return;
    store.clearActive();
    Navigator.of(context).maybePop();
  }

  void _skip() {
    context.read<TvdeDriverStore>().clearActive();
    Navigator.of(context).maybePop();
  }

  @override
  Widget build(BuildContext context) {
    final store = context.watch<TvdeDriverStore>();
    final ride = widget.ride;
    final earn = (ride.driverEarnCents ?? 0) / 100;

    return Scaffold(
      appBar: const BoraScreenAppBar(title: 'Fim da corrida'),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(Spacing.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SizedBox(height: Spacing.lg),
            const Icon(Icons.check_circle, size: 64, color: AppColors.primary),
            const SizedBox(height: Spacing.md),
            Text('Viagem concluída',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
            const SizedBox(height: Spacing.xs),
            Text('Ganhaste €${earn.toStringAsFixed(2)} nesta corrida.',
                textAlign: TextAlign.center,
                style: TextStyle(color: AppColors.textSecondary)),
            const SizedBox(height: Spacing.xl),
            Text('Como foi o passageiro?',
                textAlign: TextAlign.center,
                style: const TextStyle(
                    fontWeight: FontWeight.w600, color: AppColors.textPrimary)),
            const SizedBox(height: Spacing.md),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: List.generate(5, (i) {
                final star = i + 1;
                return IconButton(
                  iconSize: 40,
                  onPressed: () => setState(() => _stars = star),
                  icon: Icon(star <= _stars ? Icons.star : Icons.star_border,
                      color: AppColors.accent),
                );
              }),
            ),
            const SizedBox(height: Spacing.md),
            TextField(
              controller: _comment,
              maxLines: 3,
              decoration: const InputDecoration(
                labelText: 'Comentário (opcional)',
                alignLabelWithHint: true,
              ),
            ),
            const SizedBox(height: Spacing.xl),
            BoraPrimaryButton(
              label: 'Enviar avaliação',
              icon: Icons.send,
              loading: store.busy,
              onPressed: _submit,
            ),
            const SizedBox(height: Spacing.sm),
            TextButton(onPressed: _skip, child: const Text('Agora não')),
          ],
        ),
      ),
    );
  }
}
