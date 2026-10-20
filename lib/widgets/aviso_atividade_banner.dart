/// Aviso "Falta o comprovativo de atividade" no ecrã principal do prestador
/// (estafeta, motorista TVDE, limpeza, lavagem, serviços) — Bloco C · 20/10/2026.
///
/// NUNCA bloqueia: é um cartão no meio do ecrã, o resto continua a funcionar.
/// Sem rede, com erro ou com o comprovativo em dia, não aparece nada (falha
/// aberta). O botão "Enviar" abre o ecrã do comprovativo; ao voltar, relê.
///
/// Ronda 1 da revisão (20/10): "Podes continuar a trabalhar" só a quem já
/// trabalha ([emCandidatura] = false); quem está em candidatura lê que é isto
/// que falta para a candidatura seguir. Nos ecrãs com a lista de trabalho por
/// baixo (estafeta, TVDE) o aviso é [compacto] — uma linha + botão — e
/// [dispensavel] na sessão: o "×" esconde-o até a app voltar a abrir (não para
/// sempre: o comprovativo continua a faltar e o aviso volta).
library;

import 'package:flutter/material.dart';

import '../config/app_colors.dart';
import '../screens/shared/comprovativo_atividade_screen.dart';
import '../services/atividade_service.dart';

/// Título do aviso (função pura, testada).
String tituloDoAvisoAtividade(AtividadeEstado e) =>
    e.status == AtividadeStatus.recusada
        ? 'Comprovativo de atividade recusado'
        : 'Falta o comprovativo de atividade';

/// Texto do aviso (função pura, testada). PT-PT.
String textoDoAvisoAtividade(AtividadeEstado e, {required bool emCandidatura}) {
  final motivo = e.motivo == null ? '' : ': ${e.motivo}';
  if (e.status == AtividadeStatus.recusada) {
    return emCandidatura
        ? 'O teu comprovativo foi recusado$motivo. Envia outro para a tua candidatura seguir.'
        : 'O teu comprovativo foi recusado$motivo. Envia outro — podes continuar a trabalhar.';
  }
  return emCandidatura
      ? 'Envia o NIF e uma foto ou PDF do comprovativo de atividade aberta nas Finanças. '
          'É o que falta para a tua candidatura seguir.'
      : 'Envia o NIF e uma foto ou PDF do comprovativo de atividade aberta nas Finanças. '
          'Podes continuar a trabalhar.';
}

class AvisoAtividadeBanner extends StatefulWidget {
  const AvisoAtividadeBanner({
    super.key,
    this.carregar,
    this.abrir,
    this.margem = const EdgeInsets.fromLTRB(16, 8, 16, 8),
    this.emCandidatura = false,
    this.compacto = false,
    this.dispensavel = false,
  });

  /// Margem à volta do cartão (cada ecrã tem o seu espaçamento).
  final EdgeInsetsGeometry margem;

  /// A pessoa ainda está em candidatura (não trabalha): texto próprio.
  final bool emCandidatura;

  /// Uma linha + botão (ecrãs com a lista de trabalho por baixo).
  final bool compacto;

  /// Mostra o "×" que o esconde até a app voltar a abrir.
  final bool dispensavel;

  /// Injeção para os testes (por defeito, o servidor).
  final CarregarAtividade? carregar;

  /// Injeção para os testes (por defeito, abre [ComprovativoAtividadeScreen]).
  final Future<void> Function(BuildContext context)? abrir;

  /// Escondido nesta sessão pelo "×" (memória, não disco: volta na próxima
  /// abertura da app).
  static bool dispensadoNestaSessao = false;

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

  void _dispensar() {
    AvisoAtividadeBanner.dispensadoNestaSessao = true;
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final e = _estado;
    if (e == null || !e.mostrarAviso) return const SizedBox.shrink();
    if (widget.dispensavel && AvisoAtividadeBanner.dispensadoNestaSessao) {
      return const SizedBox.shrink();
    }
    final titulo = tituloDoAvisoAtividade(e);
    final botao = FilledButton(
      key: const Key('aviso-atividade-enviar'),
      onPressed: _abrir,
      style: widget.compacto
          ? FilledButton.styleFrom(
              visualDensity: VisualDensity.compact,
              padding: const EdgeInsets.symmetric(horizontal: 14),
            )
          : null,
      child: const Text('Enviar'),
    );
    final fechar = widget.dispensavel
        ? IconButton(
            key: const Key('aviso-atividade-fechar'),
            tooltip: 'Esconder até voltares a abrir a app',
            visualDensity: VisualDensity.compact,
            onPressed: _dispensar,
            icon: const Icon(Icons.close, size: 18),
          )
        : null;
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
        padding: widget.compacto
            ? const EdgeInsets.fromLTRB(12, 4, 4, 4)
            : const EdgeInsets.fromLTRB(14, 12, 10, 12),
        child: Row(
          children: [
            Icon(Icons.description_outlined,
                color: AppColors.textPrimary, size: widget.compacto ? 18 : 24),
            const SizedBox(width: 10),
            Expanded(
              child: widget.compacto
                  ? Text(
                      titulo,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          fontWeight: FontWeight.w700, fontSize: 13),
                    )
                  : Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(titulo,
                            style:
                                const TextStyle(fontWeight: FontWeight.w700)),
                        const SizedBox(height: 2),
                        Text(
                            textoDoAvisoAtividade(e,
                                emCandidatura: widget.emCandidatura),
                            style: const TextStyle(fontSize: 13)),
                      ],
                    ),
            ),
            const SizedBox(width: 8),
            botao,
            if (fechar != null) fechar,
          ],
        ),
      ),
    );
  }
}
