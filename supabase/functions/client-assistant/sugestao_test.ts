// deno test supabase/functions/client-assistant/sugestao_test.ts
// 11/11/2026 (missão fechar-tudo-2026-11-11, bloco 2): o "quero" monta o carrinho em código, o parceiro
// aberto vem primeiro e as lojas abertas pela hora de Lisboa. Dados de brincar (lojas e produtos do
// catálogo público; nada de clientes).
import { assert, assertEquals, assertStringIncludes } from 'jsr:@std/assert@1';
import {
  abertaPeloHorario,
  comQuantidade,
  confirmacaoEParaOCarrinho,
  eConfirmacaoDeCompra,
  escolherSugestao,
  filtrarLojas,
  horaDaquiA,
  linkMaps,
  type LojaAberta,
  lojaDe,
  ordenarLojas,
  parceiroPrimeiro,
  sugestaoValida,
  textoCarrinhoMontado,
  tipoDe,
} from './sugestao.ts';

// ─── "quero" / "sim" / "pode ser" ─────────────────────────────────────────────

const SIM = [
  'quero', 'eu quero', 'então eu quero', 'Então eu quero!', 'sim', 'Sim!', 'sim, quero', 'pode ser', 'Pode ser.',
  'pode ser?', 'ok', 'isso', 'quero esse', 'quero esse mesmo', 'sim por favor', 'bora', 'manda vir', 'pode mandar',
  'põe no carrinho', 'monta o carrinho', 'pode pôr no carrinho', 'está bem', 'tá bom, quero', 'quero sim',
  'claro', 'perfeito', 'combinado', 'boa!', 'sim, pode pedir', 'quero comprar', 'yes',
];
const NAO = [
  'não', 'não quero', 'nao obrigado', 'nem pensar', 'quero um hambúrguer', 'quero outra coisa', 'pode ser outro?',
  'quanto custa?', 'quero mais barato', 'sim mas sem cebola', 'por que?', 'está fechado?', 'boa noite',
  'Eu quero um chá', 'quero ver as outras opções', 'e o do Fuku?', '', 'mostra-me o menu',
  'quero esse e uma coca-cola', 'olá, tudo bem?', 'compara as lojas', 'Está certo, compara as lojas',
];

Deno.test('o "sim" à sugestão: frases curtas de confirmação', () => {
  for (const f of SIM) assertEquals(eConfirmacaoDeCompra(f).confirma, true, `devia confirmar: "${f}"`);
});

Deno.test('o "sim" à sugestão: negações, artigos novos e perguntas não confirmam', () => {
  for (const f of NAO) assertEquals(eConfirmacaoDeCompra(f).confirma, false, `não devia confirmar: "${f}"`);
});

Deno.test('quantidade dita no "quero"', () => {
  assertEquals(eConfirmacaoDeCompra('quero 2'), { confirma: true, quantidade: 2 });
  assertEquals(eConfirmacaoDeCompra('quero dois'), { confirma: true, quantidade: 2 });
  assertEquals(eConfirmacaoDeCompra('sim, três'), { confirma: true, quantidade: 3 });
  assertEquals(eConfirmacaoDeCompra('quero'), { confirma: true, quantidade: null });
  assertEquals(eConfirmacaoDeCompra('quero 200').confirma, false);
  const s = { restaurant_id: 'goola-acai-guarda', loja: 'Goola Açaí', itens: [{ product_id: 'goola-bowl', quantity: 1, nome: 'Goola Bowl' }], origem: 'produto' as const };
  assertEquals(comQuantidade(s, 2).itens[0].quantity, 2);
  assertEquals(comQuantidade(s, null), s);
});

Deno.test('o "sim" só vale para o carrinho quando a resposta anterior não perguntou outra coisa', () => {
  // conversas de 10/11 (textos do Amigo, sem dados de ninguém)
  assert(confirmacaoEParaOCarrinho('Encontrei açaí no Continente, que está aberto. Toca em "Encher o carrinho" para continuares. Se preferires, junto banana ou granola, é só dizeres.'));
  assert(confirmacaoEParaOCarrinho('Fiz-te o carrinho com um Hambúrguer do McDonald\'s. Toca em "Encher o carrinho" para avançar. Se preferires algo maior, diz-me.'));
  assert(confirmacaoEParaOCarrinho('Encontrei o Goola Bowl no Goola Açaí, aberto até às 22h. Queres que monte o carrinho?'));
  assert(confirmacaoEParaOCarrinho('Tenho o Goola Bowl. Queres este?'));
  assert(!confirmacaoEParaOCarrinho('Se quiseres algo mais barato, o Fuku tem opções. Queres que veja alguma delas?'));
  assert(!confirmacaoEParaOCarrinho('O chá está no carrinho. Se o queres já esta noite, um Favor leva-to. Queres que te prepare o Favor?'));
  assert(!confirmacaoEParaOCarrinho('Queres que eu guarde isto para as próximas conversas? Só guardo se disseres que sim.'));
  assert(!confirmacaoEParaOCarrinho('Montei o Whopper. Queres juntar batatas e bebida?'));
});

