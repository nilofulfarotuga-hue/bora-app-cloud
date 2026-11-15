// deno test --no-check --no-lock --cached-only supabase/functions/weekly-closeout-digest/logica_test.ts
// Recibos verdes (recibos-verdes-15-11, R1b): a trava no recibo semanal — sem rede.
// A trava falsa imita prestador_recibo_trava (CONTRATO.md, secção 5.3); a regra da linha é a da chave
// "retido" das listas do painel (_recibo_enriquecer): Bora paga + retido + não solta + saldo > 0.
import { assert, assertEquals } from 'https://deno.land/std@0.224.0/assert/mod.ts'
import {
  blocoReceberHtml,
  fraseRetido,
  linhaRetida,
  NAO_SE_PERDE,
  podeSerRetida,
  saldoDaSemanaCents,
  segundaLisboa,
  type Trava,
} from './logica.ts'

const FRASE_NOVEMBRO =
  'O teu pagamento desta semana fica guardado até anexares o recibo verde de novembro de 2026 na app, em Ganhos.'
const RETIDO: Trava = {
  retido: true,
  motivo: 'Retido — falta o recibo verde de novembro de 2026',
  texto_semanal: FRASE_NOVEMBRO,
  meses_em_falta: [{ nome: 'novembro de 2026' }],
}
const LIVRE: Trava = { retido: false }
const PAGA = { subject_type: 'driver', subject_id: 'd1', direction: 'bora_pays', net_cents: 1830, week_start_at: '2026-12-07T00:00:00Z' }

Deno.test('segunda-feira em Lisboa (igual a _recibo_semana do servidor)', () => {
  assertEquals(segundaLisboa('2026-12-07T00:00:00Z'), '2026-12-07') // segunda
  assertEquals(segundaLisboa('2026-12-13T23:30:00Z'), '2026-12-07') // domingo à noite (inverno, Lisboa = UTC)
  assertEquals(segundaLisboa('2026-06-07T23:30:00Z'), '2026-06-08') // domingo 23:30 UTC = segunda 00:30 em Lisboa (verão)
  assertEquals(segundaLisboa('2026-10-18T23:00:00+00:00'), '2026-10-19') // como a API devolve week_start_at (verão)
  assertEquals(segundaLisboa('2026-12-09'), '2026-12-07') // data simples (quarta)
  assertEquals(segundaLisboa('2027-01-01T10:00:00Z'), '2026-12-28') // atravessa o ano
  assertEquals(segundaLisboa('não é data'), null)
})

Deno.test('só as linhas em que a Bora paga a estafeta, limpeza ou lavagem podem ficar guardadas', () => {
  assert(podeSerRetida(PAGA))
  assert(podeSerRetida({ ...PAGA, subject_type: 'cleaner' }))
  assert(podeSerRetida({ ...PAGA, subject_type: 'washer' }))
  assert(!podeSerRetida({ ...PAGA, subject_type: 'partner' })) // lojas: fora da trava
  assert(!podeSerRetida({ ...PAGA, direction: 'owes_bora' })) // quem deve continua a ser cobrado
  assert(!podeSerRetida({ ...PAGA, direction: 'zero', net_cents: 0 }))
  assert(!podeSerRetida({ ...PAGA, net_cents: 0 }))
  assert(!podeSerRetida(null))
})

Deno.test('regra da linha retida = chave "retido" do painel', () => {
  assertEquals(linhaRetida(PAGA, RETIDO, { solto: false, saldoCents: 1830 }), true)
  assertEquals(linhaRetida(PAGA, RETIDO, {}), true) // saldo desconhecido: não se prova a compensação
  assertEquals(linhaRetida(PAGA, LIVRE, { saldoCents: 1830 }), false) // recibo anexado / trava desligada / demo
  assertEquals(linhaRetida(PAGA, null, { saldoCents: 1830 }), false) // trava ainda não existe no servidor
  assertEquals(linhaRetida(PAGA, RETIDO, { solto: true, saldoCents: 1830 }), false) // o admin soltou a semana
  assertEquals(linhaRetida(PAGA, RETIDO, { saldoCents: 0 }), false) // deve tanto como recebe: acerto de dívida
  assertEquals(linhaRetida(PAGA, RETIDO, { saldoCents: -500 }), false)
  assertEquals(linhaRetida({ ...PAGA, direction: 'owes_bora' }, RETIDO, { saldoCents: 1830 }), false)
})

Deno.test('saldo da semana: vista unificada + Casa da mesma semana, sem cancelados', () => {
  const casa = [
    { direction: 'handyman_to_bora', net_payout_cents: 3000, status: 'pending', week_start_at: '2026-12-07T00:00:00Z' },
    { direction: 'bora_to_handyman', net_payout_cents: 700, status: 'pending', week_start_at: '2026-12-08T09:00:00Z' },
    { direction: 'handyman_to_bora', net_payout_cents: 9999, status: 'cancelled', week_start_at: '2026-12-07T00:00:00Z' },
    { direction: 'bora_to_handyman', net_payout_cents: 5000, status: 'pending', week_start_at: '2026-11-30T00:00:00Z' },
  ]
  assertEquals(saldoDaSemanaCents([{ total_cents: 1830 }], casa, '2026-12-07'), 1830 - 3000 + 700)
  assertEquals(saldoDaSemanaCents([{ total_cents: '1830' }, { total_cents: null }], [], '2026-12-07'), 1830)
  assertEquals(saldoDaSemanaCents(null, null, '2026-12-07'), 0)
})

Deno.test('a frase do recibo semanal', () => {
  assertEquals(fraseRetido(RETIDO), FRASE_NOVEMBRO) // a do servidor manda
  assertEquals(fraseRetido({ retido: true, meses_em_falta: [{ nome: 'novembro de 2026' }] }), FRASE_NOVEMBRO)
  assertEquals(
    fraseRetido({ retido: true, meses_em_falta: [{ nome: 'novembro de 2026' }, { nome: 'dezembro de 2026' }] }),
    'O teu pagamento desta semana fica guardado até anexares o recibo verde de novembro de 2026, dezembro de 2026 na app, em Ganhos.',
  )
  assertEquals(
    fraseRetido({ retido: true }),
    'O teu pagamento desta semana fica guardado até anexares o recibo verde em falta na app, em Ganhos.',
  )
})

Deno.test('o bloco "A receber" não muda o valor; sem trava fica igual à v8', () => {
  const antes = '<div style="background:#F0FDF4;border:1px solid #BBF7D0;border-radius:10px;padding:14px;margin-top:16px">' +
    '<div style="font-weight:700;color:#166534">A receber da Bora: €18,30</div>' +
    '<div style="margin-top:6px;color:#14532D">A transferência é feita na segunda-feira.</div></div>'
  assertEquals(blocoReceberHtml('€18,30', null), antes)
  const retido = blocoReceberHtml('€18,30', FRASE_NOVEMBRO)
  assert(retido.includes('A receber da Bora: €18,30'))
  assert(retido.includes(FRASE_NOVEMBRO))
  assert(retido.includes(NAO_SE_PERDE))
  assert(!retido.includes('A transferência é feita na segunda-feira'))
  assert(!blocoReceberHtml('€1', '<b>x</b>').includes('<b>x</b>')) // escapa
})
