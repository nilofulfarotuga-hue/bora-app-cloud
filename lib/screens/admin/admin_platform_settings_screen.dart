import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../config/app_colors.dart';
import '../../widgets/bora/bora_screen_app_bar.dart';

/// Admin Platform Settings — edit configurable parameters in `platform_settings`.
/// HIGH-RISK: changes propagate live; use with care. All changes audited.
class AdminPlatformSettingsScreen extends StatefulWidget {
  const AdminPlatformSettingsScreen({super.key});
  @override
  State<AdminPlatformSettingsScreen> createState() => _AdminPlatformSettingsScreenState();
}

class _AdminPlatformSettingsScreenState extends State<AdminPlatformSettingsScreen> {
  Map<String, List<_Setting>> _byCategory = const {};
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
      final res = await Supabase.instance.client.rpc('admin_list_settings',
          params: {'p_category': null});
      final list = (res as List)
          .map((e) => _Setting.fromJson((e as Map).cast<String, dynamic>()))
          .toList();
      final by = <String, List<_Setting>>{};
      for (final s in list) {
        by.putIfAbsent(s.category ?? 'other', () => []).add(s);
      }
      if (mounted) setState(() => _byCategory = by);
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  /// Bloco 4 — as 5 chaves de cancelamento são editáveis COM auditoria + motivo
  /// obrigatório (via RPC admin_update_cancel_setting). As restantes chaves
  /// financeiras continuam protegidas.
  static const _cancelKeys = <String>{
    'cancel_grace_seconds',
    'cancel_fee_before_dispatch_cents',
    'cancel_fee_after_accept_cents',
    'cancel_fee_after_accept_driver_cents',
    'cancel_fee_after_pickup_ratio',
  };
  bool _isCancelKey(String key) => _cancelKeys.contains(key);

  /// Whitelist operacional: só chaves de dispatch e operação de reservas são
  /// editáveis aqui. Tudo o resto (fees, comissões, markup, tokens, wallet,
  /// valores em cêntimos, Stripe) é READ-ONLY — alterar requer sessão dedicada.
  /// Fail-safe: chave nova/desconhecida nasce protegida.
  bool _isEditable(String key) {
    if (_isCancelKey(key)) return true; // Bloco 4 — editável com auditoria
    if (key.startsWith('robot_b_')) return true; // kill switches Robot B v4
    if (key.startsWith('dispatch_')) return true;
    if (key.startsWith('reservation_')) {
      const financialMarkers = ['cents', 'payout', 'prepayment', 'bora_service', 'credit'];
      return !financialMarkers.any(key.contains);
    }
    // TVDE parada adicional (CAMPO-02): só as chaves OPERACIONAIS são editáveis
    // aqui. As de dinheiro (tvde_stop_fee_cents = taxa do cliente,
    // tvde_stop_driver_cents = ganho do motorista) ficam blindadas — alterá-las
    // é ação 🔴 que escala a pagamentos-wallet.
    // `tvde_roundtrip_discount_pct` NÃO entra aqui de propósito: é a % de
    // desconto aplicada ao pacote ida+volta, ou seja, mexe no que o cliente
    // paga. Aparece na lista em modo protegido (cadeado + descrição) como
    // qualquer outra chave de dinheiro; torná-la editável é ação 🔴.
    const tvdeStopOperational = {'tvde_max_stops', 'tvde_stop_timer_seconds'};
    if (tvdeStopOperational.contains(key)) return true;
    // BLOCO E (2026-07-28) — reagendamento de marcações. São chaves
    // OPERACIONAIS (horas de antecedência, nº de reagendamentos, janela de
    // dias): não mexem em nenhum valor cobrado, por isso são editáveis aqui.
    // O sinal (`appointment_deposit_cents`) e o split continuam blindados.
    const appointmentRescheduleOperational = {
      'appointment_reschedule_min_hours',
      'appointment_reschedule_max_count',
      'appointment_reschedule_max_days',
    };
    if (appointmentRescheduleOperational.contains(key)) return true;
    return false;
  }

  void _showProtectedInfo(_Setting s) {
    showDialog<void>(
      context: context,
      builder: (_) => AlertDialog(
        title: Row(children: [
          const Icon(Icons.lock, size: 20),
          const SizedBox(width: 8),
          Expanded(child: Text(s.key, style: const TextStyle(fontSize: 15))),
        ]),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (s.description != null)
              Text(s.description!, style: const TextStyle(fontSize: 12)),
            const SizedBox(height: 8),
            Text('Valor atual: ${s.value}',
                style: const TextStyle(fontWeight: FontWeight.w600)),
            const SizedBox(height: 12),
            const Text(
              '🔒 Chave financeira/protegida — somente leitura.\n'
              'Alterar requer sessão dedicada com validação de impacto.',
              style: TextStyle(color: AppColors.error, fontSize: 12),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Fechar')),
        ],
      ),
    );
  }

