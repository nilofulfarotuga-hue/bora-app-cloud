// Painel admin — Ajustes de peso: a secção "Ensaio do cartão (modo de teste da
// Stripe)" e a dívida (a Bora assumiu) no detalhe do pedido. Missão
// fechar-tudo-2026-11-10, Bloco C. Sem rede: a RPC e as leituras são
// substituídas pelos ganchos `pedirEnsaio` / `carregar`.
import 'package:bora_app/screens/admin/admin_ajustes_peso_screen.dart';
import 'package:bora_app/screens/admin/admin_ensaio_cartao_peso_section.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Widget _app(Widget filho) => MaterialApp(
      home: Scaffold(body: SingleChildScrollView(child: filho)),
    );

Map<String, dynamic> _ensaio(String id, String caso, String estado,
        {String? esperado, String? resultado, String? erro}) =>
    {
      'id': id,
      'caso': caso,
      'estado': estado,
      'esperado': esperado,
      'resultado': resultado,
      'valor_original_cents': 1000,
      'diferenca_cents': caso == 'a_menos' ? -180 : 250,
      'pi_original': estado == 'erro' ? null : 'pi_teste_1',
      'pi_extra': resultado == 'cartao_cobrado' ? 'pi_teste_2' : null,
      'erro': erro,
      'criado_em': '2026-11-10T21:30:00Z',
    };