// ─── A sugestão guardada ──────────────────────────────────────────────────────

const PROP_GOOLA = {
  restaurant_id: 'goola-acai-guarda', restaurant_name: 'Goola Açaí', coverage_pct: 100,
  items: [{ product_id: 'goola-bowl', name: 'Goola Bowl', quantity: 1 }],
};
const PROP_CONTINENTE = {
  restaurant_id: 'continente-guarda', restaurant_name: 'Continente', coverage_pct: 100,
  items: [{ product_id: 'cnt-1', name: 'Açaí congelado', quantity: 1 }, { product_id: 'cnt-2', name: 'Granola', quantity: 2 }],
};
const PROP_INCOMPLETA = { restaurant_id: 'pingodoce-guarda', restaurant_name: 'Pingo Doce', coverage_pct: 50, items: [{ product_id: 'pd-1', name: 'x', quantity: 1 }] };

Deno.test('escolherSugestao: um carrinho → esse; vários do cesto → o 1.º completo; vários soltos → nenhum', () => {
  const um = escolherSugestao({ propostas: [PROP_GOOLA], veioDoCesto: false, produtos: [], texto: '' });
  assertEquals(um?.restaurant_id, 'goola-acai-guarda');
  assertEquals(um?.itens, [{ product_id: 'goola-bowl', quantity: 1, nome: 'Goola Bowl' }]);
  assertEquals(um?.origem, 'carrinho');
  const cesto = escolherSugestao({ propostas: [PROP_INCOMPLETA, PROP_CONTINENTE], veioDoCesto: true, produtos: [], texto: '' });
  assertEquals(cesto?.restaurant_id, 'continente-guarda');
  assertEquals(cesto?.itens.length, 2);
  assertEquals(escolherSugestao({ propostas: [PROP_GOOLA, PROP_CONTINENTE], veioDoCesto: false, produtos: [], texto: '' }), null);
  assert(sugestaoValida(um));
  assert(!sugestaoValida({ restaurant_id: 'x', itens: [] }));
});

Deno.test('escolherSugestao sem carrinho: o produto que o texto nomeia; o parceiro aberto ganha empates', () => {
  const produtos = [
    { product_id: 'cnt-8773468', nome: 'Açaí Original Native Açaí', loja: 'Continente', restaurant_id: 'continente-guarda', parceiro: false },
    { product_id: 'goola-bowl', nome: 'Goola Bowl', loja: 'Goola Açaí', restaurant_id: 'goola-acai-guarda', parceiro: true, aberta: true },
    { product_id: 'goola-big-bowl', nome: 'Big Bowl', loja: 'Goola Açaí', restaurant_id: 'goola-acai-guarda', parceiro: true, aberta: true },
  ];
  const s = escolherSugestao({ propostas: [], veioDoCesto: false, produtos, texto: 'No Goola Açaí, aberto até às 22h, tens o Goola Bowl com 3 acompanhamentos. Queres?' });
  assertEquals(s?.itens[0].product_id, 'goola-bowl');
  assertEquals(s?.origem, 'produto');
  const nada = escolherSugestao({ propostas: [], veioDoCesto: false, produtos, texto: 'Diz-me o que te apetece.' });
  assertEquals(nada, null);
});

Deno.test('o texto do carrinho montado em código nunca tem preços e manda tocar no botão', () => {
  const t = textoCarrinhoMontado({ restaurant_id: 'goola-acai-guarda', loja: 'Goola Açaí', itens: [{ product_id: 'goola-bowl', quantity: 2, nome: 'Goola Bowl' }], origem: 'produto' }, true);
  assertStringIncludes(t, '2× Goola Bowl do Goola Açaí');
  assertStringIncludes(t, 'Encher o carrinho');
  assert(!/€|\d+,\d{2}/.test(t));
  assertStringIncludes(textoCarrinhoMontado({ restaurant_id: 'r', loja: 'Pingo Doce', itens: [{ product_id: 'a', quantity: 1 }], origem: 'carrinho' }, false), 'fechada');
});

