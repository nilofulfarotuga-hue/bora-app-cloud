import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../config/app_colors.dart';
import '../../widgets/bora/bora_screen_app_bar.dart';

/// Chat IA do painel admin.
/// Conversa com Edge Fn `admin-ai-assistant` que usa Claude com tool use
/// para executar acções no Supabase (read-only nesta v1).
class AdminAiAssistantScreen extends StatefulWidget {
  const AdminAiAssistantScreen({super.key});

  @override
  State<AdminAiAssistantScreen> createState() => _AdminAiAssistantScreenState();
}

class _AdminAiAssistantScreenState extends State<AdminAiAssistantScreen> {
  final List<_ChatMessage> _messages = [];
  final List<Map<String, dynamic>> _actions = [];
  final _input = TextEditingController();
  final _scroll = ScrollController();
  bool _sending = false;
  String? _sessionId;
  String? _error;

  @override
  void initState() {
    super.initState();
    _messages.add(_ChatMessage(
      role: 'assistant',
      text:
          'Olá Danilo. Sou o assistente IA do painel admin. Posso consultar pedidos, '
          'clientes, configurações, etc. Faz uma pergunta — por exemplo: '
          '"Mostra-me os pedidos de hoje" ou "Quanto está a comissão do parceiro agora?".',
    ));
  }

  @override
  void dispose() {
    _input.dispose();
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final text = _input.text.trim();
    if (text.isEmpty || _sending) return;
    setState(() {
      _messages.add(_ChatMessage(role: 'user', text: text));
      _sending = true;
      _error = null;
    });
    _input.clear();
    _scrollToBottom();

    try {
      final payloadMessages = _messages
          .where((m) => m.role == 'user' || m.role == 'assistant')
          .map((m) => {'role': m.role, 'content': m.text})
          .toList();

      final res = await Supabase.instance.client.functions.invoke(
        'admin-ai-assistant',
        body: {
          'session_id': _sessionId,
          'messages': payloadMessages,
        },
      );

      final data = res.data as Map<String, dynamic>?;
      if (data == null) {
        throw Exception('Sem resposta do servidor.');
      }
      final reply = (data['reply'] as String?)?.trim() ?? '(sem texto)';
      final newActions = (data['actions'] as List?)?.cast<Map<String, dynamic>>() ?? [];
      final newSession = data['session_id'] as String?;
      setState(() {
        _messages.add(_ChatMessage(role: 'assistant', text: reply));
        _actions.addAll(newActions);
        _sessionId = newSession ?? _sessionId;
      });
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      setState(() => _sending = false);
      _scrollToBottom();
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
      appBar: const BoraScreenAppBar(title: 'Assistente IA — Admin'),
      body: Column(
        children: [
          if (_error != null)
            Container(
              width: double.infinity,
              color: AppColors.error.withValues(alpha: 0.08),
              padding: const EdgeInsets.all(12),
              child: Text('Erro: $_error',
                  style: const TextStyle(color: AppColors.error)),
            ),
          Expanded(
            child: ListView.builder(
              controller: _scroll,
              padding: const EdgeInsets.all(12),
              itemCount: _messages.length + (_actions.isNotEmpty ? 1 : 0),
              itemBuilder: (_, i) {
                if (i == _messages.length) return _buildActionsCard();
                return _buildBubble(_messages[i]);
              },
            ),
          ),
          if (_sending) const LinearProgressIndicator(minHeight: 2),
          Container(
            decoration: const BoxDecoration(
              color: AppColors.surface,
              border: Border(top: BorderSide(color: AppColors.divider)),
            ),
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
            child: SafeArea(
              top: false,
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _input,
                      minLines: 1,
                      maxLines: 4,
                      enabled: !_sending,
                      decoration: InputDecoration(
                        hintText: 'Pergunta em PT-BR...',
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(20),
                        ),
                        contentPadding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 10),
                      ),
                      onSubmitted: (_) => _send(),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Material(
                    color: AppColors.primary,
                    shape: const CircleBorder(),
                    child: InkWell(
                      customBorder: const CircleBorder(),
                      onTap: _sending ? null : _send,
                      child: const Padding(
                        padding: EdgeInsets.all(12),
                        child: Icon(Icons.send, color: Colors.white, size: 20),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBubble(_ChatMessage m) {
    final isUser = m.role == 'user';
    return Align(
      alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 4),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        constraints: BoxConstraints(
            maxWidth: MediaQuery.of(context).size.width * 0.82),
        decoration: BoxDecoration(
          color: isUser ? AppColors.primary : AppColors.surface2,
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(14),
            topRight: const Radius.circular(14),
            bottomLeft: Radius.circular(isUser ? 14 : 4),
            bottomRight: Radius.circular(isUser ? 4 : 14),
          ),
        ),
        child: Text(
          m.text,
          style: TextStyle(
              color: isUser ? Colors.white : Colors.black87, fontSize: 14),
        ),
      ),
    );
  }

  Widget _buildActionsCard() {
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 10),
      color: Colors.amber.shade50,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.build, size: 16, color: Colors.amber),
                const SizedBox(width: 6),
                Text(
                  'Acções executadas (${_actions.length})',
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
              ],
            ),
            const SizedBox(height: 6),
            ..._actions.map((a) => Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(
                    '• ${a['tool']}'
                    '${a['ok'] == true ? ' ✓' : ' ✗'}',
                    style: const TextStyle(fontSize: 12),
                  ),
                )),
          ],
        ),
      ),
    );
  }
}

class _ChatMessage {
  final String role; // 'user' | 'assistant'
  final String text;
  _ChatMessage({required this.role, required this.text});
}
