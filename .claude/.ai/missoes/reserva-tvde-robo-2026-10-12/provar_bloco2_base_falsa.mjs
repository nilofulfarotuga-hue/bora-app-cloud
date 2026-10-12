// Prova do Bloco 2 (mudar destino de uma reserva) num Postgres LOCAL (PGlite),
// com uma base FALSA mínima: as tabelas e funções de que o SQL depende são
// criadas aqui com o mesmo nome e forma, as de rede/segredos são dublês que
// registam o que lhes foi pedido. Nada toca a produção.
// Uso: bun provar_bloco2_base_falsa.mjs <pasta com node_modules/@electric-sql/pglite> <bloco2-proposta-mudar-destino.md>
import { readFileSync } from 'node:fs'
import { pathToFileURL } from 'node:url'

const [, , pgliteDir, md] = process.argv
const { PGlite } = await import(pathToFileURL(`${pgliteDir}/node_modules/@electric-sql/pglite/dist/index.js`).href)
const db = new PGlite()
const sqlProposta = (readFileSync(md, 'utf8').replace(/\r\n/g, '\n').match(/```sql\n([\s\S]*?)```/) ?? [])[1]
if (!sqlProposta) throw new Error('bloco ```sql não encontrado no md')

let falhas = 0
const ok = (cond, msg) => { console.log(`${cond ? 'OK    ' : 'FALHOU'} ${msg}`); if (!cond) falhas++ }
const q = async (s, p) => (await db.query(s, p)).rows

