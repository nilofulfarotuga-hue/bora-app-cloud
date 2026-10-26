import 'package:flutter/material.dart';

import '../config/app_colors.dart';
import '../screens/driver/tvde/tvde_conformidade_screen.dart';
import '../services/driver_documentos.dart' show DocEmFalta;
import '../services/prestador_documentos.dart';
import '../services/tvde_conformidade_service.dart';

/// Motorista TVDE com a candidatura em análise: o que falta da conformidade
/// TVDE (certificado, carta, operador e contrato, carro, seguro, inspeção…)
/// e um botão que abre o ecrã onde se envia tudo isso — o mesmo que o
/// motorista aprovado usa (missão docs-reenvio-26-10).
///
/// A lista são os impedimentos que o servidor calcula
/// (`tvde_minha_conformidade`), a mesma conta que o painel mostra em
/// "Impede de trabalhar". Falha aberta: sem rede, não mostra nada.
class TvdeConformidadeEmFalta extends StatefulWidget {
  const TvdeConformidadeEmFalta({super.key, this.carregar});

  /// Só para testes: substitui `tvde_minha_conformidade`.
  @visibleForTesting
  final Future<Map<String, dynamic>> Function()? carregar;

  @override
  State<TvdeConformidadeEmFalta> createState() =>
      _TvdeConformidadeEmFaltaState();
}

class _TvdeConformidadeEmFaltaState extends State<TvdeConformidadeEmFalta> {
  List<DocEmFalta>? _falta;
  bool _carregando = true;

  @override
  void initState() {
    super.initState();
    _carregar();
  }

  Future<void> _carregar() async {
    List<DocEmFalta>? f;
    try {
      f = motivosTvdeEmFalta(await (widget.carregar?.call() ??
          TvdeConformidadeService.instance.minhaConformidade()));
    } catch (e) {
      debugPrint('[TvdeConformidadeEmFalta] $e');
      f = null; // falha aberta
    }
    if (!mounted) return;
    setState(() {
      _falta = f;
      _carregando = false;
    });
  }

  Future<void> _abrir() async {
    await Navigator.of(context).push(MaterialPageRoute<void>(
        builder: (_) => const TvdeConformidadeScreen()));
    if (mounted) await _carregar();
  }

  @override
  Widget build(BuildContext context) {
    if (_carregando) {
      return const Padding(
        padding: EdgeInsets.all(12),
        child: SizedBox(
            width: 22,
            height: 22,
            child: CircularProgressIndicator(strokeWidth: 2)),
      );
    }
    final falta = _falta;
    if (falta == null) return const SizedBox.shrink();
    if (falta.isEmpty) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: AppColors.success.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(12),
        ),
        child: const Row(
          children: [
            Icon(Icons.check_circle, color: AppColors.success),
            SizedBox(width: 10),
            Expanded(
              child: Text('Os documentos TVDE estão completos. Agora é só '
                  'esperar pela análise.'),
            ),
          ],
        ),
      );
    }
    return Container(
      key: const Key('tvde_conformidade_em_falta'),
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.red.shade50,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.red.shade200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Documentos TVDE em falta',
            style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
          ),
          const SizedBox(height: 4),
          const Text(
            'A lei pede isto a quem conduz em TVDE. Envia tudo no ecrã da '
            'Conformidade TVDE.',
            style: TextStyle(color: AppColors.textSecondary, fontSize: 13),
          ),
          const SizedBox(height: 8),
          for (final item in falta)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(Icons.error_outline,
                      color: AppColors.error, size: 20),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Falta: ${minusculaInicial(item.rotulo)}',
                      style: const TextStyle(
                          color: AppColors.error, fontWeight: FontWeight.w600),
                    ),
                  ),
                ],
              ),
            ),
          const SizedBox(height: 10),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              key: const Key('tvde_conformidade_enviar_agora'),
              onPressed: _abrir,
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.primary,
                padding: const EdgeInsets.symmetric(vertical: 12),
              ),
              icon: const Icon(Icons.upload_file),
              label: const Text('Enviar agora'),
            ),
          ),
        ],
      ),
    );
  }
}
