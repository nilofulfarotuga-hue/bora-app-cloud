import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../config/app_colors.dart';
import '../../services/admin_export_service.dart';
import '../../widgets/bora/bora_screen_app_bar.dart';

/// Painel admin (PT-BR) — "Pagamentos Connect" (Stripe Connect Fase 1).
///
/// Autoridade total do Danilo: lista todas as contas Connect (parceiros,
/// serviços, estafetas, limpeza), ações por conta (reenviar link, abrir no
/// dashboard Stripe, re-sincronizar, desligar), edição das configurações
/// `stripe_connect` (via RPC admin_update_setting), extrato de qualquer
/// parceiro com exportação CSV e trilha de auditoria.
class AdminConnectPaymentsScreen extends StatefulWidget {
  const AdminConnectPaymentsScreen({super.key});

  @override
  State<AdminConnectPaymentsScreen> createState() =>
      _AdminConnectPaymentsScreenState();
}

class _AdminConnectPaymentsScreenState
    extends State<AdminConnectPaymentsScreen> {
  bool _loading = true;
  String? _error;
  List<Map<String, dynamic>> _accounts = [];
  List<Map<String, dynamic>> _settings = [];
  List<Map<String, dynamic>> _audit = [];
  String _roleFilter = 'all';

  static const _roleLabels = {
    'partner': 'Parceiro',
    'provider': 'Serviços',
    'driver': 'Estafeta',
    'cleaner': 'Limpeza',
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
      final client = Supabase.instance.client;
      final accounts = await client.rpc('admin_list_connect_accounts');
      final settings = await client
          .rpc('admin_list_settings', params: {'p_category': 'stripe_connect'});
      List<Map<String, dynamic>> audit = [];
      try {
        final auditRes = await client
            .from('admin_audit_log')
            .select('admin_email, action, entity_type, entity_id_text, details, created_at')
            .ilike('action', 'stripe_connect%')
            .order('created_at', ascending: false)
            .limit(30);
        audit = (auditRes as List)
            .map((e) => Map<String, dynamic>.from(e as Map))
            .toList();
      } catch (_) {
        // Auditoria é secundária — não bloqueia o painel.
      }
      if (!mounted) return;
      setState(() {
        _accounts = ((accounts as List?) ?? const [])
            .map((e) => Map<String, dynamic>.from(e as Map))
            .toList();
        _settings = ((settings as List?) ?? const [])
            .map((e) => Map<String, dynamic>.from(e as Map))
            .toList();
        _audit = audit;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = 'Erro ao carregar: $e';
        _loading = false;
      });
    }
  }

  List<Map<String, dynamic>> get _filtered => _roleFilter == 'all'
      ? _accounts
      : _accounts.where((a) => a['role'] == _roleFilter).toList();

  // ── Ações por conta (Edge Function stripe-connect-admin) ─────────────────

  Future<Map<String, dynamic>?> _adminAction(
      String action, Map<String, dynamic> account) async {
    try {
      final res = await Supabase.instance.client.functions.invoke(
        'stripe-connect-admin',
        body: {
          'action': action,
          'role': account['role'],
          'row_id': account['row_id'],
        },
      );
      final data =
          res.data is Map ? Map<String, dynamic>.from(res.data) : null;
      if (data?['error'] != null) throw Exception(data!['error']);
      return data;
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Falhou: $e')));
      }
      return null;
    }
  }

  Future<void> _resendLink(Map<String, dynamic> account) async {
    final data = await _adminAction('onboard_link', account);
    final url = data?['url'] as String?;
    if (url == null || !mounted) return;
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Link de cadastro'),
        content: SelectableText(url),
        actions: [
          TextButton(
            onPressed: () async {
              await Clipboard.setData(ClipboardData(text: url));
              if (ctx.mounted) Navigator.pop(ctx);
            },
            child: const Text('Copiar'),
          ),
          TextButton(
            onPressed: () =>
                launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication),
            child: const Text('Abrir'),
          ),
        ],
      ),
    );
  }

  Future<void> _openInStripe(Map<String, dynamic> account) async {
    final id = account['account_id'] as String?;
    if (id == null) return;
    await launchUrl(
      Uri.parse('https://dashboard.stripe.com/connect/accounts/$id'),
      mode: LaunchMode.externalApplication,
    );
  }

  Future<void> _resync(Map<String, dynamic> account) async {
    final data = await _adminAction('resync', account);
    if (data != null && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Conta re-sincronizada com a Stripe.')),
      );
      _load();
    }
  }

  Future<void> _disconnect(Map<String, dynamic> account) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Desligar Connect?'),
        content: Text(
          '${account['name']} volta ao acerto manual por transferência '
          'bancária. A conta na Stripe não é apagada — dá para religar '
          'depois com "Reenviar link".',
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancelar')),
          TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Desligar',
                  style: TextStyle(color: AppColors.error))),
        ],
      ),
    );
    if (ok != true) return;
    final data = await _adminAction('disconnect', account);
    if (data != null && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Connect desligado — acerto manual.')),
      );
      _load();
    }
  }

  // ── Extrato de qualquer parceiro + CSV ────────────────────────────────────

  Future<void> _showStatement(Map<String, dynamic> account) async {
    List<Map<String, dynamic>> lines = [];
    try {
      final res = await Supabase.instance.client
          .from('partner_statement_lines')
          .select()
          .eq('owner_type', account['role'] as String)
          .eq('owner_id', account['row_id'] as String)
          .order('occurred_at', ascending: false)
          .limit(200);
      lines = (res as List)
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Erro no extrato: $e')));
      }
      return;
    }
    if (!mounted) return;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.7,
        builder: (ctx, controller) => Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      'Extrato — ${account['name']}',
                      style: const TextStyle(
                          fontWeight: FontWeight.w800, fontSize: 16),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.download),
                    tooltip: 'Exportar CSV',
                    onPressed: lines.isEmpty
                        ? null
                        : () => AdminExportService.instance.exportCsv(
                              filename:
                                  'extrato_${account['role']}_${account['row_id']}.csv',
                              headers: const [
                                'data',
                                'tipo',
                                'descricao',
                                'referencia',
                                'bruto_cents',
                                'valor_cents',
                              ],
                              rows: lines
                                  .map((l) => [
                                        l['occurred_at'],
                                        l['kind'],
                                        l['description'],
                                        l['reference'] ?? '',
                                        l['gross_cents'],
                                        l['amount_cents'],
                                      ])
                                  .toList(),
                              subject: 'Extrato ${account['name']}',
                            ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: lines.isEmpty
                  ? const Center(child: Text('Sem movimentos.'))
                  : ListView.builder(
                      controller: controller,
                      itemCount: lines.length,
                      itemBuilder: (ctx, i) {
                        final l = lines[i];
                        final cents = (l['amount_cents'] as num?) ?? 0;
                        return ListTile(
                          dense: true,
                          title: Text('${l['description']}'),
                          subtitle: Text(
                              '${_dateShort(l['occurred_at'] as String?)} · ${l['kind']}'),
                          trailing: Text(
                            _euro(cents),
                            style: TextStyle(
                              fontWeight: FontWeight.w700,
                              color: cents >= 0
                                  ? AppColors.success
                                  : AppColors.textPrimary,
                            ),
                          ),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Configurações stripe_connect (RPC admin_update_setting) ──────────────

  Future<void> _editSetting(Map<String, dynamic> setting) async {
    final key = setting['key'] as String;
    final current = setting['value'];

    if (key == 'stripe_connect_enabled') {
      final newValue = !(current == true);
      final ok = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text(newValue ? 'Ligar Connect?' : 'Desligar Connect?'),
          content: Text(newValue
              ? 'ATENÇÃO: liga o modo Connect na plataforma toda. '
                  'Só fazer depois de testar em modo teste (ver o guia).'
              : 'Desliga o modo Connect — tudo volta ao acerto manual.'),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Cancelar')),
            TextButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('Confirmar')),
          ],
        ),
      );
      if (ok != true) return;
      await _saveSetting(key, newValue);
      return;
    }

    if (key == 'stripe_fee_bearer') {
      final newValue = await showDialog<String>(
        context: context,
        builder: (ctx) => SimpleDialog(
          title: const Text('Quem paga as taxas Stripe?'),
          children: [
            SimpleDialogOption(
              onPressed: () => Navigator.pop(ctx, 'partner'),
              child: const Text('partner — o parceiro (desconta no extrato)'),
            ),
            SimpleDialogOption(
              onPressed: () => Navigator.pop(ctx, 'platform'),
              child: const Text('platform — a Bora absorve (extrato mostra 0)'),
            ),
          ],
        ),
      );
      if (newValue == null || newValue == current) return;
      await _saveSetting(key, newValue);
      return;
    }

    // Numéricos (pct/cents).
    final controller = TextEditingController(text: '$current');
    final newText = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(key),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              '⚠️ Mexer nas taxas muda o que o parceiro vê no extrato.',
              style: TextStyle(color: AppColors.warning, fontSize: 13),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: controller,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(border: OutlineInputBorder()),
            ),
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancelar')),
          TextButton(
              onPressed: () => Navigator.pop(ctx, controller.text.trim()),
              child: const Text('Salvar')),
        ],
      ),
    );
    if (newText == null || newText.isEmpty) return;
    final parsed = num.tryParse(newText.replaceAll(',', '.'));
    if (parsed == null) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('Valor inválido.')));
      }
      return;
    }
    await _saveSetting(key, parsed);
  }

  Future<void> _saveSetting(String key, Object value) async {
    try {
      await Supabase.instance.client.rpc('admin_update_setting', params: {
        'p_key': key,
        'p_value': value,
      });
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('$key atualizado.')));
      }
      _load();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Erro ao salvar: $e')));
      }
    }
  }

  // ── Helpers ───────────────────────────────────────────────────────────────

  String _euro(num? cents) =>
      '€ ${((cents ?? 0) / 100.0).toStringAsFixed(2)}';

  String _dateShort(String? iso) {
    final d = DateTime.tryParse(iso ?? '')?.toLocal();
    if (d == null) return '—';
    return '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';
  }

  (Color, String) _statusChip(String? status) => switch (status) {
        'enabled' => (AppColors.success, 'Ativa'),
        'pending' => (AppColors.warning, 'Em verificação'),
        'restricted' => (AppColors.error, 'Faltam dados'),
        'disabled' => (AppColors.error, 'Desativada'),
        _ => (AppColors.textSubtle, 'Sem conta'),
      };

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: BoraScreenAppBar(
        title: 'Pagamentos Connect',
        actions: [
          IconButton(icon: const Icon(Icons.refresh), onPressed: _load),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Text(_error!,
                        style: const TextStyle(color: AppColors.error)),
                  ),
                )
              : RefreshIndicator(
                  onRefresh: _load,
                  child: ListView(
                    padding: const EdgeInsets.all(16),
                    children: [
                      _settingsCard(),
                      const SizedBox(height: 16),
                      _filterChips(),
                      const SizedBox(height: 8),
                      if (_filtered.isEmpty)
                        const Card(
                          child: Padding(
                            padding: EdgeInsets.all(24),
                            child: Center(child: Text('Nenhuma conta.')),
                          ),
                        )
                      else
                        ..._filtered.map(_accountCard),
                      const SizedBox(height: 16),
                      _auditCard(),
                      const SizedBox(height: 24),
                    ],
                  ),
                ),
    );
  }

  Widget _filterChips() {
    final entries = [
      const MapEntry('all', 'Todos'),
      ..._roleLabels.entries,
    ];
    return Wrap(
      spacing: 8,
      children: entries
          .map((e) => ChoiceChip(
                label: Text(e.value),
                selected: _roleFilter == e.key,
                onSelected: (_) => setState(() => _roleFilter = e.key),
              ))
          .toList(),
    );
  }

  Widget _accountCard(Map<String, dynamic> a) {
    final (color, label) = _statusChip(a['status'] as String?);
    final due = (a['requirements'] is Map &&
            (a['requirements']['currently_due'] is List))
        ? (a['requirements']['currently_due'] as List)
        : const [];
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        title: Text('${a['name'] ?? a['row_id']}',
            style: const TextStyle(fontWeight: FontWeight.w700)),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(_roleLabels[a['role']] ?? '${a['role']}'),
            const SizedBox(height: 4),
            Wrap(
              spacing: 8,
              runSpacing: 4,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(label,
                      style: TextStyle(
                          color: color,
                          fontSize: 12,
                          fontWeight: FontWeight.w700)),
                ),
                if (a['account_id'] != null) ...[
                  Icon(
                    a['charges_enabled'] == true
                        ? Icons.check_circle
                        : Icons.cancel,
                    size: 14,
                    color: a['charges_enabled'] == true
                        ? AppColors.success
                        : AppColors.textSubtle,
                  ),
                  const Text('cobranças', style: TextStyle(fontSize: 11)),
                  Icon(
                    a['payouts_enabled'] == true
                        ? Icons.check_circle
                        : Icons.cancel,
                    size: 14,
                    color: a['payouts_enabled'] == true
                        ? AppColors.success
                        : AppColors.textSubtle,
                  ),
                  const Text('repasses', style: TextStyle(fontSize: 11)),
                ],
                if (due.isNotEmpty)
                  Text('falta: ${due.length} item(ns)',
                      style: const TextStyle(
                          fontSize: 11, color: AppColors.error)),
                if (a['onboarded_at'] != null)
                  Text('desde ${_dateShort(a['onboarded_at'] as String?)}',
                      style: const TextStyle(fontSize: 11)),
              ],
            ),
          ],
        ),
        trailing: PopupMenuButton<String>(
          onSelected: (v) => switch (v) {
            'link' => _resendLink(a),
            'stripe' => _openInStripe(a),
            'resync' => _resync(a),
            'statement' => _showStatement(a),
            'disconnect' => _disconnect(a),
            _ => null,
          },
          itemBuilder: (ctx) => [
            const PopupMenuItem(
                value: 'link', child: Text('Reenviar link de cadastro')),
            if (a['account_id'] != null)
              const PopupMenuItem(
                  value: 'stripe', child: Text('Abrir no dashboard Stripe')),
            if (a['account_id'] != null)
              const PopupMenuItem(
                  value: 'resync', child: Text('Re-sincronizar')),
            const PopupMenuItem(
                value: 'statement', child: Text('Ver extrato / CSV')),
            if (a['account_id'] != null)
              const PopupMenuItem(
                value: 'disconnect',
                child: Text('Desligar Connect (acerto manual)',
                    style: TextStyle(color: AppColors.error)),
              ),
          ],
        ),
      ),
    );
  }

  Widget _settingsCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Configurações',
                style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
            const SizedBox(height: 4),
            const Text(
              '⚠️ Mexer nas taxas muda o que o parceiro vê no extrato.',
              style: TextStyle(color: AppColors.warning, fontSize: 12),
            ),
            const SizedBox(height: 8),
            if (_settings.isEmpty)
              const Text('Sem chaves stripe_connect.',
                  style: TextStyle(color: AppColors.textSecondary))
            else
              ..._settings.map(
                (s) => ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  title: Text('${s['key']}',
                      style: const TextStyle(fontSize: 13)),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text('${s['value']}',
                          style: const TextStyle(
                              fontWeight: FontWeight.w700, fontSize: 13)),
                      IconButton(
                        icon: const Icon(Icons.edit, size: 18),
                        onPressed: () => _editSetting(s),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _auditCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Auditoria (últimas 30)',
                style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
            const SizedBox(height: 8),
            if (_audit.isEmpty)
              const Text('Sem ações registradas.',
                  style: TextStyle(color: AppColors.textSecondary))
            else
              ..._audit.map(
                (a) => Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Text(
                    '${_dateShort(a['created_at'] as String?)} — '
                    '${a['admin_email'] ?? '?'} — ${a['action']} — '
                    '${a['entity_type'] ?? ''} ${a['entity_id_text'] ?? ''}',
                    style: const TextStyle(fontSize: 12),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
