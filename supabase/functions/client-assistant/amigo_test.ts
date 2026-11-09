// deno test supabase/functions/client-assistant/amigo_test.ts
import { assert, assertEquals, assertStringIncludes } from 'https://deno.land/std@0.224.0/assert/mod.ts';
import {
  ACAO_NUDGE,
  blocoAmigo,
  candidatasDeixa,
  compararLinhas,
  emocaoPorDefeito,
  extrairEmocao,
  IDENTIDADE_AMIGO,
  lembreteHabitual,
  escolherDeixa,
  habitoDeAgora,
  momentoLisboa,
  pareceConversaLivre,
  pedeAcao,
  perfilParaModelo,
  respostaParaOSistema,
  soConversa,
  saudacaoHabitual,
  saudacaoSimples,
  textoLinhas,
  vencedor,
} from './amigo.ts';

const perfilJyosmi = {
  nome_tratamento: 'Ana',
  habitos: [
    { dia: 5, dia_nome: 'sexta', periodo: 'noite', loja_id: 'jyosmi-sushi-guarda', loja: 'Jyosmi Sushi', vezes: 3, ultimo_pedido_id: 'o3' },
    { dia: 2, dia_nome: 'terça', periodo: 'almoco', loja_id: 'boom', loja: 'Boom', vezes: 2, ultimo_pedido_id: 'o9' },
  ],
  lojas_favoritas: [{ id: 'jyosmi-sushi-guarda', nome: 'Jyosmi Sushi', pedidos: 3 }],
  recorrentes: [{ nome: 'Combinado Tradicional', loja: 'Jyosmi Sushi', vezes: 3 }],
  ticket_medio_eur: 19.88,
  restricoes: ['sem glúten'],
};

Deno.test('momento em Lisboa: sexta 13/11/2026 às 18:30 UTC (inverno = UTC) é sexta, tarde, 18h', () => {
  const m = momentoLisboa(new Date('2026-11-13T18:30:00Z'));
  assertEquals([m.dia, m.diaNome, m.periodo, m.hora], [5, 'sexta', 'tarde', 18]);
});

Deno.test('momento em Lisboa: no verão é UTC+1 (sexta 23:30 UTC já é sábado 00:30)', () => {
  const m = momentoLisboa(new Date('2026-07-10T23:30:00Z'));
  assertEquals([m.dia, m.periodo, m.hora], [6, 'noite', 0]);
});

Deno.test('hábito: sexta ao fim da tarde já conta para o jantar de sexta', () => {
  const h = habitoDeAgora(perfilJyosmi, { dia: 5, diaNome: 'sexta', periodo: 'tarde', hora: 18 });
  assertEquals(h?.loja_id, 'jyosmi-sushi-guarda');
  assertEquals(habitoDeAgora(perfilJyosmi, { dia: 5, diaNome: 'sexta', periodo: 'noite', hora: 20 })?.ultimo_pedido_id, 'o3');
});

Deno.test('hábito: fora do dia/hora não há saudação do costume', () => {
  assertEquals(habitoDeAgora(perfilJyosmi, { dia: 5, diaNome: 'sexta', periodo: 'tarde', hora: 15 }), null);
  assertEquals(habitoDeAgora(perfilJyosmi, { dia: 4, diaNome: 'quinta', periodo: 'noite', hora: 20 }), null);
  assertEquals(habitoDeAgora({}, { dia: 5, diaNome: 'sexta', periodo: 'noite', hora: 20 }), null);
  assertEquals(habitoDeAgora(null, { dia: 5, diaNome: 'sexta', periodo: 'noite', hora: 20 }), null);
});

Deno.test('saudação do costume como o Danilo pediu', () => {
  const h = habitoDeAgora(perfilJyosmi, { dia: 5, diaNome: 'sexta', periodo: 'noite', hora: 20 })!;
  assertEquals(saudacaoHabitual(h, perfilJyosmi),
    'Olá, Ana! Hoje é sexta. Queres o do costume do Jyosmi Sushi? Tenho o teu último pedido pronto para repetir.');
  assertStringIncludes(saudacaoSimples({ dia: 1, diaNome: 'segunda', periodo: 'noite', hora: 21 }, {}, ''), 'Boa noite! Sou o Amigo Bora');
});

