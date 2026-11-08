---
id: memoria-claude-ai-proposta-m1-2026-11-08-edge-taloes-copia-diaria
tipo: conceito
origem: [claude-ai, public.claude_ai_memoria]
ultima_confirmacao: 2026-11-08
zona: verde
confianca: alta
estado: atual
---

# M1 adendo 1 — Edge nova taloes-copia-diaria (index.ts; verify_jwt=false)

> Espelho automatico da tabela `public.claude_ai_memoria` (pagina `proposta-m1-2026-11-08-edge-taloes-copia-diaria`, origem `claude-code`, atualizada em 2026-11-08T21:12:12.248892+00:00).
> Gerado por sincroniza-memoria-claude.sh de hora a hora. NAO editar a mao: a verdade vive na tabela.
> Palavras-chave: proposta m1 2026 11 08 edge taloes copia diaria · memoria claude.ai · claude_ai_memoria

Missão m1-dinheiro-favores-2026-11-08, adendo 1 (Claude Code do PC, 08/11/2026). Ficheiro: supabase/functions/taloes-copia-diaria/index.ts. Copiado para o livro porque a bora-tranca recusa o git push (também do ramo de ensaio).

```ts
// @ts-nocheck
// supabase/functions/taloes-copia-diaria/index.ts — v1 08/11/2026
// Missão m1, adendo 1 (Danilo 08/11 20:39): "o Storage do Supabase não entra nas cópias de segurança da
// base" → 2.ª cópia automática diária dos talões novos para o Google Drive da conta da Bora, pasta
// Talões/AAAA/MM. Nunca apaga nada (nem cá nem lá). Guardar 10 anos.
//
// Agendada por pg_cron ('taloes-copia-diaria', proposta 07). Só corre com:
//   * platform_settings.taloes_copia_drive_ativa = true
//   * segredos GOOGLE_DRIVE_CLIENT_ID, GOOGLE_DRIVE_CLIENT_SECRET, GOOGLE_DRIVE_REFRESH_TOKEN (OAuth da
//     conta Google da Bora, âmbito drive.file) e GOOGLE_DRIVE_PASTA_TALOES (id da pasta "Talões").
// Sem isso responde 'por_configurar' e não faz nada (fica registado no e2e_log).
// Cada foto copiada fica marcada em order_receipt_fotos.copia_em/copia_destino (idempotente: só copia
// as que ainda não têm cópia; 200 por chamada).
// Quem chama: só o servidor (chave de servidor). POST { cron?: true, limite?: number }

import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'
import { chamadaDoServidor } from '../_shared/chaves.ts'
import { secretKey } from '../_shared/keys.ts'

const cors = { 'Access-Control-Allow-Origin': '*', 'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type' }

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: cors })
  if (!(await chamadaDoServidor(req))) return json({ ok: false, error: 'so_servidor' }, 403)
  let b: any = {}
  try { b = await req.json() } catch (_e) { /* vazio */ }
  const admin = createClient(Deno.env.get('SUPABASE_URL')!, secretKey()!, { auth: { persistSession: false } })
  const registo = async (estado: string, detalhe: string) => {
    try { await admin.from('e2e_log').insert({ fluxo: 'taloes-copia-diaria', passo: new Date().toISOString().slice(0, 10), estado, detalhe: detalhe.slice(0, 1000), device: 'edge' }) } catch (_e) { /* melhor esforço */ }
  }

  const { data: s } = await admin.from('platform_settings').select('value').eq('key', 'taloes_copia_drive_ativa').maybeSingle()
  if (!(s?.value === true || s?.value === 'true')) return json({ ok: true, estado: 'desligado' })
  const clientId = Deno.env.get('GOOGLE_DRIVE_CLIENT_ID') ?? ''
  const clientSecret = Deno.env.get('GOOGLE_DRIVE_CLIENT_SECRET') ?? ''
  const refresh = Deno.env.get('GOOGLE_DRIVE_REFRESH_TOKEN') ?? ''
  const raiz = Deno.env.get('GOOGLE_DRIVE_PASTA_TALOES') ?? ''
  if (!clientId || !clientSecret || !refresh || !raiz) {
    await registo('bloqueado', 'por_configurar: faltam os segredos GOOGLE_DRIVE_* (autorizar o Drive da Bora)')
    return json({ ok: false, estado: 'por_configurar' })
  }

  const tk = await fetch('https://oauth2.googleapis.com/token', {
    method: 'POST', headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
    body: new URLSearchParams({ client_id: clientId, client_secret: clientSecret, refresh_token: refresh, grant_type: 'refresh_token' }),
  })
  const tkb = await tk.json().catch(() => ({}))
  if (!tk.ok || !tkb.access_token) {
    await registo('erro', `token Google falhou: ${tk.status} ${JSON.stringify(tkb).slice(0, 200)}`)
    return json({ ok: false, estado: 'token_falhou' }, 500)
  }
  const auth = { Authorization: `Bearer ${tkb.access_token}` }

  const limite = Math.min(Math.max(Number(b?.limite) || 200, 1), 500)
  const { data: fotos, error } = await admin.from('order_receipt_fotos')
    .select('id, order_id, bucket, path, foto_id, recebida_em').is('copia_em', null).order('recebida_em').limit(limite)
  if (error) { await registo('erro', `leitura: ${error.message}`); return json({ ok: false, error: error.message }, 500) }

  const pastas: Record<string, string> = {}
  const pasta = async (nome: string, pai: string): Promise<string> => {
    const chave = `${pai}/${nome}`
    if (pastas[chave]) return pastas[chave]
    const q = encodeURIComponent(`name='${nome}' and '${pai}' in parents and mimeType='application/vnd.google-apps.folder' and trashed=false`)
    const r = await fetch(`https://www.googleapis.com/drive/v3/files?q=${q}&fields=files(id)`, { headers: auth })
    const rb = await r.json().catch(() => ({}))
    let id = rb?.files?.[0]?.id
    if (!id) {
      const c = await fetch('https://www.googleapis.com/drive/v3/files?fields=id', {
        method: 'POST', headers: { ...auth, 'Content-Type': 'application/json' },
        body: JSON.stringify({ name: nome, mimeType: 'application/vnd.google-apps.folder', parents: [pai] }),
      })
      id = (await c.json().catch(() => ({})))?.id
    }
    if (!id) throw new Error(`pasta ${chave} não criada`)
    pastas[chave] = id
    return id
  }

  let copiadas = 0
  const erros: string[] = []
  for (const f of fotos ?? []) {
    try {
      const d = new Date(f.recebida_em)
      const p = new Intl.DateTimeFormat('en-CA', { timeZone: 'Europe/Lisbon', year: 'numeric', month: '2-digit' }).formatToParts(d)
      const ano = p.find((x) => x.type === 'year')?.value ?? String(d.getUTCFullYear())
      const mes = p.find((x) => x.type === 'month')?.value ?? '01'
      const destino = await pasta(mes, await pasta(ano, raiz))
      const { data: blob, error: dlErr } = await admin.storage.from(f.bucket || 'receipts').download(f.path)
      if (dlErr || !blob) throw new Error(`download: ${dlErr?.message ?? 'vazio'}`)
      const nome = `${f.order_id}__${(f.foto_id ?? f.path.split('/').pop() ?? 'talao').replace(/\.jpg$/i, '')}.jpg`
      const fronteira = 'bora' + crypto.randomUUID().replace(/-/g, '')
      const meta = JSON.stringify({ name: nome, parents: [destino], description: `Talão do pedido ${f.order_id} (${f.path})` })
      const corpo = new Blob([
        `--${fronteira}\r\nContent-Type: application/json; charset=UTF-8\r\n\r\n${meta}\r\n`,
        `--${fronteira}\r\nContent-Type: image/jpeg\r\n\r\n`, blob, `\r\n--${fronteira}--`,
      ])
      const up = await fetch('https://www.googleapis.com/upload/drive/v3/files?uploadType=multipart&fields=id', {
        method: 'POST', headers: { ...auth, 'Content-Type': `multipart/related; boundary=${fronteira}` }, body: corpo,
      })
      const ub = await up.json().catch(() => ({}))
      if (!up.ok || !ub?.id) throw new Error(`upload Drive ${up.status}: ${JSON.stringify(ub).slice(0, 150)}`)
      await admin.from('order_receipt_fotos').update({ copia_em: new Date().toISOString(), copia_destino: `drive:${ub.id}`, copia_erro: null })
        .eq('id', f.id).is('copia_em', null)
      copiadas++
    } catch (e) {
      const m = e instanceof Error ? e.message : String(e)
      erros.push(`${f.path}: ${m}`)
      await admin.from('order_receipt_fotos').update({ copia_erro: m.slice(0, 300) }).eq('id', f.id)
    }
  }
  await registo(erros.length ? (copiadas ? 'parcial' : 'erro') : 'ok', `copiadas=${copiadas} de ${(fotos ?? []).length}${erros.length ? ' · ' + erros.slice(0, 3).join(' | ') : ''}`)
  return json({ ok: erros.length === 0, copiadas, verificadas: (fotos ?? []).length, erros: erros.length })
})

function json(o: any, s = 200): Response {
  return new Response(JSON.stringify(o), { status: s, headers: { ...cors, 'Content-Type': 'application/json' } })
}

```

