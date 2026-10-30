// Prova local (PGlite) da migração 20261030145000 — sem tocar em produção.
// Esquema mínimo de apoio (stubs) + a migração inteira + cenários.
import { PGlite } from '@electric-sql/pglite';
import fs from 'node:fs';

const [, , ficheiroInterruptor, ficheiroMigracao] = process.argv;
const db = new PGlite();
const q = async (sql, p) => (await db.query(sql, p)).rows;
const ex = (sql) => db.exec(sql);

await ex(`
CREATE ROLE anon; CREATE ROLE authenticated; CREATE ROLE service_role;
CREATE SCHEMA auth; CREATE SCHEMA vault; CREATE SCHEMA net; CREATE SCHEMA cron;
CREATE TABLE auth.users (id uuid PRIMARY KEY, email text, raw_app_meta_data jsonb);
CREATE FUNCTION auth.uid() RETURNS uuid LANGUAGE sql STABLE AS $$
  SELECT NULLIF(NULLIF(current_setting('request.jwt.claims', true), '')::jsonb ->> 'sub', '')::uuid $$;
CREATE TABLE vault.decrypted_secrets (name text, decrypted_secret text);
INSERT INTO vault.decrypted_secrets VALUES ('project_url', 'https://x.supabase.co'), ('service_role_key', 'k');
CREATE TABLE net.pedidos (id bigserial, url text, body jsonb);
CREATE FUNCTION net.http_post(url text, headers jsonb, body jsonb) RETURNS bigint LANGUAGE sql AS $$
  INSERT INTO net.pedidos(url, body) VALUES (url, body) RETURNING id $$;
CREATE TABLE cron.job (jobid bigserial, jobname text UNIQUE, schedule text, command text);
CREATE FUNCTION cron.schedule(n text, s text, c text) RETURNS bigint LANGUAGE sql AS $$
  INSERT INTO cron.job(jobname, schedule, command) VALUES (n, s, c)
  ON CONFLICT (jobname) DO UPDATE SET schedule = EXCLUDED.schedule, command = EXCLUDED.command RETURNING jobid $$;

CREATE TABLE public.platform_settings (key text PRIMARY KEY, value jsonb, category text, description text, is_secret boolean DEFAULT false);
INSERT INTO public.platform_settings(key, value, category) VALUES ('tips_enabled', 'true', 'tips'), ('tip_max_cents', '5000', 'tips');
CREATE FUNCTION public.get_setting(p_key text) RETURNS jsonb LANGUAGE sql STABLE AS $$
  SELECT value FROM public.platform_settings WHERE key = p_key AND NOT COALESCE(is_secret, false) $$;
CREATE TABLE public.e2e_log (id bigserial, created_at timestamptz DEFAULT now(), fluxo text, passo text, estado text, detalhe text);
CREATE TABLE public.orders (
  id text PRIMARY KEY DEFAULT gen_random_uuid()::text, user_id uuid, status text DEFAULT 'created',
  service_type text, payment_method text, payment_status text DEFAULT 'pending', payment_intent_id text,
  assigned_driver_id text, stripe_charge_cents integer DEFAULT 0, payment_buffer_total numeric,
  tip_amount_cents integer DEFAULT 0, tip_added_at timestamptz, cancelled_at timestamptz,
  status_updated_at timestamptz, created_at timestamptz DEFAULT now());
CREATE TABLE public.payment_drafts (id uuid PRIMARY KEY DEFAULT gen_random_uuid(), payment_intent_id text, user_id uuid,
  payload jsonb, amount_cents integer, created_at timestamptz DEFAULT now(), used_at timestamptz, order_id text);
CREATE TABLE public.tips (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(), target text NOT NULL CHECK (target IN ('order','tvde')),
  order_id text REFERENCES public.orders(id), tvde_ride_id uuid, client_user_id uuid NOT NULL, provider_user_id uuid NOT NULL,
  amount_cents integer NOT NULL CHECK (amount_cents >= 50), method text NOT NULL CHECK (method IN ('card','mbway','cash')),
  moment text NOT NULL CHECK (moment IN ('checkout','after')),
  status text NOT NULL DEFAULT 'pending' CHECK (status IN ('pending','requires_action','succeeded','failed','refunded','cash_due','cash_collected','cancelled')),
  stripe_payment_intent_id text, stripe_fee_cents integer, failure_reason text, created_at timestamptz NOT NULL DEFAULT now(),
  paid_at timestamptz, refunded_at timestamptz, refunded_by uuid, refund_reason text,
  liquido_prestador_cents integer GENERATED ALWAYS AS (CASE WHEN moment = 'after' AND method IN ('card','mbway')
    THEN GREATEST(0, amount_cents - COALESCE(stripe_fee_cents, 25 + CEIL(amount_cents * 0.015)::int)) ELSE amount_cents END) STORED);
CREATE UNIQUE INDEX tips_uma_viva_por_pedido ON public.tips(order_id) WHERE order_id IS NOT NULL AND status NOT IN ('failed','cancelled');
CREATE UNIQUE INDEX tips_pi_unico ON public.tips(stripe_payment_intent_id) WHERE stripe_payment_intent_id IS NOT NULL;
-- espelho igual ao de produção (04/10)
CREATE FUNCTION public.fn_tips_espelho_no_pedido() RETURNS trigger LANGUAGE plpgsql AS $f$
BEGIN
  IF NEW.order_id IS NOT NULL THEN
    UPDATE public.orders SET tip_amount_cents = CASE WHEN NEW.status IN ('succeeded','cash_due','cash_collected') THEN NEW.amount_cents ELSE 0 END
     WHERE id = NEW.order_id;
  END IF;
  RETURN NEW;
END $f$;
CREATE TRIGGER trg_tips_espelho_no_pedido AFTER INSERT OR UPDATE OF status ON public.tips FOR EACH ROW EXECUTE FUNCTION public.fn_tips_espelho_no_pedido();
CREATE FUNCTION public.fn_orders_gorjeta_acompanha() RETURNS trigger LANGUAGE plpgsql AS $f$ BEGIN RETURN NEW; END $f$;
CREATE TRIGGER trg_orders_gorjeta_acompanha AFTER UPDATE OF status, assigned_driver_id ON public.orders FOR EACH ROW EXECUTE FUNCTION public.fn_orders_gorjeta_acompanha();
INSERT INTO auth.users VALUES ('d66d1522-ad8e-426e-9a75-76d636004186', 't@x', '{}');
CREATE TABLE public.avisos (tipo text, resumo text);
CREATE FUNCTION public.notify_admin_event(p_event_type text, p_severity text, p_summary text, p_entity_type text,
  p_entity_id text, p_payload jsonb, p_deep_link text) RETURNS void LANGUAGE sql AS $$
  INSERT INTO public.avisos VALUES (p_event_type, p_summary) $$;
`);

