// Mesas dos restaurantes com reservas (ronda 04/10/2026, agente admin-geral).
// A tabela `restaurant_tables` não tinha ecrã no painel. Aqui: escolher a loja,
// ver as mesas e editar número, lugares, zona e se está ativa. Cada edição
// fica no histórico de ações (log_admin_action).

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../config/app_colors.dart';
import '../../widgets/bora/bora_screen_app_bar.dart';
import 'admin_opcoes_produto_screen.dart' show AdminEscolherLoja;

class AdminMesasScreen extends StatefulWidget {
  const AdminMesasScreen({super.key});

  @override
  State<AdminMesasScreen> createState() => _AdminMesasScreenState();
}

class _AdminMesasScreenState extends State<AdminMesasScreen> {
  String? _loja;
  List<Map<String, dynamic>> _mesas = const [];
  bool _loading = false;

  Future<void> _load() async {
    final loja = _loja;
    if (loja == null) return;
    setState(() => _loading = true);
    try {
      final rows = await Supabase.instance.client
          .from('restaurant_tables')
          .select('id, numero, capacity, zona, active, notes')
          .eq('restaurant_id', loja)
          .order('numero');
      if (!mounted) return;
      setState(() {
        _mesas = List<Map<String, dynamic>>.from(rows);
        _loading = false;
      });
    } catch (e) {
      debugPrint('[AdminMesas] $e');
      if (!mounted) return;
      setState(() => _loading = false);
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Não consegui carregar as mesas.')));
    }
  }

  Future<void> _editar(Map<String, dynamic> m) async {
    final numero = TextEditingController(text: '${m['numero'] ?? ''}');
    final lugares = TextEditingController(text: '${m['capacity'] ?? ''}');
    final zona = TextEditingController(text: '${m['zona'] ?? ''}');
    var ativa = m['active'] != false;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSt) => AlertDialog(
          title: const Text('Editar mesa'),
          content: Column(mainAxisSize: MainAxisSize.min, children: [
            TextField(
                controller: numero,
                decoration: const InputDecoration(labelText: 'Número')),
            TextField(
                controller: lugares,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: 'Lugares')),
            TextField(
                controller: zona,
                decoration: const InputDecoration(labelText: 'Zona')),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Ativa'),
              value: ativa,
              onChanged: (v) => setSt(() => ativa = v),
            ),
          ]),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Cancelar')),
            FilledButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('Salvar')),
          ],
        ),
      ),
    );
    final novo = {
      'numero': numero.text.trim(),
      'capacity': int.tryParse(lugares.text.trim()) ?? m['capacity'],
      'zona': zona.text.trim().isEmpty ? null : zona.text.trim(),
      'active': ativa,
    };
    if (ok != true || !mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    try {
      final sb = Supabase.instance.client;
      await sb.from('restaurant_tables').update(novo).eq('id', m['id']);
      await sb.rpc('log_admin_action', params: {
        'p_action': 'mesa_editada',
        'p_entity_type': 'restaurant_table',
        'p_entity_id': m['id'],
        'p_details': {
          'restaurant_id': _loja,
          'antes': {
            'numero': m['numero'],
            'capacity': m['capacity'],
            'zona': m['zona'],
            'active': m['active'],
          },
          'depois': novo,
        },
      });
      messenger.showSnackBar(const SnackBar(content: Text('Mesa gravada.')));
      await _load();
    } catch (e) {
      debugPrint('[AdminMesas] editar: $e');
      messenger.showSnackBar(
          const SnackBar(content: Text('Não consegui gravar a mesa.')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: BoraScreenAppBar(
        title: 'Mesas (reservas)',
        actions: [
          IconButton(
              icon: const Icon(Icons.refresh),
              onPressed: _loja == null ? null : _load),
        ],
      ),
      body: Column(children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
          child: AdminEscolherLoja(
            valor: _loja,
            onEscolhida: (v) {
              setState(() => _loja = v);
              _load();
            },
          ),
        ),
        Expanded(
          child: _loja == null
              ? const Center(child: Text('Escolha uma loja.'))
              : _loading
                  ? const Center(child: CircularProgressIndicator())
                  : _mesas.isEmpty
                      ? const Center(
                          child: Text('Esta loja não tem mesas configuradas.'))
                      : ListView.separated(
                          itemCount: _mesas.length,
                          separatorBuilder: (_, __) => const Divider(
                              height: 1, color: AppColors.divider),
                          itemBuilder: (_, i) {
                            final m = _mesas[i];
                            final ativa = m['active'] != false;
                            return ListTile(
                              leading: Icon(Icons.table_restaurant,
                                  color: ativa
                                      ? AppColors.success
                                      : AppColors.textSecondary),
                              title: Text('Mesa ${m['numero'] ?? '—'}'),
                              subtitle: Text(
                                  '${m['capacity'] ?? '?'} lugares'
                                  '${(m['zona'] ?? '').toString().isEmpty ? '' : ' · ${m['zona']}'}'
                                  '${ativa ? '' : ' · inativa'}'),
                              trailing: const Icon(Icons.edit, size: 18),
                              onTap: () => _editar(m),
                            );
                          },
                        ),
        ),
      ]),
    );
  }
}
