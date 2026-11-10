// Sessao 5E B3 - Edge Fn analyze-conversations v4
// v4 fix: auth via decode JWT (role claim) em vez de string match.
//        Resolve falha 401 quando vault.service_role_key != env.SUPABASE_SERVICE_ROLE_KEY.
// v3 fix: verify_jwt agora false (autenticacao feita internamente).
//
// v5 (10/11/2026, fechar-tudo bloco H): sem Gemini do projeto bora-juiz (conta de pagamento vencida,
// 402). A analise vai pelo _shared/ia_visao.ts: Claude primeiro (robo 'edge-analise-suporte', Haiku);
// mensagens de clientes -> privado=true (de reserva so motores que nao treinam com os dados: Groq).
// Os campos da resposta ficam iguais (gemini_error, gemini_model = motor:modelo que respondeu).
//
// Analisa support_chatbot_messages 7 dias e propoe 3 tipos via IA:
//   1. new_skill
//   2. playbook_update
//   3. settings_update

// @ts-nocheck
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2.45.0';
import { chamadaDoServidor, respostaAoPing, utilizadorDoPedido } from '../_shared/chaves.ts';
import { secretKey } from '../_shared/keys.ts';
import { pedirIa } from '../_shared/ia_visao.ts';

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
  'Access-Control-Allow-Methods': 'POST, OPTIONS',
};

const SUPABASE_URL = Deno.env.get('SUPABASE_URL')!;
const SUPABASE_ANON_KEY = Deno.env.get('SUPABASE_ANON_KEY')!;
const SUPABASE_SERVICE_ROLE_KEY = secretKey()!;

const SAFE_SETTING_KEYS = [
  'chatbot_welcome_text',
  'sla_hours',
  'max_messages_per_session',
  'rate_limit_per_user_day',
  'max_output_tokens_per_call',
  'max_user_message_chars',
  'max_tool_iterations',
  'skill_analysis_min_messages',
];

const CRITICAL_SKILLS = [
  'CANCEL_PRE_PURCHASE','CANCEL_DURING_PURCHASE',
  'RESERVATION_CANCEL','PASSWORD_RESET','ACCOUNT_UPDATE',
  'UPDATE_DELIVERY_INSTRUCTIONS','UPDATE_DELIVERY_ADDRESS',
  'OTP_RESEND',
];

function jsonResponse(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, 'Content-Type': 'application/json' },
  });
}

function anonymize(text: string): string {
  return String(text)
    .replace(/[\w.+-]+@[\w-]+\.[\w.-]+/g, '[email]')
    .replace(/\+?351[\s.-]?9\d{2}[\s.-]?\d{3}[\s.-]?\d{3}/g, '[phone]')
    .replace(/\+?[1-9]\d{6,14}/g, '[phone]')
    .replace(/[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}/gi, '[id]')
    .replace(/\b\d{4,}\b/g, '[number]');
}

async function sha256Hex(s: string): Promise<string> {
  const buf = await crypto.subtle.digest('SHA-256', new TextEncoder().encode(s));
  return Array.from(new Uint8Array(buf))
    .map((b) => b.toString(16).padStart(2, '0'))
    .join('');
}

function isObject(o: unknown): o is Record<string, unknown> {
  return o !== null && typeof o === 'object' && !Array.isArray(o);
}

