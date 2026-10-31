// admin-ai-assistant — chat IA do painel admin: Claude PRIMEIRO, Gemini Flash Lite de reserva.
// Secrets no Supabase: ANTHROPIC_API_KEY (Claude) e/ou GEMINI_API_KEY (reserva, já existia).
// Basta um dos dois; com os dois, o Claude responde e o Gemini só entra quando o Claude falha.
//
// 2026-10-31 (missão motor-claude-2026-10-31): Claude via _shared/claude.ts, robô 'edge-admin',
// prioridade 2 (o modelo vem do porteiro ia_claude_pode; Opus nunca). Mesmas tools, mesmo formato
// de resposta ({session_id, reply, actions, model}); "model" diz qual modelo respondeu.
// Portão de admin: app_metadata.role = 'admin' ou is_admin() no banco. Deixou de valer o
// user_metadata.role, que qualquer utilizador consegue escrever na própria conta.
//
// Modelo de reserva: gemini-3.1-flash-lite (tier gratuito).
// 2026-08-12: era gemini-2.5-flash — retirado para projectos novos (404 "no longer
// available to new users") após mover a GEMINI_API_KEY para um projecto sem faturação.
// Tools v1 (read-only):
//   - sql_select: SELECT arbitrário em public (banlist DML/DDL)
//   - get_platform_setting: lê platform_settings por chave

import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import { secretKey } from "../_shared/keys.ts";
import {
  claudePrimeiro,
  conversaParaClaude,
  ferramentasParaClaude,
  type BlocoClaude,
  type MensagemClaude,
  type ModeloClaude,
} from "../_shared/claude.ts";

const SUPABASE_URL = Deno.env.get("SUPABASE_URL")!;
const SUPABASE_SERVICE_ROLE_KEY = secretKey()!;
const SUPABASE_ANON_KEY = Deno.env.get("SUPABASE_ANON_KEY") ?? "";
const GEMINI_API_KEY = Deno.env.get("GEMINI_API_KEY") ?? "";
// Só se guarda SE existe a chave do Claude (quem a lê e usa é _shared/claude.ts).
const TEM_CLAUDE = Boolean(Deno.env.get("ANTHROPIC_API_KEY"));
const MODEL = "gemini-3.1-flash-lite";
const MAX_TOOL_ITERS = 4;
const MAX_OUTPUT_TOKENS = 2048;

const SYSTEM_PROMPT = `És o assistente IA do painel admin da Bora App (delivery + supermercados + reservas em Guarda, Portugal).

Tens acesso directo ao Supabase via tools (function calling). Idioma de resposta: PT-BR (Danilo é brasileiro).

REGRAS ABSOLUTAS:
- Antes de qualquer escrita → confirma o que vais fazer e pede ok ao Danilo na mesma resposta.
- Operações destrutivas (DELETE, DROP, TRUNCATE) → NUNCA. Recusa e pede via Claude Code.
- Para pricing / comissões / tokens / Stripe / reembolso → consulta business_rules.md primeiro e NUNCA inventes.
- Se não souberes → diz "não sei". Não inventes nomes de tabelas, RPCs ou colunas.
- Para bugs de código Flutter → gera um prompt para o Claude Code, NÃO tentes resolver via SQL.

TABELAS PRINCIPAIS:
orders, drivers, clients, restaurants, products, reservations, admin_audit_log, admin_notifications,
order_receipts_v2, driver_balances, bora_tokens, platform_settings, skill_suggestions, complaints,
robot_crosstalk, client_push_tokens, driver_push_tokens.

RPCs admin importantes (SECURITY DEFINER):
admin_list_pending_actions, admin_finalize_action, admin_approve_driver, admin_reject_driver,
admin_mark_receipt_paid, admin_reject_receipt, admin_bulk_approve_skill_suggestions,
admin_bulk_reject_skill_suggestions, admin_list_audit_log.

Quando perguntarem por dados (ex: "pedidos de hoje"), chama a tool sql_select com uma query SELECT.
Sê conciso. Mostra resultados em formato fácil de ler. Não devolvas JSON cru — resume e formata.
`;

