// impressoes-limpeza (missão a3-guarda-16-11, parte 2 — serviço de impressão)
// Apaga do bucket privado `impressoes` os ficheiros dos pedidos de impressão e de personalizados
// que acabaram há mais de 30 dias (RGPD) e limpa a morada e o texto do pedido. Corre 1 vez por
// dia pelo pg_cron (impressoes-limpeza). Molde: prescricoes-limpeza (11/11).
// Só o servidor (service role) pode chamar. Idempotente. Nunca escreve caminhos nos logs.
import { createClient } from 'jsr:@supabase/supabase-js@2'

const json = (b: unknown, status = 200) =>
  new Response(JSON.stringify(b), { status, headers: { 'Content-Type': 'application/json' } })

Deno.serve(async (req) => {
  const url = Deno.env.get('SUPABASE_URL') ?? ''
  const serviceKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? ''
  const auth = req.headers.get('Authorization') ?? ''
  if (!serviceKey || auth !== `Bearer ${serviceKey}`) {
    return json({ ok: false, error: 'forbidden' }, 403)
  }
  const sb = createClient(url, serviceKey, { auth: { persistSession: false } })

  let pedidos = 0
  let ficheiros = 0
  let falhas = 0
  for (let volta = 0; volta < 10; volta++) {
    const { data, error } = await sb.rpc('impressao_para_limpar', { p_limite: 200 })
    if (error) return json({ ok: false, error: 'listar', pedidos, ficheiros }, 500)
    const linhas = (data ?? []) as { id: string; caminhos: string[] | null }[]
    if (linhas.length === 0) break

    const prontos: string[] = []
    for (const l of linhas) {
      const caminhos = (l.caminhos ?? []).filter((c) => typeof c === 'string' && c.length > 0)
      if (caminhos.length > 0) {
        const { error: e } = await sb.storage.from('impressoes').remove(caminhos)
        if (e) { falhas++; continue }
        ficheiros += caminhos.length
      }
      prontos.push(l.id)
    }
    if (prontos.length > 0) {
      const { data: n, error: e2 } = await sb.rpc('impressao_marcar_dados_apagados', { p_ids: prontos })
      if (e2) return json({ ok: false, error: 'marcar', pedidos, ficheiros }, 500)
      pedidos += Number(n ?? 0)
    }
    if (linhas.length < 200) break
  }
  console.log(`[impressoes-limpeza] pedidos=${pedidos} ficheiros=${ficheiros} falhas=${falhas}`)
  return json({ ok: true, pedidos, ficheiros, falhas })
})
