/// Variante web da folha de execução de favores.
///
/// A execução de um favor (recolher dinheiro, comprar, fotografar o talão,
/// entregar) é do estafeta e depende de câmara e GPS do telemóvel — além de
/// correr por cima de `_finalizePurchase`, que é zona protegida. Na web
/// mostramos uma mensagem honesta em vez de meia funcionalidade.
///
/// Mantém a mesma API pública da folha real (`ErrandExecutionSheet.show`),
/// para o `driver_home_screen` compilar sem alterações no call-site.
library;

import 'package:flutter/material.dart';

import '../config/app_colors.dart';
import '../models/order_model.dart';

class ErrandExecutionSheet extends StatelessWidget {
  const ErrandExecutionSheet({super.key, required this.order});

  final OrderModel order;

  static Future<void> show(BuildContext context, OrderModel order) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => ErrandExecutionSheet(order: order),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 28, 24, 32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.phone_iphone, size: 40, color: AppColors.primary),
          const SizedBox(height: 16),
          const Text(
            'Executa este favor na aplicação',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 10),
          const Text(
            'A compra e o talão precisam da câmara e do GPS do telemóvel. '
            'Abre o Bora no telemóvel para continuar este favor.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 14, color: AppColors.textSecondary),
          ),
          const SizedBox(height: 24),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Entendi'),
            ),
          ),
        ],
      ),
    );
  }
}