Deno.test('conversa livre vai ao modelo pequeno; compras, ajuda e continuações não', () => {
  const o = { temImagem: false, ultimaTinhaCompra: false };
  assert(pareceConversaLivre('o que faço para o jantar?', o));
  assert(pareceConversaLivre('conta-me uma piada', o));
  assert(pareceConversaLivre('está frio na Guarda hoje', o));
  assert(!pareceConversaLivre('quero um hambúrguer bom e uma coca', o));
  assert(!pareceConversaLivre('onde está o meu pedido?', o));
  assert(!pareceConversaLivre('quantos tokens tenho', o));
  assert(!pareceConversaLivre('arroz, leite, 2 ovos', o));
  assert(!pareceConversaLivre('sim', o));
  assert(!pareceConversaLivre('olá', { temImagem: true, ultimaTinhaCompra: false }));
  assert(!pareceConversaLivre('obrigado', { temImagem: false, ultimaTinhaCompra: true }));
});

Deno.test('pedidos de compra/marcação têm de acabar numa ação; ajuda não', () => {
  assert(pedeAcao('quero um hambúrguer bom e uma coca'));
  assert(pedeAcao('faz-me a compra da semana'));
  assert(pedeAcao('preciso de uma faxina sábado'));
  assert(!pedeAcao('quero saber onde está o meu pedido'));
  assert(!pedeAcao('quero falar com uma pessoa'));
  assert(!pedeAcao('o que faço para o jantar?'));
});

Deno.test('deixa: prioridade tokens > check-in > parceiro novo > promoção, e rotação de 24 h', () => {
  const ctx = {
    parceiros_novos: [{ id: 'loja-nova', nome: 'Loja Nova' }],
    promocoes: [{ id: 'b1', titulo: '5 € de boas-vindas', subtitulo: null, tipo_destino: 'codigo', destino: 'BEMVINDO' }],
  };
  const c = candidatasDeixa(ctx, { tokens_balance: 120, expiring_soon_count: 30 },
    { enabled: true, eligible: true, already_done: false, tokens_today: 5 }, '2026-11-08');
  assertEquals(c.map((d) => d.tipo), ['tokens', 'checkin', 'parceiro_novo', 'promocao']);
  assertStringIncludes(c[0].texto, '30 tokens a expirar nos próximos 7 dias');
  assertStringIncludes(c[1].texto, 'vale 5 tokens');
  assertEquals(c[2].acao, { tipo: 'abrir_loja', destino: 'loja-nova' });
  assertEquals(escolherDeixa(c, new Set())?.tipo, 'tokens');
  assertEquals(escolherDeixa(c, new Set(['tokens:2026-11-08', 'checkin:2026-11-08']))?.tipo, 'parceiro_novo');
  assertEquals(escolherDeixa(c, new Set(c.map((d) => d.chave))), null);
});

Deno.test('deixa: sem tokens a expirar e com check-in feito, sobra a promoção', () => {
  const c = candidatasDeixa({ promocoes: [{ id: 'b1', titulo: 'Hambúrguer do mês na Boom!', tipo_destino: 'produto', destino: 'p1' }] },
    { expiring_soon_count: 0 }, { enabled: true, eligible: true, already_done: true }, '2026-11-08');
  assertEquals(c.length, 1);
  assertEquals(c[0].texto, 'Já viste? Hambúrguer do mês na Boom!');
});

Deno.test('perfil para o modelo cabe em ~600 tokens e nunca leva o ticket exato', () => {
  const s = perfilParaModelo(perfilJyosmi);
  assert(s.length <= 2400);
  assertStringIncludes(s, 'sexta noite: Jyosmi Sushi (3x)');
  assertStringIncludes(s, 'cerca de 20 €');
  assert(!s.includes('19.88'));
  const grande = { ...perfilJyosmi, notas: 'x'.repeat(5000), gostos: Array(5).fill('y'.repeat(500)) };
  assert(perfilParaModelo(grande).length <= 2400);
  assertEquals(perfilParaModelo({}), '(ainda não sei nada deste cliente)');
});

