// Sessão 5B-α B5 — Admin Inbox de propostas WRITE shadow do agente IA.
// Lista propostas (pending/dispatched/executed/rejected/failed/all), aprovar
// com modal confirmação, rejeitar com motivo, realtime badge.
// Sessão 5B-β2a B5: status='dispatched' + botão Executar para skills com
// EXTERNAL_DISPATCH_REQUIRED (CANCEL_PRE_PURCHASE/CANCEL_DURING_PURCHASE/
// RESERVATION_CANCEL). Aprovar coloca em dispatched (RPC valida); admin
// preme Executar para invocar Edge Fn alvo + admin_finalize_action.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../config/app_colors.dart';
import '../../config/app_spacing.dart';
import '../../widgets/bora/bora_screen_app_bar.dart';

class AdminPendingActionsScreen extends StatefulWidget {
  const AdminPendingActionsScreen({super.key});

  @override
  State<AdminPendingActionsScreen> createState() =>
      _AdminPendingActionsScreenState();
}

class _AdminPendingActionsScreenState
    extends State<AdminPendingActionsScreen> {
  static const _boraGreen = AppColors.primary;
  static const _boraOrange = AppColors.accent;

  final _supabase = Supabase.instance.client;
  String _statusFilter = 'pending';
  List<Map<String, dynamic>> _actions = [];
  int _pendingBadgeCount = 0;
  bool _loading = false;
  String? _error;
  RealtimeChannel? _channel;

  static const _filterOptions = <String, String>{
    'pending': 'Pendentes',
    'dispatched': 'Aguarda dispatch',
    'executed': 'Executadas',
    'rejected': 'Rejeitadas',
    'failed': 'Falhadas',
    'all': 'Todas',
  };

  static const _actionTypeLabels = <String, String>{
    'UPDATE_DELIVERY_INSTRUCTIONS': 'Alterar instruções de entrega',
    'UPDATE_DELIVERY_ADDRESS': 'Alterar endereço de entrega',
    'CANCEL_PRE_PURCHASE': 'Cancelar pedido pré-compra',
    'CANCEL_DURING_PURCHASE': 'Cancelar pedido (entregador envolvido)',
    'RESERVATION_CANCEL': 'Cancelar reserva',
    'PASSWORD_RESET': 'Reset password',
    'ACCOUNT_UPDATE': 'Actualizar dados conta',
  };

  @override
  void initState() {
    super.initState();
    _load();
    _refreshBadge();
    _subscribeRealtime();
  }

  @override
  void dispose() {
    if (_channel != null) {
      _supabase.removeChannel(_channel!);
    }
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final data = await _supabase.rpc('admin_list_pending_actions', params: {
        'p_status': _statusFilter,
        'p_limit': 50,
      });
      final list = (data as List? ?? [])
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList();
      if (!mounted) return;
      setState(() {
        _actions = list;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  Future<void> _refreshBadge() async {
    try {
      final data = await _supabase.rpc('admin_list_pending_actions', params: {
        'p_status': 'pending',
        'p_limit': 100,
      });
      final list = (data as List? ?? []);
      if (!mounted) return;
      setState(() => _pendingBadgeCount = list.length);
    } catch (_) {/* silent */}
  }

  void _subscribeRealtime() {
    _channel = _supabase.channel('admin_pending_actions');
    _channel!.onPostgresChanges(
      event: PostgresChangeEvent.all,
      schema: 'public',
      table: 'support_pending_actions',
      callback: (_) {
        _refreshBadge();
        if (_statusFilter == 'pending' || _statusFilter == 'all') _load();
      },
    ).subscribe();
  }

  Future<void> _approve(Map<String, dynamic> action) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Confirmar aprovação'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
                'Esta acção será EXECUTADA imediatamente após confirmação. Não pode ser desfeita.'),
            const SizedBox(height: 12),
            Text(_actionTypeLabels[action['action_type']] ??
                action['action_type'] as String),
            const SizedBox(height: 8),
            Text(_formatPayload(action['action_payload']),
                style: const TextStyle(
                    fontFamily: 'monospace', fontSize: 12)),
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancelar')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: _boraGreen),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Aprovar e executar',
                style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      // 5B-β2a: pattern unificado — admin_approve_action sempre.
      // Para skills EXTERNAL_DISPATCH_REQUIRED, RPC retorna status=dispatched
      // e a UI mostra botão Executar. Para skills self-contained, retorna
      // status=executed directamente.
      final result = await _supabase.rpc('admin_approve_action',
          params: {'p_action_id': action['id']});
      if (!mounted) return;
      final r = result as Map?;
      final hasError = r != null && r['error'] != null;
      final isDispatch = r != null && r['action'] == 'EXTERNAL_DISPATCH_REQUIRED';
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: hasError
              ? Colors.red
              : (isDispatch ? Colors.amber.shade800 : _boraGreen),
          content: Text(hasError
              ? 'Falhou: ${r['error']}'
              : isDispatch
                  ? 'Validado · aguarda dispatch (${r['target']})'
                  : 'Acção executada com sucesso'),
        ),
      );
      await _load();
      await _refreshBadge();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(backgroundColor: Colors.red, content: Text('Erro: $e')));
    }
  }

  // 5B-β2a — Despacha acção em status='dispatched' para o Edge Fn alvo
  // e finaliza com admin_finalize_action.
  Future<void> _dispatch(Map<String, dynamic> action) async {
    final actionType = action['action_type'] as String? ?? '';
    final dispatchTarget = action['dispatch_target'] as String? ?? '';
    final payload = (action['action_payload'] as Map?) ?? {};
    final actionId = action['id'];

    if (dispatchTarget.isEmpty) {
      await _supabase.rpc('admin_finalize_action', params: {
        'p_action_id': actionId,
        'p_status': 'failed',
        'p_result': {'error': 'NO_DISPATCH_TARGET — corrupted dispatched row'},
        'p_reason': null,
      });
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          backgroundColor: Colors.red,
          content: Text('Falhou: dispatch_target em falta')));
      await _load();
      await _refreshBadge();
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Confirmar execução'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
                'Esta acção é IRREVERSÍVEL. Sistema vai despachar imediatamente.'),
            const SizedBox(height: 12),
            Text(_actionTypeLabels[actionType] ?? actionType,
                style: const TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            Text('Target: $dispatchTarget',
                style: const TextStyle(
                    fontFamily: 'monospace', fontSize: 12)),
            const SizedBox(height: 8),
            Text(_formatPayload(payload),
                style: const TextStyle(
                    fontFamily: 'monospace', fontSize: 12)),
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancelar')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.amber.shade800),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Executar dispatch',
                style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    try {
      Map<String, dynamic>? data;
      String? errorMsg;
      if (dispatchTarget == 'admin-cancel-order') {
        final orderId = payload['order_id'] as String?;
        if (orderId == null || orderId.isEmpty) {
          errorMsg = 'INVALID_ORDER_ID — payload missing order_id';
        } else {
          final reasonInPayload = (payload['reason'] as String?)?.trim();
          final reasonText = (reasonInPayload == null || reasonInPayload.isEmpty)
              ? 'client_request: cancelamento via suporte IA (admin aprovado)'
              : (reasonInPayload.contains(':')
                  ? reasonInPayload
                  : 'client_request: $reasonInPayload');
          final res = await _supabase.functions.invoke('admin-cancel-order',
              body: {
                'order_id': orderId,
                'reason_code': 'client_request',
                'reason': reasonText,
              });
          data = (res.data as Map?)?.cast<String, dynamic>();
        }
      } else if (dispatchTarget == 'admin-cancel-reservation') {
        final reservationId = payload['reservation_id'] as String?;
        if (reservationId == null || reservationId.isEmpty) {
          errorMsg = 'INVALID_RESERVATION_ID — payload missing reservation_id';
        } else {
          final res = await _supabase.functions.invoke(
              'admin-cancel-reservation',
              body: {
                'reservation_id': reservationId,
                'reason': 'cancelamento via suporte IA (admin aprovado)',
              });
          data = (res.data as Map?)?.cast<String, dynamic>();
        }
      } else {
        errorMsg = 'UNKNOWN_DISPATCH_TARGET: $dispatchTarget';
      }

      if (errorMsg != null) {
        await _supabase.rpc('admin_finalize_action', params: {
          'p_action_id': actionId,
          'p_status': 'failed',
          'p_result': {'error': errorMsg},
          'p_reason': null,
        });
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            backgroundColor: Colors.red, content: Text('Falhou: $errorMsg')));
        await _load();
        await _refreshBadge();
        return;
      }

      final ok = data != null && data['success'] == true;
      if (ok) {
        await _supabase.rpc('admin_finalize_action', params: {
          'p_action_id': actionId,
          'p_status': 'executed',
          'p_result': {
            'dispatched_via': dispatchTarget,
            'idempotent': data['idempotent'],
            'refund': data['refund'],
            'previous_status': data['previous_status'],
            'new_status': data['new_status'],
          },
          'p_reason': null,
        });
        if (!mounted) return;
        final refundResult = data['refund']?['result']?.toString() ?? 'n/a';
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            backgroundColor: _boraGreen,
            content: Text('Despachado · refund $refundResult')));
      } else {
        final err = data?['error']?.toString() ?? '$dispatchTarget falhou';
        await _supabase.rpc('admin_finalize_action', params: {
          'p_action_id': actionId,
          'p_status': 'failed',
          'p_result': {'error': err, 'detail': data?.toString()},
          'p_reason': null,
        });
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            backgroundColor: Colors.red, content: Text('Falhou: $err')));
      }
      await _load();
      await _refreshBadge();
    } catch (e) {
      try {
        await _supabase.rpc('admin_finalize_action', params: {
          'p_action_id': actionId,
          'p_status': 'failed',
          'p_result': {'error': e.toString()},
          'p_reason': null,
        });
      } catch (_) {/* ignore secondary error */}
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          backgroundColor: Colors.red, content: Text('Erro: $e')));
      await _load();
      await _refreshBadge();
    }
  }

  Future<void> _reject(Map<String, dynamic> action) async {
    final ctrl = TextEditingController();
    final reason = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Rejeitar proposta'),
        content: TextField(
          controller: ctrl,
          maxLength: 200,
          maxLines: 3,
          decoration: const InputDecoration(
            labelText: 'Motivo (opcional)',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancelar')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: _boraOrange),
            onPressed: () => Navigator.pop(ctx, ctrl.text.trim()),
            child: const Text('Rejeitar',
                style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
    if (reason == null) return;
    try {
      await _supabase.rpc('admin_reject_action', params: {
        'p_action_id': action['id'],
        'p_reason': reason.isEmpty ? null : reason,
      });
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          backgroundColor: _boraOrange,
          content: Text('Proposta rejeitada')));
      await _load();
      await _refreshBadge();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(backgroundColor: Colors.red, content: Text('Erro: $e')));
    }
  }

  String _formatPayload(dynamic payload) {
    if (payload is Map) {
      return payload.entries
          .map((e) => '${e.key}: ${e.value}')
          .join('\n');
    }
    return payload?.toString() ?? '';
  }

  Color _statusColor(String status) {
    switch (status) {
      case 'pending':
        return _boraOrange;
      case 'dispatched':
        return Colors.amber.shade800;
      case 'executed':
        return _boraGreen;
      case 'rejected':
        return Colors.grey;
      case 'failed':
        return Colors.red;
      default:
        return Colors.black45;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: BoraScreenAppBar(
        title: 'Propostas IA',
        actions: [
          if (_pendingBadgeCount > 0)
            Center(
              child: Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: _boraOrange,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  '$_pendingBadgeCount',
                  style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 13),
                ),
              ),
            ),
          PopupMenuButton<String>(
            icon: const Icon(Icons.filter_list),
            tooltip: 'Filtrar status',
            initialValue: _statusFilter,
            onSelected: (v) {
              setState(() => _statusFilter = v);
              _load();
            },
            itemBuilder: (_) => _filterOptions.entries
                .map((e) => PopupMenuItem(value: e.key, child: Text(e.value)))
                .toList(),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () async {
          await _load();
          await _refreshBadge();
        },
        child: _buildBody(),
      ),
    );
  }

  Widget _buildBody() {
    if (_loading && _actions.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null) {
      return ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            color: const Color(0xFFFFEBEE),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Erro ao carregar propostas',
                      style: TextStyle(
                          color: Color(0xFFC62828),
                          fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),
                  Text(_error!,
                      style: const TextStyle(color: Color(0xFFC62828))),
                  const SizedBox(height: 12),
                  ElevatedButton(
                      onPressed: _load, child: const Text('Tentar de novo')),
                ],
              ),
            ),
          ),
        ],
      );
    }
    if (_actions.isEmpty) {
      return ListView(
        children: [
          const SizedBox(height: 80),
          Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Text(
                _statusFilter == 'pending'
                    ? 'Nenhuma proposta pendente.'
                    : 'Sem registos para "${_filterOptions[_statusFilter]}".',
                textAlign: TextAlign.center,
                style:
                    const TextStyle(fontSize: 16, color: Colors.black54),
              ),
            ),
          ),
        ],
      );
    }
    return ListView.builder(
      padding: const EdgeInsets.all(12),
      itemCount: _actions.length,
      itemBuilder: (_, i) => _buildCard(_actions[i]),
    );
  }

  Widget _buildCard(Map<String, dynamic> a) {
    final status = a['status'] as String? ?? 'unknown';
    final actionType = a['action_type'] as String? ?? '';
    final isPending = status == 'pending';
    final isDispatched = status == 'dispatched';
    final dispatchTarget = a['dispatch_target'] as String?;
    final result = a['execution_result'];
    final rejectionReason = a['rejection_reason'] as String?;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(Radii.lg),
        boxShadow: AppColors.shadowCard,
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    _actionTypeLabels[actionType] ?? actionType,
                    style: const TextStyle(
                        fontWeight: FontWeight.bold, fontSize: 16),
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: _statusColor(status).withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(status,
                      style: TextStyle(
                          color: _statusColor(status),
                          fontWeight: FontWeight.bold,
                          fontSize: 12)),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text('Cliente: ${a['user_email'] ?? '(sem email)'}',
                style: const TextStyle(color: Colors.black54, fontSize: 13)),
            const SizedBox(height: 8),
            if (a['user_message'] != null) ...[
              Container(
                padding: const EdgeInsets.all(8),
                color: const Color(0xFFF5F5F5),
                child: Text('"${a['user_message']}"',
                    style: const TextStyle(
                        fontStyle: FontStyle.italic, fontSize: 13)),
              ),
              const SizedBox(height: 8),
            ],
            const Text('Robô propõe:',
                style: TextStyle(
                    fontWeight: FontWeight.bold, fontSize: 13)),
            const SizedBox(height: 4),
            Container(
              padding: const EdgeInsets.all(8),
              color: const Color(0xFFE8F5E9),
              child: Text(_formatPayload(a['action_payload']),
                  style: const TextStyle(
                      fontFamily: 'monospace', fontSize: 12)),
            ),
            if (a['agent_reasoning'] != null) ...[
              const SizedBox(height: 8),
              Text('Razão: ${a['agent_reasoning']}',
                  style: const TextStyle(
                      fontSize: 12, color: Colors.black87)),
            ],
            const SizedBox(height: 8),
            Text('Proposto em: ${_formatTs(a['proposed_at'])}',
                style: const TextStyle(
                    fontSize: 11, color: Colors.black45)),
            if (!isPending) ...[
              if (a['reviewed_at'] != null)
                Text('Revisto em: ${_formatTs(a['reviewed_at'])}',
                    style: const TextStyle(
                        fontSize: 11, color: Colors.black45)),
              if (isDispatched && a['dispatched_at'] != null)
                Text('Dispatch desde: ${_formatTs(a['dispatched_at'])}',
                    style: TextStyle(
                        fontSize: 11, color: Colors.amber.shade900)),
              if (isDispatched && dispatchTarget != null) ...[
                const SizedBox(height: 6),
                Container(
                  padding: const EdgeInsets.all(8),
                  color: const Color(0xFFFFF8E1),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Target: $dispatchTarget',
                          style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                              color: Colors.amber.shade900)),
                      if (result is Map) ...[
                        const SizedBox(height: 4),
                        Text(_formatPayload(result),
                            style: const TextStyle(
                                fontFamily: 'monospace', fontSize: 11)),
                      ],
                    ],
                  ),
                ),
              ],
              if (!isDispatched && result != null) ...[
                const SizedBox(height: 6),
                Container(
                  padding: const EdgeInsets.all(8),
                  color: status == 'failed'
                      ? const Color(0xFFFFEBEE)
                      : const Color(0xFFF1F8E9),
                  child: Text('Resultado: ${result.toString()}',
                      style: TextStyle(
                          fontSize: 11,
                          color: status == 'failed'
                              ? Colors.red[900]
                              : Colors.black87)),
                ),
              ],
              if (rejectionReason != null && rejectionReason.isNotEmpty) ...[
                const SizedBox(height: 6),
                Text('Motivo rejeição: $rejectionReason',
                    style: const TextStyle(
                        fontSize: 12, fontStyle: FontStyle.italic)),
              ],
            ],
            if (isPending) ...[
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                          backgroundColor: _boraGreen,
                          foregroundColor: Colors.white),
                      icon: const Icon(Icons.check),
                      label: const Text('Aprovar'),
                      onPressed: () => _approve(a),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                          backgroundColor: _boraOrange,
                          foregroundColor: Colors.white),
                      icon: const Icon(Icons.close),
                      label: const Text('Rejeitar'),
                      onPressed: () => _reject(a),
                    ),
                  ),
                ],
              ),
            ],
            if (isDispatched) ...[
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.amber.shade800,
                      foregroundColor: Colors.white),
                  icon: const Icon(Icons.rocket_launch),
                  label: const Text('Executar dispatch'),
                  onPressed: () => _dispatch(a),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  String _formatTs(dynamic ts) {
    if (ts == null) return '-';
    try {
      final dt = DateTime.parse(ts as String).toLocal();
      return '${dt.year}-${_pad(dt.month)}-${_pad(dt.day)} '
          '${_pad(dt.hour)}:${_pad(dt.minute)}';
    } catch (_) {
      return ts.toString();
    }
  }

  String _pad(int n) => n.toString().padLeft(2, '0');
}
