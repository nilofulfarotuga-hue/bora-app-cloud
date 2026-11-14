/// Validação de contacto do cliente — nome e telemóvel.
///
/// Sessão `tudo-04-09-noite` (2026-09-04). Motivo real: dos 74 clientes na
/// base, 60 estavam sem nome e 69 sem telemóvel, porque o registo só exigia
/// campo "não vazio" — um espaço ou um "a" passavam. Quando um pedido corria
/// mal não havia a quem ligar.
///
/// Vive em `utils/` (e não dentro de um ecrã) porque as MESMAS regras têm de
/// valer no registo, no ecrã de completar perfil e no checkout. Uma regra
/// escrita três vezes diverge; escrita uma vez, não.
///
/// Textos em PT-PT — isto é app de cliente, não painel admin.
library;

/// Nome com pelo menos 3 letras (acentos contam; dígitos e sinais não).
///
/// Devolve `null` quando é válido — a assinatura que o `TextFormField.validator`
/// espera.
String? validarNomeCliente(String? valor) {
  final nome = (valor ?? '').trim();
  if (nome.isEmpty) return 'Indique o seu nome.';
  final letras = RegExp(r'[A-Za-zÀ-ÿ]').allMatches(nome).length;
  if (letras < 3) return 'Indique o seu nome (pelo menos 3 letras).';
  return null;
}

/// Telemóvel português: 9 dígitos a começar por 9.
///
/// Aceita também o indicativo internacional (`+351`, `00351` ou `351`) e
/// ignora espaços, hífenes e parênteses — as pessoas escrevem o número como
/// lhes apetece e recusar `+351 912 345 678` seria recusar um número certo.
String? validarTelemovelPt(String? valor) {
  final bruto = (valor ?? '').trim();
  if (bruto.isEmpty) return 'Indique o seu telemóvel.';
  final n = normalizarTelemovelPt(bruto);
  if (n == null) {
    return 'Telemóvel inválido. Use 9 dígitos a começar por 9 (ex.: 912345678).';
  }
  return null;
}

/// Devolve os 9 dígitos nacionais (ex.: `912345678`), ou `null` se não for um
/// telemóvel português válido.
///
/// É esta forma — nacional, sem indicativo — que se grava em `users.phone`,
/// para que o mesmo número escrito de duas maneiras não crie duas fichas.
String? normalizarTelemovelPt(String? valor) {
  var s = (valor ?? '').replaceAll(RegExp(r'[\s\-().]'), '');
  if (s.isEmpty) return null;
  if (s.startsWith('+')) s = s.substring(1);
  if (s.startsWith('00351')) {
    s = s.substring(5);
  } else if (s.length > 9 && s.startsWith('351')) {
    s = s.substring(3);
  }
  if (!RegExp(r'^9\d{8}$').hasMatch(s)) return null;
  return s;
}

/// Nome como fica gravado: sem espaços nas pontas nem espaços repetidos.
String limparNome(String? valor) =>
    (valor ?? '').trim().replaceAll(RegExp(r'\s+'), ' ');

/// Nome no "Editar perfil" (11/11/2026): 2 a 60 caracteres e pelo menos 2
/// letras — a mesma regra que o servidor (`_apply_user_profile_change`)
/// aplica, para o erro aparecer logo no campo e não só depois de gravar.
String? validarNomePerfil(String? valor) {
  final nome = limparNome(valor);
  if (nome.isEmpty) return 'Escreve o teu nome.';
  final tamanho = nome.runes.length;
  if (tamanho < 2 || tamanho > 60) {
    return 'O nome tem de ter entre 2 e 60 caracteres.';
  }
  if (RegExp(r'\p{L}', unicode: true).allMatches(nome).length < 2) {
    return 'Escreve o teu nome com letras.';
  }
  return null;
}

/// `true` quando a ficha tem contacto utilizável — o teste único que o ecrã de
/// completar perfil e o checkout usam para decidir se ainda falta pedir dados.
bool contactoDoClienteCompleto({String? nome, String? telemovel}) =>
    validarNomeCliente(nome) == null && validarTelemovelPt(telemovel) == null;
