// Sessão 5A-1 B9 + 5C-β RAG + 5B-α B4 + 5B-β1 B5 + 5F B3 + 5F-α B2 — Edge Fn support-chatbot
// 2026-10-07 (Claude.ai via MCP): CORRIGE erro Gemini "Role 'function' is not supported" e
// "missing thought_signature" — respostas de ferramentas passam a ir com role 'user' e a
// chamada do modelo é devolvida com as parts originais (mantém thoughtSignature).
// Historico de ferramentas de mensagens anteriores vai como texto (nao ha functionCall gravado).
// System prompt passa a conhecer os Favores (tabaco e coisas fora da app).
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
  'agent_propose_action',
  'agent_propose_action_cancel',
  'agent_propose_action_password',
  'agent_propose_action_account',
  'agent_ask_robot_b',
  'propose_skill_now',
]);

const PROPOSE_ACTION_TOOL_NAMES = new Set([
  'agent_propose_action',
  'agent_propose_action_cancel',
  'agent_propose_action_password',
  'agent_propose_action_account',
]);

const WRITE_SHADOW_ACTION_TYPES = new Set([
  'UPDATE_DELIVERY_INSTRUCTIONS',
  'UPDATE_DELIVERY_ADDRESS',
  'CANCEL_PRE_PURCHASE',
  'PASSWORD_RESET',
  'ACCOUNT_UPDATE',
]);

const SYSTEM_DELIM_OPEN = '<<<SYSTEM>>>';
const SYSTEM_DELIM_CLOSE = '<<<END_SYSTEM>>>';

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
    const buf = await crypto.subtle.digest('SHA-256', new TextEncoder().encode(text));
    return Array.from(new Uint8Array(buf)).map((b) => b.toString(16).padStart(2, '0')).join('');
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

