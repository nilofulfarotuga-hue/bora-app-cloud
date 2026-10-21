// [17/10/2026 · missão cancelamento-tardio] Diálogo de cancelar a corrida do
// cliente, alimentado SÓ pela cotação do servidor (`tvde_cancel_quote`).
//
// Porquê: a pré-visualização antiga contava a janela grátis desde o pedido e
// calculava o valor na app; o servidor conta desde o motorista aceitar e
// decide pelo tipo de corrida. Regras desta peça:
//  - a cotação pede-se ANTES de abrir o diálogo (até ~3 s; depois disso, aviso
//    neutro, sem números — nunca o cálculo local antigo);
//  - dentro da janela grátis há contador vivo; quando chega a zero pede-se
//    nova cotação e o diálogo redesenha-se;
//  - ao confirmar pede-se OUTRA cotação: se a taxa subiu em relação à que o
//    cliente viu, não se cancela — mostra-se o diálogo outra vez com o valor
//    novo. Nunca se cobra mais do que o cliente viu.
import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../config/app_colors.dart';
import '../../config/app_spacing.dart';
import '../../l10n/tr.dart';
import '../../models/tvde_cancel_quote.dart';
import '../../models/ride_kind.dart';
import '../../utils/ride_kind_context.dart';

/// Prazo para a cotação chegar antes de se mostrar o aviso neutro.
const Duration kPrazoDaCotacao = Duration(seconds: 3);

/// Margem antes do fim da janela grátis: com menos do que isto por fazer, não
/// se cancela "grátis" (o pedido pode chegar ao servidor já fora da janela).
const Duration kMargemDaJanela = Duration(seconds: 5);

/// O diálogo fecha-se com isto quando a corrida terminou enquanto estava
/// aberto: quem o abriu volta a perguntar ao servidor e decide.
const int _kReavaliar = -2;

/// O que o diálogo devolve quando o cliente confirmou o aviso neutro (sem
/// cotação, nenhum número mostrado) — o mesmo que `TextoCancelamento.taxaCents`.
const int _kSemCotacao = -1;

/// Resultado de [pedirConfirmacaoDeCancelamento].
class DecisaoDeCancelamento {
  const DecisaoDeCancelamento._({this.confirmou = false, this.jaTerminou});

  /// O cliente carregou em "Voltar" (ou o ecrã fechou entretanto).
  const DecisaoDeCancelamento.voltou() : this._();

  /// O cliente confirmou com o valor que estava a ver (ou menos).
  const DecisaoDeCancelamento.confirmou() : this._(confirmou: true);

  /// A corrida já tinha acabado ou já estava cancelada.
  const DecisaoDeCancelamento.terminada(TvdeCancelQuote q)
      : this._(jaTerminou: q);

  final bool confirmou;
  final TvdeCancelQuote? jaTerminou;
}

Future<TvdeCancelQuote?> _cotarComPrazo(
    Future<TvdeCancelQuote?> Function() cotar, Duration prazo) async {
  try {
    return await cotar().timeout(prazo, onTimeout: () => null);
  } catch (_) {
    return null;
  }
}

/// Pede a cotação, mostra o diálogo e confirma de novo antes de devolver.
/// Não cancela nada: quem chama faz o cancelamento se `confirmou`.
Future<DecisaoDeCancelamento> pedirConfirmacaoDeCancelamento(
  BuildContext context, {
  required Future<TvdeCancelQuote?> Function() cotar,
  required int minutosDaJanela,
  Duration prazo = kPrazoDaCotacao,
}) async {
  var cotacao = await _cotarComPrazo(cotar, prazo);
  while (true) {
    if (!context.mounted) return const DecisaoDeCancelamento.voltou();
    final q = cotacao;
    if (q != null && q.jaTerminou) return DecisaoDeCancelamento.terminada(q);
    final vista = await showDialog<int>(
      context: context,
      builder: (_) => TvdeCancelDialog(
        quote: q,
        minutosDaJanela: minutosDaJanela,
        recotar: () => _cotarComPrazo(cotar, prazo),
      ),
    );
    if (vista == null || !context.mounted) {
      return const DecisaoDeCancelamento.voltou();
    }
    final agora = await _cotarComPrazo(cotar, prazo);
    if (vista == _kReavaliar) {
      cotacao = agora;
      continue;
    }
    if (agora == null) {
      // Sem resposta agora. Só o aviso neutro (que já dizia "pode custar o
      // valor da corrida") pode seguir assim; quem viu um número volta a ver
      // o aviso neutro — a janela grátis pode ter acabado entretanto.
      if (vista == _kSemCotacao) return const DecisaoDeCancelamento.confirmou();
      cotacao = null;
      continue;
    }
    if (agora.jaTerminou) return DecisaoDeCancelamento.terminada(agora);
    // A janela grátis acabou com o diálogo aberto (ou o aviso neutro não
    // mostrava número): mostra-se outra vez, com o valor novo.
    if (agora.taxaAMostrar > math.max(vista, 0)) {
      cotacao = agora;
      continue;
    }
    // Grátis por um triz: o cancelamento pode chegar ao servidor já depois da
    // janela (e aí cobra-se a corrida). Com menos de [kMargemDaJanela] mostra-se
    // outra vez — o contador chega a zero e o valor real aparece.
    if (!agora.terminal &&
        agora.regra == 'dentro_da_graca' &&
        agora.secondsLeftFree < kMargemDaJanela.inSeconds) {
      cotacao = agora;
      continue;
    }
    return const DecisaoDeCancelamento.confirmou();
  }
}

