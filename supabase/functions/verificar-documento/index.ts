// @ts-nocheck
// supabase/functions/verificar-documento/index.ts  v2  2026-10-29
//
// Robô "fiscal de documentos" (missão final-app-2026-10-29, adendo 3, R2). No padrão do ocr-receipt v11:
// gemini-3.1-flash-lite com thinkingBudget 0 e, se vier vazio ou pouco seguro, gemini-3.1-flash;
// JSON estrito; PDF e imagem por inline_data com o formato certo (lido dos primeiros bytes).
// v2: repete até 2 vezes quando o Gemini responde 429/5xx (sobrecarga) e pára a 100 s.
//
// SÓ O SERVIDOR CHAMA (exigirServidor): os gatilhos do banco (pg_net), a varredura e o cron. A
// verificação "na hora" da app vive noutra função (verificar-documento-previa), com sessão.
//
// O que faz, por pessoa (corpo: { user_id, campo?, forcar_sombra?, reverificar? }):
//   1. lê do banco os documentos que a pessoa tem (_robo_documentos_alvos) e salta os já verificados;
//   2. descarrega cada um do balde privado, deteta o formato e pergunta ao Gemini (chave PAGA);
//   3. compara no servidor o nome e o NIF lidos com os da conta e DEITA FORA o que leu;
//   4. grava o veredito em documentos_verificacoes (só "bate/não bate", nunca o nome nem o NIF);
//   5. só no modo ativo (robo_documentos_ativo=true E robo_documentos_modo='ativo') chama
//      robo_documentos_aplicar, que recusa/avisa. O robô NUNCA aprova nada.
//
// Chave: GEMINI_API_KEY (a do Bora Assistente — projeto bora-juiz, nível 1 pago). Nunca a
// GEMINI_API_KEY_FALLBACK, que pode ser grátis; com a grátis a Google pode usar o conteúdo.
// Sem a chave: no-op gracioso (ok:false, gemini_nao_configurado).

import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'
import { chaveSecreta, exigirServidor } from '../_shared/chaves.ts'
import {
  analisar,
  decidir,
  detetarMime,
  hojeEmLisboa,
  MAX_BYTES,
  paraBase64,
  sha256Hex,
  tipoEsperadoDe,
} from '../_shared/documentos_robo.ts'

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
  'Access-Control-Allow-Methods': 'POST, OPTIONS',
}
const RE_UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i
const MAX_ALVOS = 10
const TEMPO_MAX_MS = 100_000 // a função não pode passar do limite da plataforma; o resto fica para a próxima

