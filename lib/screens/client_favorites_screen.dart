import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../services/client_personalization_service.dart';
import '../widgets/bora_support_fab.dart';

/// T2.2 — Cliente favorites screen. Lista parceiros marcados como favoritos.
class ClientFavoritesScreen extends StatefulWidget {
  const ClientFavoritesScreen({super.key});
  @override
  State<ClientFavoritesScreen> createState() => _ClientFavoritesScreenState();
}

class _ClientFavoritesScreenState extends State<ClientFavoritesScreen> {
  bool _loading = true;
  List<Map<String, dynamic>> _partners = const [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final favs = await ClientPersonalizationService.instance.myFavorites();
      if (favs.isEmpty) {
        if (mounted) setState(() {
          _partners = const [];
          _loading = false;
        });
        return;
      }
      // Hydrate with partner data (vendor_name match in restaurants).
      final res = await Supabase.instance.client
          .from('restaurants')
          .select('id, name, category, photo_url')
          .inFilter('name', favs);
      if (!mounted) return;
      setState(() {
        _partners = (res as List).cast<Map<String, dynamic>>();
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Erro: $e')));
    }
  }

  Future<void> _unfavorite(String partnerId) async {
    try {
      await ClientPersonalizationService.instance.toggleFavorite(partnerId);
      await _load();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Erro: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Favoritos')),
      floatingActionButton: const BoraSupportFab(),
      body: RefreshIndicator(
        onRefresh: _load,
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : _partners.isEmpty
                ? ListView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    children: const [
                      SizedBox(height: 80),
                      Center(
                        child: Padding(
                          padding: EdgeInsets.all(24),
                          child: Text(
                            'Ainda não favoritaste nenhum parceiro.\n'
                            'Toca na ⭐ no ecrã de cada loja.',
                            textAlign: TextAlign.center,
                            style: TextStyle(color: Colors.black54),
                          ),
                        ),
                      ),
                    ],
                  )
                : ListView.builder(
                    physics: const AlwaysScrollableScrollPhysics(),
                    itemCount: _partners.length,
                    itemBuilder: (_, i) {
                      final p = _partners[i];
                      return Card(
                        child: ListTile(
                          leading: p['photo_url'] != null
                              ? CircleAvatar(
                                  backgroundImage:
                                      NetworkImage(p['photo_url'] as String))
                              : const CircleAvatar(child: Icon(Icons.store)),
                          title: Text(p['name'] as String? ?? '—'),
                          subtitle: Text(p['category'] as String? ?? ''),
                          trailing: IconButton(
                            icon: const Icon(Icons.star, color: Colors.amber),
                            onPressed: () =>
                                _unfavorite(p['name'] as String),
                          ),
                        ),
                      );
                    },
                  ),
      ),
    );
  }
}
