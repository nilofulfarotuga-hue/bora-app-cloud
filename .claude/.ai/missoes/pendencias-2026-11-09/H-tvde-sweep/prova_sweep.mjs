// Prova do bloco H (pendencias-2026-11-09): tvde_dispatch_sweep / tvde_offer_to_next
// gravam 'sem_motorista' com a corrida a continuar quando a chamada de reforço TVDE está ligada.
//
// Corre em PGlite (Postgres em WASM), NUNCA em produção: os gatilhos de push chamam
// net.http_post, aqui trocado por uma função falsa que só escreve numa tabela.
// As funções vêm de defs_producao_2026-11-09.json (pg_get_functiondef lido em produção a
// 09/11/2026, só SELECT) e confere-se que o md5 do corpo aqui é o de produção.
//
// Uso: node prova_sweep.mjs <pasta-com-node_modules-do-pglite> <migracao.sql>
import { readFileSync } from 'node:fs';
import { join, dirname } from 'node:path';
import { pathToFileURL, fileURLToPath } from 'node:url';

const [pgliteDir, migPath] = process.argv.slice(2);
if (!pgliteDir || !migPath) throw new Error('uso: node prova_sweep.mjs <pasta-pglite> <migracao.sql>');
const { PGlite } = await import(pathToFileURL(join(pgliteDir, 'node_modules/@electric-sql/pglite/dist/index.js')).href);
const aqui = dirname(fileURLToPath(import.meta.url));
const defs = JSON.parse(readFileSync(join(aqui, 'defs_producao_2026-11-09.json'), 'utf8'));
const migracao = readFileSync(migPath, 'utf8');

const db = new PGlite();
const q = async (sql, p) => (await db.query(sql, p)).rows;
const falhas = [];
const ok = (cond, msg) => { if (!cond) falhas.push(msg); return cond; };

