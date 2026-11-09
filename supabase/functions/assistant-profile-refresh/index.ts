// Amigo Bora v1 (08/11/2026, missão m4-amigo-bora-v1-2026-11-08) — refresca a memória por cliente.
//
// Chamada pelo cron `amigo-bora-perfis` (de hora a hora) com a chave do servidor, ou por um admin
// (`{ user_id }` para um só cliente, `{ dry_run: true }` para ver sem gravar).
//
// Para cada cliente escolhido:
//   1. FACTOS por SQL (`assistant_amigo_factos`): lojas favoritas, artigos que repete, hábitos
//      ("sexta à noite: Jyosmi"), ticket médio, categorias usadas. Custo zero.
//   2. PREFERÊNCIAS já guardadas pelo próprio assistente (`assistant_client_memory`, ferramenta
//      remember): restrições, marcas, "o de sempre". Custo zero.
//   3. CONVERSA (só se houver 3+ mensagens novas do cliente desde o último resumo): o modelo
//      barato (Haiku, robô `edge-amigo-perfil`, P3) tira nome como gosta de ser tratado, registo
//      (formal/informal), restrições e gostos ditos em conversa. Nunca dados de pagamento.
//   4. Grava em `assistant_client_profile` (respeita `lembrar=false` e `esquecido_em`).
//
// Quem é escolhido (máx. 25 por volta): perfil inexistente ou mais velho que o último pedido
// entregue ou que a última mensagem do cliente ao assistente; e os clientes ativos (pedido nos
// últimos 60 dias) com perfil com mais de 24 h. verify_jwt=false: só o servidor ou um admin.

import { createClient } from 'https://esm.sh/@supabase/supabase-js@2.45.0';
import { chamadaDoServidor, respostaAoPing, utilizadorDoPedido } from '../_shared/chaves.ts';
import { secretKey } from '../_shared/keys.ts';
import { claudePrimeiro, extrairJson } from '../_shared/claude.ts';
import { montarPerfil } from './perfil.ts';

const SUPABASE_URL = Deno.env.get('SUPABASE_URL')!;
const MAX_POR_VOLTA = 25;
const MIN_MSGS_NOVAS = 3;

// deno-lint-ignore no-explicit-any
type Json = any;

const cors = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
  'Access-Control-Allow-Methods': 'POST, OPTIONS',
};

function resposta(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), { status, headers: { ...cors, 'Content-Type': 'application/json' } });
}

const PERFIL_SYS = [
  '<<<SYSTEM>>>',
  'Lês mensagens que um cliente escreveu ao assistente de uma app de entregas da Guarda (Bora) e tiras um resumo curto para o assistente o tratar como um amigo.',
  'Devolves SÓ JSON: {"nome_tratamento": "<como o cliente pediu ou assinou, só o primeiro nome; null se não disse>", "registo": "formal"|"informal"|null, "restricoes": ["<restrição alimentar ou de saúde que o cliente DISSE, ex. sem glúten, vegetariano>"], "gostos": ["<gosto que o cliente DISSE, ex. adora sushi, prefere Mimosa>"], "notas": "<1 frase útil para compras, ou null>"}.',
  'Regras: só o que o cliente disse claramente, nunca palpites. Nada de dinheiro, cartões, moradas, telefones, emails, documentos, nomes de outras pessoas. No máximo 5 restrições e 5 gostos, cada um com menos de 60 letras. Se não houver nada, devolve os campos a null ou listas vazias.',
  '<<<END_SYSTEM>>>',
].join('\n');

function limpa(s: unknown, max: number): string {
  return String(s ?? '').replace(/[\u0000-\u001f\u007f]/g, ' ').replace(/<<<|>>>|⟦|⟧/g, '').replace(/\s+/g, ' ').trim().slice(0, max);
}

