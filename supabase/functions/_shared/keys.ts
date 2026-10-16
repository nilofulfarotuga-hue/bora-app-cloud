// _shared/keys.ts — os nomes fixados na ordem da missão chave-nova-16-10 (16/10/2026),
// por cima de _shared/chaves.ts (que tem a implementação e os testes).
//
//   secretKey()        chave secreta para clientes admin: SUPABASE_SECRET_KEYS['backend-2026-10']
//                      → ['default'] → SUPABASE_SERVICE_ROLE_KEY (hoje já é a sb_secret default)
//   isSecretApikey(req) o cabeçalho `apikey` é uma das chaves secretas conhecidas
//   callerOk(req)      isSecretApikey(req) OU chave secreta em Bearer OU service_role legada
//                      confirmada no Auth OU utilizador com sessão válida (confirmado no Auth).
//                      É o que o verify_jwt da plataforma fazia, mais as chaves novas.
//
// Como se usa, no topo do handler de uma função chamada pelo banco/cron/outra função:
//   if (!(await callerOk(req))) return new Response(JSON.stringify({ ok: false, error: 'unauthorized' }), { status: 401, ... })
// e, em vez de Deno.env.get('SUPABASE_SERVICE_ROLE_KEY'), usar secretKey().
import {
  chamadaDoServidor,
  chaveSecreta,
  chavesSecretas,
  iguais,
  utilizadorDoPedido,
} from './chaves.ts';

export const NOME_CHAVE_BACKEND = 'backend-2026-10';

/** Chave secreta para clientes admin: 'backend-2026-10' → 'default' → variável antiga. */
export function secretKey(): string {
  const d = lerDicionarioSeguro('SUPABASE_SECRET_KEYS');
  return d[NOME_CHAVE_BACKEND] ?? d['default'] ?? chaveSecreta();
}

/** O cabeçalho `apikey` traz uma das chaves secretas conhecidas (comparação em tempo constante). */
export async function isSecretApikey(req: Request): Promise<boolean> {
  const apikey = req.headers.get('apikey') ?? '';
  if (!apikey) return false;
  for (const k of chavesSecretas()) {
    if (await iguais(apikey, k)) return true;
  }
  return false;
}

/** Servidor (chave secreta nova ou legada confirmada no Auth) ou utilizador com sessão válida. */
export async function callerOk(req: Request): Promise<boolean> {
  if (await chamadaDoServidor(req)) return true;
  return (await utilizadorDoPedido(req)) !== null;
}

/** 401 pronto quando callerOk falha; null quando pode seguir. */
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
