#!/usr/bin/env node
// ============================================================================
// cortex-worker.js — Runtime mínimo do Cortex Worker (F2: Event Bus híbrido)
// ----------------------------------------------------------------------------
// Implementa o modelo decision 4.1 (c) híbrido:
//   1. ASSINA canal cortex_tasks em Supabase Realtime (INSERT notify).
//   2. Quando notificado, chama RPC cortex_claim_next().
//   3. PostgreSQL SKIP LOCKED decide o vencedor (entre workers concorrentes).
//   4. Se a tarefa é claimada, executa placeholder/no-op (F2 = só bus).
//   5. Chama cortex_finish com placeholder.
//   6. Poll fallback: a cada POLL_INTERVAL_MS, cortex_claim_next mesmo sem
//      notificação Realtime (caso Realtime caía).
//
// FEATURE FLAG (pre-flight SS2):
//   USE_BUS=false (default) — worker arranca mas fica em modo observador.
//     NÃO reclama tarefas. Apenas loga notificações para debug.
//   USE_BUS=true — worker arranca funcional (em ambiente de teste).
//
// MODE: nao é daemon em F2. Sai após N segundos (default 60) via CTRL+C ou
//   timeout. Daemon definitivo fica para F6+.
//
// NÃO ALTERA server.mjs, carteiro.sh, ou outros componentes. É um script
//   standalone para testes do Event Bus.
// ============================================================================
import { createClient } from '@supabase/supabase-js';
import process from 'node:process';

const SUPABASE_URL = process.env.SUPABASE_URL || process.env.NEXT_PUBLIC_SUPABASE_URL || '';
const SUPABASE_KEY = process.env.SUPABASE_SERVICE_ROLE_KEY
                  || process.env.SUPABASE_ANON_KEY
                  || '';
const WORKER_NAME = process.env.WORKER_NAME || 'cortex-worker-f2-dev';
const USE_BUS = process.env.USE_BUS === 'true'; // pre-flight SS2 — default OFF
const POLL_INTERVAL_MS = parseInt(process.env.POLL_INTERVAL_MS || '10000', 10);
const RUNTIME_TIMEOUT_MS = parseInt(process.env.RUNTIME_TIMEOUT_MS || '60000', 10);
const VERBOSE = process.env.VERBOSE === 'true';

if (!SUPABASE_URL || !SUPABASE_KEY) {
  console.error('[cortex-worker] FALTA: SUPABASE_URL e (SUPABASE_SERVICE_ROLE_KEY|SUPABASE_ANON_KEY).');
  process.exit(1);
}

console.log(`[cortex-worker] init name=${WORKER_NAME} USE_BUS=${USE_BUS} poll=${POLL_INTERVAL_MS}ms timeout=${RUNTIME_TIMEOUT_MS}ms`);

const supabase = createClient(SUPABASE_URL, SUPABASE_KEY, {
  realtime: { params: { eventsPerSecond: 5 } },
});

const stats = {
  realtime_notifications: 0,
  poll_cycles: 0,
  claims_won: 0,
  claims_lost: 0,
  finished: 0,
  errors: 0,
};