  Future<void> _editSetting(_Setting s) async {
    final ctrl = TextEditingController(text: s.value.toString());
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(s.key),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (s.description != null) Text(s.description!, style: const TextStyle(fontSize: 12)),
            const SizedBox(height: 8),
            TextField(
              controller: ctrl,
              decoration: const InputDecoration(
                labelText: 'Valor (JSON)',
                border: OutlineInputBorder(),
                hintText: 'ex: 250 ou 0.80 ou "abc"',
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              '⚠️ Esta alteração propaga-se live. Tens a certeza?',
              style: TextStyle(color: AppColors.error, fontSize: 12),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancelar')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Atualizar')),
        ],
      ),
    );
    if (ok != true) return;
    try {
      // Try parse as number first, then as raw JSON, fallback to quoted string.
      final txt = ctrl.text.trim();
      dynamic parsed;
      final asNum = num.tryParse(txt);
      if (asNum != null) {
        parsed = asNum;
      } else if (txt == 'true' || txt == 'false') {
        parsed = txt == 'true';
      } else {
        parsed = txt;
      }
      await Supabase.instance.client.rpc('admin_update_setting',
          params: {'p_key': s.key, 'p_value': parsed});
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Atualizado')));
      }
      await _load();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Erro: $e')));
      }
    }
  }

  /// Bloco 4 — edição auditada de uma taxa de cancelamento (motivo obrigatório).
  Future<void> _editCancelSetting(_Setting s) async {
    final ctrl = TextEditingController(text: s.value.toString());
    final reasonCtrl = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => StatefulBuilder(
        builder: (ctx, setD) => AlertDialog(
          title: Text(s.key),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (s.description != null)
                Text(s.description!, style: const TextStyle(fontSize: 12)),
              const SizedBox(height: 8),
              TextField(
                controller: ctrl,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(
                  labelText: 'Novo valor (número)',
                  border: OutlineInputBorder(),
                  hintText: 'ex: 180 (seg) · 250 (cêntimos) · 1.0 (rácio)',
                ),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: reasonCtrl,
                maxLines: 2,
                decoration: const InputDecoration(
                  labelText: 'Motivo (obrigatório)',
                  border: OutlineInputBorder(),
                ),
                onChanged: (_) => setD(() {}),
              ),
              const SizedBox(height: 8),
              const Text(
                '⚠️ Taxa de cancelamento — propaga-se live e fica auditada.',
                style: TextStyle(color: AppColors.error, fontSize: 12),
              ),
            ],
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Cancelar')),
            FilledButton(
              onPressed: reasonCtrl.text.trim().length < 3
                  ? null
                  : () => Navigator.pop(ctx, true),
              child: const Text('Atualizar'),
            ),
          ],
        ),
      ),
    );
    if (ok != true) return;
    final value = num.tryParse(ctrl.text.trim());
    if (value == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Valor inválido — usa um número.')));
      }
      return;
    }
    try {
      await Supabase.instance.client.rpc('admin_update_cancel_setting', params: {
        'p_key': s.key,
        'p_new_value': value,
        'p_reason': reasonCtrl.text.trim(),
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Taxa atualizada e auditada')));
      }
      await _load();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Erro: $e')));
      }
    }
  }

  /// Bloco 4 — histórico das alterações de taxas (admin_audit_log).
  Future<void> _showCancelAudit() async {
    List<dynamic> rows = const [];
    try {
      final res = await Supabase.instance.client
          .rpc('admin_list_cancel_setting_audit');
      rows = (res as List?) ?? const [];
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Erro: $e')));
      }
      return;
    }
    if (!mounted) return;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (_) => DraggableScrollableSheet(
        expand: false,
        builder: (_, controller) => ListView(
          controller: controller,
          padding: const EdgeInsets.all(16),
          children: [
            const Text('Auditoria de taxas de cancelamento',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
            const SizedBox(height: 8),
            if (rows.isEmpty) const Text('Sem alterações registadas.'),
            ...rows.map((r) {
              final m = (r as Map).cast<String, dynamic>();
              final d = (m['details'] as Map?)?.cast<String, dynamic>() ?? {};
              return ListTile(
                dense: true,
                title: Text(
                    '${m['entity_id_text']}: ${d['old_value']} → ${d['new_value']}'),
                subtitle: Text(
                    '${m['admin_email'] ?? ''} · ${d['reason'] ?? ''}\n${m['created_at'] ?? ''}'),
                isThreeLine: true,
              );
            }),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _showCancelAudit,
        icon: const Icon(Icons.history),
        label: const Text('Auditoria taxas'),
      ),
      appBar: const BoraScreenAppBar(title: 'Configurações'),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(child: Text(_error!, style: const TextStyle(color: AppColors.error)))
              : RefreshIndicator(
                  onRefresh: _load,
                  child: ListView(
                    children: _byCategory.entries.map((entry) {
                      return ExpansionTile(
                        title: Text(entry.key.toUpperCase(),
                            style: const TextStyle(fontWeight: FontWeight.bold)),
                        children: entry.value.map((s) {
                          final editable = _isEditable(s.key);
                          return ListTile(
                            leading: editable
                                ? const Icon(Icons.edit_outlined,
                                    size: 18, color: AppColors.textSecondary)
                                : const Icon(Icons.lock_outline,
                                    size: 18, color: AppColors.textSubtle),
                            title: Text(s.key, style: const TextStyle(fontFamily: 'monospace')),
                            subtitle: s.description != null ? Text(s.description!) : null,
                            trailing: Text(s.value.toString(),
                                style: const TextStyle(fontWeight: FontWeight.w600)),
                            onTap: () => editable
                                ? (_isCancelKey(s.key)
                                    ? _editCancelSetting(s)
                                    : _editSetting(s))
                                : _showProtectedInfo(s),
                          );
                        }).toList(),
                      );
                    }).toList(),
                  ),
                ),
    );
  }
}

class _Setting {
  final String key;
  final dynamic value;
  final String? description;
  final String? category;
  _Setting({required this.key, required this.value, this.description, this.category});
  factory _Setting.fromJson(Map<String, dynamic> j) => _Setting(
        key: j['key'] as String,
        value: j['value'],
        description: j['description'] as String?,
        category: j['category'] as String?,
      );
}