const sqlMig = fs.readFileSync(ficheiroMigracao, 'utf8');
await ex(fs.readFileSync(ficheiroInterruptor, 'utf8'));
await ex(sqlMig);
console.log('MIGRAÇÃO: aplicada sem erros no PGlite');

const U = 'd66d1522-ad8e-426e-9a75-76d636004186';
const cli = JSON.stringify({ sub: U, role: 'authenticated' });
let falhas = 0;
const ok = (nome, cond, info = '') => { if (!cond) falhas++; console.log(`${cond ? 'ok ' : 'FALHOU'} ${nome} ${info}`); };
const claims = async (c) => ex(`SELECT set_config('request.jwt.claims', '${c}', false)`);

// interruptor desligado
await claims(cli);
let r = (await q(`SELECT public.client_preparar_gorjeta_checkout(200) r`))[0].r;
ok('desligado → junto_desligado', r.ok === false && r.motivo === 'junto_desligado');
await ex(`UPDATE public.platform_settings SET value = 'true' WHERE key = 'tips_checkout_junto_pagamento'`);
r = (await q(`SELECT public.client_preparar_gorjeta_checkout(30) r`))[0].r;
ok('0,30 € recusado', r.motivo === 'valor_invalido');
r = (await q(`SELECT public.client_preparar_gorjeta_checkout(200) r`))[0].r;
ok('marca 200', r.ok === true && r.gorjeta_cents === 200);
ok('para_cobrar = 200', (await q(`SELECT public.gorjeta_checkout_para_cobrar($1) v`, [U]))[0].v === 200);