Deno.test('comparação linha a linha: honesta nos dois sentidos, calculada em código', () => {
  const outra = [
    { query: 'gyoza', quantity: 1, preco_cents: 450 },
    { query: 'combinado tradicional', quantity: 1, preco_cents: 1400 },
    { query: 'coca-cola', quantity: 1, preco_cents: 250 },
  ];
  const bora = [
    { query: 'gyoza', name: 'Ravioli Frito (Gyoza)', line_total: 4.90 },
    { query: 'combinado tradicional', name: 'Combinado Tradicional', line_total: 12.00 },
    { query: 'coca-cola', name: 'Coca-Cola 33cl', line_total: 2.00 },
  ];
  const l = compararLinhas(outra, bora);
  assertEquals(l.map((x) => x.diferenca_cents), [-40, 200, 50]);
  const t = textoLinhas('Glovo', l, 2510, 2300);
  assertStringIncludes(t, 'Só esse artigo "gyoza", na Glovo fica 0,40 € mais barato.');
  assertStringIncludes(t, 'Com os 3 artigos, no Bora poupas 2,10 €, já com a entrega.');
  assertEquals(vencedor(2510, 2300), 'bora');
  assertEquals(vencedor(2000, 2300), 'outra');
  assertEquals(vencedor(null, 2300), 'sem_total');
});

Deno.test('comparação: sem preço da outra app nessa linha, não se inventa diferença', () => {
  const l = compararLinhas([{ query: 'pizza', quantity: 1, preco_cents: null }], [{ query: 'pizza', name: 'Pizza', line_total: 9 }]);
  assertEquals(l[0].outra_cents, null);
  assertEquals(l[0].diferenca_cents, null);
  assertStringIncludes(textoLinhas('Uber Eats', l, null, 1150), 'manda-me o print do total da Uber Eats');
});

// ─── m11 (09/11/2026): o rosto — a cara de cada resposta e o "amigo para tudo" ───

Deno.test('cara: a etiqueta [cara:...] sai do texto e vira o campo emocao', () => {
  assertEquals(extrairEmocao('[cara:alegre] Encontrei o teu hambúrguer!'), { texto: 'Encontrei o teu hambúrguer!', emocao: 'alegre' });
  assertEquals(extrairEmocao('[ cara : Triste ]Hoje está fechado.').emocao, 'triste');
  assertEquals(extrairEmocao('Olá! [cara:a_falar]').texto, 'Olá!');
  // etiqueta inválida também sai do texto, mas não vira cara
  assertEquals(extrairEmocao('[cara:zangado] Ups.'), { texto: 'Ups.', emocao: null });
  // várias: fica a primeira válida, nenhuma aparece ao cliente
  const r = extrairEmocao('[cara:pensativo] Deixa ver… [cara:alegre]');
  assertEquals(r.emocao, 'pensativo');
  assert(!r.texto.includes('['));
  // sem etiqueta: texto igual
  assertEquals(extrairEmocao('Sem cara nenhuma.'), { texto: 'Sem cara nenhuma.', emocao: null });
});

Deno.test('cara por defeito: carrinho alegre, nada triste, erro confuso, resto a falar', () => {
  assertEquals(emocaoPorDefeito({ erro: false, handoff: false, temCarrinho: true, texto: 'Aqui tens.' }), 'alegre');
  assertEquals(emocaoPorDefeito({ erro: false, handoff: false, temCarrinho: false, texto: 'Não encontrei esse produto.' }), 'triste');
  assertEquals(emocaoPorDefeito({ erro: false, handoff: false, temCarrinho: false, texto: 'A loja está fechada agora.' }), 'triste');
  assertEquals(emocaoPorDefeito({ erro: true, handoff: false, temCarrinho: false, texto: '' }), 'confuso');
  assertEquals(emocaoPorDefeito({ erro: false, handoff: true, temCarrinho: false, texto: 'Passo ao suporte.' }), 'confuso');
  assertEquals(emocaoPorDefeito({ erro: false, handoff: false, temCarrinho: false, texto: 'Está um dia bonito na Guarda.' }), 'a_falar');
});

Deno.test('adendo 1-B: o Amigo é amigo para tudo, nunca "de compras"', () => {
  assertStringIncludes(IDENTIDADE_AMIGO, 'Amigo Bora');
  assertStringIncludes(IDENTIDADE_AMIGO, 'para o que ele quiser');
  // a frase só aparece na regra que PROÍBE dizê-la
  assertEquals(IDENTIDADE_AMIGO.split('de compras').length - 1, 2);
  assertStringIncludes(IDENTIDADE_AMIGO, 'NUNCA te apresentas');
  assert(!blocoAmigo().toLowerCase().includes('assistente de compras'));
  assertStringIncludes(blocoAmigo(), '[cara:alegre]');
});