// ── 1) Tabelas (colunas e tipos lidos de produção; só as que estas funções usam) ─────────
await db.exec(`
SET check_function_bodies = off;
CREATE SCHEMA IF NOT EXISTS net; CREATE SCHEMA IF NOT EXISTS extensions;
CREATE TABLE public.platform_settings (key text PRIMARY KEY, value jsonb NOT NULL, description text, category text,
  updated_at timestamptz NOT NULL DEFAULT now(), updated_by uuid, is_secret boolean NOT NULL DEFAULT false);
CREATE TABLE public.tvde_rides (id uuid PRIMARY KEY DEFAULT gen_random_uuid(), driver_id uuid,
  origin_lat double precision NOT NULL, origin_lng double precision NOT NULL,
  dest_lat double precision NOT NULL, dest_lng double precision NOT NULL, cancel_reason text,
  status text NOT NULL DEFAULT 'solicitada', current_offer_driver_id uuid, offer_expires_at timestamptz,
  created_at timestamptz NOT NULL DEFAULT now(), updated_at timestamptz NOT NULL DEFAULT now(),
  tried_driver_ids uuid[] NOT NULL DEFAULT '{}', is_queued boolean NOT NULL DEFAULT false,
  no_driver_since timestamptz, scheduled_at timestamptz, reservation_status text, reservation_driver_id uuid,
  source text NOT NULL DEFAULT 'app', dispatch_hold_reason text, pref_fala_portugues boolean NOT NULL DEFAULT false,
  pede_mobilidade_reduzida boolean NOT NULL DEFAULT false, ride_kind text NOT NULL DEFAULT 'passageiros');
CREATE TABLE public.tvde_ride_events (id uuid PRIMARY KEY DEFAULT gen_random_uuid(), ride_id uuid NOT NULL,
  status text NOT NULL, actor text, meta jsonb, at timestamptz NOT NULL DEFAULT now(), seq bigserial);
CREATE TABLE public.ofertas_prestador_log (id uuid PRIMARY KEY DEFAULT gen_random_uuid(), categoria text NOT NULL,
  booking_id uuid, prestador_id uuid NOT NULL, user_id uuid, nome text, tem_aparelho boolean NOT NULL,
  janela_min integer NOT NULL, oferecida_em timestamptz NOT NULL DEFAULT now(), desfecho text, fechada_em timestamptz,
  pedido_ref text, fase text, estava_online boolean, janela_s integer, push_aparelhos integer, push_enviados integer,
  push_em timestamptz, push_detalhe text, seq bigserial);
CREATE TABLE public.chamada_reforco_consentimento (user_id uuid PRIMARY KEY, ligado boolean NOT NULL DEFAULT false,
  atualizado_em timestamptz NOT NULL DEFAULT now());
CREATE TABLE public.driver_push_tokens (id uuid PRIMARY KEY DEFAULT gen_random_uuid(), user_id uuid NOT NULL,
  fcm_token text NOT NULL, device_label text, platform text, active boolean NOT NULL DEFAULT true,
  fail_count smallint NOT NULL DEFAULT 0, last_fail_at timestamptz, last_used_at timestamptz NOT NULL DEFAULT now(),
  created_at timestamptz NOT NULL DEFAULT now(), updated_at timestamptz NOT NULL DEFAULT now());
CREATE TABLE public.drivers (id uuid PRIMARY KEY DEFAULT gen_random_uuid(), user_id uuid, is_online boolean DEFAULT true,
  vehicle_type text, name text, fcm_token text, approval_status text NOT NULL DEFAULT 'pending',
  is_banned boolean NOT NULL DEFAULT false, banned_until timestamptz, deleted_at timestamptz, last_heartbeat_at timestamptz);
CREATE TABLE public.driver_locations (driver_id uuid NOT NULL, latitude numeric NOT NULL, longitude numeric NOT NULL,
  is_online boolean NOT NULL DEFAULT true, last_updated timestamptz NOT NULL DEFAULT now());
CREATE TABLE public.orders (id text PRIMARY KEY DEFAULT gen_random_uuid()::text, status text, assigned_driver_id text);
CREATE TABLE public.notification_failures (id bigserial PRIMARY KEY, user_id uuid, kind text, source text, erro text,
  created_at timestamptz NOT NULL DEFAULT now());
CREATE TABLE public.e2e_log (id bigserial PRIMARY KEY, fluxo text, passo text, estado text, detalhe text, device text);

-- ── 2) Falsos: o que sai para fora (pg_net) e o que não interessa a esta prova ─────────
CREATE TABLE public._net_chamadas (seq bigserial PRIMARY KEY, url text, body jsonb);
CREATE FUNCTION net.http_post(url text, body jsonb DEFAULT '{}'::jsonb, params jsonb DEFAULT '{}'::jsonb,
  headers jsonb DEFAULT '{}'::jsonb, timeout_milliseconds integer DEFAULT 5000) RETURNS bigint
  LANGUAGE sql AS $$ INSERT INTO public._net_chamadas(url, body) VALUES (url, body) RETURNING seq $$;
CREATE FUNCTION public._dispatch_jwt() RETURNS text LANGUAGE sql AS $$ SELECT 'jwt-falso'::text $$;
CREATE FUNCTION public.aceita_papel(uuid, text) RETURNS boolean LANGUAGE sql AS $$ SELECT true $$;
CREATE FUNCTION public.is_admin() RETURNS boolean LANGUAGE sql AS $$ SELECT false $$;
CREATE FUNCTION public.tvde_reservation_lock_minutes_for(uuid) RETURNS integer LANGUAGE sql AS $$ SELECT 30 $$;
-- Fila inteligente: ligada como em produção, mas com a lista esgotada (NULL) -> o despacho de sempre.
CREATE FUNCTION public._tvde_fila_oferecer(p_ride_id uuid) RETURNS boolean LANGUAGE sql AS $$ SELECT NULL::boolean $$;
CREATE FUNCTION public._tvde_fila_varrimento() RETURNS void LANGUAGE sql AS $$ SELECT $$;
`);

