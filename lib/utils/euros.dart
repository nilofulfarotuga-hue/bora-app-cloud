/// PREÇOS NO FORMATO DE PORTUGAL (melhorias-paridade 26/10, item 6).
///
/// "9,65 €" — vírgula decimal e o símbolo depois, com espaço. Antes a app
/// mostrava "€9.65" (formato inglês). Isto muda SÓ a forma de mostrar:
/// recebe o mesmo número e nunca arredonda de outra maneira
/// (`toStringAsFixed(2)`, igual ao que estava).
String eur(num valor) {
  final negativo = valor < 0;
  final t = valor.abs().toStringAsFixed(2).replaceAll('.', ',');
  return negativo ? '-$t €' : '$t €';
}

/// Cêntimos → "9,65 €".
String eurCents(num cents) => eur(cents / 100);
