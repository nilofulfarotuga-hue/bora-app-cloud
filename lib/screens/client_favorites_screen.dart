import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../config/app_colors.dart';
import '../l10n/tr.dart';
import '../stores/favorite_store.dart';
import '../widgets/bora/bora_screen_app_bar.dart';
import '../widgets/bora_support_fab.dart';
import 'deep_link_store_screen.dart';

/// Lojas favoritas do cliente (04/10/2026).
///
/// A fonte é o [FavoriteStore] — o mesmo ♥ que aparece na lista de lojas e
/// no cabeçalho de cada loja — guardado pelo **id** da loja. Ao abrir, junta
/// os favoritos guardados na conta e converte os antigos (gravados por nome).
class ClientFavoritesScreen extends StatefulWidget {
  const ClientFavoritesScreen({super.key});
  @override
  State<ClientFavoritesScreen> createState() => _ClientFavoritesScreenState();
}

class _ClientFavoritesScreenState extends State<ClientFavoritesScreen> {
  bool _loading = true;
  bool _failed = false;
  List<Map<String, dynamic>> _stores = const [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _failed = false;
    });
    final favs = context.read<FavoriteStore>();
    try {
      await favs.loadStoresFromServer();
      final client = Supabase.instance.client;

      // Favoritos antigos guardados por nome → passam a ser por id.
      final legacy = favs.legacyStoreNames;
      if (legacy.isNotEmpty) {
        final rows = await client
            .from('restaurants')
            .select('id, name')
            .inFilter('name', legacy);
        final map = <String, String>{};
        for (final r in rows as List) {
          final m = r as Map;
          map[m['name'] as String] = m['id'] as String;
        }
        favs.migrateLegacyStores(map);
      }

      final ids = favs.favoriteStoreIds;
      if (ids.isEmpty) {
        if (!mounted) return;
        setState(() {
          _stores = const [];
          _loading = false;
        });
        return;
      }
      final res = await client
          .from('restaurants')
          .select('id, name, category, photo_url')
          .inFilter('id', ids);
      if (!mounted) return;
      setState(() {
        _stores = (res as List).cast<Map<String, dynamic>>();
        _loading = false;
      });
    } catch (e) {
      debugPrint('[ClientFavoritesScreen] load error: $e');
      if (!mounted) return;
      setState(() {
        _loading = false;
        _failed = true;
      });
    }
  }

  void _unfavorite(String id) {
    context.read<FavoriteStore>().toggleStore(id);
    setState(() {
      _stores = _stores.where((s) => s['id'] != id).toList();
    });
  }

  void _open(String id) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => DeepLinkStoreScreen(tipo: 'loja', id: id),
      ),
    );
  }

  Widget _message(String text, {bool retry = false}) {
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      children: [
        const SizedBox(height: 80),
        Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            text,
            textAlign: TextAlign.center,
            style: const TextStyle(color: AppColors.textSecondary),
          ),
        ),
        if (retry)
          Center(
            child: OutlinedButton.icon(
              onPressed: _load,
              icon: const Icon(Icons.refresh),
              label: Text('Tentar outra vez'.tr),
            ),
          ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final Widget body;
    if (_loading) {
      body = const Center(child: CircularProgressIndicator());
    } else if (_failed) {
      body = _message(
        'Não foi possível carregar os teus favoritos.'.tr,
        retry: true,
      );
    } else if (_stores.isEmpty) {
      body = _message(
        'Ainda não tens lojas favoritas.\nToca no ♥ de uma loja para a guardar aqui.'
            .tr,
      );
    } else {
      body = ListView.builder(
        physics: const AlwaysScrollableScrollPhysics(),
        itemCount: _stores.length,
        itemBuilder: (_, i) {
          final p = _stores[i];
          final id = p['id'] as String;
          final photo = p['photo_url'] as String?;
          return Card(
            child: ListTile(
              onTap: () => _open(id),
              leading: photo != null && photo.isNotEmpty
                  ? CircleAvatar(backgroundImage: NetworkImage(photo))
                  : const CircleAvatar(child: Icon(Icons.store)),
              title: Text(p['name'] as String? ?? '—'),
              trailing: IconButton(
                tooltip: 'Tirar dos favoritos'.tr,
                icon: const Icon(Icons.favorite, color: AppColors.error),
                onPressed: () => _unfavorite(id),
              ),
            ),
          );
        },
      );
    }
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: BoraScreenAppBar(title: 'Favoritos'.tr),
      floatingActionButton: const BoraSupportFab(),
      body: RefreshIndicator(onRefresh: _load, child: body),
    );
  }
}
