import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../config/app_colors.dart';

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
          .select('id, name, category, address, is_active')
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
    try {
      await Supabase.instance.client
          .from('restaurants')
          .update({'is_active': !currentActive}).eq('id', id);
      _load();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Erro: $e')));
      }
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
                            final isActive = r['is_active'] as bool? ?? true;
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
                                trailing: Switch(
                                  value: isActive,
                                  onChanged: (_) => _toggleActive(
                                      r['id'] as String, isActive),
                                ),
                              ),
                            );
                          },
                        ),
                ),
    );
  }
}
