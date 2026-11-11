// Amigo Bora — fala mais humana (11/11/2026, ordem do Danilo das 10:54, missão fechar-tudo-2026-11-11).
// Funções puras (sem rede), testadas em estilo_test.ts. O prompt pede o mesmo; aqui garante-se em código o
// que dá para garantir:
//   · nunca se reapresenta depois da saudação ("Sou o Amigo Bora…"), a não ser que lhe perguntem quem é;
//   · não abre as respostas pelo nome ("Rui, …") e não repete o nome que já usou na conversa;
//   · dá os parabéns uma vez só na conversa;
//   · UMA sugestão só: tira as frases "se preferires, também há…" e não deixa criar um 2.º carrinho
//     alternativo para um pedido de uma coisa só;
//   · o histórico da conversa que vai ao modelo: as últimas N mensagens (com as notas das ferramentas delas).

// deno-lint-ignore no-explicit-any
type Json = any;

function semAcentos(s: unknown): string {
  return String(s ?? '').toLowerCase().normalize('NFD').replace(/[̀-ͯ]/g, '');
}

/** Partes em frases, mantendo os parágrafos ("\n\n") e o espaço que vinha a seguir. */
function frases(texto: string): Array<{ frase: string; sep: string }> {
  const out: Array<{ frase: string; sep: string }> = [];
  const re = /[^.!?\n]+(?:[.!?]+|(?=\n)|$)(\s*)/g;
  let m: RegExpExecArray | null;
  while ((m = re.exec(texto)) !== null) {
    if (m[0].length === 0) { re.lastIndex++; continue; }
    const sep = m[1] ?? '';
    const frase = m[0].slice(0, m[0].length - sep.length);
    const anterior = out[out.length - 1];
    // um bocado sem letras (ex.: "🎉" no fim) vai com a frase de antes
    if (anterior && !/[\p{L}\p{N}]/u.test(frase)) {
      anterior.frase = anterior.frase + anterior.sep + frase;
      anterior.sep = sep;
      continue;
    }
    out.push({ frase, sep });
  }
  return out;
}

function juntar(partes: Array<{ frase: string; sep: string }>): string {
  return partes.map((p) => p.frase + p.sep).join('').replace(/\n{3,}/g, '\n\n').replace(/[ \t]{2,}/g, ' ').trim();
}

/** Tira as frases que [tirar] marca; se não sobrar nada, fica o texto como estava. */
function tirarFrases(texto: string, tirar: (frase: string, i: number) => boolean): string {
  const ps = frases(texto);
  // Só se mexe se as frases cobrem o texto todo (nada se perde por um corte estranho).
  if (ps.map((p) => p.frase + p.sep).join('') !== texto) return texto.trim();
  // a frase avalia-se sem o que vem antes da 1.ª letra ("🎉 Se preferires…" → "Se preferires…")
  const ficam = ps.filter((p, i) => !tirar(p.frase.trim().replace(/^[^\p{L}\p{N}]+/u, ''), i));
  if (ficam.length === ps.length) return texto.trim();
  const r = juntar(ficam);
  return r.length > 0 ? r : texto.trim();
}

