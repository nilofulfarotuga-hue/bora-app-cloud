// Amigo Bora v1 (08/11/2026, missão m4-amigo-bora-v1-2026-11-08) — a parte "amigo" do assistente,
// em funções puras (sem rede) para se testar com `deno test`:
//   · momento do dia em Lisboa e o hábito que bate com agora ("sexta à noite: Jyosmi");
//   · se uma mensagem é conversa livre (vai ao modelo pequeno) ou compra/ajuda (modelo de sempre);
//   · se o cliente quer comprar/marcar (a resposta tem de acabar numa ação);
//   · a "deixa" do fim da conversa (promoção, parceiro novo, tokens, check-in) com rotação de 24 h;
//   · a comparação linha a linha com a outra app, calculada aqui — o modelo nunca faz contas;
//   · o bloco de personalidade e o contexto do perfil (cortado a ~600 tokens).

// deno-lint-ignore no-explicit-any
type Json = any;

export type Periodo = 'manha' | 'almoco' | 'tarde' | 'noite';

export interface Momento {
  /** 1 = segunda … 7 = domingo (ISO). */
  dia: number;
  diaNome: string;
  periodo: Periodo;
  hora: number;
}

export const DIAS = ['segunda', 'terça', 'quarta', 'quinta', 'sexta', 'sábado', 'domingo'];

export function periodoDaHora(h: number): Periodo {
  if (h >= 5 && h <= 10) return 'manha';
  if (h >= 11 && h <= 14) return 'almoco';
  if (h >= 15 && h <= 18) return 'tarde';
  return 'noite';
}

/** Dia e hora em Lisboa (o servidor corre em UTC). */
export function momentoLisboa(d: Date): Momento {
  const partes = new Intl.DateTimeFormat('en-GB', {
    timeZone: 'Europe/Lisbon', weekday: 'short', hour: '2-digit', hourCycle: 'h23',
  }).formatToParts(d);
  const wd = partes.find((p) => p.type === 'weekday')?.value ?? 'Mon';
  const hora = Number(partes.find((p) => p.type === 'hour')?.value ?? '12') % 24;
  const dia = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'].indexOf(wd) + 1 || 1;
  return { dia, diaNome: DIAS[dia - 1], periodo: periodoDaHora(hora), hora };
}

export interface Habito {
  dia: number;
  dia_nome?: string;
  periodo: Periodo;
  loja_id: string;
  loja: string;
  vezes: number;
  ultimo_pedido_id?: string | null;
}

/**
 * O hábito que bate com agora: mesmo dia da semana e mesmo período, com um pouco de folga
 * ("sexta ao fim da tarde" já conta para o jantar de sexta; 10h já conta para o almoço).
 */
export function habitoDeAgora(perfil: Json, m: Momento): Habito | null {
  const lista: Habito[] = Array.isArray(perfil?.habitos) ? perfil.habitos : [];
  const bate = (h: Habito) => {
    if (Number(h?.dia) !== m.dia || !h?.loja_id) return false;
    if (h.periodo === m.periodo) return true;
    if (h.periodo === 'noite' && m.periodo === 'tarde' && m.hora >= 17) return true;
    if (h.periodo === 'almoco' && m.periodo === 'manha' && m.hora >= 10) return true;
    return false;
  };
  const bons = lista.filter(bate).sort((a, b) => Number(b.vezes ?? 0) - Number(a.vezes ?? 0));
  return bons[0] ?? null;
}

export function nomeDoCliente(perfil: Json): string | null {
  const n = typeof perfil?.nome_tratamento === 'string' ? perfil.nome_tratamento.trim() : '';
  return n && n.length <= 30 ? n : null;
}

const DIA_COM_ARTIGO: Record<number, string> = {
  1: 'segunda', 2: 'terça', 3: 'quarta', 4: 'quinta', 5: 'sexta', 6: 'sábado', 7: 'domingo',
};

/** "Hoje é sexta. Queres o do costume do Jyosmi? Tenho o teu último pedido pronto para repetir." */
export function saudacaoHabitual(h: Habito, perfil: Json): string {
  const nome = nomeDoCliente(perfil);
  const dia = DIA_COM_ARTIGO[h.dia] ?? 'hoje';
  const ola = nome ? `Olá, ${nome}! ` : '';
  return `${ola}Hoje é ${dia}. Queres o do costume do ${h.loja}? Tenho o teu último pedido pronto para repetir.`;
}

