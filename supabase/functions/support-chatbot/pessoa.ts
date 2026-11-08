// Adendo 1 da missão m4 (08/11/2026, pedido do Danilo): quando o cliente pede para falar com uma
// pessoa, o robô dá o WhatsApp da Bora (nunca o número pessoal nem o nome de ninguém da equipa),
// marca a sessão como escalada e a equipa é avisada. Funções puras, testadas em pessoa_test.ts.

/**
 * "falar com assistente" chegou a 08/11 de um cliente que queria uma pessoa: dentro do chat do
 * suporte o robô já É o assistente, por isso pedir para "falar com o assistente/atendente" conta
 * como pedir uma pessoa.
 */
const PEDE_PESSOA = new RegExp(
  [
    String.raw`\b(falar|conversar|fala|falo)\s+(com\s+)?(o\s+|a\s+|um\s+|uma\s+|algum\s+|alguma\s+)?(pessoa|humano|humana|algu[eé]m|atendente|assistente|funcion[aá]rio|operador|gerente|respons[aá]vel|equipa|equipe|suporte)`,
    String.raw`\b(quero|queria|preciso( de)?|pode(s)? (me )?passar( a| para)?|passa(-me)?( a| para)?)\s+(uma?\s+)?(pessoa|humano|atendente|algu[eé]m real)`,
    String.raw`\b(atendimento|apoio)\s+humano`,
    String.raw`\bpessoa\s+real\b`,
    String.raw`\bn[aã]o\s+quero\s+(falar\s+com\s+)?(um\s+)?(rob[oô]|bot|m[aá]quina)`,
  ].join('|'),
  'i',
);

export function querFalarComPessoa(msg: string): boolean {
  const t = (msg ?? '').trim();
  if (t.length < 4 || t.length > 300) return false;
  return PEDE_PESSOA.test(t);
}

/** "+351937501673" → { visivel: "937 501 673", link: "https://wa.me/351937501673" }. */
export function whatsappDaBora(numero: string | null | undefined): { visivel: string; link: string } {
  const digitos = String(numero ?? '').replace(/\D/g, '');
  const nacional = digitos.startsWith('351') ? digitos.slice(3) : digitos;
  const ok = /^9\d{8}$/.test(nacional);
  const n = ok ? nacional : '937501673';
  return { visivel: `${n.slice(0, 3)} ${n.slice(3, 6)} ${n.slice(6)}`, link: `https://wa.me/351${n}` };
}

export function respostaPessoa(numero: string | null | undefined): string {
  const w = whatsappDaBora(numero);
  return `Claro! Para falares com uma pessoa da equipa Bora, manda mensagem pelo WhatsApp: ${w.visivel} (${w.link}). Também já avisei a equipa — se preferires, respondem-te aqui mesmo nesta conversa.`;
}
