import 'package:flutter/material.dart';

import '../config/app_colors.dart';
import '../config/app_spacing.dart';
import '../models/restaurant_model.dart';

/// Pausa do dia de uma loja (27/10/2026, Boom! Burger: 14:30–19:00).
///
/// Usado no ecrã de horários do parceiro (PT-PT) e no painel admin (PT-BR,
/// [ptBr]) — a mesma validação ([DayHours.erroPausa]) nos dois sítios, como o
/// `WeeklyHoursEditor` dos serviços. Sem pausa mostra "Adicionar pausa"; com
/// pausa mostra o início e o fim (toca-se para mudar) e um botão para a tirar.
class PausaDoDiaEditor extends StatelessWidget {
  const PausaDoDiaEditor({
    super.key,
    required this.day,
    required this.onChanged,
    this.ptBr = false,
  });

  final DayHours day;
  final ValueChanged<DayHours> onChanged;
  final bool ptBr;

  Future<void> _escolherHora(
    BuildContext context,
    String atual,
    ValueChanged<String> onEscolhida,
  ) async {
    final parts = atual.split(':');
    final picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(
        hour: int.tryParse(parts.first) ?? 13,
        minute: parts.length > 1 ? (int.tryParse(parts[1]) ?? 0) : 0,
      ),
      builder: (ctx, child) => MediaQuery(
        data: MediaQuery.of(ctx).copyWith(alwaysUse24HourFormat: true),
        child: child ?? const SizedBox.shrink(),
      ),
    );
    if (picked == null) return;
    onEscolhida('${picked.hour.toString().padLeft(2, '0')}:'
        '${picked.minute.toString().padLeft(2, '0')}');
  }

  /// Pausa de partida: 13:00–14:00 se couber no horário; senão a 2.ª hora
  /// depois de abrir (ex.: segunda 19:00–22:30 → 20:00–21:00).
  DayHours _comPausaSugerida() {
    final almoco = day.copyWith(breakStart: '13:00', breakEnd: '14:00');
    if (almoco.erroPausa() == null) return almoco;
    final p = day.open.split(':');
    final h = p.length == 2 ? int.tryParse(p[0]) : null;
    if (h == null || h + 2 > 23) return almoco;
    String hh(int n) => '${n.toString().padLeft(2, '0')}:${p[1]}';
    return day.copyWith(breakStart: hh(h + 1), breakEnd: hh(h + 2));
  }

  @override
  Widget build(BuildContext context) {
    final erro = day.erroPausa(ptBr: ptBr);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (day.temPausa)
          Row(
            children: [
              const Icon(Icons.free_breakfast_outlined,
                  size: 18, color: AppColors.textSecondary),
              const SizedBox(width: Spacing.xs),
              const Text('Pausa',
                  style:
                      TextStyle(fontSize: 13, color: AppColors.textSecondary)),
              const SizedBox(width: Spacing.sm),
              _HoraPausa(
                key: const ValueKey('pausa-inicio'),
                value: day.breakStart!,
                onTap: () => _escolherHora(context, day.breakStart!,
                    (v) => onChanged(day.copyWith(breakStart: v))),
              ),
              const SizedBox(width: 6),
              const Text('–',
                  style: TextStyle(color: AppColors.textSecondary)),
              const SizedBox(width: 6),
              _HoraPausa(
                key: const ValueKey('pausa-fim'),
                value: day.breakEnd!,
                onTap: () => _escolherHora(context, day.breakEnd!,
                    (v) => onChanged(day.copyWith(breakEnd: v))),
              ),
              const Spacer(),
              IconButton(
                tooltip: ptBr ? 'Remover pausa' : 'Tirar pausa',
                icon: const Icon(Icons.close, size: 20),
                color: AppColors.error,
                onPressed: () => onChanged(day.copyWith(semPausa: true)),
              ),
            ],
          )
        else
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: () => onChanged(_comPausaSugerida()),
              icon: const Icon(Icons.free_breakfast_outlined, size: 18),
              label: const Text('Adicionar pausa'),
            ),
          ),
        if (erro != null)
          Padding(
            padding: const EdgeInsets.only(top: Spacing.xxs),
            child: Text(
              erro,
              style: const TextStyle(fontSize: 12, color: AppColors.error),
            ),
          ),
      ],
    );
  }
}

class _HoraPausa extends StatelessWidget {
  const _HoraPausa({super.key, required this.value, required this.onTap});

  final String value;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(Radii.sm),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: AppColors.primary.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(Radii.sm),
          border: Border.all(color: AppColors.primary.withValues(alpha: 0.25)),
        ),
        child: Text(
          value,
          style: const TextStyle(
            fontWeight: FontWeight.w700,
            color: AppColors.primary,
          ),
        ),
      ),
    );
  }
}