export function saudacaoSimples(m: Momento, perfil: Json, boasVindas: string): string {
  const nome = nomeDoCliente(perfil);
  const cumprimento = m.hora >= 5 && m.hora < 13 ? 'Bom dia' : m.hora >= 13 && m.hora < 20 ? 'Boa tarde' : 'Boa noite';
  const texto = (boasVindas ?? '').trim() ||
    'Sou o Amigo Bora. Sei o que há na Guarda e o que costumas pedir. Pergunta-me o que quiseres.';
  return `${cumprimento}${nome ? `, ${nome}` : ''}! ${texto}${lembreteHabitual(perfil)}`;
}

/**
 * m11 (09/11/2026, adendo 1 do Danilo: "cumprimenta pelo nome e lembra o habitual"): fora do dia/hora do
 * hábito, a saudação lembra a loja do costume numa frase curta. Sem perfil (ou "não lembrar"), nada.
 */
export function lembreteHabitual(perfil: Json): string {
  const habitos: Json[] = Array.isArray(perfil?.habitos) ? perfil.habitos : [];
  const lojas: Json[] = Array.isArray(perfil?.lojas_favoritas) ? perfil.lojas_favoritas : [];
  const loja = limpo(habitos[0]?.loja ?? lojas[0]?.nome ?? '', 40);
  return loja ? ` Se te apetecer, preparo-te o do costume do ${loja}.` : '';
}

// ─── A cara do Amigo (m11, 09/11/2026) ────────────────────────────────────────
// O rosto da app reage ao que o Amigo diz. O modelo escolhe a cara com uma etiqueta [cara:...] no início da
// resposta; o código tira-a do texto (o cliente nunca a vê) e devolve-a no campo opcional "emocao". Sem
// etiqueta, decide-se pelo que a resposta tem. As apps antigas ignoram o campo.

export const EMOCOES = ['alegre', 'triste', 'surpreso', 'pensativo', 'confuso', 'a_falar'] as const;
export type Emocao = typeof EMOCOES[number];

const RE_CARA = /\[\s*cara\s*:\s*([a-zA-Z_ ]+?)\s*\]\s*/g;

/** Tira as etiquetas [cara:...] do texto e devolve a primeira cara válida. */
export function extrairEmocao(texto: string): { texto: string; emocao: Emocao | null } {
  let emocao: Emocao | null = null;
  const limpoTxt = String(texto ?? '').replace(RE_CARA, (_m, e: string) => {
    const v = e.trim().toLowerCase().replace(/\s+/g, '_');
    if (!emocao && (EMOCOES as readonly string[]).includes(v)) emocao = v as Emocao;
    return '';
  }).trim();
  return { texto: limpoTxt, emocao };
}

/** A cara quando o modelo não disse nenhuma (ou a resposta foi escrita pelo sistema). */
export function emocaoPorDefeito(o: { erro: boolean; handoff: boolean; temCarrinho: boolean; texto: string }): Emocao {
  if (o.erro || o.handoff) return 'confuso';
  if (o.temCarrinho) return 'alegre';
  const t = String(o.texto ?? '').toLowerCase();
  if (/não (percebi|entendi)/.test(t)) return 'confuso';
  if (/não (encontrei|há|consegui|temos|tenho)|fechad|esgotad|indispon/.test(t)) return 'triste';
  return 'a_falar';
}

/**
 * Adendo 1-B (09/11/2026): "não é amigo de compras; é amigo para o que ele quiser". Com a personalidade
 * ligada, esta é a frase de identidade (substitui a do "assistente de compras").
 */
export const IDENTIDADE_AMIGO =
  'És o Amigo Bora, o amigo do cliente na Guarda, Portugal, para o que ele quiser: conversar, comida (restaurantes), mercado e supermercados, lojas e farmácias, Favores, Limpeza, Reservas de mesa, Serviços, dúvidas sobre a Guarda e sobre a app Bora. NUNCA te apresentas nem te descreves como "assistente de compras" nem "amigo de compras": és o Amigo, para tudo.';

