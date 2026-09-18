import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../config/app_colors.dart';
import '../../config/app_spacing.dart';
import '../../widgets/bora/bora_screen_app_bar.dart';
import 'admin_tvde_balcao_screen.dart';

/// Bora Motorista — Agenda de Clientes de Balcão
/// (missão `central-corridas-balcao-2026-09-18`, Bloco 3).
///
/// Clientes sem app (telefonam ao Danilo) e as moradas guardadas deles
/// (`tvde_client_places`, apelido tipo "Casa"/"Trabalho").
///
/// [Nota de terreno — servidor] Criar/editar/apagar o CLIENTE (linha em
/// `public.users`) não é possível a partir daqui: a RLS só deixa o dono
/// (`auth.uid() = id`) escrever nessa tabela — não há política de admin para
/// INSERT/UPDATE/DELETE, nem uma RPC `admin_*` para isso (só existe
/// `admin_tvde_create_counter_ride`, que cria o cliente como EFEITO
/// SECUNDÁRIO de uma corrida — não dá para usar aqui sem criar uma corrida
/// fantasma). Por isso a lista abaixo é só LEITURA, e "criar cliente" manda
/// para "Corridas de Balcão" (o cliente nasce ao criar a primeira corrida
/// dele). Ver relatório da missão para a proposta de RPCs
/// `admin_create_counter_client` / `admin_update_counter_client` — não são
/// meus para criar (fora do âmbito: SQL/migration).
///
/// As MORADAS (`tvde_client_places`) já têm política de admin completa
/// (`tvde_client_places_admin_all`, `is_admin()`) — por isso aqui é CRUD a
/// sério, direto na tabela.
class AdminTvdeBalcaoAgendaScreen extends StatefulWidget {
  const AdminTvdeBalcaoAgendaScreen({super.key});

  @override
  State<AdminTvdeBalcaoAgendaScreen> createState() =>
      _AdminTvdeBalcaoAgendaScreenState();
}

class _AdminTvdeBalcaoAgendaScreenState
    extends State<AdminTvdeBalcaoAgendaScreen> {
  List<Map<String, dynamic>> _clients = const [];
  bool _loading = true;
  String? _error;
  String _query = '';

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
          .from('users')
          .select('id, name, phone, created_at')
          .eq('is_counter_client', true)
          .order('name');
      if (!mounted) return;
      setState(() {
        _clients = (res as List)
            .cast<Map>()
            .map((e) => Map<String, dynamic>.from(e))
            .toList();
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = '$e';
        _loading = false;
      });
    }
  }

  void _explicaCriarCliente() {
    showDialog<void>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Novo cliente de balcão'),
        content: const Text(
          'O cliente nasce sozinho quando crias a primeira corrida dele em '
          '"Corridas de Balcão" — basta o telefone. Não há hoje um jeito de '
          'criar um cliente aqui sem criar também uma corrida (falta uma '
          'função no servidor para isso). Se só queres guardar o contacto '
          'para depois, cria a corrida quando ele ligar da próxima vez.',
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Entendi')),
          FilledButton.icon(
            onPressed: () {
              Navigator.of(context).pop();
              Navigator.of(context).push(MaterialPageRoute(
                  builder: (_) => const AdminTvdeBalcaoScreen()));
            },
            icon: const Icon(Icons.add),
            label: const Text('Ir para Corridas de Balcão'),
          ),
        ],
      ),
    );
  }

  void _explicaOcr() {
    showDialog<void>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Importar contacto por print'),
        content: const Text(
          'Ainda não dá. Precisa de uma Edge Function nova no servidor (ou '
          'adaptar a "ocr-receipt" dos Favores, que hoje só lê talão já '
          'guardado numa encomenda) para receber a foto do contacto e devolver '
          'nome+telefone pelo Gemini Vision. Isso é trabalho de servidor — '
          'fica registado no relatório da missão para outra sessão o fazer.',
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Entendi')),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final filtered = _query.trim().isEmpty
        ? _clients
        : _clients.where((c) {
            final n = (c['name'] as String? ?? '').toLowerCase();
            final p = (c['phone'] as String? ?? '');
            final q = _query.toLowerCase();
            return n.contains(q) || p.contains(_query);
          }).toList();

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: const BoraScreenAppBar(title: 'Agenda de Clientes de Balcão'),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _explicaCriarCliente,
        icon: const Icon(Icons.person_add),
        label: const Text('Novo cliente'),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(child: Text('Erro:\n$_error', textAlign: TextAlign.center))
              : RefreshIndicator(
                  onRefresh: _load,
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(12, 12, 12, 88),
                    children: [
                      TextField(
                        decoration: const InputDecoration(
                          hintText: 'Buscar por nome ou telefone',
                          prefixIcon: Icon(Icons.search),
                          isDense: true,
                          border: OutlineInputBorder(),
                        ),
                        onChanged: (v) => setState(() => _query = v),
                      ),
                      const SizedBox(height: 8),
                      OutlinedButton.icon(
                        onPressed: _explicaOcr,
                        icon: const Icon(Icons.document_scanner_outlined,
                            size: 18),
                        label: const Text('Importar contacto por print'),
                      ),
                      const SizedBox(height: 8),
                      Text('${filtered.length} cliente(s) de balcão',
                          style: const TextStyle(
                              color: AppColors.textSecondary, fontSize: 12)),
                      const SizedBox(height: 8),
                      if (filtered.isEmpty)
                        const Padding(
                          padding: EdgeInsets.only(top: 60),
                          child: Center(
                            child: Text('Nenhum cliente de balcão ainda.',
                                style:
                                    TextStyle(color: AppColors.textSecondary)),
                          ),
                        )
                      else
                        ...filtered.map((c) => _ClientCard(client: c)),
                    ],
                  ),
                ),
    );
  }
}