// Function declarations no formato Gemini
const TOOLS = [
  {
    name: "sql_select",
    description:
      "Executa uma query SELECT no schema public da DB. SOMENTE SELECT — DML/DDL é rejeitado. Timeout curto. Limita resultados a 200 linhas automaticamente.",
    parameters: {
      type: "object",
      properties: {
        query: {
          type: "string",
          description: "SELECT statement em PostgreSQL.",
        },
        rationale: {
          type: "string",
          description: "Porque é necessária esta query.",
        },
      },
      required: ["query"],
    },
  },
  {
    name: "get_platform_setting",
    description: "Lê um valor de platform_settings pela chave (ex: 'delivery_base_eur', 'partner_commission_visible').",
    parameters: {
      type: "object",
      properties: {
        key: { type: "string", description: "Chave em platform_settings." },
      },
      required: ["key"],
    },
  },
];

// deno-lint-ignore no-explicit-any
type Json = any;

function isDangerousSQL(q: string): boolean {
  const upper = q.toUpperCase();
  const banned = [
    "INSERT ",
    "UPDATE ",
    "DELETE ",
    "DROP ",
    "TRUNCATE ",
    "ALTER ",
    "CREATE ",
    "GRANT ",
    "REVOKE ",
    "COPY ",
    ";--",
  ];
  return banned.some((b) => upper.includes(b)) || !upper.trim().startsWith("SELECT");
}

// Só para o Claude, depois do SYSTEM_PROMPT em cache (regra dos modelos com thinking desligado).
const NOTA_CLAUDE =
  "Quando usares uma ferramenta, podes dizer uma frase curta antes. Se nenhuma ferramenta serve para o que foi pedido, diz isso em vez de adivinhar. Não escrevas etiquetas XML internas nem de sistema na resposta.";

async function execTool(
  fnName: string,
  fnArgs: Record<string, unknown>,
  sb: Json,
): Promise<{ ok: boolean; result?: unknown; error?: string }> {
  try {
    if (fnName === "sql_select") {
      const q = (fnArgs.query as string) ?? "";
      if (isDangerousSQL(q)) {
        return { ok: false, error: "Apenas SELECT é permitido neste tool." };
      }
      const limited = q.match(/LIMIT\s+\d+/i) ? q : `${q.replace(/;\s*$/, "")} LIMIT 200`;
      const { data, error } = await sb.rpc("admin_run_select", { p_query: limited });
      if (error) return { ok: false, error: `SQL: ${error.message}` };
      // Trim para 6KB para não estourar o token budget
      let trimmed: Json = data ?? [];
      if (Array.isArray(trimmed) && JSON.stringify(trimmed).length > 6000) {
        trimmed = trimmed.slice(0, 50);
      }
      return { ok: true, result: trimmed };
    }
    if (fnName === "get_platform_setting") {
      const key = fnArgs.key as string;
      const { data, error } = await sb
        .from("platform_settings")
        .select("key, value, description")
        .eq("key", key)
        .maybeSingle();
      if (error) return { ok: false, error: error.message };
      if (!data) return { ok: true, result: { error: "key não encontrada", key } };
      return { ok: true, result: data };
    }
    return { ok: false, error: `Tool ${fnName} desconhecido.` };
  } catch (e) {
    return { ok: false, error: `Excepção: ${(e as Error).message}` };
  }
}

