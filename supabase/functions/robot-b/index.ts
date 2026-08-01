// supabase/functions/robot-b/index.ts  v4 — "Motor de Perfeição Contínua"
//
// v4 (2026-06-10): EVOLUÇÃO da v3 (crosstalk) para o loop completo
//   OBSERVAR → DIAGNOSTICAR → CLASSIFICAR → AGIR/SUGERIR → REPORTAR → APRENDER.
//   - mode 'cycle'    : robot_observe() + auto-fixes nível 1 DETERMINÍSTICOS
//                       (whitelist FECHADA vive na RPC robot_auto_execute) +
//                       sugestões nível 2/3 via Gemini → robot_create_suggestion
//                       (benchmark obrigatório, dedup, cap 15, sino admin — tudo SQL).
//   - mode 'digest'   : resumo semanal → sino admin (cron segunda de manhã).
//   - mode 'crosstalk': comportamento v3 intacto (perguntas do Robot A).
//   - default (cron hourly): crosstalk + cycle.
//   - dry_run=true    : observa e diagnostica, NÃO escreve nada (output no response).
//   - KILL SWITCH     : platform_settings.robot_b_enabled (geral — desliga cycle,
//                       digest E crosstalk) + robot_b_auto_level1_enabled (só auto-exec).
//   - Limites duros (máx 10 auto-exec/ciclo, máx 15 sugestões abertas, whitelists,
//     benchmark obrigatório) vivem nas RPCs SQL — o robô NUNCA os altera.
//
// v3: gemini-2.5-flash (modelo lido de support_settings.gemini_model).
// v2: auth via decode JWT (role claim) em vez de string match.

// @ts-nocheck
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2.45.0';

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
  'Access-Control-Allow-Methods': 'POST, OPTIONS',
};

const SUPABASE_URL = Deno.env.get('SUPABASE_URL')!;
const SUPABASE_ANON_KEY = Deno.env.get('SUPABASE_ANON_KEY')!;
const SUPABASE_SERVICE_ROLE_KEY = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!;
const GEMINI_API_KEY = Deno.env.get('GEMINI_API_KEY');

const DEFAULT_MODEL = 'gemini-2.5-flash';

function jsonResponse(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, 'Content-Type': 'application/json' },
  });
}

async function sha256Hex(s: string): Promise<string> {
  const buf = await crypto.subtle.digest('SHA-256', new TextEncoder().encode(s));
  return Array.from(new Uint8Array(buf))
    .map((b) => b.toString(16).padStart(2, '0'))
    .join('');
}

function decodeJwtRole(token: string): string | null {
  try {
    const parts = token.split('.');
    if (parts.length !== 3) return null;
    const payload = parts[1].replace(/-/g, '+').replace(/_/g, '/');
    const padded = payload + '==='.slice(0, (4 - payload.length % 4) % 4);
    const decoded = JSON.parse(atob(padded));
    return decoded.role ?? null;
  } catch {
    return null;
  }
}

async function callGemini(model: string, systemPrompt: string, userPrompt: string,
    generationOverrides: Record<string, unknown> = {}):
    Promise<{ raw: string | null; error: string | null }> {
  try {
    const url = `https://generativelanguage.googleapis.com/v1beta/models/${model}:generateContent`;
    const resp = await fetch(url, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json', 'x-goog-api-key': GEMINI_API_KEY! },
      body: JSON.stringify({
        system_instruction: { parts: [{ text: systemPrompt }] },
        contents: [{ role: 'user', parts: [{ text: userPrompt }] }],
        generationConfig: { maxOutputTokens: 8192, temperature: 0.2, ...generationOverrides },
      }),
    });
    if (!resp.ok) {
      return { raw: null, error: `gemini http ${resp.status}: ${(await resp.text()).slice(0, 200)}` };
    }
    const j = await resp.json();
    let raw = (j?.candidates?.[0]?.content?.parts ?? [])
      .map((p: any) => p.text ?? '').join('').trim();
    raw = raw.replace(/^```(?:json)?\s*\n?/i, '').replace(/\n?```\s*$/i, '').trim();
    return { raw, error: null };
  } catch (e) {
    return { raw: null, error: 'fetch_fail: ' + (e as Error).message };
  }
}

async function getBoolSetting(admin: any, key: string): Promise<boolean> {
  const { data } = await admin.from('platform_settings').select('value').eq('key', key).maybeSingle();
  return data?.value === true || data?.value === 'true';
}

// ═════════════════════════════════════════════════════════════════════════════
// CICLO v4 — OBSERVAR → DIAGNOSTICAR → CLASSIFICAR → AGIR/SUGERIR → REPORTAR
// ═════════════════════════════════════════════════════════════════════════════

