// Sessão 5A-2 B13 — SupportChatScreen
// Gemini via Edge Fn support-chatbot + Realtime em support_chatbot_messages.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../providers/support_settings_provider.dart';
import '../widgets/bora_support_sheet.dart';

class SupportChatScreen extends StatefulWidget {
  const SupportChatScreen({
    super.key,
    this.orderId,
    this.initialMessage,
  });

  final String? orderId;

  /// Sessão 7-UI-BUG004: pre-fill opcional do TextField. Permite redireccionar
  /// o estafeta a partir do bottom sheet de cancelamento bloqueado pós-pickedUp
  /// já com a mensagem inicial preenchida (pronta a editar e enviar).
  final String? initialMessage;

  @override
  State<SupportChatScreen> createState() => _SupportChatScreenState();
}

class _SupportChatScreenState extends State<SupportChatScreen> {
  final _supabase = Supabase.instance.client;
  final TextEditingController _input = TextEditingController();
  final ScrollController _scroll = ScrollController();
  final List<_ChatMessage> _messages = [];

  String? _sessionId;
  bool _sending = false;
  bool _escalated = false;
  String? _ticketId;
  int? _remainingToday;
  int? _remainingSession;
  String? _errorBanner;
  RealtimeChannel? _channel;

  @override
  void initState() {
    super.initState();
    _messages.add(_ChatMessage.assistant(
      'Olá! Sou a Bora IA. Como posso ajudar?',
    ));
    final pre = widget.initialMessage;
    if (pre != null && pre.isNotEmpty) {
      _input.value = TextEditingValue(
        text: pre,
        selection: TextSelection.collapsed(offset: pre.length),
      );
    }
  }

  @override
  void dispose() {
    _channel?.unsubscribe();
    _input.dispose();
    _scroll.dispose();
    super.dispose();
  }

  void _subscribeRealtime(String sessionId) {
    if (_channel != null) return;
    _channel = _supabase.channel('support_chat_$sessionId');
    _channel!.onPostgresChanges(
      event: PostgresChangeEvent.insert,
      schema: 'public',
      table: 'support_chatbot_messages',
      filter: PostgresChangeFilter(
        type: PostgresChangeFilterType.eq,
        column: 'session_id',
        value: sessionId,
      ),
      callback: (payload) {
        final row = payload.newRecord;
        final role = row['role'] as String?;
        final content = (row['content'] as String?) ?? '';
        if (role == 'assistant' && content.isNotEmpty) {
          // assistant final já é setado em _send via response.reply,
          // este callback ajuda em cenários multi-device / logs duplicados
          // — guardamos apenas o último.
        }
      },
    ).subscribe();
  }

