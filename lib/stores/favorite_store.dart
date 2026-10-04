import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Persists a set of favourite product/restaurant IDs across sessions.
///
/// Lojas favoritas (04/10/2026): guardadas pelo **id da loja** (chave
/// `store_<id>`), nunca pelo nome — o nome muda e duas lojas podem ter o
/// mesmo nome. Além do aparelho, ficam também na conta do cliente
/// (`client_favorites`, RPC `client_toggle_favorite`), para aparecerem noutro
/// telemóvel e no ecrã "Favoritos" do perfil.
class FavoriteStore extends ChangeNotifier {
  static const _kKey = 'bora_favorites_v1';

  /// Prefixo das lojas favoritas (o resto da chave é o `restaurants.id`).
  static const String storePrefix = 'store_';

  /// Prefixo antigo, por NOME (`restaurant_<nome>`). Só se lê para migrar.
  static const String legacyStorePrefix = 'restaurant_';

  static String storeKey(String restaurantId) => '$storePrefix$restaurantId';

  final Set<String> _ids = {};

  FavoriteStore() {
    _load();
  }

  bool isFavorite(String id) => _ids.contains(id);

  bool isFavoriteStore(String restaurantId) =>
      _ids.contains(storeKey(restaurantId));

  /// Ids das lojas favoritas (sem prefixo).
  List<String> get favoriteStoreIds => _ids
      .where((k) => k.startsWith(storePrefix))
      .map((k) => k.substring(storePrefix.length))
      .toList();

  /// Nomes guardados no formato antigo (`restaurant_<nome>`) por migrar.
  List<String> get legacyStoreNames => _ids
      .where((k) => k.startsWith(legacyStorePrefix))
      .map((k) => k.substring(legacyStorePrefix.length))
      .toList();

  void toggle(String id) {
    if (_ids.contains(id)) {
      _ids.remove(id);
    } else {
      _ids.add(id);
    }
    notifyListeners();
    _save();
  }

  /// Liga/desliga uma loja dos favoritos (aparelho + conta).
  void toggleStore(String restaurantId) {
    final key = storeKey(restaurantId);
    toggle(key);
    // ignore: discarded_futures
    _syncStoreToServer(restaurantId, _ids.contains(key));
  }

  /// Troca as chaves antigas por nome pelas novas por id.
  /// [nameToId] vem da tabela `restaurants`; nomes sem correspondência
  /// ficam como estão (não se perde nada).
  void migrateLegacyStores(Map<String, String> nameToId) {
    var changed = false;
    for (final entry in nameToId.entries) {
      final legacy = '$legacyStorePrefix${entry.key}';
      if (_ids.remove(legacy)) {
        changed = true;
        final key = storeKey(entry.value);
        if (_ids.add(key)) {
          // ignore: discarded_futures
          _syncStoreToServer(entry.value, true);
        }
      }
    }
    if (changed) {
      notifyListeners();
      _save();
    }
  }

  /// Junta ao aparelho as lojas favoritas guardadas na conta.
  Future<void> loadStoresFromServer() async {
    try {
      final client = Supabase.instance.client;
      if (client.auth.currentUser == null) return;
      final rows = await client.from('client_favorites').select('partner_id');
      var changed = false;
      for (final r in rows as List) {
        final id = (r as Map)['partner_id'] as String?;
        if (id == null || id.isEmpty) continue;
        if (_ids.add(storeKey(id))) changed = true;
      }
      if (changed) {
        notifyListeners();
        await _save();
      }
    } catch (e) {
      debugPrint('FavoriteStore.loadStoresFromServer error: $e');
    }
  }

  Future<void> _syncStoreToServer(String restaurantId, bool wanted) async {
    try {
      final client = Supabase.instance.client;
      if (client.auth.currentUser == null) return;
      // A RPC é um "alternar": se a conta já estiver no estado pedido,
      // alterna duas vezes para não desfazer o que o cliente escolheu.
      final res = await client.rpc('client_toggle_favorite',
          params: {'p_partner_id': restaurantId});
      final now = (res is Map ? res['favorited'] : null) == true;
      if (now != wanted) {
        await client.rpc('client_toggle_favorite',
            params: {'p_partner_id': restaurantId});
      }
    } catch (e) {
      debugPrint('FavoriteStore._syncStoreToServer error: $e');
    }
  }

  Future<void> _save() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setStringList(_kKey, _ids.toList());
    } catch (e) {
      debugPrint('FavoriteStore._save error: $e');
    }
  }

  Future<void> _load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final list = prefs.getStringList(_kKey) ?? [];
      _ids.addAll(list);
      notifyListeners();
    } catch (e) {
      debugPrint('FavoriteStore._load error: $e');
    }
  }
}
