import 'dart:async';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../config/app_colors.dart';
import '../models/chat_message.dart';
import '../models/order_model.dart';
import '../screens/chat_screen.dart';

/// Parte C (2026-06-12) — acesso de chat do ESTAFETA com seletor de
/// destinatário (regra de negócio):
///  • pedido NÃO-parceiro (mercados, Wells, Leroy...): só existe o par
///    estafeta↔cliente — abre direto, sem chat com a loja;
///  • pedido parceiro: o estafeta escolhe Cliente ou Restaurante — threads
///    separadas por par (conversation_type), nunca misturadas.
Future<void> openDriverChat(BuildContext context, OrderModel order,
    {int unreadClient = 0, int unreadPartner = 0}) async {
  if (!order.isPartnerStore) {
    _pushChat(context, order, ChatTarget.client);
    return;
  }
  final target = await showModalBottomSheet<ChatTarget>(
    context: context,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
    ),
    builder: (ctx) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 14, 16, 4),
            child: Text(
              'Falar com…',
              style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
            ),
          ),
          _TargetTile(
            icon: Icons.person_outline,
            label: 'Cliente',
            unread: unreadClient,
            onTap: () => Navigator.pop(ctx, ChatTarget.client),
          ),
          _TargetTile(
            icon: Icons.storefront_outlined,
            label: 'Restaurante',
            unread: unreadPartner,
            onTap: () => Navigator.pop(ctx, ChatTarget.partner),
          ),
          const SizedBox(height: 8),
        ],
      ),
    ),
  );
  if (target != null && context.mounted) {
    _pushChat(context, order, target);
  }
}

void _pushChat(BuildContext context, OrderModel order, ChatTarget target) {
  Navigator.push(
    context,
    MaterialPageRoute<void>(
      builder: (_) => ChatScreen(
        order: order,
        senderType: ChatSenderType.driver,
        chatTarget: target,
        conversationType: resolveConversationType(
            ChatSenderType.driver, order.status, target),
      ),
    ),
  );
}

class _TargetTile extends StatelessWidget {
  const _TargetTile({
    required this.icon,
    required this.label,
    required this.unread,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final int unread;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: Icon(icon, color: AppColors.primary),
      title: Text(label),
      trailing: unread > 0 ? UnreadBadge(count: unread) : null,
      onTap: onTap,
    );
  }
}

/// Botão de chat FLUTUANTE no mapa do pedido ativo — sempre visível, com
/// badge VERMELHO de não-lidas em realtime (padrão Glovo/Uber). O contador
/// zera quando o ChatScreen marca lidas via RPC `chat_mark_read`.
class DriverChatFab extends StatefulWidget {
  const DriverChatFab({super.key, required this.order});

  final OrderModel order;

  @override
  State<DriverChatFab> createState() => _DriverChatFabState();
}

class _DriverChatFabState extends State<DriverChatFab> {
  Stream<List<Map<String, dynamic>>>? _stream;

  @override
  void initState() {
    super.initState();
    _subscribe();
  }

  @override
  void didUpdateWidget(DriverChatFab oldWidget) {
    super.didUpdateWidget(oldWidget);
    // focusOrder pode mudar com stacking — re-subscrever ao pedido certo.
    if (oldWidget.order.id != widget.order.id) _subscribe();
  }

  void _subscribe() {
    _stream = Supabase.instance.client
        .from('messages')
        .stream(primaryKey: ['id'])
        .eq('order_id', widget.order.id)
        .order('created_at', ascending: true);
  }

  bool _convMatch(Map<String, dynamic> m, String conv) {
    final c = m['conversation_type'] as String?;
    return c == null || c == conv;
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<Map<String, dynamic>>>(
      stream: _stream,
      builder: (context, snap) {
        final rows = snap.data ?? const <Map<String, dynamic>>[];
        final unreadClient = rows
            .where((m) =>
                m['sender_type'] == 'client' &&
                m['read'] != true &&
                _convMatch(m, 'client_driver'))
            .length;
        final unreadPartner = widget.order.isPartnerStore
            ? rows
                .where((m) =>
                    m['sender_type'] == 'partner' &&
                    m['read'] != true &&
                    _convMatch(m, 'driver_partner'))
                .length
            : 0;
        final unread = unreadClient + unreadPartner;

        return Stack(
          clipBehavior: Clip.none,
          children: [
            Semantics(
              label: 'Chat do pedido',
              button: true,
              child: FloatingActionButton.small(
                heroTag: 'map_chat_btn_driver',
                backgroundColor: AppColors.primary,
                foregroundColor: Colors.white,
                onPressed: () => openDriverChat(
                  context,
                  widget.order,
                  unreadClient: unreadClient,
                  unreadPartner: unreadPartner,
                ),
                child: const Icon(Icons.chat_bubble_outline),
              ),
            ),
            if (unread > 0)
              Positioned(
                right: -2,
                top: -2,
                child: UnreadBadge(count: unread),
              ),
          ],
        );
      },
    );
  }
}

/// Badge vermelho de contagem (1, 2, 3… / 9+) — mesmo visual do M11.
class UnreadBadge extends StatelessWidget {
  const UnreadBadge({super.key, required this.count});

  final int count;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
      constraints: const BoxConstraints(minWidth: 16, minHeight: 16),
      decoration: BoxDecoration(
        color: AppColors.error,
        borderRadius: BorderRadius.circular(9),
      ),
      alignment: Alignment.center,
      child: Text(
        count > 9 ? '9+' : '$count',
        style: const TextStyle(
          color: Colors.white,
          fontSize: 10,
          fontWeight: FontWeight.w800,
          height: 1.0,
        ),
      ),
    );
  }
}
