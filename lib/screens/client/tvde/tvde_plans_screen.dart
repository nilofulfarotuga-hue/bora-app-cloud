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
      context.read<TvdeStore>().loadPlanRequest();
    });
  }

  /// C4 — cliente pede adesão a um plano. Confirma, cria o pedido e mostra
  /// "pedido enviado" (o admin aprova/ativa num clique).
  Future<void> _aderir(String plan, String label) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Aderir ao $label?'),
        content: const Text(
            'Enviamos o teu pedido à equipa Bora. Assim que for aprovado, o '
            'plano fica ativo na tua conta.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Voltar')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Quero aderir')),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await context.read<TvdeStore>().requestPlan(plan, label);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Pedido enviado! A equipa Bora vai ativar o plano.')));
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Não foi possível enviar o pedido. Tenta de novo.')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final store = context.watch<TvdeStore>();
    final sub = store.subscription;
    final pending = store.planRequestStatus == 'pendente';

    return Scaffold(
      appBar: const BoraScreenAppBar(title: 'Planos'),
      body: ListView(
        padding: const EdgeInsets.all(Spacing.lg),
        children: [
          if (sub != null) _ActiveSubscription(sub: sub, dailyUsed: store.dailyUsed),
          if (sub != null) const SizedBox(height: Spacing.lg),
          if (pending) ...[
            _PendingBanner(),
            const SizedBox(height: Spacing.lg),
          ],
          Text('Planos disponíveis',
              style: const TextStyle(
                  fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
          const SizedBox(height: Spacing.sm),
          _PlanCard(
            title: 'Plano Semanal',
            price: '€56 / semana',
            detail: '14 corridas · 2 incluídas por dia · €4 / corrida',
            onAderir:
                pending || store.busy ? null : () => _aderir('semanal', 'Plano Semanal'),
          ),
          _PlanCard(
            title: 'Plano Quinzenal',
            price: '€105 / 15 dias',
            detail: '30 corridas · 2 incluídas por dia · €3,50 / corrida',
            onAderir: pending || store.busy
                ? null
                : () => _aderir('quinzenal', 'Plano Quinzenal'),
          ),
          _PlanCard(
            title: 'Plano Mensal',
            price: '€180 / mês',
            detail: '60 corridas · 2 incluídas por dia · €3 / corrida',
            onAderir:
                pending || store.busy ? null : () => _aderir('mensal', 'Plano Mensal'),
          ),
        ],
      ),
    );
  }
}

class _PendingBanner extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(Spacing.md),
      decoration: BoxDecoration(
        color: AppColors.primaryWash,
        borderRadius: BorderRadius.circular(Radii.md + 2),
      ),
      child: Row(
        children: [
          const Icon(Icons.hourglass_top, color: AppColors.primary),
          const SizedBox(width: Spacing.md),
          Expanded(
            child: Text(
              'Pedido de adesão enviado. A equipa Bora vai ativar o teu plano '
              'em breve.',
              style: TextStyle(color: AppColors.textSecondary, fontSize: 13),
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
      {required this.title,
      required this.price,
      required this.detail,
      this.onAderir});
  final String title;
  final String price;
  final String detail;
  final VoidCallback? onAderir;

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
          const SizedBox(height: Spacing.sm),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: onAderir,
              icon: const Icon(Icons.add_card, size: 18),
              label: const Text('Quero aderir'),
              style: OutlinedButton.styleFrom(
                foregroundColor: AppColors.primary,
                side: const BorderSide(color: AppColors.primary),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(Radii.md)),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
