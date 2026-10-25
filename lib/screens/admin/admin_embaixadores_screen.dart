import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../config/app_colors.dart';
import '../../widgets/bora/bora_screen_app_bar.dart';

/// Embaixadores (IPG): códigos de quem traz clientes e quanto pagar por semana.
///
/// Regra autorizada pelo Danilo a 25/10/2026: 2 € por cliente que use o código
/// e faça o 1.º pedido pago e entregue, teto de 20 € por semana. A conta vem
/// pronta do banco (`admin_embaixador_resumo`); este ecrã só mostra e edita a
/// ficha do embaixador. O pagamento continua a ser feito à mão.
class AdminEmbaixadoresScreen extends StatefulWidget {
  const AdminEmbaixadoresScreen({super.key});
  @override
  State<AdminEmbaixadoresScreen> createState() => _S();
}

class _S extends State<AdminEmbaixadoresScreen> {
  List<Map<String, dynamic>> _codigos = const [];
  List<Map<String, dynamic>> _semanas = const [];
  List<Map<String, dynamic>> _clientes = const [];
  bool _loading = true;
  String? _error;

  @override
  void initState() { super.initState(); _load(); }

  static List<Map<String, dynamic>> _lista(dynamic v) =>
      ((v as List?) ?? []).map((e) => (e as Map).cast<String, dynamic>()).toList();

  Future<void> _load() async {
    setState(() { _loading = true; _error = null; });
    try {
      final res = await Supabase.instance.client
          .rpc('admin_embaixador_resumo', params: {'p_semanas': 12});
      final m = ((res as Map?) ?? {}).cast<String, dynamic>();
      if (mounted) {
        setState(() {
          _codigos = _lista(m['codigos']);
          _semanas = _lista(m['semanas']);
          _clientes = _lista(m['clientes']);
        });
      }
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  static String _euros(dynamic cents) =>
      '${((cents as num? ?? 0) / 100).toStringAsFixed(2).replaceAll('.', ',')} €';

  static String _data(dynamic iso) {
    final d = DateTime.tryParse('${iso ?? ''}')?.toLocal();
    if (d == null) return '—';
    String dois(int n) => n.toString().padLeft(2, '0');
    return '${dois(d.day)}/${dois(d.month)}';
  }

  Future<void> _guardar(Map<String, dynamic> params) async {
    try {
      final res = await Supabase.instance.client.rpc('admin_embaixador_guardar', params: {
        'p_code': null, 'p_nome': null, 'p_telefone': null,
        'p_email': null, 'p_notas': null, 'p_ativo': null,
        ...params,
      });
      final r = ((res as Map?) ?? {}).cast<String, dynamic>();
      if (r['ok'] != true && mounted) {
        final motivo = r['motivo'] == 'email_sem_conta'
            ? 'Nenhuma conta com esse email.'
            : 'Não foi possível salvar (${r['motivo']}).';
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(motivo)));
      }
      if (mounted) await _load();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Erro: $e')));
      }
    }
  }

  Future<void> _editar(Map<String, dynamic> c) async {
    final nome = TextEditingController(text: c['nome'] ?? '');
    final tel = TextEditingController(text: c['telefone'] ?? '');
    final email = TextEditingController(text: c['email'] ?? '');
    final notas = TextEditingController(text: c['notas'] ?? '');
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Embaixador do código ${c['code']}'),
        content: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            TextField(controller: nome, decoration: const InputDecoration(labelText: 'Nome')),
            TextField(controller: tel, keyboardType: TextInputType.phone,
                decoration: const InputDecoration(labelText: 'Telefone')),
            TextField(controller: email, keyboardType: TextInputType.emailAddress,
                decoration: const InputDecoration(
                    labelText: 'Email da conta no app (opcional)',
                    helperText: 'Os pedidos da própria conta não contam.')),
            TextField(controller: notas, decoration: const InputDecoration(labelText: 'Notas')),
          ]),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Salvar')),
        ],
      ),
    );
    if (ok != true) return;
    await _guardar({
      'p_code': c['code'],
      'p_nome': nome.text,
      'p_telefone': tel.text,
      'p_email': email.text,
      'p_notas': notas.text,
    });
  }

  Widget _titulo(String t) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 20, 16, 6),
        child: Text(t, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
      );

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: const BoraScreenAppBar(title: 'Embaixadores'),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(child: Text(_error!, style: const TextStyle(color: AppColors.error)))
              : RefreshIndicator(
                  onRefresh: _load,
                  child: ListView(
                    padding: const EdgeInsets.only(bottom: 24),
                    children: [
                      const Padding(
                        padding: EdgeInsets.fromLTRB(16, 16, 16, 0),
                        child: Text(
                          'Regra autorizada em 25/10/2026: 2 € por cliente que usar o código '
                          'e fizer o 1.º pedido pago e entregue. Teto de 20 € por semana por '
                          'embaixador. Não contam o próprio embaixador nem contas repetidas '
                          '(mesmo telefone ou endereço). O pagamento é feito à mão.',
                          style: TextStyle(color: AppColors.textSecondary),
                        ),
                      ),
                      _titulo('Códigos'),
                      for (final c in _codigos)
                        SwitchListTile(
                          value: c['ativo'] == true,
                          onChanged: (v) => _guardar({'p_code': c['code'], 'p_ativo': v}),
                          title: Text('${c['code']} · ${c['nome'] ?? 'sem embaixador'}',
                              style: const TextStyle(fontWeight: FontWeight.bold)),
                          subtitle: Text('${c['usos']}/${c['max_usos'] ?? '∞'} usos · '
                              '${_euros(c['valor_por_cliente_cents'])} por cliente · '
                              'teto ${_euros(c['teto_semana_cents'])}/semana'
                              '${c['telefone'] != null ? ' · ${c['telefone']}' : ''}'),
                          secondary: IconButton(
                            icon: const Icon(Icons.edit),
                            tooltip: 'Editar embaixador',
                            onPressed: () => _editar(c),
                          ),
                        ),
                      _titulo('A pagar por semana'),
                      if (_semanas.isEmpty)
                        const ListTile(title: Text('Ainda nenhum cliente com pedido entregue.')),
                      for (final s in _semanas)
                        ListTile(
                          title: Text('Semana de ${_data(s['semana'])} · ${s['code']}'),
                          subtitle: Text('${s['elegiveis']} cliente(s) contam · '
                              '${s['excluidos']} não contam'),
                          trailing: Text(_euros(s['a_pagar_cents']),
                              style: const TextStyle(
                                  fontWeight: FontWeight.bold, color: AppColors.primary)),
                        ),
                      _titulo('Clientes que usaram os códigos'),
                      if (_clientes.isEmpty)
                        const ListTile(title: Text('Ninguém usou um código de embaixador ainda.')),
                      for (final c in _clientes)
                        ListTile(
                          dense: true,
                          leading: Icon(
                            c['motivo_exclusao'] == null ? Icons.check_circle : Icons.remove_circle,
                            color: c['motivo_exclusao'] == null
                                ? AppColors.primary
                                : AppColors.textSecondary,
                          ),
                          title: Text('${c['cliente'] ?? 'Cliente'} · ${c['code']}'),
                          subtitle: Text('Usou ${_data(c['usou_em'])} · '
                              '${c['motivo_exclusao'] ?? 'conta — 1.º pedido em ${_data(c['entregue_em'])}'}'),
                        ),
                    ],
                  ),
                ),
    );
  }
}
