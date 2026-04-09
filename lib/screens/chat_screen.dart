import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../models/chat_message.dart';
import '../models/message_model.dart';
import '../models/order_model.dart';
import '../stores/chat_store.dart';
import '../stores/order_store.dart';

class ChatScreen extends StatefulWidget {
  const ChatScreen({
    super.key,
    required this.order,
    required this.senderType,
  });

  final OrderModel order;
  final ChatSenderType senderType;

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final TextEditingController _msgCtrl = TextEditingController();
  final ScrollController _scrollCtrl = ScrollController();

  String get _senderRole =>
      widget.senderType == ChatSenderType.client ? 'client' : 'driver';

  String get _senderId {
    final o = widget.order;
    return widget.senderType == ChatSenderType.client
        ? (o.clientPhone ?? 'client_${o.id}')
        : (o.assignedDriverId ?? 'driver_${o.id}');
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<ChatStore>().listen(widget.order.id);
    });
  }

  @override
  void dispose() {
    _msgCtrl.dispose();
    _scrollCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final chatStore = context.watch<ChatStore>();
    final orderStore = context.watch<OrderStore>();
    final liveOrder = orderStore.orders.firstWhere(
      (o) => o.id == widget.order.id,
      orElse: () => widget.order,
    );
    final messages = chatStore.messagesForOrder(widget.order.id);

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
      appBar: AppBar(
        title: Text('Chat · ${liveOrder.vendorName ?? 'Pedido'}'),
        actions: [
          IconButton(
            icon: const Icon(Icons.phone),
            tooltip: 'Ligar',
            onPressed: () async {
              final phone = widget.senderType == ChatSenderType.driver
                  ? liveOrder.clientPhone
                  : liveOrder.driverPhone;
              if (phone == null || phone.isEmpty) return;
              final uri = Uri(scheme: 'tel', path: phone);
              if (await canLaunchUrl(uri)) {
                await launchUrl(uri, mode: LaunchMode.externalApplication);
              }
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
                      style: TextStyle(color: Colors.grey),
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
                          isClient:
                              widget.senderType == ChatSenderType.client,
                          order: liveOrder,
                          onApprove: () => _respond(orderStore, liveOrder,
                              msg, true),
                          onReject: () => _respond(orderStore, liveOrder,
                              msg, false),
                        );
                      }

                      return _TextBubble(message: msg, isMine: isMine);
                    },
                  ),
          ),
          const Divider(height: 1),
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
        senderId: _senderId,
        senderRole: _senderRole,
        content: text,
      );
    } catch (e) {
      debugPrint('ChatScreen._handleSend: $e');
      if (mounted) {
        messenger.showSnackBar(
          const SnackBar(
              content: Text('Não foi possível enviar a mensagem.')),
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
        senderId: _senderId,
        original: result.original,
        suggestion: result.suggestion,
        price: result.price,
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
        padding:
            const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        constraints: BoxConstraints(
            maxWidth: MediaQuery.of(context).size.width * 0.75),
        decoration: BoxDecoration(
          color: isMine
              ? Theme.of(context).colorScheme.primary
              : Colors.grey.shade200,
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
                  color: isMine ? Colors.white : Colors.black87,
                  fontSize: 14),
            ),
            const SizedBox(height: 4),
            Text(
              _fmt(message.createdAt),
              style: TextStyle(
                  fontSize: 11,
                  color: isMine ? Colors.white70 : Colors.black45),
            ),
          ],
        ),
      ),
    );
  }

  String _fmt(DateTime dt) =>
      '${dt.hour.toString().padLeft(2, '0')}:'
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
        constraints: BoxConstraints(
            maxWidth: MediaQuery.of(context).size.width * 0.88),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.orange.shade200),
          boxShadow: const [
            BoxShadow(
                color: Colors.black12,
                blurRadius: 4,
                offset: Offset(0, 2)),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(
                  horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: Colors.orange.shade50,
                borderRadius: const BorderRadius.vertical(
                    top: Radius.circular(12)),
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
                      style: TextStyle(
                          fontSize: 12, color: Colors.grey.shade600),
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
                style: const TextStyle(
                    fontSize: 11, color: Colors.black45),
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
        style:
            const TextStyle(color: Colors.black87, fontSize: 13),
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
      padding:
          const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: approved ? Colors.green.shade50 : Colors.red.shade50,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
            color: approved
                ? Colors.green.shade300
                : Colors.red.shade300),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            approved ? Icons.check_circle : Icons.cancel,
            size: 16,
            color: approved
                ? Colors.green.shade700
                : Colors.red.shade700,
          ),
          const SizedBox(width: 6),
          Text(
            approved ? 'Aprovado' : 'Rejeitado',
            style: TextStyle(
              fontWeight: FontWeight.w600,
              color: approved
                  ? Colors.green.shade700
                  : Colors.red.shade700,
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
              decoration:
                  const InputDecoration(labelText: 'Produto original'),
              validator: (v) =>
                  (v?.trim().isEmpty ?? true) ? 'Obrigatório' : null,
            ),
            const SizedBox(height: 8),
            TextFormField(
              controller: _suggestionCtrl,
              decoration:
                  const InputDecoration(labelText: 'Sugestão'),
              validator: (v) =>
                  (v?.trim().isEmpty ?? true) ? 'Obrigatório' : null,
            ),
            const SizedBox(height: 8),
            TextFormField(
              controller: _priceCtrl,
              decoration:
                  const InputDecoration(labelText: 'Preço (€)'),
              keyboardType: const TextInputType.numberWithOptions(
                  decimal: true),
              validator: (v) {
                if (v == null || v.trim().isEmpty) return 'Obrigatório';
                if (double.tryParse(
                        v.trim().replaceAll(',', '.')) ==
                    null) {
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
                price: double.parse(
                    _priceCtrl.text.trim().replaceAll(',', '.')),
              ),
            );
          },
          child: const Text('Enviar'),
        ),
      ],
    );
  }
}
