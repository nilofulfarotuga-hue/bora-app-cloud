import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../config/app_colors.dart';
import '../../config/app_spacing.dart';
import '../../l10n/tr.dart';
import '../../stores/handyman_store.dart';
import '../../widgets/bora/bora.dart';

/// CASA — disponibilidade semanal do profissional (`casa_definir_disponibilidade`).
/// Molde do `CleanerAvailabilityScreen`: janelas por dia; guardar substitui a
/// grelha inteira.
class HandymanDisponibilidadeScreen extends StatefulWidget {
  const HandymanDisponibilidadeScreen({super.key});

  @override
  State<HandymanDisponibilidadeScreen> createState() =>
      _HandymanDisponibilidadeScreenState();
}

class _HandymanDisponibilidadeScreenState
    extends State<HandymanDisponibilidadeScreen> {
  late List<CasaSlot> _slots;
  bool _dirty = false;

  /// Guarda LOCAL do botão (PADRAO_BORA 3.13), nunca o `busy` do store.
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _slots = List.of(context.read<HandymanStore>().slots);
  }

  Future<void> _save() async {
    if (_saving) return;
    setState(() => _saving = true);
    final store = context.read<HandymanStore>();
    final ok = await store.definirDisponibilidade(_slots);
    if (!mounted) return;
    setState(() {
      _saving = false;
      if (ok) _dirty = false;
    });
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(ok
            ? 'Disponibilidade guardada.'.tr
            : (store.lastError ?? 'Não foi possível guardar.'.tr))));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: BoraScreenAppBar(title: 'A minha disponibilidade'.tr),
      body: ListView(
        padding: EdgeInsets.fromLTRB(Spacing.lg, Spacing.lg, Spacing.lg,
            BoraBottomActionBar.folgaInferior(context)),
        children: [
          Text(
            'Marca os dias e as horas em que aceitas trabalhos. Só recebes ofertas que cabem numa janela que marcaste.'.tr,
            style: const TextStyle(color: AppColors.textSecondary, height: 1.4),
          ),
          const SizedBox(height: Spacing.lg),
          CasaDisponibilidadeEditor(
            slots: _slots,
            onChanged: (s) => setState(() {
              _slots = s;
              _dirty = true;
            }),
          ),
          const SizedBox(height: Spacing.lg),
          BoraPrimaryButton(
            label: 'Guardar disponibilidade'.tr,
            icon: Icons.save,
            loading: _saving,
            onPressed: _dirty
                ? _save
                : () => ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Já está tudo guardado.'.tr))),
          ),
          if (_dirty)
            Padding(
              padding: const EdgeInsets.only(top: Spacing.sm),
              child: Text(
                'Tens alterações por guardar.'.tr,
                textAlign: TextAlign.center,
                style: const TextStyle(color: AppColors.warning, fontSize: 12),
              ),
            ),
        ],
      ),
    );
  }
}

/// A grelha semanal (segunda a domingo), partilhada pela candidatura e pelo
/// ecrã da disponibilidade. weekday interno: 0 = domingo … 6 = sábado.
class CasaDisponibilidadeEditor extends StatelessWidget {
  const CasaDisponibilidadeEditor({
    super.key,
    required this.slots,
    required this.onChanged,
    this.enabled = true,
  });

  final List<CasaSlot> slots;
  final ValueChanged<List<CasaSlot>> onChanged;
  final bool enabled;

  static String _fmt(TimeOfDay t) =>
      '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

  Future<void> _adicionar(BuildContext context, int weekday) async {
    final start = await showTimePicker(
      context: context,
      initialTime: const TimeOfDay(hour: 9, minute: 0),
      helpText: 'Início da janela'.tr,
    );
    if (start == null || !context.mounted) return;
    final end = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(hour: (start.hour + 4).clamp(0, 23), minute: 0),
      helpText: 'Fim da janela'.tr,
    );
    if (end == null || !context.mounted) return;
    if (end.hour * 60 + end.minute <= start.hour * 60 + start.minute) {
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('O fim tem de ser depois do início.'.tr)));
      return;
    }
    onChanged([
      ...slots,
      CasaSlot(weekday: weekday, start: _fmt(start), end: _fmt(end)),
    ]);
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (slots.isEmpty)
          Container(
            margin: const EdgeInsets.only(bottom: Spacing.md),
            padding: const EdgeInsets.all(Spacing.md),
            decoration: BoxDecoration(
              color: AppColors.warning.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(Radii.lg),
              border: Border.all(color: AppColors.warning.withValues(alpha: 0.4)),
            ),
            child: Row(
              children: [
                const Icon(Icons.touch_app_outlined, color: AppColors.warning),
                const SizedBox(width: Spacing.md),
                Expanded(
                  child: Text(
                    'Ainda não marcaste nada. Toca no + de um dia para adicionar um horário.'.tr,
                    style: const TextStyle(color: AppColors.textPrimary),
                  ),
                ),
              ],
            ),
          ),
        for (var i = 1; i <= 7; i++)
          _Dia(
            weekday: i % 7,
            slots: slots.where((s) => s.weekday == i % 7).toList()
              ..sort((a, b) => a.start.compareTo(b.start)),
            enabled: enabled,
            onAdd: (w) => _adicionar(context, w),
            onRemove: (s) => onChanged(List.of(slots)..remove(s)),
          ),
      ],
    );
  }
}

class _Dia extends StatelessWidget {
  const _Dia({
    required this.weekday,
    required this.slots,
    required this.enabled,
    required this.onAdd,
    required this.onRemove,
  });

  final int weekday;
  final List<CasaSlot> slots;
  final bool enabled;
  final void Function(int weekday) onAdd;
  final void Function(CasaSlot slot) onRemove;

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
                child: Text(casaNomeDoDia(weekday),
                    style: const TextStyle(
                        fontWeight: FontWeight.w700,
                        color: AppColors.textPrimary)),
              ),
              IconButton(
                onPressed: enabled ? () => onAdd(weekday) : null,
                icon: const Icon(Icons.add_circle_outline,
                    color: AppColors.primary),
                tooltip: 'Adicionar janela'.tr,
              ),
            ],
          ),
          if (slots.isEmpty)
            Text('Indisponível'.tr,
                style: const TextStyle(color: AppColors.textSubtle, fontSize: 13))
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
                    onDeleted: enabled ? () => onRemove(s) : null,
                  ),
              ],
            ),
        ],
      ),
    );
  }
}