const CYCLE_SYSTEM_PROMPT = `És o Robot B v4 da Bora App (delivery + reservas + serviços, Guarda, Portugal) — o "Motor de Perfeição Contínua". Olhas o sistema como o Danilo (fundador solo, estafeta profissional da Uber/Glovo) olharia.

DNA DO DANILO (resumo do BORA_DNA.md):
1. COPIAR OS MELHORES, NUNCA INVENTAR: Glovo → Uber Eats → iFood; reservas = OpenTable/TheFork; serviços = Fresha/Booksy. Se nenhuma referência faz, a Bora provavelmente não deve fazer.
2. ZERO ERRO EM PRODUÇÃO: bug em dinheiro é o pior crime; bug visual o segundo.
3. DÚVIDA → INVESTIGAR, NUNCA ADIVINHAR: toda sugestão cita evidência EXATA das observações.
4. ADMIN = AUTORIDADE TOTAL: feature sem espelho admin é incompleta.
5. CIRÚRGICO, NÃO REVOLUCIONÁRIO: mudanças pequenas, focadas, reversíveis.
6. DINHEIRO É SAGRADO: pricing, comissões, tokens, Stripe, wallet = SEMPRE nível 3.
Antes de cada sugestão responde mentalmente às 3 perguntas do Danilo: (1) Existe nas referências da vertical? (2) Arrisca estragar o que funciona? (3) É pequeno e focado?

BENCHMARKS (toda sugestão CITA um no campo "benchmark" — sem benchmark não nasce):
- Delivery (Glovo/Uber Eats/iFood): catálogo 100% com foto+preço+categoria; produto sem preço NUNCA aparece ao cliente; loja sem operação fica escondida; push de estado <5s; cancelamentos vigiados por motivo; reatribuição automática com TTL.
- Reservas (OpenTable/TheFork/Resy): no-show rate vigiado (<5%); lembretes 24h+2h; slots órfãos libertados rápido; política de depósito clara.
- Serviços (Fresha/Booksy): marcação pending_payment expira e liberta a agenda; lembretes automáticos; no-show com política visível; agenda do staff sempre consistente.

CLASSIFICAÇÃO RÍGIDA (NUNCA alteras os níveis):
- NÍVEL 1 (AUTO): já foi executado deterministicamente pelo código ANTES de ti. NÃO geras nível 1.
- NÍVEL 2 (1-CLIQUE): melhoria segura mas estrutural, executável por UM destes payloads (whitelist fechada):
  {"type":"update_setting","key":"<dispatch_* ou reservation_* operacional — NUNCA chaves com cents/payout/prepayment/bora_service/credit>","value":<jsonb>} — APENAS chaves cuja existência conheces com certeza (o sistema rejeita chaves desconhecidas); NUNCA inventes nomes de chaves — na dúvida, nível 3.
  {"type":"hide_store","restaurant_id":"<id>"}
  {"type":"disable_products","product_ids":["<id>",...]}
  {"type":"flag_products_review","product_ids":["<id>",...]}
- NÍVEL 3 (SÓ PROPOSTA): dinheiro, pricing, Stripe, auth, RGPD, dispatch, código Flutter/Edge/SQL, índices DB, crons novos. "payload_execucao": null.

REGRAS:
- Máximo 3 sugestões por ciclo. Só sugeres o que a evidência observada suporta — números e ids exatos no campo "evidencia".
- "proposta" CONCISA: máximo 500 caracteres (problema → solução → risco).
- NO campo "evidencia" usa contagens e no máximo 5 ids de exemplo (NUNCA listas longas).
- "payload_execucao" SÓ com ids/valores CONCRETOS vindos das observações. Se a evidência é só uma contagem (sem ids), a sugestão é nível 3 com payload null (propõe o processo, não a execução).
- NÃO sugiras o que os auto-fixes nível 1 deste ciclo já cobrem (produtos sem preço desativados, preços suspeitos marcados para revisão, notificações de teste limpas).
- NÃO repitas sugestões abertas nem tipos rejeitados (listas no input).
- "dedup_key": ESCOLHE UMA das chaves canónicas listadas em CHAVES CANÓNICAS (input). É um conjunto FECHADO — copia a chave EXATAMENTE como está escrita.
  * NÃO inventes chave nova. NÃO acrescentes sufixo (-v2, -v19), data, contagem ou variação.
  * NÃO reformules com sinónimos: "otimizar-cron-queries-lentas", "queries-lentas-cron" e "otimizar-queries-cron-lentas" seriam TRÊS chaves para O MESMO problema — isso é exatamente o que não pode acontecer.
  * Se o achado NÃO couber em nenhuma chave canónica, devolve "dedup_key": "sem-chave" e explica no "titulo" qual chave nova faria falta. NUNCA inventes uma para contornar.
  * Uma chave já ocupada NÃO te impede de reportar: o servidor ATUALIZA a linha viva com a tua evidência nova. Repetir a chave certa é o comportamento CORRETO, não um erro.
- "severidade": 1-5 (5 = crítico).
- "categoria": catalogo | operacao_pedidos | marcacoes | notificacoes | seguranca | performance | ux_paridade | dados_teste | infra_cron | suporte_padroes | outro.
- "proposta": PT-BR claro — problema → solução → risco.
- Sem nada relevante: "suggestions": [].

Responde APENAS com JSON válido (sem markdown):
{"suggestions":[{"nivel":2,"severidade":3,"categoria":"...","titulo":"...","proposta":"...","evidencia":{},"payload_execucao":{}|null,"benchmark":"...","dedup_key":"..."}]}`;