Deno.serve(async (req: Request) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: corsHeaders });
  if (req.method !== 'POST')   return jsonResponse({ error: 'method_not_allowed' }, 405);

  if (!SUPABASE_URL || !SUPABASE_ANON_KEY || !SUPABASE_SERVICE_ROLE_KEY) {
    return jsonResponse({ error: 'server_misconfigured' }, 500);
  }

  let body: { scheduled?: boolean; days_back?: number; dry_run?: boolean } = {};
  try { body = await req.clone().json(); } catch { /* default empty */ }
  const scheduled = body.scheduled === true;
  const daysBack  = Math.max(1, Math.min(30, Number(body.days_back ?? 7) | 0));
  const dryRun    = body.dry_run === true;

  let isService = false;
  let isAdmin = false;

  // verify_jwt=false: o papel lido do JWT sem validar a assinatura NÃO conta — só o servidor
  // confirmado (chave secreta nova em apikey ou Bearer, ou a legada confirmada no Auth) ou um admin
  // com sessão confirmada no Auth. 31/10/2026 (chaves-varredura): a chave nova só em apikey também
  // passa (antes caía em missing_token).
  if (await chamadaDoServidor(req)) {
    isService = true;
  } else {
    const u = await utilizadorDoPedido(req);
    if (!u) {
      console.warn('[analyze v4] invalid_token scheduled=' + scheduled);
      return jsonResponse({ error: 'unauthorized' }, 401);
    }
    isAdmin = u.app_metadata?.role === 'admin';
  }
  const pong = await respostaAoPing(req, corsHeaders);
  if (pong) return pong;

  if (!isService && !isAdmin) {
    return jsonResponse({ error: 'admin_required' }, 403);
  }

  console.log(`[analyze v4] auth=${isService ? 'service' : 'admin'} scheduled=${scheduled} days_back=${daysBack}`);

  const admin = createClient(SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY);

  const { data: settingsRow } = await admin
    .from('support_settings').select('*').eq('id', 1).single();
  const lastAt = settingsRow?.last_skill_analysis_at
    ? new Date(settingsRow.last_skill_analysis_at as string)
    : null;
  const minMessages = Math.max(1, Number(settingsRow?.skill_analysis_min_messages ?? 5) | 0);

  if (!scheduled && lastAt) {
    const diffMs = Date.now() - lastAt.getTime();
    if (diffMs < 60 * 60 * 1000) {
      return jsonResponse({
        error: 'rate_limited',
        retry_after_seconds: Math.ceil((60 * 60 * 1000 - diffMs) / 1000),
        last_analysis_at: lastAt.toISOString(),
      }, 429);
    }
  }

  if (dryRun) {
    return jsonResponse({
      dry_run: true,
      status: 'ok',
      days_back: daysBack,
      threshold_min_messages: minMessages,
    });
  }

  const windowEnd   = new Date();
  const windowStart = new Date(windowEnd.getTime() - daysBack * 24 * 60 * 60 * 1000);

  const { data: msgRows, error: msgErr } = await admin
    .from('support_chatbot_messages')
    .select('content, role, created_at, support_chatbot_sessions!inner(escalated)')
    .eq('role', 'user')
    .gte('created_at', windowStart.toISOString())
    .lt('created_at', windowEnd.toISOString())
    .order('created_at', { ascending: false })
    .limit(200);

  if (msgErr) {
    console.error('[analyze v4] msg fetch err:', msgErr.message);
    return jsonResponse({ error: 'msg_fetch_failed', detail: msgErr.message }, 500);
  }

  const messages = (msgRows ?? []).map((m: any) => ({
    content: anonymize((m.content as string) ?? ''),
    escalated: m.support_chatbot_sessions?.escalated === true,
    created_at: m.created_at,
  }));

  messages.sort((a, b) => Number(b.escalated) - Number(a.escalated));

  if (messages.length < minMessages) {
    await admin.from('support_settings')
      .update({ last_skill_analysis_at: new Date().toISOString() })
      .eq('id', 1);
    return jsonResponse({
      analyzed_messages: messages.length,
      suggestions_created: 0,
      duplicates_skipped: 0,
      window_start: windowStart.toISOString(),
      window_end:   windowEnd.toISOString(),
      reason: 'below_threshold',
      threshold: minMessages,
    });
  }

  const { data: skillsRows } = await admin
    .from('support_skills')
    .select('id, skill_name, mode, playbook_md')
    .eq('active', true);
  const skillsList = (skillsRows ?? []) as Array<{
    id: string; skill_name: string; mode: string; playbook_md: string;
  }>;
  const skillNames = skillsList.map((s) => s.skill_name);
  const skillByName = new Map(skillsList.map((s) => [s.skill_name, s]));

  const safeSettingsSnapshot: Record<string, unknown> = {};
  if (settingsRow) {
    for (const k of SAFE_SETTING_KEYS) {
      if (k in settingsRow) safeSettingsSnapshot[k] = (settingsRow as any)[k];
    }
  }

  const { data: pendingRows } = await admin
    .from('skill_suggestions').select('pattern_summary').eq('status', 'pending');
  const pendingSummaries = (pendingRows ?? []).map((r: any) => r.pattern_summary as string);

  // gemini_model nas sugestões = o motor:modelo que respondeu (preenchido depois da chamada).
  let geminiModel = 'claude-haiku-5-5';

  const systemPrompt =
    'Es um analista de suporte da Bora App. Identifica padroes em mensagens de clientes.\n' +
    '\n' +
    'Podes propor 3 tipos de melhoria. Retorna APENAS um JSON array (sem markdown, sem ```json fences).\n' +
    '\n' +
    'TIPO 1 - new_skill: criar skill nova quando padrao nao esta coberto.\n' +
    '  Schema: { "proposal_type":"new_skill", "pattern_summary": string<=200, ' +
    '"message_count": number, "sample_messages": string[3..5], ' +
    '"suggested_skill_name": string (UPPER_SNAKE_CASE), "suggested_category": string, ' +
    '"suggested_mode": "read_only"|"write_shadow"|"escalate", ' +
    '"suggested_playbook_md": string (markdown ## seccoes), ' +
    '"suggested_allowed_tools": string[], "zone_type":"safe" }\n' +
    '\n' +
    'TIPO 2 - playbook_update: actualizar playbook de skill existente quando ela responde mal.\n' +
    '  Schema: { "proposal_type":"playbook_update", "target_skill_name": string (EXACTO de skills existentes), ' +
    '"zone_type": "safe"|"critical", "suggested_playbook_md": string (NOVO playbook completo, markdown), ' +
    '"pattern_summary": string<=200 }\n' +
    '  Skills CRITICAL (sempre zone_type="critical"): ' + JSON.stringify(CRITICAL_SKILLS) + '\n' +
    '  Para outras skills, zone_type="safe".\n' +
    '\n' +
    'TIPO 3 - settings_update: actualizar configuracao quando precisa ajuste.\n' +
    '  Schema: { "proposal_type":"settings_update", ' +
    '"target_setting_key": string (apenas SAFE keys), ' +
    '"target_setting_value": string, "zone_type":"safe", ' +
    '"pattern_summary": string<=200 }\n' +
    '  SAFE keys permitidas: ' + JSON.stringify(SAFE_SETTING_KEYS) + '\n' +
    '  NAO sugerir settings_update para outras keys.\n' +
    '\n' +
    'Identifica 1-5 propostas no total. Se nada novo, retorna [].\n' +
    'Para target_setting_key, regex obrigatoria: ^[a-z_]+$. Para target_skill_name, deve estar nas skills existentes.';

  const userPrompt =
    'Skills existentes (nome, modo): ' + JSON.stringify(skillsList.map((s) => ({ name: s.skill_name, mode: s.mode }))) + '\n\n' +
    'SAFE settings actuais: ' + JSON.stringify(safeSettingsSnapshot) + '\n\n' +
    'Pending suggestions (nao duplicar): ' + JSON.stringify(pendingSummaries) + '\n\n' +
    'Mensagens user (' + daysBack + ' dias, anonimizadas, max 200): ' +
    JSON.stringify(messages.slice(0, 200).map((m) => m.content)) +
    '\n\nIdentifica padroes. Retorna APENAS JSON array.';

  let suggestions: any[] = [];
  let geminiError: string | null = null;

  const ia = await pedirIa({
    robo: 'edge-analise-suporte',
    prioridade: 3,
    sistema: systemPrompt,
    texto: userPrompt,
    json: true,
    privado: true,
    maxTokens: 8192,
    prazoMs: 120_000,
    timeoutClaudeMs: 90_000,
  });
  if (!ia.ok) {
    geminiError = ia.erro;
  } else if (Array.isArray(ia.json)) {
    suggestions = ia.json as any[];
    geminiModel = `${ia.motor}:${ia.modelo}`;
  } else {
    geminiError = `${ia.motor}_returned_non_array`;
  }

  await admin.from('support_settings')
    .update({ last_skill_analysis_at: new Date().toISOString() })
    .eq('id', 1);

  if (geminiError) {
    console.error('[analyze v4]', geminiError);
    return jsonResponse({
      analyzed_messages: messages.length,
      suggestions_created: 0,
      duplicates_skipped: 0,
      window_start: windowStart.toISOString(),
      window_end:   windowEnd.toISOString(),
      gemini_error: geminiError,
    }, 502);
  }

  let created = 0;
  let skipped = 0;
  const skillNameSet = new Set(skillNames);
  const breakdown = { new_skill: 0, playbook_update: 0, settings_update: 0 };

  for (const s of suggestions) {
    if (!isObject(s)) { skipped++; continue; }

    const proposalType = String(s.proposal_type ?? 'new_skill').trim();
    const summary = String(s.pattern_summary ?? '').slice(0, 200).trim();
    if (!summary) { skipped++; continue; }

    const hash = await sha256Hex(summary.toLowerCase().trim());
    const sampleMsgs = Array.isArray(s.sample_messages)
      ? (s.sample_messages as unknown[]).slice(0, 5).map((x) => String(x).slice(0, 500))
      : [];
    const msgCount = Number(s.message_count ?? sampleMsgs.length) | 0;

    if (proposalType === 'new_skill') {
      const skillName = String(s.suggested_skill_name ?? '').trim().toUpperCase();
      if (!skillName || skillNameSet.has(skillName)) { skipped++; continue; }

      const mode = String(s.suggested_mode ?? 'read_only').trim();
      const allowedMode = ['read_only', 'write_shadow', 'escalate'].includes(mode)
        ? mode : 'read_only';

      const tools = Array.isArray(s.suggested_allowed_tools)
        ? (s.suggested_allowed_tools as unknown[]).map((x) => String(x))
        : [];

      const { error: insErr } = await admin.from('skill_suggestions').insert({
        proposal_type:           'new_skill',
        zone_type:               'safe',
        pattern_summary:         summary,
        sample_messages:         sampleMsgs,
        message_count:           msgCount,
        suggested_skill_name:    skillName,
        suggested_category:      String(s.suggested_category ?? 'general').slice(0, 80),
        suggested_mode:          allowedMode,
        suggested_playbook_md:   String(s.suggested_playbook_md ?? ''),
        suggested_allowed_tools: tools,
        pattern_hash:            hash,
        gemini_model:            geminiModel,
        analysis_window_start:   windowStart.toISOString(),
        analysis_window_end:     windowEnd.toISOString(),
      });

      if (insErr) { skipped++; }
      else { created++; breakdown.new_skill++; }
      continue;
    }

    if (proposalType === 'playbook_update') {
      const targetName = String(s.target_skill_name ?? '').trim();
      const target = skillByName.get(targetName);
      if (!target) { skipped++; continue; }
      const zoneType = CRITICAL_SKILLS.includes(targetName) ? 'critical' : 'safe';

      const { error: insErr } = await admin.from('skill_suggestions').insert({
        proposal_type:         'playbook_update',
        zone_type:             zoneType,
        target_skill_id:       target.id,
        previous_value:        target.playbook_md,
        pattern_summary:       summary,
        sample_messages:       sampleMsgs,
        message_count:         msgCount,
        suggested_playbook_md: String(s.suggested_playbook_md ?? ''),
        pattern_hash:          hash,
        gemini_model:          geminiModel,
        analysis_window_start: windowStart.toISOString(),
        analysis_window_end:   windowEnd.toISOString(),
      });

      if (insErr) { skipped++; }
      else { created++; breakdown.playbook_update++; }
      continue;
    }

    if (proposalType === 'settings_update') {
      const key = String(s.target_setting_key ?? '').trim();
      const val = String(s.target_setting_value ?? '').trim();

      if (!/^[a-z_]+$/.test(key)) { skipped++; continue; }
      if (!SAFE_SETTING_KEYS.includes(key)) { skipped++; continue; }
      if (!val) { skipped++; continue; }

      const previousValue = key in safeSettingsSnapshot
        ? String(safeSettingsSnapshot[key] ?? '')
        : null;

      const { error: insErr } = await admin.from('skill_suggestions').insert({
        proposal_type:        'settings_update',
        zone_type:            'safe',
        target_setting_key:   key,
        target_setting_value: val,
        previous_value:       previousValue,
        pattern_summary:      summary,
        sample_messages:      sampleMsgs,
        message_count:        msgCount,
        pattern_hash:         hash,
        gemini_model:         geminiModel,
        analysis_window_start: windowStart.toISOString(),
        analysis_window_end:   windowEnd.toISOString(),
      });

      if (insErr) { skipped++; }
      else { created++; breakdown.settings_update++; }
      continue;
    }

    skipped++;
  }

  return jsonResponse({
    analyzed_messages: messages.length,
    suggestions_created: created,
    duplicates_skipped: skipped,
    breakdown,
    gemini_returned: suggestions.length,
    window_start: windowStart.toISOString(),
    window_end:   windowEnd.toISOString(),
    triggered_by: scheduled ? 'cron' : (isService ? 'service' : 'admin'),
  });
});