Deno.serve(async (req: Request) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: cors });
  if (req.method !== 'POST') return resposta({ error: 'method not allowed' }, 405);
  const pong = await respostaAoPing(req, cors);
  if (pong) return pong;

  let autorizado = await chamadaDoServidor(req);
  if (!autorizado) {
    const u = await utilizadorDoPedido(req);
    autorizado = u?.app_metadata?.role === 'admin';
  }
  if (!autorizado) return resposta({ error: 'unauthorized' }, 401);

  let body: { user_id?: string; dry_run?: boolean; scheduled?: boolean } = {};
  try { body = await req.json(); } catch { /* vazio */ }
  const dryRun = body.dry_run === true;
  const db = createClient(SUPABASE_URL, secretKey()!);

  // Interruptores: com o assistente ou a personalidade desligados não se gasta nada.
  const { data: sets } = await db.from('platform_settings').select('key, value')
    .in('key', ['assistant_enabled', 'assistant_personality_enabled']);
  const m = new Map((sets ?? []).map((r: Json) => [r.key, r.value]));
  if (m.get('assistant_enabled') === false || m.get('assistant_personality_enabled') === false) {
    return resposta({ ok: true, saltado: 'assistente ou personalidade desligados' });
  }

  // Quem refrescar.
  let alvos: string[] = [];
  if (typeof body.user_id === 'string' && body.user_id.length > 10) {
    alvos = [body.user_id];
  } else {
    const desde60 = new Date(Date.now() - 60 * 86400_000).toISOString();
    const [{ data: entregues }, { data: msgs }, { data: perfis }] = await Promise.all([
      db.from('orders').select('user_id, created_at').eq('status', 'delivered').gte('created_at', desde60)
        .order('created_at', { ascending: false }).limit(2000),
      db.from('assistant_chat_messages').select('user_id, created_at').eq('role', 'user').gte('created_at', desde60)
        .order('created_at', { ascending: false }).limit(2000),
      db.from('assistant_client_profile').select('user_id, atualizado_em, lembrar'),
    ]);
    const perfil = new Map<string, { em: number; lembrar: boolean }>(
      (perfis ?? []).map((p: Json) => [p.user_id, { em: Date.parse(p.atualizado_em), lembrar: p.lembrar !== false }]));
    const ultimo = new Map<string, number>();
    for (const r of [...(entregues ?? []), ...(msgs ?? [])] as Json[]) {
      if (!r.user_id) continue;
      const t = Date.parse(r.created_at);
      if (!ultimo.has(r.user_id) || ultimo.get(r.user_id)! < t) ultimo.set(r.user_id, t);
    }
    const agora = Date.now();
    const candidatos: Array<{ id: string; prio: number }> = [];
    for (const [id, t] of ultimo) {
      const p = perfil.get(id);
      if (p && !p.lembrar) continue;
      if (!p || t > p.em) candidatos.push({ id, prio: 0 });                    // novidade desde o último resumo
      else if (agora - p.em > 24 * 3600_000) candidatos.push({ id, prio: 1 }); // ativo, resumo com mais de 1 dia
    }
    candidatos.sort((a, b) => a.prio - b.prio || (ultimo.get(b.id)! - ultimo.get(a.id)!));
    alvos = candidatos.slice(0, MAX_POR_VOLTA).map((c) => c.id);
  }

  const resultados: Json[] = [];
  let custoTotal = 0;
  for (const uid of alvos) {
    try {
      const { data: atual } = await db.from('assistant_client_profile').select('*').eq('user_id', uid).maybeSingle();
      if (atual && atual.lembrar === false) { resultados.push({ user_id: uid, saltado: 'nao_lembrar' }); continue; }
      const { data: factos, error: fe } = await db.rpc('assistant_amigo_factos', { p_user_id: uid });
      if (fe) { resultados.push({ user_id: uid, erro: fe.message }); continue; }
      const desde = atual?.esquecido_em ?? '1970-01-01T00:00:00Z';
      const { data: memorias } = await db.from('assistant_client_memory').select('kind, key, value, updated_at')
        .eq('user_id', uid).gte('updated_at', desde).limit(40);

      // Conversa: só mensagens novas (desde msgs_lidas_ate) e só se houver pelo menos 3.
      const lidasAte = atual?.msgs_lidas_ate ?? desde;
      const { data: novas } = await db.from('assistant_chat_messages').select('content, created_at')
        .eq('user_id', uid).eq('role', 'user').gt('created_at', lidasAte)
        .order('created_at', { ascending: false }).limit(40);
      let conversa: Json | null = null;
      let modelo: string | null = null;
      let custo = 0;
      let novoLidasAte = lidasAte;
      if ((novas ?? []).length >= MIN_MSGS_NOVAS) {
        const texto = (novas as Json[]).slice().reverse().map((n) => `- ${limpa(n.content, 300)}`).join('\n').slice(0, 6000);
        const r = await claudePrimeiro({
          robo: 'edge-amigo-perfil', prioridade: 3, modelo: 'claude-haiku-5-5', system: [PERFIL_SYS],
          messages: [{ role: 'user', content: `Mensagens do cliente (mais antigas primeiro):\n${texto}` }], maxTokens: 400,
        });
        if (r) {
          try { conversa = extrairJson(r.texto); } catch { conversa = null; }
          modelo = r.modelo; custo = r.custoUsd; custoTotal += r.custoUsd;
        }
        novoLidasAte = (novas as Json[])[0]?.created_at ?? lidasAte; // a mais recente
      }
      const perfil = montarPerfil(factos, memorias ?? [], conversa, atual?.perfil ?? {});
      if (!dryRun) {
        const { error: ue } = await db.from('assistant_client_profile').upsert({
          user_id: uid, perfil, msgs_lidas_ate: novoLidasAte,
          fonte: conversa ? 'factos+memoria+conversa' : 'factos+memoria',
          modelo, custo_usd: Number(atual?.custo_usd ?? 0) + custo, atualizado_em: new Date().toISOString(),
        }, { onConflict: 'user_id' });
        if (ue) { resultados.push({ user_id: uid, erro: ue.message }); continue; }
      }
      resultados.push({
        user_id: uid, habitos: (perfil.habitos ?? []).length, lojas: (perfil.lojas_favoritas ?? []).length,
        conversa: Boolean(conversa), custo_usd: Number(custo.toFixed(6)), ...(dryRun ? { perfil } : {}),
      });
    } catch (e) {
      resultados.push({ user_id: uid, erro: (e as Error).message });
    }
  }

  console.log(`[amigo-perfis] alvos=${alvos.length} custo=${custoTotal.toFixed(5)} dry=${dryRun}`);
  return resposta({ ok: true, alvos: alvos.length, custo_usd: Number(custoTotal.toFixed(6)), dry_run: dryRun, resultados });
});