// CONJUNTO FECHADO de dedup_keys (missão nunca-mais-travar-2026-07-31, I1).
// Porquê: entregar ao Gemini as chaves ocupadas com "NÃO repetir" fazia-o cumprir à letra —
// inventava "...-v19"/"...-v24" ou reformulava com sinónimos ("queries lentas de cron" chegou a
// ter 7 chaves vivas). O dedup do servidor estava correto; era a chave que mudava. Com um
// conjunto fechado o modelo não tem por onde fugir, e "sem-chave" é a saída honesta.
// Acrescentar chave aqui é ato humano deliberado — o robô nunca edita esta lista.
const DEDUP_KEYS_CANONICAS = [
  'catalogo:produtos-sem-preco',
  'catalogo:produtos-sem-foto',
  'catalogo:produtos-sem-categoria',
  'catalogo:preco-suspeito',
  'catalogo:backlog-revisao-produtos',
  'operacao_pedidos:pedidos-presos',
  'operacao_pedidos:drivers-online-sem-token',
  'marcacoes:marcacoes-pendentes-orfas',
  'marcacoes:no-show-rate',
  'notificacoes:notificacoes-falhadas',
  'seguranca:rls-desabilitado',
  'seguranca:secdef-search-path-mutavel',
  'performance:cron-queries-lentas',
  'infra_cron:cron-falhado',
  'infra_cron:http-timeouts-recorrentes',
  'ux_paridade:paridade-admin-em-falta',
  'dados_teste:dados-de-teste-em-producao',
  'suporte_padroes:crosstalk-pendente',
  'sem-chave',
];

