// deno test supabase/functions/ocr-receipt/nif_talao_test.ts
// M10 b2-nif (09/11/2026): o NIF impresso no talão contra o NIF que o estafeta tinha de dar na
// caixa. Banco de brincar (nada sai do PC).
import {
  avisarNifDoTalao, compararNifTalao, escolherNifCliente, limparNif, resumoAvisoNif, verificarNifDoTalao,
} from './nif_talao.ts'

function igual(a: unknown, b: unknown, msg: string) {
  if (JSON.stringify(a) !== JSON.stringify(b)) throw new Error(`${msg}: ${JSON.stringify(a)} != ${JSON.stringify(b)}`)
}

/** Banco de brincar: a regra, a resposta do estafeta e os avisos que ficariam gravados. */
function banco(opts: { regra?: unknown; regraErro?: string; caixa?: { nif: string; dado: boolean } | null }) {
  const avisos: Record<string, unknown>[] = []
  const sb = {
    rpc(fn: string, args: Record<string, unknown>) {
      if (fn === '_nif_caixa_regra') {
        igual(args, { p_order_id: 'p1' }, 'parâmetros da regra')
        return Promise.resolve(opts.regraErro
          ? { data: null, error: { message: opts.regraErro } }
          : { data: opts.regra ?? null, error: null })
      }
      if (fn === 'notify_admin_event') {
        avisos.push(args)
        return Promise.resolve({ data: 'id', error: null })
      }
      throw new Error(`rpc inesperada ${fn}`)
    },
    from(t: string) {
      igual(t, 'order_nif_caixa', 'tabela')
      return {
        select: () => ({
          eq: () => ({ maybeSingle: () => Promise.resolve({ data: opts.caixa ?? null, error: null }) }),
        }),
      }
    },
  }
  return { sb, avisos }
}

const BORA = { aplica: true, tipo: 'bora', nif: '519686233' }

Deno.test('limparNif: só 9 dígitos, com ou sem PT e espaços', () => {
  igual(limparNif('PT 265 148 502'), '265148502', 'PT e espaços')
  igual(limparNif(519686233), '519686233', 'número')
  igual(limparNif('12345'), null, 'curto')
  igual(limparNif(null), null, 'null')
  igual(limparNif('Consumidor final'), null, 'consumidor final')
})

Deno.test('comparar: igual passa, diferente e em falta acusam; parceiro e foto do saco não', () => {
  igual(compararNifTalao(BORA, '519686233', true), { aplica: true, ok: true, esperado: '519686233', talao: '519686233' }, 'igual')
  igual(compararNifTalao(BORA, '265148502', true),
    { aplica: true, ok: false, motivo: 'nif_diferente', esperado: '519686233', talao: '265148502' }, 'diferente')
  igual(compararNifTalao(BORA, null, true),
    { aplica: true, ok: false, motivo: 'nif_em_falta', esperado: '519686233', talao: null }, 'em falta')
  igual(compararNifTalao({ aplica: false, loja_parceira: true }, null, true), { aplica: false }, 'loja parceira')
  igual(compararNifTalao(BORA, null, false), { aplica: false }, 'não parece talão')
  igual(compararNifTalao(null, null, true), { aplica: false }, 'sem regra')
})

Deno.test('diferente: talão marcado e aviso nif_talao_diferente com os dois números', async () => {
  const { sb, avisos } = banco({ regra: BORA, caixa: { nif: '519686233', dado: true } })
  const v = await verificarNifDoTalao(sb, 'p1', 'NIF: 999 999 990', true)
  igual(v.aplica && !v.ok ? v.motivo : null, 'nif_diferente', 'motivo')
  igual(await avisarNifDoTalao(sb, 'p1', v), true, 'avisou')
  igual(avisos.length, 1, 'um aviso')
  igual(avisos[0].p_event_type, 'nif_talao_diferente', 'evento')
  igual(avisos[0].p_entity_id, 'p1', 'pedido')
  igual((avisos[0].p_payload as Record<string, unknown>).esperado, '519686233', 'esperado')
  igual((avisos[0].p_payload as Record<string, unknown>).talao, '999999990', 'talão')
  igual(avisos[0].p_summary, 'O talão mostra o NIF 999999990, mas o estafeta tinha de dar o 519686233', 'texto')
})

Deno.test('o NIF que o estafeta confirmou manda sobre a regra de agora', async () => {
  // O cliente pôs o NIF depois da compra: a regra já diz "cliente", mas na caixa deu-se o da Bora.
  const { sb } = banco({ regra: { aplica: true, tipo: 'cliente', nif: '265148502' }, caixa: { nif: '519686233', dado: true } })
  const v = await verificarNifDoTalao(sb, 'p1', '519686233', true)
  igual(v.aplica && v.ok, true, 'bate com o que foi dado')
})

