// Amigo Bora — lojas abertas, parceiro primeiro e o "quero" (11/11/2026, missão fechar-tudo-2026-11-11,
// bloco 2). Funções puras (sem rede), testadas em sugestao_test.ts.
//
// Porquê (conversas de 10/11): "quais restaurantes estão abertos?" → "não tenho a lista"; açaí → açaí
// congelado do Continente com o Goola (parceiro, açaí) aberto; "então eu quero" logo a seguir a uma
// sugestão → "não consegui montar o carrinho". Agora:
//   · lojas_abertas: quem está aberto AGORA (horário real, hora de Lisboa), parceiros primeiro, com
//     morada e link do Google Maps;
//   · um produto que exista num parceiro aberto vem antes do supermercado;
//   · "quero", "sim", "pode ser"… logo depois de uma sugestão → o carrinho é montado em CÓDIGO a partir
//     da última sugestão guardada na conversa (nunca pelo modelo).

// deno-lint-ignore no-explicit-any
type Json = any;

function semAcentos(s: unknown): string {
  return String(s ?? '').toLowerCase().normalize('NFD').replace(/[̀-ͯ]/g, '');
}

function palavras(s: unknown): string[] {
  return semAcentos(s).replace(/[^a-z0-9 ]+/g, ' ').split(/\s+/).filter(Boolean);
}

// ─── "quero" / "sim" / "pode ser" ─────────────────────────────────────────────

// Pelo menos uma destas tem de lá estar (o "sim" da compra).
const AFIRMA = new Set([
  'quero', 'queria', 'quer', 'sim', 'pode', 'podes', 'ok', 'okay', 'bora', 'vamos', 'venha', 'manda', 'mandar',
  'traz', 'traga', 'perfeito', 'combinado', 'claro', 'beleza', 'siga', 'poe', 'monta',
  'montar', 'enche', 'encher', 'adiciona', 'adicionar', 'pede', 'pedir', 'compra', 'comprar', 'aceito',
  'isso', 'esse', 'essa', 'este', 'esta', 'yes', 'avanca', 'serve', 'gostei', 'show', 'otimo', 'boa',
]);
// Palavras que podem acompanhar o "sim" sem mudar o pedido ("por" sozinho não afirma: "por que?").
const ACOMPANHA = new Set([
  'entao', 'eu', 'ser', 'mesmo', 'mesma', 'por', 'favor', 'pf', 'pfv', 'pff', 'sff', 'se', 'faz', 'faca', 'fazes',
  'la', 'ai', 'um', 'uma', 'o', 'a', 'os', 'as', 'dele', 'dela', 'desse', 'dessa', 'deste', 'desta', 'disso',
  'pra', 'para', 'mim', 'me', 'agora', 'ja', 'tambem', 'obrigado', 'obrigada', 'valeu', 'ta', 'tá', 'bem', 'bom',
  'carrinho', 'no', 'na', 'ao', 'vir', 'isso', 'aquilo', 'aquele', 'aquela', 'certo', 'exato', 'exatamente',
  'claro', 'que', 'sim', 'yes', 'please', 'de', 'do', 'da', 'e', 'muito', 'tudo', 'vai', 'pode', 'quero',
]);
const NEGA = new Set(['nao', 'nunca', 'nem', 'nada', 'mas', 'sem', 'outro', 'outra', 'outros', 'outras', 'mais', 'menos', 'trocar', 'troca', 'muda', 'mudar']);
const NUMEROS: Record<string, number> = { dois: 2, duas: 2, tres: 3, quatro: 4, cinco: 5, seis: 6, sete: 7, oito: 8, nove: 9, dez: 10 };

/**
 * A mensagem é só um "sim" à última sugestão ("quero", "então eu quero", "sim, pode ser", "pode mandar",
 * "quero 2"). Nunca com "não"/"mas"/"outro" nem com um artigo novo ("quero uma coca-cola" não é).
 */
