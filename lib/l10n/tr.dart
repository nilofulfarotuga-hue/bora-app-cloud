import 'package:flutter/foundation.dart';

import 'bora_lang.dart';
import 'strings_en.dart';

/// Tradução de texto de interface do app cliente.
///
/// **A chave é o próprio texto em português.** Isso é deliberado: se uma
/// tradução faltar, o utilizador vê o português — nunca uma chave técnica no
/// ecrã. Em português a função é a identidade, portanto o comportamento no
/// idioma de origem é literalmente o de antes desta mudança.
extension BoraTr on String {
  /// Texto traduzido para o idioma activo.
  ///
  /// ```dart
  /// Text('Adicionar ao carrinho'.tr)
  /// ```
  String get tr {
    if (!BoraLang.isEnglish) return this;
    final hit = kStringsEn[this];
    if (hit != null) return hit;
    if (kDebugMode) missingEnKeys.add(this);
    return this;
  }

  /// Igual a [tr] mas para texto com valores lá dentro.
  ///
  /// O texto guardado usa marcadores posicionais `{0}`, `{1}`, … e os valores
  /// entram pela ordem em que apareciam na interpolação original:
  ///
  /// ```dart
  /// // antes: 'Faltam ${m} minutos'
  /// 'Faltam {0} minutos'.trArgs([m])
  /// ```
  ///
  /// Os valores (preços, distâncias, nomes de loja) passam intactos — só a
  /// moldura de texto à volta é que muda de idioma.
  String trArgs(List<Object?> args) {
    var out = tr;
    for (var i = 0; i < args.length; i++) {
      out = out.replaceAll('{$i}', '${args[i]}');
    }
    return out;
  }
}

/// Chaves pedidas em inglês que não existem no dicionário.
///
/// Só se enche em debug. O teste `test/l10n_cobertura_test.dart` usa a lista
/// completa extraída do código; isto serve para apanhar em execução um caso
/// que tenha escapado.
final Set<String> missingEnKeys = <String>{};
