/// Ramo mobile/desktop: no telemovel nao se "descarrega", partilha-se. Quem
/// chama trata disso; aqui devolve-se falso para o chamador saber que tem de
/// seguir pelo caminho da partilha.
library;

Future<bool> descarregarBytes(
  List<int> bytes,
  String nomeDoFicheiro,
  String tipoMime,
) async =>
    false;
