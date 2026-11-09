// Linhas da RPC `search_products` (09/11/2026, m11): secções (categorias) e
// produtos. O servidor já manda pela ordem certa — nome exato > começa por >
// contém > sinónimo > categoria > erro de escrita > significado — e o
// `match_rank` diz isso. Aqui só se separa e se garante essa ordem (mais
// alto primeiro; empate fica como veio), para nenhum ecrã a baralhar.

class ResultadosPesquisa {
  const ResultadosPesquisa({required this.seccoes, required this.produtos});

  final List<Map<String, dynamic>> seccoes;
  final List<Map<String, dynamic>> produtos;

  bool get vazio => seccoes.isEmpty && produtos.isEmpty;
}

double _rank(Map<String, dynamic> r) => (r['match_rank'] as num?)?.toDouble() ?? 0;

List<Map<String, dynamic>> _ordenar(Iterable<Map<String, dynamic>> linhas) {
  final l = linhas.toList();
  final idx = {for (var i = 0; i < l.length; i++) l[i]: i};
  l.sort((a, b) {
    final c = _rank(b).compareTo(_rank(a));
    return c != 0 ? c : idx[a]!.compareTo(idx[b]!);
  });
  return l;
}

ResultadosPesquisa separarResultadosPesquisa(List<Map<String, dynamic>> linhas) {
  return ResultadosPesquisa(
    seccoes: _ordenar(linhas.where((r) => (r['result_type'] ?? '') == 'section')),
    produtos: _ordenar(linhas.where((r) => (r['result_type'] ?? '') == 'product')),
  );
}
