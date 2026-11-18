// deno test supabase/functions/client-assistant/farmacia_primeiro_test.ts
// 18/11/2026 (missão farmacia-peca-aqui-18-11): caso real da Farmácia da Sé — "vomidrine" não está no
// catálogo da farmácia parceira e a Wells (não-parceira) tem. Regra do Danilo: primeiro o parceiro
// (pedido especial à farmácia), a Wells só por baixo. Dados de brincar (lojas públicas; nada de clientes).
import { assert, assertEquals } from 'jsr:@std/assert@1';
import {
  ACAO_PEDIR_FARMACIA,
  acaoParaApp,
  destinoPedirFarmacia,
  type FarmaciaParceira,
  farmaciaParaPedir,
  lerDestinoPedirFarmacia,
  pareceFarmacia,
  pedirFarmaciaPrimeiro,
} from './sugestao.ts';

const SE: FarmaciaParceira = { restaurant_id: 'farmacia-se-guarda', nome: 'Farmácia da Sé' };
const WELLS_VOMIDRINE = { restaurant_id: 'wells-guarda', parceiro: false, categoria: 'pharmacy' };
const SE_BENURON = { restaurant_id: 'farmacia-se-guarda', parceiro: true, categoria: 'pharmacy' };
const GOOLA_ACAI = { restaurant_id: 'goola-acai', parceiro: true, categoria: 'restaurant' };
const CONTINENTE_ACAI = { restaurant_id: 'continente-guarda', parceiro: false, categoria: 'supermarket' };

Deno.test('vomidrine: a Sé não tem, a Wells tem → pedir à Sé primeiro', () => {
  const f = farmaciaParaPedir({ produtos: [WELLS_VOMIDRINE], farmacias: [SE], termo: 'vomidrine' });
  assertEquals(f, SE);
});

Deno.test('vomidrine: ninguém tem → mesmo assim pedir à Sé (é termo de farmácia)', () => {
  assertEquals(farmaciaParaPedir({ produtos: [], farmacias: [SE], termo: 'quero vomidrine' }), SE);
});

Deno.test('ben-u-ron: a Sé tem no catálogo → não há pedido especial (propõe-se lá, regra 3b)', () => {
  assertEquals(farmaciaParaPedir({ produtos: [SE_BENURON, WELLS_VOMIDRINE], farmacias: [SE], termo: 'ben-u-ron' }), null);
});

Deno.test('açaí: não é coisa de farmácia → nada de farmácia', () => {
  assertEquals(farmaciaParaPedir({ produtos: [GOOLA_ACAI, CONTINENTE_ACAI], farmacias: [SE], termo: 'açaí' }), null);
  assertEquals(farmaciaParaPedir({ produtos: [], farmacias: [SE], termo: 'açaí' }), null);
});

Deno.test('gotas de chocolate só no supermercado → nada de farmácia à frente do carrinho', () => {
  assertEquals(farmaciaParaPedir({ produtos: [CONTINENTE_ACAI], farmacias: [SE], termo: 'gotas de chocolate' }), null);
});

Deno.test('farmácia parceira fechada ou sem pedidos (lista vazia) → fica como antes', () => {
  assertEquals(farmaciaParaPedir({ produtos: [WELLS_VOMIDRINE], farmacias: [], termo: 'vomidrine' }), null);
});

Deno.test('termos de farmácia', () => {
  for (const t of ['vomidrine', 'tenho dor de cabeça', 'xarope para a tosse', 'Ben-u-ron', 'remédio para enjoos', 'pomada']) {
    assert(pareceFarmacia(t), t);
  }
  // Juiz 18/11: palavras com dois sentidos não puxam a farmácia.
  for (const t of ['açaí', 'pizza', 'leite meio gordo', 'cheeseburger', 'gotas de chocolate', 'chá em saquetas',
    'pensos higiénicos', 'receita de bacalhau', 'vitamina de morango']) assert(!pareceFarmacia(t), t);
});

Deno.test('destino "loja|termo" vai e volta, sem "|" no termo', () => {
  const d = destinoPedirFarmacia('farmacia-se-guarda', 'vomidrine | 10 comprimidos');
  assertEquals(d, 'farmacia-se-guarda|vomidrine 10 comprimidos');
  assertEquals(lerDestinoPedirFarmacia(d), { restaurant_id: 'farmacia-se-guarda', termo: 'vomidrine 10 comprimidos' });
  assertEquals(lerDestinoPedirFarmacia('farmacia-se-guarda'), { restaurant_id: 'farmacia-se-guarda', termo: '' });
  assertEquals(lerDestinoPedirFarmacia('|vomidrine'), null);
  assertEquals(lerDestinoPedirFarmacia("x'; drop table|a"), null);
});

Deno.test('resposta do caso Vomidrine: pedir_farmacia PRIMEIRO, a Wells por baixo', () => {
  const acoes = [
    { tipo: 'abrir_loja', rotulo: 'Abrir a Wells', destino: 'wells-guarda' },
    { tipo: ACAO_PEDIR_FARMACIA, rotulo: 'Pedir à Farmácia da Sé', destino: destinoPedirFarmacia(SE.restaurant_id, 'vomidrine') },
  ];
  const ordem = pedirFarmaciaPrimeiro(acoes);
  assertEquals(ordem.map((a) => a.tipo), [ACAO_PEDIR_FARMACIA, 'abrir_loja']);
  assertEquals(ordem[1].destino, 'wells-guarda');
});

Deno.test('app antiga (sem pedir_farmacia) recebe "abrir a farmácia" — nunca um botão que não sabe abrir', () => {
  const a = { tipo: ACAO_PEDIR_FARMACIA, rotulo: 'Pedir à Farmácia da Sé', destino: 'farmacia-se-guarda|vomidrine' };
  assertEquals(acaoParaApp(a, false, 'Farmácia da Sé'), { tipo: 'abrir_loja', rotulo: 'Abrir a Farmácia da Sé', destino: 'farmacia-se-guarda' });
  assertEquals(acaoParaApp(a, true, 'Farmácia da Sé'), a);
  const outra = { tipo: 'abrir_carteira', rotulo: 'Carteira', destino: null };
  assertEquals(acaoParaApp(outra, false, null), outra);
});
