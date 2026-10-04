// Folgas da equipa das barbearias/salões (ronda 04/10/2026, agente admin-geral).
// As exceções de horário (`staff_availability_exceptions`, is_working=false =
// folga) só eram geridas pelo parceiro. Aqui: escolher o negócio e o
// profissional, ver as folgas futuras, marcar uma folga nova ou tirar uma
// (com confirmação). Cada mudança fica no histórico de ações.

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../config/app_colors.dart';
import '../../widgets/bora/bora_screen_app_bar.dart';

class AdminFolgasScreen extends StatefulWidget {
  const AdminFolgasScreen({super.key});

  @override
  State<AdminFolgasScreen> createState() => _AdminFolgasScreenState();
}

class _AdminFolgasScreenState extends State<AdminFolgasScreen> {
  final _sb = Supabase.instance.client;
  List<Map<String, dynamic>> _negocios = const [];
  List<Map<String, dynamic>> _equipa = const [];
  List<Map<String, dynamic>> _folgas = const [];
  String? _negocio;
  String? _pessoa;
  bool _loading = false;
  bool _gravando = false;

  @override
  void initState() {
    super.initState();
    _loadNegocios();
  }

  String _iso(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  String _br(String iso) {
    final p = iso.split('-');
    return p.length == 3 ? '${p[2]}/${p[1]}/${p[0]}' : iso;
  }

  Future<void> _loadNegocios() async {
    try {
      final rows = await _sb
          .from('service_providers')
          .select('id, name')
          .order('name')
          .limit(500);
      if (!mounted) return;
      setState(() => _negocios = List<Map<String, dynamic>>.from(rows));
    } catch (e) {
      debugPrint('[AdminFolgas] negocios: $e');
    }
  }

  Future<void> _loadEquipa() async {
    final n = _negocio;
    if (n == null) return;
    try {
      final rows = await _sb
          .from('staff_members')
          .select('id, name, is_active')
          .eq('provider_id', n)
          .order('sort_order');
      if (!mounted) return;
      setState(() => _equipa = List<Map<String, dynamic>>.from(rows));
    } catch (e) {
      debugPrint('[AdminFolgas] equipa: $e');
    }
  }

  Future<void> _loadFolgas() async {
    final p = _pessoa;
    if (p == null) return;
    setState(() => _loading = true);
    try {
      final rows = await _sb
          .from('staff_availability_exceptions')
          .select('id, date, is_working, start_time, end_time, note')
          .eq('staff_id', p)
          .gte('date', _iso(DateTime.now().subtract(const Duration(days: 30))))
          .order('date');
      if (!mounted) return;
      setState(() {
        _folgas = List<Map<String, dynamic>>.from(rows);
        _loading = false;
      });
    } catch (e) {
      debugPrint('[AdminFolgas] folgas: $e');
      if (!mounted) return;
      setState(() => _loading = false);
    }
  }

  Future<void> _novaFolga() async {
    final p = _pessoa;
    if (p == null || _gravando) return;
    final hoje = DateTime.now();
    final dia = await showDatePicker(
      context: context,
      initialDate: hoje,
      firstDate: hoje,
      lastDate: hoje.add(const Duration(days: 365)),
    );
    if (dia == null || !mounted) return;
    final nota = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Folga a ${_br(_iso(dia))}'),
        content: TextField(
            controller: nota,
            decoration:
                const InputDecoration(labelText: 'Nota (opcional)')),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancelar')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Marcar folga')),
        ],
      ),
    );
    final txt = nota.text.trim();
    if (ok != true || !mounted) return;
    setState(() => _gravando = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      final row = await _sb
          .from('staff_availability_exceptions')
          .insert({
            'staff_id': p,
            'date': _iso(dia),
            'is_working': false,
            'note': txt.isEmpty ? 'Folga marcada pelo admin' : txt,
          })
          .select('id')
          .single();
      await _sb.rpc('log_admin_action', params: {
        'p_action': 'folga_marcada',
        'p_entity_type': 'staff_availability_exception',
        'p_entity_id': row['id'],
        'p_details': {'staff_id': p, 'dia': _iso(dia), 'nota': txt},
      });
      messenger.showSnackBar(const SnackBar(content: Text('Folga marcada.')));
      await _loadFolgas();
    } catch (e) {
      debugPrint('[AdminFolgas] nova: $e');
      messenger.showSnackBar(const SnackBar(
          content: Text('Não consegui marcar (já há exceção nesse dia?).')));
    } finally {
      if (mounted) setState(() => _gravando = false);
    }
  }

  Future<void> _tirar(Map<String, dynamic> f) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Tirar esta folga?'),
        content: Text(
            'O dia ${_br('${f['date']}')} volta ao horário normal e pode receber marcações.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancelar')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Tirar folga')),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    try {
      await _sb.from('staff_availability_exceptions').delete().eq('id', f['id']);
      await _sb.rpc('log_admin_action', params: {
        'p_action': 'folga_retirada',
        'p_entity_type': 'staff_availability_exception',
        'p_entity_id': f['id'],
        'p_details': {'staff_id': _pessoa, 'dia': f['date'], 'nota': f['note']},
      });
      messenger.showSnackBar(const SnackBar(content: Text('Folga retirada.')));
      await _loadFolgas();
    } catch (e) {
      debugPrint('[AdminFolgas] tirar: $e');
      messenger.showSnackBar(
          const SnackBar(content: Text('Não consegui tirar a folga.')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: const BoraScreenAppBar(title: 'Folgas da equipa'),
      floatingActionButton: _pessoa == null
          ? null
          : FloatingActionButton.extended(
              onPressed: _gravando ? null : _novaFolga,
              icon: const Icon(Icons.event_busy),
              label: const Text('Marcar folga'),
            ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          DropdownButtonFormField<String>(
            value: _negocio,
            isExpanded: true,
            decoration: const InputDecoration(labelText: 'Negócio'),
            items: [
              for (final n in _negocios)
                DropdownMenuItem(
                    value: n['id'] as String,
                    child: Text('${n['name'] ?? n['id']}',
                        overflow: TextOverflow.ellipsis)),
            ],
            onChanged: (v) {
              setState(() {
                _negocio = v;
                _pessoa = null;
                _equipa = const [];
                _folgas = const [];
              });
              _loadEquipa();
            },
          ),
          const SizedBox(height: 12),
          if (_negocio != null)
            DropdownButtonFormField<String>(
              key: ValueKey(_negocio),
              value: _pessoa,
              isExpanded: true,
              decoration: const InputDecoration(labelText: 'Profissional'),
              items: [
                for (final s in _equipa)
                  DropdownMenuItem(
                      value: s['id'] as String,
                      child: Text(
                          '${s['name'] ?? s['id']}${s['is_active'] == false ? ' (inativo)' : ''}')),
              ],
              onChanged: (v) {
                setState(() => _pessoa = v);
                _loadFolgas();
              },
            ),
          const SizedBox(height: 16),
          if (_pessoa != null && _loading)
            const Center(child: CircularProgressIndicator())
          else if (_pessoa != null && _folgas.isEmpty)
            const Text('Sem folgas nem exceções nos próximos dias.')
          else
            for (final f in _folgas)
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: Icon(
                  f['is_working'] == false ? Icons.event_busy : Icons.schedule,
                  color: f['is_working'] == false
                      ? AppColors.error
                      : AppColors.textSecondary,
                ),
                title: Text(_br('${f['date']}')),
                subtitle: Text(f['is_working'] == false
                    ? 'Folga${(f['note'] ?? '').toString().isEmpty ? '' : ' · ${f['note']}'}'
                    : 'Horário especial ${f['start_time'] ?? ''}–${f['end_time'] ?? ''}'),
                trailing: IconButton(
                  tooltip: 'Tirar',
                  icon: const Icon(Icons.close),
                  onPressed: () => _tirar(f),
                ),
              ),
        ],
      ),
    );
  }
}