class _ClientCard extends StatefulWidget {
  const _ClientCard({required this.client});
  final Map<String, dynamic> client;

  @override
  State<_ClientCard> createState() => _ClientCardState();
}

class _ClientCardState extends State<_ClientCard> {
  bool _expanded = false;
  List<Map<String, dynamic>> _places = const [];
  bool _loadingPlaces = false;

  Future<void> _loadPlaces() async {
    setState(() => _loadingPlaces = true);
    try {
      final res = await Supabase.instance.client
          .from('tvde_client_places')
          .select('id, label, address, lat, lng, use_count, last_used_at')
          .eq('client_id', widget.client['id'])
          .order('label');
      if (!mounted) return;
      setState(() {
        _places = (res as List)
            .cast<Map>()
            .map((e) => Map<String, dynamic>.from(e))
            .toList();
        _loadingPlaces = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _loadingPlaces = false);
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Erro a carregar moradas: $e')));
    }
  }

  Future<void> _addOrEditPlace({Map<String, dynamic>? place}) async {
    final saved = await showDialog<bool>(
      context: context,
      builder: (_) => _PlaceEditorDialog(
        clientId: widget.client['id'].toString(),
        place: place,
      ),
    );
    if (saved == true) _loadPlaces();
  }

  Future<void> _deletePlace(Map<String, dynamic> place) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Apagar morada'),
        content: Text('Apagar "${place['label']}"?'),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Voltar')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppColors.error),
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Apagar'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await Supabase.instance.client
          .from('tvde_client_places')
          .delete()
          .eq('id', place['id']);
      _loadPlaces();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Não deu para apagar: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.client;
    final name = (c['name'] as String?)?.trim();
    final phone = (c['phone'] as String?)?.trim();
    return Card(
      elevation: 1,
      margin: const EdgeInsets.only(bottom: 8),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Column(
        children: [
          ListTile(
            leading: const CircleAvatar(
              backgroundColor: AppColors.primaryWash,
              child: Icon(Icons.person, color: AppColors.primary),
            ),
            title: Text((name == null || name.isEmpty) ? '(sem nome)' : name),
            subtitle: Text(phone ?? '—'),
            trailing: IconButton(
              icon: Icon(_expanded ? Icons.expand_less : Icons.expand_more),
              onPressed: () {
                setState(() => _expanded = !_expanded);
                if (_expanded && _places.isEmpty) _loadPlaces();
              },
            ),
          ),
          if (_expanded)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Divider(),
                  Row(
                    children: [
                      const Text('Moradas guardadas',
                          style: TextStyle(fontWeight: FontWeight.w700)),
                      const Spacer(),
                      TextButton.icon(
                        onPressed: () => _addOrEditPlace(),
                        icon: const Icon(Icons.add, size: 16),
                        label: const Text('Nova morada'),
                      ),
                    ],
                  ),
                  if (_loadingPlaces)
                    const Padding(
                      padding: EdgeInsets.all(12),
                      child: Center(child: CircularProgressIndicator()),
                    )
                  else if (_places.isEmpty)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 8),
                      child: Text('Nenhuma morada guardada.',
                          style: TextStyle(color: AppColors.textSecondary)),
                    )
                  else
                    ..._places.map((p) => ListTile(
                          dense: true,
                          contentPadding: EdgeInsets.zero,
                          leading: const Icon(Icons.place_outlined, size: 20),
                          title: Text(p['label'] ?? '',
                              style:
                                  const TextStyle(fontWeight: FontWeight.w600)),
                          subtitle: Text(p['address'] ?? '',
                              maxLines: 1, overflow: TextOverflow.ellipsis),
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              IconButton(
                                icon: const Icon(Icons.edit, size: 18),
                                onPressed: () => _addOrEditPlace(place: p),
                              ),
                              IconButton(
                                icon: const Icon(Icons.delete_outline,
                                    size: 18, color: AppColors.error),
                                onPressed: () => _deletePlace(p),
                              ),
                            ],
                          ),
                        )),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _PlaceEditorDialog extends StatefulWidget {
  const _PlaceEditorDialog({required this.clientId, this.place});
  final String clientId;
  final Map<String, dynamic>? place;

  @override
  State<_PlaceEditorDialog> createState() => _PlaceEditorDialogState();
}

class _PlaceEditorDialogState extends State<_PlaceEditorDialog> {
  late final _label = TextEditingController(text: widget.place?['label'] ?? '');
  late final _address =
      TextEditingController(text: widget.place?['address'] ?? '');
  late final _lat =
      TextEditingController(text: widget.place?['lat']?.toString() ?? '');
  late final _lng =
      TextEditingController(text: widget.place?['lng']?.toString() ?? '');
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    _label.dispose();
    _address.dispose();
    _lat.dispose();
    _lng.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final lat = double.tryParse(_lat.text.trim().replaceAll(',', '.'));
    final lng = double.tryParse(_lng.text.trim().replaceAll(',', '.'));
    if (_label.text.trim().isEmpty ||
        _address.text.trim().isEmpty ||
        lat == null ||
        lng == null) {
      setState(() => _error =
          'Preenche apelido, morada e latitude/longitude (números).');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      if (widget.place == null) {
        await Supabase.instance.client.from('tvde_client_places').insert({
          'client_id': widget.clientId,
          'label': _label.text.trim(),
          'address': _address.text.trim(),
          'lat': lat,
          'lng': lng,
        });
      } else {
        await Supabase.instance.client
            .from('tvde_client_places')
            .update({
              'label': _label.text.trim(),
              'address': _address.text.trim(),
              'lat': lat,
              'lng': lng,
            })
            .eq('id', widget.place!['id']);
      }
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (e) {
      setState(() {
        _saving = false;
        _error = 'Não deu: $e';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.place == null ? 'Nova morada' : 'Editar morada'),
      content: SizedBox(
        width: 420,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _label,
              decoration: const InputDecoration(
                labelText: 'Apelido (Casa, Trabalho, Estádio…)',
                isDense: true,
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: Spacing.sm),
            TextField(
              controller: _address,
              decoration: const InputDecoration(
                labelText: 'Morada (texto)',
                isDense: true,
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: Spacing.sm),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _lat,
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true, signed: true),
                    decoration: const InputDecoration(
                      labelText: 'Latitude',
                      isDense: true,
                      border: OutlineInputBorder(),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: TextField(
                    controller: _lng,
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true, signed: true),
                    decoration: const InputDecoration(
                      labelText: 'Longitude',
                      isDense: true,
                      border: OutlineInputBorder(),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            const Text(
              'Dica: abre o Google Maps, clica no ponto certo e copia as '
              'coordenadas que aparecem.',
              style: TextStyle(fontSize: 11, color: AppColors.textSecondary),
            ),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(_error!,
                    style:
                        const TextStyle(color: AppColors.error, fontSize: 12)),
              ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.of(context).pop(false),
          child: const Text('Cancelar'),
        ),
        FilledButton(
          onPressed: _saving ? null : _save,
          child: Text(_saving ? 'A gravar…' : 'Gravar'),
        ),
      ],
    );
  }
}
