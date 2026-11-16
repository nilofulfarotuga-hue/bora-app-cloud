// deno test --no-check --no-lock --cached-only supabase/functions/monthly-partner-statement/logica_test.ts
// Recibos verdes (recibos-verdes-15-11, R1b): o email do dia 1 a cada prestador — sem rede.
// O resumo falso imita prestador_recibo_mensal_resumo (CONTRATO.md, secção 5.1): a Mayra é estafeta e
// limpadora (uma pessoa, duas linhas), o dono fica de fora, a conta demo também.
import { assert, assertEquals } from 'https://deno.land/std@0.224.0/assert/mod.ts'
import {
  assuntoPrestador,
  htmlPrestador,
  jaEnviadoAPessoa,
  type Prestador,
  type Resumo,
  separarPessoas,
  textoPrestador,
  textoRetencao,
} from './logica.ts'

const MAYRA: Prestador = {
  user_id: '9a8a5657-0000-4000-8000-000000000001', nome: 'Mayra Teste', nif: '123456789',
  email: 'mayra@exemplo.pt',
  linhas: [
    { servico: 'entregas', nome: 'Entregas', quantidade: 5, valor: 23.9 },
    { servico: 'limpeza', nome: 'Limpezas', quantidade: 2, valor: 40 },
  ],
  total: 63.9,
  descricao: 'Serviços prestados em novembro de 2026 através da plataforma Bora (5 entregas, 2 limpezas)',
  demo: false, conta_dono: false, proprio_adquirente: false, precisa_recibo: true, conta_para_trava: true,
  estado: 'em_falta',
}
const DONO: Prestador = {
  user_id: 'dono-0000', nome: 'Conta do dono', linhas: [{ servico: 'entregas', nome: 'Entregas', quantidade: 3, valor: 9 }],
  total: 9, conta_dono: true, proprio_adquirente: true, precisa_recibo: false, estado: 'nao_precisa',
}
const DEMO: Prestador = {
  user_id: 'demo-0000', nome: 'Demo', linhas: [{ servico: 'limpeza', nome: 'Limpezas', quantidade: 1, valor: 20 }],
  total: 20, demo: true, precisa_recibo: false, estado: 'nao_precisa',
}
const SEM_TRABALHO: Prestador = { user_id: 'zero-0000', nome: 'Zero', linhas: [], total: 0, precisa_recibo: false }

const RESUMO: Resumo = {
  ano: 2026, mes: 11, nome_mes: 'novembro',
  adquirente: {
    tipo: 'sociedade', nome: 'Danilo Fulfaro da Silva - Unipessoal Lda', nif: '519686233',
    morada: 'Rua do Torreão 14, 6300-610 Guarda',
  },
  regras: {
    descricao_modelo: 'Serviços prestados em novembro de 2026 através da plataforma Bora',
    prazo_texto: 'Fatura-recibo até ao 5.º dia útil seguinte ao recebimento (art. 36.º CIVA / art. 115.º CIRS)',
    anexar_ate: '2026-12-10',
    anexar_texto: 'Anexe o recibo na app, em Ganhos, até 10/12/2026.',
    conta_para_trava: true,
    retencao: {
      mencao_dispensa: 'Sem retenção, nos termos do n.º 1 do artigo 101.º-B do Código do IRS',
      taxa_se_aplicavel: '11,5%', limite_anual: '15.000 EUR',
    },
    iva_texto: 'IVA: isento ao abrigo do artigo 53.º do CIVA, se for o seu caso; o contabilista confirma.',
  },
  prestadores: [MAYRA, DONO, DEMO, SEM_TRABALHO, { ...MAYRA }],
}

Deno.test('um email por pessoa: estafeta e limpeza da mesma pessoa vão juntos; dono e demo ficam de fora', () => {
  const { enviar, saltar } = separarPessoas(RESUMO.prestadores)
  assertEquals(enviar.length, 1) // a Mayra repetida não conta duas vezes
  assertEquals(enviar[0].user_id, MAYRA.user_id)
  assertEquals(enviar[0].linhas?.length, 2)
  assertEquals(saltar.map((s) => s.motivo), ['conta_dono', 'demo'])
  assert(!enviar.some((p) => p.user_id === SEM_TRABALHO.user_id))
  assert(!saltar.some((s) => s.prestador.user_id === SEM_TRABALHO.user_id))
})

Deno.test('reenvio de uma pessoa só (filtro do painel)', () => {
  assertEquals(separarPessoas(RESUMO.prestadores, MAYRA.user_id).enviar.length, 1)
  const outro = separarPessoas(RESUMO.prestadores, 'ninguem')
  assertEquals(outro.enviar.length + outro.saltar.length, 0)
  // o dono com fecho_dono_passa_recibo = true vem com precisa_recibo = true e passa a receber
  const donoPassa = separarPessoas([{ ...DONO, precisa_recibo: true, proprio_adquirente: false }])
  assertEquals(donoPassa.enviar.length, 1)
  assertEquals(separarPessoas(null).enviar.length, 0)
})

