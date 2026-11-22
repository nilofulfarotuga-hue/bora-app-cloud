import { createClient } from "npm:@supabase/supabase-js@2";

// Porta do Hermes. Autentica por senha própria (só o sha256 vive em hermes_porta_tokens; ativo=false cancela).
// v1-v3 (18-19/11): lista fechada de operações nas tabelas dele.
// v4 (22/11, missão hermes-diretor-2026-11-20, ordem do Danilo de 20/11 "abre tudo... só não a parte do
// dinheiro"): o Hermes passa a LER tudo (menos segredos) e a ESCREVER em quase tudo. Quem decide o que passa
// é a base de dados (função hermes_porta_decidir, com a classificação do esquema): valores e qualquer apagar
// só com uma autorização do Danilo (uma operação exata, uma vez, 30 min); pedidos e prestadores só pelas
// funções ops_*; tabelas de controlo e de segredos nunca. A chave geral continua fora do contentor.
// O "autorizo" dito no Telegram NÃO é registado pelo Hermes: é conferido por um verificador sem IA, com senha
// própria (nome a começar por "verificador"), para o Hermes não conseguir inventar um autorizo.

const URL_SB = Deno.env.get("SUPABASE_URL")!;
const servico = () => Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
const sb = createClient(URL_SB, servico(), { auth: { persistSession: false } });

const REDES = ["redes_interacoes", "redes_metricas", "redes_experiencias"];
const IDENT = /^[a-z_][a-z0-9_]*$/;
const OPS = ["ping", "kpi_clientes", "despacho_inserir", "despacho_atualizar", "despacho_ler", "redes_interacoes", "redes_metricas",
  "redes_experiencias", "redes_ler", "livro_gravar", "e2e", "ler", "sql_ler", "colunas", "rest", "rpc", "pedir_autorizacao",
  "autorizacao_estado", "registar_autorizo"];

const json = (o: unknown, status = 200) =>
  new Response(JSON.stringify(o), { status, headers: { "Content-Type": "application/json" } });

async function sha256(s: string) {
  const d = await crypto.subtle.digest("SHA-256", new TextEncoder().encode(s));
  return Array.from(new Uint8Array(d)).map((b) => b.toString(16).padStart(2, "0")).join("");
}

function pick(o: Record<string, unknown>, keys: string[]) {
  const r: Record<string, unknown> = {};
  for (const k of keys) if (o && k in o && o[k] !== undefined) r[k] = o[k];
  return r;
}

