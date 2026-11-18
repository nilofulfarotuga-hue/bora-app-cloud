// robo-a3-catalogo — missão a3-guarda-16-11, parte 2 (pontos 1, 4 e 6 da caixa 114).
//
// Três trabalhos, só no servidor (nunca no PC):
//  1. FOTOS ("acao":"fotos"): copia para o nosso Storage (product-images/lojas/a3-guarda/) as fotos
//     dos produtos da A3 que ainda apontam para a3guarda.com e troca a photo_url. Em lotes, com
//     pausa entre pedidos; chama-se outra vez até "faltam": 0.
//  2. LOGÓTIPO E CAPA ("acao":"imagens-loja", "logo_url", "capa_url"): copia as duas imagens para
//     restaurant-assets/a3-guarda/ e põe restaurants.photo_url / cover_url.
//  3. ROBÔ DIÁRIO (sem "acao"): continua a corrida a_correr em robo_a3_corridas. Lê a loja online
//     da A3 (um pedido JSON com a lista toda), aplica PREÇO e ESGOTADO sem pisar o que foi mudado à
//     mão na Bora, mete os produtos novos com a foto já copiada e acaba as fotos que faltem.
//     O pg_cron arranca às 07:00 de Lisboa e chama de minuto a minuto até acabar; o "Atualizar
//     agora" do painel também.
//
// Regras: regras.ts (com testes). Molde: robo-glovo-farmacias (16/11).
// Só o servidor (service role) pode chamar.

import { createClient, type SupabaseClient } from 'jsr:@supabase/supabase-js@2'
import {
  decidir,
  type Estado,
  fotoDeFora,
  type Lido,
  lerProduto,
  PREFIXO,
  precoCliente,
  type Produto,
  seccaoNova,
  tipoImagem,
} from './regras.ts'

const LOJA = 'a3-guarda'
const LISTA_URL = 'https://a3guarda.com/loja/index.php?id_category=2&controller=category&resultsPerPage=9999'
const UA = 'Mozilla/5.0 (compatible; BoraGuardaBot/1.0; +https://boraguarda.com)'
const ORCAMENTO_MS = 95_000 // a Edge tem 150 s
const PAUSA_MS = 250 // educado com o site da A3
const COBERTURA_MIN = 0.8 // abaixo disto não muda nada
const COBERTURA_SUMIU = 0.98 // abaixo disto não tira de venda o que faltar na leitura
const MAX_NOVOS = 60 // mais do que isto de uma vez = algo mudou na loja online; avisa e não insere
const BUCKET_PROD = 'product-images'
const BUCKET_LOJA = 'restaurant-assets'

const json = (b: unknown, s = 200) =>
  new Response(JSON.stringify(b), { status: s, headers: { 'Content-Type': 'application/json' } })
const dorme = (ms: number) => new Promise((r) => setTimeout(r, ms))

async function todos<T>(sb: SupabaseClient, tabela: string, colunas: string, filtro: [string, string]): Promise<T[]> {
  const out: T[] = []
  const ordem = tabela === 'products' ? 'id' : 'product_id'
  for (let de = 0; ; de += 1000) {
    const { data, error } = await sb.from(tabela).select(colunas).eq(filtro[0], filtro[1]).order(ordem).range(de, de + 999)
    if (error) throw new Error(`${tabela}: ${error.message}`)
    out.push(...((data ?? []) as T[]))
    if (!data || data.length < 1000) break
  }
  return out
}

async function avisar(sb: SupabaseClient, texto: string) {
  const { error } = await sb.rpc('robo_a3_avisar', { p_texto: texto })
  if (error) console.error('aviso telegram falhou:', error.message)
}

async function gravar(sb: SupabaseClient, id: number, campos: Record<string, unknown>) {
  const { error } = await sb.from('robo_a3_corridas').update(campos).eq('id', id)
  if (error) throw new Error('gravar corrida: ' + error.message)
}

