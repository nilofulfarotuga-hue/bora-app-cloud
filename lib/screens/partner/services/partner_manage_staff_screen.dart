import 'dart:convert';
import '../../../utils/io_compat.dart';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:table_calendar/table_calendar.dart';

import '../../../config/app_colors.dart';
import '../../../config/app_spacing.dart';
import '../../../models/staff_member_model.dart';
import '../../../stores/partner_appointments_store.dart';
import '../../../utils/safe_image_picker.dart';
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
  late final TextEditingController _specialties;
  String? _photoUrl;
  XFile? _localPhoto;
  bool _uploadingPhoto = false;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    _name = TextEditingController(text: e?.name ?? '');
    _bio = TextEditingController(text: e?.bio ?? '');
    _photoUrl = e?.photoUrl;
    _specialties =
        TextEditingController(text: (e?.specialties ?? const []).join(', '));
  }

  @override
  void dispose() {
    _name.dispose();
    _bio.dispose();
    _specialties.dispose();
    super.dispose();
  }

  Future<ImageSource?> _chooseImageSource() {
    return showModalBottomSheet<ImageSource>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.photo_camera),
              title: const Text('Tirar foto'),
              onTap: () => Navigator.of(ctx).pop(ImageSource.camera),
            ),
            ListTile(
              leading: const Icon(Icons.photo_library),
              title: const Text('Escolher da galeria'),
              onTap: () => Navigator.of(ctx).pop(ImageSource.gallery),
            ),
          ],
        ),
      ),
    );
  }

  /// Reaproveita o Edge Function `upload-restaurant-asset` (mesmo caminho do
  /// logo/capa do parceiro em register_partner_screen — service_role bypassa
  /// RLS de storage). `kind: 'staff_photo'` vai para o bucket público
  /// `restaurant-assets` (só owner_doc/activity_doc vão para bucket privado).
  Future<void> _pickAndUploadPhoto() async {
    if (_uploadingPhoto) return;
    final providerId = context.read<PartnerAppointmentsStore>().providerId;
    if (providerId == null) return;
    final messenger = ScaffoldMessenger.of(context);
    final source = await _chooseImageSource();
    if (source == null || !mounted) return;
    XFile? picked;
    try {
      picked = await SafeImagePicker.pickImage(
        source: source,
        maxWidth: 1200,
        imageQuality: 85,
      );
    } catch (e) {
      if (!mounted) return;
      messenger.showSnackBar(
        SnackBar(content: Text('Erro ao seleccionar imagem: $e')),
      );
      return;
    }
    if (picked == null || !mounted) return;

    setState(() {
      _localPhoto = picked;
      _uploadingPhoto = true;
    });

    try {
      final bytes = await picked.readAsBytes();
      final ext = picked.path.contains('.')
          ? picked.path.split('.').last.toLowerCase()
          : 'jpg';
      final contentType = 'image/${ext == 'jpg' ? 'jpeg' : ext}';
      final response = await Supabase.instance.client.functions.invoke(
        'upload-restaurant-asset',
        body: {
          'restaurantId': providerId,
          'kind': 'staff_photo',
          'fileBase64': base64Encode(bytes),
          'contentType': contentType,
        },
      );
      if (response.status != 200 || response.data is! Map) {
        throw Exception('upload falhou (HTTP ${response.status})');
      }
      final data = Map<String, dynamic>.from(response.data as Map);
      if (data['success'] != true || data['public_url'] == null) {
        throw Exception(data['error']?.toString() ?? 'upload falhou');
      }
      if (!mounted) return;
      setState(() {
        _photoUrl = data['public_url'] as String;
        _uploadingPhoto = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _uploadingPhoto = false;
        _localPhoto = null;
      });
      messenger.showSnackBar(SnackBar(
        content: Text('Erro ao enviar foto: $e'),
        backgroundColor: AppColors.error,
      ));
    }
  }

  Future<void> _save() async {
    if (_saving || _uploadingPhoto) return;
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
          photoUrl: _photoUrl,
          specialties: specialties,
        );
      } else {
        await store.updateStaff(
          staffId: widget.existing!.id,
          name: name,
          bio: _bio.text.trim(),
          photoUrl: _photoUrl,
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
    final hasLocalPhoto = _localPhoto != null;
    final hasNetworkPhoto = (_photoUrl ?? '').isNotEmpty;
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
          Center(
            child: GestureDetector(
              onTap: _uploadingPhoto ? null : _pickAndUploadPhoto,
              child: Stack(
                children: [
                  CircleAvatar(
                    radius: 44,
                    backgroundColor: AppColors.primary.withValues(alpha: 0.1),
                    backgroundImage: hasLocalPhoto
                        ? boraLocalImage(_localPhoto!.path)
                        : (hasNetworkPhoto
                            ? NetworkImage(_photoUrl!) as ImageProvider
                            : null),
                    child: _uploadingPhoto
                        ? const CircularProgressIndicator()
                        : (!hasLocalPhoto && !hasNetworkPhoto
                            ? const Icon(Icons.person,
                                size: 40, color: AppColors.primary)
                            : null),
                  ),
                  Positioned(
                    right: 0,
                    bottom: 0,
                    child: Container(
                      padding: const EdgeInsets.all(6),
                      decoration: const BoxDecoration(
                        color: AppColors.accent,
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.camera_alt,
                          size: 16, color: Colors.white),
                    ),
                  ),
                ],
              ),
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

class _StaffAvailabilityScreenState extends State<_StaffAvailabilityScreen>
    with SingleTickerProviderStateMixin {
  static const _dayNames = [
    'Domingo',
    'Segunda',
    'Terça',
    'Quarta',
    'Quinta',
    'Sexta',
    'Sábado',
  ];

  late final TabController _tab;
  late Future<void> _future;
  // dayOfWeek -> (isWorking, start, end)
  final Map<int, _DayConfig> _config = {};
  final Set<int> _savingDays = <int>{};

  @override
  void initState() {
    super.initState();
    _tab = TabController(length: 2, vsync: this);
    _future = _load();
  }

  @override
  void dispose() {
    _tab.dispose();
    super.dispose();
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
      body: Column(
        children: [
          Material(
            color: AppColors.card,
            child: TabBar(
              controller: _tab,
              labelColor: AppColors.primary,
              unselectedLabelColor: AppColors.textSecondary,
              indicatorColor: AppColors.primary,
              tabs: const [
                Tab(text: 'Padrão semanal'),
                Tab(text: 'Calendário do mês'),
              ],
            ),
          ),
          Expanded(
            child: TabBarView(
              controller: _tab,
              children: [
                _buildWeeklyTab(),
                _StaffMonthCalendar(staff: widget.staff),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// Editor do padrão semanal (inalterado — apenas movido para uma aba).
  Widget _buildWeeklyTab() {
    return FutureBuilder<void>(
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

/// Tipo de marcador de um dia no calendário mensal.
enum _DayMark { none, pattern, dayOff, custom }

/// Aba "Calendário do mês" — o profissional marca EXCEÇÕES ao padrão semanal em
/// datas específicas (folgas, feriados, horário diferente), guardadas em
/// `staff_availability_exceptions`. O padrão semanal continua a ser o modelo
/// base: dias sem exceção seguem-no (ponto verde discreto nos dias de trabalho
/// do padrão). `get_available_slots` dá prioridade à exceção quando existe.
class _StaffMonthCalendar extends StatefulWidget {
  const _StaffMonthCalendar({required this.staff});

  final StaffMemberModel staff;

  @override
  State<_StaffMonthCalendar> createState() => _StaffMonthCalendarState();
}

class _StaffMonthCalendarState extends State<_StaffMonthCalendar> {
  static const _monthsPt = [
    'Janeiro', 'Fevereiro', 'Março', 'Abril', 'Maio', 'Junho',
    'Julho', 'Agosto', 'Setembro', 'Outubro', 'Novembro', 'Dezembro',
  ];
  // Indexado por DateTime.weekday - 1 (Seg=1 → 0 … Dom=7 → 6).
  static const _dowShortPt = ['Seg', 'Ter', 'Qua', 'Qui', 'Sex', 'Sáb', 'Dom'];

  late DateTime _focused;
  DateTime? _selected;
  bool _loading = true;
  String? _error;

  // 'YYYY-MM-DD' -> linha de exceção (is_working, start_time, end_time).
  final Map<String, Map<String, dynamic>> _exceptions = {};
  // tableDow (0=Dom … 6=Sáb) -> is_working no padrão semanal.
  final Map<int, bool> _weekly = {};

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _focused = DateTime(now.year, now.month, now.day);
    _load();
  }

  String _ymd(DateTime d) => '${d.year.toString().padLeft(4, '0')}-'
      '${d.month.toString().padLeft(2, '0')}-'
      '${d.day.toString().padLeft(2, '0')}';

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    final store = context.read<PartnerAppointmentsStore>();
    try {
      final results = await Future.wait([
        store.fetchAvailabilityExceptions(
            staffId: widget.staff.id, month: _focused),
        store.fetchStaffAvailability(widget.staff.id),
      ]);
      final exceptions = results[0];
      final weekly = results[1];
      _exceptions.clear();
      for (final e in exceptions) {
        final dateStr = (e['date'] as String?)?.split('T').first;
        if (dateStr != null) _exceptions[dateStr] = e;
      }
      _weekly.clear();
      for (final w in weekly) {
        final dow = w['day_of_week'] as int?;
        if (dow != null) _weekly[dow] = (w['is_working'] as bool?) ?? false;
      }
      if (!mounted) return;
      setState(() => _loading = false);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = e.toString().replaceFirst('Exception: ', '');
      });
    }
  }

  _DayMark _markFor(DateTime day) {
    final ex = _exceptions[_ymd(day)];
    if (ex != null) {
      final working = (ex['is_working'] as bool?) ?? false;
      return working ? _DayMark.custom : _DayMark.dayOff;
    }
    final tableDow = day.weekday % 7; // Dom(7)→0, Seg(1)→1 … Sáb(6)→6.
    if (_weekly[tableDow] == true) return _DayMark.pattern;
    return _DayMark.none;
  }

  TimeOfDay? _timeOf(Object? v) {
    if (v is! String || v.isEmpty) return null;
    final parts = v.split(':');
    if (parts.length < 2) return null;
    final h = int.tryParse(parts[0]);
    final m = int.tryParse(parts[1]);
    if (h == null || m == null) return null;
    return TimeOfDay(hour: h, minute: m);
  }

  String _fmt(TimeOfDay t) =>
      '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

  void _snack(String msg, {bool error = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg),
      backgroundColor: error ? AppColors.error : AppColors.success,
    ));
  }

  Future<void> _save(Future<void> Function() op, String successMsg) async {
    try {
      await op();
      if (!mounted) return;
      _snack(successMsg);
      await _load();
    } catch (e) {
      _snack(e.toString().replaceFirst('Exception: ', ''), error: true);
    }
  }

  Future<TimeOfDay?> _pickTime(TimeOfDay initial, String help) {
    return showTimePicker(
      context: context,
      initialTime: initial,
      helpText: help,
      builder: (ctx, child) => MediaQuery(
        data: MediaQuery.of(ctx).copyWith(alwaysUse24HourFormat: true),
        child: child ?? const SizedBox.shrink(),
      ),
    );
  }

  Future<void> _openDaySheet(DateTime day) async {
    final ex = _exceptions[_ymd(day)];
    final action = await showModalBottomSheet<String>(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(
                  Spacing.lg, Spacing.lg, Spacing.lg, Spacing.xs),
              child: Text(
                '${day.day} de ${_monthsPt[day.month - 1]}',
                style: const TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w800,
                  color: AppColors.textPrimary,
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(Spacing.lg, 0, Spacing.lg, Spacing.sm),
              child: Text(_statusLabel(day, ex),
                  style: const TextStyle(
                      fontSize: 13, color: AppColors.textSecondary)),
            ),
            const Divider(height: 1),
            ListTile(
              leading: const Icon(Icons.event_available, color: AppColors.primary),
              title: const Text('Seguir o padrão semanal'),
              subtitle: const Text('Remove qualquer exceção deste dia'),
              onTap: () => Navigator.pop(ctx, 'pattern'),
            ),
            ListTile(
              leading: const Icon(Icons.block, color: AppColors.error),
              title: const Text('Marcar como folga / indisponível'),
              subtitle: const Text('Sem horários disponíveis neste dia'),
              onTap: () => Navigator.pop(ctx, 'off'),
            ),
            ListTile(
              leading: const Icon(Icons.schedule, color: AppColors.accent),
              title: const Text('Horário diferente neste dia'),
              subtitle: const Text('Define início e fim só para esta data'),
              onTap: () => Navigator.pop(ctx, 'custom'),
            ),
            const SizedBox(height: Spacing.sm),
          ],
        ),
      ),
    );
    if (action == null || !mounted) return;
    switch (action) {
      case 'pattern':
        await _applyPattern(day);
        break;
      case 'off':
        await _applyDayOff(day);
        break;
      case 'custom':
        await _applyCustom(day, ex);
        break;
    }
  }

  String _statusLabel(DateTime day, Map<String, dynamic>? ex) {
    if (ex != null) {
      final working = (ex['is_working'] as bool?) ?? false;
      if (!working) return 'Estado atual: folga (exceção).';
      final s = _timeOf(ex['start_time']);
      final e = _timeOf(ex['end_time']);
      if (s != null && e != null) {
        return 'Estado atual: horário especial ${_fmt(s)}–${_fmt(e)}.';
      }
      return 'Estado atual: horário especial.';
    }
    return 'Estado atual: segue o padrão semanal.';
  }

  Future<void> _applyPattern(DateTime day) async {
    if (_exceptions[_ymd(day)] == null) {
      _snack('Este dia já segue o padrão semanal.');
      return;
    }
    await _save(
      () => context.read<PartnerAppointmentsStore>().deleteAvailabilityException(
            staffId: widget.staff.id,
            date: day,
          ),
      'Dia voltou ao padrão semanal.',
    );
  }

  Future<void> _applyDayOff(DateTime day) async {
    await _save(
      () => context.read<PartnerAppointmentsStore>().upsertAvailabilityException(
            staffId: widget.staff.id,
            date: day,
            isWorking: false,
          ),
      'Dia marcado como folga.',
    );
  }

  Future<void> _applyCustom(DateTime day, Map<String, dynamic>? ex) async {
    final start = await _pickTime(
      _timeOf(ex?['start_time']) ?? const TimeOfDay(hour: 9, minute: 0),
      'Hora de início',
    );
    if (start == null || !mounted) return;
    final end = await _pickTime(
      _timeOf(ex?['end_time']) ?? const TimeOfDay(hour: 18, minute: 0),
      'Hora de fim',
    );
    if (end == null || !mounted) return;
    if (end.hour * 60 + end.minute <= start.hour * 60 + start.minute) {
      _snack('A hora de fim tem de ser depois da de início.', error: true);
      return;
    }
    await _save(
      () => context.read<PartnerAppointmentsStore>().upsertAvailabilityException(
            staffId: widget.staff.id,
            date: day,
            isWorking: true,
            startTime: _fmt(start),
            endTime: _fmt(end),
          ),
      'Horário especial guardado.',
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(_error!, textAlign: TextAlign.center),
              const SizedBox(height: Spacing.md),
              ElevatedButton(
                onPressed: _load,
                child: const Text('Tentar de novo'),
              ),
            ],
          ),
        ),
      );
    }
    final now = DateTime.now();
    return ListView(
      padding: const EdgeInsets.all(Spacing.lg),
      children: [
        Container(
          decoration: BoxDecoration(
            color: AppColors.card,
            borderRadius: BorderRadius.circular(Radii.lg),
            boxShadow: AppColors.shadowCard,
          ),
          padding: const EdgeInsets.symmetric(
              horizontal: Spacing.sm, vertical: Spacing.md),
          child: TableCalendar<Object>(
            firstDay: DateTime(now.year - 1, 1, 1),
            lastDay: DateTime(now.year + 1, 12, 31),
            focusedDay: _focused,
            currentDay: DateTime(now.year, now.month, now.day),
            startingDayOfWeek: StartingDayOfWeek.monday,
            calendarFormat: CalendarFormat.month,
            availableGestures: AvailableGestures.horizontalSwipe,
            daysOfWeekHeight: 24,
            rowHeight: 52,
            selectedDayPredicate: (day) =>
                _selected != null && isSameDay(_selected, day),
            headerStyle: HeaderStyle(
              titleCentered: true,
              formatButtonVisible: false,
              titleTextFormatter: (date, _) =>
                  '${_monthsPt[date.month - 1]} ${date.year}',
              titleTextStyle: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w800,
                color: AppColors.textPrimary,
              ),
              leftChevronIcon:
                  const Icon(Icons.chevron_left, color: AppColors.textPrimary),
              rightChevronIcon:
                  const Icon(Icons.chevron_right, color: AppColors.textPrimary),
            ),
            onPageChanged: (focused) {
              _focused = focused;
              _load();
            },
            onDaySelected: (selected, focused) {
              setState(() {
                _selected = selected;
                _focused = focused;
              });
              _openDaySheet(selected);
            },
            calendarBuilders: CalendarBuilders<Object>(
              dowBuilder: (context, day) => Center(
                child: Text(
                  _dowShortPt[day.weekday - 1],
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textSubtle,
                  ),
                ),
              ),
              defaultBuilder: (context, day, focused) => _cell(day),
              todayBuilder: (context, day, focused) =>
                  _cell(day, isToday: true),
              selectedBuilder: (context, day, focused) =>
                  _cell(day, isSelected: true),
              outsideBuilder: (context, day, focused) =>
                  _cell(day, isOutside: true),
              disabledBuilder: (context, day, focused) =>
                  _cell(day, isOutside: true),
            ),
          ),
        ),
        const SizedBox(height: Spacing.lg),
        _legend(),
        const SizedBox(height: Spacing.md),
        _hint(),
      ],
    );
  }

  Widget _cell(DateTime day,
      {bool isToday = false, bool isSelected = false, bool isOutside = false}) {
    final mark = isOutside ? _DayMark.none : _markFor(day);
    final dotColor = switch (mark) {
      _DayMark.dayOff => AppColors.error,
      _DayMark.custom => AppColors.accent,
      _DayMark.pattern => AppColors.primary,
      _DayMark.none => Colors.transparent,
    };
    final dot = isSelected
        ? (mark == _DayMark.none ? Colors.transparent : Colors.white)
        : dotColor;
    return Container(
      margin: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: isSelected
            ? AppColors.primary
            : (isToday ? AppColors.primaryLight : null),
      ),
      alignment: Alignment.center,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            '${day.day}',
            style: TextStyle(
              fontSize: 14,
              fontWeight:
                  (isToday || isSelected) ? FontWeight.w800 : FontWeight.w500,
              color: isSelected
                  ? Colors.white
                  : (isOutside ? AppColors.textSubtle : AppColors.textPrimary),
            ),
          ),
          const SizedBox(height: 2),
          Container(
            width: 6,
            height: 6,
            decoration: BoxDecoration(shape: BoxShape.circle, color: dot),
          ),
        ],
      ),
    );
  }

  Widget _legend() {
    return Container(
      padding: const EdgeInsets.all(Spacing.md),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(Radii.lg),
        boxShadow: AppColors.shadowCard,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Legenda',
              style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textPrimary)),
          const SizedBox(height: Spacing.sm),
          _legendRow(AppColors.primary, 'Trabalha (segue o padrão semanal)'),
          _legendRow(AppColors.accent, 'Horário diferente neste dia'),
          _legendRow(AppColors.error, 'Folga / indisponível'),
        ],
      ),
    );
  }

  Widget _legendRow(Color color, String label) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        children: [
          Container(
            width: 10,
            height: 10,
            decoration: BoxDecoration(shape: BoxShape.circle, color: color),
          ),
          const SizedBox(width: Spacing.sm),
          Expanded(
            child: Text(label,
                style: const TextStyle(
                    fontSize: 13, color: AppColors.textSecondary)),
          ),
        ],
      ),
    );
  }

  Widget _hint() {
    return Container(
      padding: const EdgeInsets.all(Spacing.md),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(Radii.md),
      ),
      child: const Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.info_outline, size: 18, color: AppColors.info),
          SizedBox(width: Spacing.sm),
          Expanded(
            child: Text(
              'Toca num dia para marcar folga, um horário diferente, ou voltar '
              'ao padrão semanal. O padrão semanal continua a valer nos dias '
              'sem exceção.',
              style: TextStyle(
                fontSize: 13,
                height: 1.4,
                color: AppColors.textSecondary,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
