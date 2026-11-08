// deno test supabase/functions/support-chatbot/pessoa_test.ts
import { assert, assertEquals, assertStringIncludes } from 'https://deno.land/std@0.224.0/assert/mod.ts';
import { querFalarComPessoa, respostaPessoa, whatsappDaBora } from './pessoa.ts';

Deno.test('o caso real de 08/11: "falar com assistente" conta como pedir uma pessoa', () => {
  assert(querFalarComPessoa('falar com assistente'));
  assert(querFalarComPessoa('Falar com o atendente'));
  assert(querFalarComPessoa('quero falar com uma pessoa'));
  assert(querFalarComPessoa('posso falar com alguém?'));
  assert(querFalarComPessoa('Quero um humano'));
  assert(querFalarComPessoa('atendimento humano por favor'));
  assert(querFalarComPessoa('não quero falar com um robô'));
  assert(querFalarComPessoa('fala com o responsável'));
});

Deno.test('perguntas normais não escalam', () => {
  assert(!querFalarComPessoa('onde está o meu pedido?'));
  assert(!querFalarComPessoa('quanto custa a entrega?'));
  assert(!querFalarComPessoa('o estafeta não atende o telefone'));
  assert(!querFalarComPessoa('olá'));
  assert(!querFalarComPessoa(''));
});

Deno.test('o WhatsApp é sempre o da Bora, em formato português, com link', () => {
  assertEquals(whatsappDaBora('+351937501673'), { visivel: '937 501 673', link: 'https://wa.me/351937501673' });
  assertEquals(whatsappDaBora('937501673'), { visivel: '937 501 673', link: 'https://wa.me/351937501673' });
  // número estranho nas definições → o da Bora, nunca outro
  assertEquals(whatsappDaBora('123').link, 'https://wa.me/351937501673');
  assertEquals(whatsappDaBora(null).visivel, '937 501 673');
});

Deno.test('a resposta tem o número, o link e nenhum nome de pessoa', () => {
  const r = respostaPessoa('+351937501673');
  assertStringIncludes(r, '937 501 673');
  assertStringIncludes(r, 'https://wa.me/351937501673');
  assert(!/danilo/i.test(r));
});
