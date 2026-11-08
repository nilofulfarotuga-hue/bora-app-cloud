---
id: memoria-claude-ai-proposta-m1-2026-11-08-edge-taloes-zip-mes
tipo: conceito
origem: [claude-ai, public.claude_ai_memoria]
ultima_confirmacao: 2026-11-08
zona: verde
confianca: alta
estado: atual
---

# M1 adendo 1 — Edge nova taloes-zip-mes (index.ts; verify_jwt=false)

> Espelho automatico da tabela `public.claude_ai_memoria` (pagina `proposta-m1-2026-11-08-edge-taloes-zip-mes`, origem `claude-code`, atualizada em 2026-11-08T21:31:57.894466+00:00).
> Gerado por sincroniza-memoria-claude.sh de hora a hora. NAO editar a mao: a verdade vive na tabela.
> Palavras-chave: proposta m1 2026 11 08 edge taloes zip mes · memoria claude.ai · claude_ai_memoria

Missão m1-dinheiro-favores-2026-11-08 (Claude Code do PC, 08/11/2026). Ficheiro: supabase/functions/taloes-zip-mes/index.ts. Copiado para o livro porque a bora-tranca recusa o git push (também do ramo de ensaio).

```ts
// @ts-nocheck
// supabase/functions/taloes-zip-mes/index.ts — v1 08/11/2026
// Missão m1, adendo 1 (Danilo 08/11 20:39: talões guardados para sempre; página "Talões" com botão para
// descarregar o mês todo num ZIP; talões do mês no fecho do contabilista).
//
// Junta num ZIP todas as fotos de talão de um mês (registo public.order_receipt_fotos) + um
// indice.csv (pedido, data, loja, estafeta, valor escrito, NIF usado, ficheiro). Guarda o ZIP em
// receipts/zips/AAAA-MM/… (nunca substitui) e devolve um link assinado.
// Quem chama: admin com sessão (painel) ou o servidor (fecho-mensal-contabilista, chave de servidor).
// POST { mes: 'AAAA-MM', loja?: string, driver_uid?: uuid, validade_segundos?: number }

import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'
import { zipSync } from 'https://esm.sh/fflate@0.8.2'
import { chamadaDoServidor } from '../_shared/chaves.ts'
import { secretKey } from '../_shared/keys.ts'

const cors = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
  'Access-Control-Allow-Methods': 'POST, OPTIONS',
}
const MAX_FOTOS = 1500

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: cors })
  const url = Deno.env.get('SUPABASE_URL')!
  const admin = createClient(url, secretKey()!, { auth: { persistSession: false } })

  let quem = 'servidor'
  if (!(await chamadaDoServidor(req))) {
    const userClient = createClient(url, Deno.env.get('SUPABASE_ANON_KEY')!, {
      global: { headers: { Authorization: req.headers.get('Authorization') ?? '' } },
    })
    const { data: me } = await userClient.auth.getUser()
    if (!me?.user) return json({ ok: false, error: 'sem_sessao' }, 401)
    const { data: ehAdmin } = await userClient.rpc('is_admin')
    if (ehAdmin !== true) return json({ ok: false, error: 'so_admin' }, 403)
    quem = me.user.email ?? me.user.id
  }

  let b: any = {}
  try { b = await req.json() } catch (_e) { return json({ ok: false, error: 'json_invalido' }, 400) }
  const mes = String(b?.mes ?? '')
  if (!/^\d{4}-\d{2}$/.test(mes)) return json({ ok: false, error: 'mes_invalido' }, 400)
  const validade = Math.min(Math.max(Number(b?.validade_segundos) || 3600, 60), 7 * 24 * 3600)
  const [ano, m] = mes.split('-').map(Number)
  // limites do mês em Lisboa (aproximação segura: inclui o dia de fronteira pelos dois lados no filtro final)
  const ini = new Date(Date.UTC(ano, m - 1, 1) - 2 * 3600 * 1000).toISOString()
  const fim = new Date(Date.UTC(m === 12 ? ano + 1 : ano, m === 12 ? 0 : m, 1) + 2 * 3600 * 1000).toISOString()

  // lê o mês inteiro (sem cortar antes dos filtros); o limite conta-se depois de filtrar
  const fotos: any[] = []
  for (let de = 0; ; de += 1000) {
    const { data, error } = await admin.from('order_receipt_fotos')
      .select('order_id, bucket, path, total_cents, recebida_em, driver_uid')
      .gte('recebida_em', ini).lt('recebida_em', fim).order('recebida_em').range(de, de + 999)
    if (error) return json({ ok: false, error: 'leitura_falhou', detalhe: error.message }, 500)
    fotos.push(...(data ?? []))
    if (!data || data.length < 1000 || fotos.length > 20000) break
  }
  const doMes = fotos.filter((f) => mesLisboa(f.recebida_em) === mes)

  const ids = [...new Set(doMes.map((f) => f.order_id))]
  const pedidos: Record<string, any> = {}
  for (let i = 0; i < ids.length; i += 200) {
    const { data } = await admin.from('orders').select('id, vendor_name, restaurant_id, assigned_driver_id')
      .in('id', ids.slice(i, i + 200))
    for (const o of data ?? []) pedidos[o.id] = o
  }
  // o pedido pode guardar o id de login do estafeta OU o id da ficha (drivers.id): resolve sempre para o login
  const fichas = [...new Set(Object.values(pedidos).map((o: any) => o.assigned_driver_id).filter(Boolean))]
  const loginDaFicha: Record<string, string> = {}
  for (let i = 0; i < fichas.length; i += 200) {
    const lote = fichas.slice(i, i + 200)
    const { data } = await admin.from('drivers').select('id, user_id').in('id', lote)
    for (const d of data ?? []) loginDaFicha[d.id] = d.user_id
  }
  const estafetaDe = (f: any) => f.driver_uid ?? loginDaFicha[pedidos[f.order_id]?.assigned_driver_id] ?? pedidos[f.order_id]?.assigned_driver_id ?? null
  const nifs: Record<string, string> = {}
  for (const id of ids) {
    const { data } = await admin.rpc('_talao_nif_usado', { p_order_id: id })
    nifs[id] = data?.nif ?? ''
  }
  const loja = b?.loja ? String(b.loja).toLowerCase() : null
  const driver = b?.driver_uid ? String(b.driver_uid) : null
  const escolhidas = doMes.filter((f) => {
    const o = pedidos[f.order_id] ?? {}
    if (loja && !(String(o.restaurant_id ?? '').toLowerCase() === loja || String(o.vendor_name ?? '').toLowerCase().includes(loja))) return false
    if (driver && estafetaDe(f) !== driver) return false
    return true
  })
  if (escolhidas.length > MAX_FOTOS) return json({ ok: false, error: 'demasiadas_fotos', max: MAX_FOTOS, fotos: escolhidas.length }, 413)

  const ficheiros: Record<string, Uint8Array> = {}
  const linhas = ['pedido;data;loja;estafeta_uid;valor_escrito_eur;nif_usado;ficheiro']
  const faltaram: string[] = []
  for (const f of escolhidas) {
    const { data: blob, error: dlErr } = await admin.storage.from(f.bucket || 'receipts').download(f.path)
    if (dlErr || !blob) { faltaram.push(f.path); continue }
    const o = pedidos[f.order_id] ?? {}
    const nomeZip = `${String(o.vendor_name ?? 'loja').replace(/[^\w-]+/g, '_')}/${f.order_id.slice(0, 8)}_${f.path.split('/').pop()}`
    ficheiros[nomeZip] = new Uint8Array(await blob.arrayBuffer())
    linhas.push([f.order_id, f.recebida_em, csv(o.vendor_name ?? o.restaurant_id ?? ''), estafetaDe(f) ?? '',
      f.total_cents == null ? '' : (f.total_cents / 100).toFixed(2).replace('.', ','), nifs[f.order_id] ?? '', nomeZip].join(';'))
  }
  ficheiros['indice.csv'] = new TextEncoder().encode('﻿' + linhas.join('\r\n') + '\r\n')
  const zip = zipSync(ficheiros, { level: 0 })   // fotos já são JPEG: guardar sem recomprimir

  const destino = `zips/${mes}/taloes-${mes}-${Date.now()}.zip`
  const { error: upErr } = await admin.storage.from('receipts').upload(destino, zip, { contentType: 'application/zip', upsert: false })
  if (upErr) return json({ ok: false, error: 'zip_nao_guardado', detalhe: upErr.message }, 500)
  const { data: assinado, error: sErr } = await admin.storage.from('receipts').createSignedUrl(destino, validade)
  if (sErr) return json({ ok: false, error: 'link_falhou', detalhe: sErr.message }, 500)

  try {
    await admin.from('e2e_log').insert({ fluxo: 'taloes-zip-mes', passo: mes, estado: faltaram.length ? 'parcial' : 'ok',
      detalhe: `${escolhidas.length - faltaram.length} fotos, ${zip.byteLength} bytes, ${destino}, por ${quem}${faltaram.length ? ', faltaram ' + faltaram.length : ''}`, device: 'edge' })
  } catch (_e) { /* melhor esforço */ }
  return json({ ok: true, mes, fotos: escolhidas.length - faltaram.length, faltaram, bytes: zip.byteLength, path: destino, url: assinado?.signedUrl, validade_segundos: validade })
})

function mesLisboa(iso: string): string {
  const p = new Intl.DateTimeFormat('en-CA', { timeZone: 'Europe/Lisbon', year: 'numeric', month: '2-digit' }).formatToParts(new Date(iso))
  return `${p.find((x) => x.type === 'year')?.value}-${p.find((x) => x.type === 'month')?.value}`
}
function csv(s: string): string { return String(s).replace(/[;\r\n]+/g, ' ') }
function json(o: any, s = 200): Response {
  return new Response(JSON.stringify(o), { status: s, headers: { ...cors, 'Content-Type': 'application/json' } })
}

```

