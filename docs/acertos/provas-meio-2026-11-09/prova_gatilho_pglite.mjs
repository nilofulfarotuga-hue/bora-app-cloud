// Prova local (PGlite = Postgres em WASM) do gatilho _settlement_receipt_enqueue com o meio.
// Missão pendencias-2026-11-09, Bloco B. Não toca em produção.
//
// Uso: node prova_gatilho_pglite.mjs <pasta do pacote @electric-sql/pglite> <repo>
//
// 1. Cria um esqueleto das tabelas (só as colunas que o gatilho lê) e troca net.http_post
//    por uma tabela que conta as chamadas — assim prova-se que o gatilho só ENFILEIRA um
//    pedido à Edge (não manda email nem push ele próprio).
// 2. Corre a migração antiga (20260907000353) e mostra que, com a função antiga, o meio NÃO
//    chega à fila (tem de falhar — senão a prova não prova nada).
// 3. Corre a migração nova duas vezes (idempotente) e repete os casos: agora o meio chega.
import { readFileSync } from 'node:fs'
import { pathToFileURL } from 'node:url'
import { join } from 'node:path'

const [pglitePasta, repo] = process.argv.slice(2)
const { PGlite } = await import(pathToFileURL(join(pglitePasta, 'dist', 'index.js')).href)
const db = new PGlite()
// (a migração de 07/09 começa com BOM; o Postgres não o aceita)
const mig = (n) => readFileSync(join(repo, 'supabase', 'migrations', n), 'utf8').replace(/^﻿/, '')
process.on('unhandledRejection', (e) => { console.log('ERRO: ' + (e?.message ?? e) + (e?.where ? ' @ ' + e.where : '')); process.exit(2) })

await db.exec(`
  CREATE ROLE anon; CREATE ROLE authenticated; CREATE ROLE service_role;
  CREATE SCHEMA net; CREATE SCHEMA vault;
  CREATE TABLE net.chamadas (id serial primary key, url text, body jsonb);
  CREATE FUNCTION net.http_post(url text, headers jsonb, body jsonb) RETURNS bigint
    LANGUAGE sql AS $$ INSERT INTO net.chamadas(url, body) VALUES (url, body) RETURNING id::bigint $$;
  CREATE TABLE vault.decrypted_secrets (name text, decrypted_secret text);
  INSERT INTO vault.decrypted_secrets VALUES ('project_url','https://falso.local'), ('service_role_key','chave-falsa');
  CREATE FUNCTION public.is_admin() RETURNS boolean LANGUAGE sql AS 'select true';
  CREATE TABLE public.admin_audit_log (action text, entity_type text, entity_id_text text, details jsonb);
  CREATE TABLE public.weekly_digest_log (subject_type text, subject_id text, week_start_at timestamptz,
    subject_name text, subject_email text, net_cents int);
  CREATE TABLE public.driver_weekly_settlements (driver_id uuid, week_start_at timestamptz, status text,
    payment_method text DEFAULT 'mbway', payment_reference text);
  CREATE TABLE public.partner_weekly_settlements (partner_id text, week_start_at timestamptz, status text,
    payment_reference text);
  CREATE TABLE public.cleaner_weekly_settlements (cleaner_id uuid, week_start_at timestamptz, status text,
    payment_method text, payment_reference text);
  CREATE TABLE public.washer_weekly_settlements (washer_id uuid, week_start_at timestamptz, status text,
    payment_method text, payment_reference text);
  CREATE TABLE public.appointment_payouts (provider_id text, week_start_at timestamptz, status text,
    payment_method text, payment_reference text);
`)

const WS = '2026-11-02 00:00:00+00'
const D = '11111111-1111-1111-1111-111111111111'
const C = '22222222-2222-2222-2222-222222222222'
const W = '33333333-3333-3333-3333-333333333333'

async function semear() {
  await db.exec(`
    DELETE FROM public.settlement_receipts; DELETE FROM net.chamadas; DELETE FROM public.admin_audit_log;
    DELETE FROM public.weekly_digest_log; DELETE FROM public.driver_weekly_settlements;
    DELETE FROM public.partner_weekly_settlements; DELETE FROM public.cleaner_weekly_settlements;
    DELETE FROM public.washer_weekly_settlements; DELETE FROM public.appointment_payouts;
    INSERT INTO public.weekly_digest_log VALUES
      ('partner','boom-burger-guarda','${WS}','Boom! Burger','boom@exemplo.pt',1360),
      ('driver','${D}','${WS}','Estafeta','e@exemplo.pt',3213),
      ('cleaner','${C}','${WS}','Limpeza','l@exemplo.pt',2000),
      ('washer','${W}','${WS}','Lavador','w@exemplo.pt',-500),
      ('provider','barbearia-x','${WS}','Barbearia','b@exemplo.pt',900);
    INSERT INTO public.partner_weekly_settlements VALUES ('boom-burger-guarda','${WS}','closed',null);
    INSERT INTO public.driver_weekly_settlements (driver_id, week_start_at, status) VALUES ('${D}','${WS}','closed');
    INSERT INTO public.cleaner_weekly_settlements VALUES ('${C}','${WS}','pending',null,null);
    INSERT INTO public.washer_weekly_settlements VALUES ('${W}','${WS}','pending',null,null);
    INSERT INTO public.appointment_payouts VALUES ('barbearia-x','${WS}','pending',null,null);
  `)
}

