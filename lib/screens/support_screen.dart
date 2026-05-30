import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../config/app_colors.dart';
import '../widgets/bora/bora_screen_app_bar.dart';

class SupportScreen extends StatefulWidget {
  const SupportScreen({super.key});

  @override
  State<SupportScreen> createState() => _SupportScreenState();
}

class _SupportScreenState extends State<SupportScreen> {
  final List<_ChatMessage> _messages = [];
  final TextEditingController _ctrl = TextEditingController();
  final ScrollController _scrollCtrl = ScrollController();
  bool _faqExpanded = false;

  static const _faqs = [
    _Faq(
      question: 'Como faço um pedido?',
      answer:
          'Na tela inicial, escolhe a categoria (Restaurantes, Supermercados, etc.), seleciona a loja, adiciona produtos ao carrinho e clica em "Finalizar Pedido". Escolhe o método de pagamento e confirma.',
    ),
    _Faq(
      question: 'Como acompanho a minha entrega?',
      answer:
          'Assim que o estafeta aceitar o pedido, abrirá automaticamente um mapa de acompanhamento em tempo real. Podes também consultar o separador "Pedidos" para ver o estado atual.',
    ),
    _Faq(
      question: 'Métodos de pagamento disponíveis',
      answer:
          'Aceitamos Cartão de Crédito/Débito (via Stripe), MBWay e pagamento em Dinheiro (máx. €40). Seleciona o método no ecrã de pagamento antes de confirmar.',
    ),
    _Faq(
      question: 'Como contactar o estafeta?',
      answer:
          'No ecrã de acompanhamento de entrega, encontras o botão de chamada para falar diretamente com o estafeta atribuído ao teu pedido.',
    ),
    _Faq(
      question: 'Política de cancelamento',
      answer:
          'Podes cancelar o pedido enquanto está em estado "A preparar". Após o estafeta ter aceite, o cancelamento já não é possível. Contacta o suporte em caso de urgência.',
    ),
    _Faq(
      question: 'Como usar os meus tokens?',
      answer:
          'No ecrã de pagamento, verás a opção de aplicar os teus Bora Tokens como desconto (máx. 50% do total). Cada 100 tokens valem €0,50.',
    ),
  ];

  @override
  void initState() {
    super.initState();
    _addBot(
      'Olá! 👋 Sou o assistente de suporte Bora. Como posso ajudar?\n\nEscolhe uma pergunta frequente abaixo ou escreve a tua dúvida.',
    );
  }

  @override
  void dispose() {
    _ctrl.dispose();
    _scrollCtrl.dispose();
    super.dispose();
  }

  void _addBot(String text) {
    setState(() {
      _messages.add(_ChatMessage(text: text, isUser: false));
    });
    _scrollToBottom();
  }

