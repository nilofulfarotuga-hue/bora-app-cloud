import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../config/app_colors.dart';
import '_admin_rpc_errors.dart';
import 'admin_driver_detail_screen.dart';

class AdminDriversScreen extends StatefulWidget {
  const AdminDriversScreen({super.key});

  @override
  State<AdminDriversScreen> createState() => _AdminDriversScreenState();
}

class _AdminDriversScreenState extends State<AdminDriversScreen> {
  List<Map<String, dynamic>> _drivers = [];
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
      final data = await Supabase.instance.client
          .from('drivers')
          .select('id, name, phone, vehicle_type, is_online, approval_status')
          .order('name');
      if (mounted) {
        setState(() {
          _drivers = List<Map<String, dynamic>>.from(data);
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString();
          _loading = false;
        });
      }
    }
  }

  /// Approve via the SECURITY DEFINER RPC. From this screen we keep it
  /// simple: no force path here (use the dedicated Approval screen for
  /// drivers with missing docs). Server still enforces docs validation;
  /// if missing, surface the message verbatim.
  Future<void> _approveDriver(String driverId) async {
    try {
      await Supabase.instance.client.rpc(
        'admin_approve_driver',
        params: {
          'p_driver_id': driverId,
          'p_force': false,
          'p_justification': null,
        },
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Estafeta aprovado.'),
        backgroundColor: AppColors.primary,
      ));
      await _load();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(humanizeAdminRpcError(e)),
        backgroundColor: Colors.red,
        duration: const Duration(seconds: 5),
      ));
    }
  }

  /// Reject via the SECURITY DEFINER RPC. Always asks for a reason
  /// (server requires >= 3 chars).
  Future<void> _rejectDriver(String driverId) async {
    final controller = TextEditingController();
    final reason = await showDialog<String>(
      context: context,
      builder: (ctx) => StatefulBuilder(builder: (ctx, setLocal) {
        final ok = controller.text.trim().length >= 3;
        return AlertDialog(
          title: const Text('Rejeitar candidatura'),
          content: TextField(
            controller: controller,
            onChanged: (_) => setLocal(() {}),
            maxLines: 3,
            decoration: const InputDecoration(
              labelText: 'Motivo (mín. 3 caracteres)',
              border: OutlineInputBorder(),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, null),
              child: const Text('Cancelar'),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
              onPressed: ok
                  ? () => Navigator.pop(ctx, controller.text.trim())
                  : null,
              child: const Text('Rejeitar'),
            ),
          ],
        );
      }),
    );
    if (reason == null) return;

    try {
      await Supabase.instance.client.rpc(
        'admin_reject_driver',
        params: {'p_driver_id': driverId, 'p_reason': reason},
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Candidatura rejeitada.'),
        backgroundColor: Colors.red,
      ));
      await _load();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(humanizeAdminRpcError(e)),
        backgroundColor: Colors.red,
        duration: const Duration(seconds: 5),
      ));
    }
  }

  /// Pendentes só aparecem nesta lista durante a transição da Fase 2B; a
  /// gestão de candidaturas vive em `admin_driver_approval_screen`. Aprovar
  /// directamente daqui é um fallback para casos legacy.
  void _approvePendingFromList(String driverId) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Aprovar candidatura?'),
        content: const Text('Confirma a aprovação directa (sem documentos forçados).'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
          ElevatedButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Aprovar')),
        ],
      ),
    );
    if (ok == true) {
      await _approveDriver(driverId);
    }
  }

  void _openDetail(Map<String, dynamic> driver) {
    final id = driver['id'] as String?;
    if (id == null) return;
    final status = (driver['approval_status'] as String?) ?? 'pending';
    if (status == 'pending') {
      // Drivers pendentes não passam pelo AdminDriverDetailScreen (tem como
      // pré-condição driver aprovado). Para esta lista global, oferece o
      // fluxo rápido de aprovar/rejeitar via diálogo.
      _approvePendingFromList(id);
      return;
    }
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => AdminDriverDetailScreen(driverId: id),
      ),
    );
  }

  Color _statusColor(String status) {
    switch (status) {
      case 'approved':
        return AppColors.primary;
      case 'pending':
        return Colors.orange;
      case 'rejected':
        return Colors.red;
      default:
        return Colors.grey;
    }
  }

  String _statusLabel(String status) {
    const labels = {
      'approved': 'Aprovado',
      'pending': 'Pendente',
      'rejected': 'Rejeitado'
    };
    return labels[status] ?? status;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Gestão de Estafetas'),
        actions: [
          IconButton(icon: const Icon(Icons.refresh), onPressed: _load)
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(child: Text('Erro: $_error'))
              : RefreshIndicator(
                  onRefresh: _load,
                  child: ListView.separated(
                    padding: const EdgeInsets.all(12),
                    itemCount: _drivers.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 8),
                    itemBuilder: (_, i) {
                      final d = _drivers[i];
                      final status =
                          d['approval_status'] as String? ?? 'pending';
                      final isOnline = d['is_online'] as bool? ?? false;
                      return Card(
                        child: ListTile(
                          onTap: () => _openDetail(d),
                          leading: CircleAvatar(
                            backgroundColor:
                                _statusColor(status).withValues(alpha: 0.15),
                            child: Icon(
                              d['vehicle_type'] == 'car'
                                  ? Icons.directions_car
                                  : Icons.two_wheeler,
                              color: _statusColor(status),
                            ),
                          ),
                          title: Text(
                            d['name'] as String? ?? '—',
                            style: const TextStyle(fontWeight: FontWeight.w600),
                          ),
                          subtitle: Text(d['phone'] as String? ?? ''),
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              if (isOnline)
                                Container(
                                  width: 8,
                                  height: 8,
                                  margin: const EdgeInsets.only(right: 8),
                                  decoration: const BoxDecoration(
                                    color: AppColors.primary,
                                    shape: BoxShape.circle,
                                  ),
                                ),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 8, vertical: 3),
                                decoration: BoxDecoration(
                                  color: _statusColor(status)
                                      .withValues(alpha: 0.12),
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: Text(
                                  _statusLabel(status),
                                  style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w600,
                                    color: _statusColor(status),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                ),
    );
  }
}

