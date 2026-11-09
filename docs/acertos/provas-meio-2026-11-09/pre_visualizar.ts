// Pré-visualização do comprovativo semanal SEM enviar nada a ninguém.
// Missão pendencias-2026-11-09, Bloco B.
//
// Corre a Edge settlement-receipt TAL E QUAL (o handler do Deno.serve, caminho despacharFila),
// com: base falsa (supabase_falso.ts, pelo mapa.json), fetch trocado (o Resend nunca é
// contactado — qualquer outro endereço rebenta) e chaves falsas no env. Sem FIREBASE_* no env,
// a Edge não prepara o FCM: nenhum push sai. O texto do push lê-se pela função exportada
// corpoPushComprovativo (a mesma que o despacharFila usa).
// Guarda o HTML dos 3 casos pedidos (transferência, MB Way com número, sem meio).
//
// Uso:
//   deno run --allow-env --allow-read --allow-write --import-map=mapa.json pre_visualizar.ts <index.ts> <pasta de saída | ->
// Com "-" não grava ficheiros (serve para correr a versão ANTIGA e ver que falha).
// deno-lint-ignore-file no-explicit-any

const [indexTs, saida] = Deno.args
const urlDoFicheiro = (p: string) => 'file:///' + Deno.realPathSync(p).replace(/\\/g, '/').replace(/^\/+/, '')

// --- env falso (nada real; sem FIREBASE_* de propósito) ---
Deno.env.set('SUPABASE_URL', 'https://projeto-falso.supabase.local')
Deno.env.set('SUPABASE_SECRET_KEYS', JSON.stringify({ default: 'sb_secret_falsa_de_teste' }))
Deno.env.set('RESEND_API_KEY', 're_falsa_de_teste')

// --- a fila: os 3 casos pedidos + casos de fronteira (só os 3 primeiros viram ficheiro) ---
const WS = '2026-11-02T00:00:00+00:00'
const linha = (id: string, o: any) => ({
  id, attempts: 0, status: 'pending', sent_at: null, week_start_at: WS, html: null, last_error: null, ...o,
})
;(globalThis as any).__base = {
  boraMbway: '910000000',
  chamadas: [] as any[],
  atualizacoes: [] as any[],
  fila: [
    linha('1-transferencia', { kind: 'paid', subject_type: 'partner', subject_id: 'boom-burger-guarda', subject_name: 'Boom! Burger',
      to_email: 'parceiro@exemplo.pt', amount_cents: 1360, payment_reference: 'Transferência bancária 09/11/2026' }),
    linha('2-mbway-com-numero', { kind: 'paid', subject_type: 'driver', subject_id: 'estafeta-exemplo', subject_name: 'Estafeta Exemplo',
      to_email: 'estafeta@exemplo.pt', amount_cents: 3213, payment_reference: 'MB Way 912 345 678 · fecho 02/11-08/11' }),
    linha('3-sem-meio', { kind: 'paid', subject_type: 'cleaner', subject_id: 'limpeza-exemplo', subject_name: 'Limpeza Exemplo',
      to_email: 'limpeza@exemplo.pt', amount_cents: 2000, payment_reference: null }),
    linha('4-ambiguo', { kind: 'paid', subject_type: 'partner', subject_id: 'parceiro-ambiguo', subject_name: 'Parceiro Ambíguo',
      to_email: 'ambiguo@exemplo.pt', amount_cents: 500, payment_reference: 'Pago pelo Danilo (MB Way/transferência)' }),
    linha('5-stripe', { kind: 'paid', subject_type: 'provider', subject_id: 'barbearia-exemplo', subject_name: 'Barbearia Exemplo',
      to_email: 'barbearia@exemplo.pt', amount_cents: 900, payment_reference: 'Stripe' }),
    linha('6-recebido-mbway-sem-numero', { kind: 'received', subject_type: 'washer', subject_id: 'lavador-exemplo', subject_name: 'Lavador Exemplo',
      to_email: 'lavador@exemplo.pt', amount_cents: -500, payment_reference: 'MB Way 09/11/2026' }),
    linha('7-recebido-sem-meio', { kind: 'received', subject_type: 'driver', subject_id: 'estafeta-deve', subject_name: 'Estafeta Deve',
      to_email: 'deve@exemplo.pt', amount_cents: -397, payment_reference: null }),
  ],
}

// --- fetch trocado: nada sai da máquina ---
const emails: any[] = []
globalThis.fetch = (async (url: any, init: any = {}) => {
  const u = String(url)
  if (u === 'https://api.resend.com/emails') {
    emails.push(JSON.parse(init.body))
    return new Response(JSON.stringify({ id: 'falso' }), { status: 200 })
  }
  throw new Error('fetch inesperado (bloqueado na prova): ' + u)
}) as any

