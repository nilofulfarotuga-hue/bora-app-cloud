/// Aviso de IA do Amigo (missão fechar-tudo-2026-11-10, E6; revisto a 11/11/2026).
///
/// Regulamento (UE) 2024/1689 (IA), art. 50.º/1: quem fala com uma IA tem de o
/// saber. Até 11/11/2026 o aviso ia na primeira FALA do Amigo. Ordem do Danilo
/// (11/11, 10:54): "ele não tem que falar que é inteligência artificial... todo
/// mundo vai saber que ele é um robô". O aviso mudou de sítio, não foi apagado:
///   (a) etiqueta pequena e permanente "assistente virtual" no cabeçalho do
///       ecrã do Amigo, por baixo do nome (amigo_screen.dart, com `.tr`; EN
///       "virtual assistant");
///   (b) uma linha na Informação legal da app ([kAvisoLegalAssistente]).
/// Nunca na fala nem a abrir a conversa. O servidor (`client-assistant`) também
/// deixou de o pôr (`semAvisoIA` em amigo.ts).
library;

/// A frase antiga, que até 11/11/2026 abria a primeira fala. Já não se diz:
/// só serve para a tirar de respostas antigas guardadas.
const String kAvisoIA =
    'Sou uma inteligência artificial (IA) do Bora, não uma pessoa.';

/// A linha da Informação legal (PT-PT, sem `.tr`, como o resto desse ecrã).
const String kAvisoLegalAssistente =
    'O Amigo Bora é um assistente virtual automático (inteligência '
    'artificial). Não substitui o apoio humano: no próprio chat podes pedir '
    'para falar com uma pessoa da equipa.';

/// Tira a frase antiga do aviso de um texto (respostas guardadas antes de
/// 11/11/2026). O resto fica igual.
String semAvisoIA(String texto) => texto
    .replaceAll(kAvisoIA, ' ')
    .replaceAll(RegExp(r'[ \t]{2,}'), ' ')
    .trim();
