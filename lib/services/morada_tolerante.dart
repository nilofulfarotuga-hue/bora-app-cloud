/// Pesquisa de morada tolerante (missão tvde-pedir-nunca-trava-2026-10-14).
///
/// **Cicatriz (14/10/2026):** a cliente Stela escrevia a morada de casa como a
/// tem no papel — "Av. Cidade de Safed n8 a 1d, Guarda" — e a pesquisa com o
/// texto todo vinha vazia (15/09 e 17/09 em `web_health_events`). Sem
/// coordenadas, o botão de pedir ficava cinzento sem dizer porquê.
///
/// O Uber/Google fazem isto: quando o texto todo não dá nada, tentam outra vez
/// sem o número da porta e com as abreviaturas por extenso. Esta função devolve
/// essas tentativas, por ordem, sem repetidos. É pura (sem rede) para se poder
/// provar em teste.
library;

/// Abreviaturas portuguesas de arruamentos → por extenso. Só no INÍCIO de uma
/// parte da morada (é aí que vive o tipo de via), para não estragar nomes.
const Map<String, String> _abreviaturas = {
  'av': 'Avenida',
  'avª': 'Avenida',
  'avda': 'Avenida',
  'r': 'Rua',
  'lg': 'Largo',
  'lgo': 'Largo',
  'pc': 'Praça',
  'pç': 'Praça',
  'pca': 'Praça',
  'pça': 'Praça',
  'trav': 'Travessa',
  'tv': 'Travessa',
  'estr': 'Estrada',
  'urb': 'Urbanização',
  'qta': 'Quinta',
  'calç': 'Calçada',
  'cc': 'Calçada',
  'bº': 'Bairro',
  'br': 'Bairro',
  'bco': 'Beco',
  'al': 'Alameda',
};

/// Tokens que dizem "daqui para a frente é porta/andar/lote", não rua:
/// "n8", "nº8", "n.º8", "8", "8A", ou os marcadores soltos ("nº", "lote")
/// quando o token seguinte é número. "Nossa" ou "Norte" não contam.
final RegExp _tokenNumero = RegExp(
  r'^((n|nº|n\.º|n\.|no\.|num\.?|número)\d.*|\d.*)$',
  caseSensitive: false,
);

/// Marcadores de número soltos — só contam se vier um número a seguir.
final RegExp _marcadorSolto = RegExp(
  r'^(n|nº|n\.º|n\.|no|no\.|num\.?|número|lote|lt\.?)$',
  caseSensitive: false,
);

/// Partes inteiras (entre vírgulas) que só têm porta/andar: "1º Dto", "r/c",
/// "8", "8A", "n8", "lote 5", "3º esq", "a 1d".
final RegExp _parteSoNumero = RegExp(
  r'^(n\.?\s*º?\s*\d.*|nº\s*\d.*|\d+\s*[a-z]?$|\d+\s*º.*|r\s*/\s*c.*|lote\s*\d.*|lt\.?\s*\d.*|(esq|dto|dt|frente|fte)\.?$|[a-z]\s*\d+\s*[a-z]?$)',
  caseSensitive: false,
);

/// Código postal português (6300-123) — fica sempre: ajuda a geocodificar.
final RegExp _codigoPostal = RegExp(r'\b\d{4}-\d{3}\b');

String _limparEspacos(String s) =>
    s.replaceAll(RegExp(r'\s+'), ' ').replaceAll(RegExp(r'\s+,'), ',').trim();

/// Põe por extenso a abreviatura do tipo de via no início de [parte].
/// "Av. Cidade de Safed" → "Avenida Cidade de Safed"; "R Direita" → "Rua Direita".
String _expandirInicio(String parte) {
  final m = RegExp(r'^([A-Za-zÀ-ÿºª]+)\.?(\s+|$)').firstMatch(parte);
  if (m == null) return parte;
  final chave = m.group(1)!.toLowerCase();
  final extenso = _abreviaturas[chave];
  if (extenso == null) return parte;
  // "R" sozinho só é rua se vier seguido de nome (evita "R/C").
  final resto = parte.substring(m.end).trim();
  if (resto.isEmpty) return parte;
  return '$extenso $resto';
}

/// Corta a parte da rua no primeiro token que é número de porta, desde que
/// não faça parte do nome ("Rua 5 de Outubro", "Avenida 25 de Abril").
/// "Avenida Cidade de Safed n8 a 1d" → "Avenida Cidade de Safed".
String _semNumeroDePorta(String parte) {
  final tokens = parte.split(' ').where((t) => t.isNotEmpty).toList();
  for (var i = 1; i < tokens.length; i++) {
    final solto = _marcadorSolto.hasMatch(tokens[i]);
    if (!solto && !_tokenNumero.hasMatch(tokens[i])) continue;
    // "nº" / "lote" soltos só contam se o token seguinte for número.
    if (solto &&
        (i + 1 >= tokens.length || !RegExp(r'^\d').hasMatch(tokens[i + 1]))) {
      continue;
    }
    // Número que é nome de rua: "5 de Outubro", "1º de Maio", "31 de Janeiro".
    final seguinte = i + 1 < tokens.length ? tokens[i + 1].toLowerCase() : '';
    if (RegExp(r'^\d').hasMatch(tokens[i]) &&
        (seguinte == 'de' || seguinte == 'do' || seguinte == 'da')) {
      continue;
    }
    return tokens.sublist(0, i).join(' ');
  }
  return parte;
}

/// Tentativas de pesquisa para [texto], da mais fiel à mais tolerante, sem
/// repetidos (comparação sem maiúsculas). A primeira é sempre o texto tal
/// como foi escrito (aparado).
///
/// Ex.: "Av. Cidade de Safed n8 a 1d, Guarda" →
///   1. "Av. Cidade de Safed n8 a 1d, Guarda"
///   2. "Avenida Cidade de Safed n8 a 1d, Guarda"
///   3. "Avenida Cidade de Safed, Guarda"
List<String> variantesDeMorada(String texto) {
  final original = _limparEspacos(texto);
  if (original.isEmpty) return const [];

  final partes = original
      .split(',')
      .map((p) => p.trim())
      .where((p) => p.isNotEmpty)
      .toList();

  // 2) abreviaturas por extenso, número mantido.
  final expandidas = partes.map(_expandirInicio).toList();
  final comExtenso = _limparEspacos(expandidas.join(', '));

  // 3) sem número de porta/andar: corta a rua no número e tira as partes que
  //    são só porta/andar. Código postal e cidade ficam.
  final semNumero = <String>[];
  for (var i = 0; i < expandidas.length; i++) {
    final p = expandidas[i];
    if (_codigoPostal.hasMatch(p)) {
      semNumero.add(p);
      continue;
    }
    if (_parteSoNumero.hasMatch(p)) continue;
    semNumero.add(i == 0 ? _semNumeroDePorta(p) : p);
  }
  final tolerante = _limparEspacos(semNumero.join(', '));

  final out = <String>[];
  final vistos = <String>{};
  for (final v in [original, comExtenso, tolerante]) {
    if (v.isEmpty) continue;
    if (vistos.add(v.toLowerCase())) out.add(v);
  }
  return out;
}
