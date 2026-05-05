// Sessão 5A-1 B9 — Edge Fn support-chatbot
// Gemini 1.5 Flash + tool-calling whitelisted + defesas anti-injection.
// verify_jwt: true. POST { session_id?, message, order_id? }.

import { createClient } from 'https://esm.sh/@supabase/supabase-js@2.45.0';
import { corsHeaders } from '../_shared/cors.ts';

const SUPABASE_URL = Deno.env.get('SUPABASE_URL')!;
const SUPABASE_ANON_KEY = Deno.env.get('SUPABASE_ANON_KEY')!;
const SUPABASE_SERVICE_ROLE_KEY = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!;
const GEMINI_API_KEY = Deno.env.get('GEMINI_API_KEY');

const TOOL_WHITELIST = new Set([
  'agent_get_user_orders_summary',
  'agent_get_order_status',
  'agent_get_user_wallet_summary',
  'agent_get_user_tokens_summary',
  'agent_get_refund_status',
]);

const SYSTEM_DELIM_OPEN = '<<<SYSTEM>>>';
const SYSTEM_DELIM_CLOSE = '<<<END_SYSTEM>>>';

// === RAG (5C-β) ===
const RAG_EMBED_ENDPOINT =
  'https://generativelanguage.googleapis.com/v1beta/models/gemini-embedding-001:embedContent';
const RAG_EMBED_DIM = 768;
const RAG_EMBED_TIMEOUT_MS = 1500;
const RAG_MATCH_COUNT = 8;
const RAG_DEDUP_PER_FILE = 2;
const RAG_FINAL_LIMIT = 5;
const RAG_MIN_SIMILARITY = 0.5;

async function sha256Hex(text: string): Promise<string | null> {
  try {
    const buf = await crypto.subtle.digest(
      'SHA-256',
      new TextEncoder().encode(text),
    );
    return Array.from(new Uint8Array(buf))
      .map((b) => b.toString(16).padStart(2, '0'))
      .join('');
  } catch (e) {
    console.warn('[RAG] SHA256 unavailable:', (e as Error).message);
    return null;
  }
}

interface SupportSettings {
  rate_limit_per_user_day: number;
  max_messages_per_session: number;
  max_output_tokens_per_call: number;
  max_user_message_chars: number;
  max_tool_iterations: number;
  gemini_model: string;
  support_agent_enabled: boolean;
  whatsapp_number: string;
  support_email: string;
  rag_enabled: boolean;
}

function jsonResponse(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, 'Content-Type': 'application/json' },
  });
}

// Strip ASCII control chars (0x00-0x1F) except TAB(0x09) and LF(0x0A).
function stripControlChars(s: string): string {
  let out = '';
  for (let i = 0; i < s.length; i++) {
    const code = s.charCodeAt(i);
    if (code < 32 && code !== 9 && code !== 10) continue;
    if (code === 127) continue; // DEL
    out += s[i];
  }
  return out;
}

function sanitizeMessage(input: string, maxChars: number): { ok: boolean; out?: string; err?: string } {
  if (typeof input !== 'string') return { ok: false, err: 'message must be string' };
  const cleaned = stripControlChars(input);
  if (cleaned.includes(SYSTEM_DELIM_OPEN) || cleaned.includes(SYSTEM_DELIM_CLOSE)) {
    return { ok: false, err: 'message contains reserved system delimiter' };
  }
  const truncated = cleaned.length > maxChars ? cleaned.slice(0, maxChars) : cleaned;
  if (truncated.trim().length === 0) return { ok: false, err: 'message empty' };
  return { ok: true, out: truncated };
}

function buildFunctionDeclarations() {
  return [
    {
      name: 'agent_get_user_orders_summary',
      description: 'Devolve os ultimos pedidos do utilizador (ate 20). Nao recebe user_id, usa o JWT da chamada.',
      parameters: {
        type: 'object',
        properties: {
          p_limit: { type: 'integer', description: 'Maximo de pedidos (1-20). Default 5.' },
        },
      },
    },
    {
      name: 'agent_get_order_status',
      description: 'Devolve estado detalhado de um pedido especifico do user. Falha se o pedido nao pertencer ao user.',
      parameters: {
        type: 'object',
        properties: {
          p_order_id: { type: 'string', description: 'ID do pedido (texto, formato legacy).' },
        },
        required: ['p_order_id'],
      },
    },
    {
      name: 'agent_get_user_wallet_summary',
      description: 'Devolve saldo wallet free do user em centimos + estado de bloqueio (soft -10euros / hard -20euros).',
      parameters: { type: 'object', properties: {} },
    },
    {
      name: 'agent_get_user_tokens_summary',
      description: 'Devolve total de tokens validos (nao usados, nao expirados) + tokens a expirar nos proximos 7 dias.',
      parameters: { type: 'object', properties: {} },
    },
    {
      name: 'agent_get_refund_status',
      description: 'Devolve estado de reembolso para um pedido. Falha se o pedido nao pertencer ao user.',
      parameters: {
        type: 'object',
        properties: {
          p_order_id: { type: 'string', description: 'ID do pedido.' },
        },
        required: ['p_order_id'],
      },
    },
  ];
}

