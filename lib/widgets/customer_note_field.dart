import 'package:flutter/material.dart';

import '../config/app_colors.dart';
import '../config/app_spacing.dart';

import '../l10n/tr.dart';

/// Campo "Nota para o estafeta/motorista (opcional)" partilhado entre os fluxos
/// de pagamento (delivery/limpeza e TVDE) para garantir estilo, comportamento e
/// limite de caracteres idênticos. Só recolhe texto livre — nunca toca em
/// tarifa/pagamento. Ler `.text` do [controller] após o pedido criado.
class CustomerNoteField extends StatelessWidget {
  const CustomerNoteField({
    super.key,
    required this.controller,
    this.title = 'Nota para o estafeta (opcional)',
    this.hint = 'Ex.: deixar na portaria, não tocar à campainha',
  });

  final TextEditingController controller;
  final String title;
  final String hint;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(Radii.lg),
        boxShadow: AppColors.shadowCard,
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title.tr,
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: controller,
              maxLines: 2,
              maxLength: 200,
              textInputAction: TextInputAction.done,
              decoration: InputDecoration(
                hintText: hint.tr,
                border: const OutlineInputBorder(),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