async function runCycle(admin: any, geminiModel: string, dryRun: boolean): Promise<any> {
  // KILL SWITCH geral
  if (!(await getBoolSetting(admin, 'robot_b_enabled'))) {
    const { data: runId } = await admin.rpc('robot_start_run', { p_mode: 'cycle', p_dry_run: dryRun });
    if (runId) {
      await admin.rpc('robot_finish_run', {
        p_run_id: runId, p_status: 'skipped_kill_switch',
        p_observations: {}, p_auto_exec_count: 0, p_suggestions_created: 0, p_error: null,
      });
    }
    return { skipped: 'kill_switch', run_id: runId ?? null };
  }
  const autoLevel1 = await getBoolSetting(admin, 'robot_b_auto_level1_enabled');

  const { data: runId, error: runErr } = await admin.rpc('robot_start_run', { p_mode: 'cycle', p_dry_run: dryRun });
  if (runErr) return { error: 'start_run_failed: ' + runErr.message };

  // ── 1. OBSERVAR ────────────────────────────────────────────────────────────
  const { data: obs, error: obsErr } = await admin.rpc('robot_observe');
  if (obsErr) {
    await admin.rpc('robot_finish_run', {
      p_run_id: runId, p_status: 'error', p_observations: {},
      p_auto_exec_count: 0, p_suggestions_created: 0, p_error: 'observe_failed: ' + obsErr.message,
    });
    return { run_id: runId, error: 'observe_failed: ' + obsErr.message };
  }

  // ── 2. AGIR nível 1 — DETERMINÍSTICO (sem LLM; whitelist fechada na RPC) ──
  const planned: any[] = [];
  if ((obs.suggestions_open_count ?? 0) > 0) {
    planned.push({ op: 'expire_stale_suggestions', params: {} });
  }
  const unpricedIds: string[] = obs.products_unpriced_market?.ids ?? [];
  if (unpricedIds.length > 0) {
    planned.push({ op: 'disable_unpriced_market_products', params: { product_ids: unpricedIds } });
  }
  const suspiciousIds: string[] = obs.products_suspicious_price?.ids ?? [];
  if (suspiciousIds.length > 0) {
    planned.push({ op: 'flag_products_review', params: { product_ids: suspiciousIds } });
  }
  if ((obs.test_notifications_old_count ?? 0) > 0) {
    planned.push({ op: 'clean_test_notifications', params: {} });
  }

  const executed: any[] = [];
  let autoCount = 0;
  if (!dryRun && autoLevel1) {
    for (const a of planned.slice(0, 10)) {  // tecto extra; o duro vive na RPC
      const { data, error } = await admin.rpc('robot_auto_execute', {
        p_run_id: runId, p_operation: a.op, p_params: a.params,
      });
      executed.push({ op: a.op, ok: !error, result: data ?? null, error: error?.message ?? null });
      if (!error) autoCount++;
    }
  }

  // nível 1 desligado → vira sugestão 1-clique (payload pronto) p/ ops aplicáveis
  const level1AsSuggestions: any[] = [];
  if (!autoLevel1) {
    if (unpricedIds.length > 0) {
      level1AsSuggestions.push({
        nivel: 1, severidade: 4, categoria: 'catalogo',
        titulo: `Desativar ${unpricedIds.length} produto(s) de mercado sem preço`,
        proposta: 'Regra canónica Bora: produto sem preço NUNCA aparece ao cliente. Auto-execução nível 1 está desligada — aprovar aplica is_available=false (reversível).',
        evidencia: { product_ids: unpricedIds },
        payload_execucao: { type: 'disable_products', product_ids: unpricedIds },
        benchmark: 'Glovo/Uber Eats: produto sem preço nunca é mostrado ao cliente',
        dedup_key: 'catalogo:mercado-sem-preco',
      });
    }
    if (suspiciousIds.length > 0) {
      level1AsSuggestions.push({
        nivel: 1, severidade: 3, categoria: 'catalogo',
        titulo: `Marcar ${suspiciousIds.length} produto(s) com preço suspeito para revisão`,
        proposta: 'Preços >€500 ou <€0,05 em lojas de mercado indicam erro de scraping. Aprovar marca needs_review=true (inócuo, reversível).',
        evidencia: { product_ids: suspiciousIds },
        payload_execucao: { type: 'flag_products_review', product_ids: suspiciousIds },
        benchmark: 'Glovo/iFood: catálogos com validação de preço antes de publicar',
        dedup_key: 'catalogo:preco-suspeito',
      });
    }
  }

  // ── 3. APRENDER (input do diagnóstico) ─────────────────────────────────────
  const sixtyDaysAgo = new Date(Date.now() - 60 * 24 * 60 * 60 * 1000).toISOString();
  const { data: rejected } = await admin.from('robot_suggestions')
    .select('categoria, motivo_rejeicao, dedup_key')
    .eq('status', 'rejeitada').gt('reviewed_at', sixtyDaysAgo).limit(20);
  const { data: openSugs } = await admin.from('robot_suggestions')
    .select('titulo, dedup_key, nivel')
    .eq('status', 'nova').limit(20);

  // ── 4. DIAGNOSTICAR + CLASSIFICAR (Gemini) ─────────────────────────────────
  let gemSuggestions: any[] = [];
  let geminiError: string | null = null;
  if (GEMINI_API_KEY) {
    const userPrompt = `OBSERVAÇÕES DO CICLO (robot_observe):
${JSON.stringify(obs)}

AUTO-FIXES NÍVEL 1 ${dryRun ? 'PLANEADOS (dry-run)' : (autoLevel1 ? 'JÁ EXECUTADOS' : 'CONVERTIDOS EM SUGESTÃO (auto OFF)')} NESTE CICLO:
${JSON.stringify(planned.map((p) => p.op))}

CHAVES CANÓNICAS (conjunto FECHADO — o "dedup_key" TEM de ser uma destas, copiada tal e qual):
${JSON.stringify(DEDUP_KEYS_CANONICAS)}

SUGESTÕES JÁ ABERTAS (contexto — NÃO é proibição de chave):
${JSON.stringify(openSugs ?? [])}
Se o teu achado é o MESMO problema de uma destas, usa a MESMA dedup_key: o servidor atualiza a
linha existente com a tua evidência nova (é o comportamento correto). Não inventes variação.

TIPOS REJEITADOS NOS ÚLTIMOS 60 DIAS (NÃO repetir — aprende com o motivo):
${JSON.stringify(rejected ?? [])}

Analisa como o Danilo analisaria e retorna JSON.`;
    // thinkingBudget 0: o 2.5-flash gasta maxOutputTokens em "thinking" e trunca o
    // JSON (parse_fail position ~5844 no 1º dry-run). responseMimeType força JSON puro.
    const { raw, error } = await callGemini(geminiModel, CYCLE_SYSTEM_PROMPT, userPrompt, {
      maxOutputTokens: 16384,
      responseMimeType: 'application/json',
      thinkingConfig: { thinkingBudget: 0 },
    });
    if (error) {
      geminiError = error;
    } else if (raw) {
      try {
        const parsed = JSON.parse(raw);
        if (Array.isArray(parsed?.suggestions)) gemSuggestions = parsed.suggestions.slice(0, 5);
      } catch (e) {
        geminiError = 'parse_fail: ' + (e as Error).message + ' raw: ' + raw.slice(0, 200);
      }
    }
  } else {
    geminiError = 'gemini_key_missing';
  }

  // ── 5. SUGERIR (RPC valida: benchmark, dedup, cap 15, sino) ────────────────
  const toCreate = [...level1AsSuggestions, ...gemSuggestions];
  const created: any[] = [];
  const skipped: any[] = [];
  let sugCount = 0;
  if (!dryRun) {
    for (const s of toCreate) {
      const nivel = Number(s.nivel);
      if (![1, 2, 3].includes(nivel)) { skipped.push({ titulo: s.titulo, reason: 'nivel_invalido' }); continue; }
      // Não confiar na chave do modelo: fora do conjunto fechado -> 'sem-chave' (I1).
      // Assim uma chave inventada ("...-v20") ou reformulada com sinónimo cai toda no mesmo
      // balde em vez de gerar linha nova, e o título diz que chave canónica faltou.
      let dedup = String(s.dedup_key ?? '').trim().toLowerCase();
      if (!DEDUP_KEYS_CANONICAS.includes(dedup)) {
        console.log(`dedup_key fora do conjunto canonico: "${dedup}" -> sem-chave (titulo: ${s.titulo})`);
        dedup = 'sem-chave';
      }
      const { data: sid, error } = await admin.rpc('robot_create_suggestion', {
        p_run_id: runId,
        p_nivel: nivel,
        p_severidade: Number(s.severidade ?? 3),
        p_categoria: String(s.categoria ?? 'outro'),
        p_titulo: String(s.titulo ?? '(sem título)'),
        p_evidencia: s.evidencia ?? {},
        p_proposta: String(s.proposta ?? ''),
        p_payload: nivel === 3 ? null : (s.payload_execucao ?? null),
        p_benchmark: String(s.benchmark ?? ''),
        p_dedup_key: dedup,
      });
      if (error) skipped.push({ titulo: s.titulo, reason: error.message });
      else if (sid === null) skipped.push({ titulo: s.titulo, reason: 'dedup_ou_cap' });
      else { sugCount++; created.push({ id: sid, nivel, titulo: s.titulo }); }
    }
  }

  // ── 6. REPORTAR (fechar o run; sinos já saíram das RPCs) ───────────────────
  const obsSummary = {
    products_unpriced_market: obs.products_unpriced_market?.count ?? 0,
    products_suspicious_price: obs.products_suspicious_price?.count ?? 0,
    products_no_photo: obs.products_no_photo_count ?? 0,
    products_no_category: obs.products_no_category_count ?? 0,
    orphan_pending_appointments: obs.orphan_pending_appointments?.count ?? 0,
    stuck_orders: obs.stuck_orders?.count ?? 0,
    cron_failures_24h: (obs.cron_failures_24h ?? []).length,
    http_errors_24h: obs.http_errors_24h?.count ?? 0,
    crosstalk_pending: obs.crosstalk_pending_count ?? 0,
    security_rls_disabled: (obs.security_rls_disabled ?? []).length,
    security_secdef_mutable: (obs.security_secdef_mutable_searchpath ?? []).length,
  };
  await admin.rpc('robot_finish_run', {
    p_run_id: runId, p_status: 'ok', p_observations: obsSummary,
    p_auto_exec_count: autoCount, p_suggestions_created: sugCount,
    p_error: geminiError,
  });

  return {
    run_id: runId, dry_run: dryRun, auto_level1_enabled: autoLevel1,
    observations: obs,
    planned_level1: planned,
    executed_level1: executed,
    suggestions_created: created,
    suggestions_skipped: skipped,
    would_be_suggestions: dryRun ? toCreate : undefined,
    gemini_error: geminiError,
  };
}

