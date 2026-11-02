// Peso ao quilo — a diferença no ecrã do cliente (01/11/2026, missão
// app-fechar-2026-11-01, bloco B2; achados P1, P2 e P5 de
// docs/propostas/revisao-casa-peso-convidado-2026-11-01.md).
//
//   P1 — entre o ajuste do estafeta e o talão o total do pedido ainda é o
//        antigo: o cartão "Ajustado ao peso" acaba com "Diferença: +1,64 €"
//        (soma das linhas; negativo com o sinal "−").
//   P2 — a frase diz o que acontece a essa diferença, com a regra do talão:
//        dinheiro → paga-se ao estafeta; cartão/MB Way mais caro → por conta
//        do Bora; mais barato → carteira Bora.
//   P5 — peça ao quilo ("Melancia (~4 kg)") recusada pelo limite: a mensagem
//        diz "Escolhe uma peça mais perto de 4 kg". O limite não muda.
// Sem rede.
import 'package:bora_app/l10n/bora_lang.dart';
import 'package:bora_app/models/order_model.dart';
import 'package:bora_app/services/ajustes_peso_service.dart';
import 'package:bora_app/services/peso_variavel_estafeta_service.dart';
import 'package:bora_app/widgets/ajustes_peso_pedido.dart';
import 'package:bora_app/widgets/peso_variavel_sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

AjustePeso _ajuste({
  required String produto,
  required String nome,
  required int est,
  required int novo,
  int qty = 1,
  String? metodo,
  String? acerto,
}) =>
    AjustePeso.fromMap(<String, dynamic>{
      'settled_via': acerto,
      'id': 'aj-$produto',
      'order_id': '6a1b2c3d-0000-4000-8000-0000000000aa',
      'product_id': produto,
      'item_name': nome,
      'qty': qty,
      'est_base_cents': est,
      'real_base_cents': novo,
      'est_client_cents': est,
      'new_client_cents': novo,
      'delta_client_cents': novo - est,
      'payment_method': metodo,
    });

// Melancia 7,14 € → 9,06 € (+1,92) e banana 1,40 € → 1,12 € (−0,28): +1,64 €.
final _sobe = [
  _ajuste(
      produto: 'cont-5050572', nome: 'Melancia (~4 kg)', est: 714, novo: 906),
  _ajuste(produto: 'cont-2597619', nome: 'Banana', qty: 4, est: 140, novo: 112),
];

// Banana −0,28 e maçã 2,00 € → 1,90 € (−0,10): −0,38 €.
final _desce = [
  _ajuste(produto: 'cont-2597619', nome: 'Banana', qty: 4, est: 140, novo: 112),
  _ajuste(produto: 'cont-maca', nome: 'Maçã Gala', est: 200, novo: 190),
];

Widget _app(Widget filho) =>
    MaterialApp(home: Scaffold(body: SingleChildScrollView(child: filho)));

String _textoDe(WidgetTester t, Key k) => t.widget<Text>(find.byKey(k)).data!;

const _kDiferenca = Key('ajustes_peso_diferenca');
const _kFrase = Key('ajustes_peso_frase_pagamento');