// O que o painel faz ao marcar: status + payment_reference no MESMO UPDATE (admin_set_settlement_state).
async function marcar() {
  await db.exec(`
    UPDATE public.partner_weekly_settlements SET status='paid', payment_reference='Transferência bancária 09/11/2026' WHERE partner_id='boom-burger-guarda';
    UPDATE public.driver_weekly_settlements SET status='paid', payment_reference='MB Way 910000001' WHERE driver_id='${D}';
    UPDATE public.cleaner_weekly_settlements SET status='paid' WHERE cleaner_id='${C}';
    UPDATE public.washer_weekly_settlements SET status='received', payment_reference='   ' WHERE washer_id='${W}';
    UPDATE public.appointment_payouts SET status='paid', payment_reference='Stripe' WHERE provider_id='barbearia-x';
  `)
}

async function fila(titulo) {
  const r = await db.query(`SELECT subject_type, kind, subject_name, amount_cents,
      ${titulo.includes('ANTIGA') ? "NULL::text AS payment_reference_na_fila" : 'payment_reference AS payment_reference_na_fila'}
    FROM public.settlement_receipts ORDER BY subject_type`)
  const n = await db.query(`SELECT count(*)::int n FROM net.chamadas`)
  const erros = await db.query(`SELECT action, details FROM public.admin_audit_log`)
  console.log('--- ' + titulo)
  for (const l of r.rows) console.log('  ' + JSON.stringify(l))
  console.log('  pedidos enfileirados à Edge (net.http_post): ' + n.rows[0].n)
  console.log('  erros registados pelo gatilho: ' + erros.rows.length + (erros.rows.length ? ' ' + JSON.stringify(erros.rows) : ''))
  return r.rows
}

// 1) Função ANTIGA (migração de 07/09).
await db.exec(mig('20260907000353_comprovativo_automatico_de_acerto.sql'))
await semear(); await marcar()
const antes = await fila('FUNÇÃO ANTIGA (20260907000353) — a fila não tem onde guardar o meio')
const colAntes = await db.query(`SELECT count(*)::int n FROM information_schema.columns WHERE table_name='settlement_receipts' AND column_name='payment_reference'`)
console.log('  coluna settlement_receipts.payment_reference existe? ' + (colAntes.rows[0].n === 1))

// 2) Migração NOVA, duas vezes (idempotente).
await db.exec(mig('20261109213000_comprovativo_meio_pagamento.sql'))
await db.exec(mig('20261109213000_comprovativo_meio_pagamento.sql'))
console.log('migração nova aplicada 2x sem erro (idempotente)')
await semear(); await marcar()
const depois = await fila('FUNÇÃO NOVA (20261109213000)')

// 3) Mudar só a referência (status igual) não cria outro comprovativo; repetir pago também não.
await db.exec(`UPDATE public.partner_weekly_settlements SET payment_reference='outra coisa' WHERE partner_id='boom-burger-guarda'`)
await db.exec(`UPDATE public.partner_weekly_settlements SET status='closed' WHERE partner_id='boom-burger-guarda'`)
await db.exec(`UPDATE public.partner_weekly_settlements SET status='paid' WHERE partner_id='boom-burger-guarda'`)
const nBoom = await db.query(`SELECT count(*)::int n, max(payment_reference) ref FROM public.settlement_receipts WHERE subject_id='boom-burger-guarda'`)
console.log('Boom depois de mudar só a referência e de voltar a pagar: ' + JSON.stringify(nBoom.rows[0]) + ' (tem de ser 1 linha, a referência original)')

// Veredicto
const esperado = {
  partner: 'Transferência bancária 09/11/2026', driver: 'MB Way 910000001',
  cleaner: null, washer: null, provider: 'Stripe',
}
let ok = depois.length === 5 && nBoom.rows[0].n === 1 && nBoom.rows[0].ref === esperado.partner
for (const l of depois) if (l.payment_reference_na_fila !== esperado[l.subject_type]) ok = false
const antigaFalha = antes.every((l) => l.payment_reference_na_fila == null) && colAntes.rows[0].n === 0
console.log('VEREDICTO função antiga sem meio (tem de ser true): ' + antigaFalha)
console.log('VEREDICTO função nova copia o meio certo nos 5 papéis (tem de ser true): ' + ok)
process.exit(ok && antigaFalha ? 0 : 1)
