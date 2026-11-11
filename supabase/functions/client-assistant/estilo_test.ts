// deno test supabase/functions/client-assistant/estilo_test.ts
// 11/11/2026 (ordem do Danilo, 10:54): o Amigo mais humano. As frases de teste são as respostas reais da
// conta de teste de 11/11 (o nome trocado por "Ana").
import { assert, assertEquals } from 'jsr:@std/assert@1';
import {
  afinarFala,
  pedeVariasCoisas,
  perguntaQuemEs,
  podeOutroCarrinho,
  semNomeNoInicio,
  semParabensRepetidos,
  semReapresentacao,
  textosDoAssistente,
  ultimasMensagens,
  umaSugestaoSo,
} from './estilo.ts';

Deno.test('não se reapresenta depois da saudação', () => {
  assertEquals(semReapresentacao('Olá! Sou o Amigo Bora. A Goola está aberta até às 22h.'), 'Olá! A Goola está aberta até às 22h.');
  assertEquals(semReapresentacao('Eu sou o Amigo, o teu amigo da Guarda. Queres açaí?'), 'Queres açaí?');
  assertEquals(semReapresentacao('Sou o Bora Assistente. Aqui tens.'), 'Aqui tens.');
  // nada a tirar: fica igual
  assertEquals(semReapresentacao('A Goola está aberta até às 22h.'), 'A Goola está aberta até às 22h.');
  // só uma apresentação: não fica vazio
  assertEquals(semReapresentacao('Sou o Amigo Bora.'), 'Sou o Amigo Bora.');
});

Deno.test('a pergunta "és um robô?" deixa-o dizer quem é', () => {
  for (const f of ['és um robô?', 'tu és uma pessoa?', 'quem és tu?', 'estou a falar com uma pessoa?', 'falo com um robô?', 'és uma IA?']) {
    assert(perguntaQuemEs(f), f);
  }
  for (const f of ['quero açaí', 'o que há este fim de semana na Guarda?', 'como vai estar o tempo amanhã?']) {
    assert(!perguntaQuemEs(f), f);
  }
  const t = 'Sou o assistente virtual do Bora. Há pessoas da equipa no suporte, se quiseres.';
  assertEquals(afinarFala(t, { nome: 'Ana', anteriores: [], mensagem: 'és um robô?' }), t);
});

Deno.test('não abre a resposta pelo nome; o vocativo repetido sai', () => {
  assertEquals(
    semNomeNoInicio('Ana, a Goola Açaí está aberta até às 22:00 e tem uma taça pronta.', 'Ana', false),
    'A Goola Açaí está aberta até às 22:00 e tem uma taça pronta.',
  );
  assertEquals(semNomeNoInicio('Está pronto, Ana! Toca em "Encher o carrinho".', 'Ana', true), 'Está pronto! Toca em "Encher o carrinho".');
  // ainda não usou o nome na conversa: o vocativo do meio pode ficar uma vez
  assertEquals(semNomeNoInicio('Está pronto, Ana! Toca em "Encher o carrinho".', 'Ana', false), 'Está pronto, Ana! Toca em "Encher o carrinho".');
  assertEquals(semNomeNoInicio('Anabela já pediu.', 'Ana', true), 'Anabela já pediu.');
  assertEquals(semNomeNoInicio('Ana, olá', null, false), 'Ana, olá');
});

Deno.test('parabéns uma vez só na conversa', () => {
  const t = 'Está pronto! O açaí fica em 10,48 € no total. Parabéns pelos anos! 🎉';
  assertEquals(semParabensRepetidos(t, true), 'Está pronto! O açaí fica em 10,48 € no total.');
  assertEquals(semParabensRepetidos(t, false), t);
});

