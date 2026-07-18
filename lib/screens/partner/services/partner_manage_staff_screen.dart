import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../config/app_colors.dart';
import '../../../config/app_spacing.dart';
import '../../../models/staff_member_model.dart';
import '../../../stores/partner_appointments_store.dart';
import '../../../utils/staff_terminology.dart';
import '../../../widgets/bora/bora_primary_button.dart';
import '../../../widgets/bora/bora_screen_app_bar.dart';

/// Gestão de profissionais (foto, nome, especialidades) — "Barbeiro" só
/// quando `category == 'barbershop'`, senão termo genérico "Profissional"
/// (cabeleireiro, manicure, esteticista, etc.). Criar/editar via
/// bottom-sheet, desactivar (soft delete), editar disponibilidade semanal.
class PartnerManageStaffScreen extends StatefulWidget {
  const PartnerManageStaffScreen({super.key});

  @override
  State<PartnerManageStaffScreen> createState() =>
      _PartnerManageStaffScreenState();
}

class _PartnerManageStaffScreenState extends State<PartnerManageStaffScreen> {
  late Future<List<StaffMemberModel>> _future;

  @override
  void initState() {
    super.initState();
    _future = context.read<PartnerAppointmentsStore>().fetchStaff();
  }

  void _refresh() {
    setState(() {
      _future = context.read<PartnerAppointmentsStore>().fetchStaff();
    });
  }

  Future<void> _openForm({StaffMemberModel? existing}) async {
    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => _StaffForm(existing: existing),
    );
    if (saved == true) _refresh();
  }

  void _openAvailability(StaffMemberModel s) {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => _StaffAvailabilityScreen(staff: s)),
    );
  }

  Future<void> _confirmDeactivate(StaffMemberModel s) async {
    final store = context.read<PartnerAppointmentsStore>();
    final term = StaffTerminology.singular(store.provider?.category);
    final messenger = ScaffoldMessenger.of(context);
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Desactivar ${term.toLowerCase()}'),
        content: Text('Remover "${s.name}" da equipa? O histórico mantém-se.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar'),
          ),
          TextButton(
            style: TextButton.styleFrom(foregroundColor: AppColors.error),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Desactivar'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await store.deactivateStaff(s.id);
      if (!mounted) return;
      messenger.showSnackBar(SnackBar(
        content: Text('$term desactivado.'),
        backgroundColor: AppColors.success,
      ));
      _refresh();
    } catch (e) {
      if (!mounted) return;
      messenger.showSnackBar(SnackBar(
        content: Text(e.toString().replaceFirst('Exception: ', '')),
        backgroundColor: AppColors.error,
      ));
    }
  }

  @override
  Widget build(BuildContext context) {
    final category = context.watch<PartnerAppointmentsStore>().provider?.category;
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: BoraScreenAppBar(title: StaffTerminology.plural(category)),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _openForm(),
        backgroundColor: AppColors.accent,
        foregroundColor: Colors.white,
        icon: const Icon(Icons.add),
        label: Text('Novo ${StaffTerminology.singular(category).toLowerCase()}'),
      ),
      body: FutureBuilder<List<StaffMemberModel>>(
        future: _future,
        builder: (context, snap) {
          if (snap.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snap.hasError) {
            return _error(snap.error.toString());
          }
          final items = snap.data ?? const <StaffMemberModel>[];
          if (items.isEmpty) {
            return _empty(category);
          }
          return RefreshIndicator(
            onRefresh: () async => _refresh(),
            child: ListView.builder(
              padding: const EdgeInsets.fromLTRB(
                  Spacing.lg, Spacing.lg, Spacing.lg, 88),
              itemCount: items.length,
              itemBuilder: (_, i) => _StaffTile(
                staff: items[i],
                onEdit: () => _openForm(existing: items[i]),
                onAvailability: () => _openAvailability(items[i]),
                onDeactivate: () => _confirmDeactivate(items[i]),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _error(String e) => Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline,
                  size: 48, color: AppColors.error),
              const SizedBox(height: 12),
              Text(e.replaceFirst('Exception: ', ''),
                  textAlign: TextAlign.center),
              const SizedBox(height: 12),
              ElevatedButton(
                onPressed: _refresh,
                child: const Text('Tentar de novo'),
              ),
            ],
          ),
        ),
      );

  Widget _empty(String? category) {
    final pluralLower = StaffTerminology.plural(category).toLowerCase();
    final singularLower = StaffTerminology.singular(category).toLowerCase();
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.people_alt_outlined, size: 64, color: Colors.grey),
            const SizedBox(height: 16),
            Text(
              'Sem $pluralLower',
              style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 6),
            Text(
              'Adiciona o primeiro $singularLower no botão "Novo $singularLower".',
              textAlign: TextAlign.center,
              style: const TextStyle(color: AppColors.textSecondary),
            ),
          ],
        ),
      ),
    );
  }
}

