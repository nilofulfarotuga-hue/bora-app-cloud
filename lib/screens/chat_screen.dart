import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import '../config/app_colors.dart';
import '../models/chat_message.dart';
import '../models/message_model.dart';
import '../models/order_model.dart';
import '../stores/chat_store.dart';
import '../stores/order_store.dart';
import '../stores/restaurant_store.dart';
import '../widgets/bora/bora_screen_app_bar.dart';

enum ChatTarget { client, driver, partner }

/// Returns the conversation channel for a ChatScreen invocation.
/// Returns null when channel cannot be determined (legacy / all messages shown).
/// M11: chatTarget explícito tem prioridade para TODOS os senders — permite os
/// 2 acessos do padrão Uber Eats (cliente↔parceiro E cliente↔estafeta).
String? resolveConversationType(
  ChatSenderType senderType,
  OrderStatus status,
  ChatTarget? chatTarget,
) {
  return switch (senderType) {
    ChatSenderType.client => switch (chatTarget) {
      ChatTarget.partner => 'client_partner',
      ChatTarget.driver  => 'client_driver',
      _ => switch (status) {
        OrderStatus.preparing          => 'client_partner',
        OrderStatus.pickedUp ||
        OrderStatus.onTheWay           => 'client_driver',
        _                              => null,
      },
    },
    ChatSenderType.driver => switch (chatTarget) {
      ChatTarget.partner => 'driver_partner',
      ChatTarget.client  => 'client_driver',
      _ => switch (status) {
        OrderStatus.driverAccepted     => 'driver_partner',
        OrderStatus.pickedUp ||
        OrderStatus.onTheWay           => 'client_driver',
        _                              => null,
      },
    },
    ChatSenderType.partner => switch (chatTarget) {
      ChatTarget.client => 'client_partner',
      ChatTarget.driver => 'driver_partner',
      _                 => null,
    },
  };
}

class ChatScreen extends StatefulWidget {
  const ChatScreen({
    super.key,
    required this.order,
    required this.senderType,
    this.chatTarget,
    this.conversationType,
  });

  final OrderModel order;
  final ChatSenderType senderType;
  final ChatTarget? chatTarget;

  /// 'client_partner', 'client_driver', or 'driver_partner'.
  /// Null = show all messages (legacy / no channel filtering).
  final String? conversationType;

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final TextEditingController _msgCtrl = TextEditingController();
  final ScrollController _scrollCtrl = ScrollController();

  String get _senderRole => switch (widget.senderType) {
    ChatSenderType.client  => 'client',
    ChatSenderType.driver  => 'driver',
    ChatSenderType.partner => 'partner',
  };

  String get _senderId {
    final o = widget.order;
    return switch (widget.senderType) {
      ChatSenderType.client  => o.clientPhone ?? 'client_${o.id}',
      ChatSenderType.driver  => o.assignedDriverId ?? 'driver_${o.id}',
      ChatSenderType.partner =>
          Supabase.instance.client.auth.currentUser?.id ?? 'partner_${o.id}',
    };
  }

