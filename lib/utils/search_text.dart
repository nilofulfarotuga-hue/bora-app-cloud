/// Texto para pesquisa: minúsculas, sem acentos, espaços colapsados.
///
/// "Açaí  Grande" → "acai grande". Usado nas listas de produtos do parceiro
/// (catálogo e "Acrescentar produto" num pedido), para "acai" encontrar "Açaí".
String normalizarPesquisa(String texto) {
  const comAcento = 'àáâãäåèéêëìíîïòóôõöùúûüýÿñç';
  const semAcento = 'aaaaaaeeeeiiiiooooouuuuyync';
  final buf = StringBuffer();
  for (final ch in texto.toLowerCase().split('')) {
    final i = comAcento.indexOf(ch);
    buf.write(i >= 0 ? semAcento[i] : ch);
  }
  return buf.toString().trim().replaceAll(RegExp(r'\s+'), ' ');
}

/// true quando TODAS as palavras da pesquisa aparecem no texto (qualquer ordem).
/// Pesquisa vazia deixa passar tudo.
bool correspondePesquisa(String texto, String pesquisa) {
  final q = normalizarPesquisa(pesquisa);
  if (q.isEmpty) return true;
  final alvo = normalizarPesquisa(texto);
  return q.split(' ').every(alvo.contains);
}