export function eConfirmacaoDeCompra(msg: string): { confirma: boolean; quantidade: number | null } {
  const nao = { confirma: false, quantidade: null };
  const t = String(msg ?? '').trim();
  if (!t || t.length > 60) return nao;
  const ps = palavras(t);
  if (ps.length === 0 || ps.length > 8) return nao;
  let quantidade: number | null = null;
  let afirma = false;
  for (const p of ps) {
    if (NEGA.has(p)) return nao;
    if (/^\d+$/.test(p)) {
      const n = Number(p);
      if (n < 1 || n > 20 || quantidade !== null) return nao;
      quantidade = n;
      continue;
    }
    if (NUMEROS[p]) {
      if (quantidade !== null) return nao;
      quantidade = NUMEROS[p];
      continue;
    }
    if (AFIRMA.has(p)) { afirma = true; continue; }
    if (ACOMPANHA.has(p)) continue;
    return nao; // palavra que muda o pedido (um artigo, uma pergunta…)
  }
  return afirma ? { confirma: true, quantidade } : nao;
}

const RE_GUARDAR = /\bguard(e|ar|o|a)\b|\bposso guardar\b/;
// A pergunta é sobre ESTE carrinho/artigo ("queres que monte o carrinho?", "queres este?").
const RE_PERGUNTA_CARRINHO = /carrinho|encomend|\bmont|\bponh|\blev(o|ar)\b|\bpeco\b|\bpedir\b|\bconfirm|\bquer(es|e)?\s+(este|esse|essa|esta|isso|isto)\b/;
// …ou é sobre OUTRA coisa ("queres que veja outras?", "preparo-te um Favor?", "marco a limpeza?").
const RE_PERGUNTA_OUTRA = /favor|limpeza|faxina|lavagem|reserv|agend|marc(o|ar)|\boutr[oa]s?\b|\balgum[as]?\b|\bdiferente|\bveja\b|\bprocur|\bmais barat|\bmenu\b|\bbebida|\bbatata|\bjunt(o|ar)\b/;

/**
 * O "sim" que vem a seguir a esta resposta é para o carrinho sugerido? Não, se a resposta pediu para guardar
 * uma preferência de saúde, ou se acaba com uma pergunta sobre OUTRA coisa ("queres que veja outras?",
 * "preparo-te um Favor?"). Sem pergunta, ou com a pergunta sobre este carrinho, sim.
 */
export function confirmacaoEParaOCarrinho(textoAnterior: string): boolean {
  const t = semAcentos(textoAnterior);
  if (RE_GUARDAR.test(t)) return false;
  const perguntas = t.split(/(?<=[.!?\n])\s+/).filter((f) => f.includes('?'));
  if (perguntas.length === 0) return true;
  const ultima = perguntas[perguntas.length - 1];
  return RE_PERGUNTA_CARRINHO.test(ultima) && !RE_PERGUNTA_OUTRA.test(ultima);
}

// ─── A última sugestão (guardada na conversa) ─────────────────────────────────

export interface ItemSugerido { product_id: string; quantity: number; nome?: string | null }
export interface Sugestao {
  restaurant_id: string;
  loja: string;
  itens: ItemSugerido[];
  /** carrinho = veio de uma proposta; produto = um produto que o modelo sugeriu sem carrinho. */
  origem: 'carrinho' | 'produto';
}

export function sugestaoValida(s: Json): s is Sugestao {
  return Boolean(s && typeof s === 'object' && typeof s.restaurant_id === 'string' && s.restaurant_id &&
    Array.isArray(s.itens) && s.itens.length > 0 && s.itens.length <= 40 &&
    s.itens.every((i: Json) => typeof i?.product_id === 'string' && i.product_id.length > 0));
}

/** De uma proposta de carrinho (assistant_propose_cart / basket_quote) para a sugestão a repetir. */
export function sugestaoDaProposta(p: Json): Sugestao | null {
  const itens: ItemSugerido[] = (Array.isArray(p?.items) ? p.items : [])
    .filter((i: Json) => typeof i?.product_id === 'string' && i.product_id)
    .map((i: Json) => ({
      product_id: String(i.product_id),
      quantity: Math.max(1, Math.min(50, Math.round(Number(i.quantity ?? 1)) || 1)),
      nome: typeof i.name === 'string' ? i.name : null,
    }));
  const rid = typeof p?.restaurant_id === 'string' ? p.restaurant_id : '';
  if (!rid || itens.length === 0) return null;
  return { restaurant_id: rid, loja: String(p.restaurant_name ?? p.loja ?? ''), itens, origem: 'carrinho' };
}

