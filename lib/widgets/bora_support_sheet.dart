// Sessão 5A-2 B12 — BoraSupportSheet
// 3 cards condicionais: Bora IA (se enabled) + WhatsApp + Email.
// WhatsApp tap NÃO cria ticket (anti-spam — §31.6).

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../providers/support_settings_provider.dart';
import '../screens/support_chat_screen.dart';
import '../screens/support_email_form_screen.dart';

class BoraSupportSheet extends StatelessWidget {
  const BoraSupportSheet({super.key, this.orderId});

  final String? orderId;

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<SupportSettingsProvider>();
    return SafeArea(
      child: Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                margin: const EdgeInsets.only(bottom: 16),
                decoration: BoxDecoration(
                  color: Colors.grey.shade300,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const Text(
              'Como podemos ajudar?',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 4),
            if (orderId != null)
              Text(
                'Sobre pedido #$orderId',
                style: TextStyle(fontSize: 13, color: Colors.grey.shade600),
              ),
            const SizedBox(height: 16),
            if (provider.shouldShowAiCard)
              _ContactCard(
                icon: Icons.smart_toy_outlined,
                color: const Color(0xFFE65100),
                title: 'Falar com Bora IA',
                subtitle: 'Resposta imediata · 24/7',
                onTap: () {
                  Navigator.pop(context);
                  Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => SupportChatScreen(orderId: orderId),
                    ),
                  );
                },
              ),
            if (provider.shouldShowAiCard) const SizedBox(height: 12),
            _ContactCard(
              icon: Icons.chat_bubble_outline,
              color: const Color(0xFF25D366),
              title: 'WhatsApp',
              subtitle: provider.whatsappNumber,
              onTap: () {
                Navigator.pop(context);
                final msg = orderId == null
                    ? 'Olá Bora! Preciso de ajuda.'
                    : 'Olá Bora! Pedido #$orderId';
                final phone =
                    provider.whatsappNumber.replaceAll(RegExp(r'[^0-9]'), '');
                final uri = Uri.parse(
                  'https://wa.me/$phone?text=${Uri.encodeComponent(msg)}',
                );
                launchUrl(uri, mode: LaunchMode.externalApplication);
              },
            ),
            const SizedBox(height: 12),
            _ContactCard(
              icon: Icons.email_outlined,
              color: const Color(0xFF1976D2),
              title: 'Email',
              subtitle:
                  'Resposta em até ${provider.slaHours}h · ${provider.supportEmail}',
              onTap: () {
                Navigator.pop(context);
                Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => SupportEmailFormScreen(orderId: orderId),
                  ),
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _ContactCard extends StatelessWidget {
  const _ContactCard({
    required this.icon,
    required this.color,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final Color color;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.grey.shade50,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.grey.shade200),
        ),
        child: Row(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: color.withOpacity(0.12),
                borderRadius: BorderRadius.circular(22),
              ),
              child: Icon(icon, color: color),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title,
                      style: const TextStyle(
                          fontSize: 16, fontWeight: FontWeight.w600)),
                  const SizedBox(height: 2),
                  Text(subtitle,
                      style: TextStyle(
                          fontSize: 12, color: Colors.grey.shade600)),
                ],
              ),
            ),
            const Icon(Icons.chevron_right, color: Colors.grey),
          ],
        ),
      ),
    );
  }
}
