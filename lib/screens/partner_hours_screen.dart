import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../config/app_colors.dart';
import '../config/app_spacing.dart';
import '../models/restaurant_model.dart';
import '../stores/restaurant_store.dart';
import '../widgets/bora/bora_primary_button.dart';

class PartnerHoursScreen extends StatefulWidget {
  const PartnerHoursScreen({super.key, required this.restaurant});

  final RestaurantModel restaurant;

  @override
  State<PartnerHoursScreen> createState() => _PartnerHoursScreenState();
}

class _PartnerHoursScreenState extends State<PartnerHoursScreen> {
  late BusinessHours _hours;
  bool _saving = false;

  static const _days = <({int weekday, String label})>[
    (weekday: DateTime.monday, label: 'Segunda-feira'),
    (weekday: DateTime.tuesday, label: 'Terça-feira'),
    (weekday: DateTime.wednesday, label: 'Quarta-feira'),
    (weekday: DateTime.thursday, label: 'Quinta-feira'),
    (weekday: DateTime.friday, label: 'Sexta-feira'),
    (weekday: DateTime.saturday, label: 'Sábado'),
    (weekday: DateTime.sunday, label: 'Domingo'),
  ];

  @override
  void initState() {
    super.initState();
    _hours = widget.restaurant.businessHours;
  }

  void _updateDay(int weekday, DayHours day) {
    setState(() => _hours = _hours.copyWithDay(weekday, day));
  }

  Future<void> _pickTime(
    BuildContext context,
    int weekday,
    bool isOpen,
  ) async {
    final current = _hours.dayFor(weekday);
    final initial = _parseTimeOfDay(isOpen ? current.open : current.close) ??
        const TimeOfDay(hour: 9, minute: 0);
    final picked = await showTimePicker(
      context: context,
      initialTime: initial,
      builder: (ctx, child) => MediaQuery(
        data: MediaQuery.of(ctx).copyWith(alwaysUse24HourFormat: true),
        child: child ?? const SizedBox.shrink(),
      ),
    );
    if (picked == null) return;
    final formatted = _formatTimeOfDay(picked);
    _updateDay(
      weekday,
      isOpen ? current.copyWith(open: formatted) : current.copyWith(close: formatted),
    );
  }

  void _copyMondayToWeekdays() {
    final mon = _hours.mon;
    setState(() {
      _hours = BusinessHours(
        mon: mon,
        tue: mon,
        wed: mon,
        thu: mon,
        fri: mon,
        sat: _hours.sat,
        sun: _hours.sun,
      );
    });
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    await context
        .read<RestaurantStore>()
        .updateBusinessHours(widget.restaurant.id, _hours);
    if (!mounted) return;
    setState(() => _saving = false);
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Horários guardados.')),
    );
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.surface,
      appBar: AppBar(
        title: const Text(
          'Horários de funcionamento',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        backgroundColor: Colors.transparent,
        foregroundColor: Colors.white,
        elevation: 0,
        flexibleSpace: const DecoratedBox(
          decoration: BoxDecoration(gradient: AppColors.headerGradient),
        ),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(Spacing.lg),
          children: [
            const Text(
              'Define as horas de abertura e fecho. Os clientes só conseguem fazer pedidos dentro destas janelas.',
              style: TextStyle(color: AppColors.textSecondary, fontSize: 13),
            ),
            const SizedBox(height: Spacing.lg),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton.icon(
                onPressed: _copyMondayToWeekdays,
                icon: const Icon(Icons.copy_all_outlined, size: 18),
                label: const Text('Copiar Seg para dias úteis'),
              ),
            ),
            const SizedBox(height: Spacing.sm),
            for (final d in _days)
              _DayRow(
                label: d.label,
                hours: _hours.dayFor(d.weekday),
                onToggleClosed: (closed) => _updateDay(
                  d.weekday,
                  _hours.dayFor(d.weekday).copyWith(closed: closed),
                ),
                onTapOpen: () => _pickTime(context, d.weekday, true),
                onTapClose: () => _pickTime(context, d.weekday, false),
              ),
            const SizedBox(height: Spacing.xl),
            BoraPrimaryButton(
              label: 'Guardar',
              loading: _saving,
              onPressed: _saving ? null : _save,
            ),
          ],
        ),
      ),
    );
  }

  static TimeOfDay? _parseTimeOfDay(String hhmm) {
    final parts = hhmm.split(':');
    if (parts.length != 2) return null;
    final h = int.tryParse(parts[0]);
    final m = int.tryParse(parts[1]);
    if (h == null || m == null) return null;
    return TimeOfDay(hour: h, minute: m);
  }

  static String _formatTimeOfDay(TimeOfDay t) {
    final h = t.hour.toString().padLeft(2, '0');
    final m = t.minute.toString().padLeft(2, '0');
    return '$h:$m';
  }
}

class _DayRow extends StatelessWidget {
  const _DayRow({
    required this.label,
    required this.hours,
    required this.onToggleClosed,
    required this.onTapOpen,
    required this.onTapClose,
  });

  final String label;
  final DayHours hours;
  final ValueChanged<bool> onToggleClosed;
  final VoidCallback onTapOpen;
  final VoidCallback onTapClose;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Row(
        children: [
          Expanded(
            flex: 3,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textPrimary,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  hours.closed ? 'Fechado' : '${hours.open} – ${hours.close}',
                  style: TextStyle(
                    fontSize: 12,
                    color: hours.closed
                        ? Colors.red.shade400
                        : AppColors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
          if (!hours.closed) ...[
            _TimePill(value: hours.open, onTap: onTapOpen),
            const SizedBox(width: 6),
            const Text('–', style: TextStyle(color: AppColors.textSecondary)),
            const SizedBox(width: 6),
            _TimePill(value: hours.close, onTap: onTapClose),
            const SizedBox(width: 10),
          ],
          Switch(
            value: !hours.closed,
            onChanged: (open) => onToggleClosed(!open),
            activeColor: AppColors.primary,
          ),
        ],
      ),
    );
  }
}

class _TimePill extends StatelessWidget {
  const _TimePill({required this.value, required this.onTap});

  final String value;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: AppColors.primary.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(8),
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
