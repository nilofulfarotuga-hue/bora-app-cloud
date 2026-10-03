/// Descarregar um ficheiro gerado na app.
///
/// Porque existe: o `AdminExportService.exportCsv` escrevia num ficheiro
/// temporario e abria a folha de partilha do telemovel. Na **web** fazia
/// `debugPrint` e voltava — ou seja, no painel que o Danilo usa mesmo, o botao
/// de exportar nao fazia rigorosamente nada e nao dizia porque. Botao morto,
/// que e o pior tipo: parece feito.
///
/// Segue o padrao de import condicional que o repo ja usa em `io_compat.dart`
/// e no `place_autocomplete_service.dart`.
library;

export 'descarregar_ficheiro_io.dart'
    if (dart.library.js_interop) 'descarregar_ficheiro_web.dart';
