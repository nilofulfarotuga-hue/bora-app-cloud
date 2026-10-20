/// Aviso "Falta o comprovativo de atividade" no ecrã principal do prestador
/// (estafeta, motorista TVDE, limpeza, lavagem, serviços) — Bloco C · 20/10/2026.
///
/// NUNCA bloqueia: é um cartão no meio do ecrã, o resto continua a funcionar.
/// Sem rede, com erro ou com o comprovativo em dia, não aparece nada (falha
/// aberta). O botão "Enviar" abre o ecrã do comprovativo; ao voltar, relê.
library;

import 'package:flutter/material.dart';

import '../config/app_colors.dart';
import '../screens/shared/comprovativo_atividade_screen.dart';
import '../services/atividade_service.dart';

class AvisoAtividadeBanner extends StatefulWidget {
  const AvisoAtividadeBanner({
    super.key,
    this.carregar,
    this.abrir,
    this.margem = const EdgeInsets.fromLTRB(16, 8, 16, 8),
  });

  /// Margem à volta do cartão (cada ecrã tem o seu espaçamento).
  final EdgeInsetsGeometry margem;

  /// Injeção para os testes (por defeito, o servidor).
  final CarregarAtividade? carregar;

  /// Injeção para os testes (por defeito, abre [ComprovativoAtividadeScreen]).
  final Future<void> Function(BuildContext context)? abrir;

  @override
  State<AvisoAtividadeBanner> createState() => _AvisoAtividadeBannerState();
}

class _AvisoAtividadeBannerState extends State<AvisoAtividadeBanner> {
  AtividadeEstado? _estado;

  @override
  void initState() {
    super.initState();
    _carregar();
  }

  Future<void> _carregar() async {
    AtividadeEstado? e;
    try {
      e = await (widget.carregar ?? AtividadeService.carregar)()
          .timeout(const Duration(seconds: 10));
    } catch (_) {
      e = null; // falha aberta
    }
    if (!mounted) return;
    setState(() => _estado = e);
  }

  Future<void> _abrir() async {
    final abrir = widget.abrir;
    if (abrir != null) {
      await abrir(context);
    } else {
      await Navigator.of(context).push(MaterialPageRoute<void>(
        builder: (_) => const ComprovativoAtividadeScreen(),
      ));
    }
    if (mounted) await _carregar();
  }

  @override
  Widget build(BuildContext context) {
    final e = _estado;
    if (e == null || !e.mostrarAviso) return const SizedBox.shrink();
    final recusado = e.status == AtividadeStatus.recusada;
    final texto = recusado
        ? 'O teu comprovativo foi recusado${e.motivo == null ? '' : ': ${e.motivo}'}. '
            'Envia outro — podes continuar a trabalhar.'
        : 'Envia o NIF e uma foto ou PDF do comprovativo de atividade aberta nas '
            'Finanças. Podes continuar a trabalhar.';
    return Card(
      key: const Key('aviso-atividade'),
      margin: widget.margem,
      color: AppColors.warning.withValues(alpha: 0.10),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: AppColors.warning.withValues(alpha: 0.45)),
      ),
      elevation: 0,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 12, 10, 12),
        child: Row(
          children: [
            const Icon(Icons.description_outlined,
                color: AppColors.textPrimary),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    recusado
                        ? 'Comprovativo de atividade recusado'
                        : 'Falta o comprovativo de atividade',
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 2),
                  Text(texto, style: const TextStyle(fontSize: 13)),
                ],
              ),
            ),
            const SizedBox(width: 8),
            FilledButton(
              key: const Key('aviso-atividade-enviar'),
              onPressed: _abrir,
              child: const Text('Enviar'),
            ),
          ],
        ),
      ),
    );
  }
}