function buildSystemPrompt(
  userRole: string,
  orderId: string | null,
  settings: SupportSettings,
  skillsMd: string,
  ragContext: string,
): string {
  const lines = [
    SYSTEM_DELIM_OPEN,
    'Es o agente IA da Bora App, plataforma de entregas em Guarda, Portugal.',
    'Linguagem: PT europeu, tom amigavel e directo.',
    `Utilizador: role=${userRole}${orderId ? `, pedido em foco=${orderId}` : ''}.`,
    '',
    'REGRA CRITICA #1: NUNCA calculas dinheiro, refunds, creditos ou estimativas financeiras.',
    'Se a pergunta envolve calculo financeiro, escala via skill HUMAN_REQUEST.',
    'REGRA CRITICA #2: NUNCA inventas valores. Se nao tens info via tool, dizes-o e ofereces humano.',
    'REGRA #3: Respostas curtas (<=3 frases) excepto se explicacao tecnica necessaria.',
    'REGRA #4: Em caso de duvida ou queixa seria, marca [HANDOFF_HUMAN] no fim para escalar.',
    '',
    `WhatsApp suporte: ${settings.whatsapp_number}. Email: ${settings.support_email}.`,
    '',
    'Skills disponiveis (read-only, 5A):',
    skillsMd || '(vazio - seed em 5A-2)',
  ];
  if (ragContext) {
    lines.push('', ragContext);
  }
  lines.push(SYSTEM_DELIM_CLOSE);
  return lines.join('\n');
}

async function callRpc(
  userJwt: string,
  toolName: string,
  toolArgs: Record<string, unknown>,
): Promise<{ ok: boolean; data?: unknown; error?: string }> {
  if (!TOOL_WHITELIST.has(toolName)) {
    return { ok: false, error: `tool ${toolName} not whitelisted` };
  }
  const userClient = createClient(SUPABASE_URL, SUPABASE_ANON_KEY, {
    global: { headers: { Authorization: `Bearer ${userJwt}` } },
  });
  const { data, error } = await userClient.rpc(toolName, toolArgs);
  if (error) return { ok: false, error: error.message };
  return { ok: true, data };
}

async function callGemini(
  apiKey: string,
  model: string,
  systemPrompt: string,
  contents: unknown[],
  tools: unknown[],
  maxOutputTokens: number,
): Promise<{ ok: boolean; data?: any; error?: string }> {
  const url = `https://generativelanguage.googleapis.com/v1beta/models/${model}:generateContent`;
  const body = {
    system_instruction: { parts: [{ text: systemPrompt }] },
    contents,
    tools: [{ function_declarations: tools }],
    generationConfig: { maxOutputTokens, temperature: 0.4 },
  };
  try {
    const resp = await fetch(url, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json', 'x-goog-api-key': apiKey },
      body: JSON.stringify(body),
    });
    if (!resp.ok) {
      const text = await resp.text();
      return { ok: false, error: `gemini http ${resp.status}: ${text.slice(0, 500)}` };
    }
    const j = await resp.json();
    return { ok: true, data: j };
  } catch (e) {
    return { ok: false, error: `gemini fetch fail: ${(e as Error).message}` };
  }
}

