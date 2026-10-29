/// "ESTADO DOS TEUS DOCUMENTOS" na app do candidato (missão final-app-2026-10-29,
/// adendo 3, R8). PT-PT, "tu".
///
/// Aparece dentro de "Conta em análise" (estafeta, limpeza, lavagem, serviços) e
/// mostra, por documento, o estado, o motivo do robô e um botão para enviar de
/// novo SÓ aquele. Só aparece quando o robô está a agir: com o robô em sombra ou
/// desligado, a app não diz nada dele. Falha aberta: sem rede, não mostra nada.
library;

import 'package:flutter/material.dart';

import '../config/app_colors.dart';
import '../services/robo_documentos.dart';
import '../services/robo_documentos_service.dart';

class RoboDocumentosEstadoCard extends StatefulWidget {
  const RoboDocumentosEstadoCard({super.key, this.carregar, this.aoReenviar});

  /// Só para testes: troca o servidor.
  final Future<EstadoDocumentosApp?> Function()? carregar;

  /// Chamado com o campo do documento quando a pessoa toca "Enviar de novo".
  /// null = sem botão. Deve devolver quando o envio acabar (a lista recarrega).
  final Future<void> Function(String campo)? aoReenviar;

  @override
  State<RoboDocumentosEstadoCard> createState() => _RoboDocumentosEstadoCardState();
}

class _RoboDocumentosEstadoCardState extends State<RoboDocumentosEstadoCard> {
  EstadoDocumentosApp? _estado;
  String? _aEnviar;

  @override
  void initState() {
    super.initState();
    _carregar();
  }

  Future<void> _carregar() async {
    final e = await (widget.carregar?.call() ?? RoboDocumentosApp.estado());
    if (!mounted) return;
    setState(() => _estado = e);
  }

  Future<void> _reenviar(String campo) async {
    final cb = widget.aoReenviar;
    if (cb == null || _aEnviar != null) return;
    setState(() => _aEnviar = campo);
    try {
      await cb(campo);
    } finally {
      if (mounted) setState(() => _aEnviar = null);
    }
    await _carregar();
  }

  @override
  Widget build(BuildContext context) {
    final e = _estado;
    if (e == null || !e.ativo || e.itens.isEmpty) return const SizedBox.shrink();
    return Container(
      key: const Key('robo-estado-documentos'),
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.divider),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Estado dos teus documentos',
              style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
          const SizedBox(height: 4),
          Text(
            'Vemos cada documento assim que o envias. A aprovação final é sempre feita por uma pessoa.',
            style: TextStyle(color: Colors.grey.shade700, fontSize: 13),
          ),
          const SizedBox(height: 8),
          for (final i in e.itens) _linha(i),
        ],
      ),
    );
  }

  Widget _linha(DocumentoEstadoApp i) {
    final cor = i.precisaDeNovo
        ? AppColors.error
        : (i.decisao == 'ok' ? AppColors.success : AppColors.textSecondary);
    final icone = i.precisaDeNovo
        ? Icons.error_outline
        : (i.decisao == 'ok' ? Icons.check_circle_outline : Icons.hourglass_top);
    return Padding(
      key: Key('robo-doc-${i.campo}'),
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icone, color: cor, size: 20),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(i.rotulo, style: const TextStyle(fontWeight: FontWeight.w600)),
                Text(i.estado, style: TextStyle(color: cor, fontSize: 13)),
                if (i.precisaDeNovo && i.motivoPt != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(i.motivoPt!, style: const TextStyle(fontSize: 13)),
                  ),
              ],
            ),
          ),
          if (i.precisaDeNovo && widget.aoReenviar != null)
            _aEnviar == i.campo
                ? const SizedBox(
                    width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2))
                : OutlinedButton(
                    key: Key('robo-reenviar-${i.campo}'),
                    onPressed: _aEnviar != null ? null : () => _reenviar(i.campo),
                    child: const Text('Enviar de novo'),
                  ),
        ],
      ),
    );
  }
}
