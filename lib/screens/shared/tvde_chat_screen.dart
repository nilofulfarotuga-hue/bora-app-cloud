import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../config/app_colors.dart';
import '../../config/app_spacing.dart';
import '../../stores/tvde_chat_store.dart';
import '../../widgets/bora/bora.dart';

/// E — Chat bidirecional TVDE (reusa o padrão do chat do delivery). Scoped por
/// corrida. [myRole] = 'client' no lado do passageiro, 'driver' no motorista.
/// [otherPhone] habilita o botão de ligar (tel:) no topo.
class TvdeChatScreen extends StatefulWidget {
  const TvdeChatScreen({
    super.key,
    required this.rideId,
    required this.myRole,
    required this.title,
    this.otherPhone,
  });

  final String rideId;
  final String myRole;
  final String title;
  final String? otherPhone;

  @override
  State<TvdeChatScreen> createState() => _TvdeChatScreenState();
}

class _TvdeChatScreenState extends State<TvdeChatScreen> {
  final _controller = TextEditingController();
  final _scroll = ScrollController();
  bool _sending = false;

  @override
  void initState() {
    super.initState();
    context.read<TvdeChatStore>().listen(widget.rideId);
  }

  @override
  void dispose() {
    context.read<TvdeChatStore>().unlisten(widget.rideId);
    _controller.dispose();
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final text = _controller.text.trim();
    if (text.isEmpty || _sending) return;
    setState(() => _sending = true);
    try {
      await context.read<TvdeChatStore>().sendMessage(
            rideId: widget.rideId,
            senderRole: widget.myRole,
            content: text,
          );
      _controller.clear();
      _scrollToEnd();
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('Não foi possível enviar. Tenta de novo.')));
      }
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  void _scrollToEnd() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) {
        _scroll.animateTo(_scroll.position.maxScrollExtent,
            duration: const Duration(milliseconds: 200), curve: Curves.easeOut);
      }
    });
  }

  Future<void> _call() async {
    final phone = widget.otherPhone;
    if (phone == null || phone.isEmpty) return;
    final uri = Uri.parse('tel:$phone');
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  @override
  Widget build(BuildContext context) {
    final messages =
        context.watch<TvdeChatStore>().messagesForRide(widget.rideId);

    return Scaffold(
      appBar: BoraScreenAppBar(
        title: widget.title,
        actions: [
          if (widget.otherPhone != null && widget.otherPhone!.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.call),
              tooltip: 'Ligar',
              onPressed: _call,
            ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: messages.isEmpty
                ? Center(
                    child: Text('Ainda sem mensagens. Diz olá 👋',
                        style: TextStyle(color: AppColors.textSubtle)),
                  )
                : ListView.builder(
                    controller: _scroll,
                    padding: const EdgeInsets.all(Spacing.md),
                    itemCount: messages.length,
                    itemBuilder: (_, i) {
                      final m = messages[i];
                      final mine = m.senderRole == widget.myRole;
                      return Align(
                        alignment:
                            mine ? Alignment.centerRight : Alignment.centerLeft,
                        child: Container(
                          margin: const EdgeInsets.symmetric(vertical: 4),
                          padding: const EdgeInsets.symmetric(
                              horizontal: Spacing.md, vertical: Spacing.sm),
                          constraints: BoxConstraints(
                              maxWidth:
                                  MediaQuery.of(context).size.width * 0.72),
                          decoration: BoxDecoration(
                            color: mine
                                ? AppColors.primary
                                : AppColors.surface,
                            borderRadius: BorderRadius.circular(Radii.md + 2),
                            border: mine
                                ? null
                                : Border.all(color: AppColors.divider),
                          ),
                          child: Text(m.content,
                              style: TextStyle(
                                  color: mine
                                      ? Colors.white
                                      : AppColors.textPrimary)),
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
                      minLines: 1,
                      maxLines: 4,
                      textInputAction: TextInputAction.send,
                      onSubmitted: (_) => _send(),
                      decoration: InputDecoration(
                        hintText: 'Escreve uma mensagem…',
                        filled: true,
                        fillColor: AppColors.surface,
                        contentPadding: const EdgeInsets.symmetric(
                            horizontal: Spacing.md, vertical: Spacing.sm),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(Radii.lg),
                          borderSide: BorderSide(color: AppColors.divider),
                        ),
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
