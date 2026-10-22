// PROVA do diálogo de cancelar a corrida do CLIENTE (17/10/2026 · cancelamento
// tardio), num aparelho de verdade (emulador Android, simulador iOS ou Chrome),
// com uma store falsa a fazer de servidor: nada é escrito no banco e nenhum
// motorista real é chamado (criar corridas de teste em produção é proibido).
//
// Cenários (os mesmos do teste de widgets `test/tvde_cancel_dialog_test.dart`,
// aqui no motor de pintura do aparelho e com paragens para captura):
//   1. dentro da janela grátis: contador vivo e, a zero, o valor novo;
//   2. corrida inteira paga online: valor retido;
//   3. corrida inteira em dinheiro: debitado na carteira;
//   4. cotação falhada: aviso neutro, sem números;
//   5. o valor subiu entre o diálogo e o confirmar: não cancela, mostra o novo.
//
// Cada paragem anuncia-se no log: "[prova] PRONTO <nome>".
//   flutter test integration_test/tvde_cancelamento_prova_test.dart -d <aparelho>
import 'dart:async';

import 'package:bora_app/config/app_theme.dart';
import 'package:bora_app/models/tvde_cancel_quote.dart';
import 'package:bora_app/stores/tvde_store.dart';
import 'package:bora_app/widgets/tvde/tvde_cancel_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

const _segundosPorCaptura = 2;

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

Future<List<DecisaoDeCancelamento>> _abrir(
    WidgetTester t, _ServidorFalso store) async {
  final decisoes = <DecisaoDeCancelamento>[];
  await t.pumpWidget(MaterialApp(
    theme: AppTheme.lightTheme,
    home: Builder(
      builder: (ctx) => Scaffold(
        body: Center(
          child: ElevatedButton(
            onPressed: () async => decisoes.add(
                await pedirConfirmacaoDeCancelamento(ctx,
                    cotar: () => store.cancelQuote('prova'),
                    minutosDaJanela: 3)),
            child: const Text('Cancelar corrida (prova)'),
          ),
        ),
      ),
    ),
  ));
  await t.tap(find.text('Cancelar corrida (prova)'));
  await t.pump();
  await t.pump(const Duration(milliseconds: 400));
  return decisoes;
}

Future<void> _parar(WidgetTester t, String nome) async {
  debugPrint('[prova] PRONTO $nome');
  await t.pump(const Duration(seconds: _segundosPorCaptura));
}

String _principal(WidgetTester t) =>
    t.widget<Text>(find.byKey(const ValueKey('tvde_cancel_principal'))).data!;

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('1. janela grátis com contador e, a zero, o custo', (t) async {
    final store = _ServidorFalso([
      () => _q('dentro_da_graca', restam: 3),
      () => _q('corrida_inteira', fee: 700, como: 'carteira'),
    ]);
    final decisoes = await _abrir(t, store);
    expect(_principal(t), contains('mais 00:03 '));
    await _parar(t, 'janela_gratis');
    await t.pump(const Duration(seconds: 1));
    await t.pump();
    expect(store.pedidos, 2);
    expect(find.text('Custo de cancelamento: 7,00 €'), findsOneWidget);
    await _parar(t, 'janela_acabou');
    await t.tap(find.byKey(const ValueKey('tvde_cancel_confirmar')));
    await t.pumpAndSettle();
    expect(decisoes.single.confirmou, isTrue);
  });

  testWidgets('2. corrida inteira paga online', (t) async {
    final store = _ServidorFalso([
      () => _q('corrida_inteira', fee: 1250, como: 'pagamento_retido'),
    ]);
    final decisoes = await _abrir(t, store);
    expect(find.text('Esta corrida já está paga: o valor pago fica retido.'),
        findsOneWidget);
    expect(find.text('Cancelar e pagar 12,50 €'), findsOneWidget);
    await _parar(t, 'corrida_inteira_online');
    await t.tap(find.byKey(const ValueKey('tvde_cancel_voltar')));
    await t.pumpAndSettle();
    expect(decisoes.single.confirmou, isFalse);
  });

  testWidgets('3. corrida inteira em dinheiro → carteira', (t) async {
    final store = _ServidorFalso([
      () => _q('corrida_inteira', fee: 600, como: 'carteira'),
    ]);
    final decisoes = await _abrir(t, store);
    expect(find.textContaining('debitado da tua carteira Bora'), findsOneWidget);
    await _parar(t, 'corrida_inteira_carteira');
    await t.tap(find.text('Cancelar e pagar 6,00 €'));
    await t.pumpAndSettle();
    expect(decisoes.single.confirmou, isTrue);
  });

  testWidgets('4. cotação falhada → aviso neutro', (t) async {
    final store = _ServidorFalso([() => throw Exception('sem rede')]);
    final decisoes = await _abrir(t, store);
    expect(_principal(t), startsWith('Não foi possível confirmar agora'));
    expect(find.textContaining('€'), findsNothing);
    await _parar(t, 'aviso_neutro');
    await t.tap(find.text('Cancelar na mesma'));
    await t.pumpAndSettle();
    expect(decisoes.single.confirmou, isTrue);
  });

  testWidgets('5. o valor subiu ao confirmar → mostra o novo', (t) async {
    final store = _ServidorFalso([
      () => _q('dentro_da_graca', restam: 120),
      () => _q('corrida_inteira', fee: 850, como: 'carteira'),
    ]);
    final decisoes = await _abrir(t, store);
    await t.tap(find.text('Sim, cancelar'));
    await t.pump();
    await t.pump(const Duration(milliseconds: 400));
    expect(decisoes, isEmpty);
    expect(find.text('Custo de cancelamento: 8,50 €'), findsOneWidget);
    await _parar(t, 'valor_subiu');
    await t.tap(find.text('Cancelar e pagar 8,50 €'));
    await t.pumpAndSettle();
    expect(decisoes.single.confirmou, isTrue);
  });
}
