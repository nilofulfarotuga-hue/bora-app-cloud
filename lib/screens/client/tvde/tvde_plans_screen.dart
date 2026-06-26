import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../config/app_colors.dart';
import '../../../config/app_spacing.dart';
import '../../../models/tvde_subscription.dart';
import '../../../stores/tvde_store.dart';
import '../../../widgets/bora/bora.dart';

/// TVDE — Planos de assinatura + contador diário. Na fase de testes as
/// assinaturas são concedidas pelo admin (sem compra Stripe).
class TvdePlansScreen extends StatefulWidget {
  const TvdePlansScreen({super.key});

  @override
  State<TvdePlansScreen> createState() => _TvdePlansScreenState();
}

class _TvdePlansScreenState extends State<TvdePlansScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<TvdeStore>().loadSubscription();
    });
  }

  @override
  Widget build(BuildContext context) {
    final store = context.watch<TvdeStore>();
    final sub = store.subscription;

    return Scaffold(
      appBar: const BoraScreenAppBar(title: 'Planos'),
      body: ListView(
        padding: const EdgeInsets.all(Spacing.lg),
        children: [
          if (sub != null) _ActiveSubscription(sub: sub, dailyUsed: store.dailyUsed),
          if (sub != null) const SizedBox(height: Spacing.lg),
          Text('Planos disponíveis',
              style: const TextStyle(
                  fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
          const SizedBox(height: Spacing.sm),
          const _PlanCard(
            title: 'Plano Semanal',
            price: '€56 / semana',
            detail: '14 corridas · 2 incluídas por dia · €4 / corrida',
          ),
          const _PlanCard(
            title: 'Plano Quinzenal',
            price: '€105 / 15 dias',
            detail: '30 corridas · 2 incluídas por dia · €3,50 / corrida',
          ),
          const _PlanCard(
            title: 'Plano Mensal',
            price: '€180 / mês',
            detail: '60 corridas · 2 incluídas por dia · €3 / corrida',
          ),
          const SizedBox(height: Spacing.md),
          Container(
            padding: const EdgeInsets.all(Spacing.md),
            decoration: BoxDecoration(
              color: AppColors.primaryWash,
              borderRadius: BorderRadius.circular(Radii.md + 2),
            ),
            child: Row(
              children: [
                const Icon(Icons.info_outline, color: AppColors.primary),
                const SizedBox(width: Spacing.md),
                Expanded(
                  child: Text(
                    'Durante a fase de testes, os planos são ativados pela '
                    'equipa Bora. Fala connosco para aderir.',
                    style: TextStyle(
                        color: AppColors.textSecondary, fontSize: 13),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ActiveSubscription extends StatelessWidget {
  const _ActiveSubscription({required this.sub, required this.dailyUsed});
  final TvdeSubscription sub;
  final int dailyUsed;

  @override
  Widget build(BuildContext context) {
    final remainingToday = (sub.dailyIncluded - dailyUsed).clamp(0, sub.dailyIncluded);
    return Container(
      padding: const EdgeInsets.all(Spacing.lg),
      decoration: BoxDecoration(
        gradient: AppColors.headerGradient,
        borderRadius: BorderRadius.circular(Radii.lg),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.card_membership, color: Colors.white),
              const SizedBox(width: Spacing.sm),
              Text(sub.planLabel,
                  style: const TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.w700)),
            ],
          ),
          const SizedBox(height: Spacing.md),
          _row('Hoje', '$remainingToday de ${sub.dailyIncluded} corridas restantes'),
          const SizedBox(height: 4),
          _row('Plano', '${sub.ridesLeft} de ${sub.ridesTotal} corridas restantes'),
        ],
      ),
    );
  }

  Widget _row(String k, String v) => Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(k, style: const TextStyle(color: Colors.white70)),
          Text(v,
              style: const TextStyle(
                  color: Colors.white, fontWeight: FontWeight.w600)),
        ],
      );
}

class _PlanCard extends StatelessWidget {
  const _PlanCard(
      {required this.title, required this.price, required this.detail});
  final String title;
  final String price;
  final String detail;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: Spacing.sm),
      padding: const EdgeInsets.all(Spacing.md),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(Radii.md + 2),
        border: Border.all(color: AppColors.divider),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(title,
                  style: const TextStyle(
                      fontWeight: FontWeight.w700,
                      color: AppColors.textPrimary)),
              Text(price,
                  style: const TextStyle(
                      fontWeight: FontWeight.w700, color: AppColors.primary)),
            ],
          ),
          const SizedBox(height: 4),
          Text(detail,
              style: TextStyle(fontSize: 12, color: AppColors.textSubtle)),
        ],
      ),
    );
  }
}
