// amigo-voz/logica.ts — a decisão da voz do servidor do Amigo (pendências 09/11/2026, bloco I).
//
// Tudo o que decide está aqui, com as dependências injetadas (base, cache, Google), para os
// testes Deno provarem sem rede: desligado, sem sessão, cache, sem chave, teto, erro da Google.
//
// Regra de ouro: qualquer "não" responde 200 com { ok: false, usar_aparelho: true, motivo } —
// a app volta à voz do aparelho (ou à legenda) sem mostrar erro. Só a falta de sessão é 401.
// A voz é SEMPRE pt-PT (nunca do Brasil); a escolha é do painel, não do cliente.

export const BUCKET = 'amigo-voz';
// Vozes pt-PT na lista da Google a 09/11/2026: Standard-E (feminina), Standard-F, Wavenet-E (feminina), Wavenet-F.
export const VOZ_PADRAO = 'pt-PT-Standard-E';
export const MAX_CARACTERES = 800;
export const GOOGLE_URL = 'https://texttospeech.googleapis.com/v1/text:synthesize';
export const TEMPO_GOOGLE_MS = 8000;

export type Motivo =
  | 'sem_sessao'
  | 'texto_invalido'
  | 'desligado'
  | 'sem_chave'
  | 'teto'
  | 'limite_utilizador'
  | 'erro_google'
  | 'erro_base'
  | 'invalido';

export interface Definicoes {
  ativo: boolean;
  voz: string;
}

export interface PedidoGoogle {
  input: { text: string };
  voice: { languageCode: 'pt-PT'; name: string };
  audioConfig: { audioEncoding: 'MP3'; speakingRate: number };
}

export type TipoContagem = 'cache' | 'erro' | 'sem_chave';

export interface Dependencias {
  /** id do utilizador com sessão (confirmado no Auth) ou null. */
  utilizador(): Promise<string | null>;
  definicoes(): Promise<Definicoes>;
  chaveGoogle(): string | null;
  cacheLer(caminho: string): Promise<Uint8Array | null>;
  cacheGravar(caminho: string, mp3: Uint8Array): Promise<void>;
  reservar(userId: string, caracteres: number): Promise<{ ok: boolean; motivo?: string }>;
  contar(userId: string, caracteres: number, tipo: TipoContagem): Promise<void>;
  /** Gera o MP3 na Google; lança erro se falhar. */
  google(pedido: PedidoGoogle, chave: string): Promise<Uint8Array>;
  registo?(msg: string): void;
}

export interface Resposta {
  estado: number;
  corpo: Record<string, unknown>;
}

/** Espaços seguidos viram um; corta as pontas. */
export function normalizarTexto(t: unknown): string {
  if (typeof t !== 'string') return '';
  return t.replace(/\s+/g, ' ').trim();
}

/** Caracteres como a Google conta (pontos de código, não bytes). */
export function contarCaracteres(t: string): number {
  return [...t].length;
}

/** Só vozes pt-PT; outra coisa (incluindo pt-BR) → a voz padrão. */
export function vozSegura(v: unknown): string {
  const s = typeof v === 'string' ? v.trim() : '';
  return /^pt-PT-[A-Za-z0-9]+-[A-Z]$/.test(s) ? s : VOZ_PADRAO;
}

/** Velocidade da app (0,5–2) arredondada a 0,05 para a cache não se partir. */
export function velocidadeSegura(v: unknown): number {
  const n = typeof v === 'number' ? v : Number(v);
  if (!Number.isFinite(n)) return 1;
  const c = Math.min(2, Math.max(0.5, n));
  return Math.round(c * 20) / 20;
}

export function pedidoGoogle(texto: string, voz: string, velocidade: number): PedidoGoogle {
  return {
    input: { text: texto },
    voice: { languageCode: 'pt-PT', name: vozSegura(voz) },
    audioConfig: { audioEncoding: 'MP3', speakingRate: velocidadeSegura(velocidade) },
  };
}

/** Caminho na cache: v1/<2 primeiros>/<sha256 de voz|velocidade|texto>.mp3 */
export async function caminhoCache(texto: string, voz: string, velocidade: number): Promise<string> {
  const dados = new TextEncoder().encode(`${vozSegura(voz)}|${velocidadeSegura(velocidade).toFixed(2)}|${texto}`);
  const h = new Uint8Array(await crypto.subtle.digest('SHA-256', dados));
  const hex = [...h].map((b) => b.toString(16).padStart(2, '0')).join('');
  return `v1/${hex.slice(0, 2)}/${hex}.mp3`;
}

export function paraBase64(b: Uint8Array): string {
  let s = '';
  const passo = 0x8000;
  for (let i = 0; i < b.length; i += passo) {
    s += String.fromCharCode(...b.subarray(i, i + passo));
  }
  return btoa(s);
}

export function deBase64(s: string): Uint8Array {
  const bin = atob(s);
  const out = new Uint8Array(bin.length);
  for (let i = 0; i < bin.length; i++) out[i] = bin.charCodeAt(i);
  return out;
}