// dinheiro e Favor não gastam
await q(`INSERT INTO public.orders(id, user_id, service_type, payment_method, payment_buffer_total) VALUES ('cash1', $1, 'storeShopping', 'cash', 10)`, [U]);
await q(`INSERT INTO public.orders(id, user_id, service_type, payment_method, payment_buffer_total) VALUES ('err1', $1, 'errand', 'mbway', 10)`, [U]);
let mk = (await q(`SELECT * FROM public.gorjeta_checkout_pendente WHERE user_id = $1`, [U]))[0];
ok('dinheiro e Favor: marcação intacta, sem gorjeta', mk.usado_em === null &&
  (await q(`SELECT count(*)::int n FROM public.tips WHERE order_id IN ('cash1','err1')`))[0].n === 0);

// MB Way do carrinho
await q(`INSERT INTO public.orders(id, user_id, service_type, payment_method, payment_buffer_total) VALUES ('mb1', $1, 'storeShopping', 'mbway', 10.5)`, [U]);
let t = (await q(`SELECT * FROM public.tips WHERE order_id = 'mb1'`))[0];
mk = (await q(`SELECT * FROM public.gorjeta_checkout_pendente WHERE user_id = $1`, [U]))[0];
ok('MB Way: gorjeta pending junto 200, marcação gasta', t?.status === 'pending' && t.cobrada_junto && t.amount_cents === 200 && mk.usado_em !== null && mk.gorjeta_aplicada === true);
ok('mbway_valor = 200', (await q(`SELECT public.gorjeta_checkout_mbway_valor('mb1') v`))[0].v === 200);
ok('mbway_pi grava', (await q(`SELECT public.gorjeta_checkout_mbway_pi('mb1', 'pi_mb1') v`))[0].v === true);
await ex(`UPDATE public.orders SET payment_status = 'paid', payment_intent_id = 'pi_mb1' WHERE id = 'mb1'`);
t = (await q(`SELECT * FROM public.tips WHERE order_id = 'mb1'`))[0];
ok('MB Way pago com o PI → succeeded, espelho 200', t.status === 'succeeded' &&
  (await q(`SELECT tip_amount_cents v FROM public.orders WHERE id = 'mb1'`))[0].v === 200);

// MB Way sem PI gravado: só pelo valor
await claims(cli);
await q(`SELECT public.client_preparar_gorjeta_checkout(300)`);
await q(`INSERT INTO public.orders(id, user_id, service_type, payment_method, payment_buffer_total) VALUES ('mb2', $1, 'restaurant', 'mbway', 12.34)`, [U]);
await ex(`UPDATE public.orders SET payment_status = 'paid', payment_intent_id = 'pi_mb2' WHERE id = 'mb2'`);
ok('sem PI gravado e sem valor: fica pending', (await q(`SELECT status FROM public.tips WHERE order_id = 'mb2'`))[0].status === 'pending');
await ex(`UPDATE public.orders SET stripe_charge_cents = 1234 + 300 WHERE id = 'mb2'`);
ok('cobrado = buffer + gorjeta → succeeded', (await q(`SELECT status FROM public.tips WHERE order_id = 'mb2'`))[0].status === 'succeeded');

// MB Way falhado
await q(`SELECT public.client_preparar_gorjeta_checkout(250)`);
await q(`INSERT INTO public.orders(id, user_id, service_type, payment_method, payment_buffer_total) VALUES ('mb3', $1, 'takeaway', 'mbway', 8)`, [U]);
await ex(`UPDATE public.orders SET payment_status = 'failed' WHERE id = 'mb3'`);
ok('falhado → failed; valor 0', (await q(`SELECT status FROM public.tips WHERE order_id = 'mb3'`))[0].status === 'failed' &&
  (await q(`SELECT public.gorjeta_checkout_mbway_valor('mb3') v`))[0].v === 0);
