// _shared/keys.ts — nomes da missão chave-nova-16-10 (16/10/2026), por cima de _shared/chaves.ts.
import {
  chamadaDoServidor,
  chaveSecreta,
  chavesSecretas,
  iguais,
  utilizadorDoPedido,
} from './chaves.ts';

export const NOME_CHAVE_BACKEND = 'backend-2026-10';

export function secretKey(): string {
  const d = lerDicionarioSeguro('SUPABASE_SECRET_KEYS');
  return d[NOME_CHAVE_BACKEND] ?? d['default'] ?? chaveSecreta();
}

export async function isSecretApikey(req: Request): Promise<boolean> {
  const apikey = req.headers.get('apikey') ?? '';
  if (!apikey) return false;
  for (const k of chavesSecretas()) {
    if (await iguais(apikey, k)) return true;
  }
  return false;
}

export async function callerOk(req: Request): Promise<boolean> {
  if (await chamadaDoServidor(req)) return true;
  return (await utilizadorDoPedido(req)) !== null;
}

export async function exigirCallerOk(
  req: Request,
  cors: Record<string, string> = {},
): Promise<Response | null> {
  if (await callerOk(req)) return null;
  return new Response(JSON.stringify({ ok: false, error: 'unauthorized' }), {
    status: 401,
    headers: { ...cors, 'Content-Type': 'application/json' },
  });
}

function lerDicionarioSeguro(nome: string): Record<string, string> {
  try {
    const o = JSON.parse(Deno.env.get(nome) ?? '{}') as unknown;
    if (o && typeof o === 'object' && !Array.isArray(o)) {
      return Object.fromEntries(
        Object.entries(o as Record<string, unknown>).filter(([, v]) => typeof v === 'string' && v.length > 0),
      ) as Record<string, string>;
    }
  } catch {
    // ignora JSON inválido
  }
  return {};
}
