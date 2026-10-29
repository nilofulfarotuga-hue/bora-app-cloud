// ADENDO 4 — itens 4 e 5 (29/10/2026).
//
//   4  produto em falta num pedido já aceito: aviso, contagem e pedido de
//      troca (só ecrã; o total continua a mudar pelo servidor)
//   5  etiquetas do menu (vegetariano, picante, sem glúten)
import 'package:bora_app/l10n/bora_lang.dart';
import 'package:bora_app/models/etiquetas_dieta.dart';
import 'package:bora_app/models/order_edit.dart';
import 'package:bora_app/models/order_model.dart';
import 'package:bora_app/models/partner_product.dart';
import 'package:bora_app/services/interruptores_app.dart';
import 'package:bora_app/widgets/etiquetas_dieta_chips.dart';
import 'package:bora_app/widgets/etiquetas_menu_editor.dart';
import 'package:bora_app/widgets/order_edit/janela_troca_em_falta.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

final _agoraFixo = DateTime.utc(2026, 10, 29, 14, 0);

OrderEditGrupo _grupoEmFalta({required DateTime aplicadoEm}) => OrderEditGrupo(
      'g1',
      [
        OrderEditLinha.fromMap({
          'id': 'l1',
          'grupo_id': 'g1',
          'order_id': 'p1',
          'restaurant_id': 'r1',
          'tipo': 'remove',
          'nome': 'Menu Boom',
          'quantidade': 1,
          'estado': 'aplicado',
          'aplicado_em': aplicadoEm.toIso8601String(),
          'criado_em': aplicadoEm.toIso8601String(),
        }),
      ],
    );

Widget _app(Widget filho) => MaterialApp(home: Scaffold(body: filho));

