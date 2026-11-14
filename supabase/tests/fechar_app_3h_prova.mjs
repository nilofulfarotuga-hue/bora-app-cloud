// Prova local (PGlite) da migração
// 20261115020100_cron_desencontrar_minutos_redondos.sql — fechar-app-15-11, Bloco 3 (h).
//
// O PGlite não tem pg_cron. Monta-se aqui um `cron.job` com as tarefas TAL
// COMO ESTAVAM em produção a 14/11/2026 (jobid, horário, nome, ligada) e um
// `cron.alter_job` com a assinatura do verdadeiro. Aplica-se a migração como
// está e conta-se, minuto a minuto de um mês inteiro, quantas tarefas arrancam
// no mesmo segundo — antes e depois.
//
// Uso: node supabase/tests/fechar_app_3h_prova.mjs <pasta-com-node_modules-do-pglite>
//
// Teste anti-mentira: MUTACAO="texto=>outro" estraga a migração; a prova TEM
// de falhar. Dois estragos que ela apanha:
//   MUTACAO="'9-59/30 * * * *'=>'*/30 * * * *'"            (não desencontra nada)
//   MUTACAO="'produtos-esgotados-voltam'=>'payments-reconciler-cobrancas'"  (mexe em dinheiro)

import { readFileSync } from 'node:fs';
import { createRequire } from 'node:module';
import path from 'node:path';
import { fileURLToPath, pathToFileURL } from 'node:url';

const aqui = path.dirname(fileURLToPath(import.meta.url));
const pastaPglite = process.argv[2];
if (!pastaPglite) {
  console.error('falta a pasta do pglite');
  process.exit(2);
}
const require = createRequire(path.join(path.resolve(pastaPglite), 'x.js'));
const { PGlite } = await import(pathToFileURL(require.resolve('@electric-sql/pglite')).href);

let migracao = readFileSync(
  path.join(aqui, '..', 'migrations', '20261115020100_cron_desencontrar_minutos_redondos.sql'), 'utf8',
).replace(/\r\n/g, '\n');
if (process.env.MUTACAO) {
  const [de, para] = process.env.MUTACAO.split('=>');
  if (!migracao.includes(de)) throw new Error(`mutação não encontrada: ${de}`);
  migracao = migracao.split(de).join(para);
  console.log(`MUTAÇÃO aplicada: ${de} => ${para}`);
}

