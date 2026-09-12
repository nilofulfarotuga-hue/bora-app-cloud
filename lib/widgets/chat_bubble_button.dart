import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../config/app_colors.dart';
import '../models/chat_message.dart';
import '../models/order_model.dart';
import '../screens/chat_screen.dart';

/// M11 — Botão de chat com badge VERMELHO de não-lidas (padrão Glovo/Uber).
///
/// Subscreve as `messages` do pedido em realtime e conta as mensagens do
/// interlocutor ([chatTarget]) ainda não lidas (`read=false`). Ao tocar abre o
/// [ChatScreen], que marca as mensagens como lidas (RPC `chat_mark_read`) —
/// o badge zera sozinho via realtime.
///
/// Duas variantes:
///  • `compact: true`  → IconButton com badge (dashboards/parceiro);
///  • `compact: false` → botão largo com label + badge e, opcionalmente,
///    pré-visualização de 1 linha da última mensagem ([showPreview]).
class ChatBubbleButton extends StatefulWidget {
  const ChatBubbleButton({
    super.key,
    required this.order,
    required this.senderType,
    required this.chatTarget,
    this.label,
    this.compact = false,
    this.showPreview = false,
  });

  final OrderModel order;
  final ChatSenderType senderType;
  final ChatTarget chatTarget;
  final String? label;
  final bool compact;
  final bool showPreview;

  @override
  State<ChatBubbleButton> createState() => _ChatBubbleButtonState();
}

class _ChatBubbleButtonState extends State<ChatBubbleButton> {
  Stream<List<Map<String, dynamic>>>? _stream;

  String get _targetRole => widget.chatTarget.name;
  String get _myRole => widget.senderType.name;

  String? get _conversationType => resolveConversationType(
      widget.senderType, widget.order.status, widget.chatTarget);

  @override
  void initState() {
    super.initState();
    _stream = Supabase.instance.client
        .from('messages')
        .stream(primaryKey: ['id'])
        .eq('order_id', widget.order.id)
        .order('created_at', ascending: true);
  }

  void _openChat() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ChatScreen(
          order: widget.order,
          senderType: widget.senderType,
          chatTarget: widget.chatTarget,
          conversationType: _conversationType,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<Map<String, dynamic>>>(
      stream: _stream,
      builder: (context, snap) {
        final rows = snap.data ?? const <Map<String, dynamic>>[];
        final conv = _conversationType;
        final relevant = rows.where((m) {
          final mConv = m['conversation_type'] as String?;
          return conv == null || mConv == null || mConv == conv;
        }).toList();
        final unread = relevant
            .where((m) => m['sender_type'] == _targetRole && m['read'] != true)
            .length;
        final String? preview = widget.showPreview && relevant.isNotEmpty
            ? (relevant.last['message'] as String?)
            : null;

        if (widget.compact) {
          return Stack(
            clipBehavior: Clip.none,
            children: [
              IconButton(
                icon: const Icon(Icons.chat_bubble_outline, size: 20),
                tooltip: widget.label ?? 'Chat',
                onPressed: _openChat,
              ),
              if (unread > 0)
                Positioned(
                  right: 4,
                  top: 2,
                  child: _Badge(count: unread),
                ),
            ],
          );
        }

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            OutlinedButton.icon(
              onPressed: _openChat,
              icon: Stack(
                clipBehavior: Clip.none,
                children: [
                  const Icon(Icons.chat_bubble_outline, size: 18),
                  if (unread > 0)
                    Positioned(
                      right: -7,
                      top: -7,
                      child: _Badge(count: unread),
                    ),
                ],
              ),
              label: Text(
                widget.label ?? 'Chat',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            if (preview != null && preview.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 2, left: 4),
                child: Text(
                  preview,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 12,
                    color: AppColors.textSecondary,
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}

class _Badge extends StatelessWidget {
  const _Badge({required this.count});
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