void main() {
  group('textos do ensaio', () {
    test('casos, resultados e erros em PT-BR', () {
      expect(textoCasoEnsaioPeso('a_mais'), 'Melancia a mais');
      expect(textoCasoEnsaioPeso('pede_autenticacao'), 'Banco pede autenticação');
      expect(textoResultadoEnsaioPeso('bora_assume'), 'a Bora assume (pedido segue)');
      expect(textoResultadoEnsaioPeso(null), '—');
      expect(textoErroEnsaioPeso('falta_chave_teste'), contains('Falta a chave de teste'));
      expect(textoErroEnsaioPeso('falta_chave_teste'), contains('STRIPE_TEST_SECRET_KEY_EMPRESA'));
      expect(textoErroEnsaioPeso(null), '');
      expect(kCasosEnsaioCartaoPeso.map((c) => c.$1).toList(),
          ['a_mais', 'a_menos', 'recusado', 'pede_autenticacao']);
    });

    test('centimosBoraAssumiuPeso: só o que a Bora assumiu, só a mais', () {
      expect(
          centimosBoraAssumiuPeso([
            {'settled_via': 'bora_assume', 'delta_client_cents': 192},
            {'settled_via': 'bora_assume', 'delta_client_cents': 58},
            {'settled_via': 'ignorado_nao_ha', 'delta_client_cents': 40},
          ]),
          250);
      expect(
          centimosBoraAssumiuPeso([
            {'settled_via': 'cartao_cobrado', 'delta_client_cents': 250},
            {'settled_via': 'carteira', 'delta_client_cents': -180},
          ]),
          0);
    });
  });

  testWidgets('mostra os 4 botões e os resultados (verde, falhou, falta chave)',
      (tester) async {
    await tester.pumpWidget(_app(EnsaioCartaoPesoSection(
      carregar: () async => [
        _ensaio('e3', 'recusado', 'ok', esperado: 'bora_assume', resultado: 'bora_assume'),
        _ensaio('e2', 'a_mais', 'ok', esperado: 'cartao_cobrado', resultado: 'cartao_cobrado'),
        _ensaio('e1', 'a_mais', 'erro', esperado: 'cartao_cobrado', erro: 'falta_chave_teste'),
      ],
      pedirEnsaio: (_) async => {'ok': true},
    )));
    await tester.pumpAndSettle();

    expect(find.text('Ensaio do cartão (modo de teste da Stripe)'), findsOneWidget);
    for (final caso in ['a_mais', 'a_menos', 'recusado', 'pede_autenticacao']) {
      expect(find.byKey(Key('ensaio_cartao_peso_$caso')), findsOneWidget);
    }
    expect(find.text('OK'), findsNWidgets(2));
    expect(find.text('ERRO'), findsOneWidget);
    expect(find.text('Esperado: cartão cobrado · Deu: cartão cobrado'), findsOneWidget);
    expect(find.text('Esperado: a Bora assume (pedido segue) · Deu: a Bora assume (pedido segue)'),
        findsOneWidget);
    expect(find.textContaining('Falta a chave de teste'), findsOneWidget);
    expect(find.text('Stripe (teste): pi_teste_1 → pi_teste_2'), findsOneWidget);
  });

  testWidgets('tocar num caso pede o ensaio desse caso e lê o resultado novo',
      (tester) async {
    final pedidos = <String>[];
    var leituras = 0;
    await tester.pumpWidget(_app(EnsaioCartaoPesoSection(
      esperaEntreLeituras: Duration.zero,
      leiturasDepoisDoPedido: 2,
      pedirEnsaio: (caso) async {
        pedidos.add(caso);
        return {'ok': true, 'caso': caso};
      },
      carregar: () async {
        leituras++;
        return leituras == 1
            ? <Map<String, dynamic>>[]
            : [_ensaio('n1', 'a_menos', 'ok', esperado: 'carteira', resultado: 'carteira')];
      },
    )));
    await tester.pumpAndSettle();
    expect(find.text('Ainda não houve nenhum ensaio.'), findsOneWidget);

    await tester.tap(find.byKey(const Key('ensaio_cartao_peso_a_menos')));
    await tester.pumpAndSettle();

    expect(pedidos, ['a_menos']);
    expect(find.text('Melancia a menos'), findsOneWidget);
    expect(find.text('Esperado: carteira Bora (cartão não mexido) · Deu: carteira Bora (cartão não mexido)'),
        findsOneWidget);
  });

  testWidgets('RPC recusa: mostra o motivo e não lê nada', (tester) async {
    await tester.pumpWidget(_app(EnsaioCartaoPesoSection(
      esperaEntreLeituras: Duration.zero,
      pedirEnsaio: (_) async => {'ok': false, 'erro': 'cofre_sem_url_ou_chave'},
      carregar: () async => <Map<String, dynamic>>[],
    )));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('ensaio_cartao_peso_recusado')));
    await tester.pumpAndSettle();
    expect(find.text('Não deu para pedir o ensaio: cofre_sem_url_ou_chave'), findsOneWidget);
  });

  testWidgets('detalhe do pedido: a diferença que a Bora assumiu fica à vista',
      (tester) async {
    await tester.pumpWidget(_app(AdminAjustesPesoSection(
      orderId: 'pedido-1',
      carregar: () async => [
        {
          'item_name': 'Melancia',
          'qty': 1,
          'est_base_cents': 870,
          'real_base_cents': 1087,
          'est_client_cents': 1000,
          'new_client_cents': 1250,
          'delta_client_cents': 250,
          'payment_method': 'card',
          'settled_via': 'bora_assume',
        },
      ],
    )));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('admin_ajustes_peso_bora_assumiu')), findsOneWidget);
    expect(find.text('Ficou por cobrar: 2,50 € — a Bora assumiu'), findsOneWidget);
  });

  testWidgets('detalhe do pedido: cobrado no cartão não mostra dívida', (tester) async {
    await tester.pumpWidget(_app(AdminAjustesPesoSection(
      orderId: 'pedido-2',
      carregar: () async => [
        {
          'item_name': 'Melancia',
          'delta_client_cents': 250,
          'payment_method': 'card',
          'settled_via': 'cartao_cobrado',
        },
      ],
    )));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('admin_ajustes_peso_bora_assumiu')), findsNothing);
    expect(find.textContaining('Cartão — diferença cobrada'), findsOneWidget);
  });
}
