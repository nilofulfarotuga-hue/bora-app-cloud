// lib/widgets/checkin/checkin_festa_premio.dart
//
// A FESTA de chegar a um degrau (R3, Bloco G 10/11/2026): o prémio em grande, com a
// foto real, o nome e o valor em euros, e duas escolhas claras:
//  - "Quero este": leva o prémio; a escada dos prémios volta ao dia 1;
//  - "Continuar para o próximo": mostra a foto do próximo e quantos dias faltam.
// Não tocar em nada = o prémio fica guardado e a escada continua.
// Sem pedido pago nos últimos 30 dias (R2): "Falta 1 pedido para desbloquear" —
// o prémio fica guardado e abre sozinho quando a pessoa fizer um pedido.
import 'package:flutter/material.dart';

import '../../config/app_colors.dart';
import '../../l10n/tr.dart';
import '../../services/checkin_premios_service.dart';
import '../../utils/checkin_regras.dart';
import 'premio_foto.dart';

class CheckinFestaPremio extends StatelessWidget {
  const CheckinFestaPremio({
    super.key,
    required this.guardado,
    required this.onQueroEste,
    this.proximo,
    this.onContinuar,
    this.aDecidir = false,
    this.texto = '',
    this.precisaPedido = false,
  });

  final CheckinDegrau guardado;
  final CheckinDegrau? proximo;
  final VoidCallback onQueroEste;
  final VoidCallback? onContinuar;

  /// A escolha está a caminho do servidor (os botões travam-se por ela).
  final bool aDecidir;

  /// A regra da escada em 3 linhas (vem do servidor).
  final String texto;
  final bool precisaPedido;

  @override
  Widget build(BuildContext context) {
    final g = guardado;
    final p = proximo;
    final valor = valorEmEuros(g.valorCents);
    return Container(
      key: const Key('checkin_escada_escolha'),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFFDCFCE7), Colors.white],
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.primary, width: 1.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const Icon(Icons.emoji_events_rounded, color: AppColors.warning, size: 24),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Chegaste ao dia {0}: ganhaste {1}!'.trArgs([g.dia, g.titulo.tr]),
                  style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: AppColors.primaryDark),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Center(
            child: Container(
              key: const Key('checkin_festa_foto'),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(18),
                boxShadow: [
                  BoxShadow(color: AppColors.primary.withValues(alpha: 0.25), blurRadius: 18, spreadRadius: 1),
                ],
              ),
              child: PremioFoto(url: g.fotoUrl, tipo: g.tipo, tamanho: 132, redonda: false),
            ),
          ),
          const SizedBox(height: 10),
          Text(
            g.titulo.tr,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800, color: AppColors.textPrimary),
          ),
          if (g.lojaNome != null || valor.isNotEmpty) ...[
            const SizedBox(height: 2),
            Text(
              [if (g.lojaNome != null) g.lojaNome!, if (valor.isNotEmpty) 'vale {0}'.trArgs([valor])].join(' · '),
              key: const Key('checkin_festa_valor'),
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: AppColors.textSecondary),
            ),
          ],
          if (precisaPedido) ...[
            const SizedBox(height: 10),
            Container(
              key: const Key('checkin_falta_pedido'),
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              decoration: BoxDecoration(
                color: const Color(0xFFFEF3C7),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Row(
                children: [
                  const Icon(Icons.lock_clock_outlined, size: 18, color: Color(0xFF92400E)),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Falta 1 pedido para desbloquear. O prémio fica guardado e abre sozinho quando fizeres um pedido.'
                          .tr,
                      style: const TextStyle(fontSize: 12, height: 1.3, color: Color(0xFF92400E)),
                    ),
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 12),
          FilledButton(
            key: const Key('btn_escada_levantar'),
            onPressed: aDecidir ? null : onQueroEste,
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.primary,
              padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            child: Column(
              children: [
                Text('Quero este'.tr, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800)),
                const SizedBox(height: 2),
                Text(
                  'A escada dos prémios volta ao dia 1'.tr,
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w500),
                ),
              ],
            ),
          ),
          if (p != null && onContinuar != null) ...[
            const SizedBox(height: 8),
            OutlinedButton(
              key: const Key('btn_escada_continuar'),
              onPressed: aDecidir ? null : onContinuar,
              style: OutlinedButton.styleFrom(
                foregroundColor: AppColors.primaryDark,
                side: const BorderSide(color: AppColors.primary),
                padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 10),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              child: Row(
                children: [
                  PremioFoto(url: p.fotoUrl, tipo: p.tipo, tamanho: 40),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Continuar para o próximo'.tr,
                            style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w800)),
                        Text(
                          p.faltam <= 1
                              ? '{0} amanhã'.trArgs([p.titulo.tr])
                              : '{0} daqui a {1} dias'.trArgs([p.titulo.tr, p.faltam]),
                          key: const Key('checkin_festa_proximo'),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
          if (texto.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              texto.tr,
              key: const Key('checkin_escada_texto'),
              style: const TextStyle(fontSize: 12, height: 1.3, color: AppColors.textSecondary),
            ),
          ],
        ],
      ),
    );
  }
}
