// supabase/functions/monthly-partner-statement/logica.ts
// Recibos verdes (missão recibos-verdes-15-11, R1b, 15/11/2026) — a parte pura do email do dia 1 a
// cada prestador. Não fala com a rede nem com o Supabase: recebe o que a RPC
// prestador_recibo_mensal_resumo devolve (contrato: docs/propostas/recibos-verdes-15-11/CONTRATO.md)
// e decide quem recebe, se a pessoa já recebeu e o que o email diz. Nenhum valor é calculado aqui:
// o total, as linhas, a descrição e os textos (prazo, retenção, IVA, anexar) vêm da função.
//
// Testes (sem rede): deno test --no-check --no-lock --cached-only supabase/functions/monthly-partner-statement/logica_test.ts

const GREEN = '#16A34A'
const META = '<meta charset="utf-8">'
// Quebra de linha sem barra invertida no código (cicatriz do weekly-closeout-digest v8: o deploy por MCP).
const NL = String.fromCharCode(10)
const NOMES_MES = ['', 'janeiro', 'fevereiro', 'março', 'abril', 'maio', 'junho', 'julho', 'agosto',
  'setembro', 'outubro', 'novembro', 'dezembro']
const NOME_SERVICO: Record<string, string> = {
  entregas: 'Entregas', limpeza: 'Limpezas', lavagem: 'Lavagens auto', casa: 'Casa e Manutenção',
}

// Textos de recurso — iguais aos da função (só entram se a resposta vier sem eles).
const PRAZO_RECURSO = 'Fatura-recibo até ao 5.º dia útil seguinte ao recebimento (art. 36.º CIVA / art. 115.º CIRS)'
const MENCAO_RECURSO = 'Sem retenção, nos termos do n.º 1 do artigo 101.º-B do Código do IRS'
const TAXA_RECURSO = '11,5%'
const LIMITE_RECURSO = '15.000 EUR'
const IVA_RECURSO = 'IVA: isento ao abrigo do artigo 53.º do CIVA, se for o seu caso; o contabilista confirma.'

export type LinhaServico = { servico?: string; nome?: string; quantidade?: number | string; valor?: number | string }
export type Prestador = {
  user_id: string
  nome?: string | null
  nif?: string | null
  email?: string | null
  linhas?: LinhaServico[] | null
  total?: number | string | null
  descricao?: string | null
  demo?: boolean
  conta_dono?: boolean
  proprio_adquirente?: boolean
  precisa_recibo?: boolean
  conta_para_trava?: boolean
  estado?: string
}
export type Adquirente = { tipo?: string; nome?: string; nif?: string; morada?: string }
export type Regras = {
  descricao_modelo?: string
  prazo_texto?: string
  anexar_ate?: string
  anexar_texto?: string
  conta_para_trava?: boolean
  iva_texto?: string
  retencao?: { regra?: string; mencao_dispensa?: string; taxa_se_aplicavel?: string; limite_anual?: string }
}
export type Resumo = {
  ano: number
  mes: number
  nome_mes?: string
  adquirente?: Adquirente
  regras?: Regras
  prestadores?: Prestador[] | null
}
export type RegistoEnvio = { email_status?: string | null } | null | undefined
export type Saltado = { prestador: Prestador; motivo: 'conta_dono' | 'demo'; erro: string }

export function eur(v: unknown): string {
  return (Number(v ?? 0) || 0).toFixed(2).replace('.', ',') + ' €'
}

