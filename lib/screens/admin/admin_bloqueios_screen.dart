// Utilizadores bloqueados (ronda 04/10/2026, agente admin-geral).
// A Apple exige que quem é bloqueado numa app com conversas possa ser revisto
// pela plataforma. A tabela `blocked_users` existia sem ecrã: aqui o Danilo vê
// quem bloqueou quem (e porquê) e pode desbloquear, com confirmação e registo
// no histórico de ações (admin_audit_log).

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../config/app_colors.dart';
import '../../utils/hora_lisboa.dart';
import '../../widgets/admin/admin_csv_button.dart';
import '../../widgets/bora/bora_screen_app_bar.dart';

class AdminBloqueiosScreen extends StatefulWidget {
  const AdminBloqueiosScreen({super.key});

  @override
  State<AdminBloqueiosScreen> createState() => _AdminBloqueiosScreenState();
}

class _AdminBloqueiosScreenState extends State<AdminBloqueiosScreen> {
  List<Map<String, dynamic>> _rows = const [];
  bool _loading = true;
  String? _error;
  final Set<String> _aDesbloquear = {};

  static const _papeis = {
    'client': 'Cliente',
    'driver': 'Entregador',
    'partner': 'Parceiro',
  };

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
          .rpc('admin_blocked_users_list', params: {'p_limit': 500});
      if (!mounted) return;
      setState(() {
        _rows = ((res as List?) ?? const [])
            .map((e) => Map<String, dynamic>.from(e as Map))
            .toList();
        _loading = false;
      });
    } catch (e) {
      debugPrint('[AdminBloqueios] $e');
      if (!mounted) return;
      setState(() {
        _error = 'Não consegui carregar os bloqueios.';
        _loading = false;
      });
    }
  }

  Future<void> _desbloquear(Map<String, dynamic> r) async {
    final id = r['id']?.toString();
    if (id == null || _aDesbloquear.contains(id)) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Desbloquear?'),
        content: Text(
            '${r['bloqueador_nome'] ?? 'Esta pessoa'} voltará a poder receber/ver '
            '${r['bloqueado_nome'] ?? 'a outra pessoa'}.\n\n'
            'O bloqueio foi feito pela própria pessoa — só desbloqueie com motivo '
            '(ex.: pedido dela ou erro).'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancelar')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Desbloquear')),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    setState(() => _aDesbloquear.add(id));
    final messenger = ScaffoldMessenger.of(context);
    try {
      final sb = Supabase.instance.client;
      await sb.from('blocked_users').delete().eq('id', id);
      await sb.rpc('log_admin_action', params: {
        'p_action': 'desbloquear_utilizador',
        'p_entity_type': 'blocked_user',
        'p_entity_id': id,
        'p_details': {
          'bloqueador': r['bloqueador_email'] ?? r['blocker_id'],
          'bloqueado': r['bloqueado_nome'] ?? r['blocked_ref'],
          'motivo_original': r['motivo'],
        },
      });
      messenger.showSnackBar(const SnackBar(content: Text('Desbloqueado.')));
      await _load();
    } catch (e) {
      debugPrint('[AdminBloqueios] desbloquear: $e');
      messenger.showSnackBar(
          const SnackBar(content: Text('Não consegui desbloquear.')));
    } finally {
      if (mounted) setState(() => _aDesbloquear.remove(id));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: BoraScreenAppBar(
        title: 'Utilizadores bloqueados',
        actions: [
          AdminCsvButton(
            nome: 'bloqueios',
            colunas: const [
              ('created_at', 'quando (Lisboa)'),
              ('bloqueador_nome', 'quem bloqueou'),
              ('bloqueador_email', 'email'),
              ('bloqueador_papel', 'papel'),
              ('bloqueado_nome', 'bloqueado'),
              ('bloqueado_papel', 'papel do bloqueado'),
              ('motivo', 'motivo'),
            ],
            linhas: () => _rows,
          ),
          IconButton(icon: const Icon(Icons.refresh), onPressed: _load),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(child: Text(_error!))
              : _rows.isEmpty
                  ? const Center(
                      child: Padding(
                      padding: EdgeInsets.all(24),
                      child: Text('Ninguém bloqueou ninguém até agora.',
                          textAlign: TextAlign.center),
                    ))
                  : RefreshIndicator(
                      onRefresh: _load,
                      child: ListView.separated(
                        padding: const EdgeInsets.all(12),
                        itemCount: _rows.length,
                        separatorBuilder: (_, __) =>
                            const Divider(height: 1, color: AppColors.divider),
                        itemBuilder: (_, i) {
                          final r = _rows[i];
                          final id = r['id']?.toString() ?? '';
                          final papel1 =
                              _papeis[r['bloqueador_papel']] ?? '—';
                          final papel2 = _papeis[r['bloqueado_papel']] ?? '—';
                          return ListTile(
                            leading: const Icon(Icons.block,
                                color: AppColors.error),
                            title: Text(
                                '${r['bloqueador_nome'] ?? '—'} ($papel1) bloqueou '
                                '${r['bloqueado_nome'] ?? r['blocked_label'] ?? '—'} ($papel2)'),
                            subtitle: Text(
                                '${dataHoraLisboa(r['created_at'])}'
                                '${(r['motivo'] ?? '').toString().isEmpty ? '' : ' · ${r['motivo']}'}'),
                            trailing: _aDesbloquear.contains(id)
                                ? const SizedBox(
                                    width: 20,
                                    height: 20,
                                    child: CircularProgressIndicator(
                                        strokeWidth: 2))
                                : TextButton(
                                    onPressed: () => _desbloquear(r),
                                    child: const Text('Desbloquear')),
                          );
                        },
                      ),
                    ),
    );
  }
}
