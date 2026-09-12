import 'package:flutter/material.dart';

import '../../config/app_colors.dart';
import '../../config/app_spacing.dart';
import '../../models/weekly_hours.dart';

/// BLOCO C (2026-07-28) — editor de horário semanal partilhado.
///
/// Usado pelo ecrã do parceiro (PT-PT) e pelo painel admin (PT-BR): a mesma
/// lógica de validação nos dois sítios, para não haver duas verdades. O idioma
/// dos rótulos vem de [ptBr].
class WeeklyHoursEditor extends StatelessWidget {
  const WeeklyHoursEditor({
    super.key,
    required this.week,
    required this.onChanged,
    this.ptBr = false,
    this.enabled = true,
  });

  final Map<int, DayHours> week;
  final ValueChanged<Map<int, DayHours>> onChanged;
  final bool ptBr;
  final bool enabled;

  void _update(int dow, DayHours value) {
    onChanged({...week, dow: value});
  }

  Future<void> _pickTime(
    BuildContext context,
    String current,
    ValueChanged<String> onPicked,
  ) async {
    final parts = current.split(':');
    final initial = TimeOfDay(
      hour: int.tryParse(parts.first) ?? 9,
      minute: parts.length > 1 ? (int.tryParse(parts[1]) ?? 0) : 0,
    );
    final picked = await showTimePicker(
      context: context,
      initialTime: initial,
      builder: (ctx, child) => MediaQuery(
        data: MediaQuery.of(ctx).copyWith(alwaysUse24HourFormat: true),
        child: child!,
      ),
    );
    if (picked == null) return;
    onPicked('${picked.hour.toString().padLeft(2, '0')}:'
        '${picked.minute.toString().padLeft(2, '0')}');
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        for (final dow in kWeekdayDisplayOrder)
          _DayCard(
            dow: dow,
            hours: week[dow] ?? DayHours.defaultOpen,
            ptBr: ptBr,
            enabled: enabled,
            onChanged: (v) => _update(dow, v),
            onPickTime: _pickTime,
          ),
      ],
    );
  }
}

class _DayCard extends StatelessWidget {
  const _DayCard({
    required this.dow,
    required this.hours,
    required this.ptBr,
    required this.enabled,
    required this.onChanged,
    required this.onPickTime,
  });

  final int dow;
  final DayHours hours;
  final bool ptBr;
  final bool enabled;
  final ValueChanged<DayHours> onChanged;
  final Future<void> Function(BuildContext, String, ValueChanged<String>)
      onPickTime;

  @override
  Widget build(BuildContext context) {
    final error = hours.validate(ptBr: ptBr);
    return Container(
      margin: const EdgeInsets.only(bottom: Spacing.sm),
      padding: const EdgeInsets.all(Spacing.md),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(Radii.md),
        border: Border.all(
          color: error == null ? AppColors.divider : AppColors.error,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  kWeekdayNamesPt[dow],
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 15,
                    color: AppColors.textPrimary,
                  ),
                ),
              ),
              Text(
                hours.isWorking
                    ? (ptBr ? 'Aberto' : 'Aberto')
                    : (ptBr ? 'Fechado' : 'Fechado'),
                style: TextStyle(
                  fontSize: 12.5,
                  color: hours.isWorking
                      ? AppColors.success
                      : AppColors.textSubtle,
                  fontWeight: FontWeight.w600,
                ),
              ),
              Switch(
                value: hours.isWorking,
                onChanged: enabled
                    ? (v) => onChanged(hours.copyWith(isWorking: v))
                    : null,
              ),
            ],
          ),
          if (hours.isWorking) ...[
            const SizedBox(height: Spacing.xs),
            Row(
              children: [
                Expanded(
                  child: _TimeField(
                    label: ptBr ? 'Abertura' : 'Abertura',
                    value: hours.start,
                    enabled: enabled,
                    onTap: () => onPickTime(context, hours.start,
                        (v) => onChanged(hours.copyWith(start: v))),
                  ),
                ),
                const SizedBox(width: Spacing.sm),
                Expanded(
                  child: _TimeField(
                    label: ptBr ? 'Fechamento' : 'Fecho',
                    value: hours.end,
                    enabled: enabled,
                    onTap: () => onPickTime(context, hours.end,
                        (v) => onChanged(hours.copyWith(end: v))),
                  ),
                ),
              ],
            ),
            const SizedBox(height: Spacing.sm),
            if (hours.hasBreak)
              Row(
                children: [
                  Expanded(
                    child: _TimeField(
                      label: ptBr ? 'Início da pausa' : 'Início da pausa',
                      value: hours.breakStart!,
                      enabled: enabled,
                      onTap: () => onPickTime(context, hours.breakStart!,
                          (v) => onChanged(hours.copyWith(breakStart: v))),
                    ),
                  ),
                  const SizedBox(width: Spacing.sm),
                  Expanded(
                    child: _TimeField(
                      label: ptBr ? 'Fim da pausa' : 'Fim da pausa',
                      value: hours.breakEnd!,
                      enabled: enabled,
                      onTap: () => onPickTime(context, hours.breakEnd!,
                          (v) => onChanged(hours.copyWith(breakEnd: v))),
                    ),
                  ),
                  IconButton(
                    tooltip: ptBr ? 'Remover pausa' : 'Remover pausa',
                    icon: const Icon(Icons.close, size: 20),
                    color: AppColors.error,
                    onPressed: enabled
                        ? () => onChanged(hours.copyWith(clearBreak: true))
                        : null,
                  ),
                ],
              )
            else
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  onPressed: enabled
                      ? () => onChanged(hours.copyWith(
                            breakStart: '13:00',
                            breakEnd: '14:00',
                          ))
                      : null,
                  icon: const Icon(Icons.free_breakfast_outlined, size: 18),
                  label: Text(ptBr ? 'Adicionar pausa' : 'Adicionar pausa'),
                ),
              ),
          ],
          if (error != null) ...[
            const SizedBox(height: Spacing.xxs),
            Text(
              error,
              style: const TextStyle(fontSize: 12, color: AppColors.error),
            ),
          ],
        ],
      ),
    );
  }
}

class _TimeField extends StatelessWidget {
  const _TimeField({
    required this.label,
    required this.value,
    required this.onTap,
    required this.enabled,
  });

  final String label;
  final String value;
  final VoidCallback onTap;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: enabled ? onTap : null,
      borderRadius: BorderRadius.circular(Radii.sm),
      child: InputDecorator(
        decoration: InputDecoration(
          labelText: label,
          isDense: true,
          border: const OutlineInputBorder(),
          contentPadding: const EdgeInsets.symmetric(
              horizontal: Spacing.sm, vertical: Spacing.sm),
        ),
        child: Text(
          value,
          style: const TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w700,
            color: AppColors.textPrimary,
          ),
        ),
      ),
    );
  }
}
