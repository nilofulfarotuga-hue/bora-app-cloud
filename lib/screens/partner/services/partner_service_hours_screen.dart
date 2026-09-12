import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../config/app_colors.dart';
import '../../../config/app_spacing.dart';
import '../../../models/staff_member_model.dart';
import '../../../models/weekly_hours.dart';
import '../../../stores/partner_appointments_store.dart';
import '../../../widgets/bora/bora_primary_button.dart';
import '../../../widgets/bora/bora_screen_app_bar.dart';
import '../../../widgets/services/weekly_hours_editor.dart';

/// BLOCO C (2026-07-28) — "Horário de atendimento" (PT-PT).
///
/// O parceiro edita sozinho abertura, fecho, pausa e dias fechados.
///
/// IMPORTANTE: grava em `staff_availability` (a tabela que a RPC
/// `get_available_slots` lê para gerar os horários do cliente) e, em espelho,
/// no `service_providers.business_hours` (a vitrine da ficha). Editar só a
/// vitrine não muda um único slot — foi por isso que este ecrã existe.
class PartnerServiceHoursScreen extends StatefulWidget {
  const PartnerServiceHoursScreen({super.key});

  @override
  State<PartnerServiceHoursScreen> createState() =>
      _PartnerServiceHoursScreenState();
}

class _PartnerServiceHoursScreenState extends State<PartnerServiceHoursScreen> {
  late Future<void> _loadFuture;
  List<StaffMemberModel> _staff = const [];
  String? _selectedStaffId;
  Map<int, DayHours> _week = defaultWeek();

  /// Aplicar a toda a equipa. Default true quando há 1 profissional só (é o
  /// caso normal das barbearias pequenas) — evita horários dessincronizados.
  bool _applyToAll = true;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _loadFuture = _load();
  }

  Future<void> _load() async {
    final store = context.read<PartnerAppointmentsStore>();
    await store.loadMyProvider();
    final staff = await store.fetchStaff();
    if (staff.isEmpty) {
      if (mounted) setState(() => _staff = const []);
      return;
    }
    final selected = _selectedStaffId ?? staff.first.id;
    final week = await store.fetchWeeklyHours(selected);
    if (!mounted) return;
    setState(() {
      _staff = staff;
      _selectedStaffId = selected;
      _week = week;
      _applyToAll = staff.length == 1 || _applyToAll;
    });
  }

  Future<void> _switchStaff(String staffId) async {
    final store = context.read<PartnerAppointmentsStore>();
    setState(() => _selectedStaffId = staffId);
    try {
      final week = await store.fetchWeeklyHours(staffId);
      if (mounted) setState(() => _week = week);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(e.toString().replaceFirst('Exception: ', '')),
        backgroundColor: AppColors.error,
      ));
    }
  }

  Future<void> _save() async {
    if (_saving || _selectedStaffId == null) return;
    // Validação antes de gravar — o mesmo `validate()` do editor.
    for (final entry in _week.entries) {
      final err = entry.value.validate();
      if (err != null) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('${kWeekdayNamesPt[entry.key]}: $err'),
          backgroundColor: AppColors.error,
        ));
        return;
      }
    }
    setState(() => _saving = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      await context.read<PartnerAppointmentsStore>().saveWeeklyHours(
            staffIds: _applyToAll
                ? _staff.map((s) => s.id).toList()
                : [_selectedStaffId!],
            week: _week,
          );
      if (!mounted) return;
      messenger.showSnackBar(const SnackBar(
        content: Text('Horário guardado. Já vale para as próximas marcações.'),
        backgroundColor: AppColors.success,
      ));
    } catch (e) {
      if (!mounted) return;
      messenger.showSnackBar(SnackBar(
        content: Text(e.toString().replaceFirst('Exception: ', '')),
        backgroundColor: AppColors.error,
      ));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: const BoraScreenAppBar(title: 'Horário de atendimento'),
      body: FutureBuilder<void>(
        future: _loadFuture,
        builder: (context, snap) {
          if (snap.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snap.hasError) {
            return _ErrorState(
              message: snap.error.toString().replaceFirst('Exception: ', ''),
              onRetry: () => setState(() => _loadFuture = _load()),
            );
          }
          if (_staff.isEmpty) {
            return const _EmptyState();
          }
          return Column(
            children: [
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.all(Spacing.lg),
                  children: [
                    const _InfoBanner(),
                    if (_staff.length > 1) ...[
                      const SizedBox(height: Spacing.md),
                      _StaffSelector(
                        staff: _staff,
                        selectedId: _selectedStaffId!,
                        onSelected: _switchStaff,
                      ),
                      const SizedBox(height: Spacing.sm),
                      SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        value: _applyToAll,
                        onChanged: (v) => setState(() => _applyToAll = v),
                        title: const Text('Aplicar a toda a equipa'),
                        subtitle: const Text(
                          'Grava este horário para todos os profissionais.',
                        ),
                      ),
                    ],
                    const SizedBox(height: Spacing.md),
                    WeeklyHoursEditor(
                      week: _week,
                      enabled: !_saving,
                      onChanged: (w) => setState(() => _week = w),
                    ),
                  ],
                ),
              ),
              SafeArea(
                top: false,
                minimum: const EdgeInsets.fromLTRB(
                    Spacing.lg, Spacing.sm, Spacing.lg, Spacing.lg),
                child: BoraPrimaryButton(
                  label: 'Guardar horário',
                  loading: _saving,
                  onPressed: _saving ? null : _save,
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _InfoBanner extends StatelessWidget {
  const _InfoBanner();

  @override
  Widget build(BuildContext context) {
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
              'É este horário que o cliente vê ao marcar. Nenhuma marcação '
              'pode começar nem acabar dentro da pausa.',
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

class _StaffSelector extends StatelessWidget {
  const _StaffSelector({
    required this.staff,
    required this.selectedId,
    required this.onSelected,
  });

  final List<StaffMemberModel> staff;
  final String selectedId;
  final ValueChanged<String> onSelected;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: Spacing.sm,
      runSpacing: Spacing.xs,
      children: [
        for (final s in staff)
          ChoiceChip(
            label: Text(s.name),
            selected: s.id == selectedId,
            onSelected: (_) => onSelected(s.id),
          ),
      ],
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Padding(
        padding: EdgeInsets.all(Spacing.xxxl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.people_outline, size: 48, color: AppColors.textSubtle),
            SizedBox(height: Spacing.md),
            Text(
              'Adiciona primeiro um profissional à tua equipa.\n'
              'O horário é definido por profissional.',
              textAlign: TextAlign.center,
              style: TextStyle(color: AppColors.textSecondary),
            ),
          ],
        ),
      ),
    );
  }
}

class _ErrorState extends StatelessWidget {
  const _ErrorState({required this.message, required this.onRetry});
  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(Spacing.xxxl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline, size: 48, color: AppColors.error),
            const SizedBox(height: Spacing.md),
            Text(message, textAlign: TextAlign.center),
            const SizedBox(height: Spacing.lg),
            ElevatedButton(
              onPressed: onRetry,
              child: const Text('Tentar de novo'),
            ),
          ],
        ),
      ),
    );
  }
}