// ── cron.job de produção, 14/11/2026 (select jobid, schedule, jobname, active) ──
// [jobid, horário, nome, ligada]
const TAREFAS = [
  [65, '* * * * *', 'tvde-reservations-sweep', true],
  [81, '* * * * *', 'mover-pedidos-demo', true],
  [85, '* * * * *', 'drivers-heartbeat-expire', true],
  [95, '* * * * *', 'encomendas-telefone-relogio', true],
  [99, '* * * * *', 'tvde-roundtrip-orfaos', true],
  [104, '* * * * *', 'cleaning-offer-reping', true],
  [112, '* * * * *', 'agendados-nao-parceiros', true],
  [119, '* * * * *', 'casa_tick', true],
  [134, '* * * * *', 'farmacias-prescricao-vigiar', true],
  [55, '*/10 * * * *', 'tvde_expire_roundtrip_credits', true],
  [62, '*/10 * * * *', 'tvde-sweep-abandoned-payments', true],
  [71, '*/10 * * * *', 'appt-expire-pending-payment', true],
  [83, '*/10 * * * *', 'preencher-custos-corridas', true],
  [101, '*/10 * * * *', 'produtos-esgotados-voltam', true],
  [103, '*/10 * * * *', 'payments-reconciler-cobrancas', true],
  [132, '*/10 * * * *', 'restaurante-do-dia', true],
  [31, '*/15 * * * *', 'reservas_pro_reminders_2h', true],
  [42, '*/15 * * * *', 'appt-auto-noshow', true],
  [57, '*/15 * * * *', 'auto-approve-safe-suggestions', true],
  [76, '*/15 * * * *', 'settlement-receipts-retry', true],
  [100, '*/15 * * * *', 'carrinhos-abandonados-15min', true],
  [122, '*/15 * * * *', 'gorjetas-devolver-cancelados', true],
  [66, '*/2 * * * *', 'carwash-offer-timeout', true],
  [67, '*/2 * * * *', 'carwash-retry-unoffered', true],
  [93, '*/2 * * * *', 'tvde-dest-change-sweep', true],
  [109, '*/2 * * * *', 'drivers-sem-sinal-avisar', true],
  [128, '*/2 * * * *', 'embeddings-gte-manter', true],
  [30, '*/30 * * * *', 'reservas_pro_reminders_24h', true],
  [41, '*/30 * * * *', 'appt-reminders-2h', true],
  [49, '*/30 * * * *', 'cleaning-auto-confirm', true],
  [51, '*/30 * * * *', 'cleaning-reminders-2h', true],
  [48, '*/5 * * * *', 'cleaning-offer-timeout', true],
  [54, '*/5 * * * *', 'cleaning-expire-no-cleaner', true],
  [73, '*/5 * * * *', 'check-orphan-orders', true],
  [91, '*/5 * * * *', 'tvde-work-log-sweep', true],
  [115, '*/5 * * * *', 'vigia_pago_sem_pedido', true],
  [23, '0 * * * *', 'auto_close_no_show_reservations', true],
  [34, '0 * * * *', 'reservas_pro_expire_lists', true],
  [75, '0 * * * *', 'settlement-debt-reminders', true],
  [40, '0 10 * * *', 'appt-reminders-24h', true],
  [123, '0 22,23 * * 0', 'gorjetas-taxas-em-falta-domingo', true],
  [29, '0 3 * * *', 'auto-archive-old-suggestions', true],
  [20, '0 3 * * 1', 'update-products-continente', true],
  [21, '0 3 * * 2', 'update-products-auchan', true],
  [28, '0 4 * * 1', 'analyze-conversations-weekly', true],
  [92, '0 6 1 * *', 'tvde-amt-mensal', true],
  [74, '0 7 * * *', 'check-orphan-ledger', true],
  [116, '0 7 * * *', 'saude_chaves_funcoes', true],
  [125, '0 7,8 1 * *', 'fecho-mensal-contabilista', true],
  [33, '0 8 * * *', 'reservas_pro_morning_summary', true],
  [52, '0 8 * * *', 'cleaning-generate-recurring', true],
  [82, '0 8 * * *', 'assinaturas-aviso-renovacao', true],
  [87, '0 8 * * *', 'motorista-docs-alerta-diario', true],
  [88, '0 8,9 1 * *', 'monthly-partner-statement', true],
  [89, '0 8,9 10 * *', 'aviso-recibos-estafetas', true],
  [27, '0 9 * * *', 'wallet_overdue_alerts', true],
  [135, '0 9 * * *', 'farmacias-lembretes-mensais', true],
  [110, '0 9,10 * * *', 'robo-documentos-lembretes', true],
  [121, '0 9,10 * * *', 'robo-documentos-avisos', true],
  [97, '1-59/2 * * * *', 'execute-broadcast-queue', true],
  [84, '10 6 * * *', 'vigia-dinheiro-diario', true],
  [59, '15 * * * *', 'cleaning-stuck-in-progress-alert', true],
  [90, '15 7 * * *', 'tvde-conformidade-diaria', true],
  [47, '15 seconds', 'tvde_dispatch_sweep', true],
  [53, '15 seconds', 'bora_dispatch_maintenance', true],
  [133, '15 seconds', 'dispatch_fases_sweep', true],
  [96, '17 * * * *', 'secretario-expirar', true],
  [108, '17 * * * *', 'checkin-premios-manutencao', true],
  [129, '17 * * * *', 'embeddings-gemini-novos', true],
  [70, '17 4 * * *', 'limpa_web_health_events_30d', true],
  [94, '17 4 * * *', 'limpar-historico-cron', true],
  [45, '18 8 * * 1', 'robot-b-weekly-digest', true],
  [105, '2 * * * *', 'checkin-lembretes', true],
  [68, '20 * * * *', 'carwash-stuck-alert', true],
  [107, '20 * * * *', 'cleaning-unpaid-retry', true],
  [63, '20 0 * * 1', 'weekly-closeout-digest', true],
  [120, '20 4 * * 1', 'casa_acertos_semanais', true],
  [118, '20 7 * * *', 'saude_chaves_verificar_tarde', true],
  [124, '23 * * * *', 'prestador-suspensoes-manutencao', true],
  [131, '23 * * * *', 'amigo-bora-perfis', true],
  [32, '3-59/5 * * * *', 'reservas_pro_pending_alert', true],
  [77, '30 0 * * 1', 'driver-debt-marks', true],
  [130, '30 2,3 * * *', 'taloes-copia-diaria', true],
  [72, '30 seconds', 'partner-auto-dispatch', true],
  [86, '30 seconds', 'decisor-varrer', true],
  [106, '4 * * * *', 'receita-do-dia-avisos', true],
  [136, '40 3 * * *', 'farmacias-prescricoes-limpeza', true],
  [60, '45 5 * * *', 'payments-reconciler-daily', true],
  [50, '5 * * * *', 'cleaning-reminders-24h', true],
  [26, '5 0 * * 1', 'close-weekly-settlements', true],
  [24, '5-59/15 * * * *', 'cleanup_payment_drafts', true],
  [117, '6 * * * *', 'saude_chaves_verificar', true],
  [35, '7 * * * *', 'robot-b-hourly', true],
  [80, '7 * * * *', 'repor-demo-apagar', true],
  [102, '7 17 * * *', 'reativacao-clientes-parados', true],
  [127, '* * * * *', 'emb-prova-regua-gemini-20261103', false],
  [2, '0 3 * * 1', 'bora_weekly_auto_payout', false],
  [43, '5 0 * * 1', 'appt-weekly-payout', false],
  [58, '5 0 * * 1', 'cleaning-weekly-settlement', false],
  [69, '5 0 * * 1', 'carwash-weekly-settlement', false],
];

