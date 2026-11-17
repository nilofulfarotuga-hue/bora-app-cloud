// robo-glovo-farmacias — missão noite-farmacia-17-11 (1.1), prometido à farmácia.
//
// Lê as lojas da Glovo da Farmácia da Sé (461279) e da Farmácia Teixeira (461596) e copia
// para a Bora o PREÇO e o ESGOTADO. Corre só no servidor: o pg_cron chama esta função
// (07:30 e 14:00, hora de Lisboa) e o "Atualizar agora" do painel também.
//
// A Glovo devolve 429 com mais de ~1 pedido/s, por isso a leitura vai em fatias de ~100 s:
// cada chamada lê um bocado, grava o progresso em robo_glovo_corridas.progresso e o
// pg_cron (robo-glovo-tick, de minuto a minuto) chama outra vez até acabar.
//
// Regras (o detalhe está em regras.ts, com testes):
// - não pisa o que a farmácia mudou à mão no painel (preço, esgotado);
// - nunca mexe em fotos de produtos que já existem (ex.: CAUDALIE VINOHYDRA corrigida à mão);
// - produto novo entra com a foto da Glovo copiada para o Storage (nunca a foto-marcador);
// - leitura com menos de 80% dos produtos conhecidos = não aplica nada e avisa no Telegram;
// - cada corrida fica registada (robo_glovo_corridas) com contagens e exemplos.
//
// Só o servidor (service role) pode chamar.

import { createClient, type SupabaseClient } from 'jsr:@supabase/supabase-js@2'
import { crypto as stdCrypto } from 'jsr:@std/crypto@1'
import { encodeHex } from 'jsr:@std/encoding@1/hex'
import {
  categoriaDe,
  decidir,
  eMedicamento,
  type Estado,
  limparNome,
  MARCADORES_MD5,
  normNome,
  tipoImagem,
} from './regras.ts'
import {
  caminhoMenu,
  glovo,
  type Item,
  lerCategoria,
  type Loja,
  LOJAS,
  montarFila,
  type Progresso,
  UA,
} from './leitura.ts'

const ORCAMENTO_MS = 95_000 // trabalho por chamada (a Edge tem 150 s)
const COBERTURA_MIN = 0.8
const MAX_NOVOS = 40 // mais do que isto de uma vez = algo mudou na Glovo; avisa e não insere
const MAX_429 = 6
const BUCKET = 'product-images'


async function todos<T>(sb: SupabaseClient, tabela: string, colunas: string, loja: string): Promise<T[]> {
  const out: T[] = []
  for (let de = 0; ; de += 1000) {
    const coluna = tabela === 'products' ? 'restaurant_id' : 'loja'
    const { data, error } = await sb.from(tabela).select(colunas).eq(coluna, loja).order(tabela === 'products' ? 'id' : 'product_id').range(de, de + 999)
    if (error) throw new Error(`${tabela}: ${error.message}`)
    out.push(...((data ?? []) as T[]))
    if (!data || data.length < 1000) break
  }
  return out
}

async function avisar(sb: SupabaseClient, texto: string) {
  const { error } = await sb.rpc('robo_glovo_avisar', { p_texto: texto })
  if (error) console.error('aviso telegram falhou:', error.message)
}

async function gravar(sb: SupabaseClient, id: number, campos: Record<string, unknown>) {
  const { error } = await sb.from('robo_glovo_corridas').update(campos).eq('id', id)
  if (error) throw new Error('gravar corrida: ' + error.message)
}

const NOME_LOJA: Record<string, string> = {
  'farmacia-se-guarda': 'Farmácia da Sé',
  'farmacia-teixeira-guarda': 'Farmácia Teixeira',
}

