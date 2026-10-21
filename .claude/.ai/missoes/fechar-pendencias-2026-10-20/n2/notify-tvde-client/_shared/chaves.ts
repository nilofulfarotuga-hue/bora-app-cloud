// _shared/chaves.ts — Missão chave-nova-16-10 (16/10/2026). Ler docs/SEGURANCA-CHAVES.md.
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
    // não é JSON
  }
  return {};
}

export function chavesSecretas(): string[] {
  const d = lerDicionario('SUPABASE_SECRET_KEYS');
  const soltas = [Deno.env.get('SUPABASE_SECRET_KEY'), Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')]
    .filter((v): v is string => typeof v === 'string' && v.startsWith('sb_secret_'));
  return [...new Set([...Object.values(d), ...soltas])];
}

export function chaveSecreta(nome = 'default'): string {
  const d = lerDicionario('SUPABASE_SECRET_KEYS');
  return d[nome] ?? Object.values(d)[0] ?? Deno.env.get('SUPABASE_SECRET_KEY') ??
    Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? '';
}

export function chavePublicavel(nome = 'default'): string {
  const d = lerDicionario('SUPABASE_PUBLISHABLE_KEYS');
  return d[nome] ?? Object.values(d)[0] ?? Deno.env.get('SUPABASE_PUBLISHABLE_KEY') ??
    Deno.env.get('SUPABASE_ANON_KEY') ?? '';
}

export function temChaveNova(): boolean {
  return chavesSecretas().length > 0;
}

export function tokenBearer(req: Request): string {
  const h = req.headers.get('authorization') ?? '';
  return /^bearer\s+/i.test(h) ? h.replace(/^bearer\s+/i, '').trim() : '';
}

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

const confirmadas = new Set<string>();

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
    // rede em baixo
  }
  return false;
}

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

export async function chamadaDeAdmin(req: Request): Promise<boolean> {
  const u = await utilizadorDoPedido(req);
  return !!u && u.app_metadata?.role === 'admin';
}

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