// ---- base falsa -----------------------------------------------------------
await db.exec(`
CREATE ROLE anon; CREATE ROLE authenticated; CREATE ROLE service_role;
CREATE SCHEMA IF NOT EXISTS auth; CREATE SCHEMA IF NOT EXISTS net; CREATE SCHEMA IF NOT EXISTS vault; CREATE SCHEMA IF NOT EXISTS extensions;
CREATE TABLE public.platform_settings(key text primary key, value jsonb, description text, category text);
INSERT INTO public.platform_settings(key,value) VALUES
 ('tvde_base_distance_km','6'),('tvde_extra_per_km_cents','100'),('tvde_base_fare_cents','500'),
 ('tvde_driver_base_cents','400'),('tvde_driver_per_km_cents','80'),('tvde_km_fator_minimo','1.25');
CREATE TABLE public.tvde_rides(
  id uuid primary key default gen_random_uuid(), client_id uuid, driver_id uuid,
  origin_lat float8, origin_lng float8, origin_label text, dest_lat float8, dest_lng float8, dest_label text,
  est_distance_km numeric, est_fare_cents int, driver_earn_cents int, bora_cut_cents int,
  payment_method text, payment_intent_id text, payment_status text, status text, scheduled_at timestamptz,
  reservation_status text, reservation_driver_id uuid, roundtrip_credit_id uuid, agreed_fare_cents int,
  used_subscription_ride boolean default false, promo_credit_id uuid, tokens_applied_count int default 0,
  dest_change_count int default 0, dest_change_fee_cents int default 0, dest_change_driver_cents int default 0,
  updated_at timestamptz default now());
CREATE TABLE public.tvde_destination_changes(
  id uuid primary key default gen_random_uuid(), ride_id uuid, client_id uuid, driver_id uuid, ride_status text,
  old_dest_lat float8, old_dest_lng float8, old_dest_label text, new_dest_lat float8, new_dest_lng float8, new_dest_label text,
  km_done numeric, km_remaining numeric, km_new_total numeric, km_before numeric,
  price_before_cents int, price_new_cents int, table_diff_cents int, client_diff_cents int,
  driver_before_cents int, driver_new_cents int, driver_table_diff_cents int, driver_diff_cents int,
  min_applied boolean, driver_min_applied boolean, pricing_branch text, extra_fee_cents int, extra_driver_cents int,
  method text CHECK (method IN ('cash','card','mbway','nenhum','balcao')), payment_intent_id text,
  estado text CHECK (estado IN ('proposta','paga','aplicada','recusada','falhada')), motivo text,
  created_by uuid, created_by_role text, created_at timestamptz default now(), paid_at timestamptz, applied_at timestamptz,
  updated_at timestamptz default now(), refunded_at timestamptz, refund_cents int, refund_motivo text);
CREATE TABLE public.tvde_ride_events(id uuid primary key default gen_random_uuid(), ride_id uuid, status text, actor text, meta jsonb, at timestamptz default now());
CREATE TABLE public.tvde_client_fare_overrides(client_id uuid, active boolean, max_km numeric, fixed_fare_cents int, driver_earn_cents int);
CREATE TABLE public.net_calls(id serial, url text, body jsonb);
CREATE TABLE vault.decrypted_secrets(name text, decrypted_secret text);
INSERT INTO vault.decrypted_secrets VALUES ('service_role_key','sk-falsa'),('project_url','https://falso.local');
CREATE FUNCTION auth.uid() RETURNS uuid LANGUAGE sql STABLE AS $$ SELECT nullif(current_setting('app.uid', true), '')::uuid $$;
CREATE FUNCTION public.is_admin() RETURNS boolean LANGUAGE sql STABLE AS $$ SELECT coalesce(current_setting('app.admin', true) = '1', false) $$;
CREATE FUNCTION public.get_setting(p_key text) RETURNS jsonb LANGUAGE sql STABLE AS $$ SELECT value FROM public.platform_settings WHERE key = p_key $$;
CREATE FUNCTION public._tvde_km_seguro(p_olat float8, p_olng float8, p_dlat float8, p_dlng float8, p_km numeric) RETURNS numeric LANGUAGE sql STABLE AS $$ SELECT p_km $$;
CREATE FUNCTION public.tvde_client_fixed_fare_cents(p_client uuid, p_distance_km numeric) RETURNS int LANGUAGE sql STABLE AS $$
  select o.fixed_fare_cents from public.tvde_client_fare_overrides o where o.client_id = p_client and o.active and coalesce(p_distance_km,0) <= o.max_km limit 1 $$;
CREATE FUNCTION public.tvde_client_fixed_driver_earn_cents(p_client uuid, p_distance_km numeric) RETURNS int LANGUAGE sql STABLE AS $$
  select o.driver_earn_cents from public.tvde_client_fare_overrides o where o.client_id = p_client and o.active and coalesce(p_distance_km,0) <= o.max_km limit 1 $$;
CREATE FUNCTION public._dispatch_jwt() RETURNS text LANGUAGE sql AS $$ SELECT 'jwt-falso' $$;
CREATE FUNCTION net.http_post(url text, headers jsonb, body jsonb) RETURNS bigint LANGUAGE plpgsql AS $$ BEGIN INSERT INTO public.net_calls(url, body) VALUES (url, body); RETURN 1; END $$;
CREATE FUNCTION public._tvde_dest_change_apply(p_change_id uuid) RETURNS jsonb LANGUAGE plpgsql AS $$ BEGIN RAISE EXCEPTION 'ramo_corrida_a_meio_chamado_por_engano'; END $$;
CREATE FUNCTION public.tvde_reservation_auto_refund(p_ride_id uuid, p_motivo text) RETURNS boolean LANGUAGE plpgsql AS $$ BEGIN RAISE EXCEPTION 'auto_refund_total_chamado_por_engano'; END $$;
`)

// ---- a proposta -----------------------------------------------------------
try { await db.exec(sqlProposta); ok(true, 'SQL da proposta criado sem erro (7 funções + setting)') }
catch (e) { ok(false, `SQL da proposta: ${e.message}`); process.exit(1) }

const CLI = '11111111-1111-4111-8111-111111111111', CLI2 = '22222222-2222-4222-8222-222222222222'
const DRV = '33333333-3333-4333-8333-333333333333'
const amanha = new Date(Date.now() + 86400e3).toISOString()
async function novaReserva(extra = {}) {
  const base = { client_id: CLI, origin_lat: 40.5373, origin_lng: -7.2676, origin_label: 'Praça', dest_lat: 40.54, dest_lng: -7.26, dest_label: 'Hospital',
    est_distance_km: 4.44, est_fare_cents: 500, driver_earn_cents: 400, bora_cut_cents: 100, payment_method: 'cash', status: 'agendada',
    scheduled_at: amanha, reservation_status: 'atribuida', reservation_driver_id: DRV, ...extra }
  const cols = Object.keys(base); const vals = cols.map((_, i) => `$${i + 1}`)
  const r = await q(`INSERT INTO public.tvde_rides(${cols.join(',')}) VALUES (${vals.join(',')}) RETURNING id`, cols.map((c) => base[c]))
  return r[0].id
}
const comoCliente = (uid = CLI) => db.exec(`SELECT set_config('app.uid','${uid}',false), set_config('app.admin','0',false)`)
const esperaErro = async (sql, params, codigo, msg) => {
  try { await db.query(sql, params); ok(false, `${msg} (não deu erro)`) }
  catch (e) { ok(String(e.message).includes(codigo), `${msg} → ${e.message.slice(0, 60)}`) }
}

