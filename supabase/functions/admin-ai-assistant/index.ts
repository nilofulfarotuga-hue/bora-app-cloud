// admin-ai-assistant — chat IA do painel admin com tool use Claude
// Requer secrets: ANTHROPIC_API_KEY, SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY
//
// Modelo: claude-sonnet-4-6 (Sonnet 4.6, custo-efectivo).
// Tools disponíveis (read-only nesta v1 — write virá após Danilo aprovar):
//   - sql_select: executa SELECT arbitrário em public schema (timeouts curtos)
//   - list_pending_actions: helper para listar acções pendentes
//   - get_platform_setting / set_platform_setting: ler/escrever platform_settings

import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import Anthropic from "https://esm.sh/@anthropic-ai/sdk@0.30.1";

const SUPABASE_URL = Deno.env.get("SUPABASE_URL")!;
const SUPABASE_SERVICE_ROLE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
const ANTHROPIC_API_KEY = Deno.env.get("ANTHROPIC_API_KEY")!;
const MODEL = "claude-sonnet-4-6";

const SYSTEM_PROMPT = `És o assistente IA do painel admin da Bora App (delivery + supermercados + reservas em Guarda, Portugal).

Tens acesso directo ao Supabase via tools. Idioma: PT-BR (Danilo é brasileiro).

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

Quando perguntarem por dados (ex: "pedidos de hoje"), usa o tool sql_select com uma query SELECT.
Sê conciso. Mostra resultados em formato fácil de ler.
`;

const TOOLS = [
  {
    name: "sql_select",
    description:
      "Executa uma query SELECT no schema public. SOMENTE SELECT — DML/DDL é rejeitado. Timeout 5s. Limita resultados a 200 linhas.",
    input_schema: {
      type: "object",
      properties: {
        query: {
          type: "string",
          description: "SELECT statement (sem DML/DDL).",
        },
        rationale: {
          type: "string",
          description: "Porque é necessária esta query.",
        },
      },
      required: ["query", "rationale"],
    },
  },
  {
    name: "get_platform_setting",
    description: "Lê um valor de platform_settings pela chave.",
    input_schema: {
      type: "object",
      properties: { key: { type: "string" } },
      required: ["key"],
    },
  },
];

interface ToolUseBlock {
  type: "tool_use";
  id: string;
  name: string;
  input: Record<string, unknown>;
}

interface ToolResultBlock {
  type: "tool_result";
  tool_use_id: string;
  content: string;
  is_error?: boolean;
}

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
    ";--",
  ];
  return banned.some((b) => upper.includes(b)) || !upper.trim().startsWith("SELECT");
}

