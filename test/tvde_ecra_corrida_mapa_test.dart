import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// [Mapa já saiu · 07/10/2026 · debug_crash_logs, versão 644] "Bad state:
/// GoogleMapController for map ID 2 was used after the associated GoogleMap
/// widget had already been disposed", a partir de `_moverCamara` ←
/// `_deslizarPara` ← `_onGpsFix`. Quando a corrida fica a null o ecrã da
/// corrida troca o mapa por um ecrã vazio (o GoogleMap sai e o controlador
/// morre), mas a seta de 16 ms e o GPS do ecrã continuavam a mexer-lhe na
/// câmara. O GoogleMap é uma vista nativa e não monta num teste de widget:
/// guarda-se o código do ecrã real.
void main() {
  final f = File('lib/screens/driver/tvde/tvde_ride_active_screen.dart')
      .readAsStringSync();

  test('quando a corrida fica a null, larga o controlador e pára a seta', () {
    final ramo = f.indexOf('if (ride == null) {');
    final volta = f.indexOf('return const Scaffold(body: SizedBox.shrink());', ramo);
    expect(ramo, isNonNegative);
    expect(volta, greaterThan(ramo));
    final corpo = f.substring(ramo, volta);
    expect(corpo, contains('_mapCtrl = null;'),
        reason: 'o controlador do mapa que saiu continua guardado');
    expect(corpo, contains('_setaTimer?.cancel();'),
        reason: 'a seta continua a mexer na câmara de um mapa que saiu');
  });

  test('mexer na câmara de um mapa que já saiu nunca rebenta', () {
    for (final metodo in ['void _moverCamara(', 'Future<void> _recenter(']) {
      final i = f.indexOf(metodo);
      expect(i, isNonNegative, reason: metodo);
      // O ficheiro pode vir com quebras de linha do Windows (\r\n).
      final fim = RegExp(r'\r?\n  \}\r?\n').firstMatch(f.substring(i))!.start;
      final corpo = f.substring(i, i + fim);
      expect(corpo, contains('on StateError'),
          reason: '$metodo sem guarda para o controlador morto');
      expect(corpo, contains('_mapCtrl = null;'), reason: metodo);
    }
  });
}
