// supabase/functions/fecho-mensal-contabilista/logica.ts
// Recibos verdes (missão recibos-verdes-15-11, R1b, 15/11/2026) — a parte pura da lista de recibos
// verdes dos prestadores que vai no fecho ao contabilista. Não fala com a rede: recebe o que a RPC
// prestador_recibo_mensal_resumo devolve (CONTRATO.md, secção 5.1) e os links assinados já criados.
//
// Porque há duas listas: o fecho sai no dia 1 e os prestadores têm até ao dia 10 para anexar o recibo
// do mês fechado — no dia 1 essa lista vem quase toda "por entregar". Por isso vai também a lista FINAL
// do mês anterior (o prazo dele terminou no dia 10), com os PDFs. Só recibos à sociedade (desde 11/2026).
//
// Testes (sem rede): deno test --no-check --no-lock --cached-only supabase/functions/fecho-mensal-contabilista/logica_test.ts

// Quebra de linha sem barra invertida no código (cicatriz do weekly-closeout-digest v8: o deploy por MCP).
const NL = String.fromCharCode(10)
const NOMES_MES = ['', 'janeiro', 'fevereiro', 'março', 'abril', 'maio', 'junho', 'julho', 'agosto',
  'setembro', 'outubro', 'novembro', 'dezembro']

/** Primeiro mês com recibos à sociedade (outubro/2026 era em nome individual e fica de fora). */
export const RECIBOS_DESDE = 2026 * 12 + 11
/** Bucket privado dos recibos (R1a): {user_id}/{ano}-{mês}.pdf|jpg|png */
export const BUCKET_RECIBOS = 'recibos-verdes'
/** Os links assinados valem 7 dias (604800 s), como o ZIP dos talões. */
export const VALIDADE_LINK_S = 7 * 24 * 3600

export type MesRecibos = { ano: number; mes: number; final: boolean }
export type PrestadorResumo = {
  user_id?: string
  nome?: string | null
  nif?: string | null
  total?: number | string | null
  precisa_recibo?: boolean
  estado?: string | null
  recibo?: { numero?: string | null; data?: string | null; pdf_path?: string | null } | null
}
export type ResumoRecibos = {
  ano?: number
  mes?: number
  nome_mes?: string
  regras?: { anexar_ate?: string | null } | null
  prestadores?: PrestadorResumo[] | null
}
export type LinhaRecibo = {
  user_id: string
  nome: string
  nif: string | null
  valor: number
  numero: string | null
  data: string | null
  estado: string
  entregue: boolean
  pdf_path: string | null
  link: string | null
  situacao: string
}
export type SecaoRecibos = {
  ano: number
  mes: number
  nome: string
  final: boolean
  anexar_ate: string | null
  ensaio: boolean
  erro: string | null
  linhas: LinhaRecibo[]
  totais: { pessoas: number; entregues: number; em_falta: number; valor: number }
}

