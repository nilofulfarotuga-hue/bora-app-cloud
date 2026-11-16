// Navegador: dart:html, como o resto da app na web (web_presence_web.dart).
import 'dart:html' as html;

import 'package:flutter/foundation.dart';

void trocarEnderecoWebImpl(String fragmento) {
  try {
    final loc = html.window.location;
    html.window.history
        .replaceState(null, '', '${loc.origin}${loc.pathname}#$fragmento');
  } catch (e) {
    debugPrint('trocarEnderecoWeb falhou => $e');
  }
}
