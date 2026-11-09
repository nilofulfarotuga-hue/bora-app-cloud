// supabase/functions/ocr-receipt/nif_talao.ts
//
// v12 (M10 b2-nif, 09/11/2026) — o NIF do ADQUIRENTE impresso no talão contra o NIF que o
// estafeta tinha de dar na caixa. Regra (Danilo 04/11 e 08/11): em loja NÃO-parceira e Favor
// com compra o talão leva SEMPRE um NIF — o do cliente se pediu fatura, senão o da Bora
// (setting nif_compras_nao_parceiro). Quem decide é o servidor (`_nif_caixa_regra`, migração
// 20261109010000_m10_nif_na_caixa.sql); aqui só se compara.
// Em falta ou diferente → o talão fica marcado para revisão (ocr_flagged) e o admin recebe o
// aviso `nif_talao_diferente` com os dois números — exceto quando o estafeta já disse
// "Não consegui" (o admin já recebeu `nif_nao_dado_na_caixa`). Não mexe em dinheiro.

/** Os 9 dígitos de um NIF lido pelo modelo ("PT 265 148 502" → "265148502"), ou null. */
export function limparNif(v: unknown): string | null {
  if (typeof v !== 'string' && typeof v !== 'number') return null
  const d = String(v).replace(/\D/g, '')
  return d.length === 9 ? d : null
}

export type ComparacaoNif =
  | { aplica: false }
  | { aplica: true; ok: true; esperado: string; talao: string }
  | { aplica: true; ok: false; motivo: 'nif_em_falta' | 'nif_diferente'; esperado: string; talao: string | null }

/**
 * regra = resposta de `_nif_caixa_regra` ({aplica, nif, ...}); nifTalao = o NIF já limpo que o
 * modelo leu; pareceTalao = false quando a foto não parece um talão (aí não se acusa o NIF).
 */
export function compararNifTalao(regra: unknown, nifTalao: string | null, pareceTalao: boolean): ComparacaoNif {
  const r = (regra && typeof regra === 'object') ? regra as { aplica?: unknown; nif?: unknown } : null
  const esperado = limparNif(r?.nif)
  if (!r || r.aplica !== true || !esperado || !pareceTalao) return { aplica: false }
  if (!nifTalao) return { aplica: true, ok: false, motivo: 'nif_em_falta', esperado, talao: null }
  if (nifTalao !== esperado) return { aplica: true, ok: false, motivo: 'nif_diferente', esperado, talao: nifTalao }
  return { aplica: true, ok: true, esperado, talao: nifTalao }
}

export type VerificacaoNif = ComparacaoNif & { estafeta_disse?: boolean | null; erro?: string }

// deno-lint-ignore no-explicit-any
type Cliente = any

/**
 * Lê a regra e a resposta do estafeta (order_nif_caixa) com a chave de servidor e compara.
 * O NIF esperado é o que o estafeta confirmou (se confirmou) ou o da regra. Nunca lança: sem a
 * migração no servidor (função em falta) fica { aplica: false } e o talão segue como antes.
 */
export async function verificarNifDoTalao(
  sb: Cliente, orderId: string, nifLido: unknown, pareceTalao: boolean,
): Promise<VerificacaoNif> {
  try {
    const { data: regra, error } = await sb.rpc('_nif_caixa_regra', { p_order_id: orderId })
    if (error) return { aplica: false, erro: String(error.message ?? error) }
    let caixa: { nif?: string | null; dado?: boolean | null } | null = null
    try {
      const r = await sb.from('order_nif_caixa').select('nif, dado').eq('order_id', orderId).maybeSingle()
      caixa = r?.data ?? null
    } catch (_e) { caixa = null }
    const base = (regra && typeof regra === 'object') ? regra as Record<string, unknown> : null
    const regraFinal = base && caixa?.nif ? { ...base, nif: caixa.nif } : base
    const res = compararNifTalao(regraFinal, limparNif(nifLido), pareceTalao)
    return { ...res, estafeta_disse: caixa ? (caixa.dado ?? null) : null }
  } catch (e) {
    return { aplica: false, erro: String(e) }
  }
}

/** O texto do aviso ao admin, ou null quando não há nada a avisar. */
export function resumoAvisoNif(v: VerificacaoNif): string | null {
  if (!v.aplica || v.ok) return null
  if (v.estafeta_disse === false) return null // já avisado por nif_nao_dado_na_caixa
  // Revisão M10: NIF que o robô não conseguiu ler não é acusação; o talão fica
  // só marcado para revisão (ocr_flagged). Aviso só quando o talão mostra OUTRO NIF.
  if (v.motivo === 'nif_em_falta') return null
  return `O talão mostra o NIF ${v.talao}, mas o estafeta tinha de dar o ${v.esperado}`
}

/** Manda o aviso `nif_talao_diferente` (uma linha em admin_notifications). Nunca lança. */
export async function avisarNifDoTalao(sb: Cliente, orderId: string, v: VerificacaoNif): Promise<boolean> {
  const resumo = resumoAvisoNif(v)
  if (!resumo || !v.aplica || v.ok) return false
  try {
    const { error } = await sb.rpc('notify_admin_event', {
      p_event_type: 'nif_talao_diferente',
      p_severity: 'medium',
      p_summary: resumo,
      p_entity_type: 'order',
      p_entity_id: orderId,
      p_payload: { esperado: v.esperado, talao: v.talao, motivo: v.motivo, estafeta_disse: v.estafeta_disse ?? null },
      p_deep_link: null,
    })
    if (error) {
      console.error('[ocr-receipt] aviso nif_talao_diferente falhou:', error.message ?? error)
      return false
    }
    return true
  } catch (e) {
    console.error('[ocr-receipt] aviso nif_talao_diferente exception:', e)
    return false
  }
}