// O que a migração promete mexer — e só isto.
const PLANO = {
  'embeddings-gte-manter': ['*/2 * * * *', '1-59/2 * * * *'],
  'drivers-sem-sinal-avisar': ['*/2 * * * *', '1-59/2 * * * *'],
  'tvde-work-log-sweep': ['*/5 * * * *', '1-59/5 * * * *'],
  'produtos-esgotados-voltam': ['*/10 * * * *', '4-59/10 * * * *'],
  'reservas_pro_reminders_2h': ['*/15 * * * *', '7-59/15 * * * *'],
  'carrinhos-abandonados-15min': ['*/15 * * * *', '7-59/15 * * * *'],
  'reservas_pro_reminders_24h': ['*/30 * * * *', '9-59/30 * * * *'],
  'appt-reminders-2h': ['*/30 * * * *', '9-59/30 * * * *'],
  'cleaning-reminders-2h': ['*/30 * * * *', '9-59/30 * * * *'],
  'reservas_pro_expire_lists': ['0 * * * *', '11 * * * *'],
};

// Tarefas dos minutos redondos em que a função toca em dinheiro ou em
// despacho/ofertas (lido de pg_proc.prosrc a 14/11). NENHUMA pode mudar aqui.
const DINHEIRO_OU_DESPACHO = [
  'tvde-reservations-sweep', 'mover-pedidos-demo', 'drivers-heartbeat-expire',
  'encomendas-telefone-relogio', 'tvde-roundtrip-orfaos', 'cleaning-offer-reping',
  'agendados-nao-parceiros', 'casa_tick',
  'carwash-offer-timeout', 'carwash-retry-unoffered', 'tvde-dest-change-sweep',
  'cleaning-offer-timeout', 'cleaning-expire-no-cleaner', 'check-orphan-orders', 'vigia_pago_sem_pedido',
  'tvde_expire_roundtrip_credits', 'tvde-sweep-abandoned-payments', 'appt-expire-pending-payment',
  'preencher-custos-corridas', 'payments-reconciler-cobrancas', 'restaurante-do-dia',
  'appt-auto-noshow', 'auto-approve-safe-suggestions', 'settlement-receipts-retry',
  'gorjetas-devolver-cancelados', 'cleaning-auto-confirm',
  'auto_close_no_show_reservations', 'settlement-debt-reminders',
  'tvde_dispatch_sweep', 'bora_dispatch_maintenance', 'dispatch_fases_sweep',
  'partner-auto-dispatch', 'decisor-varrer',
];

