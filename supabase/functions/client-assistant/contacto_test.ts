import { assert, assertEquals, assertStringIncludes } from 'jsr:@std/assert@1';
import { eRespostaGenerica, juntarEscolhidos, notaFaltaContacto, oQueFalta, textoFaltaContacto } from './contacto.ts';

Deno.test('a frase genérica do fecho é reconhecida', () => {
  assert(eRespostaGenerica('Não consegui concluir. Diz-me outra vez o que precisas, por exemplo "arroz, leite e ovos".'));
  assert(eRespostaGenerica(''));
  assert(eRespostaGenerica('Encontrei opções, mas não consegui montar o carrinho desta vez.'));
  assert(!eRespostaGenerica('Tenho croissants a 0,87 € no Continente.'));
});

Deno.test('o que falta, por extenso', () => {
  assertEquals(oQueFalta({ morada: true, telefone: true }), 'a tua morada e o teu telemóvel');
  assertEquals(oQueFalta({ morada: true, telefone: false }), 'a tua morada');
  assertEquals(oQueFalta({ morada: false, telefone: true }), 'o teu telemóvel');
  assertEquals(oQueFalta({ morada: false, telefone: false }), '');
});

Deno.test('caso da Lena: sem morada, mostra o que escolheu com os preços', () => {
  const t = textoFaltaContacto({ morada: true, telefone: false }, [
    { nome: 'Croissant Folhado', loja: 'Continente', preco: 1.0, quantidade: 2 },
    { nome: 'Leite Meio Gordo Fresco Vigor', loja: 'Continente', preco: 2.63, quantidade: 1 },
    { nome: 'Croissant Folhado', loja: 'Continente', preco: 1.0, quantidade: 1 },
  ]);
  assertStringIncludes(t, 'só falta a tua morada');
  assertStringIncludes(t, 'Pôr os meus dados');
  assertStringIncludes(t, 'número da porta');
  assertStringIncludes(t, '2× Croissant Folhado (Continente) — 1,00 €');
  assertStringIncludes(t, 'Leite Meio Gordo Fresco Vigor (Continente) — 2,63 €');
  assert(!t.includes('Não consegui'));
  assert(!t.includes('telemóvel'));
});

Deno.test('sem telemóvel: fala da chamada ou WhatsApp', () => {
  const t = textoFaltaContacto({ morada: false, telefone: true }, []);
  assertStringIncludes(t, 'o teu telemóvel');
  assertStringIncludes(t, 'chamada ou WhatsApp');
  assert(!t.includes('já escolhi'));
});

Deno.test('nada em falta: sem texto', () => {
  assertEquals(textoFaltaContacto({ morada: false, telefone: false }, []), '');
});

Deno.test('juntar escolhidos tira repetidos e limita', () => {
  const muitos = Array.from({ length: 10 }, (_, i) => ({ nome: `P${i}`, loja: 'L', preco: 1, quantidade: 1 }));
  assertEquals(juntarEscolhidos(muitos).length, 6);
  assertEquals(juntarEscolhidos([{ nome: ' ', loja: '', preco: null, quantidade: 1 }]).length, 0);
});

Deno.test('a nota ao modelo proíbe o "não consegui"', () => {
  const n = notaFaltaContacto({ morada: true, telefone: true });
  assertStringIncludes(n, 'a tua morada e o teu telemóvel');
  assertStringIncludes(n, 'Não digas "não consegui"');
});
