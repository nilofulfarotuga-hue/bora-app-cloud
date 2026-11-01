import 'package:flutter/material.dart';

import '../../config/app_colors.dart';
import '../../config/app_spacing.dart';
import '../../l10n/tr.dart';
import '../../models/casa_models.dart';
import '../../utils/hora_lisboa.dart';

/// Peças de ecrã partilhadas pelos ecrãs do profissional da Casa.

/// "30 min", "1 h", "1 h 30".
String casaDuracaoTexto(int minutos) {
  if (minutos <= 0) return '—';
  if (minutos < 60) return '$minutos min';
  final h = minutos ~/ 60;
  final m = minutos % 60;
  return m == 0 ? '$h h' : '$h h ${m.toString().padLeft(2, '0')}';
}

/// "Sáb 08/11 10:00 · 2 h" (hora de Lisboa).
String casaJanelaTexto(DateTime? quando, int duracaoMin) {
  final q = quando == null ? '—' : dataHoraLisboa(quando.toUtc().toIso8601String());
  return '$q · ${casaDuracaoTexto(duracaoMin)}';
}

/// "a 3,2 km" (nunca a porta: só zona e distância).
String casaDistanciaTexto(double? km) => km == null
    ? ''
    : 'a {0} km'.trArgs([km.toStringAsFixed(1).replaceAll('.', ',')]);

/// O serviço do catálogo com este id ou, sem id, com este nome.
CasaServico? casaServicoDe(CasaConfig c, {String? id, String? nome}) {
  for (final s in c.servicos) {
    if (id != null && id.isNotEmpty && s.id == id) return s;
  }
  for (final s in c.servicos) {
    if (nome != null && nome.isNotEmpty && s.nome == nome) return s;
  }
  return null;
}

/// As respostas do cliente com o texto da pergunta (quando se conhece).
List<(String, String)> casaRespostasLegiveis(
    Map<String, dynamic> respostas, CasaServico? servico) {
  final out = <(String, String)>[];
  respostas.forEach((k, v) {
    final valor = v is List ? v.join(', ') : '${v ?? ''}';
    if (valor.trim().isEmpty) return;
    var pergunta = k;
    for (final p in servico?.perguntas ?? const <CasaPergunta>[]) {
      if (p.id == k) pergunta = p.texto;
    }
    out.add((pergunta, valor.trim()));
  });
  return out;
}

/// O estado do trabalho como o PROFISSIONAL o lê (o texto do modelo é o do
/// cliente: "Profissional a caminho").
String casaEstadoParaProfissional(CasaEstado e) => switch (e) {
      CasaEstado.aceite => 'Aceite — prepara-te'.tr,
      CasaEstado.aCaminho => 'A caminho'.tr,
      CasaEstado.chegou => 'No local'.tr,
      CasaEstado.emCurso => 'A trabalhar'.tr,
      CasaEstado.concluido => 'Concluído — à espera do cliente'.tr,
      CasaEstado.confirmado => 'Concluído e confirmado'.tr,
      CasaEstado.disputa => 'O cliente pediu para refazer'.tr,
      CasaEstado.cancelado => 'Cancelado'.tr,
      CasaEstado.expirado => 'Expirado'.tr,
      _ => e.textoPt,
    };

/// Estado de um valor extra.
String casaEstadoExtraTexto(String estado) => switch (estado) {
      'aceite' => 'Aceite pelo cliente'.tr,
      'recusado' => 'Recusado pelo cliente'.tr,
      _ => 'À espera do cliente'.tr,
    };

/// O número GRANDE é o que o profissional GANHA (skill
/// ganho-motorista-numero-grande). O total do cliente só aparece à parte, em
/// pequeno, e só quando é em dinheiro.
class CasaGanhoGrande extends StatelessWidget {
  const CasaGanhoGrande({
    super.key,
    required this.cents,
    this.legenda,
    this.tamanho = 34,
  });

  final int cents;
  final String? legenda;
  final double tamanho;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(legenda ?? 'Ganhas'.tr,
            style: const TextStyle(color: AppColors.textSecondary, fontSize: 12.5)),
        Text(
          casaEuro(cents),
          key: const Key('casa_ganho_grande'),
          style: TextStyle(
            fontSize: tamanho,
            height: 1.05,
            fontWeight: FontWeight.w800,
            color: AppColors.primaryDark,
          ),
        ),
      ],
    );
  }
}

/// Miniaturas das fotos (balde privado → URL assinado). Sem [urlDe] mostra só
/// quantas são.
class CasaFotosFila extends StatelessWidget {
  const CasaFotosFila({
    super.key,
    required this.paths,
    this.urlDe,
    this.tamanho = 72,
  });

  final List<String> paths;
  final Future<String?> Function(String path)? urlDe;
  final double tamanho;