// A segunda metade (PROPOSTA, não aplicada por esta migração): 12 tarefas
// que tocam em dinheiro e hoje correm de 5 em 5, de 10 em 10 e de 15 em 15.
// Só se simula a conta; a tabela é a de docs/propostas/fechar-app-15-11/3deh-servidor.md.
const PROPOSTA = {
  'check-orphan-orders': '4-59/5 * * * *',
  'vigia_pago_sem_pedido': '4-59/5 * * * *',
  'tvde_expire_roundtrip_credits': '2-59/10 * * * *',
  'tvde-sweep-abandoned-payments': '2-59/10 * * * *',
  'appt-expire-pending-payment': '2-59/10 * * * *',
  'preencher-custos-corridas': '6-59/10 * * * *',
  'payments-reconciler-cobrancas': '6-59/10 * * * *',
  'restaurante-do-dia': '6-59/10 * * * *',
  'appt-auto-noshow': '13-59/15 * * * *',
  'auto-approve-safe-suggestions': '13-59/15 * * * *',
  'settlement-receipts-retry': '13-59/15 * * * *',
  'gorjetas-devolver-cancelados': '13-59/15 * * * *',
};

// ── leitor de horários do cron (5 campos) ─────────────────────────────────
const campo = (txt, min, max) => {
  const s = new Set();
  for (const parte of txt.split(',')) {
    const [intervalo, passoTxt] = parte.split('/');
    const passo = passoTxt ? Number(passoTxt) : 1;
    let a;
    let b;
    if (intervalo === '*') {
      a = min; b = max;
    } else if (intervalo.includes('-')) {
      [a, b] = intervalo.split('-').map(Number);
    } else {
      a = Number(intervalo); b = passoTxt ? max : a;
    }
    for (let v = a; v <= b; v += passo) s.add(v);
  }
  return s;
};
const ler = (horario) => {
  if (/ seconds$/.test(horario)) return null; // de X em X segundos: fora do minuto certo
  const [mi, ho, dm, me, ds] = horario.trim().split(/\s+/);
  return {
    mi: campo(mi, 0, 59), ho: campo(ho, 0, 23), dm: campo(dm, 1, 31), me: campo(me, 1, 12),
    ds: campo(ds, 0, 6), diaLivre: dm === '*', semanaLivre: ds === '*',
  };
};
const corre = (h, d) => {
  if (!h.mi.has(d.getUTCMinutes()) || !h.ho.has(d.getUTCHours()) || !h.me.has(d.getUTCMonth() + 1)) return false;
  const noDia = h.dm.has(d.getUTCDate());
  const naSemana = h.ds.has(d.getUTCDay());
  if (h.diaLivre && h.semanaLivre) return true;
  if (h.diaLivre) return naSemana;
  if (h.semanaLivre) return noDia;
  return noDia || naSemana;
};
/// Conta os arranques de cada minuto de dezembro de 2026 (31 dias: apanha o
/// dia 1, o dia 10, segundas e domingos). Devolve o pior minuto, o pior de
/// cada "minuto da hora" e quantas vezes corre cada tarefa.
const simular = (linhas) => {
  const ativas = linhas.filter((l) => l.active).map((l) => ({ nome: l.jobname, h: ler(l.schedule) }))
    .filter((l) => l.h);
  const porMinutoDaHora = Array(60).fill(0);
  const corridas = {};
  let pior = { n: 0, quando: '' };
  const d = new Date(Date.UTC(2026, 11, 1, 0, 0));
  for (let i = 0; i < 31 * 24 * 60; i++) {
    let n = 0;
    for (const t of ativas) {
      if (corre(t.h, d)) {
        n++;
        corridas[t.nome] = (corridas[t.nome] ?? 0) + 1;
      }
    }
    const m = d.getUTCMinutes();
    if (n > porMinutoDaHora[m]) porMinutoDaHora[m] = n;
    if (n > pior.n) pior = { n, quando: d.toISOString().slice(0, 16) };
    d.setUTCMinutes(m + 1);
  }
  // "Hora normal": 14:00–15:00 de um dia sem tarefas diárias a essa hora.
  const normal = Array(60).fill(0);
  const e = new Date(Date.UTC(2026, 11, 16, 14, 0));
  for (let i = 0; i < 60; i++) {
    normal[i] = ativas.filter((t) => corre(t.h, e)).length;
    e.setUTCMinutes(e.getUTCMinutes() + 1);
  }
  return { pior, porMinutoDaHora, normal, corridas };
};

