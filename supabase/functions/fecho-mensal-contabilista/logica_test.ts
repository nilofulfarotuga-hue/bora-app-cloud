// deno test --no-check --no-lock --cached-only supabase/functions/fecho-mensal-contabilista/logica_test.ts
// Recibos verdes (recibos-verdes-15-11, R1b): a lista de recibos no fecho ao contabilista — sem rede.
// O resumo falso imita prestador_recibo_mensal_resumo (CONTRATO.md, secção 5.1).
import { assert, assertEquals } from 'https://deno.land/std@0.224.0/assert/mod.ts'
import {
  caminhosParaAssinar,
  htmlSecaoRecibos,
  linhasRecibos,
  mesesDeRecibos,
  type ResumoRecibos,
  secaoParaRegisto,
  secaoRecibos,
  textoSecaoRecibos,
  VALIDADE_LINK_S,
} from './logica.ts'

const PDF_ANA = 'aaaa-1111/2026-11.pdf'
const RESUMO: ResumoRecibos = {
  ano: 2026, mes: 11, nome_mes: 'novembro',
  regras: { anexar_ate: '2026-12-10' },
  prestadores: [
    { user_id: 'bbbb-2222', nome: 'Bruno Sem Recibo', nif: null, total: 40, precisa_recibo: true, estado: 'em_falta',
      recibo: { numero: null, data: null, pdf_path: null } },
    { user_id: 'aaaa-1111', nome: 'Ana Entregue', nif: '123456789', total: 63.9, precisa_recibo: true, estado: 'entregue',
      recibo: { numero: 'FR 12', data: '2026-12-03', pdf_path: PDF_ANA } },
    { user_id: 'cccc-3333', nome: 'Carla Sem PDF', nif: '987654321', total: 10.5, precisa_recibo: true, estado: 'sem_pdf',
      recibo: { numero: 'FR 7', data: '2026-12-02', pdf_path: null } },
    { user_id: 'dono', nome: 'Conta do dono', total: 9, precisa_recibo: false, estado: 'nao_precisa', recibo: null },
  ],
}

Deno.test('meses com lista: o mês fechado e a lista final do anterior, só desde novembro/2026', () => {
  assertEquals(mesesDeRecibos(2026, 10), []) // outubro: nome individual, fora
  assertEquals(mesesDeRecibos(2026, 11), [{ ano: 2026, mes: 11, final: false }])
  assertEquals(mesesDeRecibos(2026, 12), [{ ano: 2026, mes: 12, final: false }, { ano: 2026, mes: 11, final: true }])
  assertEquals(mesesDeRecibos(2027, 1), [{ ano: 2027, mes: 1, final: false }, { ano: 2026, mes: 12, final: true }])
})

Deno.test('lista de links assinados: só os recibos entregues com ficheiro, 7 dias', () => {
  assertEquals(VALIDADE_LINK_S, 604800)
  assertEquals(caminhosParaAssinar(RESUMO), [PDF_ANA])
  assertEquals(caminhosParaAssinar(null), [])
  const linhas = linhasRecibos(RESUMO, { [PDF_ANA]: 'https://exemplo/assinado?token=1' })
  assertEquals(linhas.map((l) => l.nome), ['Ana Entregue', 'Bruno Sem Recibo', 'Carla Sem PDF']) // por nome; dono fora
  assertEquals(linhas[0].link, 'https://exemplo/assinado?token=1')
  assertEquals(linhas[1].link, null)
  assertEquals(linhas.map((l) => l.situacao), ['entregue', 'falta o recibo', 'marcado sem o ficheiro (falta o PDF)'])
})

Deno.test('a secção leva nome, NIF, valor, número, data e o link; quem falta aparece a dizer que falta', () => {
  const s = secaoRecibos({ ano: 2026, mes: 11, final: true }, RESUMO, { [PDF_ANA]: 'https://exemplo/assinado?token=1&x=2' }, null)
  assertEquals(s.totais, { pessoas: 3, entregues: 1, em_falta: 2, valor: 114.4 })
  const html = htmlSecaoRecibos(s)
  assert(html.includes('Ana Entregue (NIF 123456789)'))
  assert(html.includes('63,90 €'))
  assert(html.includes('n.º FR 12 de 03/12/2026'))
  assert(html.includes('href="https://exemplo/assinado?token=1&amp;x=2"'))
  assert(html.includes('Bruno Sem Recibo') && html.includes('(sem NIF)') && html.includes('falta o recibo'))
  assert(html.includes('falta o PDF'))
  assert(html.includes('lista final') && html.includes('10/12/2026'))
  const texto = textoSecaoRecibos(s)
  assert(texto.includes('Ana Entregue (NIF 123456789): 63,90 € · recibo n.º FR 12 de 03/12/2026 · PDF: https://exemplo/assinado?token=1&x=2'))
  assert(texto.includes('Bruno Sem Recibo (sem NIF): 40,00 € · sem número · FALTA O RECIBO'))
  assert(texto.includes('Entregues 1 de 3 · em falta 2 · total 114,40 €'))
})

Deno.test('mês ainda no prazo, ensaio, erro e mês sem ninguém', () => {
  const noPrazo = htmlSecaoRecibos(secaoRecibos({ ano: 2026, mes: 11, final: false }, RESUMO, {}, null, true))
  assert(noPrazo.includes('os prestadores têm até 10/12/2026 para anexar'))
  assert(noPrazo.includes('ensaio: link não gerado'))
  const erro = secaoRecibos({ ano: 2026, mes: 11, final: false }, null, {}, 'function prestador_recibo_mensal_resumo does not exist')
  assertEquals(erro.linhas.length, 0)
  assert(htmlSecaoRecibos(erro).includes('A lista de recibos não está disponível'))
  assert(textoSecaoRecibos(erro).includes('não está disponível'))
  const vazio = secaoRecibos({ ano: 2026, mes: 11, final: false }, { prestadores: [] }, {}, null)
  assert(htmlSecaoRecibos(vazio).includes('Nenhum prestador tinha de passar recibo'))
})

Deno.test('o registo guarda a lista sem os links assinados', () => {
  const s = secaoRecibos({ ano: 2026, mes: 11, final: true }, RESUMO, { [PDF_ANA]: 'https://exemplo/assinado?token=1' }, null)
  const reg = secaoParaRegisto(s)
  assert(!JSON.stringify(reg).includes('token=1'))
  assertEquals(reg.linhas.find((l) => l.nome === 'Ana Entregue')?.link_criado, true)
  assertEquals(reg.linhas.find((l) => l.nome === 'Ana Entregue')?.pdf_path, PDF_ANA)
})

Deno.test('escapa o HTML dos nomes', () => {
  const s = secaoRecibos({ ano: 2026, mes: 11, final: false }, {
    prestadores: [{ user_id: 'x', nome: '<img src=x>', total: 1, precisa_recibo: true, estado: 'em_falta' }],
  }, {}, null)
  const html = htmlSecaoRecibos(s)
  assert(!html.includes('<img'))
  assert(html.includes('&lt;img src=x&gt;'))
})