/** Lê as linhas de platform_settings (true/"true"; texto da voz). Sem linha = desligado. */
export function definicoesDe(linhas: Array<{ key: string; value: unknown }> | null | undefined): Definicoes {
  const m = new Map((linhas ?? []).map((l) => [l.key, l.value]));
  const a = m.get('amigo_voz_servidor_ativo');
  const ativo = a === true || (typeof a === 'string' && a.trim().toLowerCase() === 'true');
  return { ativo, voz: vozSegura(m.get('amigo_voz_nome')) };
}

export function usarAparelho(motivo: Motivo, estado = 200): Resposta {
  return { estado, corpo: { ok: false, usar_aparelho: true, motivo } };
}

function motivoDaReserva(m: unknown): Motivo {
  return m === 'teto' || m === 'limite_utilizador' || m === 'desligado' || m === 'invalido' ? m : 'teto';
}

/** O pedido inteiro: sessão → texto → interruptor → cache → chave → teto → Google → cache. */
export async function tratar(corpo: unknown, d: Dependencias): Promise<Resposta> {
  const log = (m: string) => d.registo?.(m);
  const userId = await d.utilizador().catch(() => null);
  if (!userId) return usarAparelho('sem_sessao', 401);

  const c = (corpo && typeof corpo === 'object') ? corpo as Record<string, unknown> : {};
  const texto = normalizarTexto(c.texto);
  const n = contarCaracteres(texto);
  if (n === 0 || n > MAX_CARACTERES) return usarAparelho('texto_invalido');

  let defs: Definicoes;
  try {
    defs = await d.definicoes();
  } catch (e) {
    log(`definicoes: ${e}`);
    return usarAparelho('erro_base');
  }
  if (!defs.ativo) return usarAparelho('desligado');

  const voz = vozSegura(defs.voz);
  const velocidade = velocidadeSegura(c.velocidade ?? 1);
  const caminho = await caminhoCache(texto, voz, velocidade);

  // 1) cache: frases repetidas não gastam caracteres da Google
  let guardado: Uint8Array | null = null;
  try {
    guardado = await d.cacheLer(caminho);
  } catch (e) {
    log(`cache ler: ${e}`);
  }
  if (guardado && guardado.length > 0) {
    await d.contar(userId, n, 'cache').catch((e) => log(`contar cache: ${e}`));
    return {
      estado: 200,
      corpo: { ok: true, audio_base64: paraBase64(guardado), formato: 'mp3', origem: 'cache', voz, caracteres: n },
    };
  }

  // 2) sem chave: nada a gerar
  const chave = d.chaveGoogle();
  if (!chave) {
    await d.contar(userId, n, 'sem_chave').catch((e) => log(`contar sem_chave: ${e}`));
    return usarAparelho('sem_chave');
  }

  // 3) teto do dia e limite do cliente (reserva atómica na base; sem base não se gasta)
  let reserva: { ok: boolean; motivo?: string };
  try {
    reserva = await d.reservar(userId, n);
  } catch (e) {
    log(`reservar: ${e}`);
    return usarAparelho('erro_base');
  }
  if (!reserva?.ok) return usarAparelho(motivoDaReserva(reserva?.motivo));

  // 4) Google
  let mp3: Uint8Array;
  try {
    mp3 = await d.google(pedidoGoogle(texto, voz, velocidade), chave);
    if (!mp3 || mp3.length === 0) throw new Error('áudio vazio');
  } catch (e) {
    log(`google: ${e}`);
    await d.contar(userId, n, 'erro').catch((x) => log(`contar erro: ${x}`));
    return usarAparelho('erro_google');
  }

  // 5) guarda na cache (se falhar, a fala segue na mesma)
  await d.cacheGravar(caminho, mp3).catch((e) => log(`cache gravar: ${e}`));
  return {
    estado: 200,
    corpo: { ok: true, audio_base64: paraBase64(mp3), formato: 'mp3', origem: 'google', voz, caracteres: n },
  };
}

/** Chamada REST à Google (text:synthesize), com a chave no cabeçalho (não no endereço). */
export async function chamarGoogle(
  pedido: PedidoGoogle,
  chave: string,
  buscar: typeof fetch = fetch,
  tempoMs = TEMPO_GOOGLE_MS,
): Promise<Uint8Array> {
  const ctl = new AbortController();
  const t = setTimeout(() => ctl.abort(), tempoMs);
  try {
    const r = await buscar(GOOGLE_URL, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json; charset=utf-8', 'X-Goog-Api-Key': chave },
      body: JSON.stringify(pedido),
      signal: ctl.signal,
    });
    if (!r.ok) {
      const txt = (await r.text().catch(() => '')).slice(0, 300);
      throw new Error(`google ${r.status}: ${txt}`);
    }
    const j = await r.json() as { audioContent?: string };
    if (!j?.audioContent) throw new Error('google sem audioContent');
    return deBase64(j.audioContent);
  } finally {
    clearTimeout(t);
  }
}
