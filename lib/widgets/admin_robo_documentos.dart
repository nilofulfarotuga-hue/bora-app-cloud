/// ROBÔ "FISCAL DE DOCUMENTOS" NO PAINEL — as peças visuais (missão
/// final-app-2026-10-29, adendo 3, R7). Painel em PT-BR.
///
/// O veredito aparece ao lado de cada documento, em TODOS os caminhos por onde
/// o Danilo chega a candidatos (lista e ficha de entregadores, aprovações,
/// limpeza, lavagem, comprovativo). O robô NUNCA aprova nada.
library;

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../config/app_colors.dart';
import '../screens/admin/_admin_rpc_errors.dart';
import '../services/robo_documentos.dart';

Color _corDo(VereditoRobo v) =>
    v.ok ? AppColors.success : (v.errado ? AppColors.error : Colors.orange.shade800);

IconData _iconeDo(VereditoRobo v) =>
    v.ok ? Icons.smart_toy_outlined : (v.errado ? Icons.report_gmailerrorred : Icons.help_outline);

/// O veredito do robô ao lado de um documento ("Robô: parece cartão de cidadão,
/// não é o comprovativo"). Com [onDesfazer], mostra o botão quando o robô já agiu.
class RoboVereditoChip extends StatelessWidget {
  const RoboVereditoChip({super.key, required this.veredito, this.onDesfazer});

  final VereditoRobo veredito;
  final Future<void> Function(VereditoRobo)? onDesfazer;

  @override
  Widget build(BuildContext context) {
    final v = veredito;
    final cor = _corDo(v);
    final agiu = v.agiu
        ? (v.acao == 'recusado'
            ? 'O robô recusou e avisou a pessoa.'
            : 'O robô pediu o documento de novo à pessoa.')
        : (v.modo == 'sombra' ? 'Modo sombra: só olhou, não avisou ninguém.' : null);
    return Container(
      key: const Key('robo-veredito'),
      width: double.infinity,
      margin: const EdgeInsets.only(top: 4, bottom: 6),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: cor.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: cor.withValues(alpha: 0.4)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(_iconeDo(v), size: 18, color: cor),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  textoDoVeredito(v),
                  style: TextStyle(color: cor, fontWeight: FontWeight.w600, fontSize: 13),
                ),
              ),
            ],
          ),
          if (agiu != null)
            Padding(
              padding: const EdgeInsets.only(top: 2, left: 24),
              child: Text(agiu,
                  style: const TextStyle(fontSize: 12, color: AppColors.textSecondary)),
            ),
          if (v.agiu && onDesfazer != null)
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                key: const Key('robo-desfazer'),
                onPressed: () => onDesfazer!(v),
                icon: const Icon(Icons.undo, size: 16),
                label: const Text('Desfazer decisão do robô'),
              ),
            ),
        ],
      ),
    );
  }
}

/// Uma linha para as listas: "Robô: tudo certo…" / "Robô: 1 documento errado".
class RoboResumoLinha extends StatelessWidget {
  const RoboResumoLinha({super.key, required this.linha});
  final Map<String, dynamic> linha;

  @override
  Widget build(BuildContext context) {
    if (linha['_robo'] == null) return const SizedBox.shrink();
    final r = resumoDoRobo(linha);
    final cor = switch (r.nivel) {
      'ok' => AppColors.success,
      'errado' => AppColors.error,
      'duvida' => Colors.orange.shade800,
      _ => AppColors.textSecondary,
    };
    return Padding(
      padding: const EdgeInsets.only(top: 2),
      child: Text(
        r.texto,
        key: const Key('robo-resumo'),
        style: TextStyle(fontSize: 12, color: cor, fontWeight: FontWeight.w600),
      ),
    );
  }
}

/// Pede confirmação e desfaz o que o robô fez (volta a "em análise", sem avisar
/// ninguém). Devolve true se desfez.
Future<bool> desfazerDecisaoDoRobo(
  BuildContext ctx,
  VereditoRobo v, {
  Future<void> Function(int id)? desfazer,
}) async {
  final ok = await showDialog<bool>(
    context: ctx,
    builder: (dCtx) => AlertDialog(
      title: const Text('Desfazer a decisão do robô?'),
      content: Text(
        v.acao == 'recusado'
            ? 'O comprovativo volta a "em análise". A pessoa não recebe aviso nenhum — '
                'se já tinha sido avisada, usa "Lembrar este" ou fala com ela.'
            : 'Fica registado que desfizeste a decisão do robô sobre este documento.',
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(dCtx, false), child: const Text('Cancelar')),
        FilledButton(onPressed: () => Navigator.pop(dCtx, true), child: const Text('Desfazer')),
      ],
    ),
  );
  if (ok != true) return false;
  try {
    if (desfazer != null) {
      await desfazer(v.id);
    } else {
      await Supabase.instance.client.rpc('admin_documentos_desfazer', params: {'p_id': v.id});
    }
    if (ctx.mounted) {
      ScaffoldMessenger.of(ctx).showSnackBar(const SnackBar(
        content: Text('Decisão do robô desfeita.'),
        backgroundColor: AppColors.success,
      ));
    }
    return true;
  } catch (e) {
    if (ctx.mounted) {
      ScaffoldMessenger.of(ctx).showSnackBar(SnackBar(
        content: Text(humanizeAdminRpcError(e)),
        backgroundColor: AppColors.error,
      ));
    }
    return false;
  }
}

/// Antes de aprovar uma candidatura: se o servidor ia recusar (falta aprovar o
/// comprovativo) avisa com mensagem clara e devolve false — assim nem se faz a
/// chamada que dava 400. Devolve true quando pode seguir para a confirmação.
Future<bool> avisarSeAtividadePorAprovar(BuildContext ctx, Map<String, dynamic> linha) async {
  final bloqueio = bloqueioDaAtividade(linha);
  if (bloqueio == null) return true;
  await showDialog<void>(
    context: ctx,
    builder: (dCtx) => AlertDialog(
      key: const Key('robo-atividade-por-aprovar'),
      title: const Text('Falta aprovar o comprovativo de atividade'),
      content: Text(bloqueio),
      actions: [
        FilledButton(onPressed: () => Navigator.pop(dCtx), child: const Text('Entendi')),
      ],
    ),
  );
  return false;
}

/// O bloco a vermelho "O robô viu isto de errado" para pôr dentro dos
/// diálogos de aprovar. Vazio quando o robô não achou nada errado.
class RoboAvisoAprovar extends StatelessWidget {
  const RoboAvisoAprovar({super.key, required this.linha});
  final Map<String, dynamic> linha;

  @override
  Widget build(BuildContext context) {
    final avisos = avisosParaAprovar(linha);
    if (avisos.isEmpty) return const SizedBox.shrink();
    return Container(
      key: const Key('robo-aviso-aprovar'),
      width: double.infinity,
      margin: const EdgeInsets.only(top: 12),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Colors.red.shade50,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.red.shade300),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('O robô diz que há documento errado:',
              style: TextStyle(color: AppColors.error, fontWeight: FontWeight.w800)),
          const SizedBox(height: 4),
          for (final a in avisos)
            Text('• $a', style: const TextStyle(color: AppColors.error, fontSize: 13)),
        ],
      ),
    );
  }
}
