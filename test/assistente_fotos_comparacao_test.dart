// BORA ASSISTENTE — missão app-fechar 01/11/2026 (bloco B6), sem rede:
//   * várias fotos de uma vez: o corpo do pedido leva `images` com N fotos
//     (uma foto continua a ir por `image_base64`, para qualquer servidor);
//   * cartão "comparacao": o total do print da Glovo/Uber ao lado do total
//     mais barato do Bora, com os números que o servidor mandou.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:bora_app/screens/client/assistant/assistant_cards.dart';
import 'package:bora_app/services/assistant_service.dart';

AssistantFotoEnvio _foto(int i) =>
    AssistantFotoEnvio(base64: 'Zm90bz$i${'A' * 120}', mime: 'image/jpeg');

Map<String, dynamic> _comparacaoJson({
  String? app = 'Glovo',
  int outra = 2540,
  int bora = 2110,
  List<String> emFalta = const [],
}) =>
    {
      'app': app,
      'total_outra_app_cents': outra,
      'total_bora_cents': bora,
      'loja_bora': 'Continente Guarda',
      'restaurant_id': 'continente-guarda',
      'cobertura_pct': emFalta.isEmpty ? 100 : 80,
      'em_falta': emFalta,
      'diferenca_cents': outra - bora,
      'bora_mais_barato': outra - bora > 0,
      'nota':
          'Totais com entrega e taxas incluídas no Bora; o total da outra app é o que estava escrito no print.',
    };

Widget _host(Widget child) => MaterialApp(
      home: Scaffold(body: SingleChildScrollView(child: child)),
    );

