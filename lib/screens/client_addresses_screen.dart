import 'dart:async';

import 'package:flutter/material.dart';

import '../config/app_colors.dart';
import '../config/app_spacing.dart';
import '../config/maps_config.dart';
import '../models/client_address.dart';
import '../services/client_address_service.dart';
import '../services/google_places_service.dart';
import '../widgets/bora/bora_primary_button.dart';
import '../widgets/bora/bora_screen_app_bar.dart';

/// Ecrã de gestão de endereços do cliente.
/// CRUD sobre `client_addresses` (RLS por user_id). Padrão Uber/Glovo:
/// rótulo (Casa/Trabalho/Outro) + autocomplete Google Places + default.
class ClientAddressesScreen extends StatefulWidget {
  const ClientAddressesScreen({super.key, this.selectMode = false});

  /// Quando true, ao tocar num endereço devolve-o via Navigator.pop(address).
  final bool selectMode;

  @override
  State<ClientAddressesScreen> createState() => _ClientAddressesScreenState();
}

class _ClientAddressesScreenState extends State<ClientAddressesScreen> {
  final _service = ClientAddressService.instance;
  List<ClientAddress> _addresses = const [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final list = await _service.list();
      if (!mounted) return;
      setState(() => _addresses = list);
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _openForm({ClientAddress? edit}) async {
    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _AddressFormSheet(edit: edit),
    );
    if (saved == true) await _load();
  }

  Future<void> _setDefault(ClientAddress a) async {
    try {
      await _service.setDefault(a.id);
      await _load();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erro: $e')),
        );
      }
    }
  }

  Future<void> _delete(ClientAddress a) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Eliminar endereço'),
        content: Text('Eliminar "${a.label}"?'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancelar')),
          FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Eliminar')),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await _service.delete(a.id);
      await _load();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erro: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: BoraScreenAppBar(
        title: widget.selectMode ? 'Escolher endereço' : 'Os meus endereços',
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _openForm(),
        icon: const Icon(Icons.add_location_alt),
        label: const Text('Adicionar'),
      ),
      body: RefreshIndicator(
        onRefresh: _load,
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : _error != null
                ? ListView(children: [
                    const SizedBox(height: 80),
                    Center(
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Text(_error!,
                            textAlign: TextAlign.center,
                            style: const TextStyle(color: AppColors.error)),
                      ),
                    ),
                  ])
                : _addresses.isEmpty
                    ? _empty()
                    : ListView.separated(
                        padding: const EdgeInsets.fromLTRB(12, 12, 12, 80),
                        itemCount: _addresses.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 8),
                        itemBuilder: (_, i) => _addressTile(_addresses[i]),
                      ),
      ),
    );
  }

  Widget _empty() => ListView(
        children: [
          const SizedBox(height: 120),
          const Icon(Icons.location_on_outlined,
              size: 72, color: AppColors.textSubtle),
          const SizedBox(height: 12),
          const Center(
            child: Text('Ainda não tens endereços guardados',
                style: TextStyle(fontSize: 16)),
          ),
          const SizedBox(height: 6),
          const Center(
            child: Text(
              'Adiciona Casa e Trabalho para escolheres mais rápido no checkout.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 13, color: AppColors.textSecondary),
            ),
          ),
        ],
      );

  Widget _addressTile(ClientAddress a) {
    final icon = switch (a.label.toLowerCase()) {
      'casa' || 'home' => Icons.home,
      'trabalho' || 'work' => Icons.work,
      _ => Icons.place,
    };
    return Container(
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(Radii.lg),
        boxShadow: AppColors.shadowCard,
      ),
      child: ListTile(
        leading: Icon(icon, color: AppColors.primary),
        title: Row(
          children: [
            Flexible(
              child: Text(a.label,
                  style: const TextStyle(fontWeight: FontWeight.w700)),
            ),
            if (a.isDefault) ...[
              const SizedBox(width: 6),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: AppColors.primaryLight,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Text('Predefinido',
                    style: TextStyle(fontSize: 10, color: AppColors.primary)),
              ),
            ],
          ],
        ),
        subtitle: Text(a.address,
            maxLines: 2, overflow: TextOverflow.ellipsis),
        onTap: widget.selectMode
            ? () => Navigator.pop(context, a)
            : () => _openForm(edit: a),
        trailing: PopupMenuButton<String>(
          onSelected: (v) {
            switch (v) {
              case 'edit':
                _openForm(edit: a);
                break;
              case 'default':
                _setDefault(a);
                break;
              case 'delete':
                _delete(a);
                break;
            }
          },
          itemBuilder: (_) => [
            const PopupMenuItem(value: 'edit', child: Text('Editar')),
            if (!a.isDefault)
              const PopupMenuItem(
                  value: 'default', child: Text('Tornar predefinido')),
            const PopupMenuItem(value: 'delete', child: Text('Eliminar')),
          ],
        ),
      ),
    );
  }
}

class _AddressFormSheet extends StatefulWidget {
  const _AddressFormSheet({this.edit});
  final ClientAddress? edit;

  @override
  State<_AddressFormSheet> createState() => _AddressFormSheetState();
}

