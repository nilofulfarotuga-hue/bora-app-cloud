// Cancelamento tardio TVDE (17/10/2026) — o diálogo de cancelar do cliente,
// com uma store falsa a fazer de servidor (nada é escrito no banco).
//
// Prende o que o Danilo pediu: o cliente vê o valor REAL antes de cancelar,
// e nunca se cobra mais do que o que ele viu. Cenários: janela grátis com
// contador vivo, corrida inteira (paga online e em dinheiro → carteira),
// cotação falhada/lenta → aviso neutro, subida do valor ao confirmar, e
// corrida que já tinha terminado.
import 'dart:async';

import 'package:bora_app/models/tvde_cancel_quote.dart';
import 'package:bora_app/stores/tvde_store.dart';
import 'package:bora_app/widgets/tvde/tvde_cancel_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

TvdeCancelQuote _q(String regra,
        {int fee = 0, String? como, int restam = 0, int fare = 700}) =>
    TvdeCancelQuote.fromJson({
      'ok': true,
      'terminal': false,
      'regra': regra,
      'fee_cents': fee,
      'fare_cents': fare,
      'como_cobra': como,
      'grace_seconds': 180,
      'seconds_since_accept': 180 - restam,
      'seconds_left_free': restam,
      'had_driver': true,
    })!;

/// Faz de servidor: devolve as cotações por ordem (a última repete-se).
class _ServidorFalso extends TvdeStore {
  _ServidorFalso(this.respostas);
  final List<FutureOr<TvdeCancelQuote?> Function()> respostas;
  int pedidos = 0;

  @override
  Future<TvdeCancelQuote?> cancelQuote(String rideId) async {
    final i = pedidos < respostas.length ? pedidos : respostas.length - 1;
    pedidos++;
    return respostas[i]();
  }
}

class _Ecra extends StatefulWidget {
  const _Ecra(this.store, this.fim);
  final _ServidorFalso store;
  final void Function(DecisaoDeCancelamento) fim;
  @override
  State<_Ecra> createState() => _EcraState();
}

class _EcraState extends State<_Ecra> {
  @override
  Widget build(BuildContext context) => Scaffold(
        body: Center(
          child: ElevatedButton(
            onPressed: () async {
              final d = await pedirConfirmacaoDeCancelamento(context,
                  cotar: () => widget.store.cancelQuote('r1'),
                  minutosDaJanela: 3);
              widget.fim(d);
            },
            child: const Text('Cancelar'),
          ),
        ),
      );
}

Future<List<DecisaoDeCancelamento>> _abrir(
    WidgetTester t, _ServidorFalso store) async {
  final decisoes = <DecisaoDeCancelamento>[];
  await t.pumpWidget(MaterialApp(home: _Ecra(store, decisoes.add)));
  await t.tap(find.text('Cancelar'));
  await t.pump();
  await t.pump();
  return decisoes;
}

String _principal(WidgetTester t) =>
    t.widget<Text>(find.byKey(const ValueKey('tvde_cancel_principal'))).data!;