// --- apanhar o handler do Deno.serve e chamá-lo como o gatilho chama ---
let handler: any = null
;(Deno as any).serve = (h: any) => { handler = h; return { finished: Promise.resolve() } }
const modulo: any = await import(urlDoFicheiro(indexTs))
if (!handler) throw new Error('a Edge não registou Deno.serve')
const res = await handler(new Request('https://projeto-falso.supabase.local/functions/v1/settlement-receipt', {
  method: 'POST',
  headers: { apikey: 'sb_secret_falsa_de_teste', authorization: 'Bearer sb_secret_falsa_de_teste', 'content-type': 'application/json' },
  body: JSON.stringify({ trigger: 'status_change' }),
}))
const corpo = await res.json()
console.log('resposta da Edge: HTTP ' + res.status + ' ' + JSON.stringify({ na_fila: corpo.na_fila, enviados: corpo.enviados, falhados: corpo.falhados }))

// --- resultado por caso ---
const base = (globalThis as any).__base
// <b> sai sem espaço (é dentro da frase); as outras etiquetas separam blocos.
const textoSimples = (html: string) => html.replace(/<\/?b>/g, '').replace(/<[^>]+>/g, ' ').replace(/\s+/g, ' ').trim()
const ficheiros: Record<string, string> = {
  '1-transferencia': 'comprovativo_1_transferencia.html',
  '2-mbway-com-numero': 'comprovativo_2_mbway_com_numero.html',
  '3-sem-meio': 'comprovativo_3_sem_meio.html',
}
const resumo: any[] = []
for (const r of base.fila) {
  const at = base.atualizacoes.find((a: any) => a.id === r.id)
  const html: string = at?.html ?? ''
  const plano = textoSimples(html)
  const caixa = (plano.match(/(?:Recebeu|Recebemos) €[\d,]+ (.*?) Valor €/) ?? [])[1] ?? ''
  const meioLinha = (plano.match(/ Meio (.*?) Guarde /) ?? [])[1] ?? '(sem linha Meio)'
  const push = typeof modulo.corpoPushComprovativo === 'function' ? modulo.corpoPushComprovativo(r) : '(versão sem corpoPushComprovativo)'
  const email = emails.find((e) => e.to?.[0] === r.to_email)
  resumo.push({ caso: r.id, estado: at?.status, email_para: email?.to?.[0] ?? null, caixa, meio: meioLinha, push, diz_mbway: /MB Way/.test(html) })
  if (saida && saida !== '-' && ficheiros[r.id]) await Deno.writeTextFile(saida + '/' + ficheiros[r.id], html)
}
for (const l of resumo) console.log(JSON.stringify(l))
console.log('emails apanhados pelo fetch falso (nenhum saiu): ' + emails.length)

// --- veredicto ---
const por = (id: string) => resumo.find((l) => l.caso === id)
const checks: [string, boolean][] = [
  ['1 transferência diz "Enviado por transferência bancária" e não diz MB Way', por('1-transferencia').caixa === 'Enviado por transferência bancária.' && !por('1-transferencia').diz_mbway],
  ['2 MB Way com número', por('2-mbway-com-numero').caixa === 'Enviado por MB Way para 912345678.'],
  ['3 sem meio diz "Pagamento efetuado" e não diz MB Way', por('3-sem-meio').caixa === 'Pagamento efetuado.' && !por('3-sem-meio').diz_mbway],
  ['4 ambíguo (MB Way/transferência) não inventa', por('4-ambiguo').caixa === 'Pagamento efetuado.'],
  ['5 Stripe', por('5-stripe').caixa === 'Enviado por Stripe.'],
  ['6 recebido MB Way sem número (a data não vira número)', por('6-recebido-mbway-sem-numero').caixa.startsWith('Pago por MB Way. ')],
  ['7 recebido sem meio não diz MB Way', !por('7-recebido-sem-meio').diz_mbway],
  ['push 1 diz transferência', por('1-transferencia').push === 'A Bora pagou-lhe €13,60 por transferência bancária, referente à semana de 02/11.'],
  ['push 2 diz MB Way para o número', por('2-mbway-com-numero').push === 'A Bora pagou-lhe €32,13 por MB Way para 912345678, referente à semana de 02/11.'],
  ['push 3 sem meio não inventa', por('3-sem-meio').push === 'A Bora pagou-lhe €20,00, referente à semana de 02/11.'],
  ['7 emails apanhados, todos marcados sent', emails.length === 7 && resumo.every((l) => l.estado === 'sent')],
]
let tudo = true
for (const [nome, ok] of checks) { console.log((ok ? 'OK    ' : 'FALHA ') + nome); if (!ok) tudo = false }
console.log('VEREDICTO: ' + (tudo ? 'TUDO CERTO' : 'HÁ FALHAS'))
Deno.exit(tudo ? 0 : 1)
