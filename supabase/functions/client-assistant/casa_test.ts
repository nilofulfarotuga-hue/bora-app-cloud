// Testes da Casa e Manutenção no Amigo (11/11/2026, missão amigo-casa-2026-11-11).
import { assert, assertEquals, assertStringIncludes } from 'jsr:@std/assert@1';
import { casaParaModelo, deixaCasa, eTrabalhoDeCasa, precoCasa, semFraseDeMesa, temFraseDeMesa } from './casa.ts';

// Forma da casa_config no ar (11/11/2026), cortada a 4 serviços.
const CFG = {
  visivel: true,
  garantia_dias: 7,
  cancel_free_hours: 12,
  oficios: [
    { codigo: 'montagem', nome: 'Montagem de móveis' },
    { codigo: 'fixacao', nome: 'Pendurar e fixar' },
    { codigo: 'canalizacao', nome: 'Canalização' },
    { codigo: 'pintura', nome: 'Pintura' },
  ],
  servicos: [
    { oficio: 'montagem', nome: 'Montar roupeiro', modo: 'fixo', preco_cents: 8000, unidade: 'movel' },
    { oficio: 'fixacao', nome: 'Pendurar televisão', modo: 'fixo', preco_cents: 4500, unidade: 'tarefa' },
    { oficio: 'canalizacao', nome: 'Trocar torneira', modo: 'fixo', preco_cents: 4000, unidade: 'tarefa' },
    { oficio: 'canalizacao', nome: 'Autoclismo ou sifão', modo: 'hora', preco_cents: 2000, unidade: 'hora' },
    { oficio: 'pintura', nome: 'Pintura', modo: 'orcamento', preco_cents: null, unidade: 'tarefa' },
  ],
};

Deno.test('trabalhos de casa são reconhecidos', () => {
  for (const m of [
    'preciso de montar um roupeiro', 'quanto custa pendurar uma televisão?', 'quero pintar a sala',
    'tenho a torneira a pingar', 'o autoclismo não para', 'preciso de alguém para cortar a relva',
    'montar uma cama do IKEA', 'quero pôr a tv na parede',
  ]) assert(eTrabalhoDeCasa(m), m);
});

Deno.test('compras e conversa não são trabalhos de casa', () => {
  for (const m of [
    'quero açaí', 'quero um cheeseburger', 'leite, pão e ovos', 'que restaurantes estão abertos?',
    'reservar mesa para 4 no sábado', 'quero uma lâmpada LED', 'olá, tudo bem?',
  ]) assert(!eTrabalhoDeCasa(m), m);
});

Deno.test('preços saem da tabela: fixo, por móvel, à hora e orçamento', () => {
  assertEquals(precoCasa(CFG.servicos[0]), '80,00 € por móvel');
  assertEquals(precoCasa(CFG.servicos[1]), '45,00 €');
  assertEquals(precoCasa(CFG.servicos[2]), '40,00 €');
  assertEquals(precoCasa(CFG.servicos[3]), '20,00 € por hora');
  assertStringIncludes(precoCasa(CFG.servicos[4]), 'orçamento');
  assertStringIncludes(precoCasa(CFG.servicos[4]), 'fotos');
});

Deno.test('o modelo recebe serviços, material, garantia e cancelamento das definições', () => {
  const r = casaParaModelo({ ...CFG, garantia_dias: 9, cancel_free_hours: 24 });
  assertEquals(r.disponivel, true);
  assertEquals(r.servicos.length, 5);
  assertEquals(r.servicos[0].servico, 'Montar roupeiro');
  assertEquals(r.servicos[0].area, 'Montagem de móveis');
  assertStringIncludes(r.regras.material, 'ferramentas');
  assertStringIncludes(r.regras.material, 'material');
  assertStringIncludes(r.regras.garantia, '9 dias');
  assertStringIncludes(r.regras.cancelamento, '24 horas');
  assertStringIncludes(r.instrucao, 'quantas pessoas');
});

Deno.test('ofícios desligados (ex.: Pintura, fase 2) vão em ainda_nao_disponivel', () => {
  const cfg = {
    ...CFG,
    oficios: [...CFG.oficios.filter((o) => o.codigo !== 'pintura'), { codigo: 'pintura', nome: 'Pintura', ativo: false }],
    servicos: CFG.servicos.filter((s) => s.oficio !== 'pintura'),
  };
  const r = casaParaModelo(cfg);
  assertEquals(r.ainda_nao_disponivel, ['Pintura']);
  assert(!r.servicos.some((s: { servico: string }) => s.servico === 'Pintura'));
  assertStringIncludes(r.instrucao, 'ainda_nao_disponivel');
});

Deno.test('Casa desligada: o modelo diz que não está disponível, sem lista', () => {
  const r = casaParaModelo({ ...CFG, visivel: false });
  assertEquals(r.disponivel, false);
  assertEquals(r.servicos, undefined);
});

Deno.test('a ligação abre a categoria casa pelo caminho das faixas (apps já publicadas)', () => {
  const d = deixaCasa('2026-11-11');
  assertEquals(d.acao.tipo, 'abrir_faixa');
  assertEquals(JSON.parse(d.acao.destino), { tipo_destino: 'categoria', destino: 'casa' });
  assertStringIncludes(d.texto, 'Casa e Manutenção');
});

Deno.test('frases de reserva de mesa saem da resposta da Casa; o resto fica', () => {
  assert(temFraseDeMesa('Para quantas pessoas é?'));
  const t = semFraseDeMesa('Montar um roupeiro fica 80,00 €. Para quantas pessoas é? O material é teu.');
  assertEquals(t, 'Montar um roupeiro fica 80,00 €. O material é teu.');
  assertEquals(semFraseDeMesa('Fica 45,00 €.'), 'Fica 45,00 €.');
});