// === RAG context builder (5C-β) ===
async function buildRagContext(
  userMessage: string,
  // deno-lint-ignore no-explicit-any
  adminClient: any,
): Promise<string> {
  if (!GEMINI_API_KEY) return '';

  const queryNorm = userMessage.trim().toLowerCase().substring(0, 500);
  const queryHash = await sha256Hex(queryNorm);
  let queryEmbedding: number[] | null = null;

  // 1. Cache lookup (skip se queryHash null)
  if (queryHash) {
    const { data: cached } = await adminClient
      .from('support_embedding_cache')
      .select('embedding, hit_count')
      .eq('query_hash', queryHash)
      .maybeSingle();

    if (cached?.embedding) {
      try {
        const raw = cached.embedding;
        queryEmbedding = typeof raw === 'string'
          ? JSON.parse(raw) as number[]
          : raw as number[];
      } catch {
        queryEmbedding = null;
      }
      if (queryEmbedding && queryEmbedding.length === RAG_EMBED_DIM) {
        await adminClient
          .from('support_embedding_cache')
          .update({
            last_used_at: new Date().toISOString(),
            hit_count: (cached.hit_count ?? 1) + 1,
          })
          .eq('query_hash', queryHash);
        console.log('[RAG] cache HIT');
      } else {
        queryEmbedding = null;
      }
    }
  }

  // 2. Cache miss → Gemini embedding com timeout 1.5s
  if (!queryEmbedding) {
    const ctrl = new AbortController();
    const tid = setTimeout(() => ctrl.abort(), RAG_EMBED_TIMEOUT_MS);
    try {
      const embRes = await fetch(RAG_EMBED_ENDPOINT, {
        method: 'POST',
        signal: ctrl.signal,
        headers: {
          'Content-Type': 'application/json',
          'x-goog-api-key': GEMINI_API_KEY,
        },
        body: JSON.stringify({
          content: { parts: [{ text: userMessage }] },
          outputDimensionality: RAG_EMBED_DIM,
          taskType: 'RETRIEVAL_QUERY',
        }),
      });
      clearTimeout(tid);

      if (embRes.ok) {
        const embData = await embRes.json();
        const values = embData?.embedding?.values;
        if (Array.isArray(values) && values.length === RAG_EMBED_DIM) {
          queryEmbedding = values;
          if (queryHash) {
            const embLit = `[${queryEmbedding.join(',')}]`;
            await adminClient
              .from('support_embedding_cache')
              .upsert({
                query_hash: queryHash,
                query_text: userMessage.substring(0, 500),
                embedding: embLit,
              }, {
                onConflict: 'query_hash',
                ignoreDuplicates: true,
              });
            console.log('[RAG] cache MISS → embedded + cached');
          }
        } else {
          console.warn('[RAG] unexpected embedding shape');
        }
      } else {
        console.warn('[RAG] embedding http', embRes.status);
      }
    } catch (e) {
      clearTimeout(tid);
      console.warn('[RAG] embedding timeout/error:', (e as Error).message);
    }
  }

  if (!queryEmbedding) return '';

  // 3. Match knowledge top-N com dedup por source_file
  const { data: chunks, error: matchErr } = await adminClient.rpc('match_knowledge', {
    query_embedding: queryEmbedding,
    match_count: RAG_MATCH_COUNT,
    min_similarity: RAG_MIN_SIMILARITY,
  });

  if (matchErr) {
    console.warn('[RAG] match_knowledge error:', matchErr.message);
    return '';
  }
  if (!chunks || chunks.length === 0) {
    console.log('[RAG] no chunks above threshold');
    return '';
  }

  const fileCounts = new Map<string, number>();
  // deno-lint-ignore no-explicit-any
  const dedup = (chunks as any[]).filter((c) => {
    const cnt = fileCounts.get(c.source_file) || 0;
    if (cnt >= RAG_DEDUP_PER_FILE) return false;
    fileCounts.set(c.source_file, cnt + 1);
    return true;
  }).slice(0, RAG_FINAL_LIMIT);

  const ragContext =
    '=== CONHECIMENTO BORA APP ===\n' +
    '(Contexto de fundo — usa apenas se relevante para a pergunta; tools mantem fluxo principal)\n\n' +
    // deno-lint-ignore no-explicit-any
    dedup.map((c: any) =>
      `[${c.source_type}/${c.section_title ?? 'geral'}]\n${c.chunk_text}`
    ).join('\n\n---\n\n') +
    '\n=== FIM CONHECIMENTO ===';

  console.log('[RAG] chunks:', chunks.length, '| after dedup:', dedup.length, '| context chars:', ragContext.length);
  return ragContext;
}

