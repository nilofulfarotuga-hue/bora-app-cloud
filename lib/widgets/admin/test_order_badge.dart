import 'package:flutter/material.dart';

/// Badge visual para indicar pedidos de teste no painel admin.
///
/// Uso:
///   if (order.isTestOrder) const TestOrderBadge(),
///
/// Visual: pequeno chip laranja com icone de tubo de ensaio.
/// Texto em PT-BR (admin only).
///
/// Comentarios em PT-PT (regra do projecto).
class TestOrderBadge extends StatelessWidget {
  const TestOrderBadge({super.key, this.compact = false});

  /// Se true, mostra apenas icone (sem texto). Util em listas densas.
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: compact ? 4 : 8,
        vertical: 2,
      ),
      decoration: BoxDecoration(
        color: Colors.orange.shade100,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.orange.shade400, width: 1),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.science_outlined,
            size: compact ? 12 : 14,
            color: Colors.orange.shade800,
          ),
          if (!compact) ...[
            const SizedBox(width: 4),
            Text(
              'TESTE',
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.bold,
                color: Colors.orange.shade900,
                letterSpacing: 0.5,
              ),
            ),
          ],
        ],
      ),
    );
  }
}
