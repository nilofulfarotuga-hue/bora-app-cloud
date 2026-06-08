import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../config/app_colors.dart';
import '../../../config/app_spacing.dart';
import '../../../models/staff_member_model.dart';
import '../../../stores/partner_appointments_store.dart';
import '../../../widgets/bora/bora_accent_button.dart';
import '../../../widgets/bora/bora_screen_app_bar.dart';

/// Bloquear um intervalo de um barbeiro (pausa, folga). Escolher barbeiro +
/// data + hora início/fim + motivo → partner_block_slot.
class PartnerBlockSlotScreen extends StatefulWidget {
  const PartnerBlockSlotScreen({super.key});

  @override
  State<PartnerBlockSlotScreen> createState() => _PartnerBlockSlotScreenState();
}

class _PartnerBlockSlotScreenState extends State<PartnerBlockSlotScreen> {
  final _reasonCtrl = TextEditingController();

  List<StaffMemberModel> _staff = const [];
  StaffMemberModel? _staffMember;

  DateTime _day = DateTime.now();
  TimeOfDay _start = const TimeOfDay(hour: 12, minute: 0);
  TimeOfDay _end = const TimeOfDay(hour: 13, minute: 0);

  bool _loading = true;
  String? _loadError;
  bool _submitting = false;

  @override
  void initState() {
    super.initState();
    _loadStaff();
  }

  @override
  void dispose() {
    _reasonCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadStaff() async {
    setState(() {
      _loading = true;
      _loadError = null;
    });
    try {
      final staff = await context.read<PartnerAppointmentsStore>().fetchStaff();
      if (!mounted) return;
      setState(() {
        _staff = staff;
        _staffMember = staff.isNotEmpty ? staff.first : null;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loadError = e.toString().replaceFirst('Exception: ', '');
        _loading = false;
      });
    }
  }

  Future<void> _pickDay() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _day,
      firstDate: DateTime(now.year, now.month, now.day),
      lastDate: now.add(const Duration(days: 90)),
    );
    if (picked != null) setState(() => _day = picked);
  }

  Future<void> _pickTime({required bool isStart}) async {
    final picked = await showTimePicker(
      context: context,
      initialTime: isStart ? _start : _end,
    );
    if (picked == null) return;
    setState(() {
      if (isStart) {
        _start = picked;
      } else {
        _end = picked;
      }
    });
  }

  DateTime _combine(TimeOfDay t) =>
      DateTime(_day.year, _day.month, _day.day, t.hour, t.minute);

  Future<void> _submit() async {
    if (_submitting) return;
    final staff = _staffMember;
    final messenger = ScaffoldMessenger.of(context);
    if (staff == null) {
      messenger.showSnackBar(
        const SnackBar(content: Text('Escolhe um barbeiro.')),
      );
      return;
    }
    final startAt = _combine(_start);
    final endAt = _combine(_end);
    if (!endAt.isAfter(startAt)) {
      messenger.showSnackBar(
        const SnackBar(content: Text('A hora de fim tem de ser depois do início.')),
      );
      return;
    }
    setState(() => _submitting = true);
    try {
      await context.read<PartnerAppointmentsStore>().blockSlot(
            staffId: staff.id,
            startAt: startAt,
            endAt: endAt,
            reason: _reasonCtrl.text.trim().isEmpty
                ? null
                : _reasonCtrl.text.trim(),
          );
      if (!mounted) return;
      messenger.showSnackBar(const SnackBar(
        content: Text('Horário bloqueado.'),
        backgroundColor: AppColors.success,
      ));
      Navigator.pop(context);
    } catch (e) {
      if (!mounted) return;
      messenger.showSnackBar(SnackBar(
        content: Text(e.toString().replaceFirst('Exception: ', '')),
        backgroundColor: AppColors.error,
      ));
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  String _two(int v) => v.toString().padLeft(2, '0');

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: const BoraScreenAppBar(title: 'Bloquear horário'),
      body: SafeArea(
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : _loadError != null
                ? _errorState()
                : _staff.isEmpty
                    ? _noStaffState()
                    : _form(),
      ),
    );
  }

  Widget _form() {
    return Column(
      children: [
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(Spacing.lg),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _Section(
                  title: 'Barbeiro',
                  child: DropdownButtonFormField<StaffMemberModel>(
                    initialValue: _staffMember,
                    isExpanded: true,
                    decoration: const InputDecoration(
                      border: OutlineInputBorder(),
                    ),
                    items: _staff
                        .map((s) => DropdownMenuItem(
                              value: s,
                              child: Text(s.name,
                                  overflow: TextOverflow.ellipsis),
                            ))
                        .toList(),
                    onChanged: (v) => setState(() => _staffMember = v),
                  ),
                ),
                const SizedBox(height: Spacing.md),
                _Section(
                  title: 'Data',
                  child: OutlinedButton.icon(
                    onPressed: _pickDay,
                    icon: const Icon(Icons.calendar_today, size: 18),
                    label: Text(
                      '${_two(_day.day)}/${_two(_day.month)}/${_day.year}',
                    ),
                  ),
                ),
                const SizedBox(height: Spacing.md),
                _Section(
                  title: 'Intervalo',
                  child: Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: () => _pickTime(isStart: true),
                          icon: const Icon(Icons.schedule, size: 18),
                          label: Text(
                              'Início ${_two(_start.hour)}:${_two(_start.minute)}'),
                        ),
                      ),
                      const SizedBox(width: Spacing.sm),
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: () => _pickTime(isStart: false),
                          icon: const Icon(Icons.schedule, size: 18),
                          label: Text(
                              'Fim ${_two(_end.hour)}:${_two(_end.minute)}'),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: Spacing.md),
                _Section(
                  title: 'Motivo (opcional)',
                  child: TextField(
                    controller: _reasonCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Ex.: almoço, folga',
                      border: OutlineInputBorder(),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        SafeArea(
          top: false,
          minimum: const EdgeInsets.fromLTRB(
              Spacing.lg, Spacing.sm, Spacing.lg, Spacing.lg),
          child: BoraAccentButton(
            label: 'Bloquear',
            icon: Icons.block,
            loading: _submitting,
            onPressed: _submit,
          ),
        ),
      ],
    );
  }

  Widget _errorState() => Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline,
                  size: 48, color: AppColors.error),
              const SizedBox(height: 12),
              Text(_loadError!, textAlign: TextAlign.center),
              const SizedBox(height: 12),
              ElevatedButton(
                onPressed: _loadStaff,
                child: const Text('Tentar de novo'),
              ),
            ],
          ),
        ),
      );

  Widget _noStaffState() => const Center(
        child: Padding(
          padding: EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.info_outline, size: 64, color: Colors.grey),
              SizedBox(height: 16),
              Text(
                'Sem barbeiros',
                style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
              ),
              SizedBox(height: 6),
              Text(
                'Cria um barbeiro primeiro para poder bloquear horários.',
                textAlign: TextAlign.center,
                style: TextStyle(color: AppColors.textSecondary),
              ),
            ],
          ),
        ),
      );
}

class _Section extends StatelessWidget {
  const _Section({required this.title, required this.child});
  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(Radii.lg),
        boxShadow: AppColors.shadowCard,
      ),
      padding: const EdgeInsets.all(Spacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(
              fontWeight: FontWeight.w700,
              color: AppColors.textPrimary,
            ),
          ),
          const SizedBox(height: Spacing.sm),
          child,
        ],
      ),
    );
  }
}
