import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Persists a set of favourite product/restaurant IDs across sessions.
class FavoriteStore extends ChangeNotifier {
  static const _kKey = 'bora_favorites_v1';

  final Set<String> _ids = {};

  FavoriteStore() {
    _load();
  }

  bool isFavorite(String id) => _ids.contains(id);

  void toggle(String id) {
    if (_ids.contains(id)) {
      _ids.remove(id);
    } else {
      _ids.add(id);
    }
    notifyListeners();
    _save();
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
