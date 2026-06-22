// 8.2 — Banner de autorização de orçamento (cliente).
// Aparece SÓ quando errand com compra está com `errand_budget_status='pending'`
// (estafeta pediu aumento ANTES de comprar — timing A). O cliente Autoriza ou
// Recusa via RPC client_respond_budget_increase. Auto-esconde após responder.
// Self-contained: seguro para montar em qualquer ecrã que tenha a OrderModel viva.
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../config/app_colors.dart';
import '../models/order_model.dart';

class ErrandBudgetBanner extends StatefulWidget {
  const ErrandBudgetBanner({super.key, required this.order});
  final OrderModel order;

  @override
  State<ErrandBudgetBanner> createState() => _ErrandBudgetBannerState();
}

class _ErrandBudgetBannerState extends State<ErrandBudgetBanner> {
  bool _responded = false;
  bool _busy = false;

  Future<void> _respond(bool approve) async {
    setState(() => _busy = true);
    try {
      await Supabase.instance.client.rpc(
        'client_respond_budget_increase',
        params: {'p_order_id': widget.order.id, 'p_approve': approve},
      );
      if (!mounted) return;
      setState(() => _responded = true);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(approve
            ? 'Compra maior autorizada. O estafeta vai prosseguir.'
            : 'Recusaste. O estafeta não vai comprar.'),
      ));
    } catch (e) {
      if (!mounted) return;
      setState(() => _busy = false);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(
            'Não foi possível responder: ${e.toString().replaceFirst('Exception: ', '')}'),
        backgroundColor: AppColors.error,
      ));
    }
  }

  @override
  Widget build(BuildContext context) {
    final o = widget.order;
    if (_responded ||
        o.serviceType != OrderServiceType.errand ||
        o.errandBudgetStatus != 'pending') {
      return const SizedBox.shrink();
    }

    final requested = (o.errandBudgetRequestedCents ?? 0) / 100.0;
    final estimated = o.errandEstimatedPurchaseCents / 100.0;

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.primaryWash,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.primary),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.shopping_bag_outlined,
                  color: AppColors.primary, size: 20),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Autorizar compra maior?',
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            'O estafeta precisa de ~€${requested.toStringAsFixed(2)} '
            '(orçaste €${estimated.toStringAsFixed(2)}). Pagas o valor do talão.',
            style: const TextStyle(fontSize: 13),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: _busy ? null : () => _respond(false),
                  child: const Text('Recusar'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: ElevatedButton(
                  onPressed: _busy ? null : () => _respond(true),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    foregroundColor: AppColors.textOnPrimary,
                  ),
                  child: _busy
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: Colors.white))
                      : const Text('Autorizar'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
