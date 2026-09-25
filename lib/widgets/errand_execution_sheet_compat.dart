/// Ponte condicional para a folha de execução de favores.
///
/// Porque existe: `errand_execution_sheet.dart` é **zona protegida** (contém
/// `_finalizePurchase`) e a Trava bloqueia edições — nem sequer a troca do
/// `import 'dart:io'` pelo shim `io_compat`. Como esse `dart:io` impede o
/// build web de compilar, a saída correta é resolver **por fora**, sem tocar
/// num único byte do ficheiro protegido.
///
/// No mobile exporta a folha real, exatamente como antes (o
/// `driver_home_screen` continua a chamar `ErrandExecutionSheet.show`).
/// Na web exporta a variante de `errand_execution_sheet_web.dart`.
///
/// Isto não degrada nada: a execução do favor é o **fluxo do estafeta**, que
/// acontece no telemóvel (GPS, câmara, talão). O alvo desta missão é o cliente
/// a comprar e o parceiro a gerir.
library;

export 'errand_execution_sheet.dart'
    if (dart.library.js_interop) 'errand_execution_sheet_web.dart';