async function aplicar(sb: SupabaseClient, c: any, L: Loja, prog: Progresso, t0: number) {
  const lidos = prog.produtos ?? {}
  const nLidos = Object.keys(lidos).length
  const pre = L.prefix + '-'
  const db = await todos<any>(sb, 'products', 'id,name,price,is_available,category', c.loja)
  const est = await todos<Estado>(sb, 'robo_glovo_estado', '*', c.loja)
  const estMap = new Map(est.map((e) => [e.product_id, e]))
  const dbG = db.filter((p) => p.id.startsWith(pre))
  const vistos = dbG.filter((p) => lidos[p.id.slice(pre.length)])
  const conhecidos = dbG.filter((p) => !estMap.get(p.id)?.ignorar).length
  const cobertura = conhecidos ? vistos.length / conhecidos : 0
  const falhas = prog.falhas ?? []
  const base = {
    lidos: nLidos,
    conhecidos,
    cobertura: Math.round(cobertura * 1000) / 10,
    pedidos_glovo: prog.pedidos ?? 0,
    falhas: falhas.length,
  }

  if (cobertura < COBERTURA_MIN) {
    const msg = `Leitura da Glovo com ${base.cobertura}% dos produtos (mínimo 80%): ${vistos.length} de ${conhecidos}. Nada foi mudado.`
    await gravar(sb, c.id, {
      ...base,
      estado: 'abortada',
      erro: msg,
      terminada_em: new Date().toISOString(),
      lock_ate: null,
      progresso: { fase: 'feito', pedidos: prog.pedidos, falhas: falhas.slice(0, 30) },
    })
    await avisar(sb, `⚠️ Robô Glovo — ${NOME_LOJA[c.loja] ?? c.loja}: ${msg}`)
    return { abortada: true, ...base }
  }

  const agora = new Date().toISOString()
  const semFalhas = falhas.length === 0
  const updates: { id: string; upd: Record<string, unknown> }[] = []
  const estados: Estado[] = []
  const conta = { preco: 0, esgotou: 0, voltou: 0, desapareceu: 0, mao: 0, suspeitos: 0 }
  const ex = { precos: [] as any[], esgotados: [] as any[], voltaram: [] as any[], suspeitos: [] as any[], novos: [] as any[] }

  for (const p of dbG) {
    const gid = p.id.slice(pre.length)
    const g = lidos[gid] ?? null
    const d = decidir(p, estMap.get(p.id), g, semFalhas, c.loja, gid, agora)
    if (d.maoPreco || d.maoDisp) conta.mao++
    if (d.suspeito) {
      conta.suspeitos++
      if (ex.suspeitos.length < 10) ex.suspeitos.push({ id: p.id, nome: p.name, base: Number(p.price), glovo: g?.p })
    }
    if (d.precoMudou) {
      conta.preco++
      if (ex.precos.length < 5) ex.precos.push({ id: p.id, nome: p.name, de: Number(p.price), para: d.upd.price })
    }
    if (d.upd.is_available === false) {
      if (d.conta === 'desapareceu') conta.desapareceu++
      else conta.esgotou++
      if (ex.esgotados.length < 5) ex.esgotados.push({ id: p.id, nome: p.name, porque: g ? 'esgotado na Glovo' : 'saiu da Glovo' })
    }
    if (d.upd.is_available === true) {
      conta.voltou++
      if (ex.voltaram.length < 5) ex.voltaram.push({ id: p.id, nome: p.name })
    }
    if (Object.keys(d.upd).length) updates.push({ id: p.id, upd: d.upd })
    estados.push(d.estado)
  }

  // grava as mudanças (de 10 em 10)
  let erros = 0
  for (let i = 0; i < updates.length; i += 10) {
    const lote = updates.slice(i, i + 10)
    const res = await Promise.all(lote.map((u) => sb.from('products').update(u.upd).eq('id', u.id).eq('restaurant_id', c.loja)))
    for (const r of res) if (r.error) erros++
  }
  for (let i = 0; i < estados.length; i += 500) {
    const { error } = await sb.from('robo_glovo_estado').upsert(estados.slice(i, i + 500), { onConflict: 'product_id' })
    if (error) throw new Error('estado: ' + error.message)
  }

  // produtos novos
  const ids = new Set(db.map((p) => p.id))
  const nomes = new Set(db.map((p) => normNome(p.name)))
  const novos = Object.entries(lidos).filter(([gid]) => !ids.has(pre + gid) && !estMap.get(pre + gid)?.ignorar)
  let novosFeitos = 0
  let novosDeixados = 0
  const ignorar: Estado[] = []
  if (novos.length > MAX_NOVOS) {
    novosDeixados = novos.length
    await avisar(sb, `⚠️ Robô Glovo — ${NOME_LOJA[c.loja] ?? c.loja}: ${novos.length} produtos novos de uma vez (máximo ${MAX_NOVOS}). Não inseri nenhum; ver no painel.`)
  } else {
    for (const [gid, g] of novos) {
      if (Date.now() - t0 > 135_000) {
        novosDeixados++
        continue // fica para a próxima corrida
      }
      const id = pre + gid
      const nome = limparNome(g.n)
      const marca = (motivo: string) =>
        ignorar.push({ product_id: id, loja: c.loja, glovo_id: gid, ultimo_preco_robo: g.p, ultimo_disp_robo: !g.o, robo_esgotou: false, ignorar: true, motivo_ignorar: motivo, ultima_vez_visto: agora })
      if (!nome || g.p === null) { marca('sem nome ou preço na Glovo'); continue }
      if (nomes.has(normNome(nome))) { marca('mesmo nome de um produto que já existe'); continue }
      const categoria = categoriaDe(g.sc ?? '', g.c ?? '')
      if (!categoria) { marca(`categoria da Glovo desconhecida: ${g.sc} > ${g.c}`); continue }
      if (!g.img) { marca('sem foto na Glovo'); continue }
      // foto: Glovo → Storage (nunca a foto-marcador)
      let foto: string | null = null
      try {
        const r = await fetch(g.img, { headers: { 'User-Agent': UA } })
        const buf = new Uint8Array(await r.arrayBuffer())
        const tipo = r.status === 200 ? tipoImagem(buf) : null
        if (!tipo) { marca(`foto ilegível (HTTP ${r.status})`); continue }
        const md5 = encodeHex(await stdCrypto.subtle.digest('MD5', buf))
        if (MARCADORES_MD5[md5]) { marca('foto da Glovo é marcador: ' + MARCADORES_MD5[md5]); continue }
        const caminho = `farmacias/${c.loja}/${id}.${tipo.ext}`
        const up = await sb.storage.from(BUCKET).upload(caminho, buf, { contentType: tipo.type, upsert: true, cacheControl: '31536000' })
        if (up.error) { marca('upload da foto falhou: ' + up.error.message); continue }
        foto = sb.storage.from(BUCKET).getPublicUrl(caminho).data.publicUrl
      } catch (e) {
        marca('foto falhou: ' + String(e).slice(0, 120))
        continue
      }
      const linha = {
        id,
        restaurant_id: c.loja,
        name: nome,
        name_original: g.n,
        price: g.p,
        partner_shelf_price: g.p,
        category: categoria,
        photo_url: foto,
        is_available: !g.o,
        source: 'glovo-robo',
        image_source: 'glovo',
        needs_photo: false,
        requires_prescription: false,
        is_medicine: eMedicamento(g.n, g.sc ?? '', !!g.r),
        sort_order: 9999,
        last_updated: agora.slice(0, 10),
      }
      const { error } = await sb.from('products').insert(linha)
      if (error) { marca('insert falhou: ' + error.message.slice(0, 120)); continue }
      nomes.add(normNome(nome))
      novosFeitos++
      ignorar.push({ product_id: id, loja: c.loja, glovo_id: gid, ultimo_preco_robo: g.p, ultimo_disp_robo: !g.o, robo_esgotou: false, ignorar: false, motivo_ignorar: null, ultima_vez_visto: agora })
      if (ex.novos.length < 5) ex.novos.push({ id, nome, preco: g.p, categoria })
    }
  }
  if (ignorar.length) {
    const { error } = await sb.from('robo_glovo_estado').upsert(ignorar, { onConflict: 'product_id' })
    if (error) console.error('estado novos:', error.message)
  }

  const resumo = {
    ...base,
    estado: 'ok',
    mudou_preco: conta.preco,
    esgotou: conta.esgotou + conta.desapareceu,
    voltou: conta.voltou,
    novos: novosFeitos,
    mao: conta.mao,
    suspeitos: conta.suspeitos,
    erro: erros ? `${erros} produtos não gravaram` : novosDeixados ? `${novosDeixados} produtos novos ficaram para a próxima` : null,
    exemplos: { ...ex, desapareceram: conta.desapareceu, novos_ignorados: ignorar.filter((x) => x.ignorar).length },
    terminada_em: new Date().toISOString(),
    lock_ate: null,
    progresso: { fase: 'feito', pedidos: prog.pedidos, falhas: falhas.slice(0, 30) },
  }
  await gravar(sb, c.id, resumo)
  if (conta.suspeitos || erros) {
    await avisar(sb, `⚠️ Robô Glovo — ${NOME_LOJA[c.loja] ?? c.loja}: ${conta.suspeitos} preços com salto acima de 50% não aplicados, ${erros} erros a gravar. Ver no painel (Farmácias › Robô Glovo).`)
  }
  return resumo
}