  void _sendMessage(String text) {
    final trimmed = text.trim();
    if (trimmed.isEmpty) return;
    _ctrl.clear();

    setState(() {
      _messages.add(_ChatMessage(text: trimmed, isUser: true));
    });
    _scrollToBottom();

    // Match FAQ
    final lower = trimmed.toLowerCase();
    final match = _faqs.where((f) {
      return f.question.toLowerCase().contains(lower) ||
          lower
              .split(' ')
              .any((w) => w.length > 3 && f.question.toLowerCase().contains(w));
    }).firstOrNull;

    Future.delayed(const Duration(milliseconds: 400), () {
      if (!mounted) return;
      if (match != null) {
        _addBot(match.answer);
      } else {
        _addBot(
          'Não encontrei uma resposta automática para isso. 😔\n\nContacta-nos diretamente:\n📧 boraappbora@gmail.com\n📞 +351 937 501 673',
        );
      }
    });
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollCtrl.hasClients) {
        _scrollCtrl.animateTo(
          _scrollCtrl.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  Future<void> _launchEmail() async {
    final uri = Uri(
      scheme: 'mailto',
      path: 'boraappbora@gmail.com',
      query: 'subject=Suporte Bora App',
    );
    if (await canLaunchUrl(uri)) await launchUrl(uri);
  }

  Future<void> _launchPhone() async {
    final uri = Uri(scheme: 'tel', path: '+351937501673');
    if (await canLaunchUrl(uri)) await launchUrl(uri);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: BoraScreenAppBar(
        title: 'Suporte',
        actions: [
          IconButton(
            icon: const Icon(Icons.email_outlined),
            tooltip: 'Enviar email',
            onPressed: _launchEmail,
          ),
          IconButton(
            icon: const Icon(Icons.phone_outlined),
            tooltip: 'Ligar',
            onPressed: _launchPhone,
          ),
        ],
      ),
      body: Column(
        children: [
          // ── FAQ chips ────────────────────────────────────────────────────
          Container(
            color: Colors.white,
            child: ExpansionTile(
              leading: const Icon(Icons.quiz_outlined, color: AppColors.primary),
              title: const Text(
                'Perguntas frequentes',
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
              ),
              initiallyExpanded: _faqExpanded,
              onExpansionChanged: (v) => setState(() => _faqExpanded = v),
              children: _faqs
                  .map(
                    (faq) => ListTile(
                      dense: true,
                      title: Text(faq.question,
                          style: const TextStyle(fontSize: 13)),
                      trailing: const Icon(Icons.send,
                          size: 16, color: AppColors.primary),
                      onTap: () {
                        setState(() => _faqExpanded = false);
                        _sendMessage(faq.question);
                      },
                    ),
                  )
                  .toList(),
            ),
          ),

          // ── Chat messages ─────────────────────────────────────────────────
          Expanded(
            child: ListView.builder(
              controller: _scrollCtrl,
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
              itemCount: _messages.length,
              itemBuilder: (_, i) => _MessageBubble(msg: _messages[i]),
            ),
          ),

          // ── Input bar ─────────────────────────────────────────────────────
          Container(
            color: Colors.white,
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
            child: SafeArea(
              top: false,
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _ctrl,
                      textCapitalization: TextCapitalization.sentences,
                      decoration: InputDecoration(
                        hintText: 'Escreve a tua dúvida...',
                        filled: true,
                        fillColor: const Color(0xFFF0F0F0),
                        contentPadding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 10),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(24),
                          borderSide: BorderSide.none,
                        ),
                      ),
                      onSubmitted: _sendMessage,
                    ),
                  ),
                  const SizedBox(width: 8),
                  CircleAvatar(
                    backgroundColor: AppColors.primary,
                    child: IconButton(
                      icon:
                          const Icon(Icons.send, color: Colors.white, size: 18),
                      onPressed: () => _sendMessage(_ctrl.text),
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
}

// ─── Models ───────────────────────────────────────────────────────────────────

class _ChatMessage {
  const _ChatMessage({required this.text, required this.isUser});
  final String text;
  final bool isUser;
}

class _Faq {
  const _Faq({required this.question, required this.answer});
  final String question;
  final String answer;
}

// ─── Message bubble ───────────────────────────────────────────────────────────

class _MessageBubble extends StatelessWidget {
  const _MessageBubble({required this.msg});

  final _ChatMessage msg;

  @override
  Widget build(BuildContext context) {
    final isUser = msg.isUser;
    return Align(
      alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.78,
        ),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: isUser ? AppColors.primary : AppColors.surface,
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(18),
            topRight: const Radius.circular(18),
            bottomLeft: Radius.circular(isUser ? 18 : 4),
            bottomRight: Radius.circular(isUser ? 4 : 18),
          ),
          boxShadow: AppColors.shadowCard,
        ),
        child: Text(
          msg.text,
          style: TextStyle(
            color: isUser ? Colors.white : AppColors.textPrimary,
            fontSize: 14,
            height: 1.4,
          ),
        ),
      ),
    );
  }
}
