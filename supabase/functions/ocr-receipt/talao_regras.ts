// ocr-receipt · regras do talão (missão fechar-app-15-11, bloco 4, 14/11/2026)
//
// Caso real (pedido 7a3468d5, McDonald's): o robô leu "KFC" como loja e devolveu o saco em
// duas linhas ("Taxa Saco" 0,30 + "Saco de Tran" 0,30): a soma das linhas dava 25,40 € com o
// total impresso a 25,10 €.
//
// Funções puras (sem rede, sem banco) para se provarem sozinhas:
//   - conferirLoja: a loja LIDA no talão é a loja DO PEDIDO? Nunca falha a leitura; só avisa.
//   - tirarLinhasRepetidas: quando a soma das linhas passa o total impresso exatamente pelo
//     valor de uma linha repetida, essa linha conta uma vez. O total impresso é o árbitro:
//     sem total impresso não se tira nada.
//
// NÃO mexem em dinheiro: o valor do talão é o total impresso (não muda) e as linhas de
// depósito de embalagens nunca são tiradas aqui (essas alimentam o depósito Volta no servidor).

export type LinhaTalao = { name: string; qty: number; unit_price_cents: number }

export type ConferenciaLoja = {
  /** true = bate; false = não bate; null = falta uma das duas, não se sabe. */
  ok: boolean | null
  lida: string | null
  pedido: string | null
  /** Quando a loja lida é OUTRA loja que a Bora conhece (ex.: leu KFC num pedido do McDonald's). */
  outra_loja_conhecida: string | null
}

export type ConferenciaLinhas = {
  linhas: LinhaTalao[]
  removidas: LinhaTalao[]
  soma_antes_cents: number
  soma_depois_cents: number
  /** null = nada a dizer; senão o que se passou, para o painel. */
  aviso: 'linha_repetida_tirada' | 'soma_das_linhas_acima_do_total' | null
}

// Palavras que aparecem em muitos nomes e não distinguem loja nenhuma.
const PALAVRAS_GENERICAS = new Set([
  'restaurante', 'restaurantes', 'cafe', 'cafetaria', 'pastelaria', 'padaria', 'pizzaria', 'hamburgueria',
  'snack', 'bar', 'loja', 'lojas', 'supermercado', 'supermercados', 'hipermercado', 'mercado', 'farmacia',
  'guarda', 'portugal', 'lda', 'limitada', 'unipessoal', 'sociedade', 'sistemas', 'comercio', 'distribuicao',
  'the', 'and', 'dos', 'das', 'del',
])