  Future<void> _send() async {
    final text = _input.text.trim();
    if (text.isEmpty || _sending) return;

    setState(() {
      _sending = true;
      _errorBanner = null;
      _messages.add(_ChatMessage.user(text));
      _input.clear();
    });
    _scrollToBottom();

    try {
      final res = await _supabase.functions.invoke(
        'support-chatbot',
        body: {
          if (_sessionId != null) 'session_id': _sessionId,
          'message': text,
          if (widget.orderId != null) 'order_id': widget.orderId,
        },
      );
      final data = res.data as Map<String, dynamic>?;
      if (data == null) {
        throw Exception('Resposta vazia do servidor');
      }
      final reply = (data['reply'] as String?) ?? '';
      final sessionId = data['session_id'] as String?;
      final escalated = (data['escalated'] as bool?) ?? false;
      final ticketId = data['ticket_id'] as String?;
      final remToday = data['messages_remaining_today'] as int?;
      final remSession = data['messages_remaining_session'] as int?;

      setState(() {
        if (sessionId != null && _sessionId == null) {
          _sessionId = sessionId;
          _subscribeRealtime(sessionId);
        }
        _messages.add(_ChatMessage.assistant(reply));
        _escalated = escalated;
        _ticketId = ticketId;
        _remainingToday = remToday;
        _remainingSession = remSession;
        _sending = false;
      });
      _scrollToBottom();
      if (escalated && mounted) {
        Future<void>.delayed(const Duration(milliseconds: 600), _showHandoff);
      }
    } on FunctionException catch (e) {
      setState(() {
        _sending = false;
        final status = e.status;
        if (status == 429) {
          _errorBanner =
              'Limite de mensagens atingido. Podes contactar via WhatsApp ou Email.';
        } else if (status == 503) {
          _errorBanner =
              'Sistema em configuração. Contacta WhatsApp/Email.';
        } else {
          _errorBanner = 'Indisponível temporariamente. Tenta daqui a pouco.';
        }
      });
    } catch (e) {
      setState(() {
        _sending = false;
        _errorBanner = 'Erro de comunicação. Tenta novamente.';
      });
      debugPrint('[SupportChatScreen] send error: $e');
    }
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) {
        _scroll.animateTo(
          _scroll.position.maxScrollExtent,
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeOut,
        );
      }
    });
  }

  void _showHandoff() {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => BoraSupportSheet(orderId: widget.orderId),
    );
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<SupportSettingsProvider>();
    return Scaffold(
      appBar: AppBar(
        title: const Text('Bora IA — assistente'),
        actions: [
          IconButton(
            tooltip: 'Falar com humano',
            icon: const Icon(Icons.support_agent),
            onPressed: _showHandoff,
          ),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(28),
          child: Container(
            width: double.infinity,
            color: const Color(0xFFFFF3E0),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            child: Text(
              _statusBarText(provider),
              style: const TextStyle(fontSize: 11, color: Color(0xFFE65100)),
            ),
          ),
        ),
      ),
      body: Column(
        children: [
          if (_errorBanner != null)
            Container(
              width: double.infinity,
              color: const Color(0xFFFFEBEE),
              padding: const EdgeInsets.all(12),
              child: Text(
                _errorBanner!,
                style: const TextStyle(color: Color(0xFFC62828)),
              ),
            ),
          if (_escalated)
            Container(
              width: double.infinity,
              color: const Color(0xFFE3F2FD),
              padding: const EdgeInsets.all(12),
              child: Row(
                children: [
                  const Icon(Icons.swap_horiz, color: Color(0xFF1565C0)),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      _ticketId == null
                          ? 'Transferido para humano.'
                          : 'Ticket #${_ticketId!.substring(0, 8)} criado.',
                      style: const TextStyle(color: Color(0xFF1565C0)),
                    ),
                  ),
                ],
              ),
            ),
          Expanded(
            child: ListView.builder(
              controller: _scroll,
              padding: const EdgeInsets.all(12),
              itemCount: _messages.length,
              itemBuilder: (_, i) => _MessageBubble(msg: _messages[i]),
            ),
          ),
          _Composer(
            controller: _input,
            sending: _sending,
            onSend: _send,
          ),
          // Sessão 6 B2 — fallback discreto para WhatsApp/Email
          // (kill switch ON ⇒ FAB abre chat directo, este botão é o
          // último recurso humano DENTRO do chat).
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
              child: TextButton(
                style: TextButton.styleFrom(
                  foregroundColor: Colors.grey.shade600,
                  textStyle: const TextStyle(fontSize: 12),
                ),
                onPressed: () {
                  showModalBottomSheet<void>(
                    context: context,
                    isScrollControlled: true,
                    backgroundColor: Colors.transparent,
                    builder: (_) => BoraSupportSheet(
                      orderId: widget.orderId,
                      showAgentCard: false,
                    ),
                  );
                },
                child: const Text('Falar com humano'),
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _statusBarText(SupportSettingsProvider p) {
    final today = _remainingToday;
    final session = _remainingSession;
    if (today == null && session == null) {
      return 'Limites: 30 msg/dia · 30 msg/sessão';
    }
    return 'Restam ${today ?? '?'} hoje · ${session ?? '?'} nesta sessão';
  }
}

class _ChatMessage {
  _ChatMessage.user(this.content)
      : role = 'user',
        timestamp = DateTime.now();
  _ChatMessage.assistant(this.content)
      : role = 'assistant',
        timestamp = DateTime.now();

  final String role;
  final String content;
  final DateTime timestamp;

  bool get isUser => role == 'user';
}

class _MessageBubble extends StatelessWidget {
  const _MessageBubble({required this.msg});
  final _ChatMessage msg;

  @override
  Widget build(BuildContext context) {
    final isUser = msg.isUser;
    return Align(
      alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.78,
        ),
        margin: const EdgeInsets.symmetric(vertical: 4),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: isUser ? const Color(0xFFE65100) : Colors.grey.shade100,
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(16),
            topRight: const Radius.circular(16),
            bottomLeft: Radius.circular(isUser ? 16 : 4),
            bottomRight: Radius.circular(isUser ? 4 : 16),
          ),
        ),
        child: Text(
          msg.content,
          style: TextStyle(
            color: isUser ? Colors.white : Colors.black87,
            fontSize: 14,
          ),
        ),
      ),
    );
  }
}

class _Composer extends StatelessWidget {
  const _Composer({
    required this.controller,
    required this.sending,
    required this.onSend,
  });

  final TextEditingController controller;
  final bool sending;
  final VoidCallback onSend;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Container(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
        decoration: BoxDecoration(
          color: Colors.white,
          border: Border(top: BorderSide(color: Colors.grey.shade200)),
        ),
        child: Row(
          children: [
            Expanded(
              child: TextField(
                controller: controller,
                maxLength: 2000,
                maxLines: 4,
                minLines: 1,
                decoration: const InputDecoration(
                  hintText: 'Escreve a tua dúvida…',
                  counterText: '',
                  border: InputBorder.none,
                ),
                onSubmitted: (_) => onSend(),
              ),
            ),
            sending
                ? const Padding(
                    padding: EdgeInsets.all(12),
                    child: SizedBox(
                      width: 20, height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  )
                : IconButton(
                    icon: const Icon(Icons.send,
                        color: Color(0xFFE65100)),
                    onPressed: onSend,
                  ),
          ],
        ),
      ),
    );
  }
}
