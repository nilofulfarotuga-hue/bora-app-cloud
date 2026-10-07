// aplicar-gaveta (07/10/2026) — aplica uma migração guardada na gaveta
// platform_settings.staged_<nome> directamente na base, pela ligação interna do
// runtime (SUPABASE_DB_URL), porque a API de gestão do Supabase ficou doente nesse
// dia (apply_migration pendurava sem o SQL chegar à base).
//
// Só o service_role pode chamar (verify_jwt=true no gateway valida a assinatura; aqui lê-se o claim role). Cada parte corre numa transacção; no fim o
// estado da gaveta passa a "aplicado". Função temporária: apagar quando a API sarar.
// POST { key: "staged_...", dry?: boolean }

import postgres from 'npm:postgres@3.4.4';

const SERVICE_ROLE = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!;
const DB_URL = Deno.env.get('SUPABASE_DB_URL');

function json(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), { status, headers: { 'Content-Type': 'application/json' } });
}

Deno.serve(async (req: Request) => {
  if (req.method !== 'POST') return json({ ok: false, error: 'method' }, 405);
  const auth = req.headers.get('Authorization') ?? '';
  const token = auth.startsWith('Bearer ') ? auth.slice(7) : '';
  let role = '';
  try { role = JSON.parse(atob(token.split('.')[1].replace(/-/g, '+').replace(/_/g, '/'))).role ?? ''; } catch { role = ''; }
  if (role !== 'service_role' && auth !== `Bearer ${SERVICE_ROLE}`) return json({ ok: false, error: 'service_role_only', role }, 401);
  if (!DB_URL) return json({ ok: false, error: 'SUPABASE_DB_URL ausente' }, 500);

  let body: { key?: string; dry?: boolean };
  try { body = await req.json(); } catch { return json({ ok: false, error: 'json' }, 400); }
  const key = String(body.key ?? '');
  if (!key.startsWith('staged_')) return json({ ok: false, error: 'key tem de começar por staged_' }, 400);

  const sql = postgres(DB_URL, { prepare: false, max: 1, idle_timeout: 5, connect_timeout: 20 });
  const t0 = Date.now();
  try {
    const rows = await sql`select value from public.platform_settings where key = ${key}`;
    if (rows.length === 0) return json({ ok: false, error: 'chave não existe' }, 404);
    const value = rows[0].value as Record<string, unknown>;
    const text = typeof value?.sql === 'string' ? value.sql : '';
    if (!text.trim()) return json({ ok: false, error: 'sem sql' }, 400);
    if (value.estado === 'aplicado') return json({ ok: true, ja_aplicado: true, key });
    if (body.dry) return json({ ok: true, dry: true, key, chars: text.length, estado: value.estado });

    await sql.begin(async (tx) => {
      await tx.unsafe(text);
      await tx`update public.platform_settings
                 set value = value || jsonb_build_object('estado', 'aplicado', 'aplicado_em', now()::text, 'aplicado_por', 'edge aplicar-gaveta (PC do Danilo)')
               where key = ${key}`;
    });
    return json({ ok: true, key, ms: Date.now() - t0, chars: text.length });
  } catch (e) {
    const err = e as { message?: string; position?: string; code?: string };
    return json({ ok: false, key, error: err.message ?? String(e), code: err.code ?? null, position: err.position ?? null, ms: Date.now() - t0 }, 500);
  } finally {
    await sql.end({ timeout: 5 }).catch(() => {});
  }
});
