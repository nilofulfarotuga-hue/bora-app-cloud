import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../config/app_colors.dart';
import '../config/app_spacing.dart';
import '../models/restaurant_model.dart';
import '../stores/restaurant_store.dart';
import '../utils/hora_lisboa.dart';
import '../widgets/bora/bora_primary_button.dart';
import '../widgets/bora/bora_screen_app_bar.dart';

class PartnerHoursScreen extends StatefulWidget {
  const PartnerHoursScreen({super.key, required this.restaurant});

  final RestaurantModel restaurant;

  @override
  State<PartnerHoursScreen> createState() => _PartnerHoursScreenState();
}

class _PartnerHoursScreenState extends State<PartnerHoursScreen> {
  late BusinessHours _hours;
  bool _saving = false;

  // Dias fechados (feriados/férias) — business_hours.special_dates.
  List<DateTime> _diasFechados = const [];
  bool _diasCarregados = false;
  bool _aGuardarDias = false;

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
    _carregarDiasFechados();
  }

  Future<void> _carregarDiasFechados() async {
    final dias = await context
        .read<RestaurantStore>()
        .fetchDiasFechados(widget.restaurant.id);
    if (!mounted) return;
    // "Hoje" é o dia de Lisboa — o servidor lê os dias fechados por Lisboa.
    final hoje = horaLisboa(DateTime.now());
    final hojeSo = DateTime(hoje.year, hoje.month, hoje.day);
    setState(() {
      _diasFechados = dias.where((d) => !d.isBefore(hojeSo)).toList();
      _diasCarregados = true;
    });
  }

  Future<void> _guardarDias(List<DateTime> novos) async {
    if (_aGuardarDias) return;
    setState(() => _aGuardarDias = true);
    final ok = await context
        .read<RestaurantStore>()
        .guardarDiasFechados(widget.restaurant.id, novos);
    if (!mounted) return;
    setState(() {
      _aGuardarDias = false;
      if (ok) _diasFechados = (List<DateTime>.of(novos)..sort());
    });
    if (!ok) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text(
              'Não foi possível guardar os dias fechados. Tenta de novo.')));
    }
  }

  Future<void> _adicionarDiaFechado() async {
    final hoje = horaLisboa(DateTime.now());
    final escolhido = await showDatePicker(
      context: context,
      initialDate: hoje,
      firstDate: DateTime(hoje.year, hoje.month, hoje.day),
      lastDate: hoje.add(const Duration(days: 365)),
      helpText: 'Dia em que a loja está fechada',
    );
    if (escolhido == null || !mounted) return;
    final d = DateTime(escolhido.year, escolhido.month, escolhido.day);
    if (_diasFechados.contains(d)) return;
    await _guardarDias([..._diasFechados, d]);
  }

  static String _dataPt(DateTime d) {
    const dias = ['seg', 'ter', 'qua', 'qui', 'sex', 'sáb', 'dom'];
    String dd(int n) => n.toString().padLeft(2, '0');
    return '${dias[d.weekday - 1]}, ${dd(d.day)}/${dd(d.month)}/${d.year}';
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
    if (_saving) return;
    setState(() => _saving = true);
    var ok = false;
    try {
      ok = await context
          .read<RestaurantStore>()
          .updateBusinessHours(widget.restaurant.id, _hours);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
    if (!mounted) return;
    if (!ok) {
      // 2026-10-03: antes dizia "guardados" mesmo quando falhava.
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text(
                'Não foi possível guardar os horários. Verifica a ligação e tenta de novo.')),
      );
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Horários guardados.')),
    );
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: const BoraScreenAppBar(title: 'Horários de funcionamento'),
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
            const SizedBox(height: Spacing.xl),
            const Text(
              'Dias fechados (feriados, férias)',
              style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 4),
            const Text(
              'Nestes dias a loja aparece fechada o dia todo. Fica guardado logo.',
              style: TextStyle(color: AppColors.textSecondary, fontSize: 13),
            ),
            const SizedBox(height: Spacing.sm),
            if (!_diasCarregados)
              const Padding(
                padding: EdgeInsets.all(8),
                child: LinearProgressIndicator(),
              )
            else
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final d in _diasFechados)
                    InputChip(
                      label: Text(_dataPt(d)),
                      onDeleted: _aGuardarDias
                          ? null
                          : () => _guardarDias(
                              _diasFechados.where((x) => x != d).toList()),
                    ),
                  ActionChip(
                    avatar: _aGuardarDias
                        ? const SizedBox(
                            width: 14,
                            height: 14,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.add, size: 18),
                    label: const Text('Adicionar dia'),
                    onPressed: _aGuardarDias ? null : _adicionarDiaFechado,
                  ),
                ],
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
        border: Border.all(color: AppColors.divider),
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
