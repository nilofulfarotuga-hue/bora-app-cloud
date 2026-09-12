import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// T2.3 — In-app notifications wrapper.
class InAppNotificationsService {
  InAppNotificationsService._();
  static final instance = InAppNotificationsService._();

  final _supa = Supabase.instance.client;

  Future<int> unreadCount() async {
    try {
      final res = await _supa.rpc('client_unread_notifications_count');
      return (res as num?)?.toInt() ?? 0;
    } catch (e) {
      debugPrint('[InAppNotif] unread error: $e');
      return 0;
    }
  }

  Future<List<Map<String, dynamic>>> list({int limit = 50}) async {
    try {
      final res = await _supa
          .rpc('client_list_notifications', params: {'p_limit': limit});
      return (res as List).cast<Map<String, dynamic>>();
    } catch (e) {
      debugPrint('[InAppNotif] list error: $e');
      return const [];
    }
  }

  Future<void> markRead(String id) async {
    await _supa.rpc('client_mark_notification_read', params: {'p_id': id});
  }

  Future<int> markAllRead() async {
    final res = await _supa.rpc('client_mark_all_notifications_read');
    return (res as num?)?.toInt() ?? 0;
  }
}
