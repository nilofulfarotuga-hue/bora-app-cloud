/// Ramo web: cria um blob e carrega numa ancora invisivel — o mesmo que o
/// browser faz quando se carrega num link de download.
library;

import 'dart:js_interop';
import 'dart:typed_data';

import 'package:web/web.dart' as web;

Future<bool> descarregarBytes(
  List<int> bytes,
  String nomeDoFicheiro,
  String tipoMime,
) async {
  final blob = web.Blob(
    [Uint8List.fromList(bytes).toJS].toJS,
    web.BlobPropertyBag(type: tipoMime),
  );
  final url = web.URL.createObjectURL(blob);
  final a = web.document.createElement('a') as web.HTMLAnchorElement
    ..href = url
    ..download = nomeDoFicheiro;
  web.document.body?.appendChild(a);
  a.click();
  a.remove();
  // Sem revoke o blob fica na memoria do separador ate ele fechar.
  web.URL.revokeObjectURL(url);
  return true;
}
