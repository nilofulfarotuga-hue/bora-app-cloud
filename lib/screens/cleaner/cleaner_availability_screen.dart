import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../config/app_colors.dart';
import '../../config/app_spacing.dart';
import '../../models/cleaning_models.dart';
import '../../stores/cleaner_store.dart';
import '../../widgets/bora/bora.dart';

/// LIMPEZA — agenda semanal da profissional (cleaner_availability).
/// Janelas por dia da semana; guardar substitui a grelha inteira (RPC).
class CleanerAvailabilityScreen extends StatefulWidget {
  const CleanerAvailabilityScreen({super.key});

  @override
  State<CleanerAvailabilityScreen> createState() =>
      _CleanerAvailabilityScreenState();
}

class _CleanerAvailabilityScreenState extends State<CleanerAvailabilityScreen> {
  late List<CleanerSlot> _slots;
  bool _dirty = false;

  @override
  void initState() {
    super.initState();
    _slots = List.of(context.read<CleanerStore>().slots);
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      final store = context.read<CleanerStore>();
      await store.loadSlots();
      if (mounted && !_dirty) setState(() => _slots = List.of(store.slots));
    });
  }

  Future<void> _addSlot(int weekday) async {
    final start = await showTimePicker(
      context: context,
      initialTime: const TimeOfDay(hour: 9, minute: 0),
      helpText: 'Início da janela',
    );
    if (start == null || !mounted) return;
    final end = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(hour: (start.hour + 4).clamp(0, 23), minute: 0),
      helpText: 'Fim da janela',
    );
    if (end == null || !mounted) return;
    final startMin = start.hour * 60 + start.minute;
    final endMin = end.hour * 60 + end.minute;
    if (endMin <= startMin) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('O fim tem de ser depois do início.')));
      return;
    }
    String fmt(TimeOfDay t) =>
        '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';
    setState(() {
      _slots.add(
          CleanerSlot(weekday: weekday, start: fmt(start), end: fmt(end)));
      _dirty = true;
    });
  }

  void _removeSlot(CleanerSlot slot) {
    setState(() {
      _slots.remove(slot);
      _dirty = true;
    });
  }

  Future<void> _save() async {
    final store = context.read<CleanerStore>();
    try {
      await store.saveSlots(_slots);
      if (!mounted) return;
      setState(() => _dirty = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Agenda guardada. 💚')),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Não foi possível guardar a agenda.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final store = context.watch<CleanerStore>();
    final nothingMarked = _slots.isEmpty;
    return Scaffold(
      appBar: const BoraScreenAppBar(title: 'A minha disponibilidade'),
      body: ListView(
        padding: const EdgeInsets.all(Spacing.lg),
        children: [
          const Text(
            'Marca os dias e as horas em que aceitas limpezas. Só recebes '
            'ofertas que cabem por inteiro numa janela que marcaste.',
            style: TextStyle(color: AppColors.textSecondary, height: 1.4),
          ),
          if (nothingMarked) ...[
            const SizedBox(height: Spacing.md),
            Container(
              padding: const EdgeInsets.all(Spacing.md),
              decoration: BoxDecoration(
                color: AppColors.warning.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(Radii.lg),
                border:
                    Border.all(color: AppColors.warning.withValues(alpha: 0.4)),
              ),
              child: const Row(
                children: [
                  Icon(Icons.touch_app_outlined, color: AppColors.warning),
                  SizedBox(width: Spacing.md),
                  Expanded(
                    child: Text(
                      'Ainda não marcaste nada. Toca no + de um dia para '
                      'adicionar um horário e depois guarda.',
                      style: TextStyle(color: AppColors.textPrimary),
                    ),
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: Spacing.lg),
          for (var weekday = 1; weekday <= 7; weekday++)
            _DayRow(
              // ordem Seg..Dom na UI; weekday interno 0=Dom…6=Sáb
              weekday: weekday % 7,
              slots: _slots
                  .where((s) => s.weekday == weekday % 7)
                  .toList()
                ..sort((a, b) => a.start.compareTo(b.start)),
              onAdd: _addSlot,
              onRemove: _removeSlot,
            ),
          const SizedBox(height: Spacing.lg),
          BoraPrimaryButton(
            label: 'Guardar disponibilidade',
            icon: Icons.save,
            loading: store.busy,
            onPressed: _dirty
                ? _save
                : () {
                    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                        content: Text('Já está tudo guardado.')));
                  },
          ),
          if (_dirty)
            const Padding(
              padding: EdgeInsets.only(top: Spacing.sm),
              child: Text(
                'Tens alterações por guardar.',
                textAlign: TextAlign.center,
                style: TextStyle(color: AppColors.warning, fontSize: 12),
              ),
            ),
        ],
      ),
    );
  }
}

class _DayRow extends StatelessWidget {
  const _DayRow({
    required this.weekday,
    required this.slots,
    required this.onAdd,
    required this.onRemove,
  });

  final int weekday;
  final List<CleanerSlot> slots;
  final void Function(int weekday) onAdd;
  final void Function(CleanerSlot slot) onRemove;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: Spacing.sm),
      padding: const EdgeInsets.all(Spacing.md),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(Radii.lg),
        border: Border.all(color: AppColors.divider),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(CleanerSlot.weekdaysPt[weekday],
                    style: const TextStyle(
                        fontWeight: FontWeight.w700,
                        color: AppColors.textPrimary)),
              ),
              IconButton(
                onPressed: () => onAdd(weekday),
                icon: const Icon(Icons.add_circle_outline,
                    color: AppColors.primary),
                tooltip: 'Adicionar janela',
              ),
            ],
          ),
          if (slots.isEmpty)
            const Text('Indisponível',
                style:
                    TextStyle(color: AppColors.textSubtle, fontSize: 13))
          else
            Wrap(
              spacing: Spacing.sm,
              runSpacing: Spacing.xs,
              children: [
                for (final s in slots)
                  Chip(
                    label: Text('${s.start}–${s.end}'),
                    backgroundColor: AppColors.primaryWash,
                    labelStyle: const TextStyle(
                        color: AppColors.primary,
                        fontWeight: FontWeight.w600,
                        fontSize: 13),
                    deleteIcon: const Icon(Icons.close, size: 16),
                    onDeleted: () => onRemove(s),
                  ),
              ],
            ),
        ],
      ),
    );
  }
}