void main() {
  testWidgets('janela grátis: contador vivo e, a zero, o valor novo',
      (t) async {
    final store = _ServidorFalso([
      () => _q('dentro_da_graca', restam: 3),
      () => _q('corrida_inteira', fee: 700, como: 'carteira'),
    ]);
    final decisoes = await _abrir(t, store);
    expect(_principal(t), contains('mais 00:03 '));
    expect(find.text('Sim, cancelar'), findsOneWidget);
    expect(find.textContaining('até 7,00 €'), findsOneWidget);
    await t.pump(const Duration(seconds: 1));
    expect(_principal(t), contains('mais 00:02 '));
    await t.pump(const Duration(seconds: 1));
    expect(_principal(t), contains('mais 00:01 '));
    // A zero pede nova cotação e redesenha com o custo.
    await t.pump(const Duration(seconds: 1));
    await t.pump();
    expect(store.pedidos, 2);
    expect(find.text('Custo de cancelamento: 7,00 €'), findsOneWidget);
    expect(find.text('Cancelar e pagar 7,00 €'), findsOneWidget);
    await t.tap(find.byKey(const ValueKey('tvde_cancel_confirmar')));
    await t.pumpAndSettle();
    expect(decisoes.single.confirmou, isTrue,
        reason: 'o cliente viu os 7 € e confirmou; a confirmação deu 7 €');
    expect(store.pedidos, 3, reason: 'ao confirmar há sempre nova cotação');
  });

  testWidgets('corrida inteira paga online: valor retido; Voltar não cancela',
      (t) async {
    final store = _ServidorFalso([
      () => _q('corrida_inteira', fee: 1250, como: 'pagamento_retido'),
    ]);
    final decisoes = await _abrir(t, store);
    expect(find.text('Custo de cancelamento: 12,50 €'), findsOneWidget);
    expect(
        find.text('Esta corrida já está paga: o valor pago fica retido.'),
        findsOneWidget);
    expect(_principal(t),
        'O motorista já aceitou há mais de 3 min. Cancelar agora custa o valor total da corrida.');
    await t.tap(find.byKey(const ValueKey('tvde_cancel_voltar')));
    await t.pumpAndSettle();
    expect(decisoes.single.confirmou, isFalse);
    expect(store.pedidos, 1);
  });

  testWidgets('corrida inteira em dinheiro: debitado na carteira, confirma',
      (t) async {
    final store = _ServidorFalso([
      () => _q('corrida_inteira', fee: 600, como: 'carteira'),
    ]);
    final decisoes = await _abrir(t, store);
    expect(
        find.text(
            'O valor é debitado da tua carteira Bora (se não tiveres saldo, fica como dívida).'),
        findsOneWidget);
    await t.tap(find.text('Cancelar e pagar 6,00 €'));
    await t.pumpAndSettle();
    expect(decisoes.single.confirmou, isTrue);
  });

  testWidgets('cotação falhada: aviso neutro sem números e cancela na mesma',
      (t) async {
    final store = _ServidorFalso([() => throw Exception('sem rede')]);
    final decisoes = await _abrir(t, store);
    expect(_principal(t), startsWith('Não foi possível confirmar agora'));
    expect(find.textContaining('€'), findsNothing);
    await t.tap(find.text('Cancelar na mesma'));
    await t.pumpAndSettle();
    expect(decisoes.single.confirmou, isTrue);
  });

  testWidgets('cotação lenta (>3 s): aviso neutro, nunca o cálculo antigo',
      (t) async {
    final nunca = Completer<TvdeCancelQuote?>();
    final store = _ServidorFalso([() => nunca.future]);
    final decisoes = <DecisaoDeCancelamento>[];
    await t.pumpWidget(MaterialApp(home: _Ecra(store, decisoes.add)));
    await t.tap(find.text('Cancelar'));
    await t.pump(const Duration(seconds: 2));
    expect(find.byType(TvdeCancelDialog), findsNothing,
        reason: 'ainda à espera da cotação');
    await t.pump(const Duration(seconds: 2));
    await t.pump();
    expect(_principal(t), startsWith('Não foi possível confirmar agora'));
    await t.tap(find.byKey(const ValueKey('tvde_cancel_voltar')));
    await t.pumpAndSettle();
    expect(decisoes.single.confirmou, isFalse);
  });

  testWidgets(
      'o valor subiu entre o diálogo e o confirmar: NÃO cancela, mostra o novo',
      (t) async {
    final store = _ServidorFalso([
      () => _q('dentro_da_graca', restam: 120),
      () => _q('corrida_inteira', fee: 850, como: 'carteira'),
    ]);
    final decisoes = await _abrir(t, store);
    expect(find.text('Sim, cancelar'), findsOneWidget);
    await t.tap(find.text('Sim, cancelar'));
    await t.pump();
    await t.pump();
    expect(decisoes, isEmpty, reason: 'viu 0 €, o servidor diz 8,50 €');
    expect(find.text('Custo de cancelamento: 8,50 €'), findsOneWidget);
    await t.tap(find.text('Cancelar e pagar 8,50 €'));
    await t.pumpAndSettle();
    expect(decisoes.single.confirmou, isTrue);
    expect(store.pedidos, 3);
  });

  testWidgets('aviso neutro e, ao confirmar, o servidor já responde com custo',
      (t) async {
    final store = _ServidorFalso([
      () => null,
      () => _q('corrida_inteira', fee: 700, como: 'carteira'),
    ]);
    final decisoes = await _abrir(t, store);
    await t.tap(find.text('Cancelar na mesma'));
    await t.pump();
    await t.pump();
    expect(decisoes, isEmpty,
        reason: 'o aviso neutro não mostrou número: mostra-se o valor real');
    expect(find.text('Cancelar e pagar 7,00 €'), findsOneWidget);
  });

  testWidgets('corrida que já tinha terminado: sem diálogo', (t) async {
    final store = _ServidorFalso([
      () => TvdeCancelQuote.fromJson({
            'ok': true,
            'terminal': true,
            'status': 'cancelada_motorista',
            'fee_cents': 0,
          }),
    ]);
    final decisoes = await _abrir(t, store);
    await t.pumpAndSettle();
    expect(find.byType(TvdeCancelDialog), findsNothing);
    expect(decisoes.single.jaTerminou?.status, 'cancelada_motorista');
    expect(decisoes.single.confirmou, isFalse);
  });

  testWidgets('sem motorista (terminal sem_motorista): cancela sem custo',
      (t) async {
    final store = _ServidorFalso([
      () => TvdeCancelQuote.fromJson(
          {'ok': true, 'terminal': true, 'status': 'sem_motorista'}),
    ]);
    final decisoes = await _abrir(t, store);
    expect(_principal(t),
        'Ainda nenhum motorista aceitou. Cancelas sem custo.');
    await t.tap(find.text('Sim, cancelar'));
    await t.pumpAndSettle();
    expect(decisoes.single.confirmou, isTrue);
  });
}
