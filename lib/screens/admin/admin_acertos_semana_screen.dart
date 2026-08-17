import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../config/app_colors.dart';
import '../../widgets/bora/bora_screen_app_bar.dart';

/// F3 — Painel admin "Acertos da semana" (PT-BR, só Danilo).
/// Lista o fecho semanal por pessoa/parceiro (da `admin_weekly_closeout_list`):
/// quem RECEBE do Bora e quem DEVE ao Bora, com estado de pago e de email.
/// Ações: marcar pago (muda estado do settlement, com auditoria), reenviar o
/// digest, configurar o MB Way do Bora e ligar o envio externo dos emails.
class AdminAcertosSemanaScreen extends StatefulWidget {
  const AdminAcertosSemanaScreen({super.key});

  @override
  State<AdminAcertosSemanaScreen> createState() => _AdminAcertosSemanaScreenState();
}

class _AdminAcertosSemanaScreenState extends State<AdminAcertosSemanaScreen> {
  bool _loading = true;
  String? _error;
  List<Map<String, dynamic>> _items = const [];
  List<String> _weeks = const [];
  String? _week;
  String _boraMbway = '';
  bool _emailsEnabled = false;
  bool _busy = false;

  final _client = Supabase.instance.client;

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
      final res = await _client.rpc('admin_weekly_closeout_list',
          params: {'p_week_start': _week});
      final m = (res as Map).cast<String, dynamic>();
      if (!mounted) return;
      setState(() {
        _items = ((m['items'] as List?) ?? [])
            .map((e) => (e as Map).cast<String, dynamic>())
            .toList();
        _weeks = ((m['weeks'] as List?) ?? []).map((e) => e.toString()).toList();
        _week = (m['week_start'] as String?) ?? _week;
        _boraMbway = (m['bora_mbway'] as String?) ?? '';
        _emailsEnabled = m['emails_enabled'] == true;
        _loading = false;
      });
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString();
          _loading = false;
        });
      }
    }
  }

  String _eur(num cents) =>
      '€${(cents.abs() / 100).toStringAsFixed(2).replaceAll('.', ',')}';

  Future<void> _markPaid(Map<String, dynamic> r) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await _client.rpc('admin_mark_settlement_paid', params: {
        'p_subject_type': r['type'],
        'p_subject_id': r['subject_id'],
        'p_week_start': _week,
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('${r['name']} marcado como pago.')));
      }
      await _load();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Erro: $e')));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _resend() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await _client.rpc('admin_resend_weekly_digest', params: {'p_week_start': _week});
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('Digest reenviado (emails externos só com o envio ligado).')));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Erro: $e')));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _editMbway() async {
    final ctrl = TextEditingController(text: _boraMbway);
    final v = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('MB Way do Bora (cobranças)'),
        content: TextField(
          controller: ctrl,
          keyboardType: TextInputType.phone,
          decoration: const InputDecoration(
            labelText: 'Número MB Way',
            hintText: '+351 9XX XXX XXX',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancelar')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, ctrl.text.trim()),
              child: const Text('Guardar')),
        ],
      ),
    );
    if (v == null) return;
    try {
      await _client.rpc('admin_update_weekly_closeout_settings',
          params: {'p_bora_mbway': v});
      await _load();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Erro: $e')));
      }
    }
  }

  Future<void> _toggleEmails(bool on) async {
    setState(() => _emailsEnabled = on);
    try {
      await _client.rpc('admin_update_weekly_closeout_settings',
          params: {'p_emails_enabled': on});
    } catch (e) {
      if (mounted) {
        setState(() => _emailsEnabled = !on);
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Erro: $e')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final aReceber = _items.where((r) => r['direction'] == 'owes_bora').toList();
    final aPagar = _items.where((r) => r['direction'] == 'bora_pays').toList();
    final zerados = _items.where((r) => r['direction'] == 'zero').length;

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: const BoraScreenAppBar(title: 'Acertos da semana'),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(mainAxisSize: MainAxisSize.min, children: [
                      Text(_error!,
                          textAlign: TextAlign.center,
                          style: const TextStyle(color: AppColors.error)),
                      const SizedBox(height: 12),
                      ElevatedButton(
                          onPressed: _load, child: const Text('Tentar de novo')),
                    ]),
                  ),
                )
              : RefreshIndicator(
                  onRefresh: _load,
                  child: ListView(
                    padding: const EdgeInsets.all(16),
                    children: [
                      _configCard(),
                      const SizedBox(height: 12),
                      _resumoCard(aReceber.length, aPagar.length, zerados),
                      const SizedBox(height: 16),
                      if (aReceber.isNotEmpty) ...[
                        _secTitle('A RECEBER (devem ao Bora)', AppColors.success),
                        ...aReceber.map(_itemCard),
                        const SizedBox(height: 8),
                      ],
                      if (aPagar.isNotEmpty) ...[
                        _secTitle('A PAGAR (Bora paga)', AppColors.warning),
                        ...aPagar.map(_itemCard),
                      ],
                      if (_items.isEmpty)
                        const Padding(
                          padding: EdgeInsets.only(top: 40),
                          child: Center(child: Text('Sem acertos nesta semana.')),
                        ),
                    ],
                  ),
                ),
    );
  }

  Widget _secTitle(String t, Color c) => Padding(
        padding: const EdgeInsets.only(top: 4, bottom: 6),
        child: Text(t,
            style: TextStyle(fontWeight: FontWeight.w800, color: c, fontSize: 13)),
      );

  Widget _configCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            const Expanded(
                child: Text('Semana', style: TextStyle(fontWeight: FontWeight.w600))),
            if (_weeks.isNotEmpty)
              DropdownButton<String>(
                value: _weeks.contains(_week) ? _week : null,
                hint: Text(_week ?? '—'),
                items: _weeks
                    .map((w) => DropdownMenuItem(value: w, child: Text(w)))
                    .toList(),
                onChanged: (v) {
                  if (v == null) return;
                  setState(() => _week = v);
                  _load();
                },
              ),
          ]),
          const Divider(),
          InkWell(
            onTap: _editMbway,
            child: Row(children: [
              const Icon(Icons.account_balance_wallet_outlined, size: 18),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  _boraMbway.isEmpty
                      ? 'MB Way do Bora: (definir — obrigatório para cobrar)'
                      : 'MB Way do Bora: $_boraMbway',
                  style: TextStyle(
                      color: _boraMbway.isEmpty
                          ? AppColors.error
                          : AppColors.textPrimary,
                      fontWeight:
                          _boraMbway.isEmpty ? FontWeight.w600 : FontWeight.w500),
                ),
              ),
              const Icon(Icons.edit_outlined, size: 16),
            ]),
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            dense: true,
            value: _emailsEnabled,
            onChanged: _toggleEmails,
            title: const Text('Enviar emails externos'),
            subtitle: Text(_emailsEnabled
                ? 'Ligado — todos recebem o extrato por email.'
                : 'Desligado — só o Danilo; os restantes ficam "aguarda domínio".'),
          ),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton.icon(
              onPressed: _busy ? null : _resend,
              icon: const Icon(Icons.send_outlined, size: 18),
              label: const Text('Reenviar digest'),
            ),
          ),
        ]),
      ),
    );
  }

  Widget _resumoCard(int nReceber, int nPagar, int zerados) {
    return Card(
      color: AppColors.surface,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        child: Row(mainAxisAlignment: MainAxisAlignment.spaceAround, children: [
          _kpi('A receber', '$nReceber', AppColors.success),
          _kpi('A pagar', '$nPagar', AppColors.warning),
          _kpi('Zerados', '$zerados', AppColors.textSecondary),
        ]),
      ),
    );
  }

  Widget _kpi(String label, String v, Color c) => Column(children: [
        Text(v, style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: c)),
        Text(label, style: const TextStyle(fontSize: 11, color: AppColors.textSecondary)),
      ]);

  Widget _itemCard(Map<String, dynamic> r) {
    final owes = r['direction'] == 'owes_bora';
    final net = (r['net_cents'] as num?) ?? 0;
    final paid = r['paid_status'] == 'paid';
    final emailStatus = (r['email_status'] as String?) ?? '';
    final mbway = (r['mbway'] as String?) ?? '';
    final cor = owes ? AppColors.success : AppColors.warning;

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Expanded(
              child: Text('${r['name'] ?? ''}',
                  style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
            ),
            Text('${owes ? '' : '−'}${_eur(net)}',
                style: TextStyle(fontWeight: FontWeight.w800, color: cor, fontSize: 16)),
          ]),
          const SizedBox(height: 2),
          Row(children: [
            _chip(_tipoLabel(r['type'] as String?), AppColors.textSecondary),
            const SizedBox(width: 6),
            if (mbway.isNotEmpty) _chip('MB Way $mbway', AppColors.textSecondary),
          ]),
          const SizedBox(height: 8),
          Row(children: [
            _statusChip(paid ? 'PAGO' : 'PENDENTE',
                paid ? AppColors.success : AppColors.warning),
            const SizedBox(width: 6),
            _statusChip(_emailLabel(emailStatus), AppColors.textSecondary),
            const Spacer(),
            if (!paid)
              TextButton(
                onPressed: _busy ? null : () => _markPaid(r),
                child: const Text('Marcar pago'),
              ),
          ]),
        ]),
      ),
    );
  }

  String _tipoLabel(String? t) => switch (t) {
        'driver' => 'Estafeta',
        'cleaner' => 'Limpeza',
        'provider' => 'Serviços',
        'partner' => 'Parceiro',
        _ => t ?? '',
      };

  String _emailLabel(String s) => switch (s) {
        'sent' => 'email enviado',
        'aguarda_dominio' => 'email aguarda domínio',
        'skipped' => 'sem email',
        'failed' => 'email falhou',
        _ => 'email pendente',
      };

  Widget _chip(String t, Color c) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
        decoration: BoxDecoration(
          color: c.withValues(alpha: 0.10),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Text(t, style: TextStyle(fontSize: 11, color: c)),
      );

  Widget _statusChip(String t, Color c) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: c.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(6),
        ),
        child: Text(t,
            style: TextStyle(fontSize: 10, color: c, fontWeight: FontWeight.w700)),
      );
}