await ex(`UPDATE public.orders SET payment_status = 'pending' WHERE id = 'mb3'`);
ok('nova tentativa (pending) → volta a ir 250', (await q(`SELECT public.gorjeta_checkout_mbway_valor('mb3') v`))[0].v === 250);

// Cartão: pedido nasce no servidor já pago com rascunho com gorjeta
await claims('');
await q(`INSERT INTO public.payment_drafts(payment_intent_id, user_id, payload, amount_cents) VALUES ('pi_c1', $1, '{"gorjeta_checkout_cents":150}', 1150)`, [U]);
await q(`INSERT INTO public.orders(id, user_id, service_type, payment_method, payment_status, payment_intent_id, payment_buffer_total) VALUES ('c1', $1, 'storeShopping', 'card', 'paid', 'pi_c1', 10)`, [U]);
t = (await q(`SELECT * FROM public.tips WHERE order_id = 'c1'`))[0];
ok('cartão → succeeded junto 150, líquido 150', t?.status === 'succeeded' && t.cobrada_junto && t.method === 'card' && t.liquido_prestador_cents === 150 && t.stripe_payment_intent_id === 'pi_c1');
// cliente (com sessão) a criar pedido "pago" com o PI do rascunho → não cria gorjeta
await claims(cli);
await q(`INSERT INTO public.payment_drafts(payment_intent_id, user_id, payload, amount_cents) VALUES ('pi_c2', $1, '{"gorjeta_checkout_cents":150}', 1150)`, [U]);
await q(`INSERT INTO public.orders(id, user_id, service_type, payment_method, payment_status, payment_intent_id) VALUES ('c2', $1, 'storeShopping', 'card', 'paid', 'pi_c2')`, [U]);
ok('pedido "pago" criado pelo cliente não cria gorjeta', (await q(`SELECT count(*)::int n FROM public.tips WHERE order_id = 'c2'`))[0].n === 0);

// Rede de segurança: gorjeta de cartão em falta é registada só com o rascunho fechado pelo finalize;
// cancelados enviados à charge-tip
await claims('');
r = (await q(`SELECT public.gorjetas_devolver_cancelados(interval '-1 minute') r`))[0].r;
ok('conferência NÃO regista o pedido "pago" do cliente (rascunho não fechado)', r.cartao_registadas === 0 &&
  (await q(`SELECT count(*)::int n FROM public.tips WHERE order_id = 'c2'`))[0].n === 0, JSON.stringify(r));
// c3: o gatilho não viu o rascunho (simula falha) e o finalize fechou-o com este pedido
await q(`INSERT INTO public.orders(id, user_id, service_type, payment_method, payment_status, payment_intent_id) VALUES ('c3', $1, 'storeShopping', 'card', 'paid', 'pi_c3')`, [U]);
await q(`INSERT INTO public.payment_drafts(payment_intent_id, user_id, payload, amount_cents, used_at, order_id) VALUES ('pi_c3', $1, '{"gorjeta_checkout_cents":120}', 1120, now(), 'c3')`, [U]);
r = (await q(`SELECT public.gorjetas_devolver_cancelados(interval '-1 minute') r`))[0].r;
ok('conferência regista a gorjeta de cartão em falta (c3)', r.cartao_registadas === 1 &&
  (await q(`SELECT status FROM public.tips WHERE order_id = 'c3'`))[0].status === 'succeeded', JSON.stringify(r));
