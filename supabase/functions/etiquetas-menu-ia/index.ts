// @ts-nocheck
// supabase/functions/etiquetas-menu-ia/index.ts  v1  2026-10-29
//
// Adendo 4, item 5 (missão final-app-2026-10-29): etiquetas do menu (vegetariano, picante,
// sem glúten) sugeridas por IA a partir da DESCRIÇÃO do prato. O parceiro corrige no ecrã dos
// produtos; o que o parceiro escolhe nunca é substituído pela IA.
//
// Quem chama: um utilizador com sessão que é (a) admin, ou (b) o dono da loja do produto.
// Nunca um cliente, nunca ninguém sem sessão. Com o interruptor
// platform_settings.feature_etiquetas_menu_ia desligado devolve { ok:false, reason:'desligado' }.
//
// Corpo: { product_id }                       -> um prato (botão "Sugerir com IA")
//        { restaurant_id, limite? (<=20) }    -> os pratos dessa loja ainda sem etiquetas
//
// Gemini: chave PAGA (GEMINI_API_KEY, a do projeto bora-juiz, nível 1). NUNCA a
// GEMINI_API_KEY_FALLBACK, que pode ser grátis. Sem a chave: ok:false, gemini_nao_configurado.
// Modelo gemini-3.1-flash-lite com thinkingBudget 0 (armadilha conhecida do flash), temperatura 0.
//
// Escreve em products.diet_tags / diet_tags_source = 'ia' / diet_tags_at, e só em pratos cuja
// origem das etiquetas é nula ou 'ia'. Não toca em preços, nem em alergénios.

import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
  'Access-Control-Allow-Methods': 'POST, OPTIONS',
}

const PERMITIDAS = ['vegetariano', 'picante', 'sem_gluten']
const MODELO = 'gemini-3.1-flash-lite'
const LIMITE_MAXIMO = 20

const json = (body: unknown, status = 200) =>
  new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, 'Content-Type': 'application/json' },
  })

/** Só as etiquetas permitidas, sem repetidas, por ordem fixa. */
export function limparEtiquetas(bruto: unknown): string[] {
  if (!Array.isArray(bruto)) return []
  const vistas = new Set(
    bruto.map((t) => String(t).trim().toLowerCase().replace(/[\s-]+/g, '_')),
  )
  return PERMITIDAS.filter((t) => vistas.has(t))
}

const PROMPT =
  'Tu classificas pratos de um menu de restaurante em português. Recebes o nome e a descrição ' +
  'de um prato e devolves JSON ESTRITO (sem markdown, sem prosa) com este formato: ' +
  '{"tags": ["vegetariano"|"picante"|"sem_gluten", ...]}. Regras: ' +
  '"vegetariano" só se a descrição ou o nome mostram que NÃO leva carne nem peixe ' +
  '(ovos e laticínios podem levar). ' +
  '"picante" só se a descrição diz que é picante/apimentado/com piri-piri/malagueta/jalapeño. ' +
  '"sem_gluten" SÓ se a descrição diz EXPRESSAMENTE "sem glúten" ou "gluten free"; ' +
  'nunca deduzas sem glúten pelos ingredientes (é segurança alimentar). ' +
  'Na dúvida, não ponhas a etiqueta. Se não houver nenhuma, devolve {"tags": []}.'

