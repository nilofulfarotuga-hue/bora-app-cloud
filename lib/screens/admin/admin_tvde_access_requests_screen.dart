import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../config/app_colors.dart';
import '../../config/app_spacing.dart';
import '../../widgets/bora/bora_screen_app_bar.dart';
import '_admin_rpc_errors.dart';

/// Bora Motorista (TVDE) — Pedidos de acesso à categoria escondida.
///
/// Prioridade do Danilo: ver o PERFIL COMPLETO do cliente (foto, nome,
/// telefone, email, data de cadastro e histórico de pedidos/corridas) ANTES
/// de decidir, para saber QUEM é antes de aprovar.
///
/// Lê `admin_tvde_access_requests_list()` (RPC admin read-only, aditivo) e
/// escreve via `admin_set_tvde_access(client, acao)` (já existia — Fase 1).
/// Idioma: PT-BR (termos técnicos explicados entre parênteses).
class AdminTvdeAccessRequestsScreen extends StatefulWidget {
  const AdminTvdeAccessRequestsScreen({super.key});

  @override
  State<AdminTvdeAccessRequestsScreen> createState() =>
      _AdminTvdeAccessRequestsScreenState();
}

class _AdminTvdeAccessRequestsScreenState
    extends State<AdminTvdeAccessRequestsScreen> {
  late Future<List<Map<String, dynamic>>> _future;
  String _filter = 'pendente'; // pendente | aprovado | recusado | todos
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<List<Map<String, dynamic>>> _load() async {
    final res =
        await Supabase.instance.client.rpc('admin_tvde_access_requests_list');
    final list = (res as List?) ?? const [];
    return list
        .whereType<Map>()
        .map((e) => Map<String, dynamic>.from(e))
        .toList();
  }

  Future<void> _refresh() async {
    setState(() => _future = _load());
    await _future;
  }

  List<Map<String, dynamic>> _applyFilter(List<Map<String, dynamic>> all) {
    if (_filter == 'todos') return all;
    return all.where((r) => (r['status'] as String?) == _filter).toList();
  }

  Future<void> _act(Map<String, dynamic> req, String action) async {
    // action: aprovar | recusar | revogar
    final name = (req['name'] as String?)?.trim();
    final label = (name != null && name.isNotEmpty)
        ? name
        : (req['email'] as String? ?? 'cliente');
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(_actionTitle(action)),
        content: Text(_actionDescription(action, label)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor:
                  action == 'aprovar' ? AppColors.primary : AppColors.error,
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(_actionCta(action)),
          ),
        ],
      ),
    );
    if (confirm != true) return;

    setState(() => _busy = true);
    try {
      await Supabase.instance.client.rpc('admin_set_tvde_access', params: {
        'p_client_id': req['client_id'],
        'p_action': action,
      });
      if (!mounted) return;
      _toast('Feito: ${_actionCta(action)} — $label', AppColors.primary);
      await _refresh();
    } catch (e) {
      if (!mounted) return;
      _toast(humanizeAdminRpcError(e), AppColors.error);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  String _actionTitle(String a) => switch (a) {
        'aprovar' => 'Aprovar acesso',
        'recusar' => 'Recusar pedido',
        _ => 'Revogar acesso',
      };

  String _actionDescription(String a, String label) => switch (a) {
        'aprovar' =>
          'Vai LIBERAR a categoria Bora Motorista para "$label" (o cliente passa a ver e pedir corridas).',
        'recusar' =>
          'Vai RECUSAR o pedido de "$label" (a categoria continua escondida para ele).',
        _ =>
          'Vai REVOGAR o acesso de "$label" (tira a categoria — o cliente deixa de ver e pedir corridas).',
      };

  String _actionCta(String a) => switch (a) {
        'aprovar' => 'Aprovar',
        'recusar' => 'Recusar',
        _ => 'Revogar',
      };

  void _toast(String msg, Color color) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), backgroundColor: color),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: BoraScreenAppBar(
        title: 'Acesso — Bora Motorista',
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Atualizar',
            onPressed: _refresh,
          ),
        ],
      ),
      body: Column(
        children: [
          _FilterBar(
            value: _filter,
            onChanged: (v) => setState(() => _filter = v),
          ),
          if (_busy) const LinearProgressIndicator(minHeight: 2),
          Expanded(
            child: RefreshIndicator(
              onRefresh: _refresh,
              child: FutureBuilder<List<Map<String, dynamic>>>(
                future: _future,
                builder: (context, snap) {
                  if (snap.connectionState == ConnectionState.waiting) {
                    return const Center(child: CircularProgressIndicator());
                  }
                  if (snap.hasError) {
                    return _ErrorState(
                        message: '${snap.error}', onRetry: _refresh);
                  }
                  final rows = _applyFilter(snap.data ?? const []);
                  if (rows.isEmpty) {
                    return ListView(
                      children: const [
                        SizedBox(height: 120),
                        Center(
                          child: Text('Nenhum pedido nesta lista.',
                              style: TextStyle(color: AppColors.textSecondary)),
                        ),
                      ],
                    );
                  }
                  return ListView.builder(
                    padding: const EdgeInsets.all(12),
                    itemCount: rows.length,
                    itemBuilder: (_, i) => _RequestCard(
                      data: rows[i],
                      busy: _busy,
                      onAction: _act,
                    ),
                  );
                },
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _FilterBar extends StatelessWidget {
  const _FilterBar({required this.value, required this.onChanged});
  final String value;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    const opts = {
      'pendente': 'Pendentes',
      'aprovado': 'Aprovados',
      'recusado': 'Recusados',
      'todos': 'Todos',
    };
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Row(
        children: opts.entries.map((e) {
          final selected = e.key == value;
          return Padding(
            padding: const EdgeInsets.only(right: 8),
            child: ChoiceChip(
              label: Text(e.value),
              selected: selected,
              onSelected: (_) => onChanged(e.key),
              selectedColor: AppColors.primary.withValues(alpha: 0.15),
            ),
          );
        }).toList(),
      ),
    );
  }
}

class _RequestCard extends StatelessWidget {
  const _RequestCard({
    required this.data,
    required this.busy,
    required this.onAction,
  });

  final Map<String, dynamic> data;
  final bool busy;
  final Future<void> Function(Map<String, dynamic>, String) onAction;

  @override
  Widget build(BuildContext context) {
    final status = (data['status'] as String?) ?? 'pendente';
    final tvdeAccess = data['tvde_access'] == true;
    final name = (data['name'] as String?)?.trim();
    final email = (data['email'] as String?) ?? '—';
    final phone = (data['phone'] as String?)?.trim();
    final photo = (data['photo_url'] as String?)?.trim();
    final orders = (data['orders_count'] as num?)?.toInt() ?? 0;
    final rides = (data['rides_count'] as num?)?.toInt() ?? 0;
    final displayName =
        (name != null && name.isNotEmpty) ? name : email;

    return Card(
      elevation: 2,
      margin: const EdgeInsets.only(bottom: 12),
      shape:
          RoundedRectangleBorder(borderRadius: BorderRadius.circular(Radii.lg)),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Perfil completo do cliente ──
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _Avatar(photoUrl: photo, fallback: displayName),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(displayName,
                          style: const TextStyle(
                              fontWeight: FontWeight.w700, fontSize: 16)),
                      const SizedBox(height: 2),
                      _line(Icons.email_outlined, email),
                      if (phone != null && phone.isNotEmpty)
                        _line(Icons.phone_outlined, phone),
                      _line(Icons.calendar_today_outlined,
                          'Cadastro: ${_fmtDate(data['created_at'])}'),
                    ],
                  ),
                ),
                _StatusChip(status: status),
              ],
            ),
            const SizedBox(height: 10),
            // ── Histórico (para saber se é cliente real) ──
            Wrap(
              spacing: 8,
              runSpacing: 6,
              children: [
                _Pill(
                    icon: Icons.receipt_long,
                    label: '$orders pedido(s) na app'),
                _Pill(
                    icon: Icons.local_taxi,
                    label: '$rides corrida(s) TVDE'),
                if (tvdeAccess)
                  const _Pill(
                      icon: Icons.check_circle,
                      label: 'Acesso ativo',
                      color: AppColors.primary),
              ],
            ),
            const SizedBox(height: 12),
            // ── Ações conforme o estado ──
            _actions(context, status, tvdeAccess),
          ],
        ),
      ),
    );
  }

  Widget _actions(BuildContext context, String status, bool tvdeAccess) {
    final children = <Widget>[];
    final canApprove = status == 'pendente' || status == 'recusado';
    final canRefuse = status == 'pendente';
    final canRevoke = tvdeAccess || status == 'aprovado';

    if (canApprove) {
      children.add(FilledButton.icon(
        style: FilledButton.styleFrom(backgroundColor: AppColors.primary),
        onPressed: busy ? null : () => onAction(data, 'aprovar'),
        icon: const Icon(Icons.check, size: 18),
        label: Text(status == 'recusado' ? 'Aprovar mesmo assim' : 'Aprovar'),
      ));
    }
    if (canRefuse) {
      children.add(OutlinedButton.icon(
        style: OutlinedButton.styleFrom(foregroundColor: AppColors.error),
        onPressed: busy ? null : () => onAction(data, 'recusar'),
        icon: const Icon(Icons.close, size: 18),
        label: const Text('Recusar'),
      ));
    }
    if (canRevoke) {
      children.add(OutlinedButton.icon(
        style: OutlinedButton.styleFrom(foregroundColor: AppColors.error),
        onPressed: busy ? null : () => onAction(data, 'revogar'),
        icon: const Icon(Icons.block, size: 18),
        label: const Text('Revogar acesso'),
      ));
    }
    if (children.isEmpty) {
      return const Text('Sem ações disponíveis para este estado.',
          style: TextStyle(color: AppColors.textSubtle, fontSize: 12));
    }
    return Wrap(spacing: 8, runSpacing: 8, children: children);
  }

  static Widget _line(IconData icon, String text) {
    return Padding(
      padding: const EdgeInsets.only(top: 2),
      child: Row(
        children: [
          Icon(icon, size: 13, color: AppColors.textSubtle),
          const SizedBox(width: 4),
          Expanded(
            child: Text(text,
                style: const TextStyle(
                    fontSize: 12.5, color: AppColors.textSecondary)),
          ),
        ],
      ),
    );
  }
}