// ─── Que tipo de mensagem é ───────────────────────────────────────────────────

// Começos de palavra (apanham "reembolso", "tokens", "encomendar"...) e palavras curtas inteiras.
const RE_COMPRA = /\b(quer(o|ia|emos)|precis|faz(-| )?me|compr|pede|pedi|encomend|carrinho|cesto|lista|pre[cç]o|custa|barat|loja|mercado|supermercado|restaurante|farm[aá]cia|entreg|pedido|token|carteira|saldo|reembols|favor|limpeza|faxina|lavagem|reserv|marca|agend|glovo|uber|ifood|bolt|compar|promo|desconto|c[oó]digo|costume|habitual|repet|o mesmo|manda|traz|enche)/i;
const RE_CURTAS = /\b(sim|isso|esse|essa|ok|caro|cara)\b/i;
const RE_NUMERO = /\d/;

/**
 * Conversa livre = sem foto, curta, sem palavras de compra/ajuda e sem uma compra a meio
 * na resposta anterior. Vai ao modelo pequeno; tudo o resto fica no modelo de sempre.
 */
export function pareceConversaLivre(msg: string, o: { temImagem: boolean; ultimaTinhaCompra: boolean }): boolean {
  const t = (msg ?? '').trim();
  if (!t || o.temImagem || o.ultimaTinhaCompra) return false;
  if (t.length > 160) return false;
  const n = t.normalize('NFC');
  // m11 adendo 4 (09/11/2026): "não quero comprar nada, só conversar" é conversa, não compra.
  if (soConversa(n)) return true;
  if (RE_NUMERO.test(t)) return false;
  return !RE_COMPRA.test(n) && !RE_CURTAS.test(n);
}

// m11 adendo 4 (09/11/2026, print do Danilo): "não quero comprar, só conversar" fazia pedeAcao() dar true
// (o RE_ACAO apanha "quero" e "compr"), entrava a nota ACAO_NUDGE e o modelo respondia "O cliente disse...".
const RE_NEGA_COMPRA = /\b(n[aã]o|nem|nada de)\s+(quero|queria|preciso|vou|estou a pensar|penso|tenho (de|que))?\s*(de\s+)?(nada|comprar|compras|pedir|encomendar|nenhuma|nenhum)/i;
const RE_SO_CONVERSA = /\b(s[oó]|apenas|somente)\s+(quero\s+|queria\s+)?(conversar|falar|dar dois dedos de conversa|passar|dizer ol[aá]|estar|ver)\b|\bestou\s+s[oó]\s+a\s+(ver|espreitar|conversar|passar)\b|\bconversar\s+(um\s+bocado|contigo|um\s+pouco)\b|\bsem\s+comprar\b/i;
const RE_CUMPRIMENTO = /^\s*(ol[aá]+|oi+|ei|boas|bom dia|boa tarde|boa noite|e a[ií]|tudo bem|tudo bom|como (est[aá]s|vai|vais|te sentes|correu)|como [ée] que (est[aá]s|vai)|estás bom|est[aá]s boa)\b[^]*$/i;

/** O cliente só quer conversar (nega a compra, diz que é só conversa, ou é um cumprimento curto). */
export function soConversa(msg: string): boolean {
  const t = (msg ?? '').trim();
  if (!t) return false;
  if (RE_NEGA_COMPRA.test(t) || RE_SO_CONVERSA.test(t)) return true;
  // cumprimento curto ("olá, tudo bem?", "como estás?") sem pedido de compra a seguir
  return t.length <= 60 && RE_CUMPRIMENTO.test(t) && !RE_ACAO.test(t.replace(RE_CUMPRIMENTO_INICIO, ''));
}
const RE_CUMPRIMENTO_INICIO = /^\s*(ol[aá]+|oi+|ei|boas|bom dia|boa tarde|boa noite|e a[ií]|tudo bem)[,!.\s]*/i;

const RE_ACAO = /\b(quer(o|ia)\b|precis|faz(-| )?me|compr|pede|encomend|manda(-me)? vir|traz|enche|faxina|limpeza|marca|agend|favor)/i;
const RE_AJUDA = /\b(onde est|estado|reembols|cancel|token|carteira|saldo|fatura|factura|recibo|reclam|queixa|suporte|humano|pessoa|como (é que )?funciona|o que (é|e) )/i;