  DateTime _lastMarkRead = DateTime.fromMillisecondsSinceEpoch(0);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<ChatStore>().listen(widget.order.id);
      _markRead();
    });
  }

  /// M11: marca as mensagens dos outros como lidas (badge zera). Throttled —
  /// chamado ao abrir e sempre que chegam mensagens novas com o ecrã aberto.
  void _markRead() {
    final now = DateTime.now();
    if (now.difference(_lastMarkRead).inSeconds < 2) return;
    _lastMarkRead = now;
    Supabase.instance.client.rpc('chat_mark_read', params: {
      'p_order_id': widget.order.id,
      'p_reader_type': _senderRole,
    }).then((_) {}, onError: (_) {});
  }

  @override
  void dispose() {
    _msgCtrl.dispose();
    _scrollCtrl.dispose();
    super.dispose();
  }

  String? _resolveCallPhone(BuildContext context, OrderModel o) {
    final restaurantPhone = context
        .read<RestaurantStore>()
        .restaurantByName(o.vendorName)
        ?.phone;
    return switch (widget.senderType) {
      ChatSenderType.client => switch (o.status) {
        OrderStatus.preparing            => restaurantPhone,
        OrderStatus.pickedUp ||
        OrderStatus.onTheWay             => o.driverPhone,
        _                                => null,
      },
      ChatSenderType.driver => switch (o.status) {
        OrderStatus.driverAccepted       => restaurantPhone,
        OrderStatus.pickedUp ||
        OrderStatus.onTheWay             => o.clientPhone,
        _                                => null,
      },
      ChatSenderType.partner => switch (widget.chatTarget) {
        ChatTarget.client => o.clientPhone,
        ChatTarget.driver => o.driverPhone,
        _                 => null,
      },
    };
  }

  String _appBarTitle(OrderModel o) {
    final vendor = o.vendorName ?? 'Pedido';
    return switch (widget.senderType) {
      ChatSenderType.client  => widget.chatTarget == ChatTarget.partner
          ? 'Chat c/ Restaurante · $vendor'
          : 'Chat c/ Estafeta · $vendor',
      ChatSenderType.driver  => widget.chatTarget == ChatTarget.partner
          ? 'Chat c/ Restaurante · $vendor'
          : 'Chat c/ Cliente · $vendor',
      ChatSenderType.partner => switch (widget.chatTarget) {
        ChatTarget.client => 'Chat c/ Cliente · $vendor',
        ChatTarget.driver => 'Chat c/ Estafeta · $vendor',
        _                 => 'Chat · $vendor',
      },
    };
  }

  @override
  Widget build(BuildContext context) {
    final chatStore = context.watch<ChatStore>();
    final orderStore = context.watch<OrderStore>();
    final liveOrder = orderStore.orders.firstWhere(
      (o) => o.id == widget.order.id,
      orElse: () => widget.order,
    );
    final messages = chatStore
        .messagesForOrder(widget.order.id)
        .where((m) =>
            widget.conversationType == null ||
            m.conversationType == null ||
            m.conversationType == widget.conversationType)
        .toList();

    // M11: mensagens novas dos outros enquanto o ecrã está aberto → marcar
    // lidas (throttled em _markRead) para o badge dos outros ecrãs zerar.
    if (messages.any((m) => m.senderRole != _senderRole && !m.read)) {
      _markRead();
    }

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollCtrl.hasClients && messages.isNotEmpty) {
        _scrollCtrl.animateTo(
          _scrollCtrl.position.maxScrollExtent,
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeOut,
        );
      }
    });

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: BoraScreenAppBar(
        title: _appBarTitle(liveOrder),
        actions: [
          Builder(
            builder: (ctx) {
              final phone = _resolveCallPhone(ctx, liveOrder);
              if (phone == null || phone.isEmpty) return const SizedBox.shrink();
              return IconButton(
                icon: const Icon(Icons.phone),
                tooltip: 'Ligar',
                onPressed: () async {
                  final uri = Uri(scheme: 'tel', path: phone);
                  if (await canLaunchUrl(uri)) {
                    await launchUrl(uri, mode: LaunchMode.externalApplication);
                  }
                },
              );
            },
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: messages.isEmpty
                ? const Center(
                    child: Text(
                      'Sem mensagens. Seja o primeiro a escrever!',
                      style: TextStyle(color: AppColors.textSecondary),
                    ),
                  )
                : ListView.builder(
                    controller: _scrollCtrl,
                    padding: const EdgeInsets.all(16),
                    itemCount: messages.length,
                    itemBuilder: (context, index) {
                      final msg = messages[index];
                      final isMine = msg.senderRole == _senderRole;

                      if (msg.type == MessageType.substitution) {
                        return _SubstitutionCard(
                          message: msg,
                          isClient: widget.senderType == ChatSenderType.client,
                          order: liveOrder,
                          onApprove: () =>
                              _respond(orderStore, liveOrder, msg, true),
                          onReject: () =>
                              _respond(orderStore, liveOrder, msg, false),
                        );
                      }

                      return _TextBubble(message: msg, isMine: isMine);
                    },
                  ),
          ),
          const Divider(height: 1, color: AppColors.divider),
          SafeArea(
            top: false,
            minimum: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: Row(
              children: [
                if (widget.senderType == ChatSenderType.driver)
                  IconButton(
                    icon: const Icon(Icons.swap_horiz),
                    tooltip: 'Propor substituição',
                    onPressed: () => _showSubstitutionDialog(context),
                  ),
                Expanded(
                  child: TextField(
                    controller: _msgCtrl,
                    textInputAction: TextInputAction.send,
                    onSubmitted: (_) => _handleSend(context),
                    decoration: const InputDecoration(
                      hintText: 'Escreva uma mensagem...',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                ElevatedButton(
                  onPressed: () => _handleSend(context),
                  child: const Icon(Icons.send),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _handleSend(BuildContext context) async {
    final text = _msgCtrl.text.trim();
    if (text.isEmpty) return;
    _msgCtrl.clear();
    final chatStore = context.read<ChatStore>();
    final messenger = ScaffoldMessenger.of(context);
    try {
      await chatStore.sendMessage(
        orderId: widget.order.id,
        senderType: _senderId,
        senderRole: _senderRole,
        content: text,
        conversationType: widget.conversationType,
      );
    } catch (e) {
      debugPrint('ChatScreen._handleSend: $e');
      if (mounted) {
        messenger.showSnackBar(
          const SnackBar(content: Text('Não foi possível enviar a mensagem.')),
        );
      }
    }
  }

  Future<void> _respond(
    OrderStore orderStore,
    OrderModel order,
    MessageModel msg,
    bool approved,
  ) async {
    final sub = msg.substitutionContent;
    if (sub == null) return;
    final success = await orderStore.respondToSubstitution(
      orderId: order.id,
      productName: sub.original,
      approved: approved,
    );
    if (!success && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Erro ao responder substituição')),
      );
    }
  }

  Future<void> _showSubstitutionDialog(BuildContext context) async {
    final chatStore = context.read<ChatStore>();
    final messenger = ScaffoldMessenger.of(context);
    final result = await showDialog<_SubstitutionInput>(
      context: context,
      builder: (_) => const _SubstitutionDialog(),
    );
    if (result == null || !mounted) return;
    try {
      await chatStore.sendSubstitution(
        orderId: widget.order.id,
        senderType: _senderId,
        original: result.original,
        suggestion: result.suggestion,
        price: result.price,
        conversationType: widget.conversationType,
      );
    } catch (_) {
      if (mounted) {
        messenger.showSnackBar(
          const SnackBar(
              content: Text('Não foi possível enviar a substituição.')),
        );
      }
    }
  }
}

// ── Text bubble ───────────────────────────────────────────────────────────────

class _TextBubble extends StatelessWidget {
  const _TextBubble({required this.message, required this.isMine});

  final MessageModel message;
  final bool isMine;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: isMine ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 4),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        constraints:
            BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.75),
        decoration: BoxDecoration(
          color: isMine ? AppColors.primary : AppColors.surface,
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(16),
            topRight: const Radius.circular(16),
            bottomLeft: Radius.circular(isMine ? 16 : 4),
            bottomRight: Radius.circular(isMine ? 4 : 16),
          ),
        ),
        child: Column(
          crossAxisAlignment:
              isMine ? CrossAxisAlignment.end : CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              message.content,
              style: TextStyle(
                  color: isMine ? Colors.white : AppColors.textPrimary,
                  fontSize: 14),
            ),
            const SizedBox(height: 4),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  _fmt(message.createdAt),
                  style: TextStyle(
                      fontSize: 11,
                      color: isMine ? Colors.white70 : AppColors.textSecondary),
                ),
                // M11: ✓ enviada · ✓✓ lida (só nas bolhas próprias).
                if (isMine) ...[
                  const SizedBox(width: 4),
                  Icon(
                    message.read ? Icons.done_all : Icons.done,
                    size: 13,
                    color: Colors.white70,
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }

  String _fmt(DateTime dt) => '${dt.hour.toString().padLeft(2, '0')}:'
      '${dt.minute.toString().padLeft(2, '0')}';
}

// ── Substitution card ─────────────────────────────────────────────────────────

class _SubstitutionCard extends StatelessWidget {
  const _SubstitutionCard({
    required this.message,
    required this.isClient,
    required this.order,
    required this.onApprove,
    required this.onReject,
  });

  final MessageModel message;
  final bool isClient;
  final OrderModel order;
  final VoidCallback onApprove;
  final VoidCallback onReject;

  @override
  Widget build(BuildContext context) {
    final sub = message.substitutionContent;
    if (sub == null) return const SizedBox.shrink();

    final response = order.substitutionResponses[sub.original];

    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 6),
        constraints:
            BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.88),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.orange.shade200),
          boxShadow: AppColors.shadowCard,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: Colors.orange.shade50,
                borderRadius:
                    const BorderRadius.vertical(top: Radius.circular(12)),
              ),
              child: Row(
                children: [
                  Icon(Icons.swap_horiz,
                      size: 18, color: Colors.orange.shade700),
                  const SizedBox(width: 8),
                  Text(
                    'Substituir produto?',
                    style: TextStyle(
                        fontWeight: FontWeight.w700,
                        color: Colors.orange.shade800,
                        fontSize: 13),
                  ),
                ],
              ),
            ),
            // Body
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 12, 14, 0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _SubRow(label: 'Original', value: sub.original),
                  const SizedBox(height: 4),
                  _SubRow(label: 'Sugestão', value: sub.suggestion),
                  const SizedBox(height: 4),
                  _SubRow(
                      label: 'Preço',
                      value: '€${sub.price.toStringAsFixed(2)}'),
                  const SizedBox(height: 12),
                  if (response != null)
                    _ResponseBadge(approved: response)
                  else if (isClient)
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton(
                            onPressed: onReject,
                            style: OutlinedButton.styleFrom(
                              foregroundColor: Colors.red,
                              side: const BorderSide(color: Colors.red),
                            ),
                            child: const Text('Rejeitar'),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: ElevatedButton(
                            onPressed: onApprove,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.green,
                              foregroundColor: Colors.white,
                            ),
                            child: const Text('Aprovar'),
                          ),
                        ),
                      ],
                    )
                  else
                    Text(
                      'Aguardando resposta do cliente...',
                      style:
                          TextStyle(fontSize: 12, color: Colors.grey.shade600),
                    ),
                ],
              ),
            ),
            // Timestamp
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 8, 14, 10),
              child: Text(
                '${message.createdAt.hour.toString().padLeft(2, '0')}:'
                '${message.createdAt.minute.toString().padLeft(2, '0')}',
                style: const TextStyle(fontSize: 11, color: Colors.black45),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SubRow extends StatelessWidget {
  const _SubRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return RichText(
      text: TextSpan(
        style: const TextStyle(color: Colors.black87, fontSize: 13),
        children: [
          TextSpan(
              text: '$label: ',
              style: const TextStyle(fontWeight: FontWeight.w600)),
          TextSpan(text: value),
        ],
      ),
    );
  }
}

