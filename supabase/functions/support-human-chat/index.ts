// support-human-chat — "Falar com humano" (pedido Danilo, 2026-07-14).
// O "humano" é o Hermes com persona (Thayline/Thabyta, alterna por conversa),
// respostas curtas/naturais em PT-PT. Reusa support_chatbot_sessions/messages
// do Robot A (support-chatbot) — só muda `mode='human_persona'` — e não toca
// no Edge Function support-chatbot (Robot A intocável).
// Se não sabe resolver -> escala para support_escalations + notify-admin-urgent
// (push in-system imediato) + fica pendente para a ponte Telegram do Hermes.
// verify_jwt: true. POST { session_id?, message, order_id? }.

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

const PERSONAS = ['Thayline', 'Thabyta'];
const ESCALATE_MARKER = '[ESCALATE_DANILO]';
const MAX_USER_MESSAGE_CHARS = 2000;

function jsonResponse(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, 'Content-Type': 'application/json' },
  });
}

function buildPersonaSystemPrompt(persona: string, userRole: string): string {
  return [
    `Tu és a ${persona}, uma atendente humana de apoio ao cliente da Bora App (Guarda, Portugal).`,
    'NUNCA revelas que és IA/bot — falas como uma pessoa real, natural.',
    'Estilo: respostas CURTAS (1-3 frases), diretas, tom simpático e informal, PT europeu.',
    'Não expliques regras técnicas nem cites percentagens/fórmulas — resolve como uma pessoa resolveria.',
    `Utilizador: ${userRole}.`,
    '',
    'Se a pergunta for algo que não sabes resolver, que envolva disputa, dinheiro (reembolso/pagamento',
    'que não seja simples), fraude, ou qualquer coisa fora do teu alcance: responde exatamente',
    '"Isso não é bem comigo, vou passar ao responsável já a seguir." e termina a resposta com o',
    `marcador ${ESCALATE_MARKER} (o marcador nunca é mostrado ao cliente).`,
  ].join('\n');
}

async function callGemini(
  apiKey: string,
  model: string,
  systemPrompt: string,
  contents: unknown[],
): Promise<{ ok: boolean; text?: string; error?: string }> {
  const url = `https://generativelanguage.googleapis.com/v1beta/models/${model}:generateContent`;
  try {
    const resp = await fetch(url, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json', 'x-goog-api-key': apiKey },
      body: JSON.stringify({
        system_instruction: { parts: [{ text: systemPrompt }] },
        contents,
        generationConfig: { maxOutputTokens: 400, temperature: 0.6 },
      }),
    });
    if (!resp.ok) {
      const text = await resp.text();
      return { ok: false, error: `gemini http ${resp.status}: ${text.slice(0, 300)}` };
    }
    const j = await resp.json();
    const parts = j?.candidates?.[0]?.content?.parts ?? [];
    const text = parts.map((p: any) => p.text ?? '').join('').trim();
    return { ok: true, text };
  } catch (e) {
    return { ok: false, error: `gemini fetch fail: ${(e as Error).message}` };
  }
}