export interface ProdutoVisto {
  product_id: string;
  nome: string;
  loja: string;
  restaurant_id: string;
  parceiro?: boolean;
  aberta?: boolean | null;
}

const VAZIAS = new Set(['de', 'do', 'da', 'dos', 'das', 'com', 'sem', 'e', 'o', 'a', 'em', 'para', 'um', 'uma', 'ml', 'gr', 'kg', 'g', 'l', 'un']);

/** Quanto do nome do produto aparece no texto (0 a 1), pelas palavras com 3+ letras. */
function presencaNoTexto(nome: string, textoNorm: Set<string>): number {
  const ps = palavras(nome).filter((p) => p.length >= 3 && !VAZIAS.has(p) && !/^\d+$/.test(p));
  if (ps.length === 0) return 0;
  return ps.filter((p) => textoNorm.has(p)).length / ps.length;
}

/**
 * A sugestão desta resposta, para o "quero" da próxima mensagem:
 *  · 1 carrinho → esse; vários do cesto (basket_quote) → o primeiro (o mais barato com tudo);
 *    vários carrinhos soltos → nenhuma (a pessoa tem de escolher);
 *  · sem carrinho → o produto (das pesquisas desta volta) que o texto nomeia; parceiro aberto ganha empates.
 */
export function escolherSugestao(o: { propostas: Json[]; veioDoCesto: boolean; produtos: ProdutoVisto[]; texto: string }): Sugestao | null {
  const props = Array.isArray(o.propostas) ? o.propostas : [];
  if (props.length === 1) return sugestaoDaProposta(props[0]);
  if (props.length > 1) {
    if (!o.veioDoCesto) return null;
    const completas = props.filter((p) => Number(p?.coverage_pct ?? 100) >= 100);
    return sugestaoDaProposta((completas.length ? completas : props)[0]);
  }
  const texto = new Set(palavras(o.texto));
  if (texto.size === 0) return null;
  let melhor: { p: ProdutoVisto; s: number } | null = null;
  for (const p of o.produtos ?? []) {
    if (!p?.product_id || !p?.restaurant_id) continue;
    const pres = presencaNoTexto(p.nome, texto);
    if (pres < 0.6) continue;
    const s = pres + (presencaNoTexto(p.loja, texto) >= 0.5 ? 0.3 : 0) + (p.parceiro && p.aberta !== false ? 0.05 : 0);
    if (!melhor || s > melhor.s) melhor = { p, s };
  }
  if (!melhor) return null;
  return {
    restaurant_id: melhor.p.restaurant_id, loja: melhor.p.loja,
    itens: [{ product_id: melhor.p.product_id, quantity: 1, nome: melhor.p.nome }], origem: 'produto',
  };
}

/** A sugestão com a quantidade que a pessoa disse ("quero 2") — só quando há um artigo. */
export function comQuantidade(s: Sugestao, quantidade: number | null): Sugestao {
  if (!quantidade || s.itens.length !== 1) return s;
  return { ...s, itens: [{ ...s.itens[0], quantity: Math.max(1, Math.min(50, quantidade)) }] };
}

/** O texto fixo da resposta ao "quero" (nunca escreve preços: o cartão mostra o total). */
export function textoCarrinhoMontado(s: Sugestao, aberta: boolean | null | undefined): string {
  const nomes = s.itens.map((i) => i.nome).filter((n): n is string => Boolean(n && n.trim()));
  const oQue = s.itens.length === 1 && nomes.length === 1
    ? `${s.itens[0].quantity > 1 ? `${s.itens[0].quantity}× ` : ''}${nomes[0]}`
    : (s.itens.length === 1 ? 'o artigo' : `os ${s.itens.length} artigos`);
  const loja = s.loja ? ` do ${s.loja}` : '';
  const fechada = aberta === false ? ' A loja está fechada agora: podes deixá-lo agendado para quando abrir.' : '';
  return `Pronto! Pus ${oQue}${loja} no carrinho.${fechada} Toca em "Encher o carrinho" para continuar.`;
}

// ─── Parceiro primeiro ────────────────────────────────────────────────────────

/**
 * Os produtos de parceiros ABERTOS (assistant_produtos_parceiro_aberto) vêm primeiro; depois a pesquisa
 * de sempre, sem repetidos. Na pesquisa de sempre, os produtos das mesmas lojas parceiras abertas sobem.
 */