// ═════════════════════════════════════════════════════════════════════════════
// DIGEST SEMANAL → sino admin (1 notificação-resumo)
// ═════════════════════════════════════════════════════════════════════════════

async function runDigest(admin: any): Promise<any> {
  if (!(await getBoolSetting(admin, 'robot_b_enabled'))) {
    return { skipped: 'kill_switch' };
  }
  const { data: runId, error: runErr } = await admin.rpc('robot_start_run', { p_mode: 'digest', p_dry_run: false });
  if (runErr) return { error: 'start_run_failed: ' + runErr.message };

  const since = new Date(Date.now() - 7 * 24 * 60 * 60 * 1000).toISOString();
  const cnt = async (q: any) => (await q).count ?? 0;
  const sug7 = await cnt(admin.from('robot_suggestions').select('*', { count: 'exact', head: true }).gt('created_at', since));
  const abertas = await cnt(admin.from('robot_suggestions').select('*', { count: 'exact', head: true }).eq('status', 'nova'));
  const aplicadas7 = await cnt(admin.from('robot_suggestions').select('*', { count: 'exact', head: true }).eq('status', 'aplicada').gt('reviewed_at', since));
  const rejeitadas7 = await cnt(admin.from('robot_suggestions').select('*', { count: 'exact', head: true }).eq('status', 'rejeitada').gt('reviewed_at', since));
  const auto7 = await cnt(admin.from('robot_audit_log').select('*', { count: 'exact', head: true }).eq('executed_by', 'robot').gt('created_at', since));
  const ciclos7 = await cnt(admin.from('robot_runs').select('*', { count: 'exact', head: true }).eq('mode', 'cycle').gt('started_at', since));

  const summary = `🤖 Digest semanal Robot B — ${ciclos7} ciclos: ${sug7} sugestões novas (${abertas} abertas agora), ${aplicadas7} aplicadas, ${rejeitadas7} rejeitadas, ${auto7} auto-fixes nível 1.`;
  const payload = { sugestoes_7d: sug7, abertas, aplicadas_7d: aplicadas7, rejeitadas_7d: rejeitadas7, auto_fixes_7d: auto7, ciclos_7d: ciclos7 };

  const { error: digErr } = await admin.rpc('robot_notify_digest', {
    p_run_id: runId, p_summary: summary, p_payload: payload,
  });
  await admin.rpc('robot_finish_run', {
    p_run_id: runId, p_status: digErr ? 'error' : 'ok', p_observations: payload,
    p_auto_exec_count: 0, p_suggestions_created: 0, p_error: digErr?.message ?? null,
  });
  return { run_id: runId, summary, payload, error: digErr?.message ?? null };
}