class _StaffTile extends StatelessWidget {
  const _StaffTile({
    required this.staff,
    required this.onEdit,
    required this.onAvailability,
    required this.onDeactivate,
  });

  final StaffMemberModel staff;
  final VoidCallback onEdit;
  final VoidCallback onAvailability;
  final VoidCallback onDeactivate;

  @override
  Widget build(BuildContext context) {
    final hasPhoto = (staff.photoUrl ?? '').isNotEmpty;
    return Container(
      margin: const EdgeInsets.only(bottom: Spacing.md),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(Radii.lg),
        boxShadow: AppColors.shadowCard,
      ),
      child: Padding(
        padding: const EdgeInsets.all(Spacing.lg),
        child: Column(
          children: [
            Row(
              children: [
                CircleAvatar(
                  radius: 24,
                  backgroundColor: AppColors.primary.withValues(alpha: 0.1),
                  backgroundImage:
                      hasPhoto ? NetworkImage(staff.photoUrl!) : null,
                  child: hasPhoto
                      ? null
                      : const Icon(Icons.person, color: AppColors.primary),
                ),
                const SizedBox(width: Spacing.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        staff.name,
                        style: const TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 15,
                          color: AppColors.textPrimary,
                        ),
                      ),
                      if (staff.specialties.isNotEmpty) ...[
                        const SizedBox(height: 4),
                        Text(
                          staff.specialties.join(' · '),
                          style: const TextStyle(
                            fontSize: 13,
                            color: AppColors.textSecondary,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.edit_outlined),
                  tooltip: 'Editar',
                  onPressed: onEdit,
                ),
                IconButton(
                  icon: const Icon(Icons.delete_outline,
                      color: AppColors.error),
                  tooltip: 'Desactivar',
                  onPressed: onDeactivate,
                ),
              ],
            ),
            const SizedBox(height: Spacing.sm),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: onAvailability,
                icon: const Icon(Icons.calendar_view_week, size: 18),
                label: const Text('Disponibilidade semanal'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _StaffForm extends StatefulWidget {
  const _StaffForm({this.existing});
  final StaffMemberModel? existing;

  @override
  State<_StaffForm> createState() => _StaffFormState();
}

class _StaffFormState extends State<_StaffForm> {
  late final TextEditingController _name;
  late final TextEditingController _bio;
  late final TextEditingController _photo;
  late final TextEditingController _specialties;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    _name = TextEditingController(text: e?.name ?? '');
    _bio = TextEditingController(text: e?.bio ?? '');
    _photo = TextEditingController(text: e?.photoUrl ?? '');
    _specialties =
        TextEditingController(text: (e?.specialties ?? const []).join(', '));
  }

  @override
  void dispose() {
    _name.dispose();
    _bio.dispose();
    _photo.dispose();
    _specialties.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_saving) return;
    final messenger = ScaffoldMessenger.of(context);
    final category = context.read<PartnerAppointmentsStore>().provider?.category;
    final name = _name.text.trim();
    if (name.isEmpty) {
      messenger.showSnackBar(
        SnackBar(
          content: Text(
              'Indica o nome do ${StaffTerminology.singular(category).toLowerCase()}.'),
        ),
      );
      return;
    }
    final specialties = _specialties.text
        .split(',')
        .map((s) => s.trim())
        .where((s) => s.isNotEmpty)
        .toList();
    setState(() => _saving = true);
    try {
      final store = context.read<PartnerAppointmentsStore>();
      if (widget.existing == null) {
        await store.createStaff(
          name: name,
          bio: _bio.text.trim(),
          photoUrl: _photo.text.trim(),
          specialties: specialties,
        );
      } else {
        await store.updateStaff(
          staffId: widget.existing!.id,
          name: name,
          bio: _bio.text.trim(),
          photoUrl: _photo.text.trim(),
          specialties: specialties,
        );
      }
      if (!mounted) return;
      Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;
      messenger.showSnackBar(SnackBar(
        content: Text(e.toString().replaceFirst('Exception: ', '')),
        backgroundColor: AppColors.error,
      ));
      setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isEdit = widget.existing != null;
    final category =
        context.watch<PartnerAppointmentsStore>().provider?.category;
    final term = StaffTerminology.singular(category);
    return Padding(
      padding: EdgeInsets.only(
        left: Spacing.lg,
        right: Spacing.lg,
        top: Spacing.lg,
        bottom: MediaQuery.of(context).viewInsets.bottom + Spacing.lg,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            isEdit ? 'Editar ${term.toLowerCase()}' : 'Novo ${term.toLowerCase()}',
            style: const TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w800,
              color: AppColors.textPrimary,
            ),
          ),
          const SizedBox(height: Spacing.lg),
          TextField(
            controller: _name,
            textCapitalization: TextCapitalization.words,
            decoration: InputDecoration(
              labelText: 'Nome do ${term.toLowerCase()}',
              border: const OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: Spacing.md),
          TextField(
            controller: _specialties,
            decoration: const InputDecoration(
              labelText: 'Especialidades (separadas por vírgula)',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: Spacing.md),
          TextField(
            controller: _bio,
            maxLines: 2,
            decoration: const InputDecoration(
              labelText: 'Bio (opcional)',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: Spacing.md),
          TextField(
            controller: _photo,
            keyboardType: TextInputType.url,
            decoration: const InputDecoration(
              labelText: 'URL da foto (opcional)',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: Spacing.xl),
          BoraPrimaryButton(
            label: isEdit ? 'Guardar' : 'Criar',
            loading: _saving,
            onPressed: _save,
          ),
        ],
      ),
    );
  }
}

/// Editor de disponibilidade semanal de um profissional (staff_availability).
/// day_of_week: 0=Dom..6=Sáb.
class _StaffAvailabilityScreen extends StatefulWidget {
  const _StaffAvailabilityScreen({required this.staff});
  final StaffMemberModel staff;

  @override
  State<_StaffAvailabilityScreen> createState() =>
      _StaffAvailabilityScreenState();
}

class _StaffAvailabilityScreenState extends State<_StaffAvailabilityScreen> {
  static const _dayNames = [
    'Domingo',
    'Segunda',
    'Terça',
    'Quarta',
    'Quinta',
    'Sexta',
    'Sábado',
  ];

  late Future<void> _future;
  // dayOfWeek -> (isWorking, start, end)
  final Map<int, _DayConfig> _config = {};
  final Set<int> _savingDays = <int>{};

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<void> _load() async {
    final rows = await context
        .read<PartnerAppointmentsStore>()
        .fetchStaffAvailability(widget.staff.id);
    _config.clear();
    for (var d = 0; d < 7; d++) {
      _config[d] = const _DayConfig(isWorking: false);
    }
    for (final row in rows) {
      final dow = (row['day_of_week'] as int?) ?? 0;
      _config[dow] = _DayConfig(
        isWorking: (row['is_working'] as bool?) ?? false,
        start: _hhmm(row['start_time']),
        end: _hhmm(row['end_time']),
      );
    }
  }

  TimeOfDay? _hhmm(Object? v) {
    if (v is! String || v.isEmpty) return null;
    final parts = v.split(':');
    if (parts.length < 2) return null;
    final h = int.tryParse(parts[0]);
    final m = int.tryParse(parts[1]);
    if (h == null || m == null) return null;
    return TimeOfDay(hour: h, minute: m);
  }

  String _fmt(TimeOfDay? t, TimeOfDay fallback) {
    final v = t ?? fallback;
    return '${v.hour.toString().padLeft(2, '0')}:${v.minute.toString().padLeft(2, '0')}';
  }

  Future<void> _saveDay(int dow) async {
    if (_savingDays.contains(dow)) return;
    setState(() => _savingDays.add(dow));
    final messenger = ScaffoldMessenger.of(context);
    final cfg = _config[dow]!;
    try {
      await context.read<PartnerAppointmentsStore>().upsertAvailability(
            staffId: widget.staff.id,
            dayOfWeek: dow,
            isWorking: cfg.isWorking,
            startTime: _fmt(cfg.start, const TimeOfDay(hour: 9, minute: 0)),
            endTime: _fmt(cfg.end, const TimeOfDay(hour: 18, minute: 0)),
          );
      if (!mounted) return;
      messenger.showSnackBar(const SnackBar(
        content: Text('Disponibilidade guardada.'),
        backgroundColor: AppColors.success,
      ));
    } catch (e) {
      if (!mounted) return;
      messenger.showSnackBar(SnackBar(
        content: Text(e.toString().replaceFirst('Exception: ', '')),
        backgroundColor: AppColors.error,
      ));
    } finally {
      if (mounted) setState(() => _savingDays.remove(dow));
    }
  }

  Future<void> _pickTime(int dow, {required bool isStart}) async {
    final cfg = _config[dow]!;
    final initial = isStart
        ? (cfg.start ?? const TimeOfDay(hour: 9, minute: 0))
        : (cfg.end ?? const TimeOfDay(hour: 18, minute: 0));
    final picked = await showTimePicker(context: context, initialTime: initial);
    if (picked == null) return;
    setState(() {
      _config[dow] = cfg.copyWith(
        start: isStart ? picked : cfg.start,
        end: isStart ? cfg.end : picked,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: BoraScreenAppBar(title: widget.staff.name),
      body: FutureBuilder<void>(
        future: _future,
        builder: (context, snap) {
          if (snap.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snap.hasError) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(
                  snap.error.toString().replaceFirst('Exception: ', ''),
                  textAlign: TextAlign.center,
                ),
              ),
            );
          }
          return ListView(
            padding: const EdgeInsets.all(Spacing.lg),
            children: [
              for (var dow = 0; dow < 7; dow++) _dayCard(dow),
            ],
          );
        },
      ),
    );
  }

  Widget _dayCard(int dow) {
    final cfg = _config[dow]!;
    final saving = _savingDays.contains(dow);
    return Container(
      margin: const EdgeInsets.only(bottom: Spacing.md),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(Radii.lg),
        boxShadow: AppColors.shadowCard,
      ),
      child: Padding(
        padding: const EdgeInsets.all(Spacing.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    _dayNames[dow],
                    style: const TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 15,
                      color: AppColors.textPrimary,
                    ),
                  ),
                ),
                Switch(
                  value: cfg.isWorking,
                  activeThumbColor: AppColors.primary,
                  onChanged: (v) => setState(
                    () => _config[dow] = cfg.copyWith(isWorking: v),
                  ),
                ),
              ],
            ),
            if (cfg.isWorking) ...[
              const SizedBox(height: Spacing.sm),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () => _pickTime(dow, isStart: true),
                      icon: const Icon(Icons.schedule, size: 18),
                      label: Text(
                        'Início ${_fmt(cfg.start, const TimeOfDay(hour: 9, minute: 0))}',
                      ),
                    ),
                  ),
                  const SizedBox(width: Spacing.sm),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () => _pickTime(dow, isStart: false),
                      icon: const Icon(Icons.schedule, size: 18),
                      label: Text(
                        'Fim ${_fmt(cfg.end, const TimeOfDay(hour: 18, minute: 0))}',
                      ),
                    ),
                  ),
                ],
              ),
            ],
            const SizedBox(height: Spacing.sm),
            Align(
              alignment: Alignment.centerRight,
              child: saving
                  ? const Padding(
                      padding: EdgeInsets.all(8),
                      child: SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    )
                  : TextButton.icon(
                      onPressed: () => _saveDay(dow),
                      icon: const Icon(Icons.save_outlined, size: 18),
                      label: const Text('Guardar dia'),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DayConfig {
  const _DayConfig({required this.isWorking, this.start, this.end});
  final bool isWorking;
  final TimeOfDay? start;
  final TimeOfDay? end;

  _DayConfig copyWith({bool? isWorking, TimeOfDay? start, TimeOfDay? end}) =>
      _DayConfig(
        isWorking: isWorking ?? this.isWorking,
        start: start ?? this.start,
        end: end ?? this.end,
      );
}