// ── 3) Funções de produção, tal e qual; md5 do corpo tem de bater ─────────────────────
for (const d of defs) await db.exec(d.def);
for (const d of defs) {
  const [r] = await q(`SELECT md5(p.prosrc) AS m FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
                        WHERE n.nspname = 'public' AND p.proname = $1
                          AND pg_get_function_identity_arguments(p.oid) = $2`, [d.nome, d.args]);
  ok(r && r.m === d.md5_src, `md5 de ${d.nome}(${d.args}) no PGlite ${r && r.m} <> produção ${d.md5_src}`);
}

// Gatilhos de produção que tocam nesta prova (os de dinheiro/tokens não: nenhum UPDATE muda).
await db.exec(`
CREATE TRIGGER _aa_tvde_chamada_de_reforco BEFORE UPDATE OF status ON public.tvde_rides FOR EACH ROW
  WHEN ((old.status = 'solicitada'::text) AND (new.status = 'sem_motorista'::text)) EXECUTE FUNCTION _tvde_chamada_de_reforco();
CREATE TRIGGER tr_notify_tvde_client_on_status AFTER UPDATE OF status ON public.tvde_rides FOR EACH ROW EXECUTE FUNCTION fn_notify_tvde_client_on_status();
CREATE TRIGGER tr_notify_tvde_driver_on_offer AFTER UPDATE OF current_offer_driver_id ON public.tvde_rides FOR EACH ROW EXECUTE FUNCTION fn_notify_tvde_driver_on_offer();
CREATE TRIGGER trg_registar_oferta_tvde AFTER UPDATE OF current_offer_driver_id, status ON public.tvde_rides FOR EACH ROW
  WHEN ((old.current_offer_driver_id IS NOT NULL) OR (new.current_offer_driver_id IS NOT NULL)) EXECUTE FUNCTION _registar_oferta_tvde();
`);

// Interruptores: valores de produção a 09/11 (tvde_forcado_ligado muda por cenário).
// Horário do reforço: produção 08:00-03:00; aqui o dia todo para a prova não depender da hora.
const U = { ON: '00000000-0000-0000-0000-0000000000a1', REF: '00000000-0000-0000-0000-0000000000f1',
            REF2: '00000000-0000-0000-0000-0000000000f2', X: '00000000-0000-0000-0000-0000000000b1' };
await db.exec(`
INSERT INTO public.platform_settings(key, value) VALUES
 ('tvde_forcado_ligado','false'), ('tvde_forcado_tentativas','2'), ('tvde_forcado_prioridade','["${U.REF}"]'),
 ('dispatch_forcado_max_por_dia','3'), ('dispatch_forcado_visto_horas','168'),
 ('dispatch_forcado_horario_inicio','"00:00"'), ('dispatch_forcado_horario_fim','"23:59:59"'),
 ('tvde_fila_inteligente_enabled','true'), ('tvde_offer_ttl_seconds','40'), ('tvde_heartbeat_window_seconds','600'),
 ('tvde_retry_window_seconds','120'), ('tvde_reoffer_pause_seconds','35'), ('tvde_procura_max_minutos','6'),
 ('dispatch_gps_fresh_seconds','900'), ('tvde_backtoback_enabled','true');
`);

// ── 4) Cenários (cada um numa transação desfeita no fim) ───────────────────────────────
const RIDE = '00000000-0000-0000-0000-00000000c0d1';
const nomes = Object.fromEntries(Object.entries(U).map(([k, v]) => [v, k]));
const rot = (s) => s == null ? s : String(s).replace(/[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}/g,
  (m) => nomes[m] || (m === RIDE ? 'RIDE' : m));