// Valor → literal SQL (para a operação "ler", que monta um SELECT simples).
function lit(v: unknown): string {
  if (v === null || v === undefined) return "null";
  if (typeof v === "number" && Number.isFinite(v)) return String(v);
  if (typeof v === "boolean") return v ? "true" : "false";
  if (Array.isArray(v)) return "(" + (v.length ? v.map(lit).join(", ") : "null") + ")";
  return "'" + String(v).replace(/'/g, "''") + "'";
}
const COMP: Record<string, string> = { eq: "=", neq: "<>", gt: ">", gte: ">=", lt: "<", lte: "<=", like: "like", ilike: "ilike", in: "in", is: "is" };

async function restBruto(metodo: string, tab: string, qs: string, corpo: unknown, prefer: string) {
  const headers: Record<string, string> = { apikey: servico(), Authorization: `Bearer ${servico()}`, "Content-Type": "application/json" };
  if (prefer) headers["Prefer"] = prefer;
  const r = await fetch(`${URL_SB}/rest/v1/${tab}?${qs}`, { method: metodo, headers, body: metodo === "GET" || metodo === "DELETE" ? undefined : JSON.stringify(corpo) });
  const txt = await r.text();
  let c: unknown = null;
  try { c = txt ? JSON.parse(txt) : null; } catch { c = txt; }
  return { ok: r.ok, status: r.status, contagem: r.headers.get("content-range"), corpo: c };
}

Deno.serve(async (req: Request) => {
  if (req.method !== "POST") return json({ erro: "usa POST" }, 405);
  const raw = await req.text();
  if (raw.length > 300_000) return json({ erro: "corpo grande demais" }, 413);
  let b: any;
  try { b = JSON.parse(raw); } catch { return json({ erro: "json invalido" }, 400); }

  const token = String(req.headers.get("x-hermes-token") ?? b?.token ?? "");
  if (token.length < 32) return json({ erro: "sem senha" }, 401);
  const h = await sha256(token);
  const { data: t } = await sb.from("hermes_porta_tokens").select("hash,nome").eq("hash", h).eq("ativo", true).maybeSingle();
  if (!t) return json({ erro: "senha invalida ou cancelada" }, 401);
  await sb.from("hermes_porta_tokens").update({ ultimo_uso: new Date().toISOString() }).eq("hash", h);
  const verificador = String(t.nome ?? "").startsWith("verificador");

  const op = String(b?.op ?? "");
  const d = (b?.dados ?? {}) as Record<string, any>;
  // A senha do verificador só serve para conferir autorizações: nada mais.
  if (verificador && !["ping", "registar_autorizo", "autorizacao_estado"].includes(op)) return json({ erro: "esta senha so serve para conferir o autorizo" }, 403);

  try {
    switch (op) {
      case "ping":
        return json({ ok: true, hora: new Date().toISOString(), versao: "v4-diretor" });

      case "kpi_clientes": {
        const r = await sb.rpc("hermes_kpi_clientes");
        if (r.error) return json({ erro: r.error.message }, 400);
        return json({ ok: true, ...r.data });
      }

      case "despacho_inserir": {
        const row = pick(d, ["para", "tipo", "titulo", "tarefa", "prioridade", "subtarefas", "conversa_id", "precisa_auditoria"]);
        if (!row.para || !row.titulo || !row.tarefa) return json({ erro: "faltam para, titulo, tarefa" }, 400);
        const r = await sb.from("despacho").insert({ ...row, origem: "agente", tipo: row.tipo ?? "tarefa" }).select("id,estado").single();
        if (r.error) return json({ erro: r.error.message }, 400);
        return json({ ok: true, ...r.data });
      }

      case "despacho_atualizar": {
        if (!d.id) return json({ erro: "falta id" }, 400);
        const upd = pick(d, ["estado", "resultado", "prova", "prova_dados", "subtarefas", "iniciada_em", "terminada_em"]);
        const r = await sb.from("despacho").update({ ...upd, atualizada_em: new Date().toISOString() }).eq("id", d.id).select("id,estado").single();
        if (r.error) return json({ erro: r.error.message }, 400);
        return json({ ok: true, ...r.data });
      }

      case "despacho_ler": {
        let q = sb.from("despacho").select("id,origem,para,tipo,titulo,tarefa,estado,resultado,prova,created_at,terminada_em").order("id", { ascending: false }).limit(Math.min(Number(d.limite ?? 20), 50));
        if (d.para) q = q.eq("para", d.para);
        if (d.estado) q = q.eq("estado", d.estado);
        if (d.id) q = q.eq("id", d.id);
        const r = await q;
        if (r.error) return json({ erro: r.error.message }, 400);
        return json({ ok: true, linhas: r.data });
      }

      case "redes_interacoes": {
        const rows = (Array.isArray(d.linhas) ? d.linhas : [d]).slice(0, 200).map((x: any) =>
          pick(x, ["conta", "rede", "tipo", "id_externo", "id_video", "autor", "recebido", "resposta", "juiz", "estado", "canal", "motor", "erro", "recebido_em"])
        );
        const r = await sb.from("redes_interacoes").upsert(rows, { onConflict: "rede,tipo,id_externo" }).select("id");
        if (r.error) return json({ erro: r.error.message }, 400);
        return json({ ok: true, n: r.data?.length ?? 0 });
      }

      case "redes_metricas": {
        const rows = (Array.isArray(d.linhas) ? d.linhas : [d]).slice(0, 500).map((x: any) =>
          pick(x, ["conta", "rede", "dia", "id_video", "numeros", "fonte"])
        );
        const r = await sb.from("redes_metricas").upsert(rows, { onConflict: "conta,rede,dia,id_video" }).select("id");
        if (r.error) return json({ erro: r.error.message }, 400);
        return json({ ok: true, n: r.data?.length ?? 0 });
      }

      case "redes_experiencias": {
        const rows = (Array.isArray(d.linhas) ? d.linhas : [d]).slice(0, 100).map((x: any) =>
          ({ ...pick(x, ["conta", "rede", "semana_inicio", "o_que_testou", "antes", "depois", "decisao", "estado"]), atualizado_em: new Date().toISOString() })
        );
        const r = await sb.from("redes_experiencias").upsert(rows, { onConflict: "conta,rede,semana_inicio" }).select("id");
        if (r.error) return json({ erro: r.error.message }, 400);
        return json({ ok: true, n: r.data?.length ?? 0 });
      }

      case "redes_ler": {
        const tab = REDES.includes(d.tabela) ? d.tabela : null;
        if (!tab) return json({ erro: "tabela invalida" }, 400);
        let q = sb.from(tab).select("*").order("id", { ascending: false }).limit(Math.min(Number(d.limite ?? 50), 200));
        if (d.conta) q = q.eq("conta", d.conta);
        if (d.estado && tab === "redes_interacoes") q = q.eq("estado", d.estado);
        const r = await q;
        if (r.error) return json({ erro: r.error.message }, 400);
        return json({ ok: true, linhas: r.data });
      }

      // ───────── v4: ler tudo (menos segredos) ─────────
      case "colunas": {
        const tab = String(d.tabela ?? "");
        if (!IDENT.test(tab)) return json({ erro: "tabela invalida" }, 400);
        const r = await sb.rpc("hermes_porta_colunas", { p_tabela: tab });
        if (r.error) return json({ erro: r.error.message }, 400);
        return json({ ok: true, tabela: tab, colunas: r.data ?? [] });
      }

      case "sql_ler": {
        const r = await sb.rpc("hermes_porta_sql_ler", { p_sql: String(d.sql ?? ""), p_limite: Number(d.limite ?? 200) });
        if (r.error) return json({ erro: r.error.message }, 400);
        return json(r.data);
      }

      case "ler": {
        // dados: { tabela, colunas?: [..], filtros?: {col: valor} | [{coluna, op, valor}], ordem?: "col" | "col.desc", limite? }
        const tab = String(d.tabela ?? "");
        if (!IDENT.test(tab)) return json({ erro: "tabela invalida" }, 400);
        let cols: string[] = Array.isArray(d.colunas) ? d.colunas.map(String) : [];
        if (!cols.length) {
          const c = await sb.rpc("hermes_porta_colunas", { p_tabela: tab });
          if (c.error) return json({ erro: c.error.message }, 400);
          cols = c.data ?? [];
          if (!cols.length) return json({ erro: "esta tabela nao existe ou a porta nao a abre" }, 403);
        }
        if (cols.some((c) => !IDENT.test(c))) return json({ erro: "coluna invalida" }, 400);
        const filtros: { coluna: string; op: string; valor: unknown }[] = Array.isArray(d.filtros)
          ? d.filtros
          : Object.entries(d.filtros ?? {}).map(([coluna, valor]) => ({ coluna, op: valor === null ? "is" : Array.isArray(valor) ? "in" : "eq", valor }));
        const partes: string[] = [];
        for (const f of filtros) {
          if (!IDENT.test(String(f.coluna)) || !COMP[String(f.op ?? "eq")]) return json({ erro: "filtro invalido" }, 400);
          partes.push(`"${f.coluna}" ${COMP[String(f.op ?? "eq")]} ${lit(f.valor)}`);
        }
        let ordem = "";
        if (d.ordem) {
          const [c, dir] = String(d.ordem).split(".");
          if (!IDENT.test(c)) return json({ erro: "ordem invalida" }, 400);
          ordem = ` order by "${c}" ${dir === "desc" ? "desc" : "asc"}`;
        }
        const sql = `select ${cols.map((c) => `"${c}"`).join(", ")} from public."${tab}"${partes.length ? " where " + partes.join(" and ") : ""}${ordem}`;
        const r = await sb.rpc("hermes_porta_sql_ler", { p_sql: sql, p_limite: Math.min(Number(d.limite ?? 100), 1000) });
        if (r.error) return json({ erro: r.error.message }, 400);
        return json(r.data);
      }

      // ───────── v4: escrever em quase tudo, com o travão na base de dados ─────────
      case "rest": {
        // dados: { metodo: GET|POST|PATCH|DELETE, tabela, query, corpo, prefer, autorizacao_id? }
        const metodo = String(d.metodo ?? "GET").toUpperCase();
        const tab = String(d.tabela ?? "");
        const query = String(d.query ?? "").replace(/^\?/, "");
        const qs = new URLSearchParams(query);
        const sel = qs.get("select");
        if (sel && /[():!]/.test(sel)) return json({ erro: "select nao pode juntar outras tabelas (usa sql_ler)" }, 400);
        if (["POST", "PATCH"].includes(metodo) && d.corpo === undefined) return json({ erro: "falta corpo" }, 400);
        const operacao = { tipo: "rest", metodo, tabela: tab, query, corpo: d.corpo ?? null };
        const dec = await sb.rpc("hermes_porta_decidir", { p_op: operacao, p_autorizacao_id: d.autorizacao_id ?? null });
        if (dec.error) return json({ erro: dec.error.message }, 400);
        if (!dec.data?.permitido) return json({ erro: dec.data?.motivo ?? "recusado", precisa_autorizo: !!dec.data?.precisa_autorizo, classe: dec.data?.classe ?? null }, 403);
        const prefer = String(d.prefer ?? "")
          .split(",").map((s) => s.trim())
          .filter((s) => /^(resolution=(merge|ignore)-duplicates|return=(representation|minimal)|count=(exact|planned|estimated)|missing=default)$/.test(s));
        if (metodo === "DELETE") {
          // nada se perde: guarda primeiro as linhas que vão ser apagadas (no máximo 1000 de cada vez)
          const filtro = [...qs.entries()].filter(([k]) => !["select", "limit", "offset", "order"].includes(k)).concat([["limit", "1001"]]);
          const antes = await restBruto("GET", tab, new URLSearchParams(filtro).toString(), null, "");
          const linhas = Array.isArray(antes.corpo) ? antes.corpo : [];
          if (!antes.ok || linhas.length > 1000) {
            await sb.rpc("hermes_autorizacao_resultado", { p_id: d.autorizacao_id, p_resultado: "nao apagou: " + (antes.ok ? "mais de 1000 linhas; apaga em lotes" : "nao consegui ler as linhas a guardar") });
            return json({ erro: antes.ok ? "mais de 1000 linhas: apaga em lotes mais pequenos (pede nova autorizacao)" : "nao consegui guardar a copia antes de apagar" }, 400);
          }
          await sb.rpc("hermes_apagados_guardar", { p_autorizacao_id: d.autorizacao_id, p_tabela: tab, p_linhas: linhas });
          if (!prefer.some((s) => s.startsWith("return="))) prefer.push("return=representation");
        }
        const r = await restBruto(metodo, tab, qs.toString(), d.corpo, prefer.join(","));
        if (metodo !== "GET") {
          await sb.rpc("hermes_porta_auditar", { p_acao: "hermes_porta_rest_" + metodo.toLowerCase(), p_ref: tab, p_detalhe: { query, status: r.status, autorizacao_id: d.autorizacao_id ?? null, classe: dec.data?.classe } });
          if (d.autorizacao_id) await sb.rpc("hermes_autorizacao_resultado", { p_id: d.autorizacao_id, p_resultado: (r.ok ? "feito" : "falhou") + " (HTTP " + r.status + ")" });
        }
        return json({ ok: r.ok, status: r.status, contagem: r.contagem, corpo: r.corpo }, r.ok ? 200 : 400);
      }

      case "rpc": {
        // dados: { funcao, args, autorizacao_id? }
        const funcao = String(d.funcao ?? "");
        if (!IDENT.test(funcao)) return json({ erro: "funcao invalida" }, 400);
        const operacao = { tipo: "rpc", funcao, args: d.args ?? {} };
        const dec = await sb.rpc("hermes_porta_decidir", { p_op: operacao, p_autorizacao_id: d.autorizacao_id ?? null });
        if (dec.error) return json({ erro: dec.error.message }, 400);
        if (!dec.data?.permitido) return json({ erro: dec.data?.motivo ?? "recusado", precisa_autorizo: !!dec.data?.precisa_autorizo, classe: dec.data?.classe ?? null }, 403);
        const r = await sb.rpc(funcao, d.args ?? {});
        await sb.rpc("hermes_porta_auditar", { p_acao: "hermes_porta_rpc", p_ref: funcao, p_detalhe: { ok: !r.error, autorizacao_id: d.autorizacao_id ?? null, classe: dec.data?.classe } });
        if (d.autorizacao_id) await sb.rpc("hermes_autorizacao_resultado", { p_id: d.autorizacao_id, p_resultado: r.error ? "falhou: " + r.error.message : "feito" });
        if (r.error) return json({ erro: r.error.message }, 400);
        return json({ ok: true, resultado: r.data });
      }

      // ───────── v4: o autorizo do Danilo ─────────
      case "pedir_autorizacao": {
        // dados: { acao (português simples), porque, valor_eur, operacao (a chamada rest/rpc exata que vai fazer), teste? }
        const r = await sb.rpc("hermes_autorizacao_pedir", { p_acao: String(d.acao ?? ""), p_porque: d.porque ?? null, p_valor_eur: d.valor_eur ?? null, p_operacao: d.operacao ?? {}, p_teste: !!d.teste });
        if (r.error) return json({ erro: r.error.message }, 400);
        return json(r.data, r.data?.ok ? 200 : 400);
      }

      case "autorizacao_estado": {
        if (verificador && !d.id) {   // o verificador precisa de saber o que está à espera
          const p = await sb.from("hermes_autorizacoes").select("id,acao,valor_eur,criada_em,expira_em").eq("estado", "pendente").gt("expira_em", new Date().toISOString()).order("id");
          if (p.error) return json({ erro: p.error.message }, 400);
          return json({ ok: true, pendentes: p.data });
        }
        if (!d.id) return json({ erro: "falta id" }, 400);
        const r = await sb.from("hermes_autorizacoes").select("id,acao,valor_eur,estado,expira_em,via,decidida_em,usada_em,resultado").eq("id", d.id).maybeSingle();
        if (r.error) return json({ erro: r.error.message }, 400);
        return json({ ok: !!r.data, ...(r.data ?? { erro: "nao existe" }) });
      }

      case "registar_autorizo": {
        // Só o verificador sem IA (que confere a mensagem verdadeira do Danilo no Telegram) regista um autorizo.
        if (!verificador) return json({ ok: false, erro: "o autorizo do Telegram e conferido por um verificador sem IA, em menos de 1 minuto. Espera e ve o estado com autorizacao_estado." }, 403);
        if (!d.autorizacao_id) return json({ erro: "falta autorizacao_id" }, 400);
        if (d.anular) {   // o Danilo respondeu NÃO à confirmação: anula, se ainda não foi usada
          const a = await sb.rpc("hermes_autorizacao_anular", { p_id: d.autorizacao_id, p_quem: "danilo-telegram", p_texto: String(d.texto_literal_do_danilo ?? "") });
          if (a.error) return json({ erro: a.error.message }, 400);
          return json(a.data, a.data?.ok ? 200 : 400);
        }
        const decisao = d.recusar ? "recusada" : "autorizada";
        const r = await sb.rpc("hermes_autorizacao_decidir", { p_id: d.autorizacao_id, p_decisao: decisao, p_via: "telegram", p_quem: "danilo-telegram", p_texto: String(d.texto_literal_do_danilo ?? ""), p_telegram_message_id: d.telegram_message_id ?? null });
        if (r.error) return json({ erro: r.error.message }, 400);
        return json(r.data, r.data?.ok ? 200 : 400);
      }

      case "livro_gravar": {
        // Só páginas hermes-*: não deixa sobrescrever a memória do resto do sistema.
        const pagina = String(d.pagina ?? "");
        if (!/^hermes-[a-z0-9-]{1,80}$/.test(pagina)) return json({ erro: "pagina tem de ser hermes-..." }, 400);
        if (!d.titulo || !d.conteudo) return json({ erro: "faltam titulo e conteudo" }, 400);
        const r = await sb.from("claude_ai_memoria").upsert({ pagina, titulo: String(d.titulo).slice(0, 200), conteudo: String(d.conteudo).slice(0, 60000), origem: "hermes", atualizado_em: new Date().toISOString() }, { onConflict: "pagina" }).select("pagina");
        if (r.error) return json({ erro: r.error.message }, 400);
        return json({ ok: true, pagina });
      }

      case "e2e": {
        const row = pick(d, ["fluxo", "passo", "estado", "detalhe", "run_id"]);
        if (!row.fluxo || !row.passo || !row.estado) return json({ erro: "faltam fluxo, passo, estado" }, 400);
        const r = await sb.from("e2e_log").insert({ ...row, device: "hermes" }).select("id").single();
        if (r.error) return json({ erro: r.error.message }, 400);
        return json({ ok: true, id: r.data.id });
      }

      default:
        return json({ erro: "operacao desconhecida", ops: OPS }, 400);
    }
  } catch (e) {
    return json({ erro: String((e as Error).message ?? e) }, 500);
  }
});