const db = new PGlite();
let falhas = 0;
let ok = 0;
const certo = (nome, cond, detalhe = '') => {
  if (cond) {
    ok++;
    console.log(`  OK  ${nome}`);
  } else {
    falhas++;
    console.log(`  FALHOU  ${nome} ${detalhe}`);
  }
};
const q = async (sql, params = []) => (await db.query(sql, params)).rows;
const tarefas = () => q(`select jobid::int as jobid, schedule, command, jobname, active from cron.job order by jobid`);
const mapa = (linhas) => Object.fromEntries(linhas.map((l) => [l.jobname, l]));

// ── réplica do pg_cron ────────────────────────────────────────────────────
await db.exec(`
  create schema cron;
  create table cron.job (
    jobid bigint primary key, schedule text not null, command text not null,
    nodename text not null default 'localhost', nodeport int not null default 5432,
    database text not null default 'postgres', username text not null default 'postgres',
    active boolean not null default true, jobname text);
  -- Assinatura do pg_cron verdadeiro. Como ele: recusa tarefa que não exista
  -- e horário que não seja "5 campos" nem "N seconds".
  create function cron.alter_job(job_id bigint, schedule text default null, command text default null,
      database text default null, username text default null, active boolean default null)
    returns void language plpgsql as $f$
  begin
    if not exists (select 1 from cron.job j where j.jobid = job_id) then
      raise exception 'Job % does not exist or you don''t own it', job_id;
    end if;
    if schedule is not null and schedule !~ '^\\S+\\s+\\S+\\s+\\S+\\s+\\S+\\s+\\S+$'
       and schedule !~ '^[0-9]+ seconds$' then
      raise exception 'invalid schedule: %', schedule;
    end if;
    update cron.job j
       set schedule = coalesce(alter_job.schedule, j.schedule),
           command  = coalesce(alter_job.command, j.command),
           database = coalesce(alter_job.database, j.database),
           username = coalesce(alter_job.username, j.username),
           active   = coalesce(alter_job.active, j.active)
     where j.jobid = job_id;
  end $f$;
`);
for (const [jobid, schedule, jobname, active] of TAREFAS) {
  await db.query(`insert into cron.job (jobid, schedule, command, jobname, active) values ($1, $2, $3, $4, $5)`,
    [jobid, schedule, `select 'comando de ${jobname}'`, jobname, active]);
}

console.log('\n0) antes — as tarefas como estavam a 14/11');
const antes = await tarefas();
const simAntes = simular(antes);
certo('100 tarefas na réplica (95 ligadas, 5 desligadas), como em produção',
  antes.length === 100 && antes.filter((l) => l.active).length === 95, `${antes.length}`);
// O mesmo md5 pedido a produção a 14/11: prova que o quadro daqui é o de lá.
const quadro = (await q(`select md5(string_agg(jobid || '|' || schedule || '|' || jobname || '|' || active, ',' order by jobid)) m from cron.job`))[0].m;
certo('o quadro de tarefas é igual ao de produção (md5 de jobid, horário, nome, ligada)',
  quadro === 'd38c10fa24af344479311e972c132efe', quadro);
certo('minuto :00 de uma hora normal: 39 tarefas arrancam no mesmo segundo', simAntes.normal[0] === 39, `${simAntes.normal[0]}`);
certo('minuto :30: 36 (as 36 que se contaram nos registos das 18:30)', simAntes.normal[30] === 36, `${simAntes.normal[30]}`);
certo('minutos :10 :20 :40 :50: 26 a 29',
  [10, 20, 40, 50].every((m) => simAntes.normal[m] >= 26 && simAntes.normal[m] <= 29),
  JSON.stringify([10, 20, 40, 50].map((m) => simAntes.normal[m])));
console.log(`     pior minuto do mês antes: ${simAntes.pior.n} arranques (${simAntes.pior.quando} UTC)`);

