import 'package:flutter/material.dart';

import '../../../config/app_colors.dart';
import '../../../config/app_spacing.dart';
import '../../../widgets/bora/bora.dart';

import '../../../l10n/tr.dart';

/// [Reserva agendada 2026-08-19] Folha de "Marcar para depois" — o cliente
/// escolhe o DIA e a HORA da viagem.
///
/// Os limites (mínimo de antecedência, máximo de dias) vêm das definições da
/// plataforma e são passados de fora — nunca cravados aqui. O preço mostrado é
/// o mesmo da corrida normal; quem o fecha é o servidor.
///
/// Devolve o `DateTime` escolhido, ou `null` se o cliente desistir. A escolha
/// do método de pagamento NÃO acontece aqui: o ecrã reutiliza a seguir a mesma
/// folha de pagamento da corrida normal.
class TvdeScheduleRideSheet extends StatefulWidget {
  const TvdeScheduleRideSheet({
    super.key,
    required this.minAdvanceMinutes,
    required this.maxAdvanceDays,
    required this.priceCents,
    this.km,
  });

  /// Antecedência mínima (`tvde_reservation_min_advance_minutes`).
  final int minAdvanceMinutes;

  /// Antecedência máxima em dias (`tvde_reservation_max_advance_days`).
  final int maxAdvanceDays;

  /// Preço estimado, igual ao da corrida normal.
  final int priceCents;

  final double? km;

  @override
  State<TvdeScheduleRideSheet> createState() => _TvdeScheduleRideSheetState();
}

class _TvdeScheduleRideSheetState extends State<TvdeScheduleRideSheet> {
  DateTime? _escolhido;

  DateTime get _minimo =>
      DateTime.now().add(Duration(minutes: widget.minAdvanceMinutes));
  DateTime get _maximo =>
      DateTime.now().add(Duration(days: widget.maxAdvanceDays));

  static const _diasSemana = [
    'segunda-feira',
    'terça-feira',
    'quarta-feira',
    'quinta-feira',
    'sexta-feira',
    'sábado',
    'domingo',
  ];
  static const _meses = [
    'janeiro',
    'fevereiro',
    'março',
    'abril',
    'maio',
    'junho',
    'julho',
    'agosto',
    'setembro',
    'outubro',
    'novembro',
    'dezembro',
  ];

  String _formata(DateTime d) {
    final hh = d.hour.toString().padLeft(2, '0');
    final mm = d.minute.toString().padLeft(2, '0');
    return '${_diasSemana[d.weekday - 1]}, ${d.day} de ${_meses[d.month - 1]} '
        'às $hh:$mm';
  }

  Future<void> _escolherDataHora() async {
    final minimo = _minimo;
    final data = await showDatePicker(
      context: context,
      initialDate: minimo,
      firstDate: DateTime(minimo.year, minimo.month, minimo.day),
      lastDate: _maximo,
      helpText: 'Escolhe o dia'.tr,
      cancelText: 'Voltar'.tr,
      confirmText: 'Seguinte'.tr,
    );
    if (data == null || !mounted) return;

    final hora = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(minimo),
      helpText: 'Escolhe a hora'.tr,
      cancelText: 'Voltar'.tr,
      confirmText: 'Pronto'.tr,
    );
    if (hora == null || !mounted) return;

    final juntos =
        DateTime(data.year, data.month, data.day, hora.hour, hora.minute);

    // Validação local só para dar resposta imediata — quem manda é o servidor,
    // que volta a validar e devolve `too_soon` / `too_far`.
    if (juntos.isBefore(_minimo)) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('Essa hora está demasiado em cima. Marca com pelo menos {0} minutos de antecedência.'.trArgs([widget.minAdvanceMinutes])),
      ));
      return;
    }
    if (juntos.isAfter(_maximo)) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('Só dá para marcar até {0} dias à frente.'.trArgs([widget.maxAdvanceDays])),
      ));
      return;
    }
    setState(() => _escolhido = juntos);
  }

  @override
  Widget build(BuildContext context) {
    final preco = (widget.priceCents / 100).toStringAsFixed(2);
    final bottom = MediaQuery.of(context).padding.bottom;

    return Padding(
      padding: EdgeInsets.fromLTRB(
          Spacing.lg, Spacing.lg, Spacing.lg, Spacing.lg + bottom),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(
            child: Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: AppColors.divider,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: Spacing.lg),
          Text(
            'Marcar para depois'.tr,
            style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: Spacing.xs),
          Text(
            'Escolhe o dia e a hora. Procuramos motorista com antecedência e avisamos-te assim que estiver confirmado.'.tr,
            style: const TextStyle(color: AppColors.textSecondary, fontSize: 13),
          ),
          const SizedBox(height: Spacing.lg),

          // Selector de dia/hora.
          InkWell(
            onTap: _escolherDataHora,
            borderRadius: BorderRadius.circular(12),
            child: Container(
              padding: const EdgeInsets.all(Spacing.md),
              decoration: BoxDecoration(
                border: Border.all(
                  color: _escolhido == null
                      ? AppColors.divider
                      : AppColors.primary,
                  width: _escolhido == null ? 1 : 1.5,
                ),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                children: [
                  const Icon(Icons.event, color: AppColors.primary),
                  const SizedBox(width: Spacing.md),
                  Expanded(
                    child: Text(
                      _escolhido == null
                          ? 'Escolher dia e hora'.tr
                          : _formata(_escolhido!),
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: _escolhido == null
                            ? FontWeight.w400
                            : FontWeight.w600,
                        color: _escolhido == null
                            ? AppColors.textSecondary
                            : AppColors.textPrimary,
                      ),
                    ),
                  ),
                  const Icon(Icons.chevron_right,
                      color: AppColors.textSubtle),
                ],
              ),
            ),
          ),
          const SizedBox(height: Spacing.md),

          // Preço — o mesmo da corrida normal.
          Container(
            padding: const EdgeInsets.all(Spacing.md),
            decoration: BoxDecoration(
              color: AppColors.surface2,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              children: [
                const Icon(Icons.payments_outlined,
                    color: AppColors.primary, size: 20),
                const SizedBox(width: Spacing.sm),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Preço estimado: €{0}'.trArgs([preco]),
                        style: const TextStyle(
                            fontWeight: FontWeight.w600, fontSize: 15),
                      ),
                      if (widget.km != null)
                        Text(
                          '{0} km — o valor final é pela distância real.'.trArgs([widget.km!.toStringAsFixed(1)]),
                          style: const TextStyle(
                              color: AppColors.textSubtle, fontSize: 12),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: Spacing.md),
          Text(
            'A seguir escolhes como pagas: dinheiro ao motorista, cartão ou MB Way.'.tr,
            style: const TextStyle(color: AppColors.textSubtle, fontSize: 12),
          ),
          const SizedBox(height: Spacing.xl),
          BoraAccentButton(
            label: 'Continuar'.tr,
            icon: Icons.arrow_forward,
            onPressed: _escolhido == null
                ? null
                : () => Navigator.pop(context, _escolhido),
          ),
          const SizedBox(height: Spacing.sm),
          Center(
            child: TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text('Voltar'.tr),
            ),
          ),
        ],
      ),
    );
  }
}