const cenarios = [
  { id: 'S1', txt: 'procura esgotada (6 min), reforço LIGADO, há motorista que consentiu',
    reforco: true, consent: [U.REF], online: [], oferta_ha_min: 7, sem_motorista_ha_s: 60, espera: 'continua' },
  { id: 'S2', txt: 'procura esgotada (6 min), reforço LIGADO, ninguém consentiu',
    reforco: true, consent: [], online: [], oferta_ha_min: 7, sem_motorista_ha_s: 60, espera: 'acaba' },
  { id: 'S3', txt: 'procura esgotada (6 min), reforço DESLIGADO (como hoje)',
    reforco: false, consent: [U.REF], online: [], oferta_ha_min: 7, sem_motorista_ha_s: 60, espera: 'acaba' },
  { id: 'S4', txt: 'sem candidatos há 150 s (tvde_offer_to_next), reforço LIGADO, há quem consentiu',
    reforco: true, consent: [U.REF], online: [], oferta_ha_min: null, sem_motorista_ha_s: 150, espera: 'continua' },
  { id: 'S5', txt: 'sem candidatos há 150 s, reforço LIGADO mas as 2 tentativas já foram gastas',
    reforco: true, consent: [U.REF], online: [], oferta_ha_min: null, sem_motorista_ha_s: 150, gastas: [U.REF, U.REF2], espera: 'acaba' },
  { id: 'S6', txt: 'sem candidatos há 150 s, reforço DESLIGADO (como hoje)',
    reforco: false, consent: [U.REF], online: [], oferta_ha_min: null, sem_motorista_ha_s: 150, espera: 'acaba' },
  { id: 'S7', txt: 'oferta a X expirou e há um motorista online (rotação normal), reforço LIGADO',
    reforco: true, consent: [U.REF], online: [U.ON], oferta_ha_min: 1, oferta_expirada_a: U.X, sem_motorista_ha_s: null, espera: 'oferta_online' },
];

async function correrCenario(c) {
  await db.exec('BEGIN');
  try {
    await q(`UPDATE public.platform_settings SET value = to_jsonb($1::boolean) WHERE key = 'tvde_forcado_ligado'`, [c.reforco]);
    // Motoristas
    for (const uid of [U.ON, U.REF, U.REF2, U.X]) {
      const online = c.online.includes(uid);
      await q(`INSERT INTO public.drivers(user_id, name, vehicle_type, approval_status, is_online, last_heartbeat_at, fcm_token)
               VALUES ($1, $2, 'carro_passageiros', 'approved', $3, CASE WHEN $3 THEN now() ELSE now() - interval '2 hours' END, 'tok-' || $2)`,
        [uid, nomes[uid], online]);
      if (online) await q(`INSERT INTO public.driver_locations(driver_id, latitude, longitude, is_online, last_updated)
                           VALUES ($1, 40.5372, -7.2676, true, now())`, [uid]);
    }
    for (const uid of c.consent) await q(`INSERT INTO public.chamada_reforco_consentimento(user_id, ligado) VALUES ($1, true)`, [uid]);
    // Corrida
    await q(`INSERT INTO public.tvde_rides(id, origin_lat, origin_lng, dest_lat, dest_lng, status, created_at,
               current_offer_driver_id, offer_expires_at, no_driver_since, tried_driver_ids)
             VALUES ($1, 40.5373, -7.2680, 40.5500, -7.2500, 'solicitada', now() - interval '9 minutes',
               $2::uuid, CASE WHEN $2::uuid IS NULL THEN NULL ELSE now() - interval '5 seconds' END,
               CASE WHEN $3::int IS NULL THEN NULL ELSE now() - make_interval(secs => $3::int) END,
               CASE WHEN $2::uuid IS NULL THEN '{}'::uuid[] ELSE '{}'::uuid[] END)`,
      [RIDE, c.oferta_expirada_a || null, c.sem_motorista_ha_s]);
    if (c.oferta_ha_min != null)
      await q(`INSERT INTO public.tvde_ride_events(ride_id, status, actor, meta, at)
               VALUES ($1, 'oferta', 'system', jsonb_build_object('driver_id', $2::text), now() - make_interval(mins => $3::int))`,
        [RIDE, c.oferta_expirada_a || U.X, c.oferta_ha_min]);
    for (const uid of (c.gastas || []))
      await q(`INSERT INTO public.ofertas_prestador_log(categoria, booking_id, prestador_id, user_id, tem_aparelho, janela_min, fase, desfecho, oferecida_em)
               VALUES ('tvde', $1, gen_random_uuid(), $2, true, 1, 'forcado', 'expirou', now() - interval '3 minutes')`, [RIDE, uid]);
    const [{ ev0 }] = await q(`SELECT count(*)::int AS ev0 FROM public.tvde_ride_events`);
    const [{ lg0 }] = await q(`SELECT count(*)::int AS lg0 FROM public.ofertas_prestador_log`);

    await q(`SELECT public.tvde_dispatch_sweep()`);

    const [r] = await q(`SELECT status, cancel_reason, current_offer_driver_id::text AS oferta_a,
                                offer_expires_at IS NOT NULL AS com_prazo, no_driver_since IS NOT NULL AS com_no_driver_since,
                                tried_driver_ids::text AS tentados FROM public.tvde_rides WHERE id = $1`, [RIDE]);
    const ev = await q(`SELECT status, actor, meta FROM public.tvde_ride_events ORDER BY seq OFFSET $1`, [ev0]);
    const lg = await q(`SELECT user_id::text AS quem, fase, desfecho FROM public.ofertas_prestador_log ORDER BY seq OFFSET $1`, [lg0]);
    const lgFech = await q(`SELECT user_id::text AS quem, desfecho FROM public.ofertas_prestador_log ORDER BY seq LIMIT $1`, [lg0]);
    const net = await q(`SELECT regexp_replace(url, '^.*/functions/v1/', '') AS edge, body FROM public._net_chamadas ORDER BY seq`);
    return JSON.parse(rot(JSON.stringify({ corrida: r, eventos_novos: ev, registo_ofertas_novo: lg,
                                          registo_ofertas_antigo: lgFech, pushes: net })));
  } finally {
    await db.exec('ROLLBACK');
  }
}