// ─── Parceiro primeiro ────────────────────────────────────────────────────────

Deno.test('açaí: o Goola (parceiro aberto) vem antes do açaí congelado dos supermercados', () => {
  const parceiros = [
    { product_id: 'goola-bowl', restaurant_id: 'goola-acai-guarda', nome: 'Goola Bowl' },
    { product_id: 'goola-big-bowl', restaurant_id: 'goola-acai-guarda', nome: 'Big Bowl' },
  ];
  const busca = [
    { product_id: 'pd-972880', restaurant_id: 'pingodoce-guarda', nome: 'Açaí Original Native 480 ML' },
    { product_id: 'cnt-8773468', restaurant_id: 'continente-guarda', nome: 'Açaí Original Native Açaí' },
    { product_id: 'goola-bowl', restaurant_id: 'goola-acai-guarda', nome: 'Goola Bowl' },
  ];
  const r = parceiroPrimeiro(parceiros, busca);
  assertEquals(r.map((p) => p.product_id), ['goola-bowl', 'goola-big-bowl', 'pd-972880', 'cnt-8773468']);
  // sem parceiro aberto, a pesquisa fica igual
  assertEquals(parceiroPrimeiro([], busca).map((p) => p.product_id), busca.map((p) => p.product_id));
  // outro produto da mesma loja parceira aberta também sobe
  const r2 = parceiroPrimeiro([parceiros[0]], [busca[0], { product_id: 'goola-x', restaurant_id: 'goola-acai-guarda', nome: 'x' }]);
  assertEquals(r2.map((p) => p.product_id), ['goola-bowl', 'goola-x', 'pd-972880']);
});

// ─── Lojas abertas pela hora de Lisboa ────────────────────────────────────────

const H_GOOLA = { mon: { open: '10:00', close: '22:00', closed: false }, tue: { open: '10:00', close: '22:00', closed: false }, wed: { open: '10:00', close: '22:00', closed: false }, thu: { open: '10:00', close: '22:00', closed: false }, fri: { open: '10:00', close: '22:00', closed: false }, sat: { open: '10:00', close: '22:00', closed: false }, sun: { open: '10:00', close: '22:00', closed: false } };
const H_SABORES = { mon: { open: '11:00', close: '18:30', closed: false }, tue: { open: '11:00', close: '18:30', closed: false }, sun: { open: '09:00', close: '22:00', closed: true } };

Deno.test('aberta pela hora de Lisboa (inverno = UTC; verão = UTC+1)', () => {
  // terça 10/11/2026 21:04 em Lisboa (a hora do pedido de açaí)
  const terca2104 = new Date('2026-11-10T21:04:00Z');
  assertEquals(abertaPeloHorario(H_GOOLA, terca2104), { aberta: true, fecha_em_minutos: 56 });
  assertEquals(abertaPeloHorario(H_SABORES, terca2104), { aberta: false, fecha_em_minutos: null });
  // domingo fechado ("closed": true)
  assertEquals(abertaPeloHorario(H_SABORES, new Date('2026-11-15T12:00:00Z')).aberta, false);
  // verão: 21:30 UTC = 22:30 em Lisboa → o Goola já fechou; 20:30 UTC = 21:30 → aberto, fecha em 30 min
  assertEquals(abertaPeloHorario(H_GOOLA, new Date('2026-07-10T21:30:00Z')).aberta, false);
  assertEquals(abertaPeloHorario(H_GOOLA, new Date('2026-07-10T20:30:00Z')), { aberta: true, fecha_em_minutos: 30 });
  // sem horário configurado → aberta (como no banco)
  assertEquals(abertaPeloHorario(null, terca2104).aberta, true);
});

