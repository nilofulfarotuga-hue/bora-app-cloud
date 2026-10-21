// _shared/chaves.ts — as chaves da Supabase dentro das Edge Functions.
// Missão chave-nova-16-10 (16/10/2026). Ler docs/SEGURANCA-CHAVES.md antes de mexer.
//
// O que a plataforma injeta em cada função (medido a 16/10/2026 com a função chaves-diagnostico,
// confirmado na documentação "Environment variables"):
//   SUPABASE_SECRET_KEYS       JSON { "<nome>": "sb_secret_…" }        — chaves secretas NOVAS
//   SUPABASE_PUBLISHABLE_KEYS  JSON { "<nome>": "sb_publishable_…" }   — chaves publicáveis NOVAS
//   SUPABASE_SERVICE_ROLE_KEY  desde que as chaves novas existem, já traz a sb_secret "default"
//   SUPABASE_ANON_KEY          idem, já traz a sb_publishable "default"
//   (ou seja: as variáveis com nome antigo deixaram de ter os JWT legados; os JWT legados só
//   vivem no cofre do banco — vault.service_role_key / vault.dispatch_anon_jwt — até à troca.)
//
// Regras da casa:
//   • Cliente admin (salta RLS):          createClient(url, chaveSecreta())
//   • Cliente em nome do utilizador:      createClient(url, chavePublicavel(), { headers Authorization })
//   • Quem chama é o servidor?            await chamadaDoServidor(req)
//       1) aceita uma chave secreta nova no cabeçalho `apikey` ou em `Authorization: Bearer`
//          (o banco manda em Bearer porque as 50+ funções SQL não foram reescritas; outra
//          função manda `Bearer ${SUPABASE_SERVICE_ROLE_KEY}`, que hoje já é a sb_secret);
//       2) transição: a service_role LEGADA (JWT) que o cofre do banco ainda manda em Bearer
//          só é aceite depois de CONFIRMADA no Auth (GET /auth/v1/admin/users com essa chave —
//          o Auth verifica a assinatura; um JWT forjado dá 401). Nunca se aceita um JWT só por
//          o payload dizer role=service_role: com verify_jwt=false o portão deixou de validar
//          a assinatura e qualquer pessoa forja esse payload. No dia em que o Danilo desligar
//          as chaves legadas, o Auth passa a recusá-las e este caminho morre sozinho.
//   • Quem chama é um utilizador?         await utilizadorDoPedido(req)
//       confirma a sessão no Auth (GET /auth/v1/user), não lê o JWT à confiança.

type Dicionario = Record<string, string>;

function lerDicionario(nome: string): Dicionario {
  const bruto = Deno.env.get(nome);
  if (!bruto) return {};
  try {
    const o = JSON.parse(bruto) as unknown;
    if (o && typeof o === 'object' && !Array.isArray(o)) {
      return Object.fromEntries(
        Object.entries(o as Record<string, unknown>).filter(([, v]) => typeof v === 'string' && v.length > 0),
      ) as Dicionario;
    }
  } catch {
    // não é JSON — ignora-se e fica-se pelos recursos
  }
  return {};
}

