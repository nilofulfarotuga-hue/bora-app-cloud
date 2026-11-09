import 'package:flutter/material.dart';

import '../config/app_colors.dart';
import '../services/trabalho_em_curso.dart';

/// "Próxima limpeza: sábado 14:00" — o cartão pequeno do trabalho aceite para
/// outro dia (missão m2, 08/11/2026). Antes este trabalho aparecia na faixa
/// "Limpeza a decorrer — aceite — a caminho" dias a fio, por cima de tudo.
/// Sem trabalho para mais tarde (ou sem rede), não aparece.
class ProximoTrabalhoCard extends StatefulWidget {
  const ProximoTrabalhoCard({
    super.key,
    required this.categoria,
    this.margem,
    this.carregar,
  });

  /// 'limpeza' | 'lavagem'.
  final String categoria;
  final EdgeInsetsGeometry? margem;

  /// Só para testes: troca o servidor.
  final Future<TrabalhoEmCurso?> Function()? carregar;

  @override
  State<ProximoTrabalhoCard> createState() => _ProximoTrabalhoCardState();
}

class _ProximoTrabalhoCardState extends State<ProximoTrabalhoCard> {
  TrabalhoEmCurso? _t;

  @override
  void initState() {
    super.initState();
    _carregar();
  }

  Future<void> _carregar() async {
    final t = await (widget.carregar?.call() ??
        lerProximoTrabalho(widget.categoria));
    if (!mounted) return;
    setState(() => _t = t);
  }

  @override
  Widget build(BuildContext context) {
    final t = _t;
    if (t == null) return const SizedBox.shrink();
    return Padding(
      padding: widget.margem ?? EdgeInsets.zero,
      child: Container(
        key: const Key('proximo_trabalho_card'),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: AppColors.primary.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(
          children: [
            const Icon(Icons.event_available, color: AppColors.primary, size: 20),
            const SizedBox(width: 10),
            Expanded(
              child: Text(t.textoProxima,
                  style: const TextStyle(fontWeight: FontWeight.w700)),
            ),
          ],
        ),
      ),
    );
  }
}