Deno.test('estafeta já disse "Não consegui": talão marcado mas sem aviso repetido', async () => {
  const { sb, avisos } = banco({ regra: BORA, caixa: { nif: '519686233', dado: false } })
  const v = await verificarNifDoTalao(sb, 'p1', null, true)
  igual(v.aplica && !v.ok, true, 'acusado')
  igual(resumoAvisoNif(v), null, 'sem texto de aviso')
  igual(await avisarNifDoTalao(sb, 'p1', v), false, 'não avisa')
  igual(avisos.length, 0, 'nenhum aviso')
})

Deno.test('sem a migração no servidor: não faz nada e não lança', async () => {
  const { sb, avisos } = banco({ regraErro: 'Could not find the function public._nif_caixa_regra' })
  const v = await verificarNifDoTalao(sb, 'p1', null, true)
  igual(v.aplica, false, 'não se aplica')
  igual(await avisarNifDoTalao(sb, 'p1', v), false, 'não avisa')
  igual(avisos.length, 0, 'nenhum aviso')
})

Deno.test('index.ts liga tudo: pede buyer_nif, marca o talão e avisa', () => {
  const src = Deno.readTextFileSync(new URL('./index.ts', import.meta.url))
  for (const k of [
    '"buyer_nif": string|null',
    "NUNCA o NIF/NIPC da loja",
    'verificarNifDoTalao(supabase, orderId, parsed?.buyer_nif ?? null, looksLikeReceipt,',
    "{ seller: parsed?.seller_nif ?? null, nifs: parsed?.nifs ?? [] })",
    '"seller_nif": string|null, "nifs": [string]',
    'buyer_nif: buyerNifFinal, nif_check: nifCheck',
    'de depósito de embalagens (DEPOSITO, VALOR DE DEPOSITO, VASILHAME, SDR, VOLTA)',
    'ocr_flagged: legacyFlagged || !looksLikeReceipt || nifFlagged',
    'avisarNifDoTalao(supabase, orderId, nifCheck)',
    'buyer_nif: buyerNif',
  ]) {
    if (!src.includes(k)) throw new Error(`falta em index.ts: ${k}`)
  }
})

// v13 (09/11/2026) — talão do KFC 2190210d: "N. Contrib. 502604735" (loja) e "NIF:123456789"
// (cliente) logo a seguir aos dados da empresa; o modelo devolveu buyer_nif=null.
Deno.test('escolherNifCliente: o NIF esperado impresso no talão ganha, nunca o da loja', () => {
  igual(escolherNifCliente(null, '502604735', ['502604735', '123456789'], '123456789'), '123456789', 'KFC 09/11')
  igual(escolherNifCliente('502604735', '502604735', ['502604735', '123456789'], null), '123456789', 'buyer = loja → o outro')
  igual(escolherNifCliente('123456789', '502604735', [], null), '123456789', 'buyer lido')
  igual(escolherNifCliente(null, '502604735', ['502604735'], '123456789'), null, 'só o da loja → em falta')
  igual(escolherNifCliente(null, null, [], '123456789'), null, 'nada impresso')
  igual(escolherNifCliente('PT 123 456 789', null, null, null), '123456789', 'limpa espaços e PT')
  igual(escolherNifCliente('111111111', '502604735', ['111111111', '123456789'], '123456789'), '123456789', 'esperado ganha a um lido diferente')
})

Deno.test('verificarNifDoTalao com os NIF impressos: o caso do KFC fica ok', async () => {
  const { sb, avisos } = banco({ regra: { aplica: true, tipo: 'cliente', nif: '123456789' } })
  const v = await verificarNifDoTalao(sb, 'p1', null, true, { seller: '502604735', nifs: ['502604735', '123456789'] })
  igual(v.aplica && v.ok, true, 'ok')
  igual((v as { talao?: string }).talao, '123456789', 'NIF do cliente')
  igual(await avisarNifDoTalao(sb, 'p1', v), false, 'sem aviso')
  igual(avisos.length, 0, 'nenhum aviso')
})

Deno.test('verificarNifDoTalao: talão só com o NIF da loja continua em falta (sem acusar a loja)', async () => {
  const { sb } = banco({ regra: { aplica: true, tipo: 'cliente', nif: '123456789' } })
  const v = await verificarNifDoTalao(sb, 'p1', '502604735', true, { seller: '502604735', nifs: ['502604735'] })
  igual(v.aplica && !v.ok && (v as { motivo?: string }).motivo, 'nif_em_falta', 'em falta, não "diferente"')
})
