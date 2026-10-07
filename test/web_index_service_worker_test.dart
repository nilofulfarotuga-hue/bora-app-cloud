import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// [Avisos da web · 07/10/2026] O `web/index.html`, quando vê uma versão nova
/// em `versao.json`, limpa as caches e desregista os service workers para
/// recarregar fresco. Desregistava TODOS — também o do Firebase
/// (`firebase-messaging-sw.js`), e com ele a subscrição de avisos: depois de
/// cada publicação o envio seguinte para essa pessoa dava UNREGISTERED com
/// HTTP 200 (visto a 02/10). O do Flutter continua a sair; o do Firebase fica.
void main() {
  final html = File('web/index.html').readAsStringSync();

  test('a limpeza da versão nova não desregista o service worker do Firebase',
      () {
    final i = html.indexOf('getRegistrations()');
    expect(i, isNonNegative, reason: 'a limpeza dos service workers sumiu');
    final bloco = html.substring(i, html.indexOf('window.location.reload()', i));
    expect(bloco, contains("indexOf('firebase-messaging-sw.js') !== -1) return null;"),
        reason: 'o do Firebase voltou a ser desregistado');
    expect(bloco, contains('return r.unregister();'),
        reason: 'os outros service workers (o do Flutter) têm de continuar a sair');
  });
}