void main() {
  group('corpo do pedido com fotos', () {
    test('várias fotos: `images` com N elementos e image_base64 vazio', () {
      final corpo = montarCorpoAssistente(
        conversationId: 'c1',
        message: 'compara com a glovo',
        imagens: [_foto(1), _foto(2), _foto(3)],
        platform: 'android',
        dropoffLat: 40.53,
        dropoffLng: -7.26,
      );
      final images = corpo['images'] as List;
      expect(images, hasLength(3));
      expect(images.first, {'base64': _foto(1).base64, 'mime': 'image/jpeg'});
      expect(images.last, {'base64': _foto(3).base64, 'mime': 'image/jpeg'});
      expect(corpo['image_base64'], isNull,
          reason: 'a mesma foto não pode ir duas vezes ao servidor');
      expect(corpo['image_mime'], isNull);
      expect(corpo['conversation_id'], 'c1');
      expect(corpo['message'], 'compara com a glovo');
      expect(corpo['platform'], 'android');
      expect(corpo['dropoff_lat'], 40.53);
      expect(corpo['apartment_delivery'], isFalse);
    });

    test(
        'uma foto continua pelos campos antigos (compatível com qualquer servidor)',
        () {
      final corpo = montarCorpoAssistente(
        conversationId: null,
        imagens: [
          AssistantFotoEnvio(base64: _foto(1).base64, mime: 'image/png')
        ],
        platform: 'ios',
      );
      expect(corpo.containsKey('images'), isFalse);
      expect(corpo['image_base64'], _foto(1).base64);
      expect(corpo['image_mime'], 'image/png');
    });

    test('o parâmetro antigo imageBase64 ainda funciona', () {
      final corpo = montarCorpoAssistente(
        conversationId: null,
        imageBase64: 'abc',
        imageMime: 'image/jpeg',
        platform: 'web',
      );
      expect(corpo['image_base64'], 'abc');
      expect(corpo.containsKey('images'), isFalse);
    });

    test('nunca manda mais do que o máximo da app', () {
      final corpo = montarCorpoAssistente(
        conversationId: null,
        imagens: [for (var i = 0; i < 7; i++) _foto(i)],
        platform: 'android',
      );
      expect(corpo['images'] as List, hasLength(kAssistantMaxFotos));
    });

    test('sem fotos: nem images nem image_base64', () {
      final corpo = montarCorpoAssistente(
          conversationId: null, message: 'arroz', platform: 'android');
      expect(corpo.containsKey('images'), isFalse);
      expect(corpo['image_base64'], isNull);
    });

    test('o tipo da foto sai dos bytes', () {
      expect(mimeDaImagem(const [0x89, 0x50, 0x4E, 0x47, 0x0D]), 'image/png');
      expect(mimeDaImagem(const [0xFF, 0xD8, 0xFF, 0xE0]), 'image/jpeg');
      expect(
          mimeDaImagem(const [
            0x52,
            0x49,
            0x46,
            0x46,
            0,
            0,
            0,
            0,
            0x57,
            0x45,
            0x42,
            0x50,
          ]),
          'image/webp');
      expect(mimeDaImagem(const []), 'image/jpeg');
    });
  });

  group('comparação com a outra app', () {
    test('lê o cartão do servidor e conta como cartão', () {
      final r = AssistantReply.fromJson({
        'texto': 'Li 3 artigos do carrinho da Glovo…',
        'propostas': const [],
        'comparacao': _comparacaoJson(emFalta: ['ovos']),
      });
      final c = r.comparacao!;
      expect(c.app, 'Glovo');
      expect(c.totalOutraAppCents, 2540);
      expect(c.totalBoraCents, 2110);
      expect(c.diferencaCents, 430);
      expect(c.boraMaisBarato, isTrue);
      expect(c.lojaBora, 'Continente Guarda');
      expect(c.emFalta, ['ovos']);
      expect(r.temCartoes, isTrue);
      expect(AssistantReply.fromJson({'texto': 'olá'}).comparacao, isNull);
    });

    test('sem nome da app fica "outra app"', () {
      final c = AssistantComparacao.fromJson(_comparacaoJson(app: null));
      expect(c.app, 'outra app');
    });

    testWidgets(
        'Bora mais barato: "Na Glovo deu X; no Bora … dá Y — mais barato Z"',
        (tester) async {
      await tester.pumpWidget(_host(AssistantComparacaoCard(
        comparacao:
            AssistantComparacao.fromJson(_comparacaoJson(emFalta: ['ovos'])),
      )));
      expect(find.byKey(const Key('assistente-comparacao')), findsOneWidget);
      expect(find.text('Comparação com a Glovo'), findsOneWidget);
      expect(
        find.text(
            'Na Glovo deu 25,40 €; no Bora, Continente Guarda dá 21,10 € — mais barato 4,30 €.'),
        findsOneWidget,
      );
      expect(find.text('Total na Glovo (do print)'), findsOneWidget);
      expect(find.text('25,40 €'), findsOneWidget);
      expect(find.text('Total no Bora · Continente Guarda'), findsOneWidget);
      expect(find.text('21,10 €'), findsOneWidget);
      expect(find.text('Continente Guarda não tem: ovos'), findsOneWidget);
      expect(find.textContaining('No Bora já conta a entrega e as taxas'),
          findsOneWidget);
    });

    testWidgets('outra app mais barata: diz com honestidade', (tester) async {
      await tester.pumpWidget(_host(AssistantComparacaoCard(
        comparacao: AssistantComparacao.fromJson(
            _comparacaoJson(app: 'Uber Eats', outra: 1990, bora: 2150)),
      )));
      expect(
        find.text(
            'Na Uber Eats deu 19,90 €; no Bora, Continente Guarda dá 21,50 € — desta vez a Uber Eats fica 1,60 € mais barata.'),
        findsOneWidget,
      );
      expect(find.textContaining('não tem'), findsNothing);
    });

    test('igual nos dois lados', () {
      final c = AssistantComparacao.fromJson(
          _comparacaoJson(outra: 2000, bora: 2000));
      expect(textoComparacao(c),
          'Na Glovo deu 20,00 €; no Bora, Continente Guarda dá 20,00 € — fica igual.');
    });
  });
}