/** Minúsculas, sem acentos, só letras e números separados por um espaço. */
export function normalizarNome(s: string | null | undefined): string {
  return String(s ?? '')
    .normalize('NFD').replace(/[̀-ͯ]/g, '')
    .toLowerCase()
    .replace(/['’`´]/g, '') // McDonald's -> mcdonalds
    .replace(/[^a-z0-9]+/g, ' ')
    .trim()
}

function compacto(s: string): string {
  return s.replace(/ /g, '')
}

function palavrasFortes(norm: string): string[] {
  return norm.split(' ').filter((p) => p.length >= 4 && !PALAVRAS_GENERICAS.has(p))
}

/**
 * Dois nomes são a mesma loja? Tolerante a maiúsculas, acentos, apóstrofos, espaços e ao nome
 * vir com a terra ou a empresa à volta ("McDonald's" = "MC DONALDS GUARDA" = "Sistemas
 * McDonald's Portugal"). null quando falta um dos nomes.
 */
export function lojasBatem(a: string | null | undefined, b: string | null | undefined): boolean | null {
  const na = normalizarNome(a)
  const nb = normalizarNome(b)
  if (!na || !nb) return null
  if (na === nb) return true
  const ca = compacto(na)
  const cb = compacto(nb)
  // Um nome dentro do outro (com 3 letras ou mais, para "bk" não bater com tudo).
  if (ca.length >= 3 && cb.length >= 3 && (ca.includes(cb) || cb.includes(ca))) return true
  // Uma palavra forte em comum ("continente" em "Continente Modelo Guarda").
  const fa = palavrasFortes(na)
  const fb = new Set(palavrasFortes(nb))
  if (fa.some((p) => fb.has(p))) return true
  // A palavra forte de um lado colada no outro ("mc donalds" -> "mcdonalds").
  if (palavrasFortes(nb).some((p) => ca.includes(p)) || fa.some((p) => cb.includes(p))) return true
  return false
}

/**
 * Compara a loja lida com a loja do pedido. Se não baterem, procura a loja lida entre as
 * lojas que a Bora conhece: ler OUTRA loja conhecida é sinal forte de talão trocado (ou de
 * leitura errada); um nome que não é de loja nenhuma costuma ser o nome da empresa dona da
 * loja, e fica só como nota.
 */
export function conferirLoja(
  lida: string | null | undefined,
  doPedido: string | null | undefined,
  lojasConhecidas: readonly string[] = [],
): ConferenciaLoja {
  const l = lida && String(lida).trim() ? String(lida).trim() : null
  const p = doPedido && String(doPedido).trim() ? String(doPedido).trim() : null
  const ok = lojasBatem(l, p)
  let outra: string | null = null
  if (ok === false) {
    for (const nome of lojasConhecidas) {
      if (lojasBatem(nome, p) === true) continue // é a própria loja do pedido com outro nome
      if (lojasBatem(l, nome) === true) { outra = nome; break }
    }
  }
  return { ok, lida: l, pedido: p, outra_loja_conhecida: outra }
}

function valorDaLinha(l: LinhaTalao): number {
  return Math.round((Number(l.qty) || 0) * (Number(l.unit_price_cents) || 0))
}

export function somaDasLinhas(linhas: readonly LinhaTalao[]): number {
  return linhas.reduce((s, l) => s + valorDaLinha(l), 0)
}

function eSaco(nome: string): boolean {
  return /\b(saco|sacos|sac|saca|bag)\b/.test(nome)
}

function eDeposito(nome: string): boolean {
  return /\b(deposito|vasilhame|sdr|volta|tara)\b/.test(nome)
}

/**
 * Tira UMA linha repetida quando (e só quando) a soma das linhas passa o total impresso
 * exatamente pelo valor dessa linha. Conta como repetida:
 *   - a mesma linha lida duas vezes (mesmo nome, mesma quantidade, mesmo preço);
 *   - o saco em duas linhas do mesmo valor ("Taxa Saco" + "Saco de Transporte").
 * Tira-se a de baixo. Dois artigos iguais comprados a sério NÃO se tiram: aí a soma bate com
 * o total. Linhas de depósito de embalagens nunca se tiram aqui.
 */
export function tirarLinhasRepetidas(
  linhas: readonly LinhaTalao[],
  totalCents: number | null | undefined,
): ConferenciaLinhas {
  const copia = linhas.map((l) => ({ ...l }))
  const soma = somaDasLinhas(copia)
  const base: ConferenciaLinhas = {
    linhas: copia, removidas: [], soma_antes_cents: soma, soma_depois_cents: soma, aviso: null,
  }
  if (typeof totalCents !== 'number' || !(totalCents > 0) || copia.length === 0) return base
  const excesso = soma - Math.round(totalCents)
  if (excesso <= 0) return base

  const nomes = copia.map((l) => normalizarNome(l.name))
  for (let i = copia.length - 1; i >= 1; i--) {
    if (valorDaLinha(copia[i]) !== excesso) continue
    if (eDeposito(nomes[i])) continue
    let repetida = false
    for (let j = 0; j < copia.length && !repetida; j++) {
      if (j === i) continue
      const mesma = j < i && nomes[j] === nomes[i]
        && copia[j].qty === copia[i].qty && copia[j].unit_price_cents === copia[i].unit_price_cents
      const sacoDuasVezes = eSaco(nomes[i]) && eSaco(nomes[j])
        && valorDaLinha(copia[j]) === valorDaLinha(copia[i])
      repetida = mesma || sacoDuasVezes
    }
    if (!repetida) continue
    const [fora] = copia.splice(i, 1)
    return {
      linhas: copia,
      removidas: [fora],
      soma_antes_cents: soma,
      soma_depois_cents: somaDasLinhas(copia),
      aviso: 'linha_repetida_tirada',
    }
  }
  return { ...base, aviso: 'soma_das_linhas_acima_do_total' }
}
