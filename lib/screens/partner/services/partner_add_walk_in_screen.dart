import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../config/app_colors.dart';
import '../../../config/app_spacing.dart';
import '../../../models/provider_service_model.dart';
import '../../../models/staff_member_model.dart';
import '../../../stores/partner_appointments_store.dart';
import '../../../utils/staff_terminology.dart';
import '../../../widgets/bora/bora_accent_button.dart';
import '../../../widgets/bora/bora_screen_app_bar.dart';

/// Adicionar marcação sem reserva prévia (host stand). Form: nome cliente,
/// serviço, profissional, data/hora (slot livre). Submit → partner_add_walk_in.
class PartnerAddWalkInScreen extends StatefulWidget {
  const PartnerAddWalkInScreen({super.key});

  @override
  State<PartnerAddWalkInScreen> createState() => _PartnerAddWalkInScreenState();
}

class _PartnerAddWalkInScreenState extends State<PartnerAddWalkInScreen> {
  final _nameCtrl = TextEditingController();

  List<ProviderServiceModel> _services = const [];
  List<StaffMemberModel> _staff = const [];
  ProviderServiceModel? _service;
  StaffMemberModel? _staffMember;

  DateTime _day = DateTime.now();
  List<DateTime> _slots = const [];
  DateTime? _slot;
  bool _loadingSlots = false;

  bool _loading = true;
  String? _loadError;
  bool _submitting = false;

  @override
  void initState() {
    super.initState();
    _loadLists();
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadLists() async {
    setState(() {
      _loading = true;
      _loadError = null;
    });
    try {
      final store = context.read<PartnerAppointmentsStore>();
      final services = await store.fetchServices();
      final staff = await store.fetchStaff();
      if (!mounted) return;
      setState(() {
        _services = services;
        _staff = staff;
        _service = services.isNotEmpty ? services.first : null;
        _staffMember = staff.isNotEmpty ? staff.first : null;
        _loading = false;
      });
      _reloadSlots();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loadError = e.toString().replaceFirst('Exception: ', '');
        _loading = false;
      });
    }
  }

  Future<void> _reloadSlots() async {
    final service = _service;
    final staff = _staffMember;
    if (service == null || staff == null) {
      setState(() {
        _slots = const [];
        _slot = null;
      });
      return;
    }
    setState(() {
      _loadingSlots = true;
      _slot = null;
    });
    try {
      final slots = await context.read<PartnerAppointmentsStore>().availableSlots(
            staffId: staff.id,
            serviceId: service.id,
            day: _day,
          );
      if (!mounted) return;
      setState(() {
        _slots = slots;
        _loadingSlots = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _slots = const [];
        _loadingSlots = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(e.toString().replaceFirst('Exception: ', '')),
        backgroundColor: AppColors.error,
      ));
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
    if (picked == null) return;
    setState(() => _day = picked);
    _reloadSlots();
  }

  Future<void> _submit() async {
    if (_submitting) return;
    final service = _service;
    final staff = _staffMember;
    final messenger = ScaffoldMessenger.of(context);
    if (service == null || staff == null) {
      final term = StaffTerminology.singular(
              context.read<PartnerAppointmentsStore>().provider?.category)
          .toLowerCase();
      messenger.showSnackBar(
        SnackBar(content: Text('Escolhe serviço e $term.')),
      );
      return;
    }
    if (_slot == null) {
      messenger.showSnackBar(
        const SnackBar(content: Text('Escolhe um horário.')),
      );
      return;
    }
    final name = _nameCtrl.text.trim();
    if (name.isEmpty) {
      messenger.showSnackBar(
        const SnackBar(content: Text('Indica o nome do cliente.')),
      );
      return;
    }
    setState(() => _submitting = true);
    try {
      await context.read<PartnerAppointmentsStore>().addWalkIn(
            serviceId: service.id,
            staffId: staff.id,
            scheduledAt: _slot!,
            clientName: name,
          );
      if (!mounted) return;
      messenger.showSnackBar(const SnackBar(
        content: Text('Marcação criada.'),
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
    final category =
        context.watch<PartnerAppointmentsStore>().provider?.category;
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: const BoraScreenAppBar(title: 'Adicionar marcação'),
      body: SafeArea(
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : _loadError != null
                ? _errorState()
                : (_services.isEmpty || _staff.isEmpty)
                    ? _missingSetupState(category)
                    : _form(category),
      ),
    );
  }

  Widget _form(String? category) {
    return Column(
      children: [
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(Spacing.lg),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _Section(
                  title: 'Cliente',
                  child: TextField(
                    controller: _nameCtrl,
                    textCapitalization: TextCapitalization.words,
                    decoration: const InputDecoration(
                      labelText: 'Nome',
                      border: OutlineInputBorder(),
                    ),
                  ),
                ),
                const SizedBox(height: Spacing.md),
                _Section(
                  title: 'Serviço',
                  child: DropdownButtonFormField<ProviderServiceModel>(
                    initialValue: _service,
                    isExpanded: true,
                    decoration: const InputDecoration(
                      border: OutlineInputBorder(),
                    ),
                    items: _services
                        .map((s) => DropdownMenuItem(
                              value: s,
                              child: Text(
                                '${s.name} · ${s.durationLabel} · ${s.priceLabel}',
                                overflow: TextOverflow.ellipsis,
                              ),
                            ))
                        .toList(),
                    onChanged: (v) {
                      setState(() => _service = v);
                      _reloadSlots();
                    },
                  ),
                ),
                const SizedBox(height: Spacing.md),
                _Section(
                  title: StaffTerminology.singular(category),
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
                    onChanged: (v) {
                      setState(() => _staffMember = v);
                      _reloadSlots();
                    },
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
                  title: 'Horário',
                  child: _loadingSlots
                      ? const Padding(
                          padding: EdgeInsets.symmetric(vertical: 12),
                          child: Center(child: CircularProgressIndicator()),
                        )
                      : _slots.isEmpty
                          ? const Padding(
                              padding: EdgeInsets.symmetric(vertical: 8),
                              child: Text(
                                'Sem horários livres neste dia.',
                                style: TextStyle(
                                    color: AppColors.textSecondary),
                              ),
                            )
                          : Wrap(
                              spacing: Spacing.sm,
                              runSpacing: Spacing.sm,
                              children: [
                                for (final s in _slots)
                                  ChoiceChip(
                                    label: Text('${_two(s.hour)}:${_two(s.minute)}'),
                                    selected: _slot == s,
                                    selectedColor: AppColors.primary,
                                    labelStyle: TextStyle(
                                      color: _slot == s
                                          ? Colors.white
                                          : AppColors.textPrimary,
                                      fontWeight: FontWeight.w600,
                                    ),
                                    onSelected: (_) =>
                                        setState(() => _slot = s),
                                  ),
                              ],
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
            label: 'Criar marcação',
            icon: Icons.check,
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
                onPressed: _loadLists,
                child: const Text('Tentar de novo'),
              ),
            ],
          ),
        ),
      );

  Widget _missingSetupState(String? category) => Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.info_outline, size: 64, color: Colors.grey),
              const SizedBox(height: 16),
              const Text(
                'Configuração em falta',
                style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 6),
              Text(
                'Cria pelo menos um serviço e um '
                '${StaffTerminology.singular(category).toLowerCase()} primeiro.',
                textAlign: TextAlign.center,
                style: const TextStyle(color: AppColors.textSecondary),
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