async function passo(sb: SupabaseClient, c: any) {
  const L = LOJAS[c.loja]
  if (!L) throw new Error('loja desconhecida: ' + c.loja)
  const t0 = Date.now()
  const prog: Progresso = c.progresso ?? {}

  if (!prog.fase) {
    const r = await glovo(L, caminhoMenu(L))
    if (r.status === 429) {
      await gravar(sb, c.id, { lock_ate: new Date(Date.now() + 240_000).toISOString() })
      return { pausa: '429 no menu' }
    }
    if (r.status !== 200 || !r.json) throw new Error(`menu da Glovo HTTP ${r.status}: ${r.text.slice(0, 120)}`)
    const fila = montarFila(r.json)
    if (!fila.length) throw new Error('menu da Glovo sem categorias')
    Object.assign(prog, { fase: 'categorias', fila, i: 0, produtos: {}, falhas: [], pedidos: 1, r429: 0 })
  }

  if (prog.fase === 'categorias') {
    while ((prog.i ?? 0) < prog.fila!.length && Date.now() - t0 < ORCAMENTO_MS) {
      const res = await lerCategoria(L, prog.fila![prog.i!], prog)
      if (res === '429') {
        prog.r429 = (prog.r429 ?? 0) + 1
        if (prog.r429 > MAX_429) throw new Error(`a Glovo recusou ${prog.r429} vezes (429): parei`)
        await gravar(sb, c.id, { progresso: prog, lock_ate: new Date(Date.now() + 240_000).toISOString() })
        return { pausa: '429', categoria: prog.i, de: prog.fila!.length }
      }
      prog.i = prog.i! + 1
    }
    if (prog.i! < prog.fila!.length) {
      await gravar(sb, c.id, { progresso: prog, lock_ate: null, lidos: Object.keys(prog.produtos!).length })
      return { continua: true, categoria: prog.i, de: prog.fila!.length, produtos: Object.keys(prog.produtos!).length }
    }
    prog.fase = 'aplicar'
    if (Date.now() - t0 > 60_000) {
      await gravar(sb, c.id, { progresso: prog, lock_ate: null, lidos: Object.keys(prog.produtos!).length })
      return { leitura_feita: true, produtos: Object.keys(prog.produtos!).length }
    }
  }

  if (prog.fase === 'aplicar') return await aplicar(sb, c, L, prog, t0)
  return { nada: true }
}