/** Todas as chaves secretas novas (sb_secret_…) que esta função conhece. */
export function chavesSecretas(): string[] {
  const d = lerDicionario('SUPABASE_SECRET_KEYS');
  const soltas = [Deno.env.get('SUPABASE_SECRET_KEY'), Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')]
    .filter((v): v is string => typeof v === 'string' && v.startsWith('sb_secret_'));
  return [...new Set([...Object.values(d), ...soltas])];
}

/** Chave para clientes admin (salta RLS). Prefere a secreta nova; recurso = o que a plataforma der. */
export function chaveSecreta(nome = 'default'): string {
  const d = lerDicionario('SUPABASE_SECRET_KEYS');
  return d[nome] ?? Object.values(d)[0] ?? Deno.env.get('SUPABASE_SECRET_KEY') ??
    Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? '';
}

/** Chave para clientes em nome do utilizador (respeita RLS). Prefere a publicável; recurso = anon. */
export function chavePublicavel(nome = 'default'): string {
  const d = lerDicionario('SUPABASE_PUBLISHABLE_KEYS');
  return d[nome] ?? Object.values(d)[0] ?? Deno.env.get('SUPABASE_PUBLISHABLE_KEY') ??
    Deno.env.get('SUPABASE_ANON_KEY') ?? '';
}

/** Verdadeiro quando esta função já tem uma chave secreta nova à mão. */
export function temChaveNova(): boolean {
  return chavesSecretas().length > 0;
}

/** O token do cabeçalho Authorization (sem o "Bearer "), ou '' se não houver. */
export function tokenBearer(req: Request): string {
  const h = req.headers.get('authorization') ?? '';
  return /^bearer\s+/i.test(h) ? h.replace(/^bearer\s+/i, '').trim() : '';
}

/** Comparação em tempo constante (resumo SHA-256 dos dois lados). */
export async function iguais(a: string, b: string): Promise<boolean> {
  if (!a || !b) return false;
  const enc = new TextEncoder();
  const [ha, hb] = await Promise.all([
    crypto.subtle.digest('SHA-256', enc.encode(a)),
    crypto.subtle.digest('SHA-256', enc.encode(b)),
  ]);
  const x = new Uint8Array(ha);
  const y = new Uint8Array(hb);
  let dif = 0;
  for (let i = 0; i < x.length; i++) dif |= x[i] ^ y[i];
  return dif === 0;
}

/** Lê o `role` do payload de um JWT SEM validar a assinatura. Só serve para decidir se vale a pena ir ao Auth. */
export function papelNoJwtSemValidar(token: string): string | null {
  const partes = token.split('.');
  if (partes.length !== 3) return null;
  try {
    const b64 = partes[1].replace(/-/g, '+').replace(/_/g, '/');
    const payload = JSON.parse(atob(b64 + '='.repeat((4 - (b64.length % 4)) % 4))) as { role?: unknown };
    return typeof payload?.role === 'string' ? payload.role : null;
  } catch {
    return null;
  }
}

const confirmadas = new Set<string>(); // credenciais de servidor já confirmadas no Auth (por isolate)

/** Confirma no Auth que a credencial é mesmo de servidor (o Auth verifica a assinatura e o papel). */
export async function confirmadaNoAuth(credencial: string): Promise<boolean> {
  if (confirmadas.has(credencial)) return true;
  const url = Deno.env.get('SUPABASE_URL') ?? '';
  if (!url || !credencial) return false;
  try {
    const r = await fetch(`${url}/auth/v1/admin/users?per_page=1`, {
      headers: { apikey: credencial, Authorization: `Bearer ${credencial}` },
    });
    if (r.ok) {
      confirmadas.add(credencial);
      return true;
    }
  } catch {
    // rede em baixo: fecha-se, não se abre
  }
  return false;
}

/**
 * Verdadeiro quando quem chama é o servidor: o banco (pg_net, cron, gatilhos), outra Edge
 * Function, o CI ou a VPS. Ver as regras no topo do ficheiro.
 */
export async function chamadaDoServidor(req: Request): Promise<boolean> {
  const apikey = req.headers.get('apikey') ?? '';
  const bearer = tokenBearer(req);
  const candidatos = [apikey, bearer].filter((c) => c.length > 0);
  if (candidatos.length === 0) return false;
  const aceites = chavesSecretas();
  for (const c of candidatos) {
    for (const a of aceites) {
      if (await iguais(c, a)) return true;
    }
  }
  // Transição: service_role legada (JWT) em Bearer — só com confirmação viva no Auth.
  if (bearer && papelNoJwtSemValidar(bearer) === 'service_role' && (await confirmadaNoAuth(bearer))) {
    return true;
  }
  return false;
}

export type UtilizadorDoPedido = {
  id: string;
  email?: string;
  role?: string;
  app_metadata?: Record<string, unknown>;
  user_metadata?: Record<string, unknown>;
};

/** O utilizador com sessão válida por trás do pedido (confirmado no Auth), ou null. */
export async function utilizadorDoPedido(req: Request): Promise<UtilizadorDoPedido | null> {
  const token = tokenBearer(req);
  if (!token || token.startsWith('sb_') || token.split('.').length !== 3) return null;
  const papel = papelNoJwtSemValidar(token);
  if (papel === 'service_role' || papel === 'anon') return null;
  const url = Deno.env.get('SUPABASE_URL') ?? '';
  if (!url) return null;
  try {
    const r = await fetch(`${url}/auth/v1/user`, {
      headers: { apikey: chavePublicavel(), Authorization: `Bearer ${token}` },
    });
    if (!r.ok) return null;
    const u = (await r.json()) as UtilizadorDoPedido;
    return u && typeof u.id === 'string' && u.id.length > 0 ? u : null;
  } catch {
    return null;
  }
}

/** Verdadeiro quando o utilizador do pedido é admin (app_metadata.role = 'admin'). */
export async function chamadaDeAdmin(req: Request): Promise<boolean> {
  const u = await utilizadorDoPedido(req);
  return !!u && u.app_metadata?.role === 'admin';
}

/** 403 pronto quando a chamada não vem do servidor; null quando pode seguir. */
export async function exigirServidor(
  req: Request,
  cors: Record<string, string> = {},
): Promise<Response | null> {
  if (await chamadaDoServidor(req)) return null;
  return new Response(JSON.stringify({ ok: false, error: 'forbidden' }), {
    status: 403,
    headers: { ...cors, 'Content-Type': 'application/json' },
  });
}

/** 401 pronto quando não é nem servidor nem utilizador com sessão; null quando pode seguir. */
export async function exigirServidorOuUtilizador(
  req: Request,
  cors: Record<string, string> = {},
): Promise<{ resposta: Response | null; servidor: boolean; utilizador: UtilizadorDoPedido | null }> {
  if (await chamadaDoServidor(req)) return { resposta: null, servidor: true, utilizador: null };
  const u = await utilizadorDoPedido(req);
  if (u) return { resposta: null, servidor: false, utilizador: u };
  return {
    resposta: new Response(JSON.stringify({ ok: false, error: 'unauthorized' }), {
      status: 401,
      headers: { ...cors, 'Content-Type': 'application/json' },
    }),
    servidor: false,
    utilizador: null,
  };
}