export function esc(s: unknown): string {
  return String(s ?? '').replace(/&/g, '&amp;').replace(/</g, '&lt;')
    .replace(/>/g, '&gt;').replace(/"/g, '&quot;').replace(/'/g, '&#39;')
}

/** '2026-12-10' → '10/12/2026' ('' se não for uma data). */
export function dataPt(iso: unknown): string {
  const m = /^([0-9]{4})-([0-9]{2})-([0-9]{2})/.exec(String(iso ?? ''))
  return m ? m[3] + '/' + m[2] + '/' + m[1] : ''
}

export function nomeDoMes(resumo: Resumo): string {
  return resumo?.nome_mes || NOMES_MES[Number(resumo?.mes) || 0] || ''
}

/**
 * Quem recebe o email do mês (precisa_recibo = true) e quem fica de fora com registo (conta do dono,
 * conta demo). UMA entrada por pessoa (user_id): estafeta e limpeza na mesma pessoa vêm numa linha só
 * da função; repetidos são ignorados por segurança. `filtroUserId` = reenvio de uma pessoa só.
 * Quem não trabalhou no mês (total 0) não entra em lado nenhum.
 */
export function separarPessoas(
  prestadores: Prestador[] | null | undefined,
  filtroUserId?: string | null,
): { enviar: Prestador[]; saltar: Saltado[] } {
  const vistos = new Set<string>()
  const enviar: Prestador[] = []
  const saltar: Saltado[] = []
  for (const p of prestadores ?? []) {
    const uid = String(p?.user_id ?? '').trim()
    if (!uid || vistos.has(uid)) continue
    if (filtroUserId && uid !== filtroUserId) continue
    vistos.add(uid)
    if (p.precisa_recibo === true) {
      enviar.push(p)
    } else if (p.proprio_adquirente === true) {
      saltar.push({ prestador: p, motivo: 'conta_dono', erro: 'conta do próprio Danilo (adquirente): sem recibo a si mesmo' })
    } else if (p.demo === true) {
      saltar.push({ prestador: p, motivo: 'demo', erro: 'conta de demonstração — sem extrato' })
    }
  }
  return { enviar, saltar }
}

/**
 * Nunca duas vezes à mesma pessoa no mesmo mês. O registo da pessoa é driver_monthly_statement_log
 * (user_id, ano, mes — serve qualquer prestador); um envio antigo à limpeza
 * (cleaner_monthly_statement_log, por cleaner_id) também conta. Só `force: true` (botão do painel)
 * reenvia. Envios falhados, saltados ou à espera do domínio voltam a tentar.
 */
export function jaEnviadoAPessoa(
  registoPessoa: RegistoEnvio,
  registosLimpeza: RegistoEnvio[] | null | undefined,
  force: boolean,
): boolean {
  if (force === true) return false
  if (registoPessoa?.email_status === 'sent') return true
  return (registosLimpeza ?? []).some((r) => r?.email_status === 'sent')
}

export function assuntoPrestador(resumo: Resumo): string {
  return 'O seu recibo verde de ' + nomeDoMes(resumo) + ' de ' + resumo?.ano + ' · Bora'
}

/** Retenção na fonte — só texto, com os valores que a função devolve (regras.retencao). */
export function textoRetencao(regras: Regras | null | undefined): string {
  const r = regras?.retencao ?? {}
  const mencao = String(r.mencao_dispensa || MENCAO_RECURSO)
  const limite = String(r.limite_anual || LIMITE_RECURSO)
  const taxa = String(r.taxa_se_aplicavel || TAXA_RECURSO)
  return 'Se este ano não passar ' + limite + ' nesta atividade, escreva no recibo: «' + mencao + '». ' +
    'Se passar, a empresa retém ' + taxa + ' e o contabilista confirma consigo.'
}

export function linhasDoPrestador(p: Prestador): { nome: string; quantidade: number; valor: number }[] {
  return (p?.linhas ?? [])
    .filter((l) => l && (Number(l.quantidade ?? 0) > 0 || Number(l.valor ?? 0) !== 0))
    .map((l) => ({
      nome: String(l.nome || NOME_SERVICO[String(l.servico)] || l.servico || 'Serviços'),
      quantidade: Number(l.quantidade ?? 0) || 0,
      valor: Number(l.valor ?? 0) || 0,
    }))
}

function descricaoDoPrestador(p: Prestador, regras: Regras): string {
  return String(p?.descricao || regras?.descricao_modelo || '').trim()
}

/** Os pedaços do email, iguais no HTML e no texto simples. */
function pedacos(p: Prestador, resumo: Resumo) {
  const adq = resumo?.adquirente ?? {}
  const regras = resumo?.regras ?? {}
  const sociedade = adq.tipo === 'sociedade'
  const anexarAte = dataPt(regras.anexar_ate)
  return {
    nomeMes: nomeDoMes(resumo),
    ano: resumo?.ano,
    sociedade,
    adq,
    total: eur(p?.total),
    linhas: linhasDoPrestador(p),
    descricao: descricaoDoPrestador(p, regras),
    rotuloNif: sociedade ? 'NIF (NIPC)' : 'NIF',
    retencao: sociedade ? textoRetencao(regras) : null,
    iva: sociedade ? String(regras.iva_texto || IVA_RECURSO) : null,
    ivaERetencaoAntes: sociedade ? null
      : 'IVA e retenção de IRS: dependem do seu regime nas Finanças; o contabilista da Bora confirma consigo.',
    prazo: String(regras.prazo_texto || PRAZO_RECURSO),
    anexar: sociedade
      ? (String(regras.anexar_texto || ('Anexe o recibo na app, em Ganhos' + (anexarAte ? ', até ' + anexarAte : '') + '.')) +
        ' Carregue em «Já passei o recibo», escreva o número e a data e junte o PDF ou uma foto do recibo.')
      : 'Depois carregue em «Já passei o recibo» na app, em Ganhos.',
    trava: p?.conta_para_trava === true && anexarAte
      ? 'Importante: se o recibo não estiver anexado até ' + anexarAte + ', os pagamentos semanais da Bora ' +
        'ficam guardados até o anexar. Não se perde nada: sai tudo junto no pagamento seguinte.'
      : null,
    semNif: !String(p?.nif ?? '').trim()
      ? 'Ainda não temos o seu NIF. Confirme-o na app, no seu perfil. Para passar recibos verdes precisa de ter atividade aberta nas Finanças.'
      : null,
  }
}

/** O email do dia 1 (HTML): um só recibo com tudo o que a pessoa fez no mês. */
export function htmlPrestador(p: Prestador, resumo: Resumo): string {
  const x = pedacos(p, resumo)
  const linha = (a: string, b: string, forte = false) =>
    '<tr><td style="padding:6px 0">' + a + '</td><td style="padding:6px 0;text-align:right' +
    (forte ? ';font-weight:800;color:' + GREEN : '') + '">' + b + '</td></tr>'
  const caixa = 'background:#F3F4F6;border-radius:8px;padding:10px;font-size:14px;margin:0 0 14px'
  const aviso = 'background:#FFF7ED;border:1px solid #FED7AA;border-radius:8px;padding:10px;font-size:13px;margin:0 0 12px'
  const par = (s: string) => '<p style="font-size:13px;margin:0 0 8px">' + s + '</p>'
  const servicos = x.linhas.map((l) => linha(esc(l.nome) + ' (' + esc(l.quantidade) + ')', eur(l.valor))).join('')
  return META + '<div style="font-family:system-ui,Arial,sans-serif;max-width:620px;margin:auto">' +
    '<div style="background:' + GREEN + ';color:#fff;padding:18px 20px;border-radius:12px 12px 0 0">' +
    '<div style="font-size:20px;font-weight:800">Bora</div>' +
    '<div style="opacity:.9">O seu recibo verde de ' + esc(x.nomeMes) + ' de ' + esc(x.ano) + '</div></div>' +
    '<div style="border:1px solid #eee;border-top:0;border-radius:0 0 12px 12px;padding:20px">' +
    '<p style="margin:0 0 12px">Olá <b>' + esc(p?.nome) + '</b>, em ' + esc(x.nomeMes) + ' ganhou <b>' + x.total +
    '</b> pela Bora. Passe <b>um só recibo verde</b> (fatura-recibo) no Portal das Finanças com tudo o que fez no mês:</p>' +
    '<table style="width:100%;border-collapse:collapse;font-size:14px;margin-bottom:12px">' +
    servicos + linha('Total do recibo', x.total, true) + '</table>' +
    '<p style="font-size:13px;color:#555;margin:0 0 4px">Passe o recibo a estes dados (copie tal e qual):</p>' +
    '<div style="' + caixa + '"><table style="width:100%;border-collapse:collapse;font-size:14px">' +
    linha('Nome', esc(x.adq.nome)) + linha(x.rotuloNif, esc(x.adq.nif)) + linha('Morada', esc(x.adq.morada)) +
    linha('Valor', x.total, true) + '</table></div>' +
    '<p style="font-size:13px;color:#555;margin:0 0 4px">Descrição para copiar:</p>' +
    '<p style="' + caixa + '">' + esc(x.descricao) + '</p>' +
    (x.retencao ? par('<b>Retenção de IRS:</b> ' + esc(x.retencao)) : '') +
    (x.iva ? par(esc(x.iva)) : '') +
    (x.ivaERetencaoAntes ? par(esc(x.ivaERetencaoAntes)) : '') +
    par('<b>Prazo:</b> ' + esc(x.prazo) + '.') +
    par('<b>Depois:</b> ' + esc(x.anexar)) +
    (x.trava ? '<p style="' + aviso + '">' + esc(x.trava) + '</p>' : '') +
    (x.semNif ? '<p style="' + aviso + '">' + esc(x.semNif) + '</p>' : '') +
    par('Se tiver dúvidas, responda a este email.') +
    '<p style="font-size:11px;color:#999;margin-top:12px">Bora App · resumo mensal automático</p></div></div>'
}

/** O mesmo email em texto simples (vai junto como parte text/plain). */
export function textoPrestador(p: Prestador, resumo: Resumo): string {
  const x = pedacos(p, resumo)
  const out: string[] = []
  out.push('Olá ' + String(p?.nome ?? '').trim() + ',')
  out.push('em ' + x.nomeMes + ' ganhou ' + x.total + ' pela Bora. Passe um só recibo verde (fatura-recibo) no Portal das Finanças com tudo o que fez no mês:')
  for (const l of x.linhas) out.push('- ' + l.nome + ' (' + l.quantidade + '): ' + eur(l.valor))
  out.push('Total do recibo: ' + x.total)
  out.push('')
  out.push('Passe o recibo a estes dados (copie tal e qual):')
  out.push('Nome: ' + String(x.adq.nome ?? ''))
  out.push(x.rotuloNif + ': ' + String(x.adq.nif ?? ''))
  out.push('Morada: ' + String(x.adq.morada ?? ''))
  out.push('Valor: ' + x.total)
  out.push('')
  out.push('Descrição para copiar: ' + x.descricao)
  out.push('')
  if (x.retencao) out.push('Retenção de IRS: ' + x.retencao)
  if (x.iva) out.push(x.iva)
  if (x.ivaERetencaoAntes) out.push(x.ivaERetencaoAntes)
  out.push('Prazo: ' + x.prazo + '.')
  out.push('Depois: ' + x.anexar)
  if (x.trava) out.push(x.trava)
  if (x.semNif) out.push(x.semNif)
  out.push('')
  out.push('Se tiver dúvidas, responda a este email.')
  out.push('Bora App · resumo mensal automático')
  return out.join(NL)
}
