import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../config/app_colors.dart';
import '../../config/app_spacing.dart';
import '../../l10n/tr.dart';
import '../../models/casa_models.dart';
import '../../stores/handyman_store.dart';
import '../../utils/hora_lisboa.dart';
import '../../widgets/bora/bora.dart';
import 'casa_profissional_ui.dart';

/// CASA — ganhos do profissional (`casa_meus_ganhos`): a semana atual, os
/// acertos semanais e os trabalhos. A comissão explica-se em palavras com o
/// que o servidor diz (comissao_pct e sem_comissao_ate); a app não calcula
/// nada.
class HandymanGanhosScreen extends StatefulWidget {
  const HandymanGanhosScreen({super.key});

  @override
  State<HandymanGanhosScreen> createState() => _HandymanGanhosScreenState();
}

class _HandymanGanhosScreenState extends State<HandymanGanhosScreen> {
  bool _carregou = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      await context.read<HandymanStore>().carregarGanhos();
      if (mounted) setState(() => _carregou = true);
    });
  }

  @override
  Widget build(BuildContext context) {
    final store = context.watch<HandymanStore>();
    return Scaffold(
      appBar: BoraScreenAppBar(title: 'Os meus ganhos'.tr),
      body: !_carregou
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: store.carregarGanhos,
              child: CasaGanhosConteudo(
                ganhos: store.ganhos,
                perfil: store.perfil,
              ),
            ),
    );
  }
}

/// O conteúdo do ecrã dos ganhos (sem rede — testável).
class CasaGanhosConteudo extends StatelessWidget {
  const CasaGanhosConteudo({
    super.key,
    required this.ganhos,
    this.perfil,
    this.agora,
  });

  final CasaGanhos ganhos;
  final CasaPerfil? perfil;
  final DateTime? agora;

  String _data(DateTime? d) =>
      d == null ? '—' : '${casaDiaMes(d)}/${d.year}';

  @override
  Widget build(BuildContext context) {
    final g = ganhos;
    final p = perfil;
    return ListView(
      padding: EdgeInsets.fromLTRB(Spacing.lg, Spacing.lg, Spacing.lg,
          BoraBottomActionBar.folgaInferior(context)),
      children: [
        CasaCaixa(
          destaque: true,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                g.inicio == null
                    ? 'Esta semana'.tr
                    : 'Esta semana ({0} a {1})'.trArgs([
                        casaDiaMes(g.inicio!),
                        g.fim == null ? '—' : casaDiaMes(g.fim!),
                      ]),
                style: const TextStyle(
                    fontWeight: FontWeight.w700, color: AppColors.textPrimary),
              ),
              const SizedBox(height: Spacing.sm),
              CasaGanhoGrande(cents: g.ganhoCents, legenda: 'Ganhaste'.tr),
              const SizedBox(height: Spacing.sm),
              _Par('Trabalhos'.tr, '${g.trabalhos}'),
              _Par('Recebido em mão'.tr, casaEuro(g.recebidoEmMaoCents)),
              _Par('A receber no acerto'.tr, casaEuro(g.aReceberCents)),
              _Par('Comissão do Bora'.tr, casaEuro(g.comissaoCents)),
            ],
          ),
        ),
        if (p != null)
          CasaCaixa(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(Icons.info_outline, color: AppColors.primary),
                const SizedBox(width: Spacing.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        casaTextoComissao(p.comissaoPct, p.semComissaoAte,
                            agora: agora),
                        key: const Key('casa_ganhos_comissao'),
                        style: const TextStyle(color: AppColors.textPrimary),
                      ),
                      const SizedBox(height: Spacing.xs),
                      Text(
                        'A comissão só conta nos trabalhos concluídos. O que recebes em dinheiro abate no acerto da semana.'.tr,
                        style: const TextStyle(
                            color: AppColors.textSecondary, fontSize: 12.5),
                      ),
                      if (!p.valoresAutorizados)
                        Padding(
                          padding: const EdgeInsets.only(top: Spacing.xs),
                          child: Text(
                            'Os valores da Casa ainda estão a ser aprovados.'.tr,
                            style: const TextStyle(
                                color: AppColors.warning, fontSize: 12.5),
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        CasaSeccao('Acertos semanais'.tr),
        if (g.acertos.isEmpty)
          Text('Ainda não há acertos.'.tr,
              style: const TextStyle(color: AppColors.textSecondary))
        else
          for (final a in g.acertos)
            CasaCaixa(
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Semana de {0} a {1}'.trArgs([_data(a.inicio), _data(a.fim)]),
                            style: const TextStyle(
                                fontWeight: FontWeight.w600,
                                color: AppColors.textPrimary)),
                        Text(
                          [
                            '{0} trabalhos'.trArgs([a.trabalhos]),
                            a.aReceber
                                ? 'o Bora paga-te'.tr
                                : 'tu pagas ao Bora'.tr,
                            a.pago
                                ? 'pago em {0}'.trArgs([_data(a.pagoEm)])
                                : 'por pagar'.tr,
                          ].join(' · '),
                          style: const TextStyle(
                              color: AppColors.textSecondary, fontSize: 12.5),
                        ),
                      ],
                    ),
                  ),
                  Text(casaEuro(a.liquidoCents),
                      style: TextStyle(
                          fontWeight: FontWeight.w800,
                          fontSize: 16,
                          color: a.aReceber
                              ? AppColors.primaryDark
                              : AppColors.textPrimary)),
                ],
              ),
            ),
        CasaSeccao('Trabalhos'.tr),
        if (g.lista.isEmpty)
          Text('Ainda não tens trabalhos pagos.'.tr,
              style: const TextStyle(color: AppColors.textSecondary))
        else
          for (final t in g.lista)
            CasaCaixa(
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(t.servicoNome.isEmpty ? 'Trabalho'.tr : t.servicoNome,
                            style: const TextStyle(
                                fontWeight: FontWeight.w600,
                                color: AppColors.textPrimary)),
                        Text(
                          [
                            if (t.confirmadoEm != null)
                              dataHoraLisboa(
                                  t.confirmadoEm!.toUtc().toIso8601String()),
                            switch (t.metodo) {
                              'cash' => 'em dinheiro'.tr,
                              'card' => 'cartão'.tr,
                              'mbway' => 'MB WAY'.tr,
                              _ => t.metodo,
                            },
                            if (t.comissaoCents > 0)
                              'comissão {0}'.trArgs([casaEuro(t.comissaoCents)]),
                          ].where((s) => s.isNotEmpty).join(' · '),
                          style: const TextStyle(
                              color: AppColors.textSecondary, fontSize: 12.5),
                        ),
                      ],
                    ),
                  ),
                  Text(casaEuro(t.ganhoCents),
                      style: const TextStyle(
                          fontWeight: FontWeight.w800,
                          fontSize: 16,
                          color: AppColors.primaryDark)),
                ],
              ),
            ),
      ],
    );
  }
}

class _Par extends StatelessWidget {
  const _Par(this.rotulo, this.valor);
  final String rotulo;
  final String valor;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(top: 2),
        child: Row(
          children: [
            Expanded(
                child: Text(rotulo,
                    style: const TextStyle(color: AppColors.textSecondary))),
            Text(valor,
                style: const TextStyle(
                    fontWeight: FontWeight.w600, color: AppColors.textPrimary)),
          ],
        ),
      );
}
