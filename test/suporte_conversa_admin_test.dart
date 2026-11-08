// Adendo 1 da missão m4 (08/11/2026): o aviso do suporte abre a conversa e a
// equipa responde como pessoa. Funções puras do painel e do chat do cliente.
import 'package:bora_app/screens/admin/admin_suporte_conversas_screen.dart';
import 'package:bora_app/screens/support_chat_screen.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('link do aviso → conversa', () {
    const id = '24c369e0-5bbe-4a4e-a576-265aeaab8876';

    test('o link novo dos avisos e do push abre a sessão certa', () {
      expect(rotaConversaSuporte(id), '/admin/support/sessions/$id');
      expect(sessaoDoLink('/admin/support/sessions/$id'), id);
      expect(sessaoDoLink('/admin/support/sessions/$id?x=1'), id);
    });

    test('links que não são de conversa ficam de fora', () {
      expect(sessaoDoLink('/admin/support-escalations'), isNull);
      expect(sessaoDoLink('/admin/support'), isNull);
      expect(sessaoDoLink('/admin/support/sessions/'), isNull);
      expect(sessaoDoLink('/admin/support/sessions/nao-e-um-id'), isNull);
      expect(sessaoDoLink(null), isNull);
    });
  });

  group('contactos do cliente no painel', () {
    test('telefone português vira link de WhatsApp com 351', () {
      expect(numeroWhatsApp('912345678'), '351912345678');
      expect(numeroWhatsApp('+351 912 345 678'), '351912345678');
      expect(numeroWhatsApp(''), isNull);
      expect(numeroWhatsApp(null), isNull);
    });
  });

  group('chat do suporte do cliente', () {
    final agora = DateTime(2026, 11, 8, 21);

    test('só mostra cliente, robô e equipa (nunca ferramentas)', () {
      expect(kPapeisVisiveisSuporte, ['user', 'assistant', 'admin']);
      expect(kPapeisVisiveisSuporte.contains('tool'), isFalse);
    });

    test('conversa escalada continua 48 h para a resposta da equipa chegar', () {
      expect(
          sessaoSuporteContinua(
              endedAt: null,
              escalada: true,
              modo: 'ai',
              iniciadaEm: DateTime(2026, 11, 8, 20, 3),
              agora: agora),
          isTrue);
      expect(
          sessaoSuporteContinua(
              endedAt: null,
              escalada: true,
              modo: 'ai',
              iniciadaEm: DateTime(2026, 11, 5),
              agora: agora),
          isFalse);
    });

    test('com a equipa a falar (modo admin) a conversa nunca se perde', () {
      expect(
          sessaoSuporteContinua(
              endedAt: null,
              escalada: true,
              modo: 'admin',
              iniciadaEm: DateTime(2026, 11, 1),
              agora: agora),
          isTrue);
    });

    test('conversa terminada não volta', () {
      expect(
          sessaoSuporteContinua(
              endedAt: '2026-11-08T20:10:00Z',
              escalada: false,
              modo: 'ai',
              iniciadaEm: agora,
              agora: agora),
          isFalse);
    });

    test('o link do WhatsApp da Bora na resposta do robô fica tocável', () {
      const r =
          'Claro! Manda mensagem pelo WhatsApp: 937 501 673 (https://wa.me/351937501673).';
      expect(linkWhatsAppNoTexto(r), 'https://wa.me/351937501673');
      expect(linkWhatsAppNoTexto('sem link aqui'), isNull);
    });
  });
}
