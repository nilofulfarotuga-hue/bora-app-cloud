import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../config/app_colors.dart';
import '../../config/app_spacing.dart';
import '../../widgets/admin/admin_coming_soon.dart';
import '../../widgets/bora/bora_screen_app_bar.dart';
import 'admin_service_provider_detail_screen.dart';

/// Admin — Barbearias / Prestadores de serviços (vertical Serviços).
///
/// Lista `service_providers` filtrado por `approval_status` (default 'pending').
/// Aprova/rejeita via RPCs `admin_appointment_provider_approve` /
/// `admin_appointment_provider_reject` e activa/desactiva via UPDATE directo
/// em `service_providers.is_active_admin`. Espelha
/// `admin_partners_pending_screen.dart`. PT-BR.
class AdminServiceProvidersScreen extends StatefulWidget {
  const AdminServiceProvidersScreen({super.key});

  @override
  State<AdminServiceProvidersScreen> createState() =>
      _AdminServiceProvidersScreenState();
}

class _AdminServiceProvidersScreenState
    extends State<AdminServiceProvidersScreen> {
  static const _statuses = {
    'pending': 'Pendentes',
    'approved': 'Aprovados',
    'rejected': 'Rejeitados',
    null: 'Todos',
  };

  String? _filter = 'pending';
  bool _loading = true;
  String? _error;
  List<Map<String, dynamic>> _rows = const [];

  /// Filtro rápido "Só em breve".
  bool _onlyComingSoon = false;

  List<Map<String, dynamic>> get _visible => _onlyComingSoon
      ? _rows.where((r) => r['coming_soon'] == true).toList()
      : _rows;

  int get _comingSoonCount =>
      _rows.where((r) => r['coming_soon'] == true).length;

  /// Liga/desliga o "Em breve" e edita o texto do banner do cliente.
  Future<void> _editComingSoon(Map<String, dynamic> r) async {
    final changed = await showAdminComingSoonDialog(
      context: context,
      table: 'service_providers',
      id: r['id'] as String,
      name: r['name'] as String? ?? '(sem nome)',
      currentValue: r['coming_soon'] == true,
      currentText: r['coming_soon_text'] as String?,
    );
    if (changed) _load();
  }

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
      var q = Supabase.instance.client.from('service_providers').select();
      if (_filter != null) {
        q = q.eq('approval_status', _filter!);
      }
      final rows = await q.order('created_at', ascending: false);
      if (!mounted) return;
      setState(() {
        _rows = (rows as List).cast<Map<String, dynamic>>();
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = e.toString();
      });
    }
  }

  Future<void> _approve(Map<String, dynamic> r) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Aprovar prestador'),
        content: Text(
            '${r['name']} ficará imediatamente visível aos clientes. Confirmar?'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancelar')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppColors.success),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Aprovar'),
          ),
        ],
      ),
    );
    if (confirm != true) return;
    try {
      await Supabase.instance.client.rpc(
        'admin_appointment_provider_approve',
        params: {'p_provider_id': r['id']},
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${r['name']} aprovado.')),
      );
      _load();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Erro: $e')),
      );
    }
  }

  Future<void> _reject(Map<String, dynamic> r) async {
    final ctrl = TextEditingController();
    String? reason;
    try {
      reason = await showDialog<String>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text('Rejeitar ${r['name']}'),
          content: TextField(
            controller: ctrl,
            autofocus: true,
            maxLines: 3,
            decoration: const InputDecoration(
              labelText: 'Motivo (obrigatório)',
              hintText: 'Ex.: dados incompletos, licença em falta…',
              border: OutlineInputBorder(),
            ),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Cancelar')),
            FilledButton(
              style: FilledButton.styleFrom(backgroundColor: AppColors.error),
              onPressed: () {
                final txt = ctrl.text.trim();
                if (txt.isEmpty) return;
                Navigator.pop(ctx, txt);
              },
              child: const Text('Rejeitar'),
            ),
          ],
        ),
      );
    } finally {
      ctrl.dispose();
    }
    if (reason == null || reason.isEmpty) return;
    try {
      await Supabase.instance.client.rpc(
        'admin_appointment_provider_reject',
        params: {'p_provider_id': r['id'], 'p_reason': reason},
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${r['name']} rejeitado.')),
      );
      _load();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Erro: $e')),
      );
    }
  }

  /// Toggle `is_active_admin` via UPDATE directo (admin RLS permite).
  Future<void> _toggleActive(Map<String, dynamic> r) async {
    final current = (r['is_active_admin'] as bool?) ?? true;
    final next = !current;
    try {
      await Supabase.instance.client
          .from('service_providers')
          .update({'is_active_admin': next}).eq('id', r['id']);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text(
                '${r['name']} ${next ? 'activado' : 'desactivado'}.')),
      );
      _load();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Erro: $e')),
      );
    }
  }

  /// Abre a tela de gestão TOTAL do prestador (editar dados/logo/capa/horários/
  /// serviços & preços/estado/apagar). Ao voltar, recarrega a lista para
  /// reflectir quaisquer alterações.
  Future<void> _openDetail(Map<String, dynamic> r) async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => AdminServiceProviderDetailScreen(
          providerId: r['id'] as String,
          initialName: r['name'] as String? ?? '',
        ),
      ),
    );
    _load();
  }

  Color _statusColor(String? s) => switch (s) {
        'approved' => AppColors.success,
        'rejected' => AppColors.error,
        'pending' => AppColors.warning,
        _ => AppColors.textSecondary,
      };

  Widget _contactButtons(String? phone) {
    if (phone == null || phone.isEmpty) return const SizedBox.shrink();
    Future<void> launch(String scheme) async {
      final uri = Uri.parse('$scheme:${phone.replaceAll(' ', '')}');
      if (await canLaunchUrl(uri)) await launchUrl(uri);
    }

    return Row(
      children: [
        OutlinedButton.icon(
          onPressed: () => launch('tel'),
          icon: const Icon(Icons.phone, size: 16),
          label: const Text('Ligar'),
          style: OutlinedButton.styleFrom(
            foregroundColor: AppColors.success,
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          ),
        ),
        const SizedBox(width: Spacing.sm),
        OutlinedButton.icon(
          onPressed: () => launch('sms'),
          icon: const Icon(Icons.sms, size: 16),
          label: const Text('SMS'),
          style: OutlinedButton.styleFrom(
            foregroundColor: AppColors.info,
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: BoraScreenAppBar(
        title: 'Prestadores de Serviços',
        actions: [
          IconButton(icon: const Icon(Icons.refresh), onPressed: _load),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(Spacing.md),
            child: Wrap(
              spacing: Spacing.sm,
              children: _statuses.entries.map((e) {
                final selected = _filter == e.key;
                return ChoiceChip(
                  label: Text(e.value),
                  selected: selected,
                  onSelected: (_) {
                    setState(() => _filter = e.key);
                    _load();
                  },
                );
              }).toList(),
            ),
          ),
          if (_loading)
            const Expanded(child: Center(child: CircularProgressIndicator()))
          else if (_error != null)
            Expanded(
              child: Center(
                child: Padding(
                  padding: const EdgeInsets.all(Spacing.xxl),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text('Erro: $_error',
                          textAlign: TextAlign.center,
                          style: const TextStyle(color: AppColors.error)),
                      const SizedBox(height: Spacing.md),
                      ElevatedButton(
                          onPressed: _load,
                          child: const Text('Tentar de novo')),
                    ],
                  ),
                ),
              ),
            )
          else ...[
            AdminComingSoonFilterBar(
              onlyComingSoon: _onlyComingSoon,
              total: _comingSoonCount,
              onChanged: (v) => setState(() => _onlyComingSoon = v),
            ),
            if (_visible.isEmpty)
              const Expanded(
                child: Center(
                  child: Padding(
                    padding: EdgeInsets.all(Spacing.xxxl),
                    child: Text('Nenhum prestador neste estado.'),
                  ),
                ),
              )
            else
              Expanded(
                child: RefreshIndicator(
                  onRefresh: _load,
                  child: ListView.builder(
                    padding: const EdgeInsets.symmetric(horizontal: Spacing.md),
                    itemCount: _visible.length,
                    itemBuilder: (ctx, i) => _buildRow(_visible[i]),
                  ),
                ),
              ),
          ],
        ],
      ),
    );
  }

  Widget _buildRow(Map<String, dynamic> r) {
    final status = r['approval_status'] as String?;
    final reason = r['rejection_reason'] as String?;
    final isActive = (r['is_active_admin'] as bool?) ?? true;
    final createdAt =
        DateTime.tryParse(r['created_at'] as String? ?? '')?.toLocal();
    return Card(
      margin: const EdgeInsets.symmetric(vertical: Spacing.xs + 2),
      shape:
          RoundedRectangleBorder(borderRadius: BorderRadius.circular(Radii.lg)),
      child: Padding(
        padding: const EdgeInsets.all(Spacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Row(
                    children: [
                      Flexible(
                        child: Text(
                          r['name'] as String? ?? '(sem nome)',
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                              fontWeight: FontWeight.w700, fontSize: 16),
                        ),
                      ),
                      if (r['coming_soon'] == true)
                        const AdminComingSoonBadge(),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: Spacing.sm, vertical: Spacing.xs),
                  decoration: BoxDecoration(
                    color: _statusColor(status).withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(Radii.sm),
                  ),
                  child: Text(
                    (status ?? '').toUpperCase(),
                    style: TextStyle(
                        fontSize: 11,
                        color: _statusColor(status),
                        fontWeight: FontWeight.w700),
                  ),
                ),
              ],
            ),
            const SizedBox(height: Spacing.xs),
            if ((r['address'] as String?)?.isNotEmpty ?? false)
              Text('📍 ${r['address']}', style: const TextStyle(fontSize: 12)),
            if ((r['phone'] as String?)?.isNotEmpty ?? false)
              Text('☎️ ${r['phone']}', style: const TextStyle(fontSize: 12)),
            if ((r['nif'] as String?)?.isNotEmpty ?? false)
              Text('NIF: ${r['nif']}', style: const TextStyle(fontSize: 12)),
            if ((r['iban'] as String?)?.isNotEmpty ?? false)
              Text('IBAN: ${r['iban']}', style: const TextStyle(fontSize: 12)),
            const SizedBox(height: Spacing.xs + 2),
            _contactButtons(r['phone'] as String?),
            if (createdAt != null)
              Text(
                'Criado: ${createdAt.day.toString().padLeft(2, '0')}/${createdAt.month.toString().padLeft(2, '0')}/${createdAt.year}',
                style: const TextStyle(
                    fontSize: 11, color: AppColors.textSecondary),
              ),
            if (reason != null && reason.isNotEmpty) ...[
              const SizedBox(height: Spacing.xs + 2),
              Container(
                padding: const EdgeInsets.all(Spacing.sm),
                decoration: BoxDecoration(
                  color: AppColors.error.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(Radii.sm),
                ),
                child: Text('Motivo rejeição: $reason',
                    style:
                        const TextStyle(fontSize: 12, color: AppColors.error)),
              ),
            ],
            const SizedBox(height: Spacing.sm),
            Wrap(
              alignment: WrapAlignment.end,
              spacing: Spacing.sm,
              runSpacing: Spacing.xs,
              children: [
                OutlinedButton.icon(
                  icon: const Icon(Icons.settings_outlined, size: 18),
                  label: const Text('Gerir'),
                  style: OutlinedButton.styleFrom(
                      foregroundColor: AppColors.info),
                  onPressed: () => _openDetail(r),
                ),
                OutlinedButton.icon(
                  icon: const Icon(Icons.schedule, size: 18),
                  label: Text(
                      r['coming_soon'] == true ? 'Em breve ✓' : 'Em breve'),
                  style: OutlinedButton.styleFrom(
                      foregroundColor: r['coming_soon'] == true
                          ? const Color(0xFFF97316)
                          : AppColors.textSecondary),
                  onPressed: () => _editComingSoon(r),
                ),
                OutlinedButton.icon(
                  icon: Icon(
                      isActive
                          ? Icons.toggle_on
                          : Icons.toggle_off_outlined,
                      size: 18),
                  label: Text(isActive ? 'Desactivar' : 'Activar'),
                  style: OutlinedButton.styleFrom(
                      foregroundColor:
                          isActive ? AppColors.warning : AppColors.success),
                  onPressed: () => _toggleActive(r),
                ),
                if (status != 'approved')
                  OutlinedButton.icon(
                    icon: const Icon(Icons.check_circle, size: 18),
                    label: const Text('Aprovar'),
                    style: OutlinedButton.styleFrom(
                        foregroundColor: AppColors.success),
                    onPressed: () => _approve(r),
                  ),
                if (status != 'rejected')
                  OutlinedButton.icon(
                    icon: const Icon(Icons.cancel_outlined, size: 18),
                    label: const Text('Rejeitar'),
                    style: OutlinedButton.styleFrom(
                        foregroundColor: AppColors.error),
                    onPressed: () => _reject(r),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