Deno.test('fecho depois da meia-noite, pausa e dia especial', () => {
  const noite = { tue: { open: '20:00', close: '02:00' }, wed: { open: '20:00', close: '02:00' } };
  // quarta 11/11 01:00 em Lisboa
  assertEquals(abertaPeloHorario(noite, new Date('2026-11-11T01:00:00Z')), { aberta: true, fecha_em_minutos: 60 });
  assertEquals(abertaPeloHorario(noite, new Date('2026-11-11T03:00:00Z')).aberta, false);
  const pausa = { tue: { open: '09:00', close: '22:00', break_start: '14:30', break_end: '19:00' } };
  assertEquals(abertaPeloHorario(pausa, new Date('2026-11-10T15:00:00Z')).aberta, false);
  assertEquals(abertaPeloHorario(pausa, new Date('2026-11-10T13:00:00Z')), { aberta: true, fecha_em_minutos: 90 });
  const especial = { ...H_GOOLA, special_dates: [{ date: '2026-11-10', closed: true }] };
  assertEquals(abertaPeloHorario(especial, new Date('2026-11-10T12:00:00Z')).aberta, false);
});

const LOJAS: LojaAberta[] = [
  { id: 'continente-guarda', nome: 'Continente', parceiro: false, categoria: 'supermarket', servico: 'storeShopping', cozinha: 'Supermercado', morada: 'Rua do Ferrinho', lat: 40.5394, lng: -7.2722, fecha_em_minutos: 60 },
  { id: 'jyosmi-sushi-guarda', nome: 'Jyosmi Sushi', parceiro: false, categoria: 'restaurant', servico: 'restaurant', cozinha: 'Sushi · Japonesa', morada: 'Av. de São Miguel 60', lat: 40.5372, lng: -7.2650, fecha_em_minutos: 120 },
  { id: 'goola-acai-guarda', nome: 'Goola Açaí', parceiro: true, categoria: 'restaurant', servico: 'restaurant', cozinha: 'Açaí', morada: 'La Vie Guarda, Piso 3', lat: 40.5450, lng: -7.2500, fecha_em_minutos: 56 },
  { id: 'wells', nome: 'Wells', parceiro: false, categoria: 'pharmacy', servico: 'storeShopping', cozinha: '', morada: 'Continente Modelo', lat: 40.5394, lng: -7.2722, fecha_em_minutos: 30 },
];

Deno.test('lojas abertas: parceiros primeiro, depois as mais perto; filtros por tipo e pelo que se procura', () => {
  const casa = { lat: 40.5373, lng: -7.2676 };
  const todas = ordenarLojas(LOJAS, casa);
  assertEquals(todas[0].id, 'goola-acai-guarda');
  assertEquals(todas[1].id, 'jyosmi-sushi-guarda'); // a mais perto das não parceiras
  assert(typeof todas[1].distancia_km === 'number');
  assertEquals(ordenarLojas(LOJAS, null).map((l) => l.id), ['goola-acai-guarda', 'continente-guarda', 'jyosmi-sushi-guarda', 'wells']);
  assertEquals(filtrarLojas(LOJAS, 'restaurantes').map((l) => l.id), ['jyosmi-sushi-guarda', 'goola-acai-guarda']);
  assertEquals(filtrarLojas(LOJAS, 'mercados').map((l) => l.id), ['continente-guarda']);
  assertEquals(filtrarLojas(LOJAS, 'farmacias').map((l) => l.id), ['wells']);
  assertEquals(filtrarLojas(LOJAS, 'todas', 'açaí').map((l) => l.id), ['goola-acai-guarda']);
  assertEquals(filtrarLojas(LOJAS, 'todas', 'sushi').map((l) => l.id), ['jyosmi-sushi-guarda']);
  assertEquals(tipoDe('restaurantes'), 'restaurantes');
  assertEquals(tipoDe('Farmácias'), 'farmacias');
  assertEquals(tipoDe(undefined), 'todas');
});

Deno.test('link do Google Maps, hora a que fecha e leitura das linhas do banco', () => {
  assertEquals(linkMaps(40.545, -7.25), 'https://www.google.com/maps/search/?api=1&query=40.545000,-7.250000');
  assertEquals(linkMaps(null, -7.25), null);
  assertEquals(horaDaquiA(new Date('2026-11-10T21:04:00Z'), 56), '22:00');
  assertEquals(horaDaquiA(new Date('2026-11-10T23:30:00Z'), 60), '00:30');
  assertEquals(horaDaquiA(new Date(), null), null);
  const l = lojaDe({ id: 'x', nome: 'X', parceiro: true, lat: '40.5', lng: -7.2, fecha_em_minutos: null });
  assertEquals(l?.lat, 40.5);
  assertEquals(l?.fecha_em_minutos, null);
  assertEquals(lojaDe({ nome: 'sem id' }), null);
});
