/// Camada de compatibilidade `dart:io` ↔ web.
///
/// Porque existe: `dart:io` não existe no browser, e 20 ficheiros de `lib/`
/// usavam `File` (quase sempre `File(xfile.path)` vindo do `image_picker`),
/// `Platform.isAndroid/isIOS` e `SocketException`. Sem isto, o build web
/// falha na compilação — não em runtime.
///
/// Como funciona: no mobile este ficheiro reexporta o **`dart:io` verdadeiro**,
/// por isso os call-sites (`Platform.isAndroid`, `await f.readAsBytes()`)
/// ficam byte-a-byte iguais e o Android não muda nada. Na web entram os stubs
/// de `io_compat_web.dart`, que continuam a **ler mesmo os bytes** através do
/// `XFile` (o `image_picker` web devolve `blob:` URLs).
///
/// Segue o padrão de conditional import que o repo já usa em
/// `place_autocomplete_service.dart`.
///
/// Uso: trocar `import 'dart:io';` por `import '<...>/utils/io_compat.dart';`
library;

// O ramo por defeito é o de `dart:io` DE PROPÓSITO: o `flutter analyze` (e o
// build Android) resolvem sempre o default, por isso os tipos ficam a ser o
// `File`/`Platform` verdadeiros e não há conflito de tipos com o resto do
// código. Só quando `dart:js_interop` existe — isto é, ao compilar para o
// browser — é que entram os stubs web.
export 'io_compat_io.dart' if (dart.library.js_interop) 'io_compat_web.dart';
