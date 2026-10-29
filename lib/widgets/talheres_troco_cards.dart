import 'package:flutter/material.dart';

import '../config/app_colors.dart';
import '../config/app_spacing.dart';
import '../l10n/tr.dart';

/// "Talheres e guardanapos" no pagamento (paridade pequena 1, 29/10/2026).
///
/// Desligado por defeito: só vão talheres se o cliente pedir. Verde quando
/// ligado, nunca laranja (uma só cor laranja por ecrã).
class TalheresCard extends StatelessWidget {
  const TalheresCard({super.key, required this.precisa, required this.onChanged});

  final bool precisa;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      key: const Key('cartao_talheres'),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(Radii.lg),
        boxShadow: AppColors.shadowCard,
      ),
      padding: const EdgeInsets.fromLTRB(16, 8, 8, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SwitchListTile.adaptive(
            key: const Key('interruptor_talheres'),
            value: precisa,
            onChanged: onChanged,
            contentPadding: EdgeInsets.zero,
            activeThumbColor: AppColors.primary,
            title: Text(
              'Talheres e guardanapos'.tr,
              style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
            ),
            subtitle: Text(
              'Preciso de talheres e guardanapos'.tr,
              style: const TextStyle(fontSize: 16),
            ),
          ),
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: Text(
              'Se não precisares, poupas plástico e ajudas a loja. Só enviamos se pedires.'
                  .tr,
              style: const TextStyle(
                  fontSize: 16, color: AppColors.textSecondary, height: 1.3),
            ),
          ),
        ],
      ),
    );
  }
}

/// "Com que nota vais pagar?" quando o método é dinheiro (paridade pequena 2).
///
/// Só acrescenta uma linha à nota do pedido; não muda nenhum valor. As notas
/// que aparecem são as maiores que o total (ver `NotaDoPedido.notasParaTroco`).
class TrocoCard extends StatelessWidget {
  const TrocoCard({
    super.key,
    required this.notas,
    required this.escolhida,
    required this.onChanged,
  });

  /// Notas oferecidas (já filtradas pelo total do pedido).
  final List<int> notas;

  /// Nota escolhida; `null` = valor certo.
  final int? escolhida;
  final ValueChanged<int?> onChanged;

  @override
  Widget build(BuildContext context) {
    if (notas.isEmpty) return const SizedBox.shrink();
    return Container(
      key: const Key('cartao_troco'),
      margin: const EdgeInsets.only(top: 8),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(Radii.lg),
        boxShadow: AppColors.shadowCard,
      ),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Com que nota vais pagar?'.tr,
            style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _ChipNota(
                chave: const Key('chip_troco_certo'),
                texto: 'Valor certo'.tr,
                ativo: escolhida == null,
                onTap: () => onChanged(null),
              ),
              for (final n in notas)
                _ChipNota(
                  chave: Key('chip_troco_$n'),
                  texto: '$n €',
                  ativo: escolhida == n,
                  onTap: () => onChanged(n),
                ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            'Avisamos o estafeta, mas o troco depende dele. Se puderes, paga com o valor certo.'
                .tr,
            style: const TextStyle(
                fontSize: 16, color: AppColors.textSecondary, height: 1.3),
          ),
        ],
      ),
    );
  }
}

class _ChipNota extends StatelessWidget {
  const _ChipNota({
    required this.chave,
    required this.texto,
    required this.ativo,
    required this.onTap,
  });

  final Key chave;
  final String texto;
  final bool ativo;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      selected: ativo,
      label: texto,
      child: InkWell(
        key: chave,
        borderRadius: BorderRadius.circular(24),
        onTap: onTap,
        child: Container(
          constraints: const BoxConstraints(minHeight: 44, minWidth: 64),
          alignment: Alignment.center,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          decoration: BoxDecoration(
            color: ativo ? AppColors.primary : Colors.transparent,
            borderRadius: BorderRadius.circular(24),
            border: Border.all(
                color: ativo ? AppColors.primary : AppColors.divider),
          ),
          child: Text(
            texto,
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: ativo ? Colors.white : AppColors.textPrimary,
            ),
          ),
        ),
      ),
    );
  }
}