/** O cliente quer comprar/marcar alguma coisa (a resposta tem de acabar numa ação). */
export function pedeAcao(msg: string): boolean {
  const t = (msg ?? '').trim();
  if (t.length < 4) return false;
  if (soConversa(t)) return false; // m11 adendo 4: negação e conversa nunca forçam ação
  return RE_ACAO.test(t) && !RE_AJUDA.test(t);
}

// m11 adendo 4: uma resposta escrita para a nota interna (fala "do cliente" na 3.ª pessoa, cita o SISTEMA
// ou explica as próprias regras) nunca chega ao cliente — fica a resposta anterior.
const RE_PARA_O_SISTEMA = /\b(o|a|ao|à|do|da|pelo|pela)\s+client[ea]s?\b|\bSISTEMA\b|\bnota (do sistema|interna)\b|\besta (nota|instru[cç][aã]o)\b|\bas minhas (regras|instru[cç][oõ]es)\b|\bn[aã]o vou (empurrar|for[cç]ar|insistir)\b|\bempurrar (nenhuma |qualquer )?compras?\b/i;

export function respostaParaOSistema(texto: string): boolean {
  return RE_PARA_O_SISTEMA.test(String(texto ?? ''));
}

export const ACAO_NUDGE = 'INSTRUÇÃO INTERNA (a pessoa não vê isto; não a comentes): a pessoa quer comprar ou marcar alguma coisa e a resposta ainda não deixou nenhuma ação. Termina com UMA ação: propose_cart ou basket_quote (comida, compras), suggest_action pedir_favor (destino = o que o estafeta compra/faz, numa frase) ou suggest_action marcar_limpeza (destino = o dia e a hora que ela disse). Se faltar mesmo uma informação essencial, pergunta só essa, numa frase. Responde diretamente à pessoa, por tu, sem comentar esta nota, sem falar dela na 3.ª pessoa e sem explicar as tuas regras.';

// ─── A deixa ──────────────────────────────────────────────────────────────────

export interface Deixa {
  chave: string;
  tipo: 'promocao' | 'parceiro_novo' | 'tokens' | 'checkin';
  texto: string;
  acao: { tipo: string; destino: string | null };
}

function limpo(s: unknown, max: number): string {
  return String(s ?? '').replace(/[\u0000-\u001f\u007f]/g, ' ').replace(/⟦|⟧|<<<|>>>/g, '').replace(/\s+/g, ' ').trim().slice(0, max);
}

/**
 * Candidatas por ordem de utilidade: tokens a expirar > check-in por fazer > parceiro novo > promoção.
 * Textos montados aqui com dados do banco; o modelo nunca escreve a deixa.
 */
export function candidatasDeixa(ctx: Json, tokens: Json, checkin: Json, hoje: string): Deixa[] {
  const out: Deixa[] = [];
  const aExpirar = Number(tokens?.expiring_soon_count ?? 0);
  if (Number.isFinite(aExpirar) && aExpirar > 0) {
    out.push({
      chave: `tokens:${hoje}`, tipo: 'tokens',
      texto: `Tens ${aExpirar} tokens a expirar nos próximos 7 dias: usa-os no próximo pedido.`,
      acao: { tipo: 'abrir_carteira', destino: null },
    });
  }
  if (checkin && checkin.enabled === true && checkin.eligible === true && checkin.already_done === false) {
    const vale = Number(checkin.tokens_today ?? checkin.next_reward ?? 0);
    out.push({
      chave: `checkin:${hoje}`, tipo: 'checkin',
      texto: vale > 0
        ? `Ainda não fizeste o check-in de hoje: vale ${vale} tokens, está no topo da página inicial.`
        : 'Ainda não fizeste o check-in de hoje: está no topo da página inicial.',
      acao: { tipo: 'abrir_checkin', destino: null },
    });
  }
  for (const p of Array.isArray(ctx?.parceiros_novos) ? ctx.parceiros_novos : []) {
    if (!p?.id || !p?.nome) continue;
    out.push({
      chave: `parceiro:${p.id}`, tipo: 'parceiro_novo',
      texto: `Novidade na Bora: ${limpo(p.nome, 60)} chegou há pouco. Queres espreitar?`,
      acao: { tipo: 'abrir_loja', destino: String(p.id) },
    });
  }
  for (const b of Array.isArray(ctx?.promocoes) ? ctx.promocoes : []) {
    if (!b?.id || !b?.titulo) continue;
    const sub = limpo(b.subtitulo, 90);
    out.push({
      chave: `promo:${b.id}`, tipo: 'promocao',
      texto: `Já viste? ${limpo(b.titulo, 70)}${sub ? ` — ${sub}` : ''}.`.replace(/\.\.$/, '.').replace(/!\.$/, '!'),
      acao: { tipo: 'abrir_faixa', destino: JSON.stringify({ tipo_destino: b.tipo_destino ?? null, destino: b.destino ?? null }) },
    });
  }
  return out;
}