// S0: interruptor desligado → recusa
await comoCliente()
let r0 = await novaReserva()
await esperaErro(`SELECT public.tvde_reservation_dest_quote($1, 40.6, -7.1, 'Longe', 10)`, [r0], 'reservation_dest_change_disabled', 'S0 interruptor desligado recusa')
await db.exec(`UPDATE public.platform_settings SET value='true' WHERE key='tvde_reservation_dest_change_enabled'`)

// S1: dinheiro, destino mais longe (10 km) → 500 + 4×100 = 900; motorista 400 + 4×80 = 720; aplica já
let q1 = (await q(`SELECT public.tvde_reservation_dest_quote($1, 40.6, -7.1, 'Longe', 10) AS j`, [r0]))[0].j
ok(q1.price_new_cents === 900 && q1.client_diff_cents === 400 && q1.driver_new_cents === 720 && q1.needs_payment === false, `S1 cotação dinheiro 10 km: ${q1.price_before_cents}→${q1.price_new_cents} (+${q1.client_diff_cents}), motorista ${q1.driver_new_cents}, needs_payment=${q1.needs_payment}`)
let c1 = (await q(`SELECT public.tvde_reservation_change_dest($1, 40.6, -7.1, 'Longe', 10, 400) AS j`, [r0]))[0].j
let ride1 = (await q(`SELECT * FROM public.tvde_rides WHERE id=$1`, [r0]))[0]
ok(c1.applied === true && ride1.est_fare_cents === 900 && ride1.driver_earn_cents === 720 && ride1.bora_cut_cents === 180 && Number(ride1.est_distance_km) === 10 && ride1.dest_label === 'Longe' && ride1.dest_change_fee_cents === 0,
  `S1 aplicado: preço ${ride1.est_fare_cents}, ganho ${ride1.driver_earn_cents}, bora ${ride1.bora_cut_cents}, km ${ride1.est_distance_km}, fee_cents(online)=${ride1.dest_change_fee_cents}`)
let ev1 = await q(`SELECT status, actor, meta FROM public.tvde_ride_events WHERE ride_id=$1 AND status='reserva_destino_alterado'`, [r0])
ok(ev1.length === 1 && ev1[0].actor === 'client' && ev1[0].meta.client_diff_cents === 400, 'S1 evento reserva_destino_alterado (client, +400)')
let push1 = await q(`SELECT body FROM public.net_calls WHERE body->>'kind'='dest_changed' AND body->>'rideId'=$1`, [r0])
ok(push1.length === 1 && push1[0].body.driverId === DRV && push1[0].body.paidOnline === false, 'S1 aviso dest_changed ao motorista atribuído (paidOnline=false)')

// S2: cartão JÁ PAGO, mais longe → proposta (needs_payment) → confirm_paid → aplica e grava fee à parte
let r2 = await novaReserva({ payment_method: 'card', payment_status: 'succeeded', payment_intent_id: 'pi_reserva_2' })
let c2 = (await q(`SELECT public.tvde_reservation_change_dest($1, 40.6, -7.1, 'Longe', 10, 400) AS j`, [r2]))[0].j
let ride2a = (await q(`SELECT est_fare_cents, dest_label FROM public.tvde_rides WHERE id=$1`, [r2]))[0]
ok(c2.needs_payment === true && c2.estado === 'proposta' && ride2a.est_fare_cents === 500 && ride2a.dest_label === 'Hospital', `S2 cartão +400 → proposta ${c2.change_id?.slice(0, 8)}, reserva INTACTA (${ride2a.est_fare_cents}, ${ride2a.dest_label})`)
await db.query(`UPDATE public.tvde_destination_changes SET payment_intent_id='pi_dest_2' WHERE id=$1`, [c2.change_id])
await esperaErro(`SELECT public.tvde_dest_change_confirm_paid($1, 'pi_dest_2', 300)`, [c2.change_id], 'amount_mismatch', 'S2 confirm_paid com valor errado recusa')
let cp2 = (await q(`SELECT public.tvde_dest_change_confirm_paid($1, 'pi_dest_2', 400) AS j`, [c2.change_id]))[0].j
let ride2 = (await q(`SELECT * FROM public.tvde_rides WHERE id=$1`, [r2]))[0]
let ch2 = (await q(`SELECT estado, pricing_branch, paid_at, applied_at FROM public.tvde_destination_changes WHERE id=$1`, [c2.change_id]))[0]
ok(cp2.estado === 'aplicada' && ride2.est_fare_cents === 900 && ride2.dest_change_fee_cents === 400 && ride2.dest_change_driver_cents === 320 && ride2.dest_label === 'Longe' && ch2.estado === 'aplicada' && ch2.pricing_branch === 'reserva' && ch2.paid_at && ch2.applied_at,
  `S2 confirm_paid 400 → aplicado: preço ${ride2.est_fare_cents}, fee à parte ${ride2.dest_change_fee_cents}, motorista à parte ${ride2.dest_change_driver_cents}, change ${ch2.estado}/${ch2.pricing_branch}`)