// Cancelamento: MB Way com pagamento criado fica pending (a Stripe decide); sem pagamento → cancelled
await claims(cli);
await q(`SELECT public.client_preparar_gorjeta_checkout(220)`);
await q(`INSERT INTO public.orders(id, user_id, service_type, payment_method, payment_buffer_total) VALUES ('mb4', $1, 'storeShopping', 'mbway', 9)`, [U]);
await q(`SELECT public.gorjeta_checkout_mbway_pi('mb4', 'pi_mb4')`);
await q(`SELECT public.client_preparar_gorjeta_checkout(180)`);
await q(`INSERT INTO public.orders(id, user_id, service_type, payment_method, payment_buffer_total) VALUES ('mb5', $1, 'storeShopping', 'mbway', 9)`, [U]);
await claims('');
await ex(`UPDATE public.orders SET status = 'cancelled', cancelled_at = now() - interval '30 minutes' WHERE id = 'mb4'`);
await ex(`UPDATE public.orders SET status = 'cancelled', cancelled_at = now() WHERE id = 'mb5'`);
ok('cancelado: MB Way com PI fica pending; sem PI → cancelled',
  (await q(`SELECT status FROM public.tips WHERE order_id = 'mb4'`))[0].status === 'pending' &&
  (await q(`SELECT status FROM public.tips WHERE order_id = 'mb5'`))[0].status === 'cancelled');

await ex(`UPDATE public.orders SET status = 'cancelled', cancelled_at = now() WHERE id IN ('c1')`);
await ex(`DELETE FROM net.pedidos`);
r = (await q(`SELECT public.gorjetas_devolver_cancelados(interval '-1 minute') r`))[0].r;
let env = await q(`SELECT body FROM net.pedidos ORDER BY id`);
ok('conferência: cartão pago + MB Way com PI, o mais antigo primeiro (mb4 → c1)', r.pedidos_enviados === 2 &&
  env[0].body.orderId === 'mb4' && env[1].body.orderId === 'c1' && env[1].body.action === 'devolver_cancelamento', JSON.stringify(r));
// 2 tentativas falhadas → a conferência deixa de tentar (sem ciclo)
await ex(`UPDATE public.tips SET devolucao_tentativas = 2 WHERE order_id = 'c1'`);
await ex(`DELETE FROM net.pedidos`);
r = (await q(`SELECT public.gorjetas_devolver_cancelados(interval '-1 minute') r`))[0].r;
env = await q(`SELECT body FROM net.pedidos ORDER BY id`);
ok('com 2 tentativas falhadas não volta a pedir (só mb4)', r.pedidos_enviados === 1 && env[0].body.orderId === 'mb4', JSON.stringify(r));
// aviso ao admin: gorjeta paga em pedido cancelado há mais de 2 h — só na volta em que passa as 2 h
await ex(`UPDATE public.orders SET cancelled_at = now() - interval '2 hours 5 minutes' WHERE id = 'c1'`);
await ex(`DELETE FROM public.avisos`);
r = (await q(`SELECT public.gorjetas_devolver_cancelados(interval '-1 minute') r`))[0].r;
ok('aviso ao admin (pagas há > 2 h)', r.pagas_ha_mais_de_2h === 1 &&
  (await q(`SELECT count(*)::int n FROM public.avisos WHERE tipo = 'tip_refund_overdue'`))[0].n === 1, JSON.stringify(r));
await ex(`UPDATE public.orders SET cancelled_at = now() - interval '3 hours' WHERE id = 'c1'`);
await ex(`DELETE FROM public.avisos`);
r = (await q(`SELECT public.gorjetas_devolver_cancelados(interval '-1 minute') r`))[0].r;
ok('não repete o aviso nas voltas seguintes', r.pagas_ha_mais_de_2h === 0 &&
  (await q(`SELECT count(*)::int n FROM public.avisos`))[0].n === 0, JSON.stringify(r));
ok('crons', (await q(`SELECT count(*)::int n FROM cron.job`))[0].n === 2);
r = (await q(`SELECT public.gorjetas_pedir_taxas_em_falta() r`))[0].r;
ok('taxas_em_falta → pedido http', r.ok === true && (await q(`SELECT body FROM net.pedidos ORDER BY id DESC LIMIT 1`))[0].body.action === 'taxas_em_falta');
ok('sem erros registados nos gatilhos', (await q(`SELECT count(*)::int n FROM public.e2e_log WHERE estado = 'erro'`))[0].n === 0,
  JSON.stringify(await q(`SELECT detalhe FROM public.e2e_log WHERE estado = 'erro'`)));

console.log(`FIM: falhas=${falhas}`);
process.exit(falhas ? 1 : 0);