class _ResponseBadge extends StatelessWidget {
  const _ResponseBadge({required this.approved});

  final bool approved;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: approved ? Colors.green.shade50 : Colors.red.shade50,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
            color: approved ? Colors.green.shade300 : Colors.red.shade300),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            approved ? Icons.check_circle : Icons.cancel,
            size: 16,
            color: approved ? Colors.green.shade700 : Colors.red.shade700,
          ),
          const SizedBox(width: 6),
          Text(
            approved ? 'Aprovado' : 'Rejeitado',
            style: TextStyle(
              fontWeight: FontWeight.w600,
              color: approved ? Colors.green.shade700 : Colors.red.shade700,
              fontSize: 13,
            ),
          ),
        ],
      ),
    );
  }
}

// ── Substitution dialog ───────────────────────────────────────────────────────

class _SubstitutionInput {
  const _SubstitutionInput({
    required this.original,
    required this.suggestion,
    required this.price,
  });

  final String original;
  final String suggestion;
  final double price;
}

class _SubstitutionDialog extends StatefulWidget {
  const _SubstitutionDialog();

  @override
  State<_SubstitutionDialog> createState() => _SubstitutionDialogState();
}

class _SubstitutionDialogState extends State<_SubstitutionDialog> {
  final _formKey = GlobalKey<FormState>();
  final _originalCtrl = TextEditingController();
  final _suggestionCtrl = TextEditingController();
  final _priceCtrl = TextEditingController();