function maiusculaInicial(t: string): string {
  return t.replace(/^(\s*[¿¡"«(]?)(\p{Ll})/u, (_m, a: string, b: string) => a + b.toUpperCase());
}

// ─── Quem és ──────────────────────────────────────────────────────────────────

/** A pessoa pergunta quem/o que é o Amigo (aí pode dizer que é o assistente virtual). */
export function perguntaQuemEs(msg: string): boolean {
  const t = semAcentos(msg);
  return /\b(es|e)\s+(uma?\s+)?(pessoa|humano|humana|robo|bot|maquina|ia|inteligencia artificial|real|verdadeir)/.test(t) ||
    /\bquem\s+(es|e)\s+(tu|voce)\b|\b(falo|estou a falar|to falando|estou falando|falando) com (uma pessoa|um robo|alguem|um humano|uma maquina|um bot)|\bo que (es|e) (tu|voce)\b|\binteligencia artificial\b|\bchatgpt\b/.test(t);
}

// "Sou o Amigo Bora.", "Olá! Eu sou o Amigo, o teu…", "Sou o Bora Assistente…"
const RE_APRESENTA = /^(ol[aá]|oi|boa (tarde|noite)|bom dia)?[!,.\s]*(eu\s+)?sou\s+o\s+(teu\s+)?(amigo(\s+bora)?|bora\s+assistente|assistente(\s+virtual)?(\s+d[ao]\s+bora)?)\b/i;

/** Depois da saudação o Amigo não se volta a apresentar (a não ser que lhe perguntem quem é). */
export function semReapresentacao(texto: string): string {
  return tirarFrases(texto, (f) => RE_APRESENTA.test(f));
}

// ─── O nome ───────────────────────────────────────────────────────────────────

function escapar(s: string): string {
  return s.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
}

/**
 * Nunca abre a resposta pelo nome ("Ana, a Goola…" → "A Goola…"). Se o nome já foi usado nesta conversa,
 * também sai o vocativo do meio ("Está pronto, Ana!" → "Está pronto!").
 */
export function semNomeNoInicio(texto: string, nome: string | null | undefined, jaUsouNome: boolean): string {
  const n = String(nome ?? '').trim();
  if (!n || n.length > 30) return texto;
  const en = escapar(n);
  let t = texto.replace(new RegExp(`^(\\s*)${en}\\s*[,!]\\s*`, 'iu'), '$1');
  if (t !== texto) t = maiusculaInicial(t);
  if (jaUsouNome) {
    t = t.replace(new RegExp(`,\\s*${en}(?=\\s*[!.?,])`, 'giu'), '');
  }
  return t.trim();
}

/** O texto usa o nome (como palavra). */
export function usaNome(texto: string, nome: string | null | undefined): boolean {
  const n = String(nome ?? '').trim();
  if (!n) return false;
  return new RegExp(`(^|[^\\p{L}])${escapar(n)}([^\\p{L}]|$)`, 'iu').test(texto ?? '');
}

// ─── Parabéns uma vez ─────────────────────────────────────────────────────────

const RE_PARABENS = /parab[eé]ns|feliz anivers[aá]rio|muitos anos de vida|bom anivers[aá]rio/i;

export function temParabens(texto: string): boolean {
  return RE_PARABENS.test(texto ?? '');
}

/** Se já deu os parabéns nesta conversa, as frases com parabéns saem. */
export function semParabensRepetidos(texto: string, jaDeuParabens: boolean): string {
  if (!jaDeuParabens) return texto;
  return tirarFrases(texto, (f) => RE_PARABENS.test(f));
}

// ─── Uma sugestão só ──────────────────────────────────────────────────────────

const RE_ALTERNATIVA_INICIO = /^(e\s+)?(se\s+preferires|se\s+quiseres\s+(algo|uma?\s+coisa|uma?\s+(maior|menor|mais|outr))|se\s+tiveres\s+mais\s+fome|tamb[eé]m\s+(h[aá]|tens|tem)|h[aá]\s+tamb[eé]m|ou\s+ent[aã]o|em\s+alternativa|outra\s+op[cç][aã]o|como\s+alternativa)/i;
const RE_OFERECE = /\b(h[aá]|tens|tem|tamb[eé]m|outr[oa]s?|maior|menor|mais\s+barat|op[cç][oõ]es|op[cç][aã]o|em\s+vez)\b/i;

/** Tira as segundas opções ("Se preferires uma maior, há a Big Bowl…"). Ações ("podes agendar") ficam. */
export function umaSugestaoSo(texto: string): string {
  return tirarFrases(texto, (f, i) => i > 0 && RE_ALTERNATIVA_INICIO.test(f) && RE_OFERECE.test(f));
}

/** A pessoa pediu várias coisas ou para comparar (aí pode haver mais de um carrinho). */
export function pedeVariasCoisas(msg: string): boolean {
  const t = semAcentos(msg);
  return /,|\s\+\s|\be\s+(uma?|uns|umas|o|a|os|as|\d)\b|\bcompar|\bmais barat|\bou\b|\bvarias|\bvarios|\bduas lojas|\bopcoes|\balternativ|\boutras?\b|\boutros?\b|\blista\b/.test(t) ||
    (t.match(/\be\b/g)?.length ?? 0) >= 1 && t.split(/\s+/).length > 6;
}

/**
 * Pode criar-se mais um carrinho nesta volta? Num pedido de uma coisa só, o 1.º carrinho é a sugestão;
 * um 2.º (outra loja ou outro artigo em alternativa) é recusado. Cestos (basket_quote) não contam.
 */
export function podeOutroCarrinho(carrinhosSoltosDaVolta: number, msg: string): boolean {
  return carrinhosSoltosDaVolta < 1 || pedeVariasCoisas(msg);
}

// ─── Tudo junto ───────────────────────────────────────────────────────────────

export interface ContextoFala {
  nome?: string | null;
  /** Respostas anteriores do assistente nesta conversa (texto). */
  anteriores: string[];
  /** A mensagem da pessoa agora. */
  mensagem: string;
}

/** A fala do modelo afinada: sem reapresentação, sem o nome a abrir, parabéns uma vez, uma sugestão só. */
export function afinarFala(texto: string, c: ContextoFala): string {
  let t = String(texto ?? '').trim();
  if (!t) return t;
  if (!perguntaQuemEs(c.mensagem)) t = semReapresentacao(t);
  const jaUsouNome = c.anteriores.some((a) => usaNome(a, c.nome));
  t = semNomeNoInicio(t, c.nome, jaUsouNome);
  t = semParabensRepetidos(t, c.anteriores.some(temParabens));
  t = umaSugestaoSo(t);
  return maiusculaInicial(t);
}

// ─── O histórico que vai ao modelo ────────────────────────────────────────────

/**
 * As últimas [max] mensagens da pessoa e do assistente (por ordem), com as linhas das ferramentas que estão
 * entre elas. As linhas vêm por ordem cronológica.
 */
export function ultimasMensagens<T extends { role?: string }>(linhas: T[], max: number): T[] {
  const idx: number[] = [];
  linhas.forEach((l, i) => { if (l?.role === 'user' || l?.role === 'assistant') idx.push(i); });
  if (idx.length <= max) return linhas;
  return linhas.slice(idx[idx.length - max]);
}

/** Os textos das respostas do assistente no histórico (para o nome e os parabéns). */
export function textosDoAssistente(linhas: Json[]): string[] {
  return (linhas ?? []).filter((l) => l?.role === 'assistant').map((l) => String(l?.content ?? ''));
}
