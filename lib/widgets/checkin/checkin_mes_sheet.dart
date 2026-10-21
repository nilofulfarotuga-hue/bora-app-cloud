// lib/widgets/checkin/checkin_mes_sheet.dart
//
// Vista do MÊS dos marcos do check-in (Bloco D, 21/10/2026): abre pela seta do
// cartão "Check-in diário". Mostra o texto do Danilo, em que dia da sequência
// está o cliente, os 4 marcos (7, 10, 15, 30) com o que se ganha e quantos dias
// faltam, e o botão para "Os meus prémios". Tudo vem do servidor.
import 'package:flutter/material.dart';

import '../../config/app_colors.dart';
import '../../l10n/tr.dart';
import '../../services/checkin_premios_service.dart';

Future<void> mostrarCheckinMes(
  BuildContext context,
  CheckinPremiosEstado estado, {
  VoidCallback? abrirPremios,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    backgroundColor: Colors.white,
    builder: (ctx) => CheckinMesSheet(
      estado: estado,
      abrirPremios: abrirPremios == null
          ? null
          : () {
              Navigator.of(ctx).pop();
              abrirPremios();
            },
    ),
  );
}

class CheckinMesSheet extends StatelessWidget {
  const CheckinMesSheet({super.key, required this.estado, this.abrirPremios});

  final CheckinPremiosEstado estado;
  final VoidCallback? abrirPremios;

  @override
  Widget build(BuildContext context) {
    final e = estado;
    final porUsar = e.porUsar.length;
    return SafeArea(
      top: false,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.85),
        child: SingleChildScrollView(
          key: const Key('checkin_mes_sheet'),
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Os prémios do mês'.tr,
                style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 6),
              Text(
                e.texto.isNotEmpty
                    ? e.texto.tr
                    : 'Faz o check-in todos os dias. Aos 10 dias seguidos ganhas 2 salgados da Keli (pagas só a entrega e as taxas). Aos 15, um açaí do Goola. Aos 30, escolhes 2 horas de limpeza ou uma lavagem exterior do carro.'
                        .tr,
                style: const TextStyle(fontSize: 13.5, height: 1.35, color: AppColors.textSecondary),
              ),
              const SizedBox(height: 12),
              _Progresso(estado: e),
              const SizedBox(height: 12),
              for (final m in e.marcos) ...[
                _MarcoLinha(marco: m, diaMarco: e.diaMarco),
                const SizedBox(height: 8),
              ],
              const SizedBox(height: 4),
              Text(
                'Se falhares um dia, a sequência volta ao dia 1. Depois do dia {0} recomeça no dia 1.'
                    .trArgs([e.cicloDias]),
                style: const TextStyle(fontSize: 12, color: AppColors.textSubtle, height: 1.3),
              ),
              if (abrirPremios != null) ...[
                const SizedBox(height: 14),
                FilledButton.icon(
                  key: const Key('btn_os_meus_premios'),
                  onPressed: abrirPremios,
                  icon: const Icon(Icons.card_giftcard, size: 18),
                  label: Text(porUsar > 0
                      ? 'Os meus prémios ({0})'.trArgs([porUsar])
                      : 'Os meus prémios'.tr),
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _Progresso extends StatelessWidget {
  const _Progresso({required this.estado});

  final CheckinPremiosEstado estado;

  @override
  Widget build(BuildContext context) {
    final e = estado;
    final total = e.cicloDias <= 0 ? 30 : e.cicloDias;
    final valor = (e.diaMarco / total).clamp(0.0, 1.0);
    final prox = e.proximo;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFF0FDF4),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            e.diasSeguidos == 0
                ? 'Começa hoje a tua sequência.'.tr
                : 'Estás no dia {0} de {1}.'.trArgs([e.diaMarco, total]),
            key: const Key('checkin_mes_dia'),
            style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: AppColors.primaryDark),
          ),
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(99),
            child: LinearProgressIndicator(
              value: valor,
              minHeight: 8,
              backgroundColor: const Color(0xFFDCFCE7),
              color: AppColors.primary,
            ),
          ),
          if (prox != null) ...[
            const SizedBox(height: 8),
            Text(
              prox.faltam <= 1
                  ? 'Falta 1 dia para ganhares {0}.'.trArgs([prox.titulo.tr])
                  : 'Faltam {0} dias para ganhares {1}.'.trArgs([prox.faltam, prox.titulo.tr]),
              key: const Key('checkin_mes_proximo'),
              style: const TextStyle(fontSize: 12.5, color: AppColors.textSecondary),
            ),
          ],
        ],
      ),
    );
  }
}

class _MarcoLinha extends StatelessWidget {
  const _MarcoLinha({required this.marco, required this.diaMarco});

  final CheckinMarco marco;
  final int diaMarco;

  IconData get _icone => switch (marco.tipo) {
        'tokens' => Icons.toll_rounded,
        'servico' => Icons.cleaning_services_outlined,
        _ => Icons.card_giftcard,
      };

  @override
  Widget build(BuildContext context) {
    final feito = marco.atingido;
    return Container(
      key: Key('checkin_marco_${marco.dia}'),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: feito ? const Color(0xFFDCFCE7) : const Color(0xFFF9FAFB),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: feito ? AppColors.primary : const Color(0xFFE5E7EB)),
      ),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: feito ? AppColors.primary : Colors.white,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: feito ? AppColors.primary : const Color(0xFFE5E7EB)),
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  '${marco.dia}',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                    color: feito ? Colors.white : AppColors.textPrimary,
                  ),
                ),
                Text(
                  'dias'.tr,
                  style: TextStyle(fontSize: 9.5, color: feito ? Colors.white : AppColors.textSubtle),
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(_icone, size: 15, color: AppColors.primaryDark),
                    const SizedBox(width: 4),
                    Expanded(
                      child: Text(
                        marco.tipo == 'tokens' && marco.tokens != null
                            ? '{0} tokens'.trArgs([marco.tokens])
                            : marco.titulo.tr,
                        style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
                      ),
                    ),
                  ],
                ),
                if (marco.descricao.isNotEmpty)
                  Text(
                    marco.descricao.tr,
                    style: const TextStyle(fontSize: 12, color: AppColors.textSecondary, height: 1.3),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Text(
            feito
                ? 'Ganho'.tr
                : (marco.faltam == 1 ? 'Falta 1 dia'.tr : 'Faltam {0} dias'.trArgs([marco.faltam])),
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: feito ? AppColors.primaryDark : AppColors.textSubtle,
            ),
          ),
        ],
      ),
    );
  }
}