Deno.test('nunca duas vezes à mesma pessoa (registo da pessoa ou registo antigo da limpeza)', () => {
  assertEquals(jaEnviadoAPessoa({ email_status: 'sent' }, [], false), true)
  assertEquals(jaEnviadoAPessoa(null, [{ email_status: 'failed' }, { email_status: 'sent' }], false), true)
  assertEquals(jaEnviadoAPessoa(null, [], false), false)
  assertEquals(jaEnviadoAPessoa({ email_status: 'failed' }, null, false), false)
  assertEquals(jaEnviadoAPessoa({ email_status: 'skipped' }, [{ email_status: 'aguarda_dominio' }], false), false)
  // só o botão do painel (force) reenvia
  assertEquals(jaEnviadoAPessoa({ email_status: 'sent' }, [{ email_status: 'sent' }], true), false)
})

Deno.test('o email leva total, linhas por serviço, dados da empresa, descrição, prazo, retenção, IVA e Ganhos', () => {
  const html = htmlPrestador(MAYRA, RESUMO)
  const texto = textoPrestador(MAYRA, RESUMO)
  for (const s of [html, texto]) {
    assert(s.includes('63,90 €'), 'total')
    assert(s.includes('Entregas (5)') && s.includes('23,90 €'), 'linha entregas')
    assert(s.includes('Limpezas (2)') && s.includes('40,00 €'), 'linha limpezas')
    assert(s.includes('Danilo Fulfaro da Silva - Unipessoal Lda'), 'nome da empresa')
    assert(s.includes('519686233'), 'NIPC')
    assert(s.includes('NIF (NIPC)'), 'rótulo do NIPC')
    assert(s.includes('6300-610 Guarda'), 'morada')
    assert(s.includes('(5 entregas, 2 limpezas)'), 'descrição da função')
    assert(s.includes('5.º dia útil seguinte ao recebimento'), 'prazo')
    assert(s.includes('Sem retenção, nos termos do n.º 1 do artigo 101.º-B do Código do IRS'), 'menção da dispensa')
    assert(s.includes('11,5%') && s.includes('15.000 EUR'), 'retenção acima do limite')
    assert(s.includes('artigo 53.º do CIVA') && s.includes('o contabilista confirma'), 'IVA')
    assert(s.includes('Anexe o recibo na app, em Ganhos, até 10/12/2026.'), 'anexar em Ganhos')
    assert(s.includes('ficam guardados até o anexar'), 'aviso da trava')
    assert(s.includes('um só recibo verde'), 'um só recibo')
  }
  assertEquals(assuntoPrestador(RESUMO), 'O seu recibo verde de novembro de 2026 · Bora')
  assert(!texto.includes('<'), 'texto simples sem HTML')
})

Deno.test('a retenção é só texto e vem dos dados da função', () => {
  const t = textoRetencao({ retencao: { mencao_dispensa: 'MENÇÃO X', taxa_se_aplicavel: '9,9%', limite_anual: '1 EUR' } })
  assert(t.includes('«MENÇÃO X»') && t.includes('9,9%') && t.includes('1 EUR'))
  const recurso = textoRetencao(undefined)
  assert(recurso.includes('artigo 101.º-B') && recurso.includes('11,5%') && recurso.includes('15.000 EUR'))
})

Deno.test('escapa o HTML dos nomes', () => {
  const html = htmlPrestador({ ...MAYRA, nome: '<script>x</script>' }, RESUMO)
  assert(!html.includes('<script>'))
  assert(html.includes('&lt;script&gt;x&lt;/script&gt;'))
})

Deno.test('antes da sociedade (até outubro/2026): sem retenção nem IVA fixos, como na v4', () => {
  const outubro: Resumo = {
    ...RESUMO, mes: 10, nome_mes: 'outubro',
    adquirente: { tipo: 'individual', nome: 'Danilo Fulfaro da Silva', nif: '322151171', morada: 'Rua do Torreão 14, 6300-610 Guarda' },
  }
  const html = htmlPrestador({ ...MAYRA, conta_para_trava: false }, outubro)
  assert(!html.includes('Sem retenção'))
  assert(!html.includes('NIPC'))
  assert(html.includes('dependem do seu regime nas Finanças'))
  assert(html.includes('Já passei o recibo'))
  assert(!html.includes('ficam guardados'))
})

Deno.test('sem NIF: o email avisa; sem trava: não fala da trava', () => {
  const html = htmlPrestador({ ...MAYRA, nif: '', conta_para_trava: false }, RESUMO)
  assert(html.includes('Ainda não temos o seu NIF'))
  assert(!html.includes('ficam guardados'))
  assert(!htmlPrestador(MAYRA, RESUMO).includes('Ainda não temos o seu NIF'))
})