class TvdeCancelDialog extends StatefulWidget {
  const TvdeCancelDialog({
    super.key,
    required this.quote,
    required this.minutosDaJanela,
    required this.recotar,
  });

  /// null = a cotação falhou → aviso neutro.
  final TvdeCancelQuote? quote;
  final int minutosDaJanela;
  final Future<TvdeCancelQuote?> Function() recotar;

  @override
  State<TvdeCancelDialog> createState() => _TvdeCancelDialogState();
}

class _TvdeCancelDialogState extends State<TvdeCancelDialog> {
  TvdeCancelQuote? _q;
  Timer? _relogio;

  /// Segundos grátis que faltam (null = sem contador). Conta-se por tiques
  /// de 1 s; a verdade é sempre a cotação nova pedida a zero e ao confirmar.
  int? _restam;
  bool _aRecotar = false;

  @override
  void initState() {
    super.initState();
    _q = widget.quote;
    _armarContador();
  }

  @override
  void dispose() {
    _relogio?.cancel();
    super.dispose();
  }

  void _armarContador() {
    _relogio?.cancel();
    _relogio = null;
    final q = _q;
    if (q == null || q.terminal || q.regra != 'dentro_da_graca') {
      _restam = null;
      return;
    }
    _restam = q.secondsLeftFree;
    _relogio = Timer.periodic(const Duration(seconds: 1), (_) => _tique());
  }

  void _tique() {
    if (!mounted) return;
    final restam = (_restam ?? 0) - 1;
    if (restam > 0) {
      setState(() => _restam = restam);
      return;
    }
    _restam = 0;
    _relogio?.cancel();
    _relogio = null;
    unawaited(_recotar());
  }

  Future<void> _recotar() async {
    setState(() => _aRecotar = true);
    final novo = await widget.recotar();
    if (!mounted) return;
    if (novo != null && novo.jaTerminou) {
      Navigator.of(context).pop(_kReavaliar);
      return;
    }
    setState(() {
      _q = novo;
      _aRecotar = false;
    });
    _armarContador();
  }

  @override
  Widget build(BuildContext context) {
    final t = textoDoCancelamento(
      _q,
      minutosDaJanela: widget.minutosDaJanela,
      segundosRestantes: _restam,
    );
    return AlertDialog(
      title: Text('Cancelar corrida?'.trK(context.tvdeKind)),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (t.caixaCusto != null) ...[
            Container(
              padding: const EdgeInsets.symmetric(
                  horizontal: Spacing.md, vertical: Spacing.sm),
              decoration: BoxDecoration(
                color: AppColors.error.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(Radii.md),
              ),
              child: Row(
                children: [
                  const Icon(Icons.euro, size: 18, color: AppColors.error),
                  const SizedBox(width: Spacing.sm),
                  Expanded(
                    child: Text(
                      t.caixaCusto!,
                      key: const ValueKey('tvde_cancel_custo'),
                      style: const TextStyle(
                          fontWeight: FontWeight.w700,
                          color: AppColors.error),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: Spacing.md),
          ],
          Text(t.principal,
              key: const ValueKey('tvde_cancel_principal'),
              style: const TextStyle(color: AppColors.textSecondary)),
          if (t.detalhe != null) ...[
            const SizedBox(height: Spacing.sm),
            Text(t.detalhe!,
                key: const ValueKey('tvde_cancel_detalhe'),
                style: const TextStyle(
                    color: AppColors.textSubtle, fontSize: 12.5)),
          ],
        ],
      ),
      actions: [
        TextButton(
            key: const ValueKey('tvde_cancel_voltar'),
            onPressed: () => Navigator.of(context).pop(),
            child: Text('Voltar'.tr)),
        TextButton(
            key: const ValueKey('tvde_cancel_confirmar'),
            // A recotar (a janela grátis acabou agora): o valor pode mudar,
            // por isso não se confirma com o número antigo.
            onPressed: _aRecotar
                ? null
                : () => Navigator.of(context).pop(t.taxaCents),
            child: Text(t.confirmar)),
      ],
    );
  }
}