/** Descarrega uma imagem e guarda-a no Storage. Devolve o endereço público ou o motivo da falha. */
async function copiarImagem(sb: SupabaseClient, origem: string, bucket: string, caminhoSemExt: string): Promise<{ url?: string; erro?: string }> {
  try {
    const r = await fetch(origem, { headers: { 'User-Agent': UA } })
    const buf = new Uint8Array(await r.arrayBuffer())
    const tipo = r.status === 200 ? tipoImagem(buf) : null
    if (!tipo) return { erro: `imagem ilegível (HTTP ${r.status})` }
    if (buf.length < 1500) return { erro: 'imagem pequena demais (marcador?)' }
    const caminho = `${caminhoSemExt}.${tipo.ext}`
    const up = await sb.storage.from(bucket).upload(caminho, buf, { contentType: tipo.type, upsert: true, cacheControl: '31536000' })
    if (up.error) return { erro: 'upload falhou: ' + up.error.message }
    return { url: sb.storage.from(bucket).getPublicUrl(caminho).data.publicUrl }
  } catch (e) {
    return { erro: String(e).slice(0, 160) }
  }
}

/** Trabalho 1: copia fotos de produtos que ainda apontam para a3guarda.com. */
async function copiarFotos(sb: SupabaseClient, t0: number, maximo = 10_000) {
  const { data, error } = await sb
    .from('products')
    .select('id,photo_url')
    .eq('restaurant_id', LOJA)
    .ilike('photo_url', '%a3guarda.com%')
    .order('id')
    .limit(Math.min(maximo, 400))
  if (error) throw new Error('ler fotos: ' + error.message)
  let copiadas = 0
  const falhas: { id: string; erro: string }[] = []
  for (const p of data ?? []) {
    if (Date.now() - t0 > ORCAMENTO_MS) break
    if (!fotoDeFora(p.photo_url)) continue
    const r = await copiarImagem(sb, p.photo_url, BUCKET_PROD, `lojas/${LOJA}/${p.id}`)
    if (r.url) {
      // só troca se ninguém mudou a foto entretanto
      const { error: e2 } = await sb
        .from('products')
        .update({ photo_url: r.url, image_source: `a3guarda.com (loja online da A3, copiada para o Storage): ${p.photo_url}` })
        .eq('id', p.id)
        .eq('photo_url', p.photo_url)
      if (e2) falhas.push({ id: p.id, erro: 'gravar: ' + e2.message })
      else copiadas++
    } else falhas.push({ id: p.id, erro: r.erro ?? '?' })
    await dorme(PAUSA_MS)
  }
  const { count } = await sb
    .from('products')
    .select('id', { count: 'exact', head: true })
    .eq('restaurant_id', LOJA)
    .ilike('photo_url', '%a3guarda.com%')
  return { copiadas, falhas: falhas.length, exemplos_falhas: falhas.slice(0, 10), faltam: count ?? null }
}

