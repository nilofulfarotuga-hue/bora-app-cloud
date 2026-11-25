import { createClient } from "npm:@supabase/supabase-js@2";
import { secretKey } from "../_shared/keys.ts";
import { chamadaDoServidor } from "../_shared/chaves.ts";

// voz-ferramentas (25/11/2026, missão atendente-voz-2026-11-25, bloco B3).
// As ferramentas do atendente de voz do telefone da Bora (central Pipecat na VPS).
// Autentica por senha própria no cabeçalho x-voz-token (só o sha256 vive em
// voz_ferramentas_tokens; ativo=false cancela), como a hermes-porta.
// Só LÊ dados do Bora e só ESCREVE nas tabelas das chamadas e no porteiro do
// Telegram. Nunca mexe em pedidos, dinheiro, tokens nem carteiras.
//
// Operações (POST {op, dados}):
//   ping | config | abrir | fala | fechar | pedidos | loja | livro | escalar | audio_upload
//   limpar_audios (só servidor: cron diário voz-limpar-audios)

const URL_SB = Deno.env.get("SUPABASE_URL")!;
const sb = createClient(URL_SB, secretKey(), { auth: { persistSession: false } });

const json = (o: unknown, status = 200) =>
  new Response(JSON.stringify(o), { status, headers: { "Content-Type": "application/json" } });

async function sha256(s: string) {
  const d = await crypto.subtle.digest("SHA-256", new TextEncoder().encode(s));
  return Array.from(new Uint8Array(d)).map((b) => b.toString(16).padStart(2, "0")).join("");
}

const txt = (v: unknown, max = 500) => String(v ?? "").slice(0, max);

// Páginas do livro que o atendente pode consultar (nunca as [PESSOAL]).
const LIVRO_PREFIXOS = ["livro-", "business-rules", "faq-", "playbook-", "regras-operacao", "atendimento-"];
// Páginas do livro sobre a vida do dono ou outros projetos: nunca vão ao atendente,
// mesmo sem a marca [PESSOAL] (ex.: livro-areas-candidatura-paa-moradia).
const LIVRO_FORA = /pessoal|moradia|paa|financiamento|apoios|jai|danilo|saude|familia|irs|banco|divida|credito|arandelas|beunique|studio|conselho|conectores|claude|auditoria|faturacao|fiscal|stripe|contas-|acerto|chave|segredo|seguranca/i;

async function definicoes() {
  const { data } = await sb.from("voz_definicoes").select("key,value");
  const d: Record<string, unknown> = {};
  for (const r of data ?? []) d[r.key] = r.value;
  return d;
}

