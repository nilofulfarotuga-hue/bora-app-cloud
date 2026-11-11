import 'dart:io';

import 'package:bora_app/l10n/strings_en.dart';
import 'package:bora_app/services/aviso_ia.dart';
import 'package:bora_app/widgets/aviso_alergenios.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Missão fechar-tudo-2026-11-10, bloco E6, revisto a 11/11/2026: o aviso de
/// IA (Reg. (UE) 2024/1689, art. 50.º/1) SAIU DA FALA do Amigo (ordem do
/// Danilo, 10:54) e está na etiqueta "assistente virtual" do cabeçalho do ecrã
/// do Amigo e na Informação legal; alergias/dietas só com o "sim" do cliente
/// (RGPD, art. 9.º) e, enquanto um prato não tem os 14 alergénios, a app manda
/// contactar a loja antes de pagar (Reg. (UE) 1169/2011).
void main() {
  group('aviso de IA: fora da fala, sempre à vista', () {
    test('a frase antiga sai das respostas guardadas', () {
      expect(semAvisoIA('$kAvisoIA Olá! Sou o Amigo Bora.'), 'Olá! Sou o Amigo Bora.');
      expect(semAvisoIA('Aqui tens.'), 'Aqui tens.');
    });

    test('o ecrã do Amigo não põe o aviso na fala e mostra a etiqueta', () {
      final s = File('lib/screens/client/assistant/amigo_screen.dart')
          .readAsStringSync();
      expect(s, isNot(contains('comAvisoIA(')));
      expect(s, contains("'Olá! Sou o Amigo Bora. Fala comigo: estou aqui para o que precisares.'.tr"));
      expect(s, contains("Text('assistente virtual'.tr,"));
      expect(s, contains('await _voz.falar(semAvisoIA(r.texto));'));
    });

    test('a etiqueta "assistente virtual" também está em inglês', () {
      expect(kStringsEn['assistente virtual'], 'virtual assistant');
      expect(
          kStringsEn['Olá! Sou o Amigo Bora. Fala comigo: estou aqui para o que precisares.'],
          isNot(contains('AI')));
    });

    test('o chat do suporte humano NÃO mudou: diz na 1.ª resposta que é assistente virtual', () {
      final s = File('supabase/functions/support-human-chat/index.ts').readAsStringSync();
      expect(s, contains('a assistente virtual (inteligência artificial) de apoio ao cliente'));
      expect(s, contains('Na tua PRIMEIRA resposta de cada conversa diz numa frase curta que és a assistente virtual da Bora'));
    });

    test('a Informação legal diz que o Amigo é um assistente virtual', () {
      expect(kAvisoLegalAssistente, contains('assistente virtual automático (inteligência'));
      expect(kAvisoLegalAssistente, contains('Não substitui o apoio humano'));
      final legal = File('lib/screens/legal_info_screen.dart').readAsStringSync();
      expect(legal, contains('kAvisoLegalAssistente'));
    });
  });

  group('servidor do assistente (client-assistant)', () {
    final idx = File('supabase/functions/client-assistant/index.ts')
        .readAsStringSync();

    test('nenhuma fala nem saudação leva o aviso de IA', () {
      expect(idx, isNot(contains('comAvisoIA(')));
      expect(idx, contains('finalText = semAvisoIA(finalText);'));
      expect(idx, contains('texto: s.welcome,'));
      expect(idx, contains('const texto = saudacaoHabitual(hab, perfil);'));
      expect(idx, contains('texto: saudacaoSimples(m, perfil, s.amigoWelcome),'));
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
