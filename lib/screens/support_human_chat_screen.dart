// "Falar com humano" (pedido Danilo, 2026-07-14) — o humano é o Hermes com
// persona (Thayline/Thabyta). Mesmo padrão de UI do support_chat_screen.dart
// (Bora IA), mas fala com a Edge Fn support-human-chat. Se escalar, mostra
// banner "aguarda resposta" — quando o Danilo responde (via admin ou Telegram
// -> admin_reply_escalation), a mensagem chega por realtime na mesma sessão.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../config/app_colors.dart';

class SupportHumanChatScreen extends StatefulWidget {
  const SupportHumanChatScreen({super.key, this.orderId});

  final String? orderId;

  @override
  State<SupportHumanChatScreen> createState() =>
      _SupportHumanChatScreenState();
}

class _SupportHumanChatScreenState extends State<SupportHumanChatScreen> {
  final _supabase = Supabase.instance.client;
  final TextEditingController _input = TextEditingController();
  final ScrollController _scroll = ScrollController();
  final List<_Msg> _messages = [];

  String? _sessionId;
  String _personaName = 'Bora';
  bool _sending = false;
  bool _escalatedPending = false;
  String? _errorBanner;
  RealtimeChannel? _channel;

  @override
  void initState() {
    super.initState();
    _messages.add(_Msg.assistant('Olá! Em que posso ajudar?', 'Bora'));
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
    _channel = _supabase.channel('support_human_chat_$sessionId');
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
        // Deteta resposta do Danilo (chegada via admin_reply_escalation) que
        // não veio da própria chamada _send — evita duplicar a nossa própria
        // mensagem assistant (já mostrada no retorno da Edge Fn).
        if (role == 'assistant' && content.isNotEmpty && _escalatedPending) {
          setState(() {
            _messages.add(_Msg.assistant(content, _personaName));
            _escalatedPending = false;
          });
          _scrollToBottom();
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
      _messages.add(_Msg.user(text));
      _input.clear();
    });
    _scrollToBottom();

    try {
      final res = await _supabase.functions.invoke(
        'support-human-chat',
        body: {
          if (_sessionId != null) 'session_id': _sessionId,
          'message': text,
          if (widget.orderId != null) 'order_id': widget.orderId,
        },
      );
      final data = res.data as Map<String, dynamic>?;
      if (data == null) throw Exception('Resposta vazia do servidor');

      final reply = (data['reply'] as String?) ?? '';
      final sessionId = data['session_id'] as String?;
      final persona = (data['persona_name'] as String?) ?? _personaName;
      final escalated = (data['escalated'] as bool?) ?? false;

      setState(() {
        _personaName = persona;
        if (sessionId != null && _sessionId == null) {
          _sessionId = sessionId;
          _subscribeRealtime(sessionId);
        }
        _messages.add(_Msg.assistant(reply, persona));
        _escalatedPending = escalated;
        _sending = false;
      });
      _scrollToBottom();
    } on FunctionException catch (_) {
      setState(() {
        _sending = false;
        _errorBanner = 'Indisponível agora. Tenta daqui a pouco.';
      });
    } catch (e) {
      setState(() {
        _sending = false;
        _errorBanner = 'Erro de comunicação. Tenta novamente.';
      });
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.primary,
        elevation: 0,
        foregroundColor: Colors.white,
        iconTheme: const IconThemeData(color: Colors.white),
        flexibleSpace: const DecoratedBox(
          decoration: BoxDecoration(gradient: AppColors.headerGradient),
        ),
        title: Text(_personaName, style: const TextStyle(color: Colors.white)),
      ),
      body: Column(
        children: [
          if (_errorBanner != null)
            Container(
              width: double.infinity,
              color: const Color(0xFFFFEBEE),
              padding: const EdgeInsets.all(12),
              child: Text(_errorBanner!,
                  style: const TextStyle(color: Color(0xFFC62828))),
            ),
          if (_escalatedPending)
            Container(
              width: double.infinity,
              color: const Color(0xFFE3F2FD),
              padding: const EdgeInsets.all(12),
              child: const Row(
                children: [
                  Icon(Icons.hourglass_top, color: Color(0xFF1565C0)),
                  SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Passei isto ao responsável — a resposta chega aqui.',
                      style: TextStyle(color: Color(0xFF1565C0)),
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
              itemBuilder: (_, i) => _Bubble(msg: _messages[i]),
            ),
          ),
          SafeArea(
            child: Container(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
              decoration: const BoxDecoration(
                color: AppColors.surface,
                border: Border(top: BorderSide(color: AppColors.divider)),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _input,
                      maxLength: 2000,
                      maxLines: 4,
                      minLines: 1,
                      decoration: const InputDecoration(
                        hintText: 'Escreve a tua mensagem…',
                        counterText: '',
                        border: InputBorder.none,
                      ),
                      onSubmitted: (_) => _send(),
                    ),
                  ),
                  _sending
                      ? const Padding(
                          padding: EdgeInsets.all(12),
                          child: SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          ),
                        )
                      : IconButton(
                          icon: const Icon(Icons.send, color: AppColors.accent),
                          onPressed: _send,
                        ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Msg {
  _Msg.user(this.content)
      : role = 'user',
        personaName = null;
  _Msg.assistant(this.content, this.personaName) : role = 'assistant';

  final String role;
  final String content;
  final String? personaName;

  bool get isUser => role == 'user';
}

class _Bubble extends StatelessWidget {
  const _Bubble({required this.msg});
  final _Msg msg;

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
          color: isUser ? AppColors.accent : AppColors.surface,
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
            color: isUser ? Colors.white : AppColors.textPrimary,
            fontSize: 14,
          ),
        ),
      ),
    );
  }
}