function eur(v: unknown): string {
  return (Number(v ?? 0) || 0).toFixed(2).replace('.', ',') + ' €'
}
function esc(s: unknown): string {
  return String(s ?? '').replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;')
    .replace(/"/g, '&quot;').replace(/'/g, '&#39;')
}
/** '2026-12-10' → '10/12/2026' ('' se não for uma data). */
export function dataPt(iso: unknown): string {
  const m = /^([0-9]{4})-([0-9]{2})-([0-9]{2})/.exec(String(iso ?? ''))
  return m ? m[3] + '/' + m[2] + '/' + m[1] : ''
}

export function mesAnterior(ano: number, mes: number): { ano: number; mes: number } {
  return mes === 1 ? { ano: ano - 1, mes: 12 } : { ano, mes: mes - 1 }
}

/** Os meses com lista neste fecho: o mês fechado (ainda no prazo) e o anterior (lista final). */
export function mesesDeRecibos(ano: number, mes: number): MesRecibos[] {
  const out: MesRecibos[] = []
  if (ano * 12 + mes >= RECIBOS_DESDE) out.push({ ano, mes, final: false })
  const a = mesAnterior(ano, mes)
  if (a.ano * 12 + a.mes >= RECIBOS_DESDE) out.push({ ano: a.ano, mes: a.mes, final: true })
  return out
}

export function situacaoDoRecibo(estado: string | null | undefined): string {
  if (estado === 'entregue') return 'entregue'
  if (estado === 'sem_pdf') return 'marcado sem o ficheiro (falta o PDF)'
  return 'falta o recibo'
}

/** Uma linha por pessoa que tinha de passar recibo; `links` = { caminho do PDF: link assinado }. */
export function linhasRecibos(resumo: ResumoRecibos | null | undefined, links: Record<string, string> = {}): LinhaRecibo[] {
  return (resumo?.prestadores ?? [])
    .filter((p) => p?.precisa_recibo === true)
    .map((p) => {
      const r = p.recibo ?? {}
      const caminho = r.pdf_path ? String(r.pdf_path) : null
      const estado = String(p.estado ?? 'em_falta')
      return {
        user_id: String(p.user_id ?? ''),
        nome: String(p.nome ?? '').trim(),
        nif: p.nif ? String(p.nif) : null,
        valor: Number(p.total ?? 0) || 0,
        numero: r.numero ? String(r.numero) : null,
        data: r.data ? String(r.data) : null,
        estado,
        entregue: estado === 'entregue',
        pdf_path: caminho,
        link: caminho ? (links[caminho] ?? null) : null,
        situacao: situacaoDoRecibo(estado),
      }
    })
    .sort((a, b) => a.nome.localeCompare(b.nome, 'pt'))
}

/** Os caminhos a assinar: só recibos entregues com ficheiro. */
export function caminhosParaAssinar(resumo: ResumoRecibos | null | undefined): string[] {
  return linhasRecibos(resumo).filter((l) => l.entregue && l.pdf_path).map((l) => l.pdf_path as string)
}

export function secaoRecibos(
  m: MesRecibos,
  resumo: ResumoRecibos | null | undefined,
  links: Record<string, string>,
  erro: string | null,
  ensaio = false,
): SecaoRecibos {
  const linhas = erro ? [] : linhasRecibos(resumo, links)
  return {
    ano: m.ano,
    mes: m.mes,
    nome: (resumo?.nome_mes || NOMES_MES[m.mes] || '') + ' de ' + m.ano,
    final: m.final,
    anexar_ate: resumo?.regras?.anexar_ate ? String(resumo.regras.anexar_ate) : null,
    ensaio,
    erro,
    linhas,
    totais: {
      pessoas: linhas.length,
      entregues: linhas.filter((l) => l.entregue).length,
      em_falta: linhas.filter((l) => !l.entregue).length,
      valor: Math.round(linhas.reduce((a, l) => a + l.valor, 0) * 100) / 100,
    },
  }
}

function tituloDaSecao(s: SecaoRecibos): string {
  const ate = dataPt(s.anexar_ate)
  return 'Recibos verdes dos prestadores — ' + s.nome + (s.final
    ? ' (lista final' + (ate ? '; o prazo para anexar terminou a ' + ate : '') + ')'
    : (ate ? ' (os prestadores têm até ' + ate + ' para anexar)' : ''))
}

function rotuloDoLink(s: SecaoRecibos, l: LinhaRecibo): string {
  if (!l.entregue) return ''
  if (l.link) return ''
  return s.ensaio ? 'ensaio: link não gerado' : 'link indisponível — abrir no painel /admin/fecho-mensal'
}

/** A secção do email ao contabilista (9 = mês fechado, 10 = lista final do mês anterior). */
export function htmlSecaoRecibos(s: SecaoRecibos, numero = 9): string {
  const td = 'padding:5px 6px;border-bottom:1px solid #f1f1f1'
  const cab = '<h3 style="margin:16px 0 6px">' + numero + '. ' + esc(tituloDaSecao(s)) + '</h3>'
  if (s.erro) {
    return cab + '<p style="font-size:13px;color:#B45309">A lista de recibos não está disponível (' +
      esc(String(s.erro).slice(0, 160)) + '). Veja no painel /admin/fecho-mensal.</p>'
  }
  if (!s.linhas.length) return cab + '<p style="font-size:13px">Nenhum prestador tinha de passar recibo neste mês.</p>'
  const linhas = s.linhas.map((l) => {
    const quem = esc(l.nome) + (l.nif ? ' (NIF ' + esc(l.nif) + ')' : ' <span style="color:#B45309">(sem NIF)</span>')
    const recibo = l.numero ? 'n.º ' + esc(l.numero) + (l.data ? ' de ' + esc(dataPt(l.data)) : '') : '—'
    const pdf = l.entregue
      ? (l.link ? '<a href="' + esc(l.link) + '">abrir o PDF</a>' : esc(rotuloDoLink(s, l)))
      : '<span style="color:#B45309;font-weight:700">' + esc(l.situacao) + '</span>'
    return '<tr><td style="' + td + '">' + quem + '</td><td style="' + td + ';text-align:right;font-weight:700">' +
      eur(l.valor) + '</td><td style="' + td + '">' + recibo + '</td><td style="' + td + '">' + pdf + '</td></tr>'
  }).join('')
  return cab +
    '<table style="width:100%;border-collapse:collapse;font-size:13px">' +
    '<tr style="color:#666"><td style="' + td + '">Prestador</td><td style="' + td + ';text-align:right">Valor</td>' +
    '<td style="' + td + '">Recibo</td><td style="' + td + '">PDF</td></tr>' + linhas + '</table>' +
    '<p style="font-size:12px;color:#555">Entregues: ' + s.totais.entregues + ' de ' + s.totais.pessoas +
    ' · em falta: ' + s.totais.em_falta + ' · total dos recibos: ' + eur(s.totais.valor) +
    '. Os links abrem o PDF e valem 7 dias; o original fica guardado na Bora.</p>'
}

/** A mesma secção em texto simples (vai no fim do texto que o painel e o WhatsApp usam). */
export function textoSecaoRecibos(s: SecaoRecibos): string {
  const out: string[] = [tituloDaSecao(s) + ':']
  if (s.erro) {
    out.push('A lista de recibos não está disponível (' + String(s.erro).slice(0, 160) + '). Veja no painel /admin/fecho-mensal.')
    return out.join(NL)
  }
  if (!s.linhas.length) {
    out.push('Nenhum prestador tinha de passar recibo neste mês.')
    return out.join(NL)
  }
  for (const l of s.linhas) {
    const quem = l.nome + (l.nif ? ' (NIF ' + l.nif + ')' : ' (sem NIF)')
    const recibo = l.numero ? 'recibo n.º ' + l.numero + (l.data ? ' de ' + dataPt(l.data) : '') : 'sem número'
    const pdf = l.entregue ? (l.link ? 'PDF: ' + l.link : rotuloDoLink(s, l)) : l.situacao.toUpperCase()
    out.push('- ' + quem + ': ' + eur(l.valor) + ' · ' + recibo + ' · ' + pdf)
  }
  out.push('Entregues ' + s.totais.entregues + ' de ' + s.totais.pessoas + ' · em falta ' + s.totais.em_falta +
    ' · total ' + eur(s.totais.valor) + ' (links válidos 7 dias)')
  return out.join(NL)
}

/** O que fica no registo (fecho_mensal_contabilista_log.resumo): sem os links assinados. */
export function secaoParaRegisto(s: SecaoRecibos) {
  return {
    ano: s.ano, mes: s.mes, final: s.final, erro: s.erro, totais: s.totais,
    linhas: s.linhas.map((l) => ({
      user_id: l.user_id, nome: l.nome, nif: l.nif, valor: l.valor, numero: l.numero, data: l.data,
      estado: l.estado, pdf_path: l.pdf_path, link_criado: !!l.link,
    })),
  }
}