  @override
  Widget build(BuildContext context) {
    if (paths.isEmpty) return const SizedBox.shrink();
    if (urlDe == null) {
      return Row(children: [
        const Icon(Icons.photo_library_outlined,
            size: 18, color: AppColors.textSecondary),
        const SizedBox(width: Spacing.xs),
        Text('{0} fotos'.trArgs([paths.length]),
            style: const TextStyle(color: AppColors.textSecondary)),
      ]);
    }
    return SizedBox(
      height: tamanho,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: paths.length,
        separatorBuilder: (_, __) => const SizedBox(width: Spacing.sm),
        itemBuilder: (context, i) => _Miniatura(
          path: paths[i],
          urlDe: urlDe!,
          tamanho: tamanho,
        ),
      ),
    );
  }
}

class _Miniatura extends StatefulWidget {
  const _Miniatura({
    required this.path,
    required this.urlDe,
    required this.tamanho,
  });

  final String path;
  final Future<String?> Function(String path) urlDe;
  final double tamanho;

  @override
  State<_Miniatura> createState() => _MiniaturaState();
}

class _MiniaturaState extends State<_Miniatura> {
  late final Future<String?> _url = widget.urlDe(widget.path);

  void _abrir(String url) {
    showDialog<void>(
      context: context,
      builder: (ctx) => Dialog(
        insetPadding: const EdgeInsets.all(Spacing.md),
        child: InteractiveViewer(
          child: Image.network(url,
              errorBuilder: (_, __, ___) => Padding(
                    padding: const EdgeInsets.all(Spacing.xl),
                    child: Text('Não foi possível abrir a foto.'.tr),
                  )),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final placeholder = Container(
      width: widget.tamanho,
      height: widget.tamanho,
      decoration: BoxDecoration(
        color: AppColors.surface2,
        borderRadius: BorderRadius.circular(Radii.md),
      ),
      child: const Icon(Icons.image_outlined, color: AppColors.textSubtle),
    );
    return FutureBuilder<String?>(
      future: _url,
      builder: (context, snap) {
        final url = snap.data;
        if (url == null) return placeholder;
        return GestureDetector(
          onTap: () => _abrir(url),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(Radii.md),
            child: Image.network(
              url,
              width: widget.tamanho,
              height: widget.tamanho,
              fit: BoxFit.cover,
              errorBuilder: (_, __, ___) => placeholder,
            ),
          ),
        );
      },
    );
  }
}

/// Uma caixa branca com borda, como os cartões dos outros painéis.
class CasaCaixa extends StatelessWidget {
  const CasaCaixa({
    super.key,
    required this.child,
    this.destaque = false,
    this.margem = const EdgeInsets.only(bottom: Spacing.md),
  });

  final Widget child;
  final bool destaque;
  final EdgeInsetsGeometry margem;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: margem,
      padding: const EdgeInsets.all(Spacing.md),
      decoration: BoxDecoration(
        color: destaque ? AppColors.primaryWash : AppColors.surface,
        borderRadius: BorderRadius.circular(Radii.lg),
        border: Border.all(
            color: destaque ? AppColors.primary : AppColors.divider,
            width: destaque ? 1.5 : 1),
      ),
      child: child,
    );
  }
}

/// Título de secção.
class CasaSeccao extends StatelessWidget {
  const CasaSeccao(this.texto, {super.key});
  final String texto;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(top: Spacing.md, bottom: Spacing.sm),
        child: Text(texto,
            style: const TextStyle(
                fontWeight: FontWeight.w800,
                fontSize: 16,
                color: AppColors.textPrimary)),
      );
}

/// C10 (revisão 01/11): sem horários gravados (`casa_disponibilidade`) o
/// servidor nunca escolhe o profissional (`_casa_elegiveis` →
/// `_casa_disponivel`). Aviso com botão, no ecrã pendente e no aprovado.
class CasaAvisoSemHorarios extends StatelessWidget {
  const CasaAvisoSemHorarios({super.key, required this.onDefinir});
  final VoidCallback onDefinir;

  @override
  Widget build(BuildContext context) => Container(
        key: const Key('casa_aviso_sem_horarios'),
        margin: const EdgeInsets.only(bottom: Spacing.md),
        padding: const EdgeInsets.all(Spacing.md),
        decoration: BoxDecoration(
          color: AppColors.warning.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(Radii.lg),
          border: Border.all(color: AppColors.warning.withValues(alpha: 0.4)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(Icons.event_busy, color: AppColors.warning),
                const SizedBox(width: Spacing.md),
                Expanded(
                  child: Text(
                    'Sem horários não recebes trabalhos. Define os teus horários.'.tr,
                    style: const TextStyle(color: AppColors.textPrimary),
                  ),
                ),
              ],
            ),
            const SizedBox(height: Spacing.sm),
            Align(
              alignment: Alignment.centerRight,
              child: OutlinedButton.icon(
                key: const Key('casa_definir_horarios'),
                onPressed: onDefinir,
                icon: const Icon(Icons.event_available, size: 18),
                label: Text('Definir horários'.tr),
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppColors.primaryDark,
                  side: const BorderSide(color: AppColors.primary),
                ),
              ),
            ),
          ],
        ),
      );
}