Deno.serve(async (req: Request) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: corsHeaders });
  if (req.method !== 'POST') return jsonResponse({ error: 'method not allowed' }, 405);

  if (!GEMINI_API_KEY) {
    return jsonResponse({
      error: 'GEMINI_API_KEY missing',
      reply: 'Estou temporariamente indisponivel. Posso transferir-te para WhatsApp ou Email?',
      escalated: false,
      handoff_required: true,
    }, 503);
  }

  const authHeader = req.headers.get('Authorization');
  if (!authHeader?.startsWith('Bearer ')) return jsonResponse({ error: 'no jwt' }, 401);
  const userJwt = authHeader.replace('Bearer ', '');

  const userClient = createClient(SUPABASE_URL, SUPABASE_ANON_KEY, {
    global: { headers: { Authorization: `Bearer ${userJwt}` } },
  });
  const { data: userData, error: userErr } = await userClient.auth.getUser();
  if (userErr || !userData?.user) return jsonResponse({ error: 'invalid jwt' }, 401);
  const userId = userData.user.id;
  const userRole = (userData.user.user_metadata?.bora_role as string | undefined) ?? 'client';

  let payload: { session_id?: string; message?: string; order_id?: string };
  try {
    payload = await req.json();
  } catch {
    return jsonResponse({ error: 'invalid json' }, 400);
  }

  const adminClient = createClient(SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY);

  const { data: settingsRow } = await adminClient
    .from('support_settings').select('*').eq('id', 1).single();
  const settings = settingsRow as SupportSettings | null;
  if (!settings || !settings.support_agent_enabled) {
    return jsonResponse({
      reply: 'O agente IA esta temporariamente desactivado. Podes contactar via WhatsApp ou Email.',
      escalated: false,
      handoff_required: true,
    }, 503);
  }

  const sani = sanitizeMessage(payload.message ?? '', settings.max_user_message_chars);
  if (!sani.ok) return jsonResponse({ error: sani.err }, 400);
  const userMessage = sani.out!;

  const today = new Date().toISOString().slice(0, 10);
  const { data: quotaRow } = await adminClient
    .from('support_chatbot_quota')
    .select('messages_count').eq('user_id', userId).eq('day', today).maybeSingle();
  const usedToday = (quotaRow?.messages_count as number | undefined) ?? 0;
  if (usedToday >= settings.rate_limit_per_user_day) {
    return jsonResponse({
      reply: 'Atingiste o limite diario de mensagens. Tenta amanha ou contacta WhatsApp/Email.',
      escalated: false,
      handoff_required: true,
      messages_remaining_today: 0,
    }, 429);
  }

  let sessionId = payload.session_id;
  let messagesCount = 0;
  if (sessionId) {
    const { data: sess } = await adminClient
      .from('support_chatbot_sessions')
      .select('id, user_id, messages_count')
      .eq('id', sessionId).maybeSingle();
    if (!sess || sess.user_id !== userId) {
      return jsonResponse({ error: 'session not found or not owner' }, 404);
    }
    messagesCount = (sess.messages_count as number | undefined) ?? 0;
    if (messagesCount >= settings.max_messages_per_session) {
      return jsonResponse({
        reply: 'Esta conversa atingiu o limite. Posso transferir-te para humano?',
        escalated: false,
        handoff_required: true,
        messages_remaining_session: 0,
      }, 429);
    }
  } else {
    const { data: newSess, error: newErr } = await adminClient
      .from('support_chatbot_sessions')
      .insert({ user_id: userId, user_role: userRole, order_id: payload.order_id ?? null })
      .select('id').single();
    if (newErr || !newSess) return jsonResponse({ error: 'session create fail' }, 500);
    sessionId = newSess.id as string;
  }

  await adminClient.from('support_chatbot_messages').insert({
    session_id: sessionId, role: 'user', content: userMessage,
  });

  const { data: histRows } = await adminClient
    .from('support_chatbot_messages')
    .select('role, content, tool_name, tool_input, tool_output')
    .eq('session_id', sessionId)
    .order('created_at', { ascending: false })
    .limit(10);
  const history = (histRows ?? []).reverse();

  const { data: skillRows } = await adminClient
    .from('support_skills').select('skill_name, playbook_md').eq('active', true);
  const skillsMd = (skillRows ?? [])
    .map((s: { skill_name: string; playbook_md: string }) =>
      `### ${s.skill_name}\n${s.playbook_md}`)
    .join('\n\n');

  // === RAG CONTEXT INJECTION (5C-β) ===
  // Skills (instruções) ficam PRIMEIRO no prompt; ragContext (contexto) DEPOIS.
  // Try/catch garante fallback graceful — chatbot funciona sem RAG se falhar.
  let ragContext = '';
  if (settings.rag_enabled === true) {
    try {
      ragContext = await buildRagContext(userMessage, adminClient);
    } catch (e) {
      console.error('[RAG] injection error (fallback sem RAG):', (e as Error).message);
      ragContext = '';
    }
  }
  // === FIM RAG ===

  const systemPrompt = buildSystemPrompt(userRole, payload.order_id ?? null, settings, skillsMd, ragContext);
  const tools = buildFunctionDeclarations();

  const contents: any[] = [];
  for (const m of history) {
    if (m.role === 'user') {
      contents.push({ role: 'user', parts: [{ text: m.content }] });
    } else if (m.role === 'assistant') {
      contents.push({ role: 'model', parts: [{ text: m.content }] });
    } else if (m.role === 'tool') {
      contents.push({
        role: 'function',
        parts: [{
          functionResponse: {
            name: m.tool_name ?? 'unknown',
            response: { result: m.tool_output ?? null },
          },
        }],
      });
    }
  }

  let finalText = '';
  let escalated = false;
  let toolIters = 0;
  let totalTokens = 0;
  let geminiOk = true;
  let geminiError: string | undefined;

  while (toolIters <= settings.max_tool_iterations) {
    const gemRes = await callGemini(
      GEMINI_API_KEY, settings.gemini_model, systemPrompt, contents, tools,
      settings.max_output_tokens_per_call,
    );
    if (!gemRes.ok) {
      geminiOk = false;
      geminiError = gemRes.error;
      break;
    }
    const usage = gemRes.data?.usageMetadata?.totalTokenCount;
    if (typeof usage === 'number') totalTokens = usage;
    const cand = gemRes.data?.candidates?.[0];
    const parts = cand?.content?.parts ?? [];
    const fnCallPart = parts.find((p: any) => p.functionCall);
    if (fnCallPart) {
      const fnName: string = fnCallPart.functionCall.name;
      const fnArgs: Record<string, unknown> = fnCallPart.functionCall.args ?? {};
      if (!TOOL_WHITELIST.has(fnName)) {
        finalText = 'Erro interno: ferramenta nao autorizada. Posso transferir-te para humano?';
        escalated = true;
        break;
      }
      const rpcRes = await callRpc(userJwt, fnName, fnArgs);
      await adminClient.from('support_chatbot_messages').insert({
        session_id: sessionId, role: 'tool',
        content: rpcRes.ok ? 'ok' : (rpcRes.error ?? 'rpc error'),
        tool_name: fnName, tool_input: fnArgs,
        tool_output: rpcRes.ok ? rpcRes.data : { error: rpcRes.error },
      });
      contents.push({ role: 'model', parts: [{ functionCall: fnCallPart.functionCall }] });
      contents.push({
        role: 'function',
        parts: [{
          functionResponse: {
            name: fnName,
            response: rpcRes.ok ? { result: rpcRes.data } : { error: rpcRes.error },
          },
        }],
      });
      toolIters++;
      continue;
    }
    finalText = parts.map((p: any) => p.text ?? '').join('').trim();
    break;
  }

  if (toolIters > settings.max_tool_iterations && !finalText) {
    finalText = 'Nao consegui resolver. Posso transferir-te para WhatsApp/Email?';
    escalated = true;
  }
  if (!geminiOk) {
    finalText = 'Estou temporariamente indisponivel. Posso transferir-te para WhatsApp ou Email?';
    escalated = true;
  }
  if (finalText.includes('[HANDOFF_HUMAN]')) {
    escalated = true;
    finalText = finalText.replace('[HANDOFF_HUMAN]', '').trim();
  }

  await adminClient.from('support_chatbot_messages').insert({
    session_id: sessionId, role: 'assistant', content: finalText,
    tokens_used: totalTokens || null,
  });

  const newCount = messagesCount + 1;
  let ticketId: string | null = null;
  if (escalated) {
    const { data: tk } = await adminClient.from('support_tickets').insert({
      user_id: userId,
      user_role: userRole,
      channel: 'chatbot',
      subject: 'Pedido de atendimento humano',
      question: userMessage.slice(0, 4000),
      body: finalText.slice(0, 5000),
      order_id: payload.order_id ?? null,
      session_id: sessionId,
      status: 'open',
    }).select('id').single();
    ticketId = (tk?.id as string | undefined) ?? null;
    await adminClient.from('support_chatbot_sessions').update({
      messages_count: newCount,
      escalated: true,
      escalation_reason: geminiError ?? 'agent_handoff',
      ticket_id: ticketId,
    }).eq('id', sessionId);
  } else {
    await adminClient.from('support_chatbot_sessions')
      .update({ messages_count: newCount }).eq('id', sessionId);
  }

  const { data: quotaInc } = await userClient.rpc('increment_chatbot_quota');
  const usedAfter = (quotaInc as number | null) ?? (usedToday + 1);

  return jsonResponse({
    reply: finalText,
    session_id: sessionId,
    escalated,
    ticket_id: ticketId,
    messages_remaining_today: Math.max(0, settings.rate_limit_per_user_day - usedAfter),
    messages_remaining_session: Math.max(0, settings.max_messages_per_session - newCount),
  });
});