function stripControlChars(s: string): string {
  let out = '';
  for (let i = 0; i < s.length; i++) {
    const code = s.charCodeAt(i);
    if (code < 32 && code !== 9 && code !== 10) continue;
    if (code === 127) continue;
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
    {
      name: 'agent_propose_action',
      description:
        'Propoe uma accao WRITE em modo shadow (skill UPDATE_DELIVERY_INSTRUCTIONS ou UPDATE_DELIVERY_ADDRESS). ' +
        'O admin Danilo aprova manualmente antes de a accao ser executada. ' +
        'NUNCA usar para leitura (usa as tools agent_get_* para isso). ' +
        'Apos chamar, informa o cliente que a alteracao aguarda aprovacao.',
      parameters: {
        type: 'object',
        properties: {
          skill_name: { type: 'string', enum: ['UPDATE_DELIVERY_INSTRUCTIONS', 'UPDATE_DELIVERY_ADDRESS'] },
          action_type: { type: 'string', enum: ['UPDATE_DELIVERY_INSTRUCTIONS', 'UPDATE_DELIVERY_ADDRESS'] },
          action_payload: {
            type: 'object',
            description:
              'UPDATE_DELIVERY_INSTRUCTIONS: { order_id: string, new_value: string<=200ch }. ' +
              'UPDATE_DELIVERY_ADDRESS: { order_id: string, new_address: string }.',
          },
          agent_reasoning: { type: 'string' },
        },
        required: ['skill_name', 'action_type', 'action_payload', 'agent_reasoning'],
      },
    },
    {
      name: 'agent_propose_action_cancel',
      description:
        'Propoe cancelamento de pedido pre-compra (skill CANCEL_PRE_PURCHASE). ' +
        'IRREVERSIVEL — confirmar com cliente antes. ' +
        'Apenas para status created ou preparing. ' +
        'Apos aprovacao do admin, sistema chama admin-cancel-order (Stripe refund automatico).',
      parameters: {
        type: 'object',
        properties: {
          skill_name: { type: 'string', enum: ['CANCEL_PRE_PURCHASE'] },
          action_type: { type: 'string', enum: ['CANCEL_PRE_PURCHASE'] },
          action_payload: {
            type: 'object',
            description: '{ order_id: string, reason: string } — reason recomendado: "client_request: <texto curto>".',
          },
          agent_reasoning: { type: 'string' },
        },
        required: ['skill_name', 'action_type', 'action_payload', 'agent_reasoning'],
      },
    },
    {
      name: 'agent_propose_action_password',
      description:
        'Propoe reset password (skill PASSWORD_RESET). ' +
        'Confirmar identidade (nome) ANTES. ' +
        'Email e buscado automaticamente do user_id — payload deve ser objecto vazio {}. ' +
        'Maximo 2 propostas por sessao.',
      parameters: {
        type: 'object',
        properties: {
          skill_name: { type: 'string', enum: ['PASSWORD_RESET'] },
          action_type: { type: 'string', enum: ['PASSWORD_RESET'] },
          action_payload: { type: 'object', description: '{} (vazio — email vem de auth.users via user_id da sessao)' },
          agent_reasoning: { type: 'string', description: 'Inclui o nome confirmado pelo cliente.' },
        },
        required: ['skill_name', 'action_type', 'action_payload', 'agent_reasoning'],
      },
    },
    {
      name: 'agent_propose_action_account',
      description:
        'Propoe actualizacao de dados da conta (skill ACCOUNT_UPDATE). ' +
        'Apenas name e/ou phone permitidos. ' +
        'NUNCA email, password, role, wallet, tokens, fcm_token (RPC bloqueia FORBIDDEN_FIELD).',
      parameters: {
        type: 'object',
        properties: {
          skill_name: { type: 'string', enum: ['ACCOUNT_UPDATE'] },
          action_type: { type: 'string', enum: ['ACCOUNT_UPDATE'] },
          action_payload: {
            type: 'object',
            description:
              '{ name?: string (2-100ch), phone?: string (formato E.164: +351912345678) }. ' +
              'Pelo menos um dos campos e obrigatorio.',
          },
          agent_reasoning: { type: 'string' },
        },
        required: ['skill_name', 'action_type', 'action_payload', 'agent_reasoning'],
      },
    },
    {
      name: 'agent_ask_robot_b',
      description:
        'Regista problema tecnico da app (skill ASK_ROBOT_B) para analise assincrona pela ' +
        'equipa tecnica via robot_crosstalk. Usar APENAS para comportamento app (bug, crash, ' +
        'lentidao, ecra preto). NAO usar para pedido/pagamento/entrega/conta — usar skills ' +
        'apropriadas (ORDER_STATUS, REFUND_*, UPDATE_DELIVERY_*, ACCOUNT_UPDATE) ou HUMAN_REQUEST. ' +
        'Apos chamar, informa o cliente que o problema foi registado para analise tecnica.',
      parameters: {
        type: 'object',
        properties: {
          p_question: {
            type: 'string',
            description:
              'Descricao completa do problema tecnico (sera anonimizada server-side: ' +
              'emails, telefones, UUIDs, numeros longos sao mascarados).',
          },
          p_skill_triggered: { type: 'string', enum: ['ASK_ROBOT_B'], description: 'Sempre "ASK_ROBOT_B".' },
          p_context: {
            type: 'object',
            description:
              'Contexto opcional: { screen_name?: string, error_message?: string, ' +
              'frequency?: "always"|"sometimes"|"once", reproduction_steps?: string }.',
          },
          p_urgency: {
            type: 'string',
            enum: ['critical', 'medium', 'normal'],
            description:
              'critical: bloqueia uso ou perde dinheiro. medium: atrapalha mas tem workaround. ' +
              'normal: comportamento estranho mas nao bloqueia. Default normal.',
          },
        },
        required: ['p_question', 'p_skill_triggered'],
      },
    },
    {
      name: 'propose_skill_now',
      description:
        'Quando identificas que NAO tens skill para resolver um problema novo do cliente, propoes IMEDIATAMENTE uma skill nova ao admin Danilo. ' +
        'PRE-REQUISITOS: (a) ja fizeste 1-2 perguntas; (b) problema NAO coberto pelas skills; ' +
        '(c) problema razoavel/recorrente; (d) NAO e disputa/legal/RGPD/fraude. ' +
        'Apos chamar, informa o cliente que vais passar o caso a equipa.',
      parameters: {
        type: 'object',
        properties: {
          pattern_summary: { type: 'string', description: 'Descricao curta do problema em 1 frase (max 200 chars).' },
          conversation_context: { type: 'string', description: 'Resumo da conversa. Max 1000 chars.' },
          suggested_skill_name: { type: 'string', description: 'UPPER_SNAKE_CASE.' },
          suggested_playbook_md: { type: 'string', description: 'Markdown com 3-7 passos. Max 2000 chars.' },
          suggested_mode: { type: 'string', enum: ['read_only', 'write_shadow', 'escalate'] },
          sample_user_question: { type: 'string', description: 'A pergunta original do cliente (max 500 chars).' },
        },
        required: [
          'pattern_summary',
          'conversation_context',
          'suggested_skill_name',
          'suggested_playbook_md',
          'suggested_mode',
          'sample_user_question',
        ],
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
    'Es o agente IA da Bora App, plataforma de entregas + supermercados + Favores + reservas em Guarda, Portugal.',
    'Linguagem: PT europeu, tom amigavel e directo.',
    `Utilizador: role=${userRole}${orderId ? `, pedido em foco=${orderId}` : ''}.`,
    '',
    '═══ COMPORTAMENTO OBRIGATORIO ═══',
    '1. ANTES de dizer "nao sei" ou escalar, FAZ pelo menos 1-2 perguntas para perceber o contexto.',
    '2. Cancelamentos: pergunta ID do pedido, motivo, preferencia reembolso (cartao 5-10d OU carteira Bora imediato).',
    '3. Reembolsos: pergunta ID, qual o problema especifico, valor afectado.',
    '4. Bug app: pergunta o que estavas a fazer, ecra exacto, mensagem de erro, frequencia.',
    '5. SO depois de teres info suficiente:',
    '   - SE consegues resolver com tool existente → resolve.',
    '   - SE nao consegues → chama propose_skill_now (passar contexto completo) E informa cliente que escalas.',
    '',
    '═══ REGRAS DE NEGOCIO BORA APP (cita nao inventes) ═══',
    'FAVORES (service_type errand) — para tudo o que NAO esta numa loja da app:',
    '- Tabaco, tabacaria, farmacia, papelaria, levantar encomendas, pagar contas, comprar numa loja de rua.',
    '- No ecra inicial, nos icones das categorias, escolher "Favores"; escrever o que quer (marca e quantidade), onde comprar, confirmar morada, escolher Normal (ate 3h) ou Expresso (45-60 min).',
    '- O estafeta compra e entrega; a compra paga-se pelo talao, sem margem.',
    '- Tabaco e alcool so para maiores de 18; o estafeta pode pedir documento na entrega.',
    '- NUNCA mandar procurar tabaco nos supermercados ou lojas da app: nao vendem tabaco.',
    'ENTREGA:',
    '- Base: €2,50 ate 4km · +€0,50/km depois.',
    '- Saco restaurante: €0,30 fixo. Saco mercado: €0,10/saco (cap 5 sacos = €0,50 max).',
    '- Markup nao-parceiro: +15% (oculto, ja incluido no subtotal).',
    'COMISSAO PARCEIRO (10+5+5%):',
    '- 10% visivel (parceiro paga no settlement).',
    '- 5% markup oculto (incluido no preco do produto).',
    '- 5% taxa servico cliente (visivel no recibo).',
    'CANCELAMENTO PEDIDO:',
    '- Antes do dispatch (created/preparing, sem driver) → cancelamento livre, refund 100%.',
    '- Apos dispatch (driverAccepted) → taxa €2,50.',
    '- Apos pickup (pickedUp/onTheWay) → 100% retido, sem refund (driver ja comprou).',
    '- Reembolso por: cartao (5-10 dias uteis) OU carteira Bora (imediato).',
    'WALLET REFUND SPLIT (cliente cancela com refund → escolhe wallet):',
    '- 80% saldo livre (sem regras, usa em qualquer pedido).',
    '- 20% convertido em TOKENS (100 tokens = €0,50, expira 60d, max 50% desconto/pedido).',
    'TOKENS (sistema SEPARADO da wallet):',
    '- Driver normal: +40 por entrega. Driver parceiro: +50.',
    '- Cliente: ROUND(preco × 3), minimo 1 token por pedido.',
    '- 100 tokens = €0,50, max 50% desconto/pedido, expira 60d.',
    'STORESHOPPING NAO-PARCEIRO (mercado sem app integrada):',
    '- Cliente paga base + 15% markup oculto.',
    '- Driver compra fisicamente no mercado, fotografa o talao no fim.',
    '- Substituicoes: comprado / nao tem (refund parcial) / adicionado (cobra diff).',
    'RESERVAS DE MESA:',
    '- Pre-pagamento €3 cliente paga (€2 para parceiro chegada / €1 para Bora servico).',
    '- Cancela >2h antes → refund total €3.',
    '- Cancela <2h antes → Bora fica 100% (€3).',
    '- No-show → Bora fica 100% (€3). Parceiro nao recebe.',
    '',
    '═══ REGRAS CRITICAS (nao quebrar) ═══',
    '#1: NUNCA calculas dinheiro complexo, refunds finais, creditos finais (sao calculados por RPCs/triggers).',
    '   Podes citar as regras acima, mas o valor exacto vem das tools agent_get_refund_status / agent_get_user_wallet_summary.',
    '#2: NUNCA inventas valores, IDs, nomes de RPC, colunas ou comportamento — usa tools.',
    '#3: Respostas curtas (<=3 frases) excepto explicacao tecnica necessaria.',
    '#4: Em duvida ou queixa seria, marca [HANDOFF_HUMAN] no fim.',
    '#5: Se no historico houver mensagens da "equipa Bora" (humano), segue o que elas disseram e continua a conversa a partir dali.',
    '',
    '═══ O QUE NUNCA FAZES (sempre escalar humano) ═══',
    '- Disputas entre cliente/driver/parceiro.',
    '- RGPD / dados pessoais sensiveis (apaga conta, copia dados).',
    '- Reclamacoes graves: fraude, abuso, seguranca, comida estragada, acidentes.',
    '- Decisoes legais / contratuais.',
    '- Pedidos para mexer em dinheiro real fora das tools agent_propose_action_*.',
    '',
    '═══ QUANDO PROPOR SKILL NOVA (chamar propose_skill_now) ═══',
    '- Identificas padrao recorrente nao coberto pelas skills disponiveis abaixo.',
    '- Verifica se ja existe skill que cobre — se sim, usa-a, NAO proponhas duplicada.',
    '',
    `WhatsApp suporte: ${settings.whatsapp_number}. Email: ${settings.support_email}.`,
    '',
    'Skills disponiveis:',
    skillsMd || '(vazio)',
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

async function buildRagContext(
  userMessage: string,
  // deno-lint-ignore no-explicit-any
  adminClient: any,
): Promise<string> {
  if (!GEMINI_API_KEY) return '';

  const queryNorm = userMessage.trim().toLowerCase().substring(0, 500);
  const queryHash = await sha256Hex(queryNorm);
  let queryEmbedding: number[] | null = null;

  if (queryHash) {
    const { data: cached } = await adminClient
      .from('support_embedding_cache')
      .select('embedding, hit_count')
      .eq('query_hash', queryHash)
      .maybeSingle();

    if (cached?.embedding) {
      try {
        const raw = cached.embedding;
        queryEmbedding = typeof raw === 'string' ? JSON.parse(raw) as number[] : raw as number[];
      } catch {
        queryEmbedding = null;
      }
      if (queryEmbedding && queryEmbedding.length === RAG_EMBED_DIM) {
        await adminClient
          .from('support_embedding_cache')
          .update({ last_used_at: new Date().toISOString(), hit_count: (cached.hit_count ?? 1) + 1 })
          .eq('query_hash', queryHash);
      } else {
        queryEmbedding = null;
      }
    }
  }

  if (!queryEmbedding) {
    const ctrl = new AbortController();
    const tid = setTimeout(() => ctrl.abort(), RAG_EMBED_TIMEOUT_MS);
    try {
      const embRes = await fetch(RAG_EMBED_ENDPOINT, {
        method: 'POST',
        signal: ctrl.signal,
        headers: { 'Content-Type': 'application/json', 'x-goog-api-key': GEMINI_API_KEY },
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
              .upsert({ query_hash: queryHash, query_text: userMessage.substring(0, 500), embedding: embLit }, {
                onConflict: 'query_hash',
                ignoreDuplicates: true,
              });
          }
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

  const { data: chunks, error: matchErr } = await adminClient.rpc('match_knowledge', {
    query_embedding: queryEmbedding,
    match_count: RAG_MATCH_COUNT,
    min_similarity: RAG_MIN_SIMILARITY,
  });

  if (matchErr) {
    console.warn('[RAG] match_knowledge error:', matchErr.message);
    return '';
  }
  if (!chunks || chunks.length === 0) return '';

  const fileCounts = new Map<string, number>();
  // deno-lint-ignore no-explicit-any
  const dedup = (chunks as any[]).filter((c) => {
    const cnt = fileCounts.get(c.source_file) || 0;
    if (cnt >= RAG_DEDUP_PER_FILE) return false;
    fileCounts.set(c.source_file, cnt + 1);
    return true;
  }).slice(0, RAG_FINAL_LIMIT);

  return '=== CONHECIMENTO BORA APP ===\n' +
    '(Contexto de fundo — usa apenas se relevante para a pergunta; tools mantem fluxo principal)\n\n' +
    // deno-lint-ignore no-explicit-any
    dedup.map((c: any) => `[${c.source_type}/${c.section_title ?? 'geral'}]\n${c.chunk_text}`).join('\n\n---\n\n') +
    '\n=== FIM CONHECIMENTO ===';
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

  const { data: settingsRow } = await adminClient.from('support_settings').select('*').eq('id', 1).single();
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

  {
    const { error: insUserErr } = await adminClient.from('support_chatbot_messages').insert({
      session_id: sessionId, role: 'user', content: userMessage,
    });
    if (insUserErr) console.error('[CHATBOT] insert user message failed:', insUserErr.message);
  }

  const { data: histRows } = await adminClient
    .from('support_chatbot_messages')
    .select('role, content, tool_name, tool_input, tool_output')
    .eq('session_id', sessionId)
    .order('created_at', { ascending: false })
    .limit(12);
  const history = (histRows ?? []).reverse();

  const { data: skillRows } = await adminClient
    .from('support_skills').select('skill_name, playbook_md').eq('active', true);
  const skillsMd = (skillRows ?? [])
    .map((s: { skill_name: string; playbook_md: string }) => `### ${s.skill_name}\n${s.playbook_md}`)
    .join('\n\n');

  let ragContext = '';
  if (settings.rag_enabled === true) {
    try {
      ragContext = await buildRagContext(userMessage, adminClient);
    } catch (e) {
      console.error('[RAG] injection error (fallback sem RAG):', (e as Error).message);
      ragContext = '';
    }
  }

  const systemPrompt = buildSystemPrompt(userRole, payload.order_id ?? null, settings, skillsMd, ragContext);
  const tools = buildFunctionDeclarations();

  // Historico: resultados de ferramentas de turnos anteriores vao como TEXTO do lado 'user'
  // (nao ha functionCall gravado para os emparelhar; Gemini rejeita role 'function').
  // Mensagens seguidas do mesmo lado juntam-se num so bloco.
  // deno-lint-ignore no-explicit-any
  const contents: any[] = [];
  // deno-lint-ignore no-explicit-any
  const pushText = (role: 'user' | 'model', text: string) => {
    const last = contents[contents.length - 1];
    if (last && last.role === role && Array.isArray(last.parts) && last.parts.every((p: any) => typeof p.text === 'string')) {
      last.parts.push({ text });
    } else {
      contents.push({ role, parts: [{ text }] });
    }
  };
  for (const m of history) {
    if (m.role === 'user') {
      pushText('user', m.content ?? '');
    } else if (m.role === 'assistant') {
      pushText('model', m.content ?? '');
    } else if (m.role === 'tool') {
      let out = '';
      try { out = JSON.stringify(m.tool_output ?? null).slice(0, 1500); } catch { out = ''; }
      pushText('user', `[resultado da ferramenta ${m.tool_name ?? 'desconhecida'}: ${out}]`);
    }
  }
  // Gemini exige que a conversa comece do lado do utilizador.
  while (contents.length > 0 && contents[0].role !== 'user') contents.shift();

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
    // deno-lint-ignore no-explicit-any
    const fnCallPart = parts.find((p: any) => p.functionCall);
    if (fnCallPart) {
      const fnName: string = fnCallPart.functionCall.name;
      const fnArgs: Record<string, unknown> = fnCallPart.functionCall.args ?? {};
      if (!TOOL_WHITELIST.has(fnName)) {
        finalText = 'Erro interno: ferramenta nao autorizada. Posso transferir-te para humano?';
        escalated = true;
        break;
      }
      let rpcRes: { ok: boolean; data?: unknown; error?: string };
      if (fnName === 'propose_skill_now') {
        const args = fnArgs as Record<string, unknown>;
        const pattern_summary = typeof args.pattern_summary === 'string' ? args.pattern_summary.slice(0, 200) : '';
        const conversation_context = typeof args.conversation_context === 'string' ? args.conversation_context.slice(0, 1000) : '';
        const suggested_skill_name = typeof args.suggested_skill_name === 'string' ? args.suggested_skill_name.slice(0, 80).toUpperCase() : '';
        const suggested_playbook_md = typeof args.suggested_playbook_md === 'string' ? args.suggested_playbook_md.slice(0, 2000) : '';
        const suggested_mode_raw = typeof args.suggested_mode === 'string' ? args.suggested_mode : 'read_only';
        const suggested_mode = ['read_only', 'write_shadow', 'escalate'].includes(suggested_mode_raw) ? suggested_mode_raw : 'read_only';
        const sample_user_question = typeof args.sample_user_question === 'string' ? args.sample_user_question.slice(0, 500) : '';

        if (!pattern_summary || !suggested_skill_name || !suggested_playbook_md) {
          rpcRes = { ok: false, error: 'pattern_summary, suggested_skill_name e suggested_playbook_md sao obrigatorios.' };
        } else {
          const { data: existing } = await adminClient
            .from('skill_suggestions')
            .select('id')
            .eq('suggested_skill_name', suggested_skill_name)
            .eq('status', 'pending')
            .gte('suggested_at', new Date(Date.now() - 24 * 60 * 60 * 1000).toISOString())
            .maybeSingle();

          if (existing?.id) {
            rpcRes = { ok: true, data: { proposed: false, duplicate: true, existing_id: existing.id } };
          } else {
            const { data: ins, error: insErr } = await adminClient
              .from('skill_suggestions')
              .insert({
                pattern_summary,
                suggested_skill_name,
                suggested_playbook_md,
                suggested_mode,
                sample_messages: [
                  { role: 'user', content: sample_user_question },
                  { role: 'assistant_context', content: conversation_context },
                ],
                message_count: 2,
                proposal_type: 'new_skill',
                zone_type: 'safe',
                gemini_model: settings.gemini_model,
                source: 'robot_a_realtime',
                status: 'pending',
              })
              .select('id')
              .single();

            if (insErr) {
              rpcRes = { ok: false, error: insErr.message };
            } else {
              const newId = (ins?.id as string) ?? null;
              try {
                await adminClient.rpc('notify_admin_event', {
                  p_event_type: 'skill_proposal_realtime',
                  p_severity: 'high',
                  p_summary: `Robot A propoe skill: ${pattern_summary}`,
                  p_entity_type: 'skill_suggestion',
                  p_entity_id: newId,
                  p_payload: { suggested_skill_name, suggested_mode, source: 'robot_a_realtime', session_id: sessionId },
                  p_deep_link: '/admin/skill-suggestions',
                });
              } catch (notifErr) {
                console.warn('[propose_skill_now] notify_admin_event failed:', (notifErr as Error).message);
              }
              rpcRes = { ok: true, data: { proposed: true, skill_suggestion_id: newId } };
            }
          }
        }
      } else if (PROPOSE_ACTION_TOOL_NAMES.has(fnName)) {
        const args = fnArgs as Record<string, unknown>;
        const skill_name = typeof args.skill_name === 'string' ? args.skill_name : '';
        const action_type = typeof args.action_type === 'string' ? args.action_type : '';
        const action_payload = args.action_payload;
        const agent_reasoning = typeof args.agent_reasoning === 'string' ? args.agent_reasoning : null;

        if (!WRITE_SHADOW_ACTION_TYPES.has(action_type)) {
          rpcRes = { ok: false, error: `action_type not allowed: ${action_type}` };
        } else if (action_payload === null || typeof action_payload !== 'object' || Array.isArray(action_payload)) {
          rpcRes = { ok: false, error: 'action_payload must be object' };
        } else {
          const { data: actionId, error: propErr } = await adminClient.rpc('agent_propose_action', {
            p_session_id: sessionId,
            p_user_id: userId,
            p_skill_name: skill_name,
            p_action_type: action_type,
            p_action_payload: action_payload,
            p_user_message: userMessage,
            p_agent_reasoning: agent_reasoning,
          });
          if (propErr) {
            rpcRes = { ok: false, error: propErr.message };
          } else {
            rpcRes = { ok: true, data: { proposed: true, action_id: actionId, message: 'Proposta criada. Aguarda aprovacao do admin.' } };
          }
        }
      } else {
        rpcRes = await callRpc(userJwt, fnName, fnArgs);
      }
      {
        const { error: insToolErr } = await adminClient.from('support_chatbot_messages').insert({
          session_id: sessionId, role: 'tool',
          content: rpcRes.ok ? 'ok' : (rpcRes.error ?? 'rpc error'),
          tool_name: fnName, tool_input: fnArgs,
          tool_output: rpcRes.ok ? rpcRes.data : { error: rpcRes.error },
        });
        if (insToolErr) console.error('[CHATBOT] insert tool message failed:', insToolErr.message);
      }
      // Devolve as parts ORIGINAIS do modelo (mantem thoughtSignature) e a resposta com role 'user'.
      contents.push({ role: 'model', parts });
      contents.push({
        role: 'user',
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
    // deno-lint-ignore no-explicit-any
    finalText = parts.map((p: any) => p.text ?? '').join('').trim();
    break;
  }

  if (toolIters > settings.max_tool_iterations && !finalText) {
    finalText = 'Nao consegui resolver. Posso transferir-te para WhatsApp/Email?';
    escalated = true;
  }
  if (!geminiOk) {
    console.error('[CHATBOT] gemini error:', geminiError);
    finalText = 'Estou temporariamente indisponivel. Posso transferir-te para WhatsApp ou Email?';
    escalated = true;
  }
  if (!finalText) {
    finalText = 'Desculpa, nao percebi bem. Podes explicar um pouco melhor o que precisas?';
  }
  if (finalText.includes('[HANDOFF_HUMAN]')) {
    escalated = true;
    finalText = finalText.replace('[HANDOFF_HUMAN]', '').trim();
  }

  {
    const { error: insAsstErr } = await adminClient.from('support_chatbot_messages').insert({
      session_id: sessionId, role: 'assistant', content: finalText,
      tokens_used: totalTokens || null,
    });
    if (insAsstErr) console.error('[CHATBOT] insert assistant message failed:', insAsstErr.message);
  }

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

    try {
      const summary = userMessage.toLowerCase().trim().slice(0, 200);
      const hashBuf = await crypto.subtle.digest('SHA-256', new TextEncoder().encode(summary));
      const hashHex = Array.from(new Uint8Array(hashBuf)).map((b) => b.toString(16).padStart(2, '0')).join('');
      const { data: existing } = await adminClient
        .from('skill_suggestions')
        .select('id')
        .eq('pattern_hash', hashHex)
        .in('status', ['pending', 'approved'])
        .limit(1)
        .maybeSingle();
      if (!existing) {
        const nowIso = new Date().toISOString();
        await adminClient.from('skill_suggestions').insert({
          proposal_type: 'new_skill',
          zone_type: 'safe',
          pattern_summary: summary,
          sample_messages: [userMessage.slice(0, 500)],
          message_count: 1,
          suggested_category: 'general',
          suggested_mode: 'read_only',
          suggested_playbook_md: '',
          suggested_allowed_tools: [],
          pattern_hash: hashHex,
          gemini_model: null,
          analysis_window_start: nowIso,
          analysis_window_end: nowIso,
        });
      }
    } catch (e) {
      console.error('[CHATBOT] inline skill_suggestion exception:', (e as Error).message);
    }
  } else {
    await adminClient.from('support_chatbot_sessions').update({ messages_count: newCount }).eq('id', sessionId);
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