Deno.serve(async (req: Request) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: corsHeaders });
  if (req.method !== 'POST') return jsonResponse({ error: 'method not allowed' }, 405);

  if (!GEMINI_API_KEY) {
    return jsonResponse({
      error: 'GEMINI_API_KEY missing',
      reply: 'Estou com um problema técnico agora. Contacta-nos por WhatsApp ou email, por favor.',
      escalated: false,
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

  const rawMessage = (payload.message ?? '').toString();
  const userMessage = rawMessage.slice(0, MAX_USER_MESSAGE_CHARS).trim();
  if (!userMessage) return jsonResponse({ error: 'message empty' }, 400);

  const adminClient = createClient(SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY);

  const { data: settingsRow } = await adminClient
    .from('support_settings').select('gemini_model').eq('id', 1).single();
  const geminiModel = (settingsRow?.gemini_model as string | undefined) ?? 'gemini-1.5-flash';

  let sessionId = payload.session_id;
  let persona: string;

  if (sessionId) {
    const { data: sess } = await adminClient
      .from('support_chatbot_sessions')
      .select('id, user_id, persona_name')
      .eq('id', sessionId).maybeSingle();
    if (!sess || sess.user_id !== userId) {
      return jsonResponse({ error: 'session not found or not owner' }, 404);
    }
    persona = (sess.persona_name as string | undefined) ?? PERSONAS[0];
  } else {
    // Alterna persona: olha a última sessão human_persona (de qualquer user) e inverte.
    const { data: lastSess } = await adminClient
      .from('support_chatbot_sessions')
      .select('persona_name')
      .eq('mode', 'human_persona')
      .not('persona_name', 'is', null)
      .order('started_at', { ascending: false })
      .limit(1)
      .maybeSingle();
    const lastPersona = lastSess?.persona_name as string | undefined;
    persona = lastPersona === PERSONAS[0] ? PERSONAS[1] : PERSONAS[0];

    const { data: newSess, error: newErr } = await adminClient
      .from('support_chatbot_sessions')
      .insert({
        user_id: userId, user_role: userRole, order_id: payload.order_id ?? null,
        mode: 'human_persona', persona_name: persona,
      })
      .select('id').single();
    if (newErr || !newSess) return jsonResponse({ error: 'session create fail' }, 500);
    sessionId = newSess.id as string;
  }

  await adminClient.from('support_chatbot_messages').insert({
    session_id: sessionId, role: 'user', content: userMessage,
  });

  const { data: histRows } = await adminClient
    .from('support_chatbot_messages')
    .select('role, content')
    .eq('session_id', sessionId)
    .order('created_at', { ascending: false })
    .limit(10);
  const history = (histRows ?? []).reverse();

  const contents = history
    .filter((m: any) => m.role === 'user' || m.role === 'assistant')
    .map((m: any) => ({
      role: m.role === 'user' ? 'user' : 'model',
      parts: [{ text: m.content }],
    }));

  const systemPrompt = buildPersonaSystemPrompt(persona, userRole);
  const gemRes = await callGemini(GEMINI_API_KEY, geminiModel, systemPrompt, contents);

  let finalText = gemRes.ok && gemRes.text
    ? gemRes.text
    : 'Isso não é bem comigo, vou passar ao responsável já a seguir.';
  let escalated = false;
  if (finalText.includes(ESCALATE_MARKER)) {
    escalated = true;
    finalText = finalText.replace(ESCALATE_MARKER, '').trim();
  }
  if (!gemRes.ok) escalated = true;

  await adminClient.from('support_chatbot_messages').insert({
    session_id: sessionId, role: 'assistant', content: finalText,
  });

  let escalationId: string | null = null;
  if (escalated) {
    const { data: esc } = await adminClient.from('support_escalations').insert({
      session_id: sessionId, user_id: userId, user_role: userRole,
      question: userMessage, persona_name: persona,
    }).select('id').single();
    escalationId = (esc?.id as string | undefined) ?? null;

    await adminClient.from('support_chatbot_sessions')
      .update({ escalated_pending: true }).eq('id', sessionId);

    try {
      await adminClient.functions.invoke('notify-admin-urgent', {
        body: {
          kind: 'generic',
          title: '💬 Cliente precisa de ti — suporte',
          body: userMessage.length > 150 ? userMessage.slice(0, 150) + '…' : userMessage,
          route: '/admin/support-escalations',
          ref: escalationId ?? 'support_escalation',
        },
      });
    } catch (e) {
      console.warn('[support-human-chat] notify-admin-urgent failed:', (e as Error).message);
    }
  } else {
    await adminClient.from('support_chatbot_sessions')
      .update({ messages_count: (history.length ?? 0) + 1 }).eq('id', sessionId);
  }

  return jsonResponse({
    reply: finalText,
    session_id: sessionId,
    persona_name: persona,
    escalated,
    escalation_id: escalationId,
  });
});