async function callGemini(
  systemPrompt: string,
  contents: Json[],
  tools: Json[],
): Promise<{ ok: boolean; data?: Json; error?: string }> {
  const url = `https://generativelanguage.googleapis.com/v1beta/models/${MODEL}:generateContent`;
  const body = {
    system_instruction: { parts: [{ text: systemPrompt }] },
    contents,
    tools: [{ function_declarations: tools }],
    generationConfig: { maxOutputTokens: MAX_OUTPUT_TOKENS, temperature: 0.3 },
  };
  try {
    const resp = await fetch(url, {
      method: "POST",
      headers: { "Content-Type": "application/json", "x-goog-api-key": GEMINI_API_KEY },
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

// Converte mensagens do Flutter ({role:'user'|'assistant', content:string}) em
// formato Gemini ({role:'user'|'model', parts:[{text}]}).
function toGeminiContents(
  msgs: Array<{ role: string; content: unknown }>,
): Json[] {
  const out: Json[] = [];
  for (const m of msgs) {
    const role = m.role === "assistant" ? "model" : m.role === "user" ? "user" : null;
    if (!role) continue;
    const text =
      typeof m.content === "string"
        ? m.content
        : JSON.stringify(m.content);
    if (!text.trim()) continue;
    out.push({ role, parts: [{ text }] });
  }
  return out;
}

Deno.serve(async (req) => {
  const cors = {
    "Access-Control-Allow-Origin": "*",
    "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
    "Access-Control-Allow-Methods": "POST, OPTIONS",
  };
  if (req.method === "OPTIONS") return new Response("ok", { headers: cors });
  if (req.method !== "POST")
    return new Response("Method not allowed", { status: 405, headers: cors });

  try {
    if (!GEMINI_API_KEY && !TEM_CLAUDE) {
      return new Response(JSON.stringify({ error: "ANTHROPIC_API_KEY e GEMINI_API_KEY em falta nos secrets" }), {
        status: 500,
        headers: { ...cors, "content-type": "application/json" },
      });
    }

    const authHeader = req.headers.get("authorization") ?? "";
    const jwt = authHeader.replace(/^Bearer\s+/i, "");
    if (!jwt) return new Response("missing auth", { status: 401, headers: cors });

    // Valida role admin no JWT do user
    const userClient = createClient(SUPABASE_URL, SUPABASE_ANON_KEY, {
      global: { headers: { Authorization: authHeader } },
    });
    const { data: userData, error: userErr } = await userClient.auth.getUser();
    if (userErr || !userData?.user) {
      return new Response("invalid jwt", { status: 401, headers: cors });
    }
    // app_metadata só o servidor escreve; is_admin() é a mesma regra do banco (RLS do painel).
    // O user_metadata.role deixou de contar: o próprio utilizador consegue escrevê-lo.
    let ehAdmin =
      (userData.user.app_metadata as Record<string, unknown>)?.["role"] === "admin";
    if (!ehAdmin) {
      const { data: adminRpc } = await userClient.rpc("is_admin");
      ehAdmin = adminRpc === true;
    }
    if (!ehAdmin) {
      return new Response("forbidden — admin only", { status: 403, headers: cors });
    }

    const body = await req.json().catch(() => ({}));
    const incomingMessages: Array<{ role: string; content: unknown }> =
      Array.isArray(body.messages)
        ? body.messages
        : typeof body.message === "string"
          ? [{ role: "user", content: body.message }]
          : [];
    if (incomingMessages.length === 0) {
      return new Response(JSON.stringify({ error: "no messages" }), {
        status: 400,
        headers: { ...cors, "content-type": "application/json" },
      });
    }
    const sessionId: string | null = body.session_id ?? null;

    const sbAdmin = createClient(SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY, {
      auth: { autoRefreshToken: false, persistSession: false },
    });

    const actionsLog: Array<Record<string, unknown>> = [];
    const contents: Json[] = toGeminiContents(incomingMessages);
    let finalText = "";
    let geminiError: string | null = null;
    let modeloUsado: string = MODEL;

    // ── Claude primeiro (robô edge-admin, P2). null em qualquer volta → Gemini abaixo. ──
    let claudeTerminou = false;
    if (TEM_CLAUDE) {
      const claudeMsgs: MensagemClaude[] = conversaParaClaude(
        incomingMessages
          .filter((m) => m.role === "user" || m.role === "assistant")
          .map((m) => ({
            role: m.role as "user" | "assistant",
            texto: typeof m.content === "string" ? m.content : JSON.stringify(m.content),
          })),
      );
      const claudeTools = ferramentasParaClaude(TOOLS);
      let modeloClaude: ModeloClaude | undefined;
      let voltas = 0;
      while (voltas <= MAX_TOOL_ITERS) {
        const r = await claudePrimeiro({
          robo: "edge-admin",
          prioridade: 2,
          system: [SYSTEM_PROMPT, NOTA_CLAUDE],
          messages: claudeMsgs,
          tools: claudeTools,
          maxTokens: MAX_OUTPUT_TOKENS,
          modelo: modeloClaude,
        });
        if (!r) break;
        modeloClaude = r.modelo;
        modeloUsado = r.modelo;
        if (r.toolUses.length > 0) {
          // Devolve o conteúdo do Claude tal e qual e TODOS os resultados numa só mensagem.
          claudeMsgs.push({ role: "assistant", content: r.conteudo });
          const resultados: BlocoClaude[] = [];
          for (const tu of r.toolUses) {
            const res = await execTool(tu.name, tu.input, sbAdmin);
            actionsLog.push({ tool: tu.name, input: tu.input, ok: res.ok, ts: new Date().toISOString() });
            resultados.push({
              type: "tool_result",
              tool_use_id: tu.id,
              content: JSON.stringify(res.ok ? { result: res.result } : { error: res.error }),
              is_error: !res.ok,
            });
          }
          claudeMsgs.push({ role: "user", content: resultados });
          voltas++;
          continue;
        }
        finalText = r.texto.trim();
        claudeTerminou = true;
        break;
      }
      // Gastou as voltas todas a chamar ferramentas: acaba como o Gemini acabaria (sem texto).
      if (voltas > MAX_TOOL_ITERS) claudeTerminou = true;
    }
    if (!claudeTerminou && !GEMINI_API_KEY) {
      geminiError = "claude indisponivel e GEMINI_API_KEY em falta";
    }

    let toolIters = 0;
    while (!claudeTerminou && !geminiError && toolIters <= MAX_TOOL_ITERS) {
      modeloUsado = MODEL;
      const gemRes = await callGemini(SYSTEM_PROMPT, contents, TOOLS);
      if (!gemRes.ok) {
        geminiError = gemRes.error ?? "gemini unknown error";
        break;
      }
      const cand = gemRes.data?.candidates?.[0];
      const parts: Json[] = cand?.content?.parts ?? [];
      const fnCallPart = parts.find((p: Json) => p.functionCall);

      if (fnCallPart) {
        const fnName: string = fnCallPart.functionCall.name;
        const fnArgs: Record<string, unknown> = fnCallPart.functionCall.args ?? {};
        const res = await execTool(fnName, fnArgs, sbAdmin);
        actionsLog.push({
          tool: fnName,
          input: fnArgs,
          ok: res.ok,
          ts: new Date().toISOString(),
        });
        contents.push({ role: "model", parts: [{ functionCall: fnCallPart.functionCall }] });
        contents.push({
          role: "function",
          parts: [
            {
              functionResponse: {
                name: fnName,
                response: res.ok ? { result: res.result } : { error: res.error },
              },
            },
          ],
        });
        toolIters++;
        continue;
      }

      finalText = parts.map((p: Json) => p.text ?? "").join("").trim();
      break;
    }

    if (geminiError) {
      return new Response(
        JSON.stringify({ error: geminiError, actions: actionsLog }),
        { status: 502, headers: { ...cors, "content-type": "application/json" } },
      );
    }

    if (!finalText) {
      finalText = "(sem resposta do modelo — tenta reformular)";
    }

    // Persiste sessão completa para auditoria
    let savedSessionId = sessionId;
    const allMessages = [
      ...incomingMessages,
      { role: "assistant", content: finalText },
    ];
    if (sessionId) {
      await sbAdmin
        .from("admin_ai_sessions")
        .update({ messages: allMessages, actions: actionsLog })
        .eq("id", sessionId);
    } else {
      const firstUser = incomingMessages.find((m) => m.role === "user");
      const title = typeof firstUser?.content === "string"
        ? firstUser.content.slice(0, 80)
        : "Nova sessão";
      const { data: ins } = await sbAdmin
        .from("admin_ai_sessions")
        .insert({
          admin_id: userData.user.id,
          title,
          messages: allMessages,
          actions: actionsLog,
        })
        .select("id")
        .single();
      savedSessionId = (ins?.id as string) ?? null;
    }

    return new Response(
      JSON.stringify({
        session_id: savedSessionId,
        reply: finalText,
        actions: actionsLog,
        model: modeloUsado,
      }),
      { headers: { ...cors, "content-type": "application/json" } },
    );
  } catch (e) {
    return new Response(JSON.stringify({ error: (e as Error).message }), {
      status: 500,
      headers: { ...cors, "content-type": "application/json" },
    });
  }
});