// ── a migração, tal como está no repo ─────────────────────────────────────
let aplicou = true;
try {
  await db.exec(migracao);
  console.log('\nmigração aplicada no PGlite');
} catch (e) {
  aplicou = false;
  console.log(`\nA MIGRAÇÃO REBENTOU: ${e.message}`);
}
certo('a migração aplica-se', aplicou);
const depois = await tarefas();
const mAntes = mapa(antes);
const mDepois = mapa(depois);

console.log('\n1) mexe só no que promete');
for (const [nome, [de, para]] of Object.entries(PLANO)) {
  certo(`${nome}: "${de}" → "${para}"`,
    mAntes[nome]?.schedule === de && mDepois[nome]?.schedule === para, `ficou "${mDepois[nome]?.schedule}"`);
}
const mexidas = depois.filter((l) => l.schedule !== mAntes[l.jobname].schedule).map((l) => l.jobname).sort();
certo('mudaram de horário exatamente as 10 do plano, nenhuma outra',
  JSON.stringify(mexidas) === JSON.stringify(Object.keys(PLANO).sort()), JSON.stringify(mexidas));
certo('nenhuma tarefa de dinheiro ou de despacho mudou de horário',
  DINHEIRO_OU_DESPACHO.every((n) => mDepois[n] && mDepois[n].schedule === mAntes[n].schedule),
  JSON.stringify(DINHEIRO_OU_DESPACHO.filter((n) => mDepois[n]?.schedule !== mAntes[n]?.schedule)));
certo('nenhuma do plano está na lista de dinheiro/despacho',
  Object.keys(PLANO).every((n) => !DINHEIRO_OU_DESPACHO.includes(n)));
certo('comando, ligada/desligada e número de tarefas: tudo igual',
  depois.length === antes.length &&
  depois.every((l) => l.command === mAntes[l.jobname].command && l.active === mAntes[l.jobname].active));

console.log('\n2) a mesma frequência, só noutro minuto');
const simDepois = simular(depois);
certo('cada tarefa corre as mesmas vezes num mês (31 dias) que antes',
  Object.keys(simAntes.corridas).every((n) => simAntes.corridas[n] === simDepois.corridas[n]),
  JSON.stringify(Object.keys(simAntes.corridas).filter((n) => simAntes.corridas[n] !== simDepois.corridas[n])));
certo('nenhuma das 10 ficou num minuto redondo (0, 10, 20, 30, 40, 50)',
  Object.keys(PLANO).every((n) => {
    const h = ler(mDepois[n].schedule);
    return [0, 10, 20, 30, 40, 50].every((m) => !h.mi.has(m));
  }));

console.log('\n3) o pico desce');
certo('minuto :00 de uma hora normal: 39 → 29', simDepois.normal[0] === 29, `${simDepois.normal[0]}`);
certo('minuto :30: 36 → 27', simDepois.normal[30] === 27, `${simDepois.normal[30]}`);
const picoNormalAntes = Math.max(...simAntes.normal);
const picoNormalDepois = Math.max(...simDepois.normal);
certo('o pior minuto de uma hora normal fica 10 abaixo', picoNormalDepois === picoNormalAntes - 10,
  `${picoNormalAntes} → ${picoNormalDepois}`);
certo('o pior minuto do mês inteiro fica 10 abaixo', simDepois.pior.n === simAntes.pior.n - 10,
  `${simAntes.pior.n} → ${simDepois.pior.n}`);
const novos = [1, 4, 7, 9, 11, 22, 37, 39, 52];
certo('os minutos para onde foram não viram pico (≤ 17 numa hora normal)',
  novos.every((m) => simDepois.normal[m] <= 17), JSON.stringify(novos.map((m) => `${m}:${simDepois.normal[m]}`)));
certo('nenhum minuto ficou pior do que o pior de antes',
  simDepois.porMinutoDaHora.every((n) => n <= simAntes.pior.n - 10));
console.log(`     hora normal, antes : ${simAntes.normal.join(' ')}`);
console.log(`     hora normal, depois: ${simDepois.normal.join(' ')}`);
console.log(`     pior minuto do mês: ${simAntes.pior.n} (${simAntes.pior.quando}) → ${simDepois.pior.n} (${simDepois.pior.quando})`);

