// @ts-nocheck
// supabase/functions/resumo-avaliacoes/index.ts  v1  2026-10-29
//
// Adendo 4, item 8 (missão final-app-2026-10-29): resumo, escrito por IA, do que os clientes
// dizem nas avaliações de uma loja. Aparece SÓ no painel do parceiro (e no do admin).
//
// Quem chama: utilizador com sessão que é (a) admin ou (b) o dono da loja. Nunca um cliente.
// Com o interruptor platform_settings.feature_resumo_avaliacoes_ia desligado devolve
// { ok:false, reason:'desligado' }.
//
// Corpo: { restaurant_id, forcar? }
//
// IA (10/11/2026, fechar-tudo bloco H): o Gemini do projeto bora-juiz saiu (conta de pagamento vencida,
// 402). Agora _shared/ia_visao.ts: Claude primeiro (robo 'edge-resumo-avaliacoes', Haiku); comentários de
// clientes → privado=true: de reserva só motores que não treinam com os dados (Groq). Sem motor:
// { ok:false, reason:'gemini_erro', detalhe:<erro claro> } (o nome do motivo fica, a app já o conhece).
// O resumo é guardado em restaurant_review_summary (só o dono e o admin leem). Faz-se no máximo
// uma vez por dia por loja, e só se houver pelo menos 3 comentários; os nomes dos clientes nunca
// entram (a consulta nem os lê).

import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'
import { pedirIa } from '../_shared/ia_visao.ts'

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
  'Access-Control-Allow-Methods': 'POST, OPTIONS',
}

const MIN_COMENTARIOS = 3
const MAX_COMENTARIOS = 60
const UM_DIA_MS = 24 * 60 * 60 * 1000

const json = (body: unknown, status = 200) =>
  new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, 'Content-Type': 'application/json' },
  })

const PROMPT =
  'Tu resumes avaliações de clientes de um restaurante ou loja em português de Portugal. ' +
  'Recebes uma lista de avaliações (estrelas e comentário). Escreve, para o DONO da loja, um resumo ' +
  'curto e honesto em texto corrido (no máximo 4 frases): o que os clientes mais elogiam e o que mais ' +
  'criticam, com o que se repete. Regras: não inventes nada que não esteja nos comentários; não ' +
  'cites nomes de pessoas nem dados pessoais; não prometas nada; sem listas, sem emojis, sem markdown. ' +
  'Devolve JSON ESTRITO: {"resumo": "..."}.'

async function pedirResumo(linhas: string[]) {
  const r = await pedirIa({
    robo: 'edge-resumo-avaliacoes',
    prioridade: 3,
    sistema: PROMPT,
    texto: linhas.join('\n'),
    json: true,
    privado: true,
    maxTokens: 1024,
  })
  if (!r.ok) return { erro: r.erro.slice(0, 300), resumo: null as string | null }
  // deno-lint-ignore no-explicit-any
  const resumo = String((r.json as any)?.resumo ?? '').trim().slice(0, 900)
  return { erro: resumo ? null : 'vazio', resumo: resumo || null }
}

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: corsHeaders })
  if (req.method !== 'POST') return json({ ok: false, error: 'metodo' }, 405)

  const url = Deno.env.get('SUPABASE_URL')!
  const anon = Deno.env.get('SUPABASE_ANON_KEY')!
  const servico = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? Deno.env.get('SUPABASE_SECRET_KEY')
  if (!url || !anon || !servico) return json({ ok: false, error: 'env_em_falta' }, 500)

  const auth = req.headers.get('Authorization') ?? ''
  const comoUtilizador = createClient(url, anon, { global: { headers: { Authorization: auth } } })
  const { data: dadosUser, error: erroUser } = await comoUtilizador.auth.getUser()
  if (erroUser || !dadosUser?.user) return json({ ok: false, error: 'sem_sessao' }, 401)
  const uid = dadosUser.user.id

  let corpo: any
  try {
    corpo = await req.json()
  } catch {
    return json({ ok: false, error: 'json_invalido' }, 400)
  }
  const lojaId = typeof corpo?.restaurant_id === 'string' ? corpo.restaurant_id : null
  if (!lojaId) return json({ ok: false, error: 'falta_restaurant_id' }, 400)
  const forcar = corpo?.forcar === true

  const bd = createClient(url, servico, { auth: { persistSession: false } })

  const { data: cfg } = await bd.from('platform_settings').select('value')
    .eq('key', 'feature_resumo_avaliacoes_ia').maybeSingle()
  if (cfg?.value !== true && cfg?.value !== 'true') return json({ ok: false, reason: 'desligado' })

  // Permissão: admin ou dono da loja.
  const { data: souAdmin } = await comoUtilizador.rpc('is_admin')
  if (souAdmin !== true) {
    const { data: loja } = await bd.from('restaurants').select('id').eq('id', lojaId).eq('user_', uid).maybeSingle()
    if (!loja) return json({ ok: false, error: 'nao_e_a_tua_loja' }, 403)
  }

  // As avaliações públicas com comentário (a consulta não lê quem avaliou).
  const { data: avaliacoes, error: erroLer } = await bd.from('ratings')
    .select('stars, rating, comment, created_at')
    .eq('subject_type', 'partner').eq('subject_id', lojaId)
    .not('comment', 'is', null)
    .or('flagged_inappropriate.is.null,flagged_inappropriate.eq.false')
    .order('created_at', { ascending: false })
    .limit(MAX_COMENTARIOS)
  if (erroLer) return json({ ok: false, error: 'ler_avaliacoes' }, 500)
  const comTexto = (avaliacoes ?? []).filter((a) => String(a.comment ?? '').trim().length >= 3)
  if (comTexto.length < MIN_COMENTARIOS) {
    return json({ ok: false, reason: 'poucos_comentarios', comentarios: comTexto.length, minimo: MIN_COMENTARIOS })
  }

  // No máximo um resumo por dia, a não ser que mudem as avaliações ou se force.
  const { data: antigo } = await bd.from('restaurant_review_summary')
    .select('summary, ratings_count, generated_at').eq('restaurant_id', lojaId).maybeSingle()
  if (antigo && !forcar) {
    const idade = Date.now() - new Date(antigo.generated_at).getTime()
    if (idade < UM_DIA_MS && antigo.ratings_count === comTexto.length) {
      return json({ ok: true, resumo: antigo.summary, ratings_count: antigo.ratings_count, da_cache: true })
    }
  }

  const linhas = comTexto.map((a) => {
    const estrelas = Number(a.stars ?? a.rating ?? 0)
    return `${estrelas > 0 ? estrelas + ' estrelas' : 'sem estrelas'}: ${String(a.comment).trim().slice(0, 400)}`
  })
  const r = await pedirResumo(linhas)
  if (r.erro || !r.resumo) return json({ ok: false, reason: 'gemini_erro', detalhe: r.erro })

  const { error: erroGravar } = await bd.from('restaurant_review_summary').upsert({
    restaurant_id: lojaId,
    summary: r.resumo,
    ratings_count: comTexto.length,
    generated_at: new Date().toISOString(),
  })
  if (erroGravar) return json({ ok: false, error: 'gravar' }, 500)
  return json({ ok: true, resumo: r.resumo, ratings_count: comTexto.length, da_cache: false })
})
