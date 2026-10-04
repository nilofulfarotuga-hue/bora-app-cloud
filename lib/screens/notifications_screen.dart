import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../config/app_colors.dart';
import '../config/app_spacing.dart';
import '../models/order_model.dart';
import '../services/in_app_notifications_service.dart';
import '../stores/order_store.dart';
import '../widgets/bora/lista_estado.dart';
import '../widgets/bora_support_fab.dart';
import '../widgets/bora/bora_screen_app_bar.dart';
import 'order_details_screen.dart';

import '../l10n/tr.dart';

/// T2.3 — Lista de in-app notifications cliente.
class NotificationsScreen extends StatefulWidget {
  const NotificationsScreen({super.key});
  @override
  State<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends State<NotificationsScreen> {
  bool _loading = true;
  bool _failed = false;
  List<Map<String, dynamic>> _items = const [];

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
    try {
      final items = await InAppNotificationsService.instance.listOrThrow();
      if (!mounted) return;
      setState(() {
        _items = items;
        _loading = false;
      });
    } catch (e) {
      debugPrint('[NotificationsScreen] load error: $e');
      if (!mounted) return;
      setState(() {
        _loading = false;
        _failed = true;
      });
    }
  }

  Future<void> _markAll() async {
    try {
      await InAppNotificationsService.instance.markAllRead();
    } catch (e) {
      debugPrint('[NotificationsScreen] markAll error: $e');
    }
    if (!mounted) return;
    await _load();
  }

  /// Toque numa notificação: marca como lida e, se for de um pedido, abre o
  /// pedido (padrão Glovo/Uber Eats).
  Future<void> _open(Map<String, dynamic> n) async {
    if (n['read_at'] == null) {
      try {
        await InAppNotificationsService.instance.markRead(n['id'] as String);
      } catch (e) {
        debugPrint('[NotificationsScreen] markRead error: $e');
      }
    }
    if (!mounted) return;
    final order = await _orderFor(n['related_id'] as String?);
    if (!mounted) return;
    if (order != null) {
      await Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => OrderDetailsScreen(order: order)),
      );
      if (!mounted) return;
    }
    await _load();
  }

  Future<OrderModel?> _orderFor(String? relatedId) async {
    if (relatedId == null || relatedId.isEmpty) return null;
    for (final o in context.read<OrderStore>().orders) {
      if (o.id == relatedId) return o;
    }
    try {
      final row = await Supabase.instance.client
          .from('orders')
          .select()
          .eq('id', relatedId)
          .maybeSingle();
      return row == null ? null : OrderModel.fromSupabase(row);
    } catch (_) {
      // Não é um pedido (marcação, limpeza, campanha…) — fica só lida.
      return null;
    }
  }

  IconData _iconFor(String kind) {
    switch (kind) {
      case 'cashback':
        return Icons.celebration;
      case 'cancellation':
        return Icons.cancel_outlined;
      case 'refund':
        return Icons.replay;
      case 'referral':
        return Icons.card_giftcard;
      case 'promo':
        return Icons.local_offer;
      case 'admin':
        return Icons.campaign;
      default:
        return Icons.notifications;
    }
  }

  @override
  Widget build(BuildContext context) {
    final unreadCount = _items.where((n) => n['read_at'] == null).length;
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: BoraScreenAppBar(
        title: 'Notificações'.tr,
        actions: [
          if (unreadCount > 0)
            TextButton(
              onPressed: _markAll,
              child: Text('Marcar todas'.tr,
                  style: const TextStyle(color: Colors.white)),
            ),
        ],
      ),
      floatingActionButton: const BoraSupportFab(),
      body: RefreshIndicator(
        onRefresh: _load,
        child: _loading
            ? const ListaACarregar()
            : _failed
                ? ListView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    children: [
                      const SizedBox(height: 80),
                      ListaComErro(onRetry: _load),
                    ],
                  )
            : _items.isEmpty
                ? ListView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    children: [
                      const SizedBox(height: 80),
                      Center(
                          child: Text('Sem notificações.'.tr,
                              style: const TextStyle(color: AppColors.textSecondary))),
                    ],
                  )
                : ListView.builder(
                    physics: const AlwaysScrollableScrollPhysics(),
                    itemCount: _items.length,
                    itemBuilder: (_, i) {
                      final n = _items[i];
                      final unread = n['read_at'] == null;
                      return Container(
                        margin: const EdgeInsets.symmetric(
                            horizontal: Spacing.md, vertical: Spacing.xs),
                        decoration: BoxDecoration(
                          color: unread
                              ? AppColors.primaryLight
                              : AppColors.surface,
                          borderRadius: BorderRadius.circular(Radii.lg),
                          boxShadow: AppColors.shadowCard,
                        ),
                        child: ListTile(
                          leading: Icon(_iconFor(n['kind'] as String? ?? ''),
                              color: AppColors.primary),
                          title: Text(n['title'] as String? ?? '',
                              style: TextStyle(
                                  color: AppColors.textPrimary,
                                  fontWeight: unread
                                      ? FontWeight.bold
                                      : FontWeight.normal)),
                          subtitle: Text(n['body'] as String? ?? '',
                              style: const TextStyle(
                                  color: AppColors.textSecondary)),
                          trailing: unread
                              ? Container(
                                  width: 10,
                                  height: 10,
                                  decoration: const BoxDecoration(
                                      color: AppColors.error,
                                      shape: BoxShape.circle))
                              : null,
                          onTap: () => _open(n),
                        ),
                      );
                    },
                  ),
      ),
    );
  }
}
