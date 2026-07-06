import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../config/app_colors.dart';
import '../config/app_spacing.dart';
import '../screens/shared/cleaning_chat_screen.dart';
import '../stores/cleaning_chat_store.dart';

/// LIMPEZA — botão de chat com badge vermelho de não-lidas + preview da
/// última mensagem (padrão visual do ChatBubbleButton do delivery, que é
/// acoplado a OrderModel — por isso replicado aqui para reservas de limpeza).
/// Liga o listener realtime da reserva enquanto está montado (refcount no
/// CleaningChatStore) para o badge atualizar ao vivo.
class CleaningChatButton extends StatefulWidget {
  const CleaningChatButton({
    super.key,
    required this.bookingId,
    required this.myRole, // 'client' | 'cleaner'
    required this.title,
    this.otherPhone,
    this.showPreview = false,
    this.compact = false,
  });

  final String bookingId;
  final String myRole;
  final String title;
  final String? otherPhone;
  final bool showPreview;
  final bool compact;

  @override
  State<CleaningChatButton> createState() => _CleaningChatButtonState();
}

class _CleaningChatButtonState extends State<CleaningChatButton> {
  @override
  void initState() {
    super.initState();
    context.read<CleaningChatStore>().listen(widget.bookingId);
  }

  @override
  void dispose() {
    context.read<CleaningChatStore>().unlisten(widget.bookingId);
    super.dispose();
  }

  void _open() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => CleaningChatScreen(
          bookingId: widget.bookingId,
          myRole: widget.myRole,
          title: widget.title,
          otherPhone: widget.otherPhone,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final store = context.watch<CleaningChatStore>();
    final unread = store.unreadFor(widget.bookingId, widget.myRole);
    final last = store.lastFor(widget.bookingId);

    final icon = Stack(
      clipBehavior: Clip.none,
      children: [
        const Icon(Icons.chat_bubble_outline, color: AppColors.primary),
        if (unread > 0)
          Positioned(
            right: -6,
            top: -6,
            child: Container(
              padding: const EdgeInsets.all(3),
              decoration: const BoxDecoration(
                color: AppColors.error,
                shape: BoxShape.circle,
              ),
              constraints: const BoxConstraints(minWidth: 16, minHeight: 16),
              child: Text(
                unread > 9 ? '9+' : '$unread',
                textAlign: TextAlign.center,
                style: const TextStyle(
                    color: Colors.white,
                    fontSize: 9,
                    fontWeight: FontWeight.w800),
              ),
            ),
          ),
      ],
    );

    if (widget.compact) {
      return IconButton(
        onPressed: _open,
        tooltip: 'Chat',
        icon: icon,
      );
    }

    return InkWell(
      borderRadius: BorderRadius.circular(Radii.md),
      onTap: _open,
      child: Container(
        padding: const EdgeInsets.all(Spacing.md),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(Radii.md),
          border: Border.all(
            color: unread > 0 ? AppColors.primary : AppColors.divider,
            width: unread > 0 ? 1.5 : 1,
          ),
        ),
        child: Row(
          children: [
            icon,
            const SizedBox(width: Spacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    unread > 0 ? 'Nova mensagem' : 'Enviar mensagem',
                    style: const TextStyle(
                        fontWeight: FontWeight.w700,
                        color: AppColors.textPrimary),
                  ),
                  if (widget.showPreview && last != null)
                    Text(
                      last.content,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          color: AppColors.textSecondary, fontSize: 12),
                    ),
                ],
              ),
            ),
            const Icon(Icons.chevron_right, color: AppColors.textSubtle),
          ],
        ),
      ),
    );
  }
}
