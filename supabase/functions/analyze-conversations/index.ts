// Sessao 5E B3 - Edge Fn analyze-conversations v2
// Analisa support_chatbot_messages 7 dias e propoe 3 tipos via Gemini:
//   1. new_skill        (5D mantido)
//   2. playbook_update  (NOVO 5E — actualizar playbook skill existente)
//   3. settings_update  (NOVO 5E — actualizar support_settings SAFE)
// POST { scheduled?: boolean, days_back?: int, dry_run?: boolean }
// verify_jwt: true. Admin-only via app_metadata.role='admin' OR
// service_role JWT (cron use).

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

// SAFE settings whitelist (mirror RPC admin_approve_skill_suggestion)
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

// CRITICAL skills (mirror RPC). OTP_RESEND defensivo: nao existe ainda.
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

  const authHeader = req.headers.get('Authorization') ?? '';
  const token = authHeader.replace(/^Bearer\s+/i, '').trim();
  if (!token) return jsonResponse({ error: 'missing_token' }, 401);

  let body: { scheduled?: boolean; days_back?: number; dry_run?: boolean } = {};
  try { body = await req.json(); } catch { /* default empty */ }
  const scheduled = body.scheduled === true;
  const daysBack  = Math.max(1, Math.min(30, Number(body.days_back ?? 7) | 0));
  const dryRun    = body.dry_run === true;

  const userClient = createClient(SUPABASE_URL, SUPABASE_ANON_KEY, {
    global: { headers: { Authorization: `Bearer ${token}` } },
  });
  const { data: userData, error: authErr } = await userClient.auth.getUser();

  let isService = false;
  let isAdmin = false;
  if (authErr || !userData?.user) {
    if (token === SUPABASE_SERVICE_ROLE_KEY) {
      isService = true;
    } else {
      return jsonResponse({ error: 'unauthorized' }, 401);
    }
  } else {
    isAdmin = userData.user.app_metadata?.role === 'admin';
  }

  if (!isService && !isAdmin) {
    return jsonResponse({ error: 'admin_required' }, 403);
  }

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

  if (!GEMINI_API_KEY) {
    return jsonResponse({
      error: 'gemini_key_missing',
      analyzed_messages: 0,
      suggestions_created: 0,
    }, 503);
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
    console.error('[analyze] msg fetch err:', msgErr.message);
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

  // 5E: fetch skills with id+playbook_md (para lookup playbook_update)
  const { data: skillsRows } = await admin
    .from('support_skills')
    .select('id, skill_name, mode, playbook_md')
    .eq('active', true);
  const skillsList = (skillsRows ?? []) as Array<{
    id: string; skill_name: string; mode: string; playbook_md: string;
  }>;
  const skillNames = skillsList.map((s) => s.skill_name);
  const skillByName = new Map(skillsList.map((s) => [s.skill_name, s]));

  // 5E: build SAFE settings snapshot for prompt
  const safeSettingsSnapshot: Record<string, unknown> = {};
  if (settingsRow) {
    for (const k of SAFE_SETTING_KEYS) {
      if (k in settingsRow) safeSettingsSnapshot[k] = (settingsRow as any)[k];
    }
  }

  const { data: pendingRows } = await admin
    .from('skill_suggestions').select('pattern_summary').eq('status', 'pending');
  const pendingSummaries = (pendingRows ?? []).map((r: any) => r.pattern_summary as string);

  // 2026-08-12: fallback era gemini-1.5-flash (retirado). Só usado se a BD não responder.
  const geminiModel = (settingsRow?.gemini_model as string) ?? 'gemini-3.1-flash-lite';

  // 5E system prompt: 3 tipos
  const systemPrompt =
    'Es um analista de suporte da Bora App. Identifica padroes em mensagens de clientes.\n' +
    '\n' +
    'Podes propor 3 tipos de melhoria. Retorna APENAS um JSON array (sem markdown, sem ```json fences).\n' +
    '\n' +
    'TIPO 1 — new_skill: criar skill nova quando padrao nao esta coberto.\n' +
    '  Schema: { "proposal_type":"new_skill", "pattern_summary": string<=200, ' +
    '"message_count": number, "sample_messages": string[3..5], ' +
    '"suggested_skill_name": string (UPPER_SNAKE_CASE), "suggested_category": string, ' +
    '"suggested_mode": "read_only"|"write_shadow"|"escalate", ' +
    '"suggested_playbook_md": string (markdown ## seccoes), ' +
    '"suggested_allowed_tools": string[], "zone_type":"safe" }\n' +
    '\n' +
    'TIPO 2 — playbook_update: actualizar playbook de skill existente quando ela responde mal.\n' +
    '  Schema: { "proposal_type":"playbook_update", "target_skill_name": string (EXACTO de skills existentes), ' +
    '"zone_type": "safe"|"critical", "suggested_playbook_md": string (NOVO playbook completo, markdown), ' +
    '"pattern_summary": string<=200 }\n' +
    '  Skills CRITICAL (sempre zone_type="critical"): ' + JSON.stringify(CRITICAL_SKILLS) + '\n' +
    '  Para outras skills, zone_type="safe".\n' +
    '\n' +
    'TIPO 3 — settings_update: actualizar configuracao quando precisa ajuste.\n' +
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

  try {
    const url = `https://generativelanguage.googleapis.com/v1beta/models/${geminiModel}:generateContent`;
    const resp = await fetch(url, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json', 'x-goog-api-key': GEMINI_API_KEY },
      body: JSON.stringify({
        system_instruction: { parts: [{ text: systemPrompt }] },
        contents: [{ role: 'user', parts: [{ text: userPrompt }] }],
        // 5E: 4096 -> 8192 (playbook_update payloads sao maiores)
        generationConfig: { maxOutputTokens: 8192, temperature: 0.3 },
      }),
    });
    if (!resp.ok) {
      const txt = await resp.text();
      geminiError = `gemini http ${resp.status}: ${txt.slice(0, 300)}`;
    } else {
      const j = await resp.json();
      const cand = j?.candidates?.[0];
      let raw = (cand?.content?.parts ?? [])
        .map((p: any) => p.text ?? '').join('').trim();
      raw = raw.replace(/^```(?:json)?\s*\n?/i, '').replace(/\n?```\s*$/i, '').trim();
      try {
        const parsed = JSON.parse(raw);
        if (Array.isArray(parsed)) suggestions = parsed;
        else geminiError = 'gemini_returned_non_array';
      } catch (e) {
        geminiError = 'gemini_parse_fail: ' + (e as Error).message + ' raw: ' + raw.slice(0, 200);
      }
    }
  } catch (e) {
    geminiError = 'gemini_fetch_fail: ' + (e as Error).message;
  }

  await admin.from('support_settings')
    .update({ last_skill_analysis_at: new Date().toISOString() })
    .eq('id', 1);

  if (geminiError) {
    console.error('[analyze]', geminiError);
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

    // ─── Tipo 1: new_skill ───
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

    // ─── Tipo 2: playbook_update ───
    if (proposalType === 'playbook_update') {
      const targetName = String(s.target_skill_name ?? '').trim();
      const target = skillByName.get(targetName);
      if (!target) {
        console.warn('[analyze] playbook_update target not found:', targetName);
        skipped++; continue;
      }
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

    // ─── Tipo 3: settings_update ───
    if (proposalType === 'settings_update') {
      const key = String(s.target_setting_key ?? '').trim();
      const val = String(s.target_setting_value ?? '').trim();

      if (!/^[a-z_]+$/.test(key)) {
        console.warn('[analyze] settings_update invalid key format:', key);
        skipped++; continue;
      }
      if (!SAFE_SETTING_KEYS.includes(key)) {
        console.warn('[analyze] settings_update key not in whitelist:', key);
        skipped++; continue;
      }
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

    // Unknown type
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