console.log('\n4) repetir não estraga; o que já foi mudado por outro fica como está');
await db.exec(migracao);
const outraVez = await tarefas();
certo('aplicar duas vezes dá exatamente o mesmo', JSON.stringify(outraVez) === JSON.stringify(depois));
// Alguém mudou uma tarefa à mão e outra já não existe: a migração não toca
// na primeira nem rebenta com a segunda.
await db.exec(`
  select cron.alter_job(101, schedule := '*/20 * * * *');
  select cron.alter_job(34, schedule := '0 * * * *');
  delete from cron.job where jobname = 'cleaning-reminders-2h';
`);
let rebentou = '';
try {
  await db.exec(migracao);
} catch (e) {
  rebentou = e.message;
}
const m3 = mapa(await tarefas());
certo('tarefa em falta não rebenta a migração', rebentou === '', rebentou);
certo('horário mudado à mão por outro fica intocado', m3['produtos-esgotados-voltam'].schedule === '*/20 * * * *');
certo('tarefa que voltou ao horário antigo é desencontrada outra vez', m3['reservas_pro_expire_lists'].schedule === '11 * * * *');

console.log('\n5) a segunda metade (PROPOSTA — dinheiro, à espera de ordem): só a conta');
const comProposta = depois.map((l) => (PROPOSTA[l.jobname] ? { ...l, schedule: PROPOSTA[l.jobname] } : l));
const simProposta = simular(comProposta);
certo('as 12 da proposta são TODAS de dinheiro/despacho e nenhuma é das já mexidas',
  Object.keys(PROPOSTA).length === 12 &&
  Object.keys(PROPOSTA).every((n) => DINHEIRO_OU_DESPACHO.includes(n) && !PLANO[n] && mAntes[n]));
certo('com a proposta, cada tarefa continua a correr as mesmas vezes',
  Object.keys(simAntes.corridas).every((n) => simAntes.corridas[n] === simProposta.corridas[n]));
const picoNormalProposta = Math.max(...simProposta.normal);
certo('com a proposta, o pior minuto de uma hora normal fica em 17 (era 39)',
  picoNormalProposta === 17, `${picoNormalProposta}`);
console.log(`     hora normal, com a proposta: ${simProposta.normal.join(' ')}`);
console.log(`     pior minuto do mês com a proposta: ${simProposta.pior.n} (${simProposta.pior.quando})`);

// A conta do pior caso: todas as tarefas do minuto com a ligação aberta ao
// mesmo tempo, mais as 5 varreduras de segundos a coincidir. Na prática as
// tarefas rápidas saem antes de as últimas entrarem — por isso hoje falha
// "às vezes" e não em todos os minutos redondos.
console.log('\n6) cabe nas ligações? (57 para todos; ~28 já ocupadas em repouso; +5 das varreduras de segundos)');
const LIVRES = 57 - 28;
const cabe = (n) => `${n} + 5 = ${n + 5} ${n + 5 <= LIVRES ? 'cabe' : 'NÃO cabe'} em ${LIVRES}`;
console.log(`     antes,  pior minuto de hora normal: ${cabe(picoNormalAntes)}`);
console.log(`     depois, pior minuto de hora normal: ${cabe(picoNormalDepois)}`);
console.log(`     com a proposta, hora normal:        ${cabe(picoNormalProposta)}`);
console.log(`     com a proposta, pior do mês:        ${cabe(simProposta.pior.n)}`);
certo('antes não cabia', picoNormalAntes + 5 > LIVRES);
certo('só esta migração alivia mas, no pior caso, ainda não cabe ao minuto :00 — falta a proposta',
  picoNormalDepois + 5 > LIVRES && picoNormalDepois < picoNormalAntes, cabe(picoNormalDepois));
certo('com a proposta cabe, mesmo no pior minuto do mês (dia 1 às 08:00)', simProposta.pior.n + 5 <= LIVRES,
  `${simProposta.pior.n} + 5 vs ${LIVRES}`);

console.log(`\nRESULTADO: ${ok} certos, ${falhas} falhados`);
process.exit(falhas ? 1 : 0);
