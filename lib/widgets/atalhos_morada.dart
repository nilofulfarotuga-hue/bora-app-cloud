import 'package:flutter/material.dart';

import '../config/app_colors.dart';
import '../services/atalhos_morada_service.dart';

/// Linha de chips com as moradas guardadas e os destinos recentes, por baixo
/// de um campo de morada (missão tvde-pedir-nunca-trava, 14/10/2026). Um toque
/// preenche o campo com a morada E as coordenadas — igual ao Uber/Bolt.
/// Sem atalhos, não ocupa espaço nenhum.
class AtalhosMorada extends StatelessWidget {
  const AtalhosMorada({
    super.key,
    required this.atalhos,
    required this.onEscolher,
    this.prefixoChave = 'atalho',
  });

  final List<AtalhoMorada> atalhos;
  final ValueChanged<AtalhoMorada> onEscolher;

  /// Distingue as duas linhas (recolha/destino) nos testes e na prova web.
  final String prefixoChave;

  IconData _icone(AtalhoMorada a) {
    if (a.recente) return Icons.history;
    final r = a.rotulo.toLowerCase();
    if (r.contains('casa')) return Icons.home_outlined;
    if (r.contains('trabalho')) return Icons.work_outline;
    return Icons.bookmark_border;
  }

  @override
  Widget build(BuildContext context) {
    if (atalhos.isEmpty) return const SizedBox.shrink();
    // ListView horizontal (nunca Row): com fonte grande ou muitos atalhos
    // uma Row estoura para fora do ecrã.
    return SizedBox(
      height: 40,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: atalhos.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (context, i) {
          final a = atalhos[i];
          return ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 200),
            child: ActionChip(
              key: ValueKey('${prefixoChave}_$i'),
              avatar: Icon(_icone(a), size: 18, color: AppColors.primary),
              label: Text(
                a.rotulo,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              tooltip: a.morada,
              visualDensity: VisualDensity.compact,
              onPressed: () => onEscolher(a),
            ),
          );
        },
      ),
    );
  }
}
