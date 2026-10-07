import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// [Painel rebenta · 07/10/2026 · debug_crash_logs] "Null check operator used
/// on a null value" a construir `_NotificationElement<DraggableScrollableNotification>`,
/// 19 vezes no Android entre as versões 637 e 654, a seguir a terminar
/// corridas. Pilha: `DraggableScrollableController._onExtentReplaced` ←
/// `_DraggableScrollableSheetState.didUpdateWidget`.
///
/// No ecrã da corrida (`TvdeRideActiveScreen`) o botão SOS só existe enquanto
/// a corrida não acabou e está, na mesma `Stack`, ANTES do painel arrastável.
/// Os dois são `Positioned` sem chave: quando o SOS sai, o Flutter casa o
/// painel com o lugar do SOS, monta um painel NOVO com o mesmo controlador e
/// desmonta o velho — que, ao sair, desliga o controlador e destrói o tamanho
/// do novo. A actualização seguinte rebenta. Com chaves, o painel é sempre o
/// mesmo.
///
/// O ecrã real não monta num teste (mapa nativo, GPS, Supabase): prova-se o
/// mecanismo com a mesma pilha e guarda-se o ficheiro real.
class _Pilha extends StatefulWidget {
  const _Pilha({required this.comChave});
  final bool comChave;

  @override
  State<_Pilha> createState() => _PilhaState();
}

class _PilhaState extends State<_Pilha> {
  final DraggableScrollableController ctrl = DraggableScrollableController();
  bool sos = true;
  double extent = 0.30;

  @override
  void dispose() {
    ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        const SizedBox.expand(),
        Positioned(right: 8, bottom: 8, child: Text('mira $extent')),
        if (sos)
          Positioned(
            key: widget.comChave ? const ValueKey<String>('sos') : null,
            left: 8,
            bottom: 8,
            child: const Material(child: Text('SOS')),
          ),
        Positioned.fill(
          key: widget.comChave ? const ValueKey<String>('painel') : null,
          child: NotificationListener<DraggableScrollableNotification>(
            onNotification: (n) => false,
            child: DraggableScrollableSheet(
              controller: ctrl,
              initialChildSize: 0.30,
              minChildSize: 0.14,
              maxChildSize: 0.52,
              snap: true,
              snapSizes: const [0.14, 0.30, 0.52],
              builder: (ctx, sc) => ListView(
                controller: sc,
                children: const [SizedBox(height: 600, child: Text('painel'))],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

Future<_PilhaState> _montar(WidgetTester tester, {required bool comChave}) async {
  await tester.pumpWidget(MaterialApp(home: Scaffold(body: _Pilha(comChave: comChave))));
  return tester.state<_PilhaState>(find.byType(_Pilha));
}

void main() {
  testWidgets(
      'sem chave (como estava): o SOS sai no fim da corrida e o painel '
      'arrastável rebenta — a réplica reproduz o erro de produção',
      (tester) async {
    final s = await _montar(tester, comChave: false);
    s.setState(() => s.sos = false); // corrida terminada
    await tester.pump();
    s.setState(() => s.extent = 0.14); // a actualização seguinte
    await tester.pump();
    // Em debug o Flutter apanha-o à entrada ("already attached"); na app
    // publicada passa e rebenta depois em `_onExtentReplaced` (Null check).
    final erro = tester.takeException();
    expect(erro, isNotNull, reason: 'a réplica deixou de reproduzir o erro');
    expect(
        '$erro',
        anyOf(contains('already attached to a sheet'),
            contains('Null check operator')));
  });

  testWidgets(
      'com chave: o SOS sai e volta (fim da corrida, corrida da fila) e o '
      'painel é sempre o mesmo, ligado ao controlador', (tester) async {
    final s = await _montar(tester, comChave: true);
    final painel = tester.element(find.byType(DraggableScrollableSheet));
    expect(s.ctrl.isAttached, isTrue);

    s.setState(() => s.sos = false); // corrida terminada
    await tester.pump();
    s.setState(() => s.extent = 0.14);
    await tester.pump();
    expect(tester.takeException(), isNull);
    expect(tester.element(find.byType(DraggableScrollableSheet)), same(painel),
        reason: 'o painel foi recriado');
    expect(s.ctrl.isAttached, isTrue);

    s.setState(() => s.sos = true); // entra a corrida da fila
    await tester.pump();
    s.setState(() => s.extent = 0.52);
    await tester.pump();
    expect(tester.takeException(), isNull);
    expect(tester.element(find.byType(DraggableScrollableSheet)), same(painel));
    expect(s.ctrl.isAttached, isTrue);
    s.ctrl.jumpTo(0.52); // o controlador continua a mandar no painel
    await tester.pump();
    expect(s.ctrl.size, closeTo(0.52, 0.001));
  });

  test('o ecrã real da corrida tem as duas chaves na pilha', () {
    final f = File('lib/screens/driver/tvde/tvde_ride_active_screen.dart')
        .readAsStringSync();
    final painel = f.indexOf("key: const ValueKey<String>('tvde_corrida_painel')");
    final sos = f.indexOf("key: const ValueKey<String>('tvde_corrida_sos')");
    final listener =
        f.indexOf('NotificationListener<DraggableScrollableNotification>');
    expect(painel, isNonNegative, reason: 'o painel perdeu a chave');
    expect(sos, isNonNegative, reason: 'o SOS perdeu a chave');
    expect(sos < painel && painel < listener, isTrue,
        reason: 'a chave do painel tem de estar no Positioned que o envolve');
    expect(listener - painel < 120, isTrue,
        reason: 'a chave do painel não está no Positioned do painel');
  });
}
