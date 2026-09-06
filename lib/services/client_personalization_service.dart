import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// T2.2 — Search history + favoritos cliente (RPC wrappers).
class ClientPersonalizationService {
  ClientPersonalizationService._();
  static final instance = ClientPersonalizationService._();

  final _supa = Supabase.instance.client;

  Future<void> logSearch(String query) async {
    if (query.trim().isEmpty) return;
    try {
      await _supa.rpc('client_log_search', params: {'p_query': query});
    } catch (e) {
      debugPrint('[ClientPersonalization] logSearch error: $e');
    }
  }

  Future<List<String>> recentSearches({int limit = 10}) async {
    try {
      final res = await _supa
          .from('client_search_history')
          .select('query')
          .order('searched_at', ascending: false)
          .limit(limit);
      return (res as List).map((e) => (e as Map)['query'] as String).toList();
    } catch (e) {
      debugPrint('[ClientPersonalization] recentSearches error: $e');
      return const [];
    }
  }

  Future<bool> toggleFavorite(String partnerId) async {
    final res = await _supa
        .rpc('client_toggle_favorite', params: {'p_partner_id': partnerId});
    return (res as Map)['favorited'] as bool;
  }

  Future<List<String>> myFavorites() async {
    try {
      final res = await _supa
          .from('client_favorites')
          .select('partner_id')
          .order('added_at', ascending: false);
      return (res as List).map((e) => (e as Map)['partner_id'] as String).toList();
    } catch (e) {
      debugPrint('[ClientPersonalization] myFavorites error: $e');
      return const [];
    }
  }

  Future<bool> isFavorite(String partnerId) async {
    try {
      final res = await _supa
          .from('client_favorites')
          .select('partner_id')
          .eq('partner_id', partnerId)
          .maybeSingle();
      return res != null;
    } catch (_) {
      return false;
    }
  }
}