  @override
  void dispose() {
    _originalCtrl.dispose();
    _suggestionCtrl.dispose();
    _priceCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Propor substituição'),
      content: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextFormField(
              controller: _originalCtrl,
              decoration: const InputDecoration(labelText: 'Produto original'),
              validator: (v) =>
                  (v?.trim().isEmpty ?? true) ? 'Obrigatório' : null,
            ),
            const SizedBox(height: 8),
            TextFormField(
              controller: _suggestionCtrl,
              decoration: const InputDecoration(labelText: 'Sugestão'),
              validator: (v) =>
                  (v?.trim().isEmpty ?? true) ? 'Obrigatório' : null,
            ),
            const SizedBox(height: 8),
            TextFormField(
              controller: _priceCtrl,
              decoration: const InputDecoration(labelText: 'Preço (€)'),
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              validator: (v) {
                if (v == null || v.trim().isEmpty) return 'Obrigatório';
                if (double.tryParse(v.trim().replaceAll(',', '.')) == null) {
                  return 'Valor inválido';
                }
                return null;
              },
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancelar'),
        ),
        ElevatedButton(
          onPressed: () {
            if (!_formKey.currentState!.validate()) return;
            Navigator.pop(
              context,
              _SubstitutionInput(
                original: _originalCtrl.text.trim(),
                suggestion: _suggestionCtrl.text.trim(),
                price:
                    double.parse(_priceCtrl.text.trim().replaceAll(',', '.')),
              ),
            );
          },
          child: const Text('Enviar'),
        ),
      ],
    );
  }
}