async function tryClaimAndExecute(reason) {
  try {
    const { data, error } = await supabase.rpc('cortex_claim_next', { p_agent: WORKER_NAME });
    if (error) {
      // kill switch ativo OU RPC invalida
      if (String(error.message).includes('KILL_SWITCH_ATIVO')) {
        if (VERBOSE) console.log(`[cortex-worker] KILL_SWITCH_ATIVO (claim ${reason})`);
        return;
      }
      console.error(`[cortex-worker] claim_next error (${reason}):`, error.message);
      stats.errors++;
      return;
    }
    if (!data || (Array.isArray(data) ? data.length === 0 : !data.id)) {
      // fila vazia — outro worker ganhou via SKIP LOCKED
      stats.claims_lost++;
      if (VERBOSE) console.log(`[cortex-worker] no claim (fila vazia / outro ganhou, ${reason})`);
      return;
    }
    const task = Array.isArray(data) ? data[0] : data;
    stats.claims_won++;
    console.log(`[cortex-worker] CLAIM won ${reason}: task=${task.id} tarefa="${String(task.tarefa).slice(0, 60)}" tentativa=${task.tentativa}`);

    if (!USE_BUS) {
      console.log(`[cortex-worker] USE_BUS=false -> no-op finish (observador)`);
      // Em modo observador, ainda assim finisher a task para liberar fila.
      // (Para não deixar fila preza em testes. Em prod USE_BUS=false nao executaria.)
      const { error: e2 } = await supabase.rpc('cortex_finish', {
        p_task_id: task.id,
        p_ok: true,
        p_resultado: { reason: 'observer_noop', use_bus: false },
        p_erro: null,
        p_custo: 0,
        p_modelo: 'none-observer',
      });
      if (e2) {
        console.error(`[cortex-worker] finish error:`, e2.message);
        stats.errors++;
      } else {
        stats.finished++;
      }
      return;
    }

    // USE_BUS=true: executar (placeholder = no-op em F2)
    console.log(`[cortex-worker] EXECUTE task=${task.id} (placeholder no-op em F2)`);
    const { error: e3 } = await supabase.rpc('cortex_finish', {
      p_task_id: task.id,
      p_ok: true,
      p_resultado: { executed_by: WORKER_NAME, runtime_placeholder: true },
      p_erro: null,
      p_custo: 0.0001,
      p_modelo: 'placeholder-f2',
    });
    if (e3) {
      console.error(`[cortex-worker] finish error:`, e3.message);
      stats.errors++;
    } else {
      stats.finished++;
      console.log(`[cortex-worker] FINISH ok task=${task.id}`);
    }
  } catch (err) {
    console.error(`[cortex-worker] tryClaimAndExecute exception (${reason}):`, err.message);
    stats.errors++;
  }
}

// ---- 1. Realtime subscription ----
let realtime_ok = false;
const channel = supabase.channel('cortex-tasks-realtime')
  .onPostgresChanges(
    { event: 'INSERT', schema: 'public', table: 'cortex_tasks' },
    (payload) => {
      stats.realtime_notifications++;
      if (VERBOSE) console.log(`[cortex-worker] Realtime INSERT: ${payload.new?.id} (USE_BUS=${USE_BUS})`);
      tryClaimAndExecute('realtime');
    },
  )
  .on('system', { event: 'SUBSCRIBED' }, () => {
    realtime_ok = true;
    console.log(`[cortex-worker] Realtime SUBSCRIBED ok (canal cortex-tasks-realtime)`);
  })
  .on('system', { event: 'CHANNEL_ERROR' }, (err) => {
    realtime_ok = false;
    console.error(`[cortex-worker] Realtime CHANNEL_ERROR:`, err);
  })
  .subscribe();

// ---- 2. Poll fallback (mesmo quando Realtime falha) ----
const pollTimer = setInterval(() => {
  stats.poll_cycles++;
  if (VERBOSE) console.log(`[cortex-worker] poll cycle #${stats.poll_cycles} (realtime_ok=${realtime_ok})`);
  tryClaimAndExecute('poll');
}, POLL_INTERVAL_MS);

// ---- 3. Timeout shutdown ----
const shutdownTimer = setTimeout(() => {
  console.log(`[cortex-worker] timeout ${RUNTIME_TIMEOUT_MS}ms alcanzado -> shutdown`);
  shutdown();
}, RUNTIME_TIMEOUT_MS);

// ---- 4. Graceful shutdown ----
let shutting = false;
function shutdown() {
  if (shutting) return;
  shutting = true;
  console.log(`[cortex-worker] Shutting down...`);
  console.log(`[cortex-worker] Stats:`, JSON.stringify(stats, null, 2));
  clearInterval(pollTimer);
  clearTimeout(shutdownTimer);
  supabase.removeChannel(channel).then(() => {
    console.log(`[cortex-worker] channel removed`);
    process.exit(0);
  }).catch((e) => {
    console.error(`[cortex-worker] removeChannel error:`, e.message);
    process.exit(0);
  });
}
process.on('SIGINT', shutdown);
process.on('SIGTERM', shutdown);
process.on('SIGQUIT', shutdown);

console.log(`[cortex-worker] ready (USE_BUS=${USE_BUS}). CTRL+C to shutdown.`);