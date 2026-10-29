import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../config/app_colors.dart';
import '../../widgets/bora/bora_screen_app_bar.dart';

/// Item 30 (paridade-admin-360): config dos filtros de descoberta do cliente
/// ("aberto agora", dietético). Lê/escreve a chave NÃO-financeira
/// platform_settings.discovery_filters via admin_update_setting.
/// 29/10/2026: a app do cliente já mostra os 3 filtros rápidos da lista de
/// restaurantes ("Aberto agora", "Ir buscar", "Entrega grátis") quando estes
/// interruptores estão ligados. Os filtros dietéticos continuam sem efeito
/// (precisam de etiqueta por produto).
class AdminDiscoveryFiltersScreen extends StatefulWidget {
  const AdminDiscoveryFiltersScreen({super.key});
  @override
  State<AdminDiscoveryFiltersScreen> createState() =>
      _AdminDiscoveryFiltersScreenState();
}

class _AdminDiscoveryFiltersScreenState
    extends State<AdminDiscoveryFiltersScreen> {
  bool _openNow = false;
  bool _takeaway = false;
  bool _freeDelivery = false;
  bool _dietary = false;
  List<String> _tags = const [];
  bool _loading = true;
  bool _saving = false;
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
      final res = await Supabase.instance.client
          .from('platform_settings')
          .select('value')
          .eq('key', 'discovery_filters')
          .maybeSingle();
      final v = ((res?['value'] as Map?) ?? {}).cast<String, dynamic>();
      if (mounted) {
        setState(() {
          _openNow = (v['open_now_enabled'] as bool?) ?? false;
          _takeaway = (v['takeaway_enabled'] as bool?) ?? false;
          _freeDelivery = (v['free_delivery_enabled'] as bool?) ?? false;
          _dietary = (v['dietary_enabled'] as bool?) ?? false;
          _tags = ((v['dietary_tags'] as List?) ?? const [])
              .map((e) => e.toString())
              .toList();
        });
      }
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      await Supabase.instance.client.rpc('admin_update_setting', params: {
        'p_key': 'discovery_filters',
        'p_value': {
          'open_now_enabled': _openNow,
          'takeaway_enabled': _takeaway,
          'free_delivery_enabled': _freeDelivery,
          'dietary_enabled': _dietary,
          'dietary_tags': _tags,
        },
      });
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Filtros de descoberta guardados.'),
        backgroundColor: AppColors.primary,
      ));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('Erro: $e'),
        backgroundColor: AppColors.error,
      ));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _addTag() async {
    final ctrl = TextEditingController();
    final tag = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Nova etiqueta dietética'),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          decoration: const InputDecoration(
            hintText: 'ex.: sem_acucar',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx), child: const Text('Cancelar')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppColors.primary),
            onPressed: () => Navigator.pop(ctx, ctrl.text.trim()),
            child: const Text('Adicionar'),
          ),
        ],
      ),
    );
    if (tag == null || tag.isEmpty || _tags.contains(tag)) return;
    setState(() => _tags = [..._tags, tag]);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: const BoraScreenAppBar(title: 'Filtros de Descoberta'),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(
                  child: Text(_error!,
                      style: const TextStyle(color: AppColors.error)))
              : ListView(
                  padding: const EdgeInsets.all(12),
                  children: [
                    Card(
                      child: SwitchListTile(
                        title: const Text('Filtro "Aberto agora"'),
                        subtitle: const Text(
                            'Cliente pode filtrar lojas abertas neste momento'),
                        value: _openNow,
                        activeThumbColor: AppColors.primary,
                        onChanged: (v) => setState(() => _openNow = v),
                      ),
                    ),
                    Card(
                      child: SwitchListTile(
                        key: const Key('filtro_ir_buscar_admin'),
                        title: const Text('Filtro "Ir buscar"'),
                        subtitle: const Text(
                            'Cliente pode ver só as lojas que têm retirada no balcão (takeaway)'),
                        value: _takeaway,
                        activeThumbColor: AppColors.primary,
                        onChanged: (v) => setState(() => _takeaway = v),
                      ),
                    ),
                    Card(
                      child: SwitchListTile(
                        key: const Key('filtro_entrega_gratis_admin'),
                        title: const Text('Filtro "Entrega grátis"'),
                        subtitle: const Text(
                            'Cliente pode ver só as lojas com entrega grátis configurada'),
                        value: _freeDelivery,
                        activeThumbColor: AppColors.primary,
                        onChanged: (v) => setState(() => _freeDelivery = v),
                      ),
                    ),
                    Card(
                      child: Column(
                        children: [
                          SwitchListTile(
                            title: const Text('Filtros dietéticos'),
                            subtitle: const Text(
                                'Cliente pode filtrar por etiquetas dietéticas'),
                            value: _dietary,
                            activeThumbColor: AppColors.primary,
                            onChanged: (v) => setState(() => _dietary = v),
                          ),
                          Padding(
                            padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                            child: Wrap(
                              spacing: 6,
                              runSpacing: 6,
                              children: [
                                ..._tags.map((t) => Chip(
                                      label: Text(t),
                                      onDeleted: () => setState(() => _tags =
                                          _tags
                                              .where((x) => x != t)
                                              .toList()),
                                    )),
                                ActionChip(
                                  avatar: const Icon(Icons.add, size: 18),
                                  label: const Text('Adicionar'),
                                  onPressed: _addTag,
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),
                    const Text(
                      'Os filtros "Aberto agora", "Ir buscar" e "Entrega grátis" '
                      'aparecem na lista de restaurantes da app do cliente quando '
                      'ligados. Os filtros dietéticos ainda não têm efeito: '
                      'precisam de etiqueta por produto.',
                      style: TextStyle(
                          color: AppColors.textSecondary, fontSize: 12),
                    ),
                    const SizedBox(height: 12),
                    FilledButton.icon(
                      style: FilledButton.styleFrom(
                          backgroundColor: AppColors.primary,
                          padding: const EdgeInsets.symmetric(vertical: 14)),
                      icon: _saving
                          ? const SizedBox(
                              height: 18,
                              width: 18,
                              child: CircularProgressIndicator(
                                  strokeWidth: 2, color: Colors.white))
                          : const Icon(Icons.save),
                      label: const Text('Guardar'),
                      onPressed: _saving ? null : _save,
                    ),
                  ],
                ),
    );
  }
}