let again = (await q(`SELECT public.tvde_dest_change_confirm_paid($1, 'pi_dest_2', 400) AS j`, [c2.change_id]))[0].j
ok(again.already === true, 'S2 confirm_paid repetido é idempotente (already=true)')
let push2 = await q(`SELECT body FROM public.net_calls WHERE body->>'kind'='dest_changed' AND body->>'rideId'=$1`, [r2])
ok(push2.length === 1 && push2[0].body.paidOnline === true && push2[0].body.driverDiffCents === 320, 'S2 aviso dest_changed paidOnline=true, +320 ao motorista')

// S3: cartão JÁ PAGO a 900 (10 km), destino mais perto (4 km → 500) → aplica já + devolução de 400 pedida
let r3 = await novaReserva({ payment_method: 'mbway', payment_status: 'succeeded', payment_intent_id: 'pi_reserva_3', est_distance_km: 10, est_fare_cents: 900, driver_earn_cents: 720, bora_cut_cents: 180, dest_label: 'Longe' })
let q3 = (await q(`SELECT public.tvde_reservation_dest_quote($1, 40.54, -7.26, 'Perto', 4) AS j`, [r3]))[0].j
ok(q3.client_diff_cents === -400 && q3.refund_cents === 400 && q3.needs_payment === false, `S3 cotação mais perto: diff ${q3.client_diff_cents}, refund_cents ${q3.refund_cents}`)
let c3 = (await q(`SELECT public.tvde_reservation_change_dest($1, 40.54, -7.26, 'Perto', 4, -400) AS j`, [r3]))[0].j
let ride3 = (await q(`SELECT * FROM public.tvde_rides WHERE id=$1`, [r3]))[0]
let ch3 = (await q(`SELECT estado, refund_cents, refunded_at, payment_intent_id, client_diff_cents FROM public.tvde_destination_changes WHERE ride_id=$1`, [r3]))[0]
let refund3 = await q(`SELECT body FROM public.net_calls WHERE body->>'action'='auto_refund_reservation' AND body->>'ride_id'=$1`, [r3])
let evr3 = await q(`SELECT meta FROM public.tvde_ride_events WHERE ride_id=$1 AND status='reserva_reembolso_pedido'`, [r3])
ok(c3.applied === true && c3.refund_requested === true && ride3.est_fare_cents === 500 && ride3.driver_earn_cents === 400 && ride3.payment_status === 'succeeded' && ride3.dest_change_fee_cents === 0
  && ch3.estado === 'aplicada' && ch3.refund_cents === 400 && ch3.refunded_at === null && ch3.payment_intent_id === null
  && refund3.length === 1 && refund3[0].body.valor_cents === 400 && refund3[0].body.manter_estado === true && evr3.length === 1 && evr3[0].meta.parcial === true,
  `S3 mais perto pago: preço ${ride3.est_fare_cents}, estado pagamento ${ride3.payment_status}, pedido auto_refund_reservation valor_cents=${refund3[0]?.body?.valor_cents}, change refund_cents=${ch3.refund_cents} (refunded_at null até a tvde-payment confirmar)`)

