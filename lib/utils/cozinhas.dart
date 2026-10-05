/// Tipos de comida derivados de `restaurants.cuisine_type` (05/10).
///
/// O campo é texto livre ("Sushi · Japonesa · Poke", "Fast Food",
/// "Italiana · Pizzas · Massas"). Aqui parte-se em pedaços, tiram-se acentos
/// e maiúsculas, e cada pedaço passa por um mapa de sinónimos para uma chave
/// canónica ('sushi', 'pizza', 'hamburguer', 'acai', 'kebab'…). Usado pelas
/// faixas por cozinha da home, pelo filtro da lista de restaurantes e pela
/// pesquisa global — uma verdade só.
library;

/// Minúsculas sem acentos, espaços normalizados.
String normalizarTexto(String s) {
  const de = 'áàâãäéèêëíìîïóòôõöúùûüçñ';
  const para = 'aaaaaeeeeiiiiooooouuuucn';
  final b = StringBuffer();
  for (final ch in s.toLowerCase().split('')) {
    final i = de.indexOf(ch);
    b.write(i >= 0 ? para[i] : ch);
  }
  return b.toString().replaceAll(RegExp(r'\s+'), ' ').trim();
}

/// Sinónimos → chave canónica. O que não está aqui fica com o próprio nome.
const Map<String, String> _sinonimos = {
  'sushi': 'sushi',
  'japonesa': 'sushi',
  'japones': 'sushi',
  'pizza': 'pizza',
  'pizzas': 'pizza',
  'pizzaria': 'pizza',
  'hamburguer': 'hamburguer',
  'hamburgueres': 'hamburguer',
  'hamburger': 'hamburguer',
  'burger': 'hamburguer',
  'burgers': 'hamburguer',
  'fast food': 'hamburguer',
  'fastfood': 'hamburguer',
  'acai': 'acai',
  'kebab': 'kebab',
  'kebabs': 'kebab',
  'doner': 'kebab',
  'durum': 'kebab',
};

const Map<String, String> _nomes = {
  'sushi': 'Sushi',
  'pizza': 'Pizza',
  'hamburguer': 'Hambúrguer',
  'acai': 'Açaí',
  'kebab': 'Kebab',
};

/// Chave canónica de um texto qualquer ('Hambúrguer' → 'hamburguer').
String chaveCozinha(String texto) {
  final n = normalizarTexto(texto);
  return _sinonimos[n] ?? n;
}

/// Nome bonito para mostrar ('hamburguer' → 'Hambúrguer').
String nomeCozinha(String chave) {
  final conhecido = _nomes[chave];
  if (conhecido != null) return conhecido;
  if (chave.isEmpty) return chave;
  return chave[0].toUpperCase() + chave.substring(1);
}

/// Todas as chaves de uma loja, por ordem (a primeira é a principal).
List<String> cozinhaChaves(String cuisineType) {
  final out = <String>[];
  for (final parte in cuisineType.split(RegExp(r'[·,/|]'))) {
    final n = normalizarTexto(parte);
    if (n.isEmpty) continue;
    final k = _sinonimos[n] ?? n;
    if (!out.contains(k)) out.add(k);
  }
  return out;
}

/// Chave de cozinha a que uma pesquisa corresponde, se for uma das
/// conhecidas ('hamburguer' → 'hamburguer', 'hamburg' → 'hamburguer').
/// Serve para a pesquisa achar as lojas que o banco não liga ao termo
/// (ex.: 'hamburguer' dá produtos mas não dá o McDonald's, que é 'Fast Food').
String? cozinhaDaPesquisa(String q) {
  final n = normalizarTexto(q);
  if (n.length < 3) return null;
  final direto = _sinonimos[n];
  if (direto != null) return direto;
  for (final e in _sinonimos.entries) {
    if (e.key.startsWith(n)) return e.value;
  }
  return null;
}