void main() {
  group('P1 — linha da diferença', () {
    testWidgets('dois ajustes: "Diferença: +1,64 €"', (t) async {
      await t.pumpWidget(_app(AjustesPesoLista(
          ajustes: _sobe, metodoPagamento: PaymentMethod.cash)));
      expect(find.text('Ajustado ao peso: 7,14 € → 9,06 €'), findsOneWidget);
      expect(find.text('Ajustado ao peso: 1,40 € → 1,12 €'), findsOneWidget);
      expect(_textoDe(t, _kDiferenca), 'Diferença: +1,64 €');
    });

    testWidgets('mais barato: sinal menos tipográfico', (t) async {
      await t.pumpWidget(_app(AjustesPesoLista(
          ajustes: _desce, metodoPagamento: PaymentMethod.cash)));
      expect(_textoDe(t, _kDiferenca), 'Diferença: −0,38 €');
    });

    test('textoDiferenca', () {
      expect(AjustesPesoLista.textoDiferenca(192), '+1,92 €');
      expect(AjustesPesoLista.textoDiferenca(-28), '−0,28 €');
      expect(AjustesPesoLista.textoDiferenca(0), '0,00 €');
    });

    testWidgets('linhas que voltaram ao previsto não entram na conta',
        (t) async {
      await t.pumpWidget(_app(AjustesPesoLista(ajustes: [
        _sobe.first,
        _ajuste(produto: 'cont-x', nome: 'Pera', est: 300, novo: 300),
      ], metodoPagamento: PaymentMethod.card)));
      expect(_textoDe(t, _kDiferenca), 'Diferença: +1,92 €');
      expect(find.textContaining('Pera'), findsNothing);
    });

    testWidgets('sem ajustes não desenha nada (nem a diferença)', (t) async {
      await t.pumpWidget(_app(const AjustesPesoLista(
          ajustes: [], metodoPagamento: PaymentMethod.cash)));
      expect(find.byKey(_kDiferenca), findsNothing);
      expect(find.byKey(_kFrase), findsNothing);
    });
  });

  group('P2 — frase conforme o pagamento', () {
    testWidgets('dinheiro', (t) async {
      await t.pumpWidget(_app(AjustesPesoLista(
          ajustes: _sobe, metodoPagamento: PaymentMethod.cash)));
      expect(
          _textoDe(t, _kFrase), 'Pagas o valor final ao estafeta na entrega.');
    });

    testWidgets('dinheiro, mesmo mais barato', (t) async {
      await t.pumpWidget(_app(AjustesPesoLista(
          ajustes: _desce, metodoPagamento: PaymentMethod.cash)));
      expect(
          _textoDe(t, _kFrase), 'Pagas o valor final ao estafeta na entrega.');
    });

    testWidgets('cartão, mais caro: por conta do Bora', (t) async {
      await t.pumpWidget(_app(AjustesPesoLista(
          ajustes: _sobe, metodoPagamento: PaymentMethod.card)));
      expect(_textoDe(t, _kFrase),
          'O peso real saiu mais caro; a diferença fica por conta do Bora.');
    });

    testWidgets('cartão, mais barato: carteira Bora', (t) async {
      await t.pumpWidget(_app(AjustesPesoLista(
          ajustes: _desce, metodoPagamento: PaymentMethod.card)));
      expect(_textoDe(t, _kFrase),
          'Saiu mais barato: a diferença vai para a tua carteira Bora no fim.');
    });

    testWidgets('MB Way segue a regra do cartão', (t) async {
      await t.pumpWidget(_app(AjustesPesoLista(
          ajustes: _sobe, metodoPagamento: PaymentMethod.mbway)));
      expect(_textoDe(t, _kFrase),
          'O peso real saiu mais caro; a diferença fica por conta do Bora.');
    });

    testWidgets('cartão sem diferença no total: sem frase', (t) async {
      await t.pumpWidget(_app(AjustesPesoLista(ajustes: [
        _ajuste(produto: 'a', nome: 'A', est: 100, novo: 128),
        _ajuste(produto: 'b', nome: 'B', est: 128, novo: 100),
      ], metodoPagamento: PaymentMethod.card)));
      expect(_textoDe(t, _kDiferenca), 'Diferença: 0,00 €');
      expect(find.byKey(_kFrase), findsNothing);
    });

    testWidgets('sem método do ecrã, usa o payment_method da linha', (t) async {
      await t.pumpWidget(_app(AjustesPesoLista(ajustes: [
        _ajuste(
            produto: 'cont-5050572',
            nome: 'Melancia (~4 kg)',
            est: 714,
            novo: 906,
            metodo: 'mbway'),
      ])));
      expect(_textoDe(t, _kFrase),
          'O peso real saiu mais caro; a diferença fica por conta do Bora.');
    });

    testWidgets('em inglês traduz e mantém o valor', (t) async {
      addTearDown(() => BoraLang.notifier.value = AppLang.pt);
      BoraLang.notifier.value = AppLang.en;
      await t.pumpWidget(_app(AjustesPesoLista(
          ajustes: _sobe, metodoPagamento: PaymentMethod.cash)));
      expect(_textoDe(t, _kDiferenca), 'Difference: +1,64 €');
      expect(_textoDe(t, _kFrase),
          'You pay the final amount to the courier on delivery.');
    });

    test('a soma é a do serviço (delta_client_cents)', () {
      expect(AjustesPesoService.somaDiferencaCents(_sobe), 164);
      expect(AjustesPesoService.somaDiferencaCents(_desce), -38);
    });
  });

  group('B3 (02/11) — diferença a mais cobrada no cartão', () {
    const vaiSer = 'A diferença vai ser cobrada no cartão com que pagaste.';
    const foi = 'A diferença foi cobrada no cartão com que pagaste.';
    const bora =
        'O peso real saiu mais caro; a diferença fica por conta do Bora.';
    List<AjustePeso> sobeCom(String? acerto) => [
          _ajuste(
              produto: 'cont-5050572',
              nome: 'Melancia (~4 kg)',
              est: 714,
              novo: 906,
              acerto: acerto),
        ];

    Future<String> frase(WidgetTester t,
        {required PaymentMethod metodo,
        String? acerto,
        bool cobra = false}) async {
      await t.pumpWidget(_app(AjustesPesoLista(
          ajustes: sobeCom(acerto), metodoPagamento: metodo, cobraCartao: cobra)));
      return _textoDe(t, _kFrase);
    }

    testWidgets('cartão, interruptor ligado, antes do talão: vai ser cobrada',
        (t) async {
      expect(await frase(t, metodo: PaymentMethod.card, cobra: true), vaiSer);
    });
    testWidgets('cartão, talão a cobrar (cartao_pendente)', (t) async {
      expect(
          await frase(t, metodo: PaymentMethod.card, acerto: 'cartao_pendente'),
          vaiSer);
    });
    testWidgets('cartão cobrado: a linha do recibo diz que foi', (t) async {
      expect(
          await frase(t,
              metodo: PaymentMethod.card, acerto: 'cartao_cobrado', cobra: true),
          foi);
      expect(_textoDe(t, _kDiferenca), 'Diferença: +1,92 €');
    });
    testWidgets('cobrança falhou (bora_assume): por conta do Bora', (t) async {
      expect(
          await frase(t,
              metodo: PaymentMethod.card, acerto: 'bora_assume', cobra: true),
          bora);
    });
    testWidgets('MB Way nunca é cobrado, mesmo com o interruptor', (t) async {
      expect(await frase(t, metodo: PaymentMethod.mbway, cobra: true), bora);
    });
    testWidgets('interruptor desligado: igual a antes', (t) async {
      expect(await frase(t, metodo: PaymentMethod.card), bora);
    });
    testWidgets('linha de produto que não havia não esconde a do cartão',
        (t) async {
      await t.pumpWidget(_app(AjustesPesoLista(ajustes: [
        _ajuste(
            produto: 'cont-x', nome: 'Pera', est: 200, novo: 150,
            acerto: 'ignorado_nao_ha'),
        ...sobeCom('cartao_cobrado'),
      ], metodoPagamento: PaymentMethod.card)));
      expect(_textoDe(t, _kFrase), foi);
    });
    testWidgets('em inglês', (t) async {
      addTearDown(() => BoraLang.notifier.value = AppLang.pt);
      BoraLang.notifier.value = AppLang.en;
      expect(
          await frase(t, metodo: PaymentMethod.card, acerto: 'cartao_cobrado'),
          'The difference was charged to the card you paid with.');
    });
  });

  group('P5 — peça ao quilo fora do limite', () {
    test('peso médio lido do nome que o gatilho escreve', () {
      expect(
          PesoVariavelEstafetaService.pesoMedioDoNome('Melancia (~4 kg) × 1'),
          4);
      expect(
          PesoVariavelEstafetaService.pesoMedioDoNome(
              'Melancia Alongada Metade (~2,5 kg)'),
          2.5);
      expect(PesoVariavelEstafetaService.pesoMedioDoNome('Banana × 4'), isNull);
      expect(PesoVariavelEstafetaService.pesoMedioDoNome('Arroz 1 kg'), isNull);
    });

    test('quilos em PT-PT', () {
      expect(PesoVariavelEstafetaService.kgTexto(4), '4');
      expect(PesoVariavelEstafetaService.kgTexto(2.5), '2,5');
      expect(PesoVariavelEstafetaService.kgTexto(1.25), '1,25');
      expect(PesoVariavelEstafetaService.kgTexto(10), '10');
    });

    test('mensagem com o peso a procurar e o intervalo do servidor', () {
      final m = PesoVariavelEstafetaService.mensagemErro('fora_do_limite',
          minimoCents: 500, maximoCents: 928, pesoMedioKg: 4);
      expect(m, contains('Escolhe uma peça mais perto de 4 kg'));
      expect(m, contains('Aceite: 5,00 € a 9,28 €.'));
      expect(m, contains('"Não há"'));
    });

    test('sem peso médio fica a mensagem de sempre', () {
      final m = PesoVariavelEstafetaService.mensagemErro('fora_do_limite',
          minimoCents: 500, maximoCents: 928);
      expect(m, contains('Pesa outra vez'));
      expect(m, isNot(contains('Escolhe uma peça')));
    });

    testWidgets('a folha da balança mostra-a para "Melancia (~4 kg)"',
        (t) async {
      await t.pumpWidget(MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (ctx) => ElevatedButton(
              onPressed: () => PesoVariavelSheet.abrir(
                ctx,
                nomeLinha: 'Melancia (~4 kg) × 1',
                estimadoCaixaCents: 714,
                enviar: (_) async => PesoVariavelResultado.erro(
                    'fora_do_limite',
                    minimoCents: 500,
                    maximoCents: 928),
              ),
              child: const Text('abrir'),
            ),
          ),
        ),
      ));
      await t.tap(find.text('abrir'));
      await t.pumpAndSettle();
      await t.enterText(find.byKey(const Key('peso_campo')), '12,40');
      await t.tap(find.byKey(const Key('peso_confirmar')));
      await t.pumpAndSettle();
      expect(find.textContaining('Escolhe uma peça mais perto de 4 kg'),
          findsOneWidget);
      expect(find.byType(PesoVariavelSheet), findsOneWidget);
    });
  });
}
