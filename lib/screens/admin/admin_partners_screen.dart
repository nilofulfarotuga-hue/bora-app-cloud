import 'dart:async';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../config/app_colors.dart';
import '../../config/app_spacing.dart';
import '../../widgets/admin/admin_coming_soon.dart';
import '../../widgets/bora/bora_screen_app_bar.dart';
import '../../services/admin_audit_service.dart';
import '../../services/admin_export_service.dart';
import 'admin_partner_detail_screen.dart';

class AdminPartnersScreen extends StatefulWidget {
  const AdminPartnersScreen({super.key});

  @override
  State<AdminPartnersScreen> createState() => _AdminPartnersScreenState();
}

class _AdminPartnersScreenState extends State<AdminPartnersScreen> {
  List<Map<String, dynamic>> _restaurants = [];
  bool _loading = true;
  String? _error;

  /// Filtro rápido "Só em breve".
  bool _onlyComingSoon = false;

  List<Map<String, dynamic>> get _visible => _onlyComingSoon
      ? _restaurants.where((r) => r['coming_soon'] == true).toList()
      : _restaurants;

  int get _comingSoonCount =>
      _restaurants.where((r) => r['coming_soon'] == true).length;

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
          .from('restaurants')
          .select(
              'id, name, category, address, is_active_admin, coming_soon, coming_soon_text')
          .order('name');
      if (mounted) {
        setState(() {
          _restaurants = List<Map<String, dynamic>>.from(data);
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

  Future<void> _toggleActive(String id, bool currentActive) async {
    final newActive = !currentActive;
    try {
      await Supabase.instance.client
          .from('restaurants')
          .update({'is_active_admin': newActive}).eq('id', id);

      // Best-effort audit (never blocks UX). entity_id stays null because
      // restaurants.id is TEXT, not UUID — the textual id travels in details.
      unawaited(AdminAuditService.logAction(
        action: 'partner_toggle',
        entityType: 'restaurant',
        details: {
          'restaurant_id': id,
          'old': currentActive,
          'new': newActive,
        },
      ));

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(newActive
            ? 'Parceiro reactivado.'
            : 'Parceiro desactivado pelo admin.'),
        backgroundColor:
            newActive ? AppColors.success : AppColors.warning,
        duration: const Duration(seconds: 2),
      ));
      await _load();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('Falhou actualizar parceiro: $e'),
        backgroundColor: AppColors.error,
        duration: const Duration(seconds: 4),
      ));
    }
  }

  IconData _categoryIcon(String? cat) {
    switch (cat) {
      case 'supermarket':
        return Icons.local_grocery_store;
      case 'pharmacy':
        return Icons.local_pharmacy;
      case 'store':
        return Icons.storefront;
      case 'festas':
        return Icons.celebration;
      case 'sobremesa':
        return Icons.icecream;
      default:
        return Icons.restaurant;
    }
  }

  String _categoryLabel(String? cat) {
    const labels = {
      'restaurant': 'Restaurante',
      'supermarket': 'Supermercado',
      'pharmacy': 'Farmácia',
      'store': 'Loja',
      'beauty': 'Beleza',
      'festas': 'Festas',
      // Sobremesas (2026-08-27) — açaí, sorvetes e doces. Uma loja pode estar
      // aqui E em Restaurantes ao mesmo tempo, pela coluna extra_categories.
      'sobremesa': 'Sobremesas',
    };
    return labels[cat] ?? (cat ?? '—');
  }

  /// Item 20 (paridade-admin-360): exportar a lista visível para CSV.
  Future<void> _exportCsv() async {
    try {
      final stamp = DateTime.now().toIso8601String().substring(0, 10);
      await AdminExportService.instance.exportCsv(
        filename: 'bora_parceiros_$stamp.csv',
        headers: const [
          'id', 'nome', 'categoria', 'morada', 'ativo', 'em_breve',
          'texto_em_breve',
        ],
        rows: _visible
            .map((r) => [
                  r['id'] ?? '',
                  r['name'] ?? '',
                  r['category'] ?? '',
                  r['address'] ?? '',
                  (r['is_active_admin'] == false) ? 'não' : 'sim',
                  (r['coming_soon'] == true) ? 'sim' : 'não',
                  r['coming_soon_text'] ?? '',
                ])
            .toList(),
        subject: 'Parceiros Bora ($stamp)',
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Erro ao exportar: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: BoraScreenAppBar(
        title: 'Parceiros / Restaurantes',
        actions: [
          IconButton(
            icon: const Icon(Icons.file_download_outlined),
            tooltip: 'Exportar CSV',
            onPressed: _restaurants.isEmpty ? null : _exportCsv,
          ),
          IconButton(icon: const Icon(Icons.refresh), onPressed: _load)
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(child: Text('Erro: $_error'))
              : Column(
                children: [
                  AdminComingSoonFilterBar(
                    onlyComingSoon: _onlyComingSoon,
                    total: _comingSoonCount,
                    onChanged: (v) => setState(() => _onlyComingSoon = v),
                  ),
                  Expanded(
                    child: RefreshIndicator(
                  onRefresh: _load,
                  child: _visible.isEmpty
                      ? const Center(child: Text('Sem parceiros registados'))
                      : ListView.separated(
                          padding: const EdgeInsets.all(12),
                          itemCount: _visible.length,
                          separatorBuilder: (_, __) =>
                              const SizedBox(height: 8),
                          itemBuilder: (_, i) {
                            final r = _visible[i];
                            final isActive =
                                r['is_active_admin'] as bool? ?? true;
                            final category = r['category'] as String?;
                            final comingSoon = r['coming_soon'] == true;
                            return Card(
                              shape: RoundedRectangleBorder(
                                  borderRadius:
                                      BorderRadius.circular(Radii.lg)),
                              child: ListTile(
                                leading: CircleAvatar(
                                  backgroundColor:
                                      AppColors.primary.withValues(alpha: 0.1),
                                  child: Icon(_categoryIcon(category),
                                      color: AppColors.primary),
                                ),
                                title: Row(
                                  children: [
                                    Flexible(
                                      child: Text(
                                        r['name'] as String? ?? '—',
                                        overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(
                                            fontWeight: FontWeight.w600),
                                      ),
                                    ),
                                    if (comingSoon)
                                      const AdminComingSoonBadge(),
                                  ],
                                ),
                                subtitle: Text(
                                  '${_categoryLabel(category)} · ${r['address'] as String? ?? ''}',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                trailing: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    IconButton(
                                      tooltip: 'Em breve',
                                      icon: Icon(
                                        Icons.schedule,
                                        color: comingSoon
                                            ? const Color(0xFFF97316)
                                            : AppColors.textSecondary,
                                      ),
                                      onPressed: () => _editComingSoon(r),
                                    ),
                                    Switch(
                                      value: isActive,
                                      onChanged: (_) => _toggleActive(
                                          r['id'] as String, isActive),
                                    ),
                                    const Icon(Icons.chevron_right,
                                        color: AppColors.textSecondary),
                                  ],
                                ),
                                onTap: () => Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (_) => AdminPartnerDetailScreen(
                                      restaurantId: r['id'] as String,
                                      initialName: r['name'] as String? ?? '—',
                                    ),
                                  ),
                                ).then((_) => _load()),
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

  /// Liga/desliga o "Em breve" e edita o texto do banner do cliente.
  Future<void> _editComingSoon(Map<String, dynamic> r) async {
    final changed = await showAdminComingSoonDialog(
      context: context,
      table: 'restaurants',
      id: r['id'] as String,
      name: r['name'] as String? ?? '—',
      currentValue: r['coming_soon'] == true,
      currentText: r['coming_soon_text'] as String?,
    );
    if (changed) await _load();
  }
}