/** Trabalho 2: logótipo e capa da loja. */
async function imagensLoja(sb: SupabaseClient, corpo: Record<string, unknown>) {
  const out: Record<string, unknown> = {}
  const upd: Record<string, unknown> = {}
  for (const [chave, coluna, nome] of [['logo_url', 'photo_url', 'logo'], ['capa_url', 'cover_url', 'capa']] as const) {
    const origem = corpo[chave]
    if (typeof origem !== 'string' || !/^https:\/\//.test(origem)) continue
    const r = await copiarImagem(sb, origem, BUCKET_LOJA, `${LOJA}/${nome}`)
    out[nome] = r
    if (r.url) upd[coluna] = r.url + '?v=' + Date.now()
  }
  if (Object.keys(upd).length) {
    const { error } = await sb.from('restaurants').update(upd).eq('id', LOJA)
    if (error) out.erro_gravar = error.message
    else out.gravado = upd
  }
  return out
}

/** Lê a lista inteira da loja online (um pedido). */
async function lerLoja(): Promise<Record<string, Lido>> {
  const r = await fetch(LISTA_URL, {
    headers: { Accept: 'application/json', 'X-Requested-With': 'XMLHttpRequest', 'User-Agent': UA },
  })
  if (r.status !== 200) throw new Error(`loja online respondeu HTTP ${r.status}`)
  const j = await r.json()
  const lista = Array.isArray(j?.products) ? j.products : []
  const out: Record<string, Lido> = {}
  for (const p of lista) {
    const l = lerProduto(p)
    if (l) out[l.id] = l
  }
  return out
}

async function passo(sb: SupabaseClient, c: any, t0: number) {
  const prog = (c.progresso ?? {}) as { lidos?: Record<string, Lido>; aplicado?: boolean; novos_feitos?: boolean }
  const { data: cfg } = await sb.from('robo_a3_config').select('*').eq('id', 1).single()
  const fator = Number(cfg?.fator_preco ?? 1.15)

  // 1) ler
  if (!prog.lidos) {
    prog.lidos = await lerLoja()
    await gravar(sb, c.id, { progresso: prog, lidos: Object.keys(prog.lidos).length })
  }
  const lidos = prog.lidos

  // 2) aplicar preço e esgotado
  if (!prog.aplicado) {
    const db = await todos<Produto & { category: string }>(sb, 'products', 'id,name,price,partner_shelf_price,is_available,photo_url,category', ['restaurant_id', LOJA])
    const est = await todos<Estado>(sb, 'robo_a3_estado', '*', ['loja', LOJA])
    const estMap = new Map(est.map((e) => [e.product_id, e]))
    const nossos = db.filter((p) => p.id.startsWith(PREFIXO))
    const conhecidos = nossos.filter((p) => !estMap.get(p.id)?.ignorar)
    const vistos = conhecidos.filter((p) => lidos[p.id.slice(PREFIXO.length)])
    const cobertura = conhecidos.length ? vistos.length / conhecidos.length : 1
    if (cobertura < COBERTURA_MIN) {
      await gravar(sb, c.id, { estado: 'abortada', cobertura, conhecidos: conhecidos.length, terminada_em: new Date().toISOString(), lock_ate: null, erro: `leitura incompleta: ${vistos.length} de ${conhecidos.length}` })
      await avisar(sb, `⚠️ Robô da A3 Guarda: a loja online só mostrou ${vistos.length} de ${conhecidos.length} produtos conhecidos. Não mudei nada. Ver no painel (Lojas › Robô A3).`)
      return { abortada: true, cobertura }
    }
    const agora = new Date().toISOString()
    // Tirar de venda o que "desapareceu" só com a leitura quase completa (uma lista cortada a 85%
    // não pode esconder 270 produtos de uma vez). Entre 80% e 98% muda preço e esgotado, mais nada.
    const leituraCompleta = cobertura >= COBERTURA_SUMIU
    // Contagens: as de mudanças somam entre chamadas (a corrida pode ir em várias); mão e suspeitos recontam-se.
    const contas = {
      mudou_preco: c.mudou_preco ?? 0, esgotou: c.esgotou ?? 0, voltou: c.voltou ?? 0, desapareceu: c.desapareceu ?? 0,
      mao: 0, suspeitos: 0,
    }
    const exemplos: Record<string, unknown>[] = Array.isArray(c.exemplos) ? c.exemplos : []
    const semMudanca: Estado[] = []
    const comMudanca: { p: Produto & { category: string }; d: ReturnType<typeof decidir> }[] = []
    for (const p of nossos) {
      const l = lidos[p.id.slice(PREFIXO.length)] ?? null
      const d = decidir(p, estMap.get(p.id), l, leituraCompleta, fator, agora)
      if (d.maoPreco || d.maoDisp) contas.mao++
      if (d.suspeito) {
        contas.suspeitos++
        if (exemplos.length < 30) exemplos.push({ id: p.id, nome: p.name, suspeito: true, balcao: p.partner_shelf_price, a3: l?.preco })
      }
      if (Object.keys(d.upd).length) comMudanca.push({ p, d })
      else semMudanca.push({ ...d.estado, loja: LOJA } as Estado)
    }
    // estado dos que não mudam (é o mesmo valor da base: não cria "mão humana" falsa)
    for (let i = 0; i < semMudanca.length; i += 500) {
      const { error } = await sb.from('robo_a3_estado').upsert(semMudanca.slice(i, i + 500), { onConflict: 'product_id' })
      if (error) throw new Error('gravar estado: ' + error.message)
    }
    // cada mudança grava logo o seu estado: se a chamada morrer a meio, a seguinte recomeça
    // da base e não confunde o que o robô já mudou com uma mudança à mão
    let acabou = true
    for (const { p, d } of comMudanca) {
      if (Date.now() - t0 > ORCAMENTO_MS) { acabou = false; break }
      const { error } = await sb.from('products').update({ ...d.upd, last_updated: agora.slice(0, 10) }).eq('id', p.id)
      if (error) throw new Error(`atualizar ${p.id}: ${error.message}`)
      const { error: e2 } = await sb.from('robo_a3_estado').upsert({ ...d.estado, loja: LOJA }, { onConflict: 'product_id' })
      if (e2) throw new Error(`gravar estado ${p.id}: ${e2.message}`)
      if (d.conta === 'preco') contas.mudou_preco++
      else if (d.conta) contas[d.conta]++
      if (exemplos.length < 30) exemplos.push({ id: p.id, nome: p.name, ...d.upd })
    }
    prog.aplicado = acabou
    await gravar(sb, c.id, { progresso: prog, cobertura, conhecidos: conhecidos.length, ...contas, exemplos })
    if (!acabou) return { continua: 'aplicar', ...contas }
    if (contas.suspeitos) await avisar(sb, `Robô da A3 Guarda: ${contas.suspeitos} preço(s) com salto acima de 50% não foram aplicados. Ver no painel (Lojas › Robô A3).`)
  }

  // 3) produtos novos (com foto já no Storage; nunca produto sem foto)
  let novos = c.novos ?? 0
  if (!prog.novos_feitos) {
    const db = await todos<{ id: string; category: string }>(sb, 'products', 'id,category', ['restaurant_id', LOJA])
    const est = await todos<Estado>(sb, 'robo_a3_estado', 'product_id,ignorar', ['loja', LOJA])
    const existentes = new Set(db.map((p) => p.id))
    const ignorados = new Set(est.filter((e) => e.ignorar).map((e) => e.product_id))
    const seccoes = new Set(db.map((p) => p.category))
    const porFazer = Object.values(lidos).filter((l) => !existentes.has(PREFIXO + l.id) && !ignorados.has(PREFIXO + l.id))
    if (porFazer.length > MAX_NOVOS && novos === 0) {
      await avisar(sb, `⚠️ Robô da A3 Guarda: a loja online tem ${porFazer.length} produtos novos de uma vez (limite ${MAX_NOVOS}). Não meti nenhum; ver no painel.`)
      prog.novos_feitos = true
    } else {
      for (const l of porFazer) {
        if (Date.now() - t0 > ORCAMENTO_MS) break
        const id = PREFIXO + l.id
        const ignorar = (motivo: string) =>
          sb.from('robo_a3_estado').upsert({ product_id: id, loja: LOJA, ext_id: l.id, ultimo_balcao_robo: l.preco, ultimo_disp_robo: false, ignorar: true, motivo_ignorar: motivo }, { onConflict: 'product_id' })
        if (!l.foto) { await ignorar('sem foto na loja online'); continue }
        const r = await copiarImagem(sb, l.foto, BUCKET_PROD, `lojas/${LOJA}/${id}`)
        await dorme(PAUSA_MS)
        if (!r.url) { await ignorar('foto falhou: ' + r.erro); continue }
        const vende = !l.esgotado && !!l.preco
        const desc = [l.marca ? `Marca: ${l.marca}` : '', l.ref ? `Referência: ${l.ref}` : ''].filter(Boolean).join('\n\n')
        const { error } = await sb.from('products').insert({
          id,
          restaurant_id: LOJA,
          name: l.nome,
          description: desc || null,
          photo_url: r.url,
          image_source: `a3guarda.com (loja online da A3, copiada para o Storage): ${l.foto}`,
          price: l.preco ? precoCliente(l.preco, fator) : 0,
          partner_shelf_price: l.preco ?? 0,
          is_available: vende,
          category: seccaoNova(l, seccoes),
          taxonomy_section: 'Outros', // explícito: não criar linhas novas em category_mapping (achado 16/11)
          source: 'a3-loja-online-robo',
          last_updated: new Date().toISOString().slice(0, 10),
          sort_order: 900000 + Number(l.id),
          needs_photo: false,
        })
        if (error) { await ignorar('inserir falhou: ' + error.message); continue }
        await sb.from('robo_a3_estado').upsert({ product_id: id, loja: LOJA, ext_id: l.id, ultimo_balcao_robo: l.preco ?? 0, ultimo_disp_robo: vende, ultima_vez_visto: new Date().toISOString() }, { onConflict: 'product_id' })
        novos++
      }
      if (Date.now() - t0 <= ORCAMENTO_MS) prog.novos_feitos = true
    }
    await gravar(sb, c.id, { progresso: prog, novos })
    if (!prog.novos_feitos) return { continua: 'novos', novos }
  }

  // 4) fotos que ainda estejam fora
  const f = await copiarFotos(sb, t0)
  const fotos = (c.fotos_copiadas ?? 0) + f.copiadas
  if (f.faltam && f.faltam > 0 && f.copiadas > 0) {
    await gravar(sb, c.id, { fotos_copiadas: fotos })
    return { continua: 'fotos', ...f }
  }
  // lidos sai do progresso no fim (não guardar 1800 produtos em cada corrida antiga)
  await gravar(sb, c.id, { estado: 'ok', fotos_copiadas: fotos, fotos_falhas: f.falhas, progresso: { aplicado: true, novos_feitos: true }, terminada_em: new Date().toISOString(), lock_ate: null })
  return { terminada: true, novos, fotos_copiadas: fotos, fotos_faltam: f.faltam }
}

Deno.serve(async (req) => {
  const url = Deno.env.get('SUPABASE_URL') ?? ''
  const serviceKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? ''
  const auth = req.headers.get('Authorization') ?? ''
  if (!serviceKey || auth !== `Bearer ${serviceKey}`) return json({ erro: 'só o servidor' }, 403)
  const sb = createClient(url, serviceKey, { auth: { persistSession: false } })
  const corpo = (await req.json().catch(() => ({}))) as Record<string, unknown>
  const t0 = Date.now()

  try {
    if (corpo.acao === 'fotos') return json(await copiarFotos(sb, t0, Number(corpo.maximo ?? 400)))
    if (corpo.acao === 'imagens-loja') return json(await imagensLoja(sb, corpo))
  } catch (e) {
    return json({ erro: String(e instanceof Error ? e.message : e).slice(0, 400) }, 500)
  }

  const { data: linhas, error } = await sb.from('robo_a3_corridas').select('*').eq('estado', 'a_correr').order('id').limit(1)
  if (error) return json({ erro: error.message }, 500)
  const c = linhas?.[0]
  if (!c) return json({ nada: 'sem corridas por fazer' })

  const agora = new Date().toISOString()
  const { data: tranca } = await sb
    .from('robo_a3_corridas')
    .update({ lock_ate: new Date(Date.now() + 170_000).toISOString() })
    .eq('id', c.id)
    .or(`lock_ate.is.null,lock_ate.lt."${agora}"`)
    .select('id')
  if (!tranca?.length) return json({ ocupada: c.id })

  try {
    const r = await passo(sb, c, t0)
    if (!('terminada' in r) && !('abortada' in r)) await gravar(sb, c.id, { lock_ate: null })
    return json({ corrida: c.id, ...r })
  } catch (e) {
    const msg = String(e instanceof Error ? e.message : e).slice(0, 400)
    await gravar(sb, c.id, { estado: 'erro', erro: msg, terminada_em: new Date().toISOString(), lock_ate: null }).catch(() => {})
    await avisar(sb, `⚠️ Robô da A3 Guarda: parou com erro. ${msg.slice(0, 200)}`)
    return json({ corrida: c.id, erro: msg }, 500)
  }
})