// ═════════════════════════════════════════════════════════════════════════════
// CROSSTALK (v3 — intacto): perguntas do Robot A em robot_crosstalk
// ═════════════════════════════════════════════════════════════════════════════

async function processCrosstalk(admin: any, geminiModel: string, limit: number, dryRun: boolean): Promise<any> {
  const { data: pendingRows, error: pendingErr } = await admin
    .from('robot_crosstalk')
    .select('id, question, question_context, urgency, skill_triggered, session_id, created_at')
    .eq('direction', 'a_to_b')
    .eq('status', 'pending')
    .order('created_at', { ascending: true })
    .limit(limit);

  if (pendingErr) {
    return { error: 'fetch_pending_failed', detail: pendingErr.message };
  }
  if (!pendingRows || pendingRows.length === 0) {
    return { processed: 0, reason: 'no_pending_questions' };
  }

  const urgencyOrder: Record<string, number> = { critical: 0, medium: 1, normal: 2 };
  pendingRows.sort((a: any, b: any) => {
    const ua = urgencyOrder[a.urgency] ?? 2;
    const ub = urgencyOrder[b.urgency] ?? 2;
    if (ua !== ub) return ua - ub;
    return new Date(a.created_at).getTime() - new Date(b.created_at).getTime();
  });

  if (dryRun) {
    return {
      dry_run: true,
      pending_count: pendingRows.length,
      questions: pendingRows.map((r: any) => ({
        id: r.id, urgency: r.urgency, question: String(r.question).slice(0, 100),
      })),
    };
  }

  const results: any[] = [];
  let answered = 0;
  let suggestionsCreated = 0;

  for (const row of pendingRows) {
    const qId = row.id as string;
    const question = String(row.question || '');
    const urgency = String(row.urgency || 'normal');
    const context = row.question_context ?? {};

    // RAG: fallback por texto (text-embedding-004 já foi shutdown 14-Jan-2026)
    let ragChunks: any[] = [];
    const keywords = question
      .toLowerCase()
      .replace(/[^a-zà-ÿ\s]/gi, '')
      .split(/\s+/)
      .filter((w) => w.length > 4)
      .slice(0, 5);
    if (keywords.length > 0) {
      const orFilter = keywords.map((kw) => `chunk_text.ilike.%${kw}%`).join(',');
      const { data: textChunks } = await admin
        .from('support_knowledge_chunks')
        .select('id, source_file, section_title, chunk_text')
        .or(orFilter)
        .limit(5);
      ragChunks = textChunks ?? [];
    }

    const ragContext = ragChunks.length > 0
      ? ragChunks
          .map((c: any, i: number) => `[Chunk ${i + 1} — ${c.source_file ?? '?'} / ${c.section_title ?? '?'}]\n${(c.chunk_text ?? '').slice(0, 800)}`)
          .join('\n\n')
      : '(sem chunks relevantes)';

    const systemPrompt = `És o Robot B — analista técnico da Bora App (delivery+supermercado+reservas em Guarda, Portugal).

O Robot A (chatbot Gemini de suporte ao cliente) encaminhou-te uma pergunta técnica/bug que não soube resolver. A tua função:

1. Analisar a pergunta com o contexto RAG da knowledge base do projeto.
2. Dar uma resposta técnica clara, em PT-PT, explicando:
   - Causa provável do problema (se identificável)
   - O que deve ser corrigido na app (lado técnico)
   - O que dizer ao cliente (lado UX)
3. Se a pergunta revela um padrão útil para o bot aprender no futuro, propor UMA skill_suggestion.

Responde APENAS com JSON válido (sem markdown, sem \`\`\`json fences):
{
  "answer_markdown": "resposta técnica detalhada em markdown PT-PT (causa raiz + fix + UX)",
  "suggestion": null OR {
    "proposal_type": "new_skill" | "playbook_update",
    "pattern_summary": "resumo <= 200 chars",
    "suggested_skill_name": "UPPER_SNAKE_CASE" (só se new_skill),
    "suggested_category": "categoria" (só se new_skill),
    "suggested_mode": "read_only" | "write_shadow" | "escalate" (só se new_skill),
    "suggested_playbook_md": "playbook markdown completo",
    "target_skill_name": "nome skill existente" (só se playbook_update)
  }
}

Se não houver padrão útil, suggestion = null.`;

    const userPrompt = `PERGUNTA (urgência: ${urgency}):
${question}

CONTEXTO da chamada:
${JSON.stringify(context)}

SKILL que disparou: ${row.skill_triggered ?? 'ASK_ROBOT_B'}

KNOWLEDGE BASE relevante:
${ragContext}

Analisa e retorna JSON.`;

    let answer = '';
    let suggestion: any = null;
    const { raw, error: gemErr } = await callGemini(geminiModel, systemPrompt, userPrompt);
    let geminiError: string | null = gemErr;

    if (!geminiError && raw) {
      try {
        const parsed = JSON.parse(raw);
        answer = String(parsed.answer_markdown ?? '').trim();
        if (parsed.suggestion && typeof parsed.suggestion === 'object') {
          suggestion = parsed.suggestion;
        }
      } catch (e) {
        geminiError = 'parse_fail: ' + (e as Error).message + ' raw: ' + raw.slice(0, 200);
      }
    }

    if (!answer || geminiError) {
      results.push({ id: qId, error: geminiError ?? 'empty_answer' });
      continue;
    }

    const ragChunksJson = ragChunks.slice(0, 5).map((c: any) => ({
      id: c.id, source_file: c.source_file, section_title: c.section_title,
    }));

    const { error: respErr } = await admin.rpc('robot_b_respond', {
      p_crosstalk_id: qId,
      p_answer: answer,
      p_rag_chunks: ragChunksJson,
    });

    if (respErr) {
      results.push({ id: qId, error: 'respond_failed: ' + respErr.message });
      continue;
    }
    answered++;

    if (suggestion && suggestion.pattern_summary) {
      const summary = String(suggestion.pattern_summary).slice(0, 200).trim();
      const hash = await sha256Hex(summary.toLowerCase());

      const { data: dup } = await admin
        .from('skill_suggestions')
        .select('id')
        .eq('pattern_hash', hash)
        .eq('status', 'pending')
        .maybeSingle();

      if (!dup) {
        const propType = String(suggestion.proposal_type ?? 'new_skill');
        const insertPayload: any = {
          proposal_type: propType,
          zone_type: 'safe',
          pattern_summary: summary,
          sample_messages: [question.slice(0, 500)],
          message_count: 1,
          suggested_playbook_md: String(suggestion.suggested_playbook_md ?? ''),
          pattern_hash: hash,
          gemini_model: geminiModel,
          analysis_window_start: new Date(Date.now() - 24 * 60 * 60 * 1000).toISOString(),
          analysis_window_end: new Date().toISOString(),
        };

        if (propType === 'new_skill') {
          insertPayload.suggested_skill_name = String(suggestion.suggested_skill_name ?? '').toUpperCase();
          insertPayload.suggested_category = String(suggestion.suggested_category ?? 'technical_support');
          insertPayload.suggested_mode = String(suggestion.suggested_mode ?? 'read_only');
          insertPayload.suggested_allowed_tools = [];
        } else if (propType === 'playbook_update') {
          const targetName = String(suggestion.target_skill_name ?? '');
          if (targetName) {
            const { data: targetSkill } = await admin
              .from('support_skills')
              .select('id, playbook_md')
              .eq('skill_name', targetName)
              .maybeSingle();
            if (targetSkill) {
              insertPayload.target_skill_id = targetSkill.id;
              insertPayload.previous_value = targetSkill.playbook_md;
            }
          }
        }

        const { error: sugErr } = await admin
          .from('skill_suggestions')
          .insert(insertPayload);

        if (!sugErr) suggestionsCreated++;
      }
    }

    results.push({
      id: qId,
      urgency,
      answered: true,
      suggestion_created: !!suggestion,
      rag_chunks_used: ragChunks.length,
    });
  }

  return {
    processed: pendingRows.length,
    answered,
    suggestions_created: suggestionsCreated,
    results,
  };
}

