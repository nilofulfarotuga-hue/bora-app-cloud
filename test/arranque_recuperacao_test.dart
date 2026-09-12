import 'package:flutter_test/flutter_test.dart';

import 'package:bora_app/main.dart' show arranqueEmRecuperacao;

/// Fixa o comportamento apanhado ao vivo a 2026-08-28: o Supabase **substitui**
/// o fragmento do `redirectTo` em vez de lhe acrescentar o token, por isso a
/// rota `/#/redefinir-palavra-passe` nunca chega à app e o cliente aterrava no
/// ecrã de escolha de perfil. Quem reconhece a ligação é esta função.
void main() {
  group('arranqueEmRecuperacao', () {
    test('a forma REAL do link do email — o Supabase substitui o fragmento', () {
      // Foi exactamente isto que o servidor devolveu no teste ao vivo:
      // Location: https://app.boraguarda.com#access_token=…&type=recovery
      expect(
        arranqueEmRecuperacao(Uri.parse(
            'https://app.boraguarda.com/#access_token=abc123'
            '&expires_in=3600&refresh_token=xyz&token_type=bearer'
            '&type=recovery')),
        isTrue,
      );
    });

    test('a forma antiga, com a rota à frente do token', () {
      expect(
        arranqueEmRecuperacao(Uri.parse(
            'https://app.boraguarda.com/#/redefinir-palavra-passe'
            '#access_token=abc123&type=recovery')),
        isTrue,
      );
    });

    test('o formato de código (PKCE) na query também conta', () {
      expect(
        arranqueEmRecuperacao(
            Uri.parse('https://app.boraguarda.com/?type=recovery&code=abc')),
        isTrue,
      );
    });

    test('o endereço antigo continua a ser reconhecido', () {
      expect(
        arranqueEmRecuperacao(Uri.parse(
            'https://bora-app-web.pages.dev/#access_token=a&type=recovery')),
        isTrue,
      );
    });

    test('um arranque normal NÃO abre o ecrã de palavra-passe', () {
      expect(arranqueEmRecuperacao(Uri.parse('https://app.boraguarda.com/')),
          isFalse);
      expect(
        arranqueEmRecuperacao(Uri.parse('https://app.boraguarda.com/#/loja/x')),
        isFalse,
      );
    });

    test('confirmar email e convite NÃO abrem o ecrã de palavra-passe', () {
      // Estes têm ecrã próprio; abrir aqui o de redefinir seria mandar o
      // utilizador escolher uma palavra-passe que ele não pediu para mudar.
      expect(
        arranqueEmRecuperacao(Uri.parse(
            'https://app.boraguarda.com/#access_token=a&type=signup')),
        isFalse,
      );
      expect(
        arranqueEmRecuperacao(Uri.parse(
            'https://app.boraguarda.com/#access_token=a&type=invite')),
        isFalse,
      );
    });

    test('o erro de ligação expirada não abre o ecrã', () {
      // Location real de um token gasto:
      // #error=access_denied&error_code=otp_expired&…
      expect(
        arranqueEmRecuperacao(Uri.parse(
            'https://app.boraguarda.com/#error=access_denied'
            '&error_code=otp_expired'
            '&error_description=Email+link+is+invalid+or+has+expired')),
        isFalse,
      );
    });
  });
}