async function execTool(
  block: ToolUseBlock,
  sb: ReturnType<typeof createClient>,
): Promise<ToolResultBlock> {
  try {
    if (block.name === "sql_select") {
      const q = (block.input.query as string) ?? "";
      if (isDangerousSQL(q)) {
        return {
          type: "tool_result",
          tool_use_id: block.id,
          content: "ERRO: apenas SELECT é permitido neste tool.",
          is_error: true,
        };
      }
      // pg_meta query via service role
      const limited = q.match(/LIMIT\s+\d+/i) ? q : `${q.replace(/;\s*$/, "")} LIMIT 200`;
      const { data, error } = await sb.rpc("admin_run_select", { p_query: limited });
      if (error) {
        return {
          type: "tool_result",
          tool_use_id: block.id,
          content: `ERRO SQL: ${error.message}`,
          is_error: true,
        };
      }
      return {
        type: "tool_result",
        tool_use_id: block.id,
        content: JSON.stringify(data ?? []).slice(0, 8000),
      };
    }
    if (block.name === "get_platform_setting") {
      const key = block.input.key as string;
      const { data, error } = await sb
        .from("platform_settings")
        .select("key, value, description")
        .eq("key", key)
        .maybeSingle();
      if (error) {
        return {
          type: "tool_result",
          tool_use_id: block.id,
          content: `ERRO: ${error.message}`,
          is_error: true,
        };
      }
      return {
        type: "tool_result",
        tool_use_id: block.id,
        content: JSON.stringify(data ?? { error: "key não encontrada" }),
      };
    }
    return {
      type: "tool_result",
      tool_use_id: block.id,
      content: `Tool ${block.name} desconhecido.`,
      is_error: true,
    };
  } catch (e) {
    return {
      type: "tool_result",
      tool_use_id: block.id,
      content: `EXCEPÇÃO: ${(e as Error).message}`,
      is_error: true,
    };
  }
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
    const authHeader = req.headers.get("authorization") ?? "";
    const jwt = authHeader.replace(/^Bearer\s+/i, "");
    if (!jwt) return new Response("missing auth", { status: 401, headers: cors });

    // Verificar role admin no JWT
    const userClient = createClient(SUPABASE_URL, Deno.env.get("SUPABASE_ANON_KEY") ?? "", {
      global: { headers: { Authorization: authHeader } },
    });
    const { data: userData, error: userErr } = await userClient.auth.getUser();
    if (userErr || !userData?.user)
      return new Response("invalid jwt", { status: 401, headers: cors });
    const role =
      (userData.user.app_metadata as Record<string, unknown>)?.["role"] ??
      (userData.user.user_metadata as Record<string, unknown>)?.["role"];
    if (role !== "admin")
      return new Response("forbidden — admin only", { status: 403, headers: cors });

    const body = await req.json().catch(() => ({}));
    const incomingMessages: Array<{ role: string; content: unknown }> =
      Array.isArray(body.messages) ? body.messages : [];
    const sessionId: string | null = body.session_id ?? null;

    if (!ANTHROPIC_API_KEY)
      return new Response(JSON.stringify({ error: "ANTHROPIC_API_KEY missing" }), {
        status: 500,
        headers: { ...cors, "content-type": "application/json" },
      });

    const anthropic = new Anthropic({ apiKey: ANTHROPIC_API_KEY });
    const sbAdmin = createClient(SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY, {
      auth: { autoRefreshToken: false, persistSession: false },
    });

    const actionsLog: Array<Record<string, unknown>> = [];

    // Tool-use loop (max 4 iterations)
    let working = [...incomingMessages];
    let finalText = "";
    for (let i = 0; i < 4; i++) {
      const resp = await anthropic.messages.create({
        model: MODEL,
        max_tokens: 1500,
        system: SYSTEM_PROMPT,
        tools: TOOLS as unknown as Anthropic.Tool[],
        // deno-lint-ignore no-explicit-any
        messages: working as any,
      });

      const textParts = resp.content.filter((b) => b.type === "text").map((b) => (b as { text: string }).text);
      finalText = textParts.join("\n");

      const toolUses = resp.content.filter((b) => b.type === "tool_use") as unknown as ToolUseBlock[];
      if (toolUses.length === 0) {
        working.push({ role: "assistant", content: resp.content });
        break;
      }

      working.push({ role: "assistant", content: resp.content });
      const toolResults: ToolResultBlock[] = [];
      for (const tu of toolUses) {
        const res = await execTool(tu, sbAdmin);
        toolResults.push(res);
        actionsLog.push({
          tool: tu.name,
          input: tu.input,
          ok: !res.is_error,
          ts: new Date().toISOString(),
        });
      }
      working.push({ role: "user", content: toolResults });
    }

    // Persistir sessão
    let savedSessionId = sessionId;
    if (sessionId) {
      await sbAdmin
        .from("admin_ai_sessions")
        .update({ messages: working, actions: actionsLog })
        .eq("id", sessionId);
    } else {
      const { data: ins } = await sbAdmin
        .from("admin_ai_sessions")
        .insert({
          admin_id: userData.user.id,
          title: (incomingMessages[0]?.content as string)?.toString().slice(0, 80) ?? "Nova sessão",
          messages: working,
          actions: actionsLog,
        })
        .select("id")
        .single();
      savedSessionId = ins?.id ?? null;
    }

    return new Response(
      JSON.stringify({
        session_id: savedSessionId,
        reply: finalText,
        actions: actionsLog,
        messages: working,
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