// ═════════════════════════════════════════════════════════════════════════════
// HANDLER
// ═════════════════════════════════════════════════════════════════════════════

Deno.serve(async (req: Request) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: corsHeaders });
  if (req.method !== 'POST')   return jsonResponse({ error: 'method_not_allowed' }, 405);

  if (!SUPABASE_URL || !SUPABASE_ANON_KEY || !SUPABASE_SERVICE_ROLE_KEY) {
    return jsonResponse({ error: 'server_misconfigured' }, 500);
  }

  const authHeader = req.headers.get('Authorization') ?? '';
  const token = authHeader.replace(/^Bearer\s+/i, '').trim();
  if (!token) return jsonResponse({ error: 'missing_token' }, 401);

  let isService = false;
  let isAdmin = false;

  const jwtRole = decodeJwtRole(token);
  if (jwtRole === 'service_role') {
    isService = true;
  } else {
    const userClient = createClient(SUPABASE_URL, SUPABASE_ANON_KEY, {
      global: { headers: { Authorization: `Bearer ${token}` } },
    });
    const { data: userData } = await userClient.auth.getUser();
    isAdmin = userData?.user?.app_metadata?.role === 'admin';
  }

  if (!isService && !isAdmin) {
    return jsonResponse({ error: 'unauthorized', jwt_role: jwtRole }, 401);
  }

  let body: { mode?: string; limit?: number; dry_run?: boolean } = {};
  try { body = await req.json(); } catch { /* default */ }
  const mode   = String(body.mode ?? 'full');
  const limit  = Math.max(1, Math.min(10, Number(body.limit ?? 5) | 0));
  const dryRun = body.dry_run === true;

  if (!GEMINI_API_KEY && mode !== 'digest') {
    // o ciclo ainda corre as partes determinísticas; só avisa
  }

  const admin = createClient(SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY);

  // modelo Gemini das settings (fallback default)
  const { data: settingsRow } = await admin
    .from('support_settings').select('gemini_model').eq('id', 1).maybeSingle();
  const geminiModel = (settingsRow?.gemini_model as string) || DEFAULT_MODEL;

  const triggeredBy = isService ? 'service' : 'admin';

  if (mode === 'digest') {
    const digest = await runDigest(admin);
    return jsonResponse({ mode, triggered_by: triggeredBy, digest });
  }

  if (mode === 'cycle') {
    const cycle = await runCycle(admin, geminiModel, dryRun);
    return jsonResponse({ mode, triggered_by: triggeredBy, model: geminiModel, cycle });
  }

  if (mode === 'crosstalk') {
    if (!(await getBoolSetting(admin, 'robot_b_enabled'))) {
      return jsonResponse({ mode, skipped: 'kill_switch', triggered_by: triggeredBy });
    }
    if (!GEMINI_API_KEY) return jsonResponse({ error: 'gemini_key_missing' }, 503);
    const crosstalk = await processCrosstalk(admin, geminiModel, limit, dryRun);
    return jsonResponse({ mode, triggered_by: triggeredBy, model: geminiModel, ...crosstalk });
  }

  // default 'full' (cron hourly): crosstalk + cycle, ambos gated pelo kill switch
  if (!(await getBoolSetting(admin, 'robot_b_enabled'))) {
    const { data: runId } = await admin.rpc('robot_start_run', { p_mode: 'cycle', p_dry_run: dryRun });
    if (runId) {
      await admin.rpc('robot_finish_run', {
        p_run_id: runId, p_status: 'skipped_kill_switch',
        p_observations: {}, p_auto_exec_count: 0, p_suggestions_created: 0, p_error: null,
      });
    }
    return jsonResponse({ mode: 'full', skipped: 'kill_switch', triggered_by: triggeredBy, run_id: runId ?? null });
  }
  const crosstalk = GEMINI_API_KEY
    ? await processCrosstalk(admin, geminiModel, limit, dryRun)
    : { error: 'gemini_key_missing' };
  const cycle = await runCycle(admin, geminiModel, dryRun);
  return jsonResponse({ mode: 'full', triggered_by: triggeredBy, model: geminiModel, crosstalk, cycle });
});