const semEvSM = (s) => ({ ...s, eventos_novos: s.eventos_novos.filter((e) => e.status !== 'sem_motorista') });
const conta = (s) => s.eventos_novos.filter((e) => e.status === 'sem_motorista').length;

const antes = {};
for (const c of cenarios) antes[c.id] = await correrCenario(c);

// ── 5) Aplica a migração (o ficheiro do repo, tal e qual) — 2 vezes = idempotente ────
const md5Antes = await q(`SELECT proname, md5(prosrc) AS m FROM pg_proc WHERE proname IN ('tvde_dispatch_sweep','tvde_offer_to_next') ORDER BY 1`);
await db.exec(migracao);
const md5Depois = await q(`SELECT proname, md5(prosrc) AS m, position('2026-11-09 (H)' IN prosrc) > 0 AS marca,
                                  prosecdef, proconfig::text AS cfg FROM pg_proc WHERE proname IN ('tvde_dispatch_sweep','tvde_offer_to_next') ORDER BY 1`);
await db.exec(migracao);
const md5Repetida = await q(`SELECT proname, md5(prosrc) AS m FROM pg_proc WHERE proname IN ('tvde_dispatch_sweep','tvde_offer_to_next') ORDER BY 1`);
ok(JSON.stringify(md5Depois.map((x) => x.m)) === JSON.stringify(md5Repetida.map((x) => x.m)), 'migração não é idempotente');
ok(md5Depois.every((x) => x.marca && x.prosecdef && x.cfg === '{search_path=public}'), 'atributos/marca em falta depois da migração');
// Ficheiro com CRLF (checkout Windows) também passa (já aplicada -> nada a fazer, sem erro)
await db.exec(migracao.replace(/\r?\n/g, '\r\n'));

