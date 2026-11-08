// Sessão 5A-2 B13 — SupportChatScreen
// Gemini via Edge Fn support-chatbot + Realtime em support_chatbot_messages.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import '../config/app_colors.dart';
import '../providers/support_settings_provider.dart';
import '../widgets/bora_support_sheet.dart';

import '../l10n/tr.dart';

/// Sessão 2026-05-18 — persistência local do session_id activo.
/// Sem isto, sair e voltar ao ecrã do chatbot criava sessão nova (perdia
/// histórico + contexto da IA). A chave guarda apenas o UUID; o histórico
/// vem da DB via _loadHistory().
const String _kActiveSessionPrefsKey = 'active_support_session_id';

/// Adendo 1 m4 (08/11/2026): papéis que o cliente vê no chat. 'admin' é a
/// equipa Bora a responder como pessoa; 'tool' e 'system' nunca aparecem
/// (antes o histórico mostrava as linhas de ferramenta como balões do robô).
const List<String> kPapeisVisiveisSuporte = ['user', 'assistant', 'admin'];

/// Uma conversa escalada continua a abrir durante 48 h: é por ela que a
/// resposta da equipa chega ao cliente.
bool sessaoSuporteContinua({
  required Object? endedAt,
  required bool escalada,
  required String? modo,
  required DateTime? iniciadaEm,
  DateTime? agora,
}) {
  if (endedAt != null) return false;
  if (!escalada || modo == 'admin') return true;
  if (iniciadaEm == null) return false;
  return (agora ?? DateTime.now()).difference(iniciadaEm) <
      const Duration(hours: 48);
}