class _Avatar extends StatelessWidget {
  const _Avatar({required this.photoUrl, required this.fallback});
  final String? photoUrl;
  final String fallback;

  @override
  Widget build(BuildContext context) {
    final has = photoUrl != null && photoUrl!.trim().isNotEmpty;
    final initial =
        fallback.trim().isNotEmpty ? fallback.trim()[0].toUpperCase() : '?';
    return CircleAvatar(
      radius: 26,
      backgroundColor: AppColors.primary.withValues(alpha: 0.12),
      backgroundImage: has ? NetworkImage(photoUrl!) : null,
      child: has
          ? null
          : Text(initial,
              style: const TextStyle(
                  color: AppColors.primary, fontWeight: FontWeight.bold)),
    );
  }
}

class _StatusChip extends StatelessWidget {
  const _StatusChip({required this.status});
  final String status;

  @override
  Widget build(BuildContext context) {
    final (label, color) = switch (status) {
      'aprovado' => ('Aprovado', AppColors.primary),
      'recusado' => ('Recusado', AppColors.error),
      _ => ('Pendente', AppColors.warning),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(label,
          style: TextStyle(
              color: color, fontSize: 11, fontWeight: FontWeight.w600)),
    );
  }
}

class _Pill extends StatelessWidget {
  const _Pill({required this.icon, required this.label, this.color});
  final IconData icon;
  final String label;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final c = color ?? AppColors.textSecondary;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: c.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: c),
          const SizedBox(width: 5),
          Text(label, style: TextStyle(fontSize: 12, color: c)),
        ],
      ),
    );
  }
}

class _ErrorState extends StatelessWidget {
  const _ErrorState({required this.message, required this.onRetry});
  final String message;
  final Future<void> Function() onRetry;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        const SizedBox(height: 80),
        const Icon(Icons.error_outline, size: 48, color: AppColors.error),
        const SizedBox(height: 12),
        Text('Erro ao carregar:\n$message', textAlign: TextAlign.center),
        const SizedBox(height: 16),
        Center(
          child: FilledButton.icon(
            onPressed: onRetry,
            icon: const Icon(Icons.refresh),
            label: const Text('Tentar de novo'),
          ),
        ),
      ],
    );
  }
}

String _fmtDate(dynamic iso) {
  if (iso == null) return '—';
  final d = DateTime.tryParse(iso.toString());
  if (d == null) return iso.toString();
  final l = d.toLocal();
  String two(int n) => n.toString().padLeft(2, '0');
  return '${two(l.day)}/${two(l.month)}/${l.year}';
}