export function parceiroPrimeiro<T extends { product_id: string; restaurant_id?: string }>(parceiros: T[], busca: T[]): T[] {
  const vistos = new Set<string>();
  const lojasParceiras = new Set(parceiros.map((p) => p.restaurant_id).filter(Boolean));
  const out: T[] = [];
  const juntar = (p: T) => { if (p?.product_id && !vistos.has(p.product_id)) { vistos.add(p.product_id); out.push(p); } };
  parceiros.forEach(juntar);
  busca.filter((p) => p.restaurant_id && lojasParceiras.has(p.restaurant_id)).forEach(juntar);
  busca.forEach(juntar);
  return out;
}

// ─── Lojas abertas ────────────────────────────────────────────────────────────

export interface LojaAberta {
  id: string;
  nome: string;
  parceiro: boolean;
  categoria: string | null;
  servico: string | null;
  cozinha: string | null;
  morada: string | null;
  lat: number | null;
  lng: number | null;
  fecha_em_minutos: number | null;
}

export function lojaDe(j: Json): LojaAberta | null {
  if (!j || typeof j.id !== 'string' || typeof j.nome !== 'string') return null;
  const n = (x: unknown) => (typeof x === 'number' && Number.isFinite(x) ? x : (x === null || x === undefined || x === '' ? null : (Number.isFinite(Number(x)) ? Number(x) : null)));
  return {
    id: j.id, nome: j.nome, parceiro: j.parceiro === true,
    categoria: j.categoria ?? null, servico: j.servico ?? null, cozinha: j.cozinha ?? null, morada: j.morada ?? null,
    lat: n(j.lat), lng: n(j.lng), fecha_em_minutos: n(j.fecha_em_minutos),
  };
}

export function linkMaps(lat: number | null, lng: number | null): string | null {
  if (lat === null || lng === null || !Number.isFinite(lat) || !Number.isFinite(lng)) return null;
  return `https://www.google.com/maps/search/?api=1&query=${lat.toFixed(6)},${lng.toFixed(6)}`;
}

export function distanciaKm(a: { lat: number; lng: number }, b: { lat: number; lng: number }): number {
  const r = (x: number) => (x * Math.PI) / 180;
  const dLat = r(b.lat - a.lat);
  const dLng = r(b.lng - a.lng);
  const h = Math.sin(dLat / 2) ** 2 + Math.cos(r(a.lat)) * Math.cos(r(b.lat)) * Math.sin(dLng / 2) ** 2;
  return 6371 * 2 * Math.asin(Math.min(1, Math.sqrt(h)));
}

export type TipoLoja = 'todas' | 'restaurantes' | 'mercados' | 'farmacias' | 'lojas';

export function tipoDe(x: unknown): TipoLoja {
  const t = semAcentos(x);
  if (/restaur|comida|comer|jantar|almoc/.test(t)) return 'restaurantes';
  if (/mercad|supermerc/.test(t)) return 'mercados';
  if (/farmac/.test(t)) return 'farmacias';
  if (/^loja/.test(t)) return 'lojas';
  return 'todas';
}

/** Filtra pelo tipo e pelo que a pessoa procura ("sushi", "açaí": nome ou cozinha). */
export function filtrarLojas(lojas: LojaAberta[], tipo: TipoLoja, procura?: string | null): LojaAberta[] {
  const ps = palavras(procura ?? '').filter((p) => p.length >= 3 && !VAZIAS.has(p));
  return lojas.filter((l) => {
    if (tipo === 'restaurantes' && l.servico !== 'restaurant') return false;
    if (tipo === 'mercados' && l.categoria !== 'supermarket') return false;
    if (tipo === 'farmacias' && l.categoria !== 'pharmacy') return false;
    if (tipo === 'lojas' && l.categoria !== 'store') return false;
    if (ps.length === 0) return true;
    const alvo = new Set(palavras(`${l.nome} ${l.cozinha ?? ''}`));
    return ps.some((p) => alvo.has(p) || alvo.has(p.replace(/s$/, '')) || [...alvo].some((a) => a.startsWith(p)));
  });
}