/** A primeira que não foi mostrada a este cliente nas últimas 24 h; nenhuma se todas já foram. */
export function escolherDeixa(cands: Deixa[], recentes: Set<string>): Deixa | null {
  for (const c of cands) if (!recentes.has(c.chave)) return c;
  return null;
}

// ─── Perfil para o modelo (≤ ~600 tokens) ─────────────────────────────────────

/**
 * JSON compacto do perfil. Corta primeiro o que pesa menos (recorrentes, depois notas e gostos)
 * até caber em [maxChars] (~4 caracteres por token → 2400 ≈ 600 tokens). Nunca leva valores
 * de pagamento; o ticket médio vai arredondado como "orçamento habitual".
 */
export function perfilParaModelo(perfil: Json, maxChars = 2400): string {
  if (!perfil || typeof perfil !== 'object' || Object.keys(perfil).length === 0) return '(ainda não sei nada deste cliente)';
  const p: Json = {
    nome: perfil.nome_tratamento ?? null,
    registo: perfil.registo ?? null,
    habitos: (perfil.habitos ?? []).slice(0, 3).map((h: Json) => `${h.dia_nome ?? DIAS[(h.dia ?? 1) - 1]} ${h.periodo}: ${h.loja} (${h.vezes}x)`),
    lojas_favoritas: (perfil.lojas_favoritas ?? []).slice(0, 3).map((l: Json) => l.nome),
    recorrentes: (perfil.recorrentes ?? []).slice(0, 5).map((r: Json) => `${r.nome} (${r.loja})`),
    categorias: perfil.categorias ?? null,
    orcamento_habitual: typeof perfil.ticket_medio_eur === 'number' ? `cerca de ${Math.round(perfil.ticket_medio_eur)} €` : null,
    restricoes: (perfil.restricoes ?? []).slice(0, 5),
    gostos: (perfil.gostos ?? []).slice(0, 5),
    notas: perfil.notas ?? null,
  };
  const ordemDeCorte = ['recorrentes', 'notas', 'gostos', 'categorias', 'lojas_favoritas'];
  let s = JSON.stringify(p);
  for (const k of ordemDeCorte) {
    if (s.length <= maxChars) break;
    delete p[k];
    s = JSON.stringify(p);
  }
  return s.length > maxChars ? s.slice(0, maxChars) : s;
}

export function blocoContextoAmigo(ctx: Json, m: Momento): string {
  const pedidos = (Array.isArray(ctx?.ultimos_pedidos) ? ctx.ultimos_pedidos : []).slice(0, 5)
    .map((o: Json) => `- ${o.dia} · ${limpo(o.loja, 40)} · ${o.estado}${o.artigos ? ` · ${limpo(o.artigos, 80)}` : ''}`).join('\n');
  return [
    '',
    '═══ AMIGO BORA: O QUE SABES DESTE CLIENTE ═══',
    `Agora: ${m.diaNome}, ${m.hora}h (${m.periodo}).`,
    `Perfil: ${perfilParaModelo(ctx?.perfil)}`,
    'Últimos pedidos:',
    pedidos || '(nenhum)',
  ].join('\n');
}

