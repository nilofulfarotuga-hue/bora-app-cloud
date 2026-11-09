// Pesquisa "super inteligente" (missão m11, adendo 2, parte A — 09/11/2026):
// estado vazio com "Pede ao Amigo", ordem dos resultados, aprendizagem
// (pesquisa sem resultado → produto no carrinho) e o painel admin.
//
// A lógica da ordem no servidor (exato > começa > texto > sinónimo >
// categoria > erro de escrita > significado) está provada em PGlite
// (docs/pesquisa/provas/prova_pglite.mjs) e em produção com 60 pesquisas
// (docs/pesquisa/provas/antes-depois-60.csv).
import 'package:bora_app/screens/admin/admin_menu_registry.dart';
import 'package:bora_app/screens/admin/admin_pesquisas_sem_resultado_screen.dart';
import 'package:bora_app/services/assistant_service.dart';
import 'package:bora_app/services/pesquisa_aprendizagem.dart';
import 'package:bora_app/utils/pesquisa_resultados.dart';
import 'package:bora_app/widgets/pesquisa_sem_resultado.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Widget _app(Widget filho) => MaterialApp(home: Scaffold(body: filho));

void main() {
  group('estado vazio — nunca beco sem saída', () {
    setUp(() => AssistantFlags.enabled.value = true);

    testWidgets('dentro de uma loja: "Não encontrei X aqui" e "Pede ao Amigo" com a mensagem certa',
        (tester) async {
      String? enviada;
      await tester.pumpWidget(_app(PesquisaSemResultado(
        termo: ' gelado ',
        loja: "McDonald's",
        aoPedirAoAmigo: (m) => enviada = m,
      )));
      expect(find.text('Não encontrei "gelado" aqui.'), findsOneWidget);
      expect(find.text('Pede ao Amigo'), findsOneWidget);
      await tester.tap(find.byKey(const Key('pede-ao-amigo')));
      await tester.pump();
      expect(enviada,
          'Não encontrei "gelado" em McDonald\'s. Procura noutras lojas ou propõe-me um Favor.');
    });

    testWidgets('na lupa da home (sem loja): mensagem "na Bora" e as sugestões por baixo',
        (tester) async {
      String? enviada;
      await tester.pumpWidget(_app(PesquisaSemResultado(
        termo: 'xpto',
        aoPedirAoAmigo: (m) => enviada = m,
        extra: const Text('Pizza'),
      )));
      expect(find.text('Não encontrei "xpto".'), findsOneWidget);
      expect(find.text('Pizza'), findsOneWidget);
      await tester.tap(find.byKey(const Key('pede-ao-amigo')));
      expect(enviada, 'Não encontrei "xpto" na Bora. Procura noutras lojas ou propõe-me um Favor.');
    });

    testWidgets('com o assistente desligado no painel não mostra o botão (não leva a um ecrã morto)',
        (tester) async {
      AssistantFlags.enabled.value = false;
      addTearDown(() => AssistantFlags.enabled.value = true);
      await tester.pumpWidget(_app(const PesquisaSemResultado(termo: 'gelado', loja: 'Wells')));
      expect(find.byKey(const Key('pede-ao-amigo')), findsNothing);
      expect(find.text('Experimenta outra palavra.'), findsOneWidget);
    });
  });

  group('ordem dos resultados', () {
    test('produtos por match_rank (mais alto primeiro), empates como vieram; secções à parte', () {
      final r = separarResultadosPesquisa([
        {'result_type': 'product', 'name': 'Ben-U-Ron 500mg', 'match_rank': 3.9},
        {'result_type': 'section', 'name': 'Saúde', 'match_rank': 10.2},
        {'result_type': 'product', 'name': 'Paracetamol Wellsmed', 'match_rank': 5.7},
        {'result_type': 'product', 'name': 'Supofen Paracetamol', 'match_rank': 4.6},
        {'result_type': 'product', 'name': 'Ben-U-Ron Caff', 'match_rank': 3.9},
        {'result_type': 'product', 'name': 'Sem rank'},
      ]);
      expect(r.seccoes.map((e) => e['name']), ['Saúde']);
      expect(r.produtos.map((e) => e['name']), [
        'Paracetamol Wellsmed', // começa por
        'Supofen Paracetamol', // contém
        'Ben-U-Ron 500mg', // sinónimo (empate: fica a ordem do servidor)
        'Ben-U-Ron Caff',
        'Sem rank',
      ]);
      expect(r.vazio, isFalse);
      expect(separarResultadosPesquisa(const []).vazio, isTrue);
    });
  });

  group('aprende sozinha', () {
    late List<(String, Map<String, dynamic>)> chamadas;
    late DateTime agora;
    late PesquisaAprendizagem a;

    setUp(() {
      chamadas = [];
      agora = DateTime(2026, 11, 9, 12);
      a = PesquisaAprendizagem(
        rpc: (f, p) async => chamadas.add((f, p)),
        agora: () => agora,
        espera: const Duration(milliseconds: 10),
      );
    });

    test('pesquisa sem resultado fica registada uma vez (depois de parado), não letra a letra', () async {
      a.semResultado('ge', restaurantId: 'mcdonalds-guarda'); // curto demais
      a.semResultado('gel', restaurantId: 'mcdonalds-guarda');
      a.semResultado('gelado', restaurantId: 'mcdonalds-guarda');
      await Future<void>.delayed(const Duration(milliseconds: 40));
      a.semResultado('gelado', restaurantId: 'mcdonalds-guarda'); // repetida
      await Future<void>.delayed(const Duration(milliseconds: 40));
      expect(chamadas.length, 1);
      expect(chamadas.single.$1, 'pesquisa_registar_sem_resultado');
      expect(chamadas.single.$2,
          {'p_termo': 'gelado', 'p_restaurant_id': 'mcdonalds-guarda', 'p_origem': 'loja'});
    });

    test('voltou a haver resultados → não regista; sair do ecrã envia o que estava parado', () async {
      a.semResultado('gelado', restaurantId: 'kfc-guarda');
      a.comResultado();
      await Future<void>.delayed(const Duration(milliseconds: 40));
      expect(chamadas, isEmpty);
      a.semResultado('pistacio', restaurantId: 'kfc-guarda');
      a.sairDoEcra();
      await Future<void>.delayed(Duration.zero);
      expect(chamadas.single.$2['p_termo'], 'pistacio');
    });

    test('produto posto no carrinho da mesma loja a seguir → guarda a escolha', () async {
      expect(a.carrinhoMudou(['x1'], 'mcdonalds-guarda'), isNull); // 1.ª leitura
      a.semResultado('gelado', restaurantId: 'mcdonalds-guarda');
      agora = agora.add(const Duration(minutes: 3));
      final aprendido = a.carrinhoMudou(['x1', 'mcflurry-oreo'], 'mcdonalds-guarda');
      expect(aprendido, 'mcflurry-oreo');
      await Future<void>.delayed(Duration.zero);
      final escolha = chamadas.where((c) => c.$1 == 'pesquisa_aprender_escolha').single;
      expect(escolha.$2, {
        'p_termo': 'gelado',
        'p_restaurant_id': 'mcdonalds-guarda',
        'p_product_id': 'mcflurry-oreo',
      });
      // só uma vez por pesquisa
      expect(a.carrinhoMudou(['x1', 'mcflurry-oreo', 'outro'], 'mcdonalds-guarda'), isNull);
    });

    test('outra loja, ou passou a janela, não ensina nada', () {
      a.carrinhoMudou(const [], 'wells-guarda');
      a.semResultado('paracetamol', restaurantId: 'wells-guarda');
      expect(a.carrinhoMudou(['bigmac'], 'mcdonalds-guarda'), isNull);
      a.semResultado('paracetamol', restaurantId: 'wells-guarda');
      agora = agora.add(const Duration(minutes: 30));
      expect(a.carrinhoMudou(['bigmac', 'benuron'], 'wells-guarda'), isNull);
    });

    test('pesquisa na lupa da home (sem loja) aprende com a loja onde ele comprou', () {
      a.carrinhoMudou(const [], null);
      a.semResultado('gelado', origem: 'lupa');
      expect(a.carrinhoMudou(['sundae'], 'kfc-guarda'), 'sundae');
    });
  });

  group('painel admin "Pesquisas sem resultado"', () {
    test('está no menu do painel', () {
      final item = adminMenuAllItems().where((i) => i.id == 'clientes_pesquisas_sem_resultado');
      expect(item, hasLength(1));
      expect(item.single.title, 'Pesquisas sem resultado');
    });

    testWidgets('mostra os termos por loja, as escolhas e cria um sinônimo', (tester) async {
      tester.view.physicalSize = const Size(1000, 2400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      Map<String, Object?>? criado;
      final ativados = <(int, bool)>[];
      await tester.pumpWidget(MaterialApp(
        home: AdminPesquisasSemResultadoScreen(
          carregar: (dias) async => {
            'dias': dias,
            'total': 7,
            'termos_distintos': 2,
            'termos': [
              {
                'restaurant_id': 'mcdonalds-guarda',
                'loja': "McDonald's",
                'chave': 'pistacio',
                'termo': 'pistácio',
                'vezes': 5,
                'pessoas': 4,
                'resolvidas': 1,
                'tem_sinonimo': false,
                'sugestoes': [
                  {'product_id': 'm1', 'nome': 'McFlurry® Oreo®', 'vezes': 2},
                ],
              },
              {
                'restaurant_id': null,
                'loja': 'Lupa da home',
                'chave': 'xpto',
                'termo': 'xpto',
                'vezes': 2,
                'pessoas': 2,
                'resolvidas': 0,
                'tem_sinonimo': true,
                'sugestoes': [],
              },
            ],
            'aprendidos': [
              {'termo': 'docinho', 'loja': "McDonald's", 'produto': 'Tarte de Maçã', 'vezes': 3},
            ],
          },
          listar: (busca) async => [
            {'id': 9, 'termo': 'gelado', 'alvo': 'mcflurry', 'ativo': true, 'origem': 'manual', 'loja': null},
          ],
          criar: ({required termo, alvo, restaurantId, productId}) async {
            criado = {'termo': termo, 'alvo': alvo, 'restaurantId': restaurantId, 'productId': productId};
            return {'ok': true, 'id': 77};
          },
          ativar: (id, ativo) async {
            ativados.add((id, ativo));
            return {'ok': true};
          },
        ),
      ));
      await tester.pumpAndSettle();

      expect(find.text('7 pesquisas sem resultado · 2 termos diferentes'), findsOneWidget);
      expect(find.text('"pistácio"'), findsOneWidget);
      expect(find.textContaining("McDonald's · 5 vezes · 4 clientes"), findsOneWidget);
      expect(find.text('McFlurry® Oreo® (2)'), findsOneWidget);
      expect(find.text('já tem sinônimo'), findsOneWidget);
      expect(find.text('"docinho" → Tarte de Maçã'), findsOneWidget);
      expect(find.text('gelado → mcflurry'), findsOneWidget);

      await tester.tap(find.byKey(const Key('criar-sinonimo-pistacio-mcdonalds-guarda')));
      await tester.pumpAndSettle();
      expect(find.text('Criar sinônimo'), findsWidgets);
      await tester.enterText(find.byKey(const Key('sinonimo-alvo')), 'mcflurry');
      await tester.tap(find.text('McFlurry® Oreo®').last);
      await tester.pump();
      await tester.tap(find.byKey(const Key('sinonimo-gravar')));
      await tester.pumpAndSettle();
      expect(criado, {
        'termo': 'pistácio',
        'alvo': 'mcflurry',
        'restaurantId': 'mcdonalds-guarda',
        'productId': 'm1',
      });
      expect(find.text('Sinônimo criado. A pesquisa já usa.'), findsOneWidget);

      await tester.tap(find.byType(Switch).first);
      await tester.pumpAndSettle();
      expect(ativados, [(9, false)]);
    });
  });
}