// S4: preço fixo do cliente (Ricardo/Vina): 5,00 € até 8 km, motorista 4,00 € — destino a 7 km mantém 500/400 (diff 0)
await db.query(`INSERT INTO public.tvde_client_fare_overrides VALUES ($1, true, 8, 500, 400)`, [CLI2])
await comoCliente(CLI2)
let r4 = await novaReserva({ client_id: CLI2, payment_method: 'mbway', payment_status: 'succeeded', payment_intent_id: 'pi_reserva_4' })
let q4 = (await q(`SELECT public.tvde_reservation_dest_quote($1, 40.6, -7.1, 'SUMA', 7) AS j`, [r4]))[0].j
ok(q4.price_new_cents === 500 && q4.client_diff_cents === 0 && q4.driver_new_cents === 400 && q4.fixed_fare_override_cents === 500 && q4.needs_payment === false, `S4 preço fixo do cliente respeitado a 7 km: ${q4.price_new_cents} (diff ${q4.client_diff_cents}), motorista ${q4.driver_new_cents}`)
let q4b = (await q(`SELECT public.tvde_reservation_dest_quote($1, 40.6, -7.1, 'Fora do fixo', 9) AS j`, [r4]))[0].j
ok(q4b.price_new_cents === 800 && q4b.client_diff_cents === 300 && q4b.needs_payment === true, `S4b acima do max_km (9 km) volta à tabela: ${q4b.price_new_cents} (+${q4b.client_diff_cents}), needs_payment=${q4b.needs_payment}`)
// admin muda com o preço fixo do CLIENTE (não o do admin)
await db.exec(`SELECT set_config('app.uid','${CLI}',false), set_config('app.admin','1',false)`)
let c4 = (await q(`SELECT public.tvde_reservation_change_dest($1, 40.6, -7.1, 'SUMA', 7, 0) AS j`, [r4]))[0].j
let ev4 = await q(`SELECT actor FROM public.tvde_ride_events WHERE ride_id=$1 AND status='reserva_destino_alterado'`, [r4])
ok(c4.applied === true && c4.client_diff_cents === 0 && ev4[0]?.actor === 'admin', `S4c admin aplica com diff 0 e actor=admin`)

// S5: guardas
await comoCliente()
let r5 = await novaReserva({ payment_method: 'card', payment_status: 'pendente', reservation_status: 'aguarda_pagamento', reservation_driver_id: null })
await esperaErro(`SELECT public.tvde_reservation_dest_quote($1, 40.6, -7.1, 'x', 10)`, [r5], 'reservation_awaiting_payment', 'S5a aguarda_pagamento recusa')
let r6 = await novaReserva({ roundtrip_credit_id: '44444444-4444-4444-8444-444444444444' })
await esperaErro(`SELECT public.tvde_reservation_dest_quote($1, 40.6, -7.1, 'x', 10)`, [r6], 'reservation_dest_change_not_supported', 'S5b pacote ida-e-volta recusa')
let r7 = await novaReserva({ status: 'motorista_a_caminho' })
await esperaErro(`SELECT public.tvde_reservation_dest_quote($1, 40.6, -7.1, 'x', 10)`, [r7], 'too_late_to_change', 'S5c corrida já arrancada recusa')
await comoCliente(CLI2)
await esperaErro(`SELECT public.tvde_reservation_dest_quote($1, 40.6, -7.1, 'x', 10)`, [r0], 'reservation_not_yours', 'S5d reserva alheia recusa')
await comoCliente()
await esperaErro(`SELECT public.tvde_reservation_change_dest($1, 40.6, -7.1, 'x', 10, 999)`, [r0], 'dest_change_price_changed', 'S5e preço esperado diferente recusa')
await esperaErro(`SELECT public.tvde_reservation_dest_quote($1, 40.6, -7.1, 'x', 400)`, [r0], 'dest_too_far', 'S5f 400 km recusa')

// S6: abaixo do mínimo Stripe (diff 20 c online) → não cobra, preço fica
await db.query(`INSERT INTO public.tvde_client_fare_overrides VALUES ($1, true, 100, 520, 400)`, [CLI])
let r8 = await novaReserva({ payment_method: 'card', payment_status: 'succeeded', payment_intent_id: 'pi_8' })
let q8 = (await q(`SELECT public.tvde_reservation_dest_quote($1, 40.6, -7.1, 'x', 10) AS j`, [r8]))[0].j
ok(q8.client_diff_cents === 0 && q8.abaixo_minimo_stripe === true && q8.price_new_cents === 500, `S6 diferença de 20 c online → 0 (abaixo do mínimo Stripe), preço fica ${q8.price_new_cents}`)

console.log(`\nfalhas: ${falhas}`)
process.exit(falhas ? 1 : 0)