Deno.test('uma sugestão só: as segundas opções saem, as ações ficam', () => {
  assertEquals(
    umaSugestaoSo('A Goola Bowl fica em 12,48 € com a entrega. Toca em "Encher o carrinho". Se preferires uma maior, há a Big Bowl por 11,55 €.'),
    'A Goola Bowl fica em 12,48 € com a entrega. Toca em "Encher o carrinho".',
  );
  assertEquals(
    umaSugestaoSo('Toca em "Encher o carrinho" para pedir.\n\nSe tiveres mais fome, também há a Big Bowl por 11,55 €. E parabéns pelo dia, já agora!'),
    'Toca em "Encher o carrinho" para pedir.\n\nE parabéns pelo dia, já agora!',
  );
  // uma ação alternativa (agendar) fica
  const agendar = 'O Pingo Doce está fechado. Se preferires, podes agendá-lo para as 8h.';
  assertEquals(umaSugestaoSo(agendar), agendar);
  // nunca fica vazio
  assertEquals(umaSugestaoSo('Também há a Big Bowl.'), 'Também há a Big Bowl.');
});

Deno.test('tudo junto, nas respostas reais de 11/11', () => {
  const anteriores = ['Ana, os resultados que encontrei são todos de verão.', 'Está pronto, Ana! Parabéns pelos anos! 🎉'];
  const r = afinarFala(
    'Ana, a Goola Açaí está aberta até às 22:00, por isso montei-te uma Goola Bowl, que com a entrega dá 12,48 €. Toca em "Encher o carrinho". E parabéns pelo dia! 🎉 Se preferires uma maior, há a Big Bowl por 11,55 €.',
    { nome: 'Ana', anteriores, mensagem: 'quero açaí' },
  );
  assertEquals(r, 'A Goola Açaí está aberta até às 22:00, por isso montei-te uma Goola Bowl, que com a entrega dá 12,48 €. Toca em "Encher o carrinho".');
  assert(!r.includes('Ana'));
  // sem nada para afinar, igual
  assertEquals(afinarFala('Amanhã chove na Guarda, segundo o IPMA.', { nome: 'Ana', anteriores: [], mensagem: 'tempo?' }), 'Amanhã chove na Guarda, segundo o IPMA.');
});

Deno.test('um carrinho só num pedido de uma coisa; vários numa lista ou comparação', () => {
  assert(podeOutroCarrinho(0, 'quero um hambúrguer'));
  assert(!podeOutroCarrinho(1, 'quero um hambúrguer'));
  assert(!podeOutroCarrinho(1, 'me dá uma vontade de comer hambúrguer'));
  assert(!podeOutroCarrinho(1, 'quero açaí'));
  assert(podeOutroCarrinho(1, 'vitamina C mais barata e um remédio para a gripe'));
  assert(podeOutroCarrinho(1, 'arroz, leite e ovos'));
  assert(podeOutroCarrinho(1, 'compara o McDonald\'s e o Burger King'));
  assert(podeOutroCarrinho(1, 'qual é o hambúrguer mais barato?'));
  assert(pedeVariasCoisas('quero um hambúrguer e uma coca'));
  assert(!pedeVariasCoisas('eu tava aqui pensando Eu queria dar uma volta de comer um Açaí'));
});

Deno.test('o histórico são as últimas N mensagens, com as ferramentas delas', () => {
  const linhas = [
    { role: 'user', content: 'u1' }, { role: 'assistant', content: 'a1' },
    { role: 'user', content: 'u2' }, { role: 'tool', content: 't2' }, { role: 'assistant', content: 'a2' },
    { role: 'user', content: 'u3' }, { role: 'tool', content: 't3' }, { role: 'tool', content: 't3b' }, { role: 'assistant', content: 'a3' },
    { role: 'user', content: 'u4' },
  ];
  assertEquals(ultimasMensagens(linhas, 3).map((l) => l.content), ['u3', 't3', 't3b', 'a3', 'u4']);
  assertEquals(ultimasMensagens(linhas, 4).map((l) => l.content), ['a2', 'u3', 't3', 't3b', 'a3', 'u4']);
  assertEquals(ultimasMensagens(linhas, 50).length, linhas.length);
  assertEquals(textosDoAssistente(linhas), ['a1', 'a2', 'a3']);
});
