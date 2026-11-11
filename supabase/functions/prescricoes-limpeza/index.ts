// prescricoes-limpeza (missão farmacias-2026-11-11)
// Apaga do bucket privado `prescricoes` as fotos e assinaturas dos pedidos de receita que já
// passaram os dias de retenção (definição pharmacy_prescription_retention_days, 30) e põe a null
// os códigos da receita. Corre 1 vez por dia pelo pg_cron (farmacias-prescricoes-limpeza).
// Só o servidor (service role) pode chamar. Idempotente: o que já foi apagado não volta a contar.
// Nunca escreve caminhos nem códigos nos logs (dados de saúde) — só contagens.
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
    const { data, error } = await sb.rpc('prescricao_para_limpar', { p_limite: 200 })
    if (error) return json({ ok: false, error: 'listar', pedidos, ficheiros }, 500)
    const linhas = (data ?? []) as { id: string; caminhos: string[] | null }[]
    if (linhas.length === 0) break

    const prontos: string[] = []
    for (const l of linhas) {
      const caminhos = (l.caminhos ?? []).filter((c) => typeof c === 'string' && c.length > 0)
      if (caminhos.length > 0) {
        const { error: e } = await sb.storage.from('prescricoes').remove(caminhos)
        if (e) { falhas++; continue }
        ficheiros += caminhos.length
      }
      prontos.push(l.id)
    }
    if (prontos.length > 0) {
      const { data: n, error: e2 } = await sb.rpc('prescricao_marcar_dados_apagados', { p_ids: prontos })
      if (e2) return json({ ok: false, error: 'marcar', pedidos, ficheiros }, 500)
      pedidos += Number(n ?? 0)
    }
    if (linhas.length < 200) break
  }
  console.log(`[prescricoes-limpeza] pedidos=${pedidos} ficheiros=${ficheiros} falhas=${falhas}`)
  return json({ ok: true, pedidos, ficheiros, falhas })
})