// Guarda: se a função no ar tiver mudado, a migração aborta e não toca em nada.
let guarda = 'nao_abortou';
await db.exec('BEGIN');
try {
  const [{ def }] = await q(`SELECT pg_get_functiondef('public.tvde_offer_to_next(uuid)'::regprocedure) AS def`);
  const orig = defs.find((d) => d.nome === 'tvde_offer_to_next').def;
  await db.exec(orig.replace('BEGIN\n  SELECT * INTO v_ride', 'BEGIN\n  -- mudança de outra pessoa\n  SELECT * INTO v_ride'));
  await db.exec(migracao);
} catch (e) { guarda = 'abortou: ' + String(e.message).slice(0, 110); }
await db.exec('ROLLBACK');
ok(guarda.startsWith('abortou') && guarda.includes('mudou desde 09/11'), 'guarda md5 não abortou: ' + guarda);

const depois = {};
for (const c of cenarios) depois[c.id] = await correrCenario(c);

// ── 6) Comparação ────────────────────────────────────────────────────────────────────
const linhas = [];
linhas.push(`md5 das 14 funções no PGlite = produção: ${falhas.filter((f) => f.startsWith('md5 de')).length === 0 ? 'SIM' : 'NAO'}`);
linhas.push(`migração: ${md5Antes.map((x) => x.proname + ' ' + x.m.slice(0, 8)).join(', ')} -> ${md5Depois.map((x) => x.proname + ' ' + x.m.slice(0, 8)).join(', ')}; 2.a vez igual; CRLF ok; guarda md5: ${guarda.slice(0, 60)}`);
for (const c of cenarios) {
  const a = antes[c.id], d = depois[c.id];
  const igualResto = JSON.stringify(semEvSM(a)) === JSON.stringify(semEvSM(d));
  const nA = conta(a), nD = conta(d);
  const estado = `${d.corrida.status}${d.corrida.oferta_a ? ' oferta=' + d.corrida.oferta_a : ''}`;
  const fases = d.registo_ofertas_novo.map((l) => `${l.quem}:${l.fase}`).join(',') || '-';
  const pushes = d.pushes.map((p) => `${p.edge}${p.body.driverId ? '>' + p.body.driverId : ''}${p.body.status ? '/' + p.body.status : ''}`).join(',') || '-';
  ok(igualResto, `${c.id}: alguma coisa além do evento sem_motorista mudou`);
  if (c.espera === 'continua') {
    ok(a.corrida.status === 'solicitada' && nA === 1, `${c.id}: ANTES devia ter o defeito (solicitada + 1 evento sem_motorista), teve ${a.corrida.status}/${nA}`);
    ok(d.corrida.status === 'solicitada' && nD === 0, `${c.id}: DEPOIS não devia gravar sem_motorista, gravou ${nD}`);
    ok(d.corrida.oferta_a === 'REF', `${c.id}: a oferta de reforço devia ir ao REF, foi a ${d.corrida.oferta_a}`);
  } else if (c.espera === 'acaba') {
    ok(a.corrida.status === 'sem_motorista' && nA === 1 && d.corrida.status === 'sem_motorista' && nD === 1,
      `${c.id}: devia acabar sem_motorista com 1 evento antes e depois (${a.corrida.status}/${nA} -> ${d.corrida.status}/${nD})`);
  } else {
    ok(nA === 0 && nD === 0 && d.corrida.oferta_a === 'ON', `${c.id}: rotação normal devia oferecer ao ON sem sem_motorista`);
  }
  linhas.push(`${c.id} ${c.txt}\n     corrida=${estado} | eventos sem_motorista antes=${nA} depois=${nD} | resto igual=${igualResto ? 'SIM' : 'NAO'}` +
              ` | registo de ofertas=${fases} | pushes=${pushes}`);
}
console.log(linhas.join('\n'));
console.log(falhas.length ? 'PROVA_FALHOU\n - ' + falhas.join('\n - ') : 'PROVA_OK');
if (process.env.DETALHE) console.log(JSON.stringify({ antes, depois }, null, 1));
await db.close();
process.exit(falhas.length ? 1 : 0);
