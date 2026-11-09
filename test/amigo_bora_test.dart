// Amigo Bora v1 (missão m4-amigo-bora-v1-2026-11-08): entrada única na home,
// cartão da primeira vez com "Agora não", saudação ao abrir, deixa, perfil e
// comparação linha a linha (os números vêm sempre do servidor).
import 'package:bora_app/screens/client/assistant/amigo_bora_entrada.dart';
import 'package:bora_app/screens/client/assistant/assistant_cards.dart';
import 'package:bora_app/screens/client/assistant/assistant_chat_screen.dart';
import 'package:bora_app/services/assistant_service.dart';
import 'package:bora_app/widgets/bora_assistant_fab.dart';
import 'package:bora_app/widgets/bora_support_fab.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() {
    AssistantFlags.reset();
    AssistantFlags.aplicar({
      'assistant_enabled': true,
      'assistant_personality_enabled': true,
      'assistant_amigo_welcome_text': '',
    });
  });

  group('resposta do servidor', () {
    test('saudação do costume com carrinho e "Sim, repete"', () {
      final r = AssistantReply.fromJson({
        'ok': true,
        'conversation_id': 'c1',
        'texto':
            'Olá, Ana! Hoje é sexta. Queres o do costume do Jyosmi Sushi? Tenho o teu último pedido pronto para repetir.',
        'saudacao': 'habitual',
        'propostas': [
          {'proposal_id': 'p1', 'restaurant_id': 'jyosmi-sushi-guarda', 'restaurant_name': 'Jyosmi Sushi', 'customer_total': 23.5, 'items': []}
        ],
        'acoes': [
          {'tipo': 'repetir_habitual', 'rotulo': 'Sim, repete', 'destino': 'p1'}
        ],
      });
      expect(r.saudacao, 'habitual');
      expect(r.propostas.single.proposalId, 'p1');
      expect(r.acoes.single.tipo, 'repetir_habitual');
      expect(r.acoes.single.destino, 'p1');
    });

    test('deixa vem com id, tipo e ação', () {
      final r = AssistantReply.fromJson({
        'texto': 'Que tal um sushi?',
        'deixa': {
          'id': 'd1',
          'tipo': 'parceiro_novo',
          'texto': 'Novidade na Bora: Loja Nova chegou há pouco. Queres espreitar?',
          'acao': {'tipo': 'abrir_loja', 'destino': 'loja-nova'}
        },
      });
      expect(r.deixa!.id, 'd1');
      expect(r.deixa!.acaoTipo, 'abrir_loja');
      expect(r.deixa!.acaoDestino, 'loja-nova');
      expect(AssistantReply.fromJson({'texto': 'x'}).deixa, isNull);
    });

    test('comparação só com linhas (sem total da outra app) não inventa total', () {
      final c = AssistantComparacao.fromJson({
        'app': 'Glovo',
        'total_outra_app_cents': null,
        'total_bora_cents': 2300,
        'loja_bora': 'Jyosmi Sushi',
        'diferenca_cents': null,
        'bora_mais_barato': false,
        'vencedor': 'sem_total',
        'linhas': [
          {'artigo': 'gyoza', 'quantidade': 1, 'outra_cents': 450, 'bora_cents': 490, 'diferenca_cents': -40},
          {'artigo': 'pizza', 'quantidade': 1, 'outra_cents': null, 'bora_cents': 900, 'diferenca_cents': null},
        ],
      });
      expect(c.temTotalOutra, isFalse);
      expect(c.igual, isFalse);
      expect(c.vencedor, 'sem_total');
      expect(c.linhas.first.diferencaCents, -40);
      expect(c.linhas.last.outraCents, isNull);
      expect(textoComparacao(c), contains('artigo a artigo'));
    });
  });

  group('o que o Amigo sabe de mim', () {
    test('frases sem valores, com a preposição certa do dia', () {
      final f = frasesDoPerfilAmigo({
        'nome_tratamento': 'Ana',
        'habitos': [
          {'dia': 5, 'periodo': 'noite', 'loja': 'Jyosmi Sushi'},
          {'dia': 6, 'periodo': 'almoco', 'loja': 'Boom'},
        ],
        'lojas_favoritas': [
          {'nome': 'Jyosmi Sushi'}
        ],
        'recorrentes': [
          {'nome': 'Combinado Tradicional'}
        ],
        'ticket_medio_eur': 19.88,
        'restricoes': ['sem glúten'],
      });
      expect(f, contains('Chamo-te Ana.'));
      expect(f, contains('Costumas pedir no Jyosmi Sushi à sexta à noite.'));
      expect(f, contains('Costumas pedir no Boom ao sábado ao almoço.'));
      expect(f, contains('Disseste-me: sem glúten.'));
      expect(f.join(' '), isNot(contains('19')));
      expect(frasesDoPerfilAmigo(null), isEmpty);
      expect(frasesDoPerfilAmigo(const {}), isEmpty);
    });
  });

  group('quando o Amigo saúda ao abrir', () {
    final agora = DateTime(2026, 11, 13, 19);
    test('conversa nova ou parada há mais de 6 h', () {
      expect(
          amigoDeveSaudar(personalidade: true, temMensagens: false, ultimaMensagem: null, temPedidoInicial: false, agora: agora),
          isTrue);
      expect(
          amigoDeveSaudar(personalidade: true, temMensagens: true, ultimaMensagem: DateTime(2026, 11, 13, 10), temPedidoInicial: false, agora: agora),
          isTrue);
      expect(
          amigoDeveSaudar(personalidade: true, temMensagens: true, ultimaMensagem: DateTime(2026, 11, 13, 18), temPedidoInicial: false, agora: agora),
          isFalse);
    });
    test('nunca com a personalidade desligada nem com mensagem/proposta inicial', () {
      expect(
          amigoDeveSaudar(personalidade: false, temMensagens: false, ultimaMensagem: null, temPedidoInicial: false, agora: agora),
          isFalse);
      expect(
          amigoDeveSaudar(personalidade: true, temMensagens: false, ultimaMensagem: null, temPedidoInicial: true, agora: agora),
          isFalse);
    });
  });

  group('entrada única na home', () {
    testWidgets('botão "Ajuda-me a escolher" + cartão; "Agora não" esconde só o cartão',
        (tester) async {
      SharedPreferences.setMockInitialValues({});
      var abriu = 0;
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(body: AmigoBoraEntrada(abrir: () => abriu++)),
      ));
      await tester.pumpAndSettle();

      expect(find.text('Ajuda-me a escolher'), findsOneWidget);
      expect(find.byKey(const Key('amigo-bora-cartao')), findsOneWidget);
      expect(find.text(kAmigoBoraBoasVindas), findsOneWidget);

      await tester.tap(find.byKey(const Key('amigo-bora-botao')));
      expect(abriu, 1);

      await tester.tap(find.byKey(const Key('amigo-bora-agora-nao')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('amigo-bora-cartao')), findsNothing);
      expect(find.text('Ajuda-me a escolher'), findsOneWidget);
      final p = await SharedPreferences.getInstance();
      expect(p.getBool(kAmigoBoraCartaoFechadoKey), isTrue);
    });

    testWidgets('cartão já fechado antes não volta', (tester) async {
      SharedPreferences.setMockInitialValues({kAmigoBoraCartaoFechadoKey: true});
      await tester.pumpWidget(const MaterialApp(home: Scaffold(body: AmigoBoraEntrada())));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('amigo-bora-cartao')), findsNothing);
      expect(find.text('Ajuda-me a escolher'), findsOneWidget);
    });

    testWidgets('sem personalidade: só o botão; assistente desligado: nada',
        (tester) async {
      SharedPreferences.setMockInitialValues({});
      AssistantFlags.aplicar({'assistant_enabled': true, 'assistant_personality_enabled': false});
      await tester.pumpWidget(const MaterialApp(home: Scaffold(body: AmigoBoraEntrada())));
      await tester.pumpAndSettle();
      expect(find.text('Ajuda-me a escolher'), findsOneWidget);
      expect(find.byKey(const Key('amigo-bora-cartao')), findsNothing);

      AssistantFlags.aplicar({'assistant_enabled': false});
      await tester.pumpAndSettle();
      expect(find.text('Ajuda-me a escolher'), findsNothing);
    });

    testWidgets('o botão flutuante do assistente saiu: fica só o do suporte',
        (tester) async {
      await tester.pumpWidget(const MaterialApp(
        home: Scaffold(floatingActionButton: BoraClientFabs()),
      ));
      expect(find.byType(BoraSupportFab), findsOneWidget);
      expect(find.byType(FloatingActionButton), findsOneWidget);
    });
  });

  testWidgets('a deixa é uma linha tocável', (tester) async {
    var tocou = 0;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: AmigoDeixaLinha(
          deixa: const AssistantDeixa(
              id: 'd1', tipo: 'tokens', texto: 'Tens 30 tokens a expirar.', acaoTipo: 'abrir_carteira'),
          onTap: () => tocou++,
        ),
      ),
    ));
    await tester.tap(find.byKey(const Key('amigo-deixa')));
    expect(tocou, 1);
    expect(find.text('Tens 30 tokens a expirar.'), findsOneWidget);
  });
}
