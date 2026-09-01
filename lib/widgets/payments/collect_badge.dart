import 'package:flutter/material.dart';

import '../../config/app_colors.dart';

import '../../l10n/tr.dart';

/// Estado de cobrança que o EXECUTOR (estafeta / motorista / profissional de
/// limpeza) vê. Um estado explícito para cada caso — nunca "nada" (era o bug
/// do delivery: card/MB Way não mostrava sinal e arriscava cobrar 2×).
enum CollectState {
  /// Cliente paga em dinheiro na entrega/no fim → cobrar o valor.
  collectCash,

  /// Já pago no app (cartão / MB Way) → NÃO cobrar.
  paidOnline,

  /// Coberto por plano/subscrição (cliente paga €0) → NÃO cobrar.
  coveredByPlan,
}

/// Badge ÚNICO do executor, partilhado por delivery, TVDE e limpeza. Mesma
/// redação, cor e ícone nas três verticais. Para [CollectState.collectCash] o
/// [amountCents] é OBRIGATÓRIO (assert) — impossível mostrar um badge de
/// dinheiro sem dizer quanto.
class CollectBadge extends StatelessWidget {
  const CollectBadge({
    super.key,
    required this.state,
    this.amountCents,
    this.approx = false,
    this.dense = false,
  }) : assert(state != CollectState.collectCash || amountCents != null,
            'collectCash exige amountCents (o valor a cobrar).');

  final CollectState state;

  /// Valor a cobrar em cêntimos (só usado em [CollectState.collectCash]).
  final int? amountCents;

  /// Prefixa "~" (valor ainda estimado, ex.: TVDE antes do fim).
  final bool approx;

  /// Versão compacta (sem caixa), para cartões de oferta.
  final bool dense;

  @override
  Widget build(BuildContext context) {
    final bool collect = state == CollectState.collectCash;
    final Color color = collect ? Colors.orange.shade900 : AppColors.primary;

    final IconData icon;
    final String text;
    if (collect) {
      icon = Icons.payments_outlined;
      final v = ((amountCents ?? 0) / 100).toStringAsFixed(2);
      text = 'COBRAR EM DINHEIRO: {0}€{1}'.trArgs([approx ? '~' : '', v]);
    } else if (state == CollectState.paidOnline) {
      icon = Icons.check_circle_outline;
      text = 'JÁ PAGO NA APP — não cobrar'.tr;
    } else {
      icon = Icons.card_membership;
      text = 'COBERTO PELO PLANO — não cobrar'.tr;
    }

    final row = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 16, color: color),
        const SizedBox(width: 6),
        Flexible(
          child: Text(
            text,
            style: TextStyle(
                color: color, fontSize: 13, fontWeight: FontWeight.w700),
          ),
        ),
      ],
    );

    if (dense) return row;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      decoration: BoxDecoration(
        color: collect
            ? Colors.orange.withValues(alpha: 0.12)
            : AppColors.primary.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(8),
      ),
      child: row,
    );
  }
}