function json(o: unknown, status = 200) {
  return new Response(JSON.stringify(o), { status, headers: { 'Content-Type': 'application/json' } })
}

Deno.serve(async (req) => {
  const url = Deno.env.get('SUPABASE_URL') ?? ''
  const serviceKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? ''
  const auth = req.headers.get('Authorization') ?? ''
  if (!serviceKey || auth !== `Bearer ${serviceKey}`) return json({ erro: 'só o servidor' }, 403)
  const sb = createClient(url, serviceKey, { auth: { persistSession: false } })
  const corpo = await req.json().catch(() => ({}))

  let q = sb.from('robo_glovo_corridas').select('*').eq('estado', 'a_correr').order('id').limit(1)
  if (corpo?.corrida_id) q = sb.from('robo_glovo_corridas').select('*').eq('estado', 'a_correr').eq('id', corpo.corrida_id).limit(1)
  const { data: linhas, error } = await q
  if (error) return json({ erro: error.message }, 500)
  const c = linhas?.[0]
  if (!c) return json({ nada: 'sem corridas por fazer' })

  // tranca: uma chamada de cada vez por corrida
  const agora = new Date().toISOString()
  const { data: tranca } = await sb
    .from('robo_glovo_corridas')
    .update({ lock_ate: new Date(Date.now() + 170_000).toISOString() })
    .eq('id', c.id)
    .or(`lock_ate.is.null,lock_ate.lt."${agora}"`)
    .select('id')
  if (!tranca?.length) return json({ ocupada: c.id })

  try {
    const r = await passo(sb, c)
    return json({ corrida: c.id, loja: c.loja, ...r })
  } catch (e) {
    const msg = String(e instanceof Error ? e.message : e).slice(0, 400)
    await gravar(sb, c.id, { estado: 'erro', erro: msg, terminada_em: new Date().toISOString(), lock_ate: null }).catch(() => {})
    await avisar(sb, `⚠️ Robô Glovo — ${NOME_LOJA[c.loja] ?? c.loja}: parou com erro. ${msg.slice(0, 200)}`)
    return json({ corrida: c.id, erro: msg }, 500)
  }
})