Deno.serve(async (req: Request) => {
  if (req.method !== "POST") return json({ erro: "usa POST" }, 405);
  const raw = await req.text();
  if (raw.length > 200_000) return json({ erro: "corpo grande demais" }, 413);
  let b: any;
  try { b = JSON.parse(raw || "{}"); } catch { return json({ erro: "JSON invalido" }, 400); }
  const op = String(b?.op ?? "");
  const d = (b?.dados ?? {}) as Record<string, any>;

  // Limpeza dos áudios com mais de 90 dias: o servidor (chave secreta) ou a própria
  // central com a senha dela (o vigia da VPS chama uma vez por dia). O cron no banco
  // ficou por fazer: a trava do modo automático recusa ler o cofre (vault).
  if (op === "limpar_audios") {
    const tk = String(req.headers.get("x-voz-token") ?? "");
    let centralOk = false;
    if (tk.length >= 32) {
      const { data: tc } = await sb.from("voz_ferramentas_tokens").select("hash")
        .eq("hash", await sha256(tk)).eq("ativo", true).maybeSingle();
      centralOk = !!tc;
    }
    if (!centralOk && !(await chamadaDoServidor(req))) return json({ erro: "so servidor" }, 401);
    const { data: velhos, error } = await sb.rpc("voz_audios_expirados", { p_limite: 200 });
    if (error) return json({ erro: error.message }, 500);
    let apagados = 0;
    for (const v of velhos ?? []) {
      const { error: e } = await sb.storage.from("chamadas-voz").remove([v.audio_path]);
      if (!e) { await sb.rpc("voz_audio_apagado", { p_chamada_id: v.id }); apagados++; }
    }
    return json({ ok: true, encontrados: (velhos ?? []).length, apagados });
  }

  const token = String(req.headers.get("x-voz-token") ?? "");
  if (token.length < 32) return json({ erro: "sem senha" }, 401);
  const h = await sha256(token);
  const { data: t } = await sb.from("voz_ferramentas_tokens").select("hash").eq("hash", h).eq("ativo", true).maybeSingle();
  if (!t) return json({ erro: "senha invalida ou cancelada" }, 401);
  await sb.from("voz_ferramentas_tokens").update({ ultimo_uso: new Date().toISOString() }).eq("hash", h);

  try {
    switch (op) {
      case "ping":
        return json({ ok: true, hora: new Date().toISOString(), versao: "v1" });

      // Definições + gasto do dia + motor a usar (reserva se o teto do dia passou).
      case "config": {
        const def = await definicoes();
        const { data: gasto } = await sb.rpc("voz_gasto_hoje_usd");
        const gastoUsd = Number(gasto ?? 0);
        const tetoDiaEur = Number(def.voz_opus_teto_dia_eur ?? 5);
        // Conversão prudente (1 USD ≈ 0,95 EUR); o teto conta-se em euros.
        const passouTeto = gastoUsd * 0.95 >= tetoDiaEur;
        return json({
          ok: true, definicoes: def, gasto_hoje_usd: gastoUsd,
          motor: passouTeto ? def.voz_motor_reserva : def.voz_motor, passou_teto_dia: passouTeto,
        });
      }

      // Abre a chamada e já traz quem é e os pedidos recentes desse número.
      case "abrir": {
        const tel = txt(d.telefone, 40);
        const { data: ab, error } = await sb.rpc("voz_chamada_abrir", {
          p_telefone: tel, p_sip_call_id: txt(d.sip_call_id, 200), p_motor: txt(d.motor, 60), p_teste: !!d.teste,
        });
        if (error) return json({ erro: error.message }, 500);
        const userId = ab?.quem?.user_id ?? null;
        const { data: ped } = await sb.rpc("voz_pedidos_recentes", { p_tel: tel, p_user_id: userId });
        return json({ ok: true, ...ab, pedidos: ped ?? [] });
      }

      case "fala": {
        const quem = txt(d.quem, 20);
        if (!["cliente", "atendente", "sistema", "ferramenta"].includes(quem)) return json({ erro: "quem invalido" }, 400);
        const texto = txt(d.texto, 8000).trim();
        if (!texto) return json({ ok: true, ignorada: true });
        const { data: id, error } = await sb.rpc("voz_fala_gravar", {
          p_chamada_id: d.chamada_id, p_quem: quem, p_texto: texto, p_ms: d.ms ?? null,
        });
        if (error) return json({ erro: error.message }, 500);
        return json({ ok: true, id });
      }

      case "fechar": {
        const etiquetas = Array.isArray(d.etiquetas) ? d.etiquetas.map((e: unknown) => txt(e, 40)).slice(0, 10) : [];
        const { data: r, error } = await sb.rpc("voz_chamada_fechar", {
          p_chamada_id: d.chamada_id, p_estado: txt(d.estado, 20), p_resumo: txt(d.resumo, 1200),
          p_etiquetas: etiquetas, p_custo_usd: Number(d.custo_usd ?? 0),
          p_tokens_entrada: Math.round(Number(d.tokens_entrada ?? 0)), p_tokens_saida: Math.round(Number(d.tokens_saida ?? 0)),
          p_audio_path: d.audio_path ? txt(d.audio_path, 300) : null,
          p_primeira_palavra_ms: d.primeira_palavra_ms == null ? null : Math.round(Number(d.primeira_palavra_ms)),
          p_gravacao_consentida: d.gravacao_consentida !== false,
        });
        if (error) return json({ erro: error.message }, 500);
        return json(r);
      }

      case "pedidos": {
        const { data, error } = await sb.rpc("voz_pedidos_recentes", {
          p_tel: txt(d.telefone, 40), p_user_id: d.user_id ?? null,
        });
        if (error) return json({ erro: error.message }, 500);
        return json({ ok: true, pedidos: data ?? [] });
      }

      // Lojas: nome, tipo, se é parceira, se está aberta ao público na app, horário.
      case "loja": {
        const q = txt(d.consulta, 80).replace(/[%_,()]/g, " ").trim();
        if (q.length < 2) return json({ erro: "consulta curta" }, 400);
        const { data, error } = await sb.from("restaurants")
          .select("name,category,is_partner,coming_soon,business_hours,approval_status")
          .ilike("name", `%${q}%`).limit(5);
        if (error) return json({ erro: error.message }, 500);
        return json({
          ok: true,
          lojas: (data ?? []).map((r) => ({
            nome: r.name, tipo: r.category, parceira: !!r.is_partner,
            disponivel_na_app: r.approval_status === "approved" && !r.coming_soon,
            horario: r.business_hours ?? null,
          })),
        });
      }

      // Livro comum: só páginas de negócio (nunca [PESSOAL]); devolve trechos curtos.
      case "livro": {
        const q = txt(d.consulta, 80).replace(/[%_,()]/g, " ").trim();
        if (q.length < 3) return json({ erro: "consulta curta" }, 400);
        const { data, error } = await sb.from("claude_ai_memoria").select("pagina,conteudo")
          .or(LIVRO_PREFIXOS.map((p) => `pagina.ilike.${p}*`).join(","))
          .ilike("conteudo", `%${q}%`).limit(12);
        if (error) return json({ erro: error.message }, 500);
        const trechos = (data ?? [])
          .filter((r) => !/\[PESSOAL\]/i.test(r.conteudo ?? "") && !LIVRO_FORA.test(r.pagina ?? ""))
          .slice(0, 4)
          .map((r) => {
            const c = String(r.conteudo ?? "");
            const i = Math.max(0, c.toLowerCase().indexOf(q.toLowerCase()) - 300);
            return { pagina: r.pagina, trecho: c.slice(i, i + 900) };
          });
        return json({ ok: true, trechos });
      }

      // Passa o caso à equipa: cartão no Telegram (porteiro) — o push vai no fechar.
      case "escalar": {
        const cartao = [
          "📞 ATENDENTE DE VOZ — caso para a equipa",
          `Quem: ${txt(d.quem, 120) || "não identificado"} (${txt(d.telefone, 30) || "sem número"})`,
          `Quer: ${txt(d.o_que_quer, 300)}`,
          d.pedido ? `Pedido: ${txt(d.pedido, 40)}` : "",
          `Resumo: ${txt(d.resumo, 600)}`,
          d.chamada_id ? `Chamada: /admin/chamadas/${txt(d.chamada_id, 40)}` : "",
        ].filter(Boolean).join("\n");
        const { error } = await sb.from("porteiro_entrada").insert({
          origem: "atendente-voz", nivel: d.teste ? "INFO" : "URGENTE", texto: cartao.slice(0, 3900),
        });
        if (error) return json({ erro: error.message }, 500);
        return json({ ok: true });
      }

      // URL para a central enviar o áudio da chamada (bucket privado, 90 dias).
      case "audio_upload": {
        const id = txt(d.chamada_id, 40);
        if (!/^[0-9a-f-]{36}$/.test(id)) return json({ erro: "chamada_id invalido" }, 400);
        const ext = ["wav", "mp3", "ogg"].includes(String(d.ext)) ? String(d.ext) : "wav";
        const caminho = `${new Date().toISOString().slice(0, 7)}/${id}.${ext}`;
        const { data, error } = await sb.storage.from("chamadas-voz").createSignedUploadUrl(caminho);
        if (error) return json({ erro: error.message }, 500);
        return json({ ok: true, caminho, url: data.signedUrl, token: data.token });
      }

      default:
        return json({ erro: `operacao desconhecida: ${op}` }, 400);
    }
  } catch (e) {
    return json({ erro: String((e as Error)?.message ?? e) }, 500);
  }
});
