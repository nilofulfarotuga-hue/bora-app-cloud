import 'dart:async';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../config/app_colors.dart';
import '../../services/admin_audit_service.dart';
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
          .select('id, name, category, address, is_active_admin')
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
            newActive ? AppColors.primary : Colors.orange.shade700,
        duration: const Duration(seconds: 2),
      ));
      await _load();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('Falhou actualizar parceiro: $e'),
        backgroundColor: Colors.red,
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
    };
    return labels[cat] ?? (cat ?? '—');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Parceiros / Restaurantes'),
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
                  child: _restaurants.isEmpty
                      ? const Center(child: Text('Sem parceiros registados'))
                      : ListView.separated(
                          padding: const EdgeInsets.all(12),
                          itemCount: _restaurants.length,
                          separatorBuilder: (_, __) =>
                              const SizedBox(height: 8),
                          itemBuilder: (_, i) {
                            final r = _restaurants[i];
                            final isActive =
                                r['is_active_admin'] as bool? ?? true;
                            final category = r['category'] as String?;
                            return Card(
                              child: ListTile(
                                leading: CircleAvatar(
                                  backgroundColor:
                                      AppColors.primary.withValues(alpha: 0.1),
                                  child: Icon(_categoryIcon(category),
                                      color: AppColors.primary),
                                ),
                                title: Text(
                                  r['name'] as String? ?? '—',
                                  style: const TextStyle(
                                      fontWeight: FontWeight.w600),
                                ),
                                subtitle: Text(
                                  '${_categoryLabel(category)} · ${r['address'] as String? ?? ''}',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                trailing: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Switch(
                                      value: isActive,
                                      onChanged: (_) => _toggleActive(
                                          r['id'] as String, isActive),
                                    ),
                                    const Icon(Icons.chevron_right, color: Colors.grey),
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
    );
  }
}