Deno.test('saudação lembra o habitual pelo nome da loja (e não inventa sem perfil)', () => {
  assertEquals(lembreteHabitual({}), '');
  assertEquals(lembreteHabitual({ lojas_favoritas: [{ nome: 'Boom' }] }), ' Se te apetecer, preparo-te o do costume do Boom.');
  const s = saudacaoSimples({ dia: 1, diaNome: 'segunda', periodo: 'noite', hora: 21 }, perfilJyosmi, '');
  assertStringIncludes(s, 'Boa noite, Ana!');
  assertStringIncludes(s, 'do costume do Jyosmi Sushi');
});

// ─── m11 adendo 4 (09/11/2026): "não quero comprar, só conversar" não é compra; resposta à nota interna descartada ───

const SO_CONVERSA = [
  'não quero comprar nada, só conversar',
  'Não quero comprar nada',
  'nao quero nada obrigado',
  'só quero conversar contigo',
  'só falar um bocado',
  'estou só a ver',
  'estou só a espreitar a app',
  'como estás?',
  'olá, tudo bem?',
  'bom dia!',
  'boa noite Amigo',
  'oi',
  'e aí, como vai?',
  'não vou pedir nada hoje',
  'hoje não preciso de nada',
];
const COMPRAS = [
  'quero um hambúrguer',
  'quero comprar leite e pão',
  'preciso de paracetamol',
  'faz-me uma faxina amanhã às 10',
  'manda vir sushi para o jantar',
  'olá, quero uma pizza',
  'bom dia, preciso de um favor: ir à farmácia',
  'quero encomendar o do costume',
  'compra-me tabaco',
  'traz-me uma coca-cola',
  'quero marcar uma limpeza para sábado',
  'enche o carrinho com o que costumo pedir',
  'queria pedir um kebab',
  'preciso de comprar fraldas',
  "quero comer qualquer coisa do McDonald's",
];

Deno.test('adendo 4: 15 frases de conversa/negação NUNCA forçam ação; são conversa livre', () => {
  for (const f of SO_CONVERSA) {
    assertEquals(pedeAcao(f), false, `pedeAcao("${f}") devia ser false`);
    assertEquals(pareceConversaLivre(f, { temImagem: false, ultimaTinhaCompra: false }), true, `conversa livre: "${f}"`);
  }
});

Deno.test('adendo 4: 15 pedidos de compra/marcação continuam a pedir ação', () => {
  for (const f of COMPRAS) {
    assertEquals(soConversa(f), false, `soConversa("${f}") devia ser false`);
    assertEquals(pedeAcao(f), true, `pedeAcao("${f}") devia ser true`);
  }
});

Deno.test('adendo 4: resposta escrita para a nota interna é apanhada', () => {
  assert(respostaParaOSistema('O cliente disse claramente que não quer comprar nada, só conversar, por isso não vou empurrar nenhuma compra.'));
  assert(respostaParaOSistema('Segundo a nota do sistema, devo terminar com uma ação.'));
  assert(respostaParaOSistema('Não vou empurrar compras, prometo.'));
  assert(respostaParaOSistema('SISTEMA: ok'));
  assert(!respostaParaOSistema('Estou ótimo, obrigado por perguntares! Por aqui está tudo tranquilo. E tu, como está a correr a manhã?'));
  assert(!respostaParaOSistema('Encontrei o teu hambúrguer no Boom. Queres que prepare o carrinho?'));
});

Deno.test('adendo 4: as notas internas pedem resposta direta, por tu, e o Amigo fala como amigo', () => {
  assertStringIncludes(ACAO_NUDGE, 'Responde diretamente à pessoa, por tu');
  assert(!ACAO_NUDGE.startsWith('SISTEMA'));
  assertStringIncludes(blocoAmigo(), 'CONVERSA SOLTA');
  assertStringIncludes(blocoAmigo(), 'nunca dizes "o cliente"');
  assertStringIncludes(blocoAmigo(), 'Estou ótimo, obrigado por perguntares!');
});