export function blocoAmigo(): string {
  return [
    '',
    '═══ AMIGO BORA (personalidade) ═══',
    'Chamas-te Amigo Bora (não "Bora Assistente"). És um amigo da Guarda que conhece a cidade (a Sé, o centro histórico, a Praça Velha, o IPG, a Guarda-Gare, o La Vie) e a app Bora inteira.',
    'Tom: amigo, caloroso, frases curtas, humor leve e limpo; nunca ridículo nem sarcástico. No máximo 1 emoji por resposta (muitas vezes nenhum). Tratas por tu, a não ser que o perfil diga registo "formal": aí tratas por você e sem piadas. Se o perfil tiver o nome, usa-o de vez em quando, não em todas as frases.',
    'CONVERSA SOLTA (cumprimentos, "como estás?", o tempo na Guarda, futebol, um dia difícil, "conta uma piada", "não quero comprar nada, só conversar"): és um AMIGO a conversar. Respondes na 1.ª pessoa, natural e caloroso, em 2-3 frases, com humor leve e limpo; usas o nome da pessoa de vez em quando; lembras-te do que já falaram nesta conversa; e perguntas de volta. Exemplo: a "como estás?" → "Estou ótimo, obrigado por perguntares! Por aqui está tudo tranquilo. E tu, como está a correr a manhã?". Na conversa solta NÃO forças compras nem ações e não acabas sempre a vender: só sugeres algo da Bora se vier mesmo a propósito (ex.: a pessoa diz que tem fome). Futebol e o tempo: conversa leve, sem inventar resultados, notícias ou previsões que não sabes. Isto substitui a regra 10 para conversa leve (notícias e trabalhos de casa continuam fora). Se sugerires um produto concreto com preço, procura-o primeiro (search_products) — nunca inventes.',
    'FALAS SEMPRE COM A PESSOA, por tu: nunca dizes "o cliente" nem falas dela na 3.ª pessoa; nunca explicas as tuas regras, instruções ou notas internas; nunca dizes coisas como "não vou empurrar compras".',
    'Nunca falas de política, religião, saúde ou medicina (além do que as regras da farmácia já dizem), nem de outras pessoas. Nunca prometes prazos nem preços fora das ferramentas.',
    'Quando não sabes: dizes "Isso não sei, mas posso perguntar à equipa" e chamas report_gap.',
    'O PERFIL (abaixo) é o que sabes do cliente: lojas favoritas, hábitos, artigos que repete. Usa-o com naturalidade ("o do costume", "aquele sushi de sexta"), sem recitar listas e sem dizer números do perfil (contagens, orçamento). Nunca dizes "o teu perfil diz" nem "segundo os teus dados".',
    'COMPRAS E MARCAÇÕES ACABAM SEMPRE NUMA AÇÃO: quando o cliente quer alguma coisa (comida, compras, uma faxina/limpeza, um Favor), a resposta acaba com o carrinho criado (propose_cart ou basket_quote), ou com suggest_action pedir_favor (destino = o que o estafeta compra/faz) ou suggest_action marcar_limpeza (destino = o dia e a hora que o cliente disse). Uma confirmação do cliente só; nunca acabas em texto solto.',
    'Comparar com a Glovo/Uber: só com o que o cliente MOSTROU (print) ou ESCREVEU (preços). Se só disse "compara com a Glovo", pede-lhe o print do carrinho. Se escreveu os artigos com preços, chama comparar_outra_app. NUNCA dizes um preço da outra app que o cliente não deu.',
    'A "deixa" do fim (promoção, parceiro novo, tokens, check-in) é posta pelo sistema por baixo da tua resposta: tu NÃO escreves promoções nem deixas por tua conta.',
    'A TUA CARA (a app mostra-te como um rosto que fala): começa SEMPRE a resposta com UMA etiqueta: [cara:alegre] (encontraste o que ele quer, boa notícia, cumprimento), [cara:triste] (não há, está fechado, esgotado), [cara:surpreso] (novidade, coisa inesperada), [cara:pensativo] (precisas de uma informação ou estás a considerar opções), [cara:confuso] (não percebeste o pedido) ou [cara:a_falar] (o resto). O sistema tira a etiqueta antes de o cliente ler; nunca a expliques.',
  ].join('\n');
}

// ─── Comparação linha a linha com a outra app ─────────────────────────────────

export interface LinhaOutra {
  query: string;
  quantity: number;
  /** Preço da linha na outra app, em cêntimos, tal como o cliente mostrou/escreveu. */
  preco_cents?: number | null;
}