/// Primeiro link do WhatsApp num texto (o robô dá o da Bora quando o cliente
/// pede uma pessoa).
String? linkWhatsAppNoTexto(String texto) =>
    RegExp(r'https://wa\.me/\d{9,15}').firstMatch(texto)?.group(0);

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

  /// A equipa Bora assumiu a conversa (o robô está calado).
  bool _modoEquipa = false;

  /// Ids das mensagens da equipa já mostradas (o Realtime pode repetir).
  final Set<String> _idsEquipa = {};

  @override
  void initState() {
    super.initState();
    _messages.add(_ChatMessage.assistant(
      'Olá! Sou a Bora IA. Como posso ajudar?'.tr,
    ));
    final pre = widget.initialMessage;
    if (pre != null && pre.isNotEmpty) {
      _input.value = TextEditingValue(
        text: pre,
        selection: TextSelection.collapsed(offset: pre.length),
      );
    }
    // Sessão 2026-05-18 — tenta restaurar sessão activa antes de mostrar
    // estado vazio. Fire-and-forget; greeting fica visível enquanto carrega.
    _restoreSession();
  }

  /// Lê o session_id persistido em SharedPreferences. Se existir e
  /// ainda estiver activo (ended_at IS NULL && escalated = false), carrega
  /// o histórico de mensagens e subscreve o realtime channel. Caso contrário
  /// limpa a chave e deixa o utilizador iniciar conversa nova.
  Future<void> _restoreSession() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final saved = prefs.getString(_kActiveSessionPrefsKey);
      if (saved == null || saved.isEmpty) return;

      // RLS garante que só vemos sessões do auth.uid() — não precisa filtrar
      // user_id explicitamente.
      final session = await _supabase
          .from('support_chatbot_sessions')
          .select('id, ended_at, escalated, ticket_id, mode, started_at')
          .eq('id', saved)
          .maybeSingle();

      if (session == null) {
        await prefs.remove(_kActiveSessionPrefsKey);
        return;
      }
      final escalated = (session['escalated'] as bool?) ?? false;
      final modo = session['mode'] as String?;
      // Adendo 1 m4 (08/11/2026): uma conversa escalada já não se descarta
      // logo — é por ela que a resposta da equipa Bora chega (48 h).
      if (!sessaoSuporteContinua(
        endedAt: session['ended_at'],
        escalada: escalated,
        modo: modo,
        iniciadaEm: DateTime.tryParse(session['started_at']?.toString() ?? ''),
      )) {
        await prefs.remove(_kActiveSessionPrefsKey);
        return;
      }

      if (!mounted) return;
      _sessionId = saved;
      _escalated = escalated;
      _modoEquipa = modo == 'admin';
      _ticketId = session['ticket_id'] as String?;
      _subscribeRealtime(saved);
      await _loadHistory(saved);
    } catch (e) {
      debugPrint('[SupportChatScreen] _restoreSession error: $e');
    }
  }

  /// Carrega as últimas 50 mensagens da sessão por ordem cronológica.
  Future<void> _loadHistory(String sessionId) async {
    if (!mounted) return;
    try {
      final rows = await _supabase
          .from('support_chatbot_messages')
          .select('id, role, content, created_at')
          .eq('session_id', sessionId)
          .inFilter('role', kPapeisVisiveisSuporte)
          .order('created_at', ascending: true)
          .limit(50);

      if (!mounted) return;
      setState(() {
        if (rows.isNotEmpty) {
          // Remove o greeting inicial — substituído pelo histórico real.
          _messages.clear();
        }
        for (final r in rows as List) {
          final role = r['role'] as String?;
          final content = (r['content'] as String?) ?? '';
          if (content.isEmpty) continue;
          if (role == 'admin') {
            _idsEquipa.add(r['id'].toString());
            _messages.add(_ChatMessage.equipa(content));
          } else {
            _messages.add(role == 'user'
                ? _ChatMessage.user(content)
                : _ChatMessage.assistant(content));
          }
        }
      });
      _scrollToBottom();
    } catch (e) {
      debugPrint('[SupportChatScreen] _loadHistory error: $e');
    }
  }

  Future<void> _persistSessionId(String sessionId) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_kActiveSessionPrefsKey, sessionId);
    } catch (e) {
      debugPrint('[SupportChatScreen] _persistSessionId error: $e');
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
        // A resposta do robô chega por _send (response.reply). Aqui só entram
        // as mensagens da equipa Bora, escritas por uma pessoa no painel.
        if (role == 'admin' && content.isNotEmpty && mounted) {
          final id = row['id']?.toString() ?? '';
          if (id.isNotEmpty && !_idsEquipa.add(id)) return;
          setState(() {
            _messages.add(_ChatMessage.equipa(content));
            _modoEquipa = true;
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
      final modoEquipa = data['modo'] == 'admin';
      final jaEscalada = _escalated;

      if (!mounted) return;
      setState(() {
        if (sessionId != null && _sessionId == null) {
          _sessionId = sessionId;
          _subscribeRealtime(sessionId);
          // Sessão 2026-05-18 — persistir para sobreviver a dispose() do widget.
          _persistSessionId(sessionId);
        }
        // Com a equipa a responder, o robô não responde (reply vazio).
        if (reply.trim().isNotEmpty) _messages.add(_ChatMessage.assistant(reply));
        _escalated = escalated;
        _modoEquipa = _modoEquipa || modoEquipa;
        _ticketId = ticketId ?? _ticketId;
        _remainingToday = remToday;
        _remainingSession = remSession;
        _sending = false;
      });
      _scrollToBottom();
      if (escalated && !jaEscalada && !modoEquipa && mounted) {
        // Adendo 1 m4 (08/11/2026): a sessão escalada FICA guardada — é por
        // ela que a resposta da equipa chega (antes limpava-se e a resposta
        // perdia-se). O robô já deu o WhatsApp; o painel abre por cima.
        Future<void>.delayed(const Duration(milliseconds: 600), _showHandoff);
      }
    } on FunctionException catch (e) {
      if (!mounted) return;
      setState(() {
        _sending = false;
        final status = e.status;
        if (status == 429) {
          _errorBanner =
              'Limite de mensagens atingido. Podes contactar via WhatsApp ou Email.'.tr;
        } else if (status == 503) {
          _errorBanner =
              'Sistema em configuração. Contacta WhatsApp/Email.'.tr;
        } else {
          _errorBanner = 'Indisponível temporariamente. Tenta daqui a pouco.'.tr;
        }
      });
    } catch (e) {
      debugPrint('[SupportChatScreen] send error: $e');
      if (!mounted) return;
      setState(() {
        _sending = false;
        _errorBanner = 'Erro de comunicação. Tenta novamente.'.tr;
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

  void _showHandoff() {
    if (!mounted) return;
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
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.primary,
        elevation: 0,
        foregroundColor: Colors.white,
        iconTheme: const IconThemeData(color: Colors.white),
        actionsIconTheme: const IconThemeData(color: Colors.white),
        flexibleSpace: const DecoratedBox(
          decoration: BoxDecoration(gradient: AppColors.headerGradient),
        ),
        title: Text(
          'Bora IA — assistente'.tr,
          style: const TextStyle(color: Colors.white),
        ),
        actions: [
          IconButton(
            tooltip: 'Falar com humano'.tr,
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
              style: const TextStyle(fontSize: 11, color: AppColors.accent),
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
          if (_modoEquipa)
            Container(
              width: double.infinity,
              color: AppColors.primaryWash,
              padding: const EdgeInsets.all(12),
              child: Row(
                children: [
                  const Icon(Icons.support_agent, color: AppColors.primaryDark),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Estás a falar com a equipa Bora.'.tr,
                      style: const TextStyle(color: AppColors.primaryDark),
                    ),
                  ),
                ],
              ),
            )
          else if (_escalated)
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
                          ? 'Transferido para humano.'.tr
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
                  foregroundColor: AppColors.textSecondary,
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
                child: Text('Falar com humano'.tr),
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
      return 'Limites: 30 msg/dia · 30 msg/sessão'.tr;
    }
    return 'Restam {0} hoje · {1} nesta sessão'.trArgs([today ?? '?', session ?? '?']);
  }
}

class _ChatMessage {
  _ChatMessage.user(this.content)
      : role = 'user',
        timestamp = DateTime.now();
  _ChatMessage.assistant(this.content)
      : role = 'assistant',
        timestamp = DateTime.now();

  /// Adendo 1 m4: resposta escrita por uma pessoa da equipa Bora no painel.
  _ChatMessage.equipa(this.content)
      : role = 'admin',
        timestamp = DateTime.now();

  final String role;
  final String content;
  final DateTime timestamp;

  bool get isUser => role == 'user';
  bool get isEquipa => role == 'admin';
}

class _MessageBubble extends StatelessWidget {
  const _MessageBubble({required this.msg});
  final _ChatMessage msg;

  @override
  Widget build(BuildContext context) {
    final isUser = msg.isUser;
    final wa = isUser ? null : linkWhatsAppNoTexto(msg.content);
    return Align(
      alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.78,
        ),
        margin: const EdgeInsets.symmetric(vertical: 4),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: isUser
              ? AppColors.accent
              : msg.isEquipa
                  ? AppColors.primaryWash
                  : AppColors.surface,
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(16),
            topRight: const Radius.circular(16),
            bottomLeft: Radius.circular(isUser ? 16 : 4),
            bottomRight: Radius.circular(isUser ? 4 : 16),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            if (msg.isEquipa)
              Padding(
                padding: const EdgeInsets.only(bottom: 2),
                child: Text(
                  'Equipa Bora'.tr,
                  style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: AppColors.primaryDark,
                  ),
                ),
              ),
            Text(
              msg.content,
              style: TextStyle(
                color: isUser ? Colors.white : AppColors.textPrimary,
                fontSize: 14,
              ),
            ),
            if (wa != null)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: OutlinedButton.icon(
                  onPressed: () => launchUrl(Uri.parse(wa),
                      mode: LaunchMode.externalApplication),
                  icon: const Icon(Icons.chat, size: 18),
                  label: Text('Abrir o WhatsApp da Bora'.tr),
                ),
              ),
          ],
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
        decoration: const BoxDecoration(
          color: AppColors.surface,
          border: Border(top: BorderSide(color: AppColors.divider)),
        ),
        child: Row(
          children: [
            Expanded(
              child: TextField(
                controller: controller,
                maxLength: 2000,
                maxLines: 4,
                minLines: 1,
                decoration: InputDecoration(
                  hintText: 'Escreve a tua dúvida…'.tr,
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
                        color: AppColors.accent),
                    onPressed: onSend,
                  ),
          ],
        ),
      ),
    );
  }
}
