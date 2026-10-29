/// NIF português (fatura com NIF, 28/10/2026).
///
/// [nifPtValido] é o ESPELHO da função `nif_pt_valido(text)` do servidor — a
/// mesma regra, passo a passo, para a app avisar antes de o servidor recusar
/// (`NIF_INVALIDO`). Mudar uma obriga a mudar a outra.
///
/// Regra: depois de tirar os espaços, tem de ter 9 dígitos; o primeiro dígito é
/// 1, 2, 3, 5, 6, 8 ou 9 (ou os dois primeiros são 45, 70, 71, 72, 74, 75, 77,
/// 78 ou 79); e o último dígito é o de controlo, calculado por módulo 11 com os
/// pesos 9, 8, 7, 6, 5, 4, 3, 2 sobre os 8 primeiros.
bool nifPtValido(String? nif) {
  final d = (nif ?? '').replaceAll(RegExp(r'\s'), '');
  if (!RegExp(r'^[0-9]{9}$').hasMatch(d)) return false;

  const primeiros = {'1', '2', '3', '5', '6', '8', '9'};
  const doisPrimeiros = {
    '45',
    '70',
    '71',
    '72',
    '74',
    '75',
    '77',
    '78',
    '79',
  };
  if (!primeiros.contains(d[0]) && !doisPrimeiros.contains(d.substring(0, 2))) {
    return false;
  }

  var soma = 0;
  for (var i = 0; i < 8; i++) {
    soma += int.parse(d[i]) * (9 - i);
  }
  var controlo = 11 - (soma % 11);
  if (controlo >= 10) controlo = 0;
  return controlo == int.parse(d[8]);
}

/// Só os dígitos (o servidor também os limpa assim antes de validar).
String soDigitosNif(String? texto) =>
    (texto ?? '').replaceAll(RegExp(r'\D'), '');

/// "123456789" → "123 456 789". Com menos de 9 dígitos devolve o que há.
String formatarNif(String? nif) {
  final d = soDigitosNif(nif);
  if (d.length != 9) return d;
  return '${d.substring(0, 3)} ${d.substring(3, 6)} ${d.substring(6)}';
}
