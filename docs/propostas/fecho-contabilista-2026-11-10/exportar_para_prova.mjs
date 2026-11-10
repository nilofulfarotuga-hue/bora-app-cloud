// Exporta (só leitura) as tabelas e funções de que o fecho depende, para provar a proposta no PGlite.
// Uso: node exportar.mjs  → escreve dump.json nesta pasta. Os dados ficam só no scratchpad desta sessão.
import { execFileSync } from 'node:child_process'
import fs from 'node:fs'
import path from 'node:path'

const SB = path.join(process.env.LOCALAPPDATA, 'npm-cache/_npx/b96a6bd565c470ce/node_modules/@supabase/cli-windows-x64/bin/supabase.exe')
const WT = 'C:/BoraLocal/wt-fecho-contabilista-10-11'
const AQUI = path.dirname(new URL(import.meta.url).pathname).replace(/^\/([A-Za-z]:)/, '$1')

const TABELAS = [
  ['public.orders', "created_at >= '2026-09-20' or delivered_at >= '2026-09-20'"],
  ['public.ledger_entries', "created_at >= '2026-09-20'"],
  ['public.order_receipts_v2', "order_id in (select id from public.orders where created_at >= '2026-09-20')"],
  ['public.restaurants', 'true'],
  ['public.drivers', 'true'],
  ['public.driver_fiscal_status', 'true'],
  ['public.provider_atividade', 'true'],
  ['public.cleaners', 'true'],
  ['public.casa_profissionais', 'true'],
  ['public.washers', 'true'],
  ['public.cleaning_bookings', 'true'],
  ['public.carwash_bookings', 'true'],
  ['public.tvde_rides', "created_at >= '2026-09-25'"],
  ['public.platform_settings', "key like 'fecho_%' or key = 'token_value_cents_x100'"],
  ['public.bora_tokens', "created_at >= '2026-09-25' or source_order_id like 'promo-%'"],
  ['public.promo_code_uses', 'true'],
  ['public.promo_codes', 'true'],
  ['public.checkin_premios_vales', 'true'],
  ['public.stripe_extrato_contabilista', "mes in ('2026-10','2026-11')"],
  ['public.order_invoice_requests', 'true'],
  ['public.client_billing_profile', 'true'],
  ['public.partner_weekly_settlements', 'true'],
  ['public.cleaner_weekly_settlements', 'true'],
  ['public.appointment_payouts', 'true'],
  ['public.service_providers', 'true'],
  ['public.monthly_statement_log', 'true'],
  ['public.fecho_mensal_contabilista_log', 'true'],
  ['public.driver_monthly_invoices', 'true'],
  ['public.tips', "created_at >= '2026-09-20'"],
]
const FUNCOES = ['_fecho_limites', '_fecho_pedidos', '_mult_nao_parceiro', 'pedido_parceiro_chamou',
  '_fecho_stripe_estimado', 'is_demo_email', 'get_setting']

function correr(sql) {
  const f = path.join(AQUI, '_q.sql')
  fs.writeFileSync(f, sql)
  const out = execFileSync(SB, ['db', 'query', '--linked', '--project-ref', 'ojykpzwqrtusfeakzrna', '--agent', 'no',
    '--output-format', 'json', '--yes', '-f', f], { cwd: WT, encoding: 'utf8', maxBuffer: 256 * 1024 * 1024, stdio: ['ignore', 'pipe', 'pipe'] })
  const j = JSON.parse(out)
  return Array.isArray(j) ? j : (j.rows ?? j.data ?? j.result ?? j)
}

const dump = { tabelas: [], funcoes: [] }
for (const [t, filtro] of TABELAS) {
  const sql = `select '${t}' t,
    (select json_agg(json_build_object('n', attname, 't', format_type(atttypid, atttypmod)) order by attnum)
       from pg_attribute where attrelid = '${t}'::regclass and attnum > 0 and not attisdropped) cols,
    (select coalesce(json_agg(x), '[]'::json) from (select * from ${t} where ${filtro}) x) dados`
  const r = correr(sql)[0]
  dump.tabelas.push(r)
  console.log(t, (r.dados ?? []).length)
}
const u = correr(`select coalesce(json_agg(json_build_object('id', id, 'email', email)), '[]'::json) d from auth.users`)[0]
dump.auth_users = u.d
console.log('auth.users', u.d.length)
const fs2 = correr(`select p.proname, pg_get_functiondef(p.oid) def from pg_proc p join pg_namespace n on n.oid = p.pronamespace
  where n.nspname = 'public' and p.proname in (${FUNCOES.map((x) => `'${x}'`).join(',')})`)
dump.funcoes = fs2
console.log('funcoes', fs2.map((x) => x.proname).join(','))
const sig = correr(`select p.proname, pg_get_function_identity_arguments(p.oid) a, pg_get_function_result(p.oid) r from pg_proc p join pg_namespace n on n.oid = p.pronamespace
  where n.nspname = 'public' and p.proname in ('log_admin_action', 'is_admin')`)
dump.assinaturas = sig
console.log('assinaturas', JSON.stringify(sig))
// Números de referência no AR (antes da proposta), para comparar.
dump.referencia = correr(`select set_config('request.jwt.claims', '{"role":"service_role"}', true) x,
  public.admin_monthly_closeout(2026, 10) out10, public.admin_monthly_closeout(2026, 11) out11`)[0]
fs.writeFileSync(path.join(AQUI, 'dump.json'), JSON.stringify(dump))
console.log('ok dump.json', fs.statSync(path.join(AQUI, 'dump.json')).size)