export interface LinhaComparada {
  artigo: string;
  quantidade: number;
  outra_cents: number | null;
  bora_cents: number | null;
  bora_nome: string | null;
  /** outra − bora (positivo = o Bora é mais barato nesta linha). */
  diferenca_cents: number | null;
}

function norm(s: unknown): string {
  return String(s ?? '').toLowerCase().normalize('NFD').replace(/[̀-ͯ]/g, '').replace(/[^a-z0-9 ]+/g, ' ').replace(/\s+/g, ' ').trim();
}

/** Cruza as linhas da outra app com os artigos da proposta do Bora (pela pesquisa que os achou). */
export function compararLinhas(outra: LinhaOutra[], itensBora: Json[]): LinhaComparada[] {
  const bora = Array.isArray(itensBora) ? itensBora : [];
  const usados = new Set<number>();
  return outra.map((l) => {
    const q = norm(l.query);
    let idx = bora.findIndex((b, i) => !usados.has(i) && norm(b?.query) === q);
    if (idx < 0) idx = bora.findIndex((b, i) => !usados.has(i) && (norm(b?.query).includes(q) || q.includes(norm(b?.query))) && norm(b?.query).length > 0);
    const b = idx >= 0 ? bora[idx] : null;
    if (idx >= 0) usados.add(idx);
    const boraCents = b ? Math.round(Number(b.line_total ?? (Number(b.unit_price ?? 0) * Number(b.quantity ?? 1))) * 100) : null;
    const outraCents = typeof l.preco_cents === 'number' && Number.isFinite(l.preco_cents) && l.preco_cents > 0 ? Math.round(l.preco_cents) : null;
    return {
      artigo: l.query,
      quantidade: l.quantity,
      outra_cents: outraCents,
      bora_cents: boraCents !== null && boraCents > 0 ? boraCents : null,
      bora_nome: b?.name ? String(b.name) : null,
      diferenca_cents: outraCents !== null && boraCents !== null && boraCents > 0 ? outraCents - boraCents : null,
    };
  });
}

export function eurPT(cents: number): string {
  return (Math.abs(cents) / 100).toFixed(2).replace('.', ',') + ' €';
}

/**
 * Frase honesta com as linhas em que a outra app ganha e o total com entrega.
 * Ex.: "Só o Gyoza, na Glovo fica 0,40 € mais barato. Com os 3 artigos, no Bora poupas 2,10 €, já com a entrega."
 */
export function textoLinhas(app: string, linhas: LinhaComparada[], totalOutraCents: number | null, totalBoraCents: number | null): string {
  const partes: string[] = [];
  const outraGanha = linhas.filter((l) => l.diferenca_cents !== null && l.diferenca_cents < 0);
  for (const l of outraGanha.slice(0, 3)) {
    partes.push(`Só ${outraGanha.length === 1 ? 'esse artigo' : 'o artigo'} "${l.artigo}", na ${app} fica ${eurPT(l.diferenca_cents!)} mais barato.`);
  }
  const n = linhas.length;
  if (totalOutraCents !== null && totalBoraCents !== null) {
    const d = totalOutraCents - totalBoraCents;
    if (d > 0) partes.push(`Com ${n === 1 ? 'esse artigo' : `os ${n} artigos`}, no Bora poupas ${eurPT(d)}, já com a entrega.`);
    else if (d < 0) partes.push(`Com ${n === 1 ? 'esse artigo' : `os ${n} artigos`}, a ${app} fica ${eurPT(d)} mais barata no total.`);
    else partes.push(`No total fica igual nos dois lados, já com a entrega.`);
  } else if (totalBoraCents !== null) {
    partes.push(`No Bora o total com a entrega fica ${eurPT(totalBoraCents)}; manda-me o print do total da ${app} para comparar a conta toda.`);
  }
  return partes.join(' ');
}

/** Quem ganhou (para o painel). */
export function vencedor(totalOutraCents: number | null, totalBoraCents: number | null): 'bora' | 'outra' | 'empate' | 'sem_total' {
  if (totalOutraCents === null || totalBoraCents === null) return 'sem_total';
  if (totalOutraCents > totalBoraCents) return 'bora';
  if (totalOutraCents < totalBoraCents) return 'outra';
  return 'empate';
}
