import '../l10n/tr.dart';

/// Aviso de IA do assistente / Amigo (missão fechar-tudo-2026-11-10, E6).
///
/// Regulamento (UE) 2024/1689 (IA), art. 50.º/1: quem fala com uma IA tem de
/// o saber logo. O servidor (`client-assistant`, `comAvisoIA` em amigo.ts) põe
/// o aviso na primeira fala de cada conversa; a app só o põe nas falas que ela
/// própria escreve sem o servidor (a saudação de reserva do Amigo quando a
/// rede falha, ou o texto de boas-vindas escrito no painel).
const String kAvisoIA =
    'Sou uma inteligência artificial (IA) do Bora, não uma pessoa.';

final RegExp _iaMaiusculas = RegExp(r'(^|[^\p{L}])(IA|AI)([^\p{L}]|$)', unicode: true);
final RegExp _iaPorExtenso =
    RegExp(r'intelig[eê]ncia artificial|artificial intelligence', caseSensitive: false);

/// O texto já diz que é uma IA ("IA"/"AI" em maiúsculas ou por extenso).
/// "ia" do verbo ir e "dia" não contam.
bool jaDizQueEIA(String texto) =>
    _iaMaiusculas.hasMatch(texto) || _iaPorExtenso.hasMatch(texto);

/// A primeira fala de cada conversa começa pelo aviso de IA, se ainda não o
/// disser. As seguintes ficam como estão.
String comAvisoIA(String texto, {bool primeiraFala = true}) {
  final t = texto.trim();
  if (!primeiraFala || jaDizQueEIA(t)) return t;
  final aviso = kAvisoIA.tr;
  return t.isEmpty ? aviso : '$aviso $t';
}
