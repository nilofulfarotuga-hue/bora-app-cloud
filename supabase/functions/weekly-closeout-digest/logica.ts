// supabase/functions/weekly-closeout-digest/logica.ts
// Recibos verdes (missão recibos-verdes-15-11, R1b, 15/11/2026) — a parte pura da trava no recibo
// semanal. Não fala com a rede: recebe a linha do weekly_digest_log, a resposta de
// prestador_recibo_trava (CONTRATO.md, secção 5.3) e o que a função leu (soltura, saldo da semana).
// A regra é a mesma das listas do painel (_recibo_enriquecer, "retido"): a linha só fica guardada
// quando a Bora paga, a pessoa está retida, a semana não foi solta à mão e a pessoa não deve mais do
// que recebe nessa semana. NENHUM valor muda: só o texto do recibo.
//
// Testes (sem rede): deno test --no-check --no-lock --cached-only supabase/functions/weekly-closeout-digest/logica_test.ts

// Os mesmos tipos de linha que a trava olha no "Acertos da semana" (_recibo_enriquecer, modo semanal).
export const TIPOS_COM_TRAVA = ['driver', 'cleaner', 'washer']

export const NAO_SE_PERDE = 'Não se perde: sai todo junto no primeiro pagamento depois de o anexares.'

export type LinhaDigest = {
  subject_type?: string | null
  subject_id?: string | null
  direction?: string | null
  net_cents?: number | string | null
  week_start_at?: string | null
}
export type Trava = {
  retido?: boolean | null
  motivo?: string | null
  texto_semanal?: string | null
  meses_em_falta?: { nome?: string | null }[] | null
}
export type LinhaVista = { total_cents?: number | string | null }
export type AcertoCasa = {
  direction?: string | null
  net_payout_cents?: number | string | null
  status?: string | null
  week_start_at?: string | null
}

function esc(s: unknown): string {
  return String(s ?? '').replace(/&/g, '&amp;').replace(/</g, '&lt;')
    .replace(/>/g, '&gt;').replace(/"/g, '&quot;').replace(/'/g, '&#39;')
}

/**
 * Segunda-feira (em Lisboa) da semana de uma data — a mesma conta do servidor
 * (_recibo_semana: date_trunc('week', ts AT TIME ZONE 'Europe/Lisbon')). Devolve 'AAAA-MM-DD' ou null.
 */
export function segundaLisboa(iso: unknown): string | null {
  const d = new Date(String(iso ?? ''))
  if (isNaN(d.getTime())) return null
  const p = new Intl.DateTimeFormat('en-GB', {
    timeZone: 'Europe/Lisbon', year: 'numeric', month: '2-digit', day: '2-digit',
  }).formatToParts(d)
  const g = (t: string) => Number(p.find((x) => x.type === t)?.value)
  const local = new Date(Date.UTC(g('year'), g('month') - 1, g('day')))
  local.setUTCDate(local.getUTCDate() - ((local.getUTCDay() + 6) % 7))
  return local.toISOString().slice(0, 10)
}

/** A linha é das que a trava pode segurar: estafeta, limpeza ou lavagem, e a Bora é que paga. */
export function podeSerRetida(r: LinhaDigest | null | undefined): boolean {
  return !!r && TIPOS_COM_TRAVA.includes(String(r.subject_type)) && r.direction === 'bora_pays' &&
    Math.abs(Number(r.net_cents ?? 0) || 0) > 0
}

/**
 * Saldo da pessoa na semana, em cêntimos (a conta de _recibo_semana_saldo_cents): a vista do acerto
 * unificado (estafeta + limpeza + lavagem, já com a dívida por abater) mais a Casa (a Bora paga = +,
 * a pessoa paga = −; cancelados fora). <= 0 quer dizer que a pessoa deve à Bora nessa semana.
 */
export function saldoDaSemanaCents(
  vista: LinhaVista[] | null | undefined,
  casa: AcertoCasa[] | null | undefined,
  semana: string | null,
): number {
  let s = 0
  for (const v of vista ?? []) s += Number(v?.total_cents ?? 0) || 0
  for (const a of casa ?? []) {
    if (!a || a.status === 'cancelled') continue
    if (segundaLisboa(a.week_start_at) !== semana) continue
    const c = Number(a.net_payout_cents ?? 0) || 0
    if (a.direction === 'bora_to_handyman') s += c
    else if (a.direction === 'handyman_to_bora') s -= c
  }
  return Math.round(s)
}

/**
 * A linha fica mesmo guardada? Igual à chave "retido" das listas do painel: a Bora paga, a pessoa
 * está retida, a semana não foi solta à mão e não é só acerto de dívida (saldo da semana > 0).
 * Saldo desconhecido (null) = não se prova a compensação, por isso conta como guardada.
 */
export function linhaRetida(
  r: LinhaDigest | null | undefined,
  trava: Trava | null | undefined,
  ctx: { solto?: boolean; saldoCents?: number | null } = {},
): boolean {
  if (!podeSerRetida(r)) return false
  if (!trava || trava.retido !== true) return false
  if (ctx.solto === true) return false
  if (typeof ctx.saldoCents === 'number' && Number.isFinite(ctx.saldoCents) && ctx.saldoCents <= 0) return false
  return true
}

/**
 * A frase do recibo semanal. Vem do servidor (texto_semanal); se faltar, monta-se com os meses em falta:
 * "O teu pagamento desta semana fica guardado até anexares o recibo verde de [mês] na app, em Ganhos."
 */
export function fraseRetido(trava: Trava | null | undefined): string {
  const t = trava?.texto_semanal
  if (typeof t === 'string' && t.trim()) return t.trim()
  const nomes = (Array.isArray(trava?.meses_em_falta) ? trava!.meses_em_falta! : [])
    .map((m) => String(m?.nome ?? '').trim()).filter(Boolean)
  return 'O teu pagamento desta semana fica guardado até anexares ' +
    (nomes.length ? 'o recibo verde de ' + nomes.join(', ') : 'o recibo verde em falta') + ' na app, em Ganhos.'
}

/**
 * O bloco "A receber da Bora" do recibo semanal. `net` já vem formatado (o mesmo valor de sempre).
 * Sem frase = exatamente o bloco da v8. Com frase = o mesmo valor, e em vez de "a transferência é
 * feita na segunda-feira" diz que o pagamento fica guardado até anexar o recibo verde.
 */
export function blocoReceberHtml(net: string, frase: string | null | undefined): string {
  return '<div style="background:#F0FDF4;border:1px solid #BBF7D0;border-radius:10px;padding:14px;margin-top:16px">' +
    '<div style="font-weight:700;color:#166534">A receber da Bora: ' + net + '</div>' +
    (frase
      ? '<div style="margin-top:6px;color:#9A3412;font-weight:600">' + esc(frase) + '</div>' +
        '<div style="margin-top:4px;color:#7C2D12;font-size:13px">' + esc(NAO_SE_PERDE) + '</div></div>'
      : '<div style="margin-top:6px;color:#14532D">A transferência é feita na segunda-feira.</div></div>')
}