async function pedirAoGemini(chave: string, nome: string, descricao: string) {
  const r = await fetch(
    `https://generativelanguage.googleapis.com/v1beta/models/${MODELO}:generateContent`,
    {
      method: 'POST',
      headers: { 'Content-Type': 'application/json', 'x-goog-api-key': chave },
      body: JSON.stringify({
        contents: [{
          parts: [
            { text: PROMPT },
            { text: `Nome: ${nome.slice(0, 200)}\nDescrição: ${descricao.slice(0, 800)}` },
          ],
        }],
        generationConfig: {
          temperature: 0,
          response_mime_type: 'application/json',
          maxOutputTokens: 200,
          thinkingConfig: { thinkingBudget: 0 },
        },
      }),
    },
  )
  if (!r.ok) return { erro: r.status, tags: [] as string[] }
  const raw = await r.json().catch(() => ({}))
  const texto = raw?.candidates?.[0]?.content?.parts?.[0]?.text ?? '{}'
  try {
    return { erro: null, tags: limparEtiquetas(JSON.parse(texto)?.tags) }
  } catch {
    return { erro: 'json_invalido', tags: [] as string[] }
  }
}

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: corsHeaders })
  if (req.method !== 'POST') return json({ ok: false, error: 'metodo' }, 405)

  const url = Deno.env.get('SUPABASE_URL')!
  const anon = Deno.env.get('SUPABASE_ANON_KEY')!
  const servico = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? Deno.env.get('SUPABASE_SECRET_KEY')
  const chaveGemini = Deno.env.get('GEMINI_API_KEY')
  if (!url || !anon || !servico) return json({ ok: false, error: 'env_em_falta' }, 500)

  // 1) Quem é: sessão obrigatória.
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
  const produtoId = typeof corpo?.product_id === 'string' ? corpo.product_id : null
  const lojaId = typeof corpo?.restaurant_id === 'string' ? corpo.restaurant_id : null
  if (!produtoId && !lojaId) return json({ ok: false, error: 'falta_product_id_ou_restaurant_id' }, 400)

  const bd = createClient(url, servico, { auth: { persistSession: false } })

  // 2) Interruptor do painel.
  const { data: cfg } = await bd.from('platform_settings').select('value')
    .eq('key', 'feature_etiquetas_menu_ia').maybeSingle()
  if (cfg?.value !== true && cfg?.value !== 'true') {
    return json({ ok: false, reason: 'desligado' })
  }

  // 3) Quais pratos, e de que loja.
  let pratos: any[] = []
  if (produtoId) {
    const { data } = await bd.from('products')
      .select('id, name, description, restaurant_id, diet_tags_source')
      .eq('id', produtoId).maybeSingle()
    if (!data) return json({ ok: false, error: 'produto_nao_existe' }, 404)
    pratos = [data]
  } else {
    const limite = Math.max(1, Math.min(Number(corpo?.limite ?? LIMITE_MAXIMO) || LIMITE_MAXIMO, LIMITE_MAXIMO))
    const { data } = await bd.from('products')
      .select('id, name, description, restaurant_id, diet_tags_source')
      .eq('restaurant_id', lojaId)
      .is('diet_tags_source', null)
      .eq('is_available', true)
      .not('description', 'is', null)
      .limit(limite)
    pratos = data ?? []
  }
  if (pratos.length === 0) return json({ ok: true, atualizados: 0, resultados: [] })

  // 4) Permissão: admin, ou dono de TODAS as lojas envolvidas.
  const lojas = [...new Set(pratos.map((p) => p.restaurant_id))]
  const { data: souAdmin } = await comoUtilizador.rpc('is_admin')
  if (souAdmin !== true) {
    const { data: minhas } = await bd.from('restaurants').select('id').in('id', lojas).eq('user_', uid)
    const meus = new Set((minhas ?? []).map((l) => l.id))
    if (!lojas.every((l) => meus.has(l))) return json({ ok: false, error: 'nao_e_a_tua_loja' }, 403)
  }

  if (!chaveGemini) return json({ ok: false, reason: 'gemini_nao_configurado' })

  // 5) Pergunta ao Gemini e grava (nunca por cima do que o parceiro escolheu).
  const resultados: any[] = []
  let atualizados = 0
  for (const p of pratos) {
    if (p.diet_tags_source === 'parceiro') {
      resultados.push({ product_id: p.id, tags: null, saltado: 'escolhido_pelo_parceiro' })
      continue
    }
    const descricao = String(p.description ?? '').trim()
    if (descricao.length < 5) {
      resultados.push({ product_id: p.id, tags: [], saltado: 'sem_descricao' })
      continue
    }
    const r = await pedirAoGemini(chaveGemini, String(p.name ?? ''), descricao)
    if (r.erro) {
      resultados.push({ product_id: p.id, tags: null, erro: r.erro })
      continue
    }
    const { error } = await bd.from('products').update({
      diet_tags: r.tags,
      diet_tags_source: 'ia',
      diet_tags_at: new Date().toISOString(),
    }).eq('id', p.id).or('diet_tags_source.is.null,diet_tags_source.eq.ia')
    if (error) {
      resultados.push({ product_id: p.id, tags: null, erro: 'gravar' })
      continue
    }
    atualizados++
    resultados.push({ product_id: p.id, tags: r.tags })
  }
  return json({ ok: true, atualizados, resultados })
})
