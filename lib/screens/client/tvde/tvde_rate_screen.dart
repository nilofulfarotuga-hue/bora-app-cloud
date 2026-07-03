import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../config/app_colors.dart';
import '../../../config/app_spacing.dart';
import '../../../models/tvde_ride.dart';
import '../../../stores/tvde_store.dart';
import '../../../widgets/bora/bora.dart';

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
    final covered = widget.ride.usedSubscriptionRide;
    final fare = widget.ride.displayFareCents / 100;

    return Scaffold(
      appBar: const BoraScreenAppBar(title: 'Avaliar viagem'),
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
                    fontWeight: FontWeight.w700,
                    color: AppColors.textPrimary)),
            const SizedBox(height: Spacing.xs),
            Text(
                covered
                    ? 'Corrida incluída no teu plano — não pagaste nada.'
                    : 'Pagaste €${fare.toStringAsFixed(2)} em dinheiro.',
                textAlign: TextAlign.center,
                style: TextStyle(color: AppColors.textSecondary)),
            const SizedBox(height: Spacing.xl),
            Text('Como foi o motorista?',
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
