// @ts-nocheck
// supabase/functions/verificar-documento-previa/index.ts  v1  2026-10-29
//
// Verificação "na hora" (adendo 3, R8): quando o candidato escolhe o ficheiro, a app pergunta aqui se
// parece o documento certo, ANTES de enviar — como a Uber e a Glovo. É a única porta com sessão do robô
// (a verificar-documento é só do servidor). Não decide nada sobre a conta: só devolve o veredito.
//
// Corpo: { campo, path, nif? }  — o ficheiro já está no balde privado da própria pessoa (primeira pasta
// = o id dela). Só mostra veredito à app quando o robô está LIGADO e em modo ativo; senão grava a
// observação (modo sombra) e responde { ok:true, ativo:false } para a app não dizer nada.
// Falha sempre "aberta": se algo correr mal, a app deixa a pessoa seguir.
// Limites: 12 análises por pessoa por dia e o limite global robo_documentos_limite_dia.
//
// Chave: GEMINI_API_KEY (paga, a do Bora Assistente). Nunca a de reserva. Ver _shared/documentos_robo.ts.

import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'
import { chaveSecreta, exigirServidorOuUtilizador } from '../_shared/chaves.ts'
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

const CAMPOS: Record<string, { bucket: string; tipo: string }> = {
  'provider_atividade.documento_path': { bucket: 'provider-atividade', tipo: 'comprovativo_atividade_AT' },
  'drivers.registration_selfie_url': { bucket: 'driver-documents', tipo: 'selfie' },
  'drivers.document_photo_url': { bucket: 'driver-documents', tipo: 'documento_identificacao' },
  'drivers.vehicle_photo_url': { bucket: 'driver-documents', tipo: 'foto_veiculo' },
  'drivers.vehicle_doc_url': { bucket: 'driver-documents', tipo: 'documento_veiculo' },
  'cleaners.docs.id_doc': { bucket: 'cleaner-documents', tipo: 'documento_identificacao' },
  'washers.docs.id_doc': { bucket: 'washer-documents', tipo: 'documento_identificacao' },
  'washers.docs.driving_license': { bucket: 'washer-documents', tipo: 'carta_conducao' },
}
const POR_PESSOA_DIA = 12

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: corsHeaders })
  if (req.method !== 'POST') return json({ ok: false, error: 'metodo' }, 405)

  const quem = await exigirServidorOuUtilizador(req, corsHeaders)
  if (quem.resposta) return quem.resposta
  if (!quem.utilizador) return json({ ok: false, error: 'so_com_sessao' }, 403)
  const uid = quem.utilizador.id

  let corpo: any
  try {
    corpo = await req.json()
  } catch {
    return json({ ok: false, error: 'json_invalido' }, 400)
  }
  const campo = String(corpo?.campo ?? '')
  const caminho = String(corpo?.path ?? '')
  const alvo = CAMPOS[campo]
  if (!alvo) return json({ ok: false, error: 'campo_invalido' }, 400)
  if (!caminho || caminho.includes('..') || caminho.split('/')[0] !== uid) {
    return json({ ok: false, error: 'documento_invalido' }, 400)
  }
  const esperado = tipoEsperadoDe(alvo.tipo)
  if (!esperado) return json({ ok: false, error: 'tipo_invalido' }, 400)

  const chave = Deno.env.get('GEMINI_API_KEY')
  if (!chave) return json({ ok: true, ativo: false, motivo: 'sem_chave' })
  const admin = createClient(Deno.env.get('SUPABASE_URL')!, chaveSecreta(), { auth: { persistSession: false } })

  try {
    const { data: cfg } = await admin.rpc('_robo_documentos_cfg')
    if (!cfg || !(Number(cfg.limite_dia ?? 0) > 0)) return json({ ok: true, ativo: false, motivo: 'pausado' })
    const acting = cfg.ativo === true && cfg.modo === 'ativo'
    const confMin = Number(cfg.confianca_min ?? 0.85)

    // Já visto este ficheiro? Devolve o mesmo veredito, sem pagar outra vez.
    const { data: ant } = await admin.from('documentos_verificacoes')
      .select('decisao, motivo_pt, confianca, tipo_detectado')
      .eq('user_id', uid).eq('campo', campo).eq('path', caminho).is('revertido_em', null)
      .order('id', { ascending: false }).limit(1).maybeSingle()
    if (ant) return json(resposta(acting, ant))

    const desde = new Date(Date.now() - 24 * 3600 * 1000).toISOString()
    const { count: minhas } = await admin.from('documentos_verificacoes').select('id', { count: 'exact', head: true })
      .eq('user_id', uid).gte('created_at', desde).not('modelo', 'is', null)
    if ((minhas ?? 0) >= POR_PESSOA_DIA) return json({ ok: true, ativo: false, motivo: 'limite_pessoa' })
    const { count: todas } = await admin.from('documentos_verificacoes').select('id', { count: 'exact', head: true })
      .gte('created_at', desde).not('modelo', 'is', null)
    if ((todas ?? 0) >= Number(cfg.limite_dia)) return json({ ok: true, ativo: false, motivo: 'limite_dia' })

    const dl = await admin.storage.from(alvo.bucket).download(decodeURIComponent(caminho))
    if (dl.error || !dl.data) return json({ ok: true, ativo: false, motivo: 'sem_ficheiro' })
    const bytes = new Uint8Array(await dl.data.arrayBuffer())
    const mime = detetarMime(bytes)
    if (!mime || bytes.length > MAX_BYTES) return json({ ok: true, ativo: false, motivo: 'formato' })

    const { data: info } = await admin.rpc('_robo_documentos_alvos', { p_user_id: uid })
    const nifDigitado = typeof corpo?.nif === 'string' ? corpo.nif : null
    const a = await analisar(chave, mime, paraBase64(bytes), esperado, confMin)
    if (!a.leitura) return json({ ok: true, ativo: false, motivo: 'sem_resposta' })
    const v = decidir({
      esperado, leitura: a.leitura, nomeConta: info?.nome_conta ?? null,
      nifConta: nifDigitado ?? info?.nif_conta ?? null, confiancaMin: confMin, hoje: hojeEmLisboa(),
    })
    // NIF digitado na hora: se o documento mostra outro NIF, é só dúvida (já tratado em decidir).
    await admin.from('documentos_verificacoes').insert({
      user_id: uid, papel: 'prestador', campo, tipo_documento_esperado: alvo.tipo, bucket: alvo.bucket, path: caminho,
      sha256: await sha256Hex(bytes), modelo: a.modelo, tipo_detectado: v.tipo_detectado, legivel: v.legivel,
      nome_bate: v.nome_bate, nif_bate: v.nif_bate, validade: v.validade, confianca: v.confianca,
      motivo_pt: v.motivo_pt, decisao: v.decisao, acao: 'nenhuma', modo: acting ? 'previa' : 'sombra',
    })
    return json(resposta(acting, v))
  } catch (e) {
    console.error('[verificar-documento-previa]', String(e).slice(0, 200))
    return json({ ok: true, ativo: false, motivo: 'erro' })
  }
})

// Só mostra veredito quando o robô está a agir; senão a app não diz nada.
function resposta(acting: boolean, v: any) {
  if (!acting) return { ok: true, ativo: false }
  return {
    ok: true, ativo: true, decisao: v.decisao, motivo_pt: v.decisao === 'ok' ? null : v.motivo_pt,
    tipo_detectado: v.tipo_detectado ?? null, confianca: Number(v.confianca ?? 0),
  }
}

function json(obj: any, status = 200): Response {
  return new Response(JSON.stringify(obj), {
    status,
    headers: { ...corsHeaders, 'Content-Type': 'application/json' },
  })
}
