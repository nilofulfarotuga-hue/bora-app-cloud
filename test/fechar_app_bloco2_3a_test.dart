// Missão fechar-app-15-11.
//
// Bloco 2 — [CarregamentoUnico]: um só carregamento de pedidos em voo, um só
// à espera, e 2 s de intervalo para o estafeta.
// Bloco 3a — `selected_options_priced` não se perde quando o estafeta grava o
// estado das compras (o preço de balcão ficava sem as opções).
import 'dart:async';

import 'package:bora_app/models/cart_item.dart';
import 'package:bora_app/models/order_model.dart';
import 'package:bora_app/screens/driver_main_screen.dart';
import 'package:bora_app/services/carregamento_unico.dart';
import 'package:bora_app/widgets/driver_item_options.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Bloco 2 — CarregamentoUnico', () {
    test('uma chamada sozinha corre logo, uma vez', () async {
      final c = CarregamentoUnico();
      var corridas = 0;
      await c.correr(() async => corridas++);
      expect(corridas, 1);
      expect(c.emVoo, isFalse);
      expect(c.aEspera, isFalse);
    });

    test('rajada de 10 chamadas com uma em voo: corre 2 vezes, não 10', () async {
      final c = CarregamentoUnico();
      var corridas = 0;
      final porta = Completer<void>();
      Future<void> operacao() async {
        corridas++;
        if (corridas == 1) await porta.future;
      }

      final primeira = c.correr(operacao);
      final seguintes = [for (var i = 0; i < 9; i++) c.correr(operacao)];
      expect(corridas, 1, reason: 'só a primeira arrancou');
      expect(c.emVoo, isTrue);
      expect(c.aEspera, isTrue);
      // As 9 juntaram-se todas ao MESMO carregamento seguinte.
      expect(seguintes.toSet().length, 1);

      porta.complete();
      await primeira;
      await Future.wait(seguintes);
      expect(corridas, 2);
      expect(c.emVoo, isFalse);
      expect(c.aEspera, isFalse);
    });

    test('quem chama a meio recebe dados pedidos DEPOIS da chamada', () async {
      final c = CarregamentoUnico();
      final ordem = <String>[];
      final porta = Completer<void>();
      var n = 0;
      Future<void> operacao() async {
        final eu = ++n;
        ordem.add('inicio$eu');
        if (eu == 1) await porta.future;
        ordem.add('fim$eu');
      }

      final primeira = c.correr(operacao);
      final segunda = c.correr(operacao).then((_) => ordem.add('segunda-pronta'));
      porta.complete();
      await primeira;
      await segunda;
      expect(ordem, ['inicio1', 'fim1', 'inicio2', 'fim2', 'segunda-pronta']);
    });

    test('um erro não deixa o carregamento seguinte preso', () async {
      final c = CarregamentoUnico();
      var corridas = 0;
      await c.correr(() async {
        corridas++;
        throw StateError('rede caiu');
      });
      await c.correr(() async => corridas++);
      expect(corridas, 2);
      expect(c.emVoo, isFalse);
    });

    // [15/11/2026, revisão] Os dois casos em que a versão anterior ficava
    // presa para sempre (lia o próprio `Future` antes de ele existir).
    test('um erro lançado logo à entrada, sem nenhuma espera, não prende nada',
        () async {
      final c = CarregamentoUnico();
      var corridas = 0;
      // De propósito NÃO é `async`: rebenta antes de devolver um Future.
      Future<void> rebentaAEntrada() {
        corridas++;
        throw StateError('rebentou à entrada');
      }

      await c.correr(rebentaAEntrada);
      expect(c.emVoo, isFalse);
      await c.correr(() async => corridas++);
      expect(corridas, 2);
      expect(c.emVoo, isFalse);
      expect(c.aEspera, isFalse);
    });

    test('o intervalo acaba entre as duas contas: corre na mesma e não prende',
        () async {
      // O relógio salta entre a 1.ª conta ("falta 1 s") e a 2.ª ("já passou").
      final base = DateTime(2026, 11, 15, 10);
      const saltos = <int>[0, 1, 3];
      var leituras = 0;
      DateTime relogio() {
        final s = saltos[leituras < saltos.length ? leituras : saltos.length - 1];
        leituras++;
        return base.add(Duration(seconds: s));
      }

      final c = CarregamentoUnico(agora: relogio);
      const dois = Duration(seconds: 2);
      var corridas = 0;
      await c.correr(() async => corridas++, intervalo: dois);
      await c.correr(() async => corridas++, intervalo: dois);
      expect(corridas, 2);
      expect(c.aEspera, isFalse);
      // E o seguinte também corre: não ficou nenhum Future falhado guardado.
      await c.correr(() async => corridas++);
      expect(corridas, 3);
      expect(c.emVoo, isFalse);
    });

    // testWidgets corre com relógio falso: `tester.pump(duração)` avança os
    // temporizadores, e o teste falha sozinho se ficar algum por disparar.
    testWidgets('estafeta: dois carregamentos seguidos ficam a 2 s um do outro',
        (tester) async {
      var agora = DateTime(2026, 11, 15, 10);
      final c = CarregamentoUnico(agora: () => agora);
      var inicios = 0;
      Future<void> operacao() async => inicios++;
      Future<void> passar(int ms) async {
        agora = agora.add(Duration(milliseconds: ms));
        await tester.pump(Duration(milliseconds: ms));
      }

      unawaited(c.correr(operacao, intervalo: esperaEntreCarregamentosEstafeta));
      await tester.pump();
      expect(inicios, 1);

      // 300 ms depois chegam mais dois pedidos (aviso + voltar à app).
      await passar(300);
      unawaited(c.correr(operacao, intervalo: esperaEntreCarregamentosEstafeta));
      unawaited(c.correr(operacao, intervalo: esperaEntreCarregamentosEstafeta));
      await tester.pump();
      expect(inicios, 1, reason: 'ainda não passaram 2 s');
      expect(c.aEspera, isTrue);

      await passar(1600);
      expect(inicios, 1, reason: '1,9 s: ainda à espera');

      await passar(200);
      await tester.pump();
      expect(inicios, 2, reason: 'aos 2 s corre UM (os dois juntaram-se)');
      expect(c.aEspera, isFalse);
    });

    testWidgets('sem intervalo (cliente, loja, painel) não há espera nenhuma',
        (tester) async {
      final c = CarregamentoUnico();
      var corridas = 0;
      unawaited(c.correr(() async => corridas++));
      await tester.pump();
      unawaited(c.correr(() async => corridas++));
      await tester.pump();
      expect(corridas, 2);
    });

    test('filtro e páginas do histórico do estafeta', () {
      expect(
        filtroPedidosDoEstafeta('abc-123'),
        'assigned_driver_id.eq.abc-123,current_driver_offer_id.eq.abc-123',
      );
      expect(listaEstadosFinaisPostgrest(), '(delivered,cancelled,rejected)');
      expect(intervaloDaPaginaHistorico(0), (de: 0, ate: 19));
      expect(intervaloDaPaginaHistorico(1), (de: 20, ate: 39));
      expect(intervaloDaPaginaHistorico(-3), (de: 0, ate: 19));
      expect(tamanhoPaginaHistoricoEstafeta, 20);
      expect(esperaEntreCarregamentosEstafeta, const Duration(seconds: 2));
    });
  });

  group('Bloco 2 — histórico do estafeta às páginas de 20', () {
    List<OrderModel> entregas(int n) => [
          for (var i = 0; i < n; i++)
            OrderModel.fromSupabase({
              'id': 'pedido-${i.toString().padLeft(3, '0')}',
              'status': 'delivered',
              'service_type': 'restaurant',
              'payment_method': 'cash',
              'price': 12.5,
              'items': const [],
              'created_at':
                  DateTime.utc(2026, 11, 14, 12).subtract(Duration(hours: i)).toIso8601String(),
            }),
        ];

    Widget app(Widget filho) => MaterialApp(home: filho);
    // Ecrã alto para o teste: o ListView só monta o que cabe no ecrã, e aqui
    // quer-se contar as linhas todas sem andar a rolar.
    void ecraAlto(WidgetTester t) {
      t.view.physicalSize = const Size(800, 6000);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.reset);
    }
    Finder linhas() => find.byWidgetPredicate((w) =>
        w.key is ValueKey<String> &&
        (w.key! as ValueKey<String>).value.startsWith('pedido_feito_'));
    final verMais = find.byKey(const Key('pedidos_estafeta_ver_mais'));

    testWidgets('45 entregas: mostra 20, depois 40, depois as 45', (t) async {
      ecraAlto(t);
      await t.pumpWidget(app(PedidosEstafetaCorpo(
        emCurso: 0,
        ofertas: 0,
        historico: entregas(45),
        aoAbrirInicio: () {},
        agora: () => DateTime.utc(2026, 11, 14, 13),
      )));
      expect(linhas(), findsNWidgets(20));

      await t.tap(verMais);
      await t.pump();
      expect(linhas(), findsNWidgets(40));

      await t.tap(verMais);
      await t.pump();
      expect(linhas(), findsNWidgets(45));
      expect(verMais, findsNothing, reason: 'não há mais nada para mostrar');
    });

    testWidgets('até 20 entregas não aparece botão nenhum', (t) async {
      ecraAlto(t);
      await t.pumpWidget(app(PedidosEstafetaCorpo(
        emCurso: 0,
        ofertas: 0,
        historico: entregas(20),
        aoAbrirInicio: () {},
        agora: () => DateTime.utc(2026, 11, 14, 13),
      )));
      expect(linhas(), findsNWidgets(20));
      expect(verMais, findsNothing);
    });

    testWidgets('quando as de cá acabam, pede a página seguinte ao servidor',
        (t) async {
      ecraAlto(t);
      var pedidos = 0;
      await t.pumpWidget(app(PedidosEstafetaCorpo(
        emCurso: 0,
        ofertas: 0,
        historico: entregas(20),
        aoAbrirInicio: () {},
        agora: () => DateTime.utc(2026, 11, 14, 13),
        haMaisNoServidor: true,
        aoPedirMaisAntigas: () => pedidos++,
      )));
      await t.tap(verMais);
      await t.pump();
      expect(pedidos, 1);
    });

    testWidgets('enquanto a página chega mostra a roda e não o botão',
        (t) async {
      await t.pumpWidget(app(PedidosEstafetaCorpo(
        emCurso: 0,
        ofertas: 0,
        historico: entregas(3),
        aoAbrirInicio: () {},
        agora: () => DateTime.utc(2026, 11, 14, 13),
        haMaisNoServidor: true,
        aCarregarMais: true,
      )));
      expect(verMais, findsNothing);
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
    });
  });

  group('Bloco 3a — selected_options_priced não se perde', () {
    // Forma real gravada pelo create_order (pedido 7f527ceb: base 11 €,
    // tamanho Média +2 €).
    Map<String, dynamic> itemDoServidor() => {
          'productId': 'prod-pizza-1',
          'name': 'Pizza da casa',
          'price': 13.0,
          'quantity': 2,
          'purchaseStatus': 'pending',
          'basePrice': 11.0,
          'deposit_units': 0,
          'selected_options': [
            {
              'group': 'Tamanho',
              'items': ['Média'],
            },
          ],
          'selected_options_priced': [
            {
              'group': 'Tamanho',
              'items': [
                {'name': 'Média', 'price_add': 2},
              ],
            },
          ],
        };

    test('ler do pedido e voltar a gravar mantém o que o servidor pôs', () {
      final original = itemDoServidor();
      final item = CartItem.fromJson(original);
      item.purchaseStatus = 'bought';
      final gravado = item.toJson();

      expect(gravado['selected_options_priced'],
          original['selected_options_priced']);
      expect(gravado['purchaseStatus'], 'bought');
      // E o preço de balcão continua a contar as opções depois de reler.
      final relido = CartItem.fromJson(gravado);
      expect(relido.optionsPriceAdd, 2);
      expect(relido.basePriceWithOptions, 13);
    });

    test('a cópia para a lista de compras do estafeta não o deita fora', () {
      final item = CartItem.fromJson({
        ...itemDoServidor(),
        'age_restricted': true,
        'variable_weight': true,
      });
      final copia = copyOrderItemsForDriverSheet([item]).single;
      copia.purchaseStatus = 'unavailable';
      final gravado = copia.toJson();

      expect(gravado['selected_options_priced'],
          itemDoServidor()['selected_options_priced']);
      expect(gravado['age_restricted'], true);
      expect(gravado['variable_weight'], true);
      // A cópia é um objeto novo: não mexe no item do pedido.
      expect(item.purchaseStatus, 'pending');
    });

    test('nunca grava a versão formatada para o ecrã', () {
      final item = CartItem.fromJson(itemDoServidor());
      expect(item.selectedOptionsPriced.single.items.single, contains('+'));
      final gravado = item.toJson()['selected_options_priced'] as List;
      final primeiro = (gravado.single as Map)['items'] as List;
      expect(primeiro.single, isA<Map>());
      expect((primeiro.single as Map)['name'], 'Média');
    });

    test('item do carrinho (pedido novo) não inventa preços de opções', () {
      final novo = CartItem(
        productId: 'prod-pizza-1',
        name: 'Pizza da casa',
        price: 13,
        selectedOptions: CartItem.fromJson(itemDoServidor()).selectedOptions,
      );
      expect(novo.toJson().containsKey('selected_options_priced'), isFalse);
    });

    test('item sem opções fica como estava', () {
      final item = CartItem.fromJson({
        'productId': 'p1',
        'name': 'Água 1,5 L',
        'price': 0.6,
        'quantity': 1,
      });
      expect(item.toJson().containsKey('selected_options_priced'), isFalse);
      expect(item.toJson().containsKey('selected_options'), isFalse);
    });
  });
}