Deno.serve(async (req) => {
  const t0 = Date.now()
  if (req.method === 'OPTIONS') return new Response('ok', { headers: corsHeaders })
  if (req.method !== 'POST') return json({ ok: false, error: 'metodo' }, 405)
  const bloqueio = await exigirServidor(req, corsHeaders)
  if (bloqueio) return bloqueio

  let corpo: any
  try {
    corpo = await req.json()
  } catch {
    return json({ ok: false, error: 'json_invalido' }, 400)
  }
  const userId = String(corpo?.user_id ?? '')
  if (!RE_UUID.test(userId)) return json({ ok: false, error: 'user_id_invalido' }, 400)
  const forcarSombra = corpo?.forcar_sombra === true
  const reverificar = corpo?.reverificar === true
  const filtroCampo = typeof corpo?.campo === 'string' ? corpo.campo : null

  const chave = Deno.env.get('GEMINI_API_KEY')
  if (!chave) {
    console.warn('[verificar-documento] GEMINI_API_KEY em falta — nada a fazer')
    return json({ ok: false, reason: 'gemini_nao_configurado' })
  }

  const admin = createClient(Deno.env.get('SUPABASE_URL')!, chaveSecreta(), { auth: { persistSession: false } })

  const { data: cfg, error: erroCfg } = await admin.rpc('_robo_documentos_cfg')
  if (erroCfg || !cfg) return json({ ok: false, error: 'sem_definicoes', detalhe: erroCfg?.message ?? null }, 500)
  const limiteDia = Number(cfg.limite_dia ?? 200)
  if (!(limiteDia > 0)) return json({ ok: true, parado: 'limite_dia_zero' })
  const confMin = Number(cfg.confianca_min ?? 0.85)
  const modo = !forcarSombra && cfg.ativo === true && cfg.modo === 'ativo' ? 'ativo' : 'sombra'

  const { data: info, error: erroAlvos } = await admin.rpc('_robo_documentos_alvos', { p_user_id: userId })
  if (erroAlvos || !info) return json({ ok: false, error: 'sem_alvos', detalhe: erroAlvos?.message ?? null }, 500)

  const desde = new Date(Date.now() - 24 * 3600 * 1000).toISOString()
  const { count } = await admin.from('documentos_verificacoes').select('id', { count: 'exact', head: true })
    .gte('created_at', desde).not('modelo', 'is', null)
  let usadas = count ?? 0

  const resultados: any[] = []
  for (const alvo of (info.alvos ?? []).slice(0, MAX_ALVOS)) {
    if (filtroCampo && alvo.campo !== filtroCampo) continue
    const esperado = tipoEsperadoDe(alvo.tipo_esperado)
    if (!esperado) {
      resultados.push({ campo: alvo.campo, estado: 'tipo_desconhecido' })
      continue
    }

    // Já verificado este ficheiro? (mesmo campo e caminho, veredito não desfeito)
    const { data: ant } = await admin.from('documentos_verificacoes').select('*')
      .eq('user_id', userId).eq('campo', alvo.campo).eq('path', alvo.path).is('revertido_em', null)
      .order('id', { ascending: false }).limit(1).maybeSingle()
    if (ant && !reverificar) {
      if (ant.modo === 'previa') {
        // O candidato já foi avisado na app antes de enviar; se enviou mesmo assim, decide o Danilo.
        const insistiu = ant.decisao === 'errado'
        const copia = {
          user_id: userId, papel: alvo.papel, campo: alvo.campo, tipo_documento_esperado: alvo.tipo_esperado,
          bucket: alvo.bucket, path: alvo.path, sha256: ant.sha256, modelo: ant.modelo,
          tipo_detectado: ant.tipo_detectado, legivel: ant.legivel, nome_bate: ant.nome_bate, nif_bate: ant.nif_bate,
          validade: ant.validade, confianca: ant.confianca,
          motivo_pt: insistiu ? 'Enviado mesmo depois do aviso do robô na app; ver à mão.' : ant.motivo_pt,
          decisao: insistiu ? 'duvida' : ant.decisao, acao: 'nenhuma', modo,
        }
        const { data: nova, error } = await admin.from('documentos_verificacoes').insert(copia).select('id').single()
        if (!error && nova) {
          const aplicado = modo === 'ativo' ? await aplicar(admin, nova.id) : null
          resultados.push({ campo: alvo.campo, estado: 'reaproveitado_da_previa', decisao: copia.decisao, aplicado })
        }
      } else {
        resultados.push({ campo: alvo.campo, estado: 'ja_verificado', decisao: ant.decisao })
      }
      continue
    }

    // Ficheiro.
    const dl = await admin.storage.from(alvo.bucket).download(decodeURIComponent(alvo.path))
    if (dl.error || !dl.data) {
      resultados.push({ campo: alvo.campo, estado: 'sem_ficheiro' })
      continue
    }
    const bytes = new Uint8Array(await dl.data.arrayBuffer())
    const sha = await sha256Hex(bytes)
    const base = {
      user_id: userId, papel: alvo.papel, campo: alvo.campo, tipo_documento_esperado: alvo.tipo_esperado,
      bucket: alvo.bucket, path: alvo.path, sha256: sha, acao: 'nenhuma', modo,
    }
    const mime = detetarMime(bytes)
    if (!mime || bytes.length > MAX_BYTES) {
      const { data: n } = await admin.from('documentos_verificacoes').insert({
        ...base, modelo: null, tipo_detectado: null, legivel: null, nome_bate: null, nif_bate: null,
        validade: null, confianca: 0,
        motivo_pt: 'O robô não consegue analisar este formato ou tamanho de ficheiro; ver à mão.',
        decisao: 'duvida',
      }).select('id').single()
      resultados.push({ campo: alvo.campo, estado: 'formato', id: n?.id ?? null })
      continue
    }

    if (usadas >= limiteDia) {
      resultados.push({ campo: alvo.campo, estado: 'limite_dia' })
      break
    }
    if (Date.now() - t0 > TEMPO_MAX_MS) {
      resultados.push({ campo: alvo.campo, estado: 'tempo' })
      break
    }
    const b64 = paraBase64(bytes)
    let a = await analisar(chave, mime, b64, esperado, confMin)
    // 429/5xx do Gemini (sobrecarga) costumam passar à segunda: espera um pouco e repete, até 2 vezes.
    for (const espera of [2000, 5000]) {
      if (a.leitura || ![429, 500, 502, 503, 504].includes(a.httpStatus ?? 0)) break
      await new Promise((r) => setTimeout(r, espera))
      a = await analisar(chave, mime, b64, esperado, confMin)
    }
    usadas++
    if (!a.leitura) {
      await admin.from('e2e_log').insert({
        fluxo: 'robo-documentos', passo: 'gemini', estado: 'falhou',
        detalhe: `u=${userId.slice(0, 8)} campo=${alvo.campo} http=${a.httpStatus ?? 'sem'}`, device: 'edge-verificar-documento',
      })
      resultados.push({ campo: alvo.campo, estado: 'gemini_falhou', http: a.httpStatus })
      continue
    }

    // Compara aqui e deita fora o nome e o NIF lidos (só ficam os "bate").
    const v = decidir({
      esperado, leitura: a.leitura, nomeConta: info.nome_conta ?? null, nifConta: info.nif_conta ?? null,
      confiancaMin: confMin, hoje: hojeEmLisboa(),
    })
    const { data: gravada, error: erroGravar } = await admin.from('documentos_verificacoes').insert({
      ...base, modelo: a.modelo, tipo_detectado: v.tipo_detectado, legivel: v.legivel,
      nome_bate: v.nome_bate, nif_bate: v.nif_bate, validade: v.validade, confianca: v.confianca,
      motivo_pt: v.motivo_pt, decisao: v.decisao,
    }).select('id').single()
    if (erroGravar || !gravada) {
      resultados.push({ campo: alvo.campo, estado: 'nao_gravou', detalhe: erroGravar?.message ?? null })
      continue
    }
    const aplicado = modo === 'ativo' ? await aplicar(admin, gravada.id) : null
    resultados.push({ campo: alvo.campo, id: gravada.id, decisao: v.decisao, confianca: v.confianca, tipo: v.tipo_detectado, aplicado })
  }

  await admin.from('e2e_log').insert({
    fluxo: 'robo-documentos', passo: 'verificar', estado: 'ok',
    detalhe: `u=${userId.slice(0, 8)} modo=${modo} n=${resultados.length} ` +
      resultados.map((r) => `${String(r.campo).split('.').pop()}:${r.decisao ?? r.estado}`).join(','),
    device: 'edge-verificar-documento',
  })
  return json({ ok: true, modo, resultados })
})

async function aplicar(admin: any, id: number): Promise<any> {
  const { data, error } = await admin.rpc('robo_documentos_aplicar', { p_id: id })
  if (error) {
    await admin.from('e2e_log').insert({
      fluxo: 'robo-documentos', passo: 'aplicar', estado: 'falhou', detalhe: `id=${id} ${error.message}`.slice(0, 300),
      device: 'edge-verificar-documento',
    })
    return { erro: error.message }
  }
  return data
}

function json(obj: any, status = 200): Response {
  return new Response(JSON.stringify(obj), {
    status,
    headers: { ...corsHeaders, 'Content-Type': 'application/json' },
  })
}
