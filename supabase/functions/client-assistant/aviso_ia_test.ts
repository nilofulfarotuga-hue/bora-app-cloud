// deno test supabase/functions/client-assistant/aviso_ia_test.ts
// Missão fechar-tudo-2026-11-10, bloco E6: o assistente diz que é uma IA na primeira fala de cada
// conversa (Reg. (UE) 2024/1689, art. 50.º/1) e só guarda alergias/dietas com o "sim" do cliente
// (RGPD, art. 9.º/2 a)).
import { assert, assertEquals } from 'https://deno.land/std@0.224.0/assert/mod.ts';
import { AVISO_IA, comAvisoIA, consentimentoExplicito, eDadoDeSaude, jaDizQueEIA } from './amigo.ts';

Deno.test('primeira fala: começa pelo aviso de IA', () => {
  assertEquals(comAvisoIA('Boa tarde, Ana! Pergunta-me o que quiseres.', true),
    `${AVISO_IA} Boa tarde, Ana! Pergunta-me o que quiseres.`);
});

Deno.test('as falas seguintes não repetem o aviso', () => {
  assertEquals(comAvisoIA('Aqui tens as lojas.', false), 'Aqui tens as lojas.');
});

Deno.test('se o texto já diz que é uma IA, não se duplica', () => {
  const t = 'Olá! Sou o Amigo, uma inteligência artificial do Bora.';
  assertEquals(comAvisoIA(t, true), t);
  assert(jaDizQueEIA('Sou uma IA do Bora.'));
  // "ia" do verbo ir e "dia" não contam como aviso.
  assert(!jaDizQueEIA('Eu ia pedir uma pizza hoje, bom dia.'));
});

Deno.test('fala vazia na primeira vez: fica só o aviso', () => {
  assertEquals(comAvisoIA('', true), AVISO_IA);
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
