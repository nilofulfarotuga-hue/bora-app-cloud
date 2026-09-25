import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../config/app_colors.dart';
import '../../../config/app_spacing.dart';
import '../../../models/provider_service_model.dart';
import '../../../stores/partner_appointments_store.dart';
import '../../../widgets/bora/bora_primary_button.dart';
import '../../../widgets/bora/bora_screen_app_bar.dart';

/// Gestão de serviços do prestador (nome, duração, preço). Criar/editar via
/// bottom-sheet, desactivar (soft delete is_active=false).
class PartnerManageServicesScreen extends StatefulWidget {
  const PartnerManageServicesScreen({super.key});

  @override
  State<PartnerManageServicesScreen> createState() =>
      _PartnerManageServicesScreenState();
}

class _PartnerManageServicesScreenState
    extends State<PartnerManageServicesScreen> {
  late Future<List<ProviderServiceModel>> _future;

  @override
  void initState() {
    super.initState();
    _future = context.read<PartnerAppointmentsStore>().fetchServices();
  }

  void _refresh() {
    setState(() {
      _future = context.read<PartnerAppointmentsStore>().fetchServices();
    });
  }

  Future<void> _openForm({ProviderServiceModel? existing}) async {
    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => _ServiceForm(existing: existing),
    );
    if (saved == true) _refresh();
  }

  Future<void> _confirmDeactivate(ProviderServiceModel s) async {
    final store = context.read<PartnerAppointmentsStore>();
    final messenger = ScaffoldMessenger.of(context);
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Desactivar serviço'),
        content: Text('Remover "${s.name}" da lista? O histórico mantém-se.'),
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
      await store.deactivateService(s.id);
      if (!mounted) return;
      messenger.showSnackBar(const SnackBar(
        content: Text('Serviço desactivado.'),
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
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: const BoraScreenAppBar(title: 'Serviços'),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _openForm(),
        backgroundColor: AppColors.accent,
        foregroundColor: Colors.white,
        icon: const Icon(Icons.add),
        label: const Text('Novo serviço'),
      ),
      body: FutureBuilder<List<ProviderServiceModel>>(
        future: _future,
        builder: (context, snap) {
          if (snap.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snap.hasError) {
            return _error(snap.error.toString());
          }
          final items = snap.data ?? const <ProviderServiceModel>[];
          if (items.isEmpty) {
            return _empty();
          }
          return RefreshIndicator(
            onRefresh: () async => _refresh(),
            child: ListView.builder(
              padding: const EdgeInsets.fromLTRB(
                  Spacing.lg, Spacing.lg, Spacing.lg, 88),
              itemCount: items.length,
              itemBuilder: (_, i) => _ServiceTile(
                service: items[i],
                onEdit: () => _openForm(existing: items[i]),
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

  Widget _empty() => const Center(
        child: Padding(
          padding: EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.content_cut, size: 64, color: Colors.grey),
              SizedBox(height: 16),
              Text(
                'Sem serviços',
                style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
              ),
              SizedBox(height: 6),
              Text(
                'Adiciona o primeiro serviço no botão "Novo serviço".',
                textAlign: TextAlign.center,
                style: TextStyle(color: AppColors.textSecondary),
              ),
            ],
          ),
        ),
      );
}

class _ServiceTile extends StatelessWidget {
  const _ServiceTile({
    required this.service,
    required this.onEdit,
    required this.onDeactivate,
  });

  final ProviderServiceModel service;
  final VoidCallback onEdit;
  final VoidCallback onDeactivate;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: Spacing.md),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(Radii.lg),
        boxShadow: AppColors.shadowCard,
      ),
      child: Padding(
        padding: const EdgeInsets.all(Spacing.lg),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    service.name,
                    style: const TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 15,
                      color: AppColors.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '${service.durationLabel} · ${service.priceLabel}',
                    style: const TextStyle(
                      fontSize: 13,
                      color: AppColors.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
            IconButton(
              icon: const Icon(Icons.edit_outlined),
              tooltip: 'Editar',
              onPressed: onEdit,
            ),
            IconButton(
              icon: const Icon(Icons.delete_outline, color: AppColors.error),
              tooltip: 'Desactivar',
              onPressed: onDeactivate,
            ),
          ],
        ),
      ),
    );
  }
}

class _ServiceForm extends StatefulWidget {
  const _ServiceForm({this.existing});
  final ProviderServiceModel? existing;

  @override
  State<_ServiceForm> createState() => _ServiceFormState();
}

class _ServiceFormState extends State<_ServiceForm> {
  late final TextEditingController _name;
  late final TextEditingController _desc;
  late final TextEditingController _duration;
  late final TextEditingController _price;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    _name = TextEditingController(text: e?.name ?? '');
    _desc = TextEditingController(text: e?.description ?? '');
    _duration = TextEditingController(
        text: e != null ? e.durationMinutes.toString() : '30');
    _price = TextEditingController(
        text: e != null ? (e.priceCents / 100).toStringAsFixed(2) : '');
  }

  @override
  void dispose() {
    _name.dispose();
    _desc.dispose();
    _duration.dispose();
    _price.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_saving) return;
    final messenger = ScaffoldMessenger.of(context);
    final name = _name.text.trim();
    final duration = int.tryParse(_duration.text.trim());
    final priceEur = double.tryParse(_price.text.trim().replaceAll(',', '.'));
    if (name.isEmpty) {
      messenger.showSnackBar(
        const SnackBar(content: Text('Indica o nome do serviço.')),
      );
      return;
    }
    if (duration == null || duration <= 0) {
      messenger.showSnackBar(
        const SnackBar(content: Text('Duração inválida (minutos).')),
      );
      return;
    }
    if (priceEur == null || priceEur < 0) {
      messenger.showSnackBar(
        const SnackBar(content: Text('Preço inválido.')),
      );
      return;
    }
    final priceCents = (priceEur * 100).round();
    setState(() => _saving = true);
    try {
      final store = context.read<PartnerAppointmentsStore>();
      if (widget.existing == null) {
        await store.createService(
          name: name,
          description: _desc.text.trim(),
          durationMinutes: duration,
          priceCents: priceCents,
        );
      } else {
        await store.updateService(
          serviceId: widget.existing!.id,
          name: name,
          description: _desc.text.trim(),
          durationMinutes: duration,
          priceCents: priceCents,
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
            isEdit ? 'Editar serviço' : 'Novo serviço',
            style: const TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w800,
              color: AppColors.textPrimary,
            ),
          ),
          const SizedBox(height: Spacing.lg),
          TextField(
            controller: _name,
            textCapitalization: TextCapitalization.sentences,
            decoration: const InputDecoration(
              labelText: 'Nome',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: Spacing.md),
          TextField(
            controller: _desc,
            decoration: const InputDecoration(
              labelText: 'Descrição (opcional)',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: Spacing.md),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _duration,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: 'Duração (min)',
                    border: OutlineInputBorder(),
                  ),
                ),
              ),
              const SizedBox(width: Spacing.md),
              Expanded(
                child: TextField(
                  controller: _price,
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(
                    labelText: 'Preço (€)',
                    border: OutlineInputBorder(),
                  ),
                ),
              ),
            ],
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
