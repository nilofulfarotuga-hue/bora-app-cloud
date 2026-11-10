import 'dart:io';

import 'package:bora_app/services/aviso_ia.dart';
import 'package:bora_app/widgets/aviso_alergenios.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Missão fechar-tudo-2026-11-10, bloco E6: o assistente/Amigo diz que é uma
/// IA na primeira fala (Reg. (UE) 2024/1689, art. 50.º/1), só guarda
/// alergias/dietas com o "sim" do cliente (RGPD, art. 9.º) e, enquanto um
/// prato não tem os 14 alergénios, a app manda contactar a loja antes de pagar
/// (Reg. (UE) 1169/2011).
void main() {
  group('primeira fala do Amigo', () {
    test('a primeira fala começa pelo aviso de IA', () {
      expect(comAvisoIA('Olá! Sou o Amigo.'), '$kAvisoIA Olá! Sou o Amigo.');
    });

    test('as falas seguintes ficam como estão', () {
      expect(comAvisoIA('Aqui tens.', primeiraFala: false), 'Aqui tens.');
    });

    test('se já diz que é uma IA, não se repete', () {
      const t = 'Olá! Sou o Amigo, uma inteligência artificial do Bora.';
      expect(comAvisoIA(t), t);
      expect(jaDizQueEIA('Sou uma IA.'), isTrue);
      expect(jaDizQueEIA('I am an AI.'), isTrue);
      expect(jaDizQueEIA('Eu ia pedir, bom dia.'), isFalse,
          reason: '"ia" do verbo ir e "dia" não são o aviso');
    });

    test('texto vazio: fica só o aviso', () {
      expect(comAvisoIA('  '), kAvisoIA);
    });

    test('o ecrã do Amigo põe o aviso na saudação feita sem o servidor', () {
      final s = File('lib/screens/client/assistant/amigo_screen.dart')
          .readAsStringSync();
      expect(s, contains('r ??= AssistantReply.texto(comAvisoIA('));
    });
  });

  group('servidor do assistente (client-assistant)', () {
    final idx = File('supabase/functions/client-assistant/index.ts')
        .readAsStringSync();

    test('primeira resposta de cada conversa e todas as saudações com aviso',
        () {
      expect(idx, contains('finalText = comAvisoIA(finalText, messagesCount === 0);'));
      expect(idx, contains('texto: comAvisoIA(s.welcome, true)'));
      expect(idx, contains('comAvisoIA(saudacaoHabitual(hab, perfil), true)'));
      expect(idx, contains('comAvisoIA(saudacaoSimples(m, perfil, s.amigoWelcome), true)'));
    });

    test('alergias e dietas só se guardam com consentimento explícito', () {
      expect(idx, contains('const saude = eDadoDeSaude(kind, key, value);'));
      expect(idx, contains("args.consentimento !== true || !consentimentoExplicito(userMessage)"));
      expect(idx, contains("error: 'sem_consentimento'"));
      expect(idx, contains("base: 'RGPD art. 9.º/2 a)'"));
    });
  });

  group('alergénios em falta', () {
    test('lista vazia ou nula = por preencher', () {
      expect(alergeniosEmFalta(null), isTrue);
      expect(alergeniosEmFalta(const []), isTrue);
      expect(alergeniosEmFalta(const ['gluten']), isFalse);
    });

    test('carrinho: basta um prato sem alergénios (ou fora do menu)', () {
      final menu = {
        'p1': ['gluten', 'leite'],
        'p2': <String>[],
      };
      expect(carrinhoComAlergeniosEmFalta(['p1'], menu), isFalse);
      expect(carrinhoComAlergeniosEmFalta(['p1', 'p2'], menu), isTrue);
      expect(carrinhoComAlergeniosEmFalta(['p1', 'p9'], menu), isTrue,
          reason: 'prato que não está no menu carregado: sem informação');
      expect(carrinhoComAlergeniosEmFalta(const [], menu), isFalse);
    });

    testWidgets('o aviso diz para contactar a loja antes de pagar',
        (tester) async {
      await tester.pumpWidget(const MaterialApp(
          home: Scaffold(body: AvisoAlergenios(noCarrinho: true))));
      expect(find.text('Alergénios: contacta a loja antes de pagar.'),
          findsOneWidget);
      expect(find.textContaining('14 alergénios'), findsOneWidget);
    });

    testWidgets('na ficha do produto, só a frase principal', (tester) async {
      await tester.pumpWidget(
          const MaterialApp(home: Scaffold(body: AvisoAlergenios())));
      expect(find.text('Alergénios: contacta a loja antes de pagar.'),
          findsOneWidget);
      expect(find.textContaining('14 alergénios'), findsNothing);
    });

    test('ficha do produto e carrinho usam o aviso', () {
      final ficha =
          File('lib/screens/product_detail_screen.dart').readAsStringSync();
      expect(ficha, contains('const AvisoAlergenios()'));
      final carrinho = File('lib/screens/cart_screen.dart').readAsStringSync();
      expect(carrinho, contains('AvisoAlergenios(noCarrinho: true)'));
      expect(carrinho, contains('carrinhoComAlergeniosEmFalta('));
    });

    test('migração: carimbo por gatilho, sem coluna repetida', () {
      final sql = File(
              'supabase/migrations/20261110190100_products_alergenios_preenchido_em.sql')
          .readAsStringSync();
      expect(sql, contains('ADD COLUMN IF NOT EXISTS alergenios_preenchido_em timestamptz'));
      expect(sql, contains('BEFORE INSERT OR UPDATE OF allergens ON public.products'));
      expect(sql, isNot(contains('alergenios text[]')),
          reason: 'os 14 alergénios já vivem em products.allergens');
    });
  });
}