Future<void> _desmontar(WidgetTester t) async {
  await t.pumpWidget(const SizedBox.shrink());
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    BoraLang.notifier.value = AppLang.pt;
    InterruptoresApp.instance.definirParaTeste({
      InterruptoresApp.esgotadoAviso: true,
      InterruptoresApp.esgotadoMinutos: 10,
      InterruptoresApp.etiquetasMenu: true,
      InterruptoresApp.etiquetasMenuIa: false,
    });
  });

  group('4 — janela de troca (contas)', () {
    final desde = DateTime.utc(2026, 10, 29, 13, 57);

    test('dez minutos a contar do momento em que a loja aplicou', () {
      expect(
        JanelaTroca.restante(
            desde: desde, agora: DateTime.utc(2026, 10, 29, 14, 0), minutos: 10),
        const Duration(minutes: 7),
      );
      expect(
        JanelaTroca.aberta(
            desde: desde, agora: DateTime.utc(2026, 10, 29, 14, 7), minutos: 10),
        isFalse,
        reason: 'às 14:07 já passaram os 10 minutos das 13:57',
      );
    });

    test('nunca devolve tempo negativo', () {
      expect(
        JanelaTroca.restante(
            desde: desde, agora: DateTime.utc(2026, 10, 29, 20), minutos: 10),
        Duration.zero,
      );
    });

    test('contagem lê-se m:ss', () {
      expect(JanelaTroca.contagem(const Duration(minutes: 9, seconds: 5)), '9:05');
      expect(JanelaTroca.contagem(Duration.zero), '0:00');
    });

    test('a janela abre quando a loja aplicou; sem isso, quando criou', () {
      final g = _grupoEmFalta(aplicadoEm: desde);
      expect(JanelaTroca.desdeDoGrupo(g), desde);
    });
  });

  group('4 — janela de troca (ecrã do cliente)', () {
    testWidgets('mostra a contagem e os dois botões durante a janela', (t) async {
      final g = _grupoEmFalta(aplicadoEm: DateTime.utc(2026, 10, 29, 13, 57));
      await t.pumpWidget(_app(JanelaTrocaCliente(
        grupo: g,
        order: _pedidoFalso(),
        agora: () => _agoraFixo,
      )));
      await t.pump();
      expect(find.byKey(const Key('janela_troca_cliente')), findsOneWidget);
      expect(t.widget<Text>(find.byKey(const Key('janela_troca_contagem'))).data,
          'Faltam 7:00');
      expect(find.byKey(const Key('btn_pedir_troca')), findsOneWidget);
      expect(find.byKey(const Key('btn_ficar_sem')), findsOneWidget);
      expect(find.textContaining('Tens 10 min para pedir uma troca'), findsOneWidget);
      // Botões grandes o suficiente para o polegar.
      expect(t.getSize(find.byKey(const Key('btn_pedir_troca'))).height,
          greaterThanOrEqualTo(48));
      await _desmontar(t);
    });

    testWidgets('passada a janela, desaparece', (t) async {
      final g = _grupoEmFalta(aplicadoEm: DateTime.utc(2026, 10, 29, 13, 30));
      await t.pumpWidget(_app(JanelaTrocaCliente(
        grupo: g,
        order: _pedidoFalso(),
        agora: () => _agoraFixo,
      )));
      await t.pump();
      expect(find.byKey(const Key('janela_troca_cliente')), findsNothing);
      await _desmontar(t);
    });

    testWidgets('"Ficar sem ele" fecha o aviso', (t) async {
      final g = _grupoEmFalta(aplicadoEm: DateTime.utc(2026, 10, 29, 13, 58));
      await t.pumpWidget(_app(JanelaTrocaCliente(
        grupo: g,
        order: _pedidoFalso(),
        agora: () => _agoraFixo,
      )));
      await t.pump();
      await t.tap(find.byKey(const Key('btn_ficar_sem')));
      await t.pump();
      expect(find.byKey(const Key('janela_troca_cliente')), findsNothing);
      await _desmontar(t);
    });

    testWidgets('com o interruptor desligado no painel não desenha nada',
        (t) async {
      InterruptoresApp.instance
          .definirParaTeste({InterruptoresApp.esgotadoAviso: false});
      final g = _grupoEmFalta(aplicadoEm: DateTime.utc(2026, 10, 29, 13, 59));
      await t.pumpWidget(_app(JanelaTrocaCliente(
        grupo: g,
        order: _pedidoFalso(),
        agora: () => _agoraFixo,
      )));
      await t.pump();
      expect(find.byKey(const Key('janela_troca_cliente')), findsNothing);
      await _desmontar(t);
    });

    testWidgets('o parceiro vê quanto tempo o cliente ainda tem', (t) async {
      final g = _grupoEmFalta(aplicadoEm: DateTime.utc(2026, 10, 29, 13, 57));
      await t.pumpWidget(
          _app(AvisoTrocaParceiro(grupo: g, agora: () => _agoraFixo)));
      await t.pump();
      expect(find.textContaining('ainda tem 7:00 para pedir uma troca'),
          findsOneWidget);
      await t.pumpWidget(_app(AvisoTrocaParceiro(
          grupo: _grupoEmFalta(aplicadoEm: DateTime.utc(2026, 10, 29, 12)),
          agora: () => _agoraFixo)));
      await t.pump();
      expect(find.textContaining('já terminou'), findsOneWidget);
      await _desmontar(t);
    });
  });

  group('5 — etiquetas do menu', () {
    test('normaliza variantes, tira repetidas e ignora o que não conhece', () {
      expect(
        normalizarEtiquetas(['Picante', 'sem gluten', 'sem-glúten', 'VEGETARIANO', 'vegan', 'picante']),
        ['vegetariano', 'picante', 'sem_gluten'],
      );
      expect(normalizarEtiquetas(null), isEmpty);
      expect(etiquetasDeLinha('não é lista'), isEmpty);
      expect(etiquetasDeLinha(['picante']), ['picante']);
    });

    test('o produto sem etiquetas tem lista vazia e o copyWith muda-a', () {
      const p = PartnerProduct(
        id: 'a',
        restaurantId: 'r',
        name: 'Prato',
        description: '',
        price: 5,
        photoUrl: '',
        isAvailable: true,
      );
      expect(p.dietTags, isEmpty);
      expect(p.copyWith(dietTags: ['picante']).dietTags, ['picante']);
      expect(p.copyWith(name: 'Outro').dietTags, isEmpty);
    });

    testWidgets('o cliente vê os chips pela ordem fixa', (t) async {
      await t.pumpWidget(_app(const EtiquetasDietaChips(
          etiquetas: ['sem_gluten', 'picante', 'vegetariano'])));
      await t.pump();
      final textos = t
          .widgetList<Text>(find.descendant(
              of: find.byKey(const Key('etiquetas_dieta')),
              matching: find.byType(Text)))
          .map((w) => w.data)
          .toList();
      expect(textos, ['Vegetariano', 'Picante', 'Sem glúten']);
    });

    testWidgets('sem etiquetas, ou com o interruptor desligado, nada aparece',
        (t) async {
      await t.pumpWidget(_app(const EtiquetasDietaChips(etiquetas: [])));
      await t.pump();
      expect(find.byKey(const Key('etiquetas_dieta')), findsNothing);
      InterruptoresApp.instance
          .definirParaTeste({InterruptoresApp.etiquetasMenu: false});
      await t.pumpWidget(_app(
          EtiquetasDietaChips(key: UniqueKey(), etiquetas: const ['picante'])));
      await t.pump();
      await t.pump();
      expect(find.byKey(const Key('etiquetas_dieta')), findsNothing);
    });

    testWidgets('o parceiro liga e desliga as etiquetas e fica a saber o resultado',
        (t) async {
      List<String>? ultimo;
      await t.pumpWidget(_app(EtiquetasMenuEditor(
        inicial: const ['picante'],
        aoMudar: (v) => ultimo = v,
      )));
      await t.pump();
      expect(t.widget<FilterChip>(find.byKey(const Key('etiqueta_picante'))).selected,
          isTrue);
      await t.tap(find.byKey(const Key('etiqueta_vegetariano')));
      await t.pump();
      expect(ultimo, ['vegetariano', 'picante']);
      await t.tap(find.byKey(const Key('etiqueta_picante')));
      await t.pump();
      expect(ultimo, ['vegetariano']);
    });

    testWidgets('o botão da IA só existe com o interruptor ligado e prato guardado',
        (t) async {
      await t.pumpWidget(_app(EtiquetasMenuEditor(
          inicial: const [], aoMudar: (_) {}, productId: 'p1')));
      await t.pump();
      expect(find.byKey(const Key('btn_sugerir_etiquetas_ia')), findsNothing,
          reason: 'interruptor desligado');
      InterruptoresApp.instance.definirParaTeste(
          {InterruptoresApp.etiquetasMenuIa: true});
      await t.pumpWidget(_app(EtiquetasMenuEditor(
          inicial: const [], aoMudar: (_) {}, productId: 'p1', key: UniqueKey())));
      await t.pump();
      await t.pump();
      expect(find.byKey(const Key('btn_sugerir_etiquetas_ia')), findsOneWidget);
      await t.pumpWidget(_app(EtiquetasMenuEditor(
          inicial: const [], aoMudar: (_) {}, key: UniqueKey())));
      await t.pump();
      await t.pump();
      expect(find.byKey(const Key('btn_sugerir_etiquetas_ia')), findsNothing,
          reason: 'prato novo: ainda não há descrição guardada');
    });

    test('resposta da IA em palavras que o parceiro lê', () {
      final ok = interpretarRespostaDaIa({
        'ok': true,
        'resultados': [
          {'product_id': 'p1', 'tags': ['picante', 'vegan']},
        ],
      });
      expect(ok.etiquetas, ['picante']);
      expect(ok.mensagem, contains('Confirma ou corrige'));

      expect(
        interpretarRespostaDaIa({
          'ok': true,
          'resultados': [
            {'product_id': 'p1', 'tags': null, 'saltado': 'sem_descricao'},
          ],
        }).etiquetas,
        isNull,
      );
      expect(
        interpretarRespostaDaIa({
          'ok': true,
          'resultados': [
            {'product_id': 'p1', 'saltado': 'escolhido_pelo_parceiro'},
          ],
        }).mensagem,
        contains('Já escolheste'),
      );
      expect(interpretarRespostaDaIa({'ok': false, 'reason': 'desligado'}).mensagem,
          'A sugestão por IA está desligada.');
      expect(interpretarRespostaDaIa(null).etiquetas, isNull);
    });
  });
}

/// Um pedido mínimo: o ecrã de pedir troca só o leva ao chat.
OrderModel _pedidoFalso() => OrderModel(
      id: 'p1',
      total: 10,
      serviceType: OrderServiceType.restaurant,
      isPartnerStore: true,
      status: OrderStatus.preparing,
    );
