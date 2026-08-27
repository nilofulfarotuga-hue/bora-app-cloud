import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../config/app_colors.dart';
import '../../config/app_spacing.dart';

/// LAVAGEM AUTO — chat cliente ⇄ lavador.
/// Mesmo desenho do chat da Limpeza: realtime na tabela `carwash_messages`,
/// e botão de telefone dos dois lados.
class CarwashChatScreen extends StatefulWidget {
  const CarwashChatScreen({
    super.key,
    required this.bookingId,
    required this.myRole, // 'client' | 'washer'
    required this.title,
    this.otherPhone,
  });

  final String bookingId;
  final String myRole;
  final String title;
  final String? otherPhone;

  @override
  State<CarwashChatScreen> createState() => _CarwashChatScreenState();
}

class _CarwashChatScreenState extends State<CarwashChatScreen> {
  final _controller = TextEditingController();
  final _scroll = ScrollController();

  SupabaseClient get _sb => Supabase.instance.client;

  List<Map<String, dynamic>> _messages = [];
  RealtimeChannel? _channel;
  bool _sending = false;

  @override
  void initState() {
    super.initState();
    _load();
    _subscribe();
  }

  @override
  void dispose() {
    final ch = _channel;
    if (ch != null) _sb.removeChannel(ch);
    _controller.dispose();
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final rows = await _sb
          .from('carwash_messages')
          .select()
          .eq('booking_id', widget.bookingId)
          .order('created_at');
      if (!mounted) return;
      setState(() => _messages =
          (rows as List).map((r) => Map<String, dynamic>.from(r as Map)).toList());
      _scrollToEnd();
    } catch (_) {/* lista fica vazia; o utilizador pode tentar enviar */}
  }

  void _subscribe() {
    _channel = _sb.channel('carwash_chat_${widget.bookingId}')
      ..onPostgresChanges(
        event: PostgresChangeEvent.insert,
        schema: 'public',
        table: 'carwash_messages',
        filter: PostgresChangeFilter(
          type: PostgresChangeFilterType.eq,
          column: 'booking_id',
          value: widget.bookingId,
        ),
        callback: (payload) {
          if (!mounted) return;
          setState(() => _messages = [..._messages, payload.newRecord]);
          _scrollToEnd();
        },
      )
      ..subscribe();
  }

  void _scrollToEnd() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) {
        _scroll.animateTo(
          _scroll.position.maxScrollExtent,
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOut,
        );
      }
    });
  }

  Future<void> _send() async {
    final text = _controller.text.trim();
    if (text.isEmpty || _sending) return;
    setState(() => _sending = true);
    try {
      await _sb.from('carwash_messages').insert({
        'booking_id': widget.bookingId,
        'sender_role': widget.myRole,
        'message': text,
      });
      _controller.clear();
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Não foi possível enviar. Tente outra vez.')),
        );
      }
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<void> _call() async {
    final phone = widget.otherPhone;
    if (phone == null || phone.isEmpty) return;
    final uri = Uri.parse('tel:$phone');
    if (await canLaunchUrl(uri)) await launchUrl(uri);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: Text(widget.title),
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        actions: [
          if ((widget.otherPhone ?? '').isNotEmpty)
            IconButton(onPressed: _call, icon: const Icon(Icons.phone)),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: _messages.isEmpty
                ? const Center(
                    child: Padding(
                      padding: EdgeInsets.all(Spacing.xxl),
                      child: Text(
                        'Ainda não há mensagens.\nEscreva a primeira aqui em baixo.',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: AppColors.textSubtle),
                      ),
                    ),
                  )
                : ListView.builder(
                    controller: _scroll,
                    padding: const EdgeInsets.all(Spacing.lg),
                    itemCount: _messages.length,
                    itemBuilder: (_, i) {
                      final m = _messages[i];
                      final mine = m['sender_role'] == widget.myRole;
                      return Align(
                        alignment:
                            mine ? Alignment.centerRight : Alignment.centerLeft,
                        child: Container(
                          margin: const EdgeInsets.only(bottom: Spacing.sm),
                          padding: const EdgeInsets.symmetric(
                              horizontal: Spacing.md, vertical: Spacing.sm),
                          constraints: BoxConstraints(
                              maxWidth:
                                  MediaQuery.of(context).size.width * 0.75),
                          decoration: BoxDecoration(
                            color: mine ? AppColors.primary : AppColors.card,
                            borderRadius: BorderRadius.circular(14),
                          ),
                          child: Text(
                            (m['message'] ?? '').toString(),
                            style: TextStyle(
                              color:
                                  mine ? Colors.white : AppColors.textPrimary,
                            ),
                          ),
                        ),
                      );
                    },
                  ),
          ),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.all(Spacing.sm),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _controller,
                      textInputAction: TextInputAction.send,
                      onSubmitted: (_) => _send(),
                      decoration: const InputDecoration(
                        hintText: 'Escreva a sua mensagem',
                        border: OutlineInputBorder(),
                        contentPadding: EdgeInsets.symmetric(
                            horizontal: Spacing.md, vertical: Spacing.sm),
                      ),
                    ),
                  ),
                  const SizedBox(width: Spacing.sm),
                  IconButton.filled(
                    onPressed: _sending ? null : _send,
                    icon: const Icon(Icons.send),
                    style: IconButton.styleFrom(
                        backgroundColor: AppColors.primary),
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