/** Parceiros primeiro; depois os mais perto da morada (se houver); depois por nome. */
export function ordenarLojas(lojas: LojaAberta[], perto?: { lat: number; lng: number } | null): Array<LojaAberta & { distancia_km: number | null }> {
  return lojas
    .map((l) => ({
      ...l,
      distancia_km: perto && l.lat !== null && l.lng !== null ? Math.round(distanciaKm(perto, { lat: l.lat, lng: l.lng }) * 10) / 10 : null,
    }))
    .sort((a, b) => {
      if (a.parceiro !== b.parceiro) return a.parceiro ? -1 : 1;
      if (a.distancia_km !== null && b.distancia_km !== null && a.distancia_km !== b.distancia_km) return a.distancia_km - b.distancia_km;
      return a.nome.localeCompare(b.nome, 'pt');
    });
}

/** Dia (0 = domingo), data e minutos do dia em Lisboa. */
export function agoraLisboa(d: Date): { dow: number; data: string; minutos: number } {
  const partes = new Intl.DateTimeFormat('en-GB', {
    timeZone: 'Europe/Lisbon', weekday: 'short', year: 'numeric', month: '2-digit', day: '2-digit',
    hour: '2-digit', minute: '2-digit', hourCycle: 'h23',
  }).formatToParts(d);
  const v = (t: string) => partes.find((p) => p.type === t)?.value ?? '';
  const dow = ['Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat'].indexOf(v('weekday'));
  return { dow: dow < 0 ? 0 : dow, data: `${v('year')}-${v('month')}-${v('day')}`, minutos: (Number(v('hour')) % 24) * 60 + Number(v('minute')) };
}

/** "HH:MM" de Lisboa daqui a N minutos (a hora a que a loja fecha). */
export function horaDaquiA(d: Date, minutos: number | null): string | null {
  if (minutos === null || !Number.isFinite(minutos) || minutos < 0) return null;
  const m = (agoraLisboa(d).minutos + Math.round(minutos)) % 1440;
  return `${String(Math.floor(m / 60)).padStart(2, '0')}:${String(m % 60).padStart(2, '0')}`;
}

function hhmm(x: unknown): number | null {
  const m = /^(\d{1,2}):(\d{2})/.exec(String(x ?? ''));
  if (!m) return null;
  const h = Number(m[1]);
  const mi = Number(m[2]);
  if (h > 24 || mi > 59) return null;
  return h * 60 + mi;
}

const DIAS_CHAVE = ['sun', 'mon', 'tue', 'wed', 'thu', 'fri', 'sat'];

/**
 * Aberta agora pelo horário guardado (business_hours), à hora de Lisboa — a MESMA regra do
 * is_partner_open do banco (dia especial > dia da semana; "closed"; fecho depois da meia-noite; pausa).
 * Só serve de reserva quando a função do banco não responde (sem as interrupções do painel).
 */
export function abertaPeloHorario(hours: Json, d: Date): { aberta: boolean; fecha_em_minutos: number | null } {
  if (!hours || typeof hours !== 'object' || Array.isArray(hours)) return { aberta: true, fecha_em_minutos: null };
  const agora = agoraLisboa(d);
  let dia: Json = null;
  if (Array.isArray(hours.special_dates)) dia = hours.special_dates.find((e: Json) => e?.date === agora.data) ?? null;
  if (!dia) dia = hours[DIAS_CHAVE[agora.dow]];
  if (!dia || typeof dia !== 'object' || dia.closed === true) return { aberta: false, fecha_em_minutos: null };
  const abre = hhmm(dia.open);
  const fecha = hhmm(dia.close);
  if (abre === null || fecha === null) return { aberta: true, fecha_em_minutos: null };
  const m = agora.minutos;
  let aberta: boolean;
  let falta: number | null = null;
  if (fecha <= abre) {
    aberta = m >= abre || m < fecha;
    if (aberta) falta = m >= abre ? (1440 - m) + fecha : fecha - m;
  } else {
    aberta = m >= abre && m < fecha;
    if (aberta) falta = fecha - m;
  }
  const ps = hhmm(dia.break_start);
  const pe = hhmm(dia.break_end);
  if (aberta && ps !== null && pe !== null && ps < pe) {
    if (m >= ps && m < pe) return { aberta: false, fecha_em_minutos: null };
    if (m < ps && (falta === null || ps - m < falta)) falta = ps - m;
  }
  return { aberta, fecha_em_minutos: aberta ? falta : null };
}
