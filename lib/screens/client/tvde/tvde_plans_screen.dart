import 'dart:async';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../config/app_colors.dart';
import '../../../config/app_spacing.dart';
import '../../../models/tvde_subscription.dart';
import '../../../services/payment_service.dart';
import '../../../stores/tvde_store.dart';
import '../../../widgets/bora/bora.dart';
import '../reservation/reservation_payment_method_sheet.dart';
import 'plan_mbway_waiting_dialog.dart';

import '../../../l10n/tr.dart';

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
  // Planos SEGUNDA A SEXTA (2 corridas/dia útil) — espelha admin_grant_subscription
  // e tvde_activate_paid_subscription no backend. Só o preço vem de lá em runtime;
  // o total de corridas é fixo pela regra do plano (5/10/22 dias úteis × 2).
  static const _ridesTotal = {'semanal': 10, 'quinzenal': 20, 'mensal': 44};
  static const _period = {'semanal': 'semana', 'quinzenal': '15 dias', 'mensal': 'mês'};

  /// plano → preço em cêntimos (via RPC tvde_plan_price_cents). null = a carregar.
  Map<String, int>? _priceCents;

  /// F5 (2026-08-16): retry do preço — fim do "A carregar…" eterno.
  Timer? _priceRetry;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<TvdeStore>().loadSubscription();
      context.read<TvdeStore>().loadPlanRequest();
    });
    _loadPrices();
  }

  @override
  void dispose() {
    _priceRetry?.cancel();
    super.dispose();
  }

  Future<void> _loadPrices() async {
    final store = context.read<TvdeStore>();
    // F5 (2026-08-16): antes, uma RPC a falhar (throw) deixava o ecrã em
    // "A carregar…" para sempre; e uma RPC a devolver null virava preço 0 com
    // o mapa NÃO-null — botão Aderir ATIVO com o label ainda "A carregar…".
    // Agora: qualquer preço em falta/<=0 ⇒ mapa fica null (botão desativado)
    // e tenta de novo sozinho a cada 8s enquanto o ecrã estiver aberto.
    List<int?> results;
    try {
      results = await Future.wait([
        store.planPriceCents('semanal'),
        store.planPriceCents('quinzenal'),
        store.planPriceCents('mensal'),
      ]);
    } catch (e) {
      debugPrint('[TvdePlans] _loadPrices falhou: $e');
      results = const [null, null, null];
    }
    if (!mounted) return;
    final ok = results.every((c) => c != null && c > 0);
    setState(() {
      _priceCents = ok
          ? {
              'semanal': results[0]!,
              'quinzenal': results[1]!,
              'mensal': results[2]!,
            }
          : null;
    });
    if (!ok) {
      _priceRetry?.cancel();
      _priceRetry = Timer(const Duration(seconds: 8), _loadPrices);
    }
  }

  String _priceLabel(String plan) {
    final cents = _priceCents?[plan];
    if (cents == null || cents <= 0) return 'A carregar…'.tr;
    final v = cents / 100;
    final euros = v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toStringAsFixed(2);
    return '€$euros / ${_period[plan]}';
  }

  String _detailLabel(String plan) =>
      '{0} corridas · Segunda a Sexta · 2 por dia útil'.trArgs([_ridesTotal[plan]]);

  /// [Item A] Cliente adere pagando por **cartão OU MB Way** (dinheiro NÃO é
  /// permitido no plano). Reaproveita o MESMO picker das Reservas/Serviços
  /// (`ReservationPaymentMethodSheet`) e, no MB Way, o mesmo padrão server-confirm
  /// + poll. A subscrição ativa-se automaticamente (a Edge Function isolada
  /// `tvde-plan-payment` verifica o PI na Stripe — sem tocar no webhook).
  Future<void> _aderir(String plan, String label, double priceEur) async {
    if (kIsWeb) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('O pagamento do plano está disponível na app móvel.'.tr)));
      return;
    }

    // Picker cartão/MB Way (sem dinheiro) — reaproveitado das Reservas.
    final choice = await showModalBottomSheet<ReservationPaymentChoice>(
      context: context,
      isScrollControlled: true,
      builder: (_) =>
          ReservationPaymentMethodSheet(amountEur: priceEur, title: label),
    );
    if (choice == null || !mounted) return;

    final store = context.read<TvdeStore>();
    final messenger = ScaffoldMessenger.of(context);

    // ── MB Way ──────────────────────────────────────────────────────────────
    if (choice.method == ReservationPaymentMethod.mbway) {
      final created =
          await store.createPlanPaymentMbway(plan, choice.mbwayPhone!);
      if (!mounted) return;
      if (created == null) {
        messenger.showSnackBar(SnackBar(
            content: Text('Não foi possível iniciar o MBWay. Confirma o número e tenta de novo.'.tr)));
        return;
      }
      final ok = await showDialog<bool>(
        context: context,
        barrierDismissible: false,
        builder: (_) => PlanMbwayWaitingDialog(
          plan: plan,
          paymentIntentId: created['paymentIntentId'] as String,
          amount: priceEur,
        ),
      );
      if (!mounted) return;
      messenger.showSnackBar(SnackBar(
          content: Text(ok == true
              ? 'Plano ativo! Já podes usar as corridas incluídas.'.tr
              : 'Não recebemos a confirmação MBWay. Se pagaste, reabre os Planos; senão tenta de novo.'.tr)));
      return;
    }

    // ── Cartão (Stripe) ─────────────────────────────────────────────────────
    // 1) Cria o PaymentIntent do plano (Edge Function isolada).
    final created = await store.createPlanPayment(plan);
    if (!mounted) return;
    if (created == null) {
      messenger.showSnackBar(SnackBar(
          content: Text('Não foi possível iniciar o pagamento. Tenta de novo.'.tr)));
      return;
    }

    // 2) Folha de pagamento Stripe (cartão). Lança em cancelamento/erro.
    try {
      await PaymentService().processPayment(created['clientSecret'] as String);
    } catch (_) {
      if (!mounted) return;
      messenger.showSnackBar(SnackBar(
          content: Text('Pagamento não concluído.'.tr)));
      return;
    }

    // 3) Ativa a subscrição — a Edge Function reverifica o PI na Stripe.
    try {
      await store.activatePlan(plan, created['paymentIntentId'] as String);
      if (!mounted) return;
      messenger.showSnackBar(SnackBar(
          content: Text('Plano ativo! Já podes usar as corridas incluídas.'.tr)));
    } catch (_) {
      if (!mounted) return;
      messenger.showSnackBar(SnackBar(
          content: Text('O pagamento foi feito, mas a ativação falhou. Reabre os Planos para confirmar, ou contacta o suporte.'.tr)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final store = context.watch<TvdeStore>();
    final sub = store.subscription;
    final pending = store.planRequestStatus == 'pendente';

    return Scaffold(
      appBar: BoraScreenAppBar(title: 'Planos'.tr),
      body: ListView(
        padding: const EdgeInsets.all(Spacing.lg),
        children: [
          if (sub != null) _ActiveSubscription(sub: sub, dailyUsed: store.dailyUsed),
          if (sub != null) const SizedBox(height: Spacing.lg),
          if (pending) ...[
            _PendingBanner(),
            const SizedBox(height: Spacing.lg),
          ],
          Text('Planos disponíveis'.tr,
              style: const TextStyle(
                  fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
          const SizedBox(height: Spacing.sm),
          const _WeekdayNotice(),
          const SizedBox(height: Spacing.sm),
          _PlanCard(
            title: 'Plano Semanal'.tr,
            price: _priceLabel('semanal'),
            detail: _detailLabel('semanal'),
            onAderir: pending || store.busy || _priceCents == null
                ? null
                : () => _aderir(
                    'semanal', 'Plano Semanal'.tr, _priceCents!['semanal']! / 100),
          ),
          _PlanCard(
            title: 'Plano Quinzenal'.tr,
            price: _priceLabel('quinzenal'),
            detail: _detailLabel('quinzenal'),
            onAderir: pending || store.busy || _priceCents == null
                ? null
                : () => _aderir('quinzenal', 'Plano Quinzenal'.tr,
                    _priceCents!['quinzenal']! / 100),
          ),
          _PlanCard(
            title: 'Plano Mensal'.tr,
            price: _priceLabel('mensal'),
            detail: _detailLabel('mensal'),
            onAderir: pending || store.busy || _priceCents == null
                ? null
                : () => _aderir(
                    'mensal', 'Plano Mensal'.tr, _priceCents!['mensal']! / 100),
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
              'Pedido de adesão enviado. A equipa Bora vai ativar o teu plano em breve.'.tr,
              style: const TextStyle(color: AppColors.textSecondary, fontSize: 13),
            ),
          ),
        ],
      ),
    );
  }
}

/// Aviso fixo: os planos só cobrem Segunda a Sexta (2 corridas/dia útil).
/// Fim de semana fica de fora — nesses dias o cliente paga a tarifa normal.
class _WeekdayNotice extends StatelessWidget {
  const _WeekdayNotice();

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
          const Icon(Icons.event_available, color: AppColors.primary),
          const SizedBox(width: Spacing.md),
          Expanded(
            child: Text(
              'Válido Segunda a Sexta. Aos fins de semana (sábado e domingo) as corridas não são cobertas pelo plano — paga-se a tarifa normal.'.tr,
              style: const TextStyle(color: AppColors.textSecondary, fontSize: 12.5),
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
          const SizedBox(height: 2),
          Text('Segunda a Sexta · fim de semana não incluído'.tr,
              style: const TextStyle(color: Colors.white70, fontSize: 11.5)),
          const SizedBox(height: Spacing.md),
          _row('Hoje'.tr, '{0} de {1} corridas restantes'.trArgs([remainingToday, sub.dailyIncluded])),
          const SizedBox(height: 4),
          _row('Plano'.tr, '{0} de {1} corridas restantes'.trArgs([sub.ridesLeft, sub.ridesTotal])),
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
              style: const TextStyle(fontSize: 12, color: AppColors.textSubtle)),
          const SizedBox(height: Spacing.sm),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: onAderir,
              icon: const Icon(Icons.add_card, size: 18),
              label: Text('Quero aderir'.tr),
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
