import 'package:flutter/material.dart';

import '../../../config/app_colors.dart';
import '../../../config/app_spacing.dart';
import '../../../l10n/tr.dart';

/// Escolha da VOLTA no ida-e-volta marcado (2026-09-23).
/// `hora == null` = "Chamo quando terminar" (fica o vale da volta, como hoje).
class TvdeEscolhaVolta {
  const TvdeEscolhaVolta(this.hora);
  final DateTime? hora;
}

/// Folha "E a volta?" — duas escolhas, "Chamo quando terminar" vem marcada.
///
/// Os limites (30 min a 12 h depois da ida) são os mesmos que o servidor
/// valida em `tvde_schedule_roundtrip`; aqui só se avisa antes, em palavras.
class TvdeVoltaSheet extends StatefulWidget {
  const TvdeVoltaSheet({super.key, required this.ida});

  final DateTime ida;

  static const int folgaMinimaMin = 30;
  static const int folgaMaximaHoras = 12;

  @override
  State<TvdeVoltaSheet> createState() => _TvdeVoltaSheetState();
}

/// Junta a hora escolhida ao dia certo: se a hora for antes da da ida, é no
/// dia seguinte (ida às 22:00, volta às 01:30).
DateTime tvdeHoraDaVolta(DateTime ida, TimeOfDay hora) {
  var v = DateTime(ida.year, ida.month, ida.day, hora.hour, hora.minute);
  if (!v.isAfter(ida)) v = v.add(const Duration(days: 1));
  return v;
}

/// Mensagem de erro (PT-PT) ou `null` se a hora da volta serve.
String? tvdeValidaVolta(DateTime ida, DateTime volta) {
  final gap = volta.difference(ida);
  if (gap < const Duration(minutes: TvdeVoltaSheet.folgaMinimaMin)) {
    return 'A volta tem de ser pelo menos 30 minutos depois da ida.';
  }
  if (gap > const Duration(hours: TvdeVoltaSheet.folgaMaximaHoras)) {
    return 'A volta tem de ser no máximo 12 horas depois da ida.';
  }
  return null;
}

class _TvdeVoltaSheetState extends State<TvdeVoltaSheet> {
  bool _marcar = false;
  DateTime? _volta;
  String? _erro;

  String _hhmm(DateTime d) =>
      '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';

  Future<void> _escolherHora() async {
    final base = _volta ?? widget.ida.add(const Duration(hours: 2));
    final t = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(hour: base.hour, minute: base.minute),
      helpText: 'Hora da volta'.tr,
    );
    if (t == null || !mounted) return;
    final v = tvdeHoraDaVolta(widget.ida, t);
    setState(() {
      _volta = v;
      _marcar = true;
      _erro = tvdeValidaVolta(widget.ida, v)?.tr;
    });
  }

  @override
  Widget build(BuildContext context) {
    final podeContinuar = !_marcar || (_volta != null && _erro == null);
    return Padding(
      padding: EdgeInsets.fromLTRB(Spacing.lg, Spacing.lg, Spacing.lg,
          Spacing.lg + MediaQuery.of(context).viewInsets.bottom),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('E a volta?'.tr,
              style:
                  const TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
          const SizedBox(height: Spacing.xs),
          Text('Ida às {0}.'.trArgs([_hhmm(widget.ida)]),
              style: const TextStyle(color: AppColors.textSubtle)),
          const SizedBox(height: Spacing.md),
          _Opcao(
            key: const Key('volta_chamo_quando_terminar'),
            selecionada: !_marcar,
            titulo: 'Chamo quando terminar'.tr,
            texto:
                'Fica a volta garantida. Quando acabares, carregas em "Chamar a volta".'
                    .tr,
            onTap: () => setState(() {
              _marcar = false;
              _erro = null;
            }),
          ),
          const SizedBox(height: Spacing.sm),
          _Opcao(
            key: const Key('volta_marcar_hora'),
            selecionada: _marcar,
            titulo: _volta == null
                ? 'Marcar hora da volta'.tr
                : 'Volta às {0}'.trArgs([_hhmm(_volta!)]),
            texto: 'Um motorista vem buscar-te a essa hora.'.tr,
            onTap: _escolherHora,
          ),
          if (_erro != null) ...[
            const SizedBox(height: Spacing.sm),
            Text(_erro!,
                key: const Key('volta_erro'),
                style: const TextStyle(color: AppColors.error)),
          ],
          const SizedBox(height: Spacing.lg),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.primary,
              padding: const EdgeInsets.symmetric(vertical: Spacing.md),
            ),
            onPressed: podeContinuar
                ? () => Navigator.of(context)
                    .pop(TvdeEscolhaVolta(_marcar ? _volta : null))
                : null,
            child: Text('Continuar'.tr),
          ),
        ],
      ),
    );
  }
}

class _Opcao extends StatelessWidget {
  const _Opcao({
    super.key,
    required this.selecionada,
    required this.titulo,
    required this.texto,
    required this.onTap,
  });

  final bool selecionada;
  final String titulo;
  final String texto;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.all(Spacing.md),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: selecionada ? AppColors.primary : AppColors.divider,
            width: selecionada ? 1.5 : 1,
          ),
        ),
        child: Row(
          children: [
            Icon(
              selecionada
                  ? Icons.radio_button_checked
                  : Icons.radio_button_unchecked,
              color: selecionada ? AppColors.primary : AppColors.textSubtle,
            ),
            const SizedBox(width: Spacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(titulo,
                      style: const TextStyle(fontWeight: FontWeight.w700)),
                  const SizedBox(height: 2),
                  Text(texto,
                      style: const TextStyle(
                          fontSize: 12, color: AppColors.textSubtle)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
