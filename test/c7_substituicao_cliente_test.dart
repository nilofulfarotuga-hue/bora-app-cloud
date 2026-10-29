import 'package:bora_app/l10n/bora_lang.dart';
import 'package:bora_app/models/order_service_type.dart';
import 'package:bora_app/services/substituicao_service.dart';
import 'package:bora_app/widgets/substituicao_seletor.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// C7 (adendo 5, item 7, 29/10/2026) — SUBSTITUIÇÃO ESCOLHIDA ANTES DE PAGAR,
/// o lado do cliente: o interruptor nasce desligado, a pergunta só aparece em
/// mercados não parceiros e Favores com compra, a última escolha pré-marca, e a
/// escolha só vai para o servidor quando o pedido tem id real (3 tentativas, sem
/// nunca travar o pagamento).
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  /// Serviço de teste: guarda as chamadas ao servidor e responde ao gosto.
  SubstituicaoService servico({
    bool ligada = true,
    String? guardada,
    List<Map<String, dynamic>>? chamadas,
    Object? Function(String funcao, Map<String, dynamic> p)? aoChamar,
  }) =>
      SubstituicaoService(
        espera: Duration.zero,
        lerInterruptor: () async => ligada,
        rpc: (funcao, p) async {
          chamadas?.add({'funcao': funcao, ...p});
          final erro = aoChamar?.call(funcao, p);
          if (erro is Exception) throw erro;
          if (funcao == 'client_get_substitution_preference') return guardada;
          return {'ok': true};
        },
      );

  group('SubstituicaoEscolha', () {
    test('os códigos são os do servidor', () {
      expect(SubstituicaoEscolha.trocar.codigo, 'trocar');
      expect(SubstituicaoEscolha.tirarDevolver.codigo, 'tirar_devolver');
      expect(SubstituicaoEscolha.ligar.codigo, 'ligar');
    });

    test('deCodigo lê o que o servidor devolve, com ou sem aspas', () {
      expect(
          SubstituicaoEscolha.deCodigo('trocar'), SubstituicaoEscolha.trocar);
      expect(SubstituicaoEscolha.deCodigo('"tirar_devolver"'),
          SubstituicaoEscolha.tirarDevolver);
      expect(
          SubstituicaoEscolha.deCodigo(' ligar '), SubstituicaoEscolha.ligar);
      expect(SubstituicaoEscolha.deCodigo(null), isNull);
      expect(SubstituicaoEscolha.deCodigo(''), isNull);
      expect(SubstituicaoEscolha.deCodigo('qualquer'), isNull);
    });

    test('cada opção tem título e frase própria (cliente, estafeta e admin)',
        () {
      final titulos = SubstituicaoEscolha.values.map((e) => e.titulo).toSet();
      final frases =
          SubstituicaoEscolha.values.map((e) => e.fraseEstafeta).toSet();
      final admin = SubstituicaoEscolha.values.map((e) => e.textoAdmin).toSet();
      expect(titulos.length, 3);
      expect(frases.length, 3);
      expect(admin.length, 3);
    });
  });

  group('substituicaoAplica', () {
    test('mercado que não é parceiro: sim; parceiro: não', () {
      expect(
          substituicaoAplica(
              serviceType: OrderServiceType.storeShopping,
              lojaParceira: false,
              favorComLista: false),
          isTrue);
      expect(
          substituicaoAplica(
              serviceType: OrderServiceType.storeShopping,
              lojaParceira: true,
              favorComLista: false),
          isFalse);
    });

    test('Favor: só com compra (lista)', () {
      expect(
          substituicaoAplica(
              serviceType: OrderServiceType.errand,
              lojaParceira: false,
              favorComLista: true),
          isTrue);
      expect(
          substituicaoAplica(
              serviceType: OrderServiceType.errand,
              lojaParceira: false,
              favorComLista: false),
          isFalse);
    });

    test('restaurante, takeaway, encomenda e recado: nunca', () {
      for (final t in [
        OrderServiceType.restaurant,
        OrderServiceType.takeaway,
        OrderServiceType.carryGroceries,
        OrderServiceType.sendPackage,
      ]) {
        expect(
            substituicaoAplica(
                serviceType: t, lojaParceira: false, favorComLista: true),
            isFalse,
            reason: '$t');
      }
    });
  });

  group('SubstituicaoService', () {
    test('o interruptor que falha a ler vale DESLIGADO', () async {
      final s = SubstituicaoService(
          lerInterruptor: () async => throw Exception('sem rede'));
      expect(await s.ligada(), isFalse);
    });

    test('lê o interruptor uma vez e guarda 2 minutos', () async {
      var leituras = 0;
      final s = SubstituicaoService(lerInterruptor: () async {
        leituras++;
        return true;
      });
      expect(await s.ligada(), isTrue);
      expect(await s.ligada(), isTrue);
      expect(leituras, 1);
    });

    test('escolhaGuardada: lê o que o servidor devolve; falhar dá null',
        () async {
      expect(await servico(guardada: 'tirar_devolver').escolhaGuardada(),
          SubstituicaoEscolha.tirarDevolver);
      expect(await servico(guardada: null).escolhaGuardada(), isNull);
      final semRede = servico(aoChamar: (_, __) => Exception('sem rede'));
      expect(await semRede.escolhaGuardada(), isNull);
    });

    test('gravar manda o pedido e o código ao servidor', () async {
      final chamadas = <Map<String, dynamic>>[];
      final ok = await servico(chamadas: chamadas)
          .gravar('ord-1', SubstituicaoEscolha.tirarDevolver);
      expect(ok, isTrue);
      expect(chamadas, [
        {
          'funcao': 'client_set_substitution_preference',
          'p_order_id': 'ord-1',
          'p_pref': 'tirar_devolver',
        }
      ]);
    });

    test('rede a falhar: 3 tentativas e devolve false sem lançar', () async {
      final chamadas = <Map<String, dynamic>>[];
      final s = servico(
          chamadas: chamadas, aoChamar: (_, __) => Exception('sem rede'));
      expect(await s.gravar('ord-1', SubstituicaoEscolha.trocar), isFalse);
      expect(chamadas.length, 3);
    });

    test('o servidor recusa de vez (já recolhido): não repete', () async {
      final chamadas = <Map<String, dynamic>>[];
      final s = servico(
          chamadas: chamadas,
          aoChamar: (_, __) => Exception('ORDER_ALREADY_PICKED_UP: pickedUp'));
      expect(await s.gravar('ord-1', SubstituicaoEscolha.ligar), isFalse);
      expect(chamadas.length, 1);
    });

    test('a escolha pendente vai uma vez só, com o id do pedido', () async {
      final chamadas = <Map<String, dynamic>>[];
      final s = servico(chamadas: chamadas);
      final dono = Object();
      s.definirPendente(dono, SubstituicaoEscolha.trocar);

      s.gravarPendenteEmSegundoPlano('ord-9');
      await Future<void>.delayed(Duration.zero);
      expect(chamadas.length, 1);
      expect(chamadas.first['p_order_id'], 'ord-9');
      expect(s.pendente, isNull, reason: 'já foi: não vai a outro pedido');

      s.gravarPendenteEmSegundoPlano('ord-10');
      await Future<void>.delayed(Duration.zero);
      expect(chamadas.length, 1);
    });

    test('sem escolha, ou sem id de pedido, não chama o servidor', () async {
      final chamadas = <Map<String, dynamic>>[];
      final s = servico(chamadas: chamadas);
      s.gravarPendenteEmSegundoPlano('ord-1'); // nada pendente
      s.definirPendente(Object(), SubstituicaoEscolha.trocar);
      s.gravarPendenteEmSegundoPlano(null); // pedido sem id
      await Future<void>.delayed(Duration.zero);
      expect(chamadas, isEmpty);
      expect(s.pendente, SubstituicaoEscolha.trocar,
          reason: 'sem id não gasta a escolha');
    });

    test('largarPendente só limpa se a escolha ainda for de quem a registou',
        () {
      final s = servico();
      final a = Object();
      final b = Object();
      s.definirPendente(a, SubstituicaoEscolha.trocar);
      s.definirPendente(b, SubstituicaoEscolha.ligar);
      s.largarPendente(a);
      expect(s.pendente, SubstituicaoEscolha.ligar);
      s.largarPendente(b);
      expect(s.pendente, isNull);
    });
  });

  group('SubstituicaoSeletor (ecrã de pagamento)', () {
    Widget app(SubstituicaoService s,
            {OrderServiceType tipo = OrderServiceType.storeShopping,
            bool parceira = false,
            bool favorComLista = false}) =>
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: SubstituicaoSeletor(
                servico: s,
                serviceType: tipo,
                lojaParceira: parceira,
                favorComLista: favorComLista,
              ),
            ),
          ),
        );

    IconData? icone(WidgetTester t, SubstituicaoEscolha e) {
      final inkWell = find.byKey(Key('substituicao_opcao_${e.codigo}'));
      final ic = find.descendant(of: inkWell, matching: find.byType(Icon));
      return t.widget<Icon>(ic).icon;
    }

    testWidgets('interruptor DESLIGADO: não desenha nada', (t) async {
      final s = servico(ligada: false, guardada: 'trocar');
      await t.pumpWidget(app(s));
      await t.pumpAndSettle();
      expect(find.byKey(const Key('substituicao_cartao')), findsNothing);
      expect(find.text('Se faltar um produto'), findsNothing);
      expect(s.pendente, isNull);
    });

    testWidgets(
        'interruptor ligado em mercado: mostra as 3 opções, nenhuma marcada',
        (t) async {
      final s = servico(ligada: true, guardada: null);
      await t.pumpWidget(app(s));
      await t.pumpAndSettle();

      expect(find.byKey(const Key('substituicao_cartao')), findsOneWidget);
      expect(find.text('Se faltar um produto'), findsOneWidget);
      expect(find.text('Trocar por um parecido'), findsOneWidget);
      expect(find.text('Tirar e devolver o valor'), findsOneWidget);
      expect(find.text('Falar comigo no chat'), findsOneWidget);
      for (final e in SubstituicaoEscolha.values) {
        expect(icone(t, e), Icons.radio_button_unchecked, reason: e.codigo);
      }
      expect(s.pendente, isNull, reason: 'sem escolha nada vai ao pedido');
    });

    testWidgets('a última escolha vem pré-marcada e já está pendente',
        (t) async {
      final s = servico(ligada: true, guardada: 'tirar_devolver');
      await t.pumpWidget(app(s));
      await t.pumpAndSettle();

      expect(icone(t, SubstituicaoEscolha.tirarDevolver),
          Icons.radio_button_checked);
      expect(
          icone(t, SubstituicaoEscolha.trocar), Icons.radio_button_unchecked);
      expect(icone(t, SubstituicaoEscolha.ligar), Icons.radio_button_unchecked);
      expect(s.pendente, SubstituicaoEscolha.tirarDevolver);
    });

    testWidgets('tocar numa opção muda a marca e a escolha pendente',
        (t) async {
      final s = servico(ligada: true, guardada: 'trocar');
      await t.pumpWidget(app(s));
      await t.pumpAndSettle();

      await t.tap(find.byKey(const Key('substituicao_opcao_ligar')));
      await t.pumpAndSettle();

      expect(icone(t, SubstituicaoEscolha.ligar), Icons.radio_button_checked);
      expect(
          icone(t, SubstituicaoEscolha.trocar), Icons.radio_button_unchecked);
      expect(s.pendente, SubstituicaoEscolha.ligar);
    });

    testWidgets('Favor com lista: aparece; Favor só recado: não', (t) async {
      await t.pumpWidget(
          app(servico(), tipo: OrderServiceType.errand, favorComLista: true));
      await t.pumpAndSettle();
      expect(find.byKey(const Key('substituicao_cartao')), findsOneWidget);

      await t.pumpWidget(
          app(servico(), tipo: OrderServiceType.errand, favorComLista: false));
      await t.pumpAndSettle();
      expect(find.byKey(const Key('substituicao_cartao')), findsNothing);
    });

    testWidgets('restaurante e loja parceira: não aparece, mesmo ligado',
        (t) async {
      await t.pumpWidget(app(servico(), tipo: OrderServiceType.restaurant));
      await t.pumpAndSettle();
      expect(find.byKey(const Key('substituicao_cartao')), findsNothing);

      await t.pumpWidget(app(servico(), parceira: true));
      await t.pumpAndSettle();
      expect(find.byKey(const Key('substituicao_cartao')), findsNothing);
    });

    testWidgets('sair do ecrã larga a escolha (não vai a outro pedido)',
        (t) async {
      final s = servico(ligada: true, guardada: 'trocar');
      await t.pumpWidget(app(s));
      await t.pumpAndSettle();
      expect(s.pendente, SubstituicaoEscolha.trocar);

      await t.pumpWidget(const MaterialApp(home: Scaffold(body: SizedBox())));
      expect(s.pendente, isNull);
    });
  });

  group('SubstituicaoCard em inglês', () {
    tearDown(() => BoraLang.notifier.value = AppLang.pt);

    testWidgets('as três opções e o título traduzem-se', (t) async {
      BoraLang.notifier.value = AppLang.en;
      await t.pumpWidget(MaterialApp(
        home: Scaffold(
          body: SubstituicaoCard(escolha: null, onChanged: (_) {}),
        ),
      ));
      expect(find.text('If a product is missing'), findsOneWidget);
      expect(find.text('Swap it for a similar one'), findsOneWidget);
      expect(find.text('Remove it and refund the amount'), findsOneWidget);
      expect(find.text('Talk to me in the chat'), findsOneWidget);
    });
  });
}
