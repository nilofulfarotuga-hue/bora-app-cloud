import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../config/app_colors.dart';
import '../../../config/app_spacing.dart';
import '../../../models/tvde_subscription.dart';
import '../../../services/payment_service.dart';
import '../../../stores/tvde_store.dart';
import '../../../widgets/bora/bora.dart';

/// TVDE — Planos de assinatura + contador diário. [Item A] o cliente PAGA o
/// plano por cartão (Stripe, Edge Function isolada tvde-plan-payment) e a
/// subscrição ativa-se automaticamente. O admin também pode conceder
/// (admin_grant_subscription) — os dois caminhos coexistem.
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

  /// [Item A] Cliente adere pagando por cartão: cria PaymentIntent → folha
  /// Stripe → ativa (a Edge Function verifica o PI na Stripe). Sem espera pelo
  /// admin.
  Future<void> _aderir(String plan, String label, String price) async {
    if (kIsWeb) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('O pagamento por cartão está disponível na app móvel.')));
      return;
    }
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Aderir ao $label?'),
        content: Text(
            'Vais pagar $price por cartão. Assim que o pagamento for confirmado, '
            'o plano fica ativo na tua conta imediatamente.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Voltar')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Pagar')),
        ],
      ),
    );
    if (confirmed != true) return;

    final store = context.read<TvdeStore>();
    final messenger = ScaffoldMessenger.of(context);

    // 1) Cria o PaymentIntent do plano (Edge Function isolada).
    final created = await store.createPlanPayment(plan);
    if (!mounted) return;
    if (created == null) {
      messenger.showSnackBar(const SnackBar(
          content: Text('Não foi possível iniciar o pagamento. Tenta de novo.')));
      return;
    }

    // 2) Folha de pagamento Stripe (cartão). Lança em cancelamento/erro.
    try {
      await PaymentService().processPayment(created['clientSecret'] as String);
    } catch (_) {
      if (!mounted) return;
      messenger.showSnackBar(const SnackBar(
          content: Text('Pagamento não concluído.')));
      return;
    }

    // 3) Ativa a subscrição — a Edge Function reverifica o PI na Stripe.
    try {
      await store.activatePlan(plan, created['paymentIntentId'] as String);
      if (!mounted) return;
      messenger.showSnackBar(const SnackBar(
          content: Text('Plano ativo! Já podes usar as corridas incluídas.')));
    } catch (_) {
      if (!mounted) return;
      messenger.showSnackBar(const SnackBar(
          content: Text('O pagamento foi feito, mas a ativação falhou. Reabre '
              'os Planos para confirmar, ou contacta o suporte.')));
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
            onAderir: pending || store.busy
                ? null
                : () => _aderir('semanal', 'Plano Semanal', '€56'),
          ),
          _PlanCard(
            title: 'Plano Quinzenal',
            price: '€105 / 15 dias',
            detail: '30 corridas · 2 incluídas por dia · €3,50 / corrida',
            onAderir: pending || store.busy
                ? null
                : () => _aderir('quinzenal', 'Plano Quinzenal', '€105'),
          ),
          _PlanCard(
            title: 'Plano Mensal',
            price: '€180 / mês',
            detail: '60 corridas · 2 incluídas por dia · €3 / corrida',
            onAderir: pending || store.busy
                ? null
                : () => _aderir('mensal', 'Plano Mensal', '€180'),
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