class _AddressFormSheetState extends State<_AddressFormSheet> {
  final _labelCtrl = TextEditingController();
  final _addressCtrl = TextEditingController();
  final _places = GooglePlacesService(googleApiKey);
  Timer? _debounce;
  List<dynamic> _predictions = const [];
  double? _lat;
  double? _lng;
  String? _city;
  String? _postalCode;
  bool _isDefault = false;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    final e = widget.edit;
    if (e != null) {
      _labelCtrl.text = e.label;
      _addressCtrl.text = e.address;
      _lat = e.lat;
      _lng = e.lng;
      _city = e.city;
      _postalCode = e.postalCode;
      _isDefault = e.isDefault;
    }
  }

  @override
  void dispose() {
    _labelCtrl.dispose();
    _addressCtrl.dispose();
    _debounce?.cancel();
    super.dispose();
  }

  void _onAddressChanged(String v) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 350), () async {
      if (v.trim().length < 3) {
        if (mounted) setState(() => _predictions = const []);
        return;
      }
      try {
        final preds = await _places.autocomplete(v.trim());
        if (mounted) setState(() => _predictions = preds);
      } catch (_) {/* silencioso */}
    });
  }

  Future<void> _selectPrediction(Map<String, dynamic> pred) async {
    final placeId = pred['place_id'] as String?;
    final desc = pred['description'] as String?;
    if (placeId == null || desc == null) return;
    setState(() {
      _addressCtrl.text = desc;
      _predictions = const [];
    });
    try {
      final details = await _places.placeDetails(placeId);
      if (details == null) return;
      final geom = details['geometry'] as Map?;
      final loc = geom?['location'] as Map?;
      if (loc != null) {
        _lat = (loc['lat'] as num?)?.toDouble();
        _lng = (loc['lng'] as num?)?.toDouble();
      }
      final comps = (details['address_components'] as List?) ?? const [];
      for (final c in comps) {
        final m = (c as Map).cast<String, dynamic>();
        final types = (m['types'] as List?) ?? const [];
        if (types.contains('postal_code')) {
          _postalCode = m['long_name'] as String?;
        }
        if (types.contains('locality') ||
            types.contains('administrative_area_level_2')) {
          _city ??= m['long_name'] as String?;
        }
      }
      if (mounted) setState(() {});
    } catch (_) {/* silencioso */}
  }

  Future<void> _save() async {
    if (_labelCtrl.text.trim().isEmpty || _addressCtrl.text.trim().isEmpty) {
      setState(() => _error = 'Preenche rótulo e endereço.');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final svc = ClientAddressService.instance;
      if (widget.edit != null) {
        await svc.update(
          id: widget.edit!.id,
          label: _labelCtrl.text.trim(),
          address: _addressCtrl.text.trim(),
          city: _city,
          postalCode: _postalCode,
          lat: _lat,
          lng: _lng,
          isDefault: _isDefault,
        );
      } else {
        await svc.create(
          label: _labelCtrl.text.trim(),
          address: _addressCtrl.text.trim(),
          city: _city,
          postalCode: _postalCode,
          lat: _lat,
          lng: _lng,
          isDefault: _isDefault,
        );
      }
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;
    return Padding(
      padding: EdgeInsets.only(bottom: bottomInset),
      child: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                widget.edit == null ? 'Novo endereço' : 'Editar endereço',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 16),
              Wrap(
                spacing: 8,
                children: ['Casa', 'Trabalho', 'Outro'].map((preset) {
                  final selected = _labelCtrl.text == preset;
                  return ChoiceChip(
                    label: Text(preset),
                    selected: selected,
                    onSelected: (_) =>
                        setState(() => _labelCtrl.text = preset),
                  );
                }).toList(),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _labelCtrl,
                decoration: const InputDecoration(
                  labelText: 'Rótulo',
                  hintText: 'Casa, Trabalho, Casa dos pais...',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _addressCtrl,
                onChanged: _onAddressChanged,
                decoration: const InputDecoration(
                  labelText: 'Endereço',
                  hintText: 'Rua, número, cidade',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.place),
                ),
              ),
              if (_predictions.isNotEmpty)
                Container(
                  margin: const EdgeInsets.only(top: 4),
                  decoration: BoxDecoration(
                    border: Border.all(color: AppColors.divider),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Column(
                    children: _predictions.take(5).map((p) {
                      final m = (p as Map).cast<String, dynamic>();
                      return ListTile(
                        dense: true,
                        leading: const Icon(Icons.location_on, size: 18),
                        title: Text(
                          m['description'] as String? ?? '',
                          style: const TextStyle(fontSize: 13),
                        ),
                        onTap: () => _selectPrediction(m),
                      );
                    }).toList(),
                  ),
                ),
              const SizedBox(height: 12),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Tornar predefinido'),
                subtitle: const Text('Usado por defeito no checkout'),
                value: _isDefault,
                onChanged: (v) => setState(() => _isDefault = v),
              ),
              if (_error != null) ...[
                const SizedBox(height: 8),
                Text(_error!, style: const TextStyle(color: AppColors.error)),
              ],
              const SizedBox(height: 16),
              BoraPrimaryButton(
                label: 'Guardar',
                onPressed: _saving ? null : _save,
                loading: _saving,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
