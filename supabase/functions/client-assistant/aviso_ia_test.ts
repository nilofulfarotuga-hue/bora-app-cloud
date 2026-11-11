// deno test supabase/functions/client-assistant/aviso_ia_test.ts
// Missão fechar-tudo-2026-11-10, bloco E6, revisto a 11/11/2026 (ordem do Danilo, 10:54: "ele não tem que
// falar que é inteligência artificial"): o aviso de IA SAIU DA FALA — está na etiqueta "assistente virtual"
// do cabeçalho do ecrã do Amigo e na Informação legal da app (Reg. (UE) 2024/1689, art. 50.º/1). As alergias
// e dietas continuam a guardar-se só com o "sim" do cliente (RGPD, art. 9.º/2 a)).
import { assert, assertEquals } from 'https://deno.land/std@0.224.0/assert/mod.ts';
import { AVISO_IA, consentimentoExplicito, eDadoDeSaude, saudacaoSimples, semAvisoIA } from './amigo.ts';

Deno.test('a frase antiga do aviso sai da fala (o modelo copiava-a do histórico)', () => {
  assertEquals(semAvisoIA(`${AVISO_IA} A Goola Açaí está aberta até às 22:00.`), 'A Goola Açaí está aberta até às 22:00.');
  assertEquals(semAvisoIA('Aqui tens as lojas.'), 'Aqui tens as lojas.');
  assertEquals(semAvisoIA(AVISO_IA), '');
});

Deno.test('a resposta honesta a "és um robô?" fica (só sai a frase antiga exata)', () => {
  const t = 'Sou o assistente virtual do Bora, uma inteligência artificial. Se quiseres, há pessoas da equipa no suporte.';
  assertEquals(semAvisoIA(t), t);
});

Deno.test('a saudação é natural e não diz que é uma IA', () => {
  const s = saudacaoSimples({ dia: 3, diaNome: 'quarta', periodo: 'manha', hora: 10 }, { nome_tratamento: 'Ana' }, '');
  assert(s.startsWith('Bom dia, Ana! Sou o Amigo Bora.'), s);
  assert(!/intelig[eê]ncia artificial|\bIA\b/.test(s), s);
});

Deno.test('alergias, intolerâncias e dietas são dados de saúde', () => {
  assert(eDadoDeSaude('restricao_alimentar', 'x', 'y'));
  assert(eDadoDeSaude('nota', 'saúde', 'sou celíaco'));
  assert(eDadoDeSaude('nota', 'amendoim', 'alergia a amendoim'));
  assert(eDadoDeSaude('nota', 'comida', 'sem lactose'));
  assert(!eDadoDeSaude('marca_preferida', 'leite', 'Mimosa'));
  assert(!eDadoDeSaude('orcamento_habitual', 'semana', '30 euros'));
});

Deno.test('consentimento: só um sim claro conta', () => {
  for (const sim of ['sim', 'Sim, podes guardar', 'podes', 'pode sim', 'ok', 'claro', 'guarda isso', 'autorizo', 'está bem']) {
    assert(consentimentoExplicito(sim), sim);
  }
  for (const nao of ['não', 'nao guardes', 'sim mas não guardes', 'sou celíaco', '', 'nunca', 'agora não']) {
    assert(!consentimentoExplicito(nao), nao);
  }
});
