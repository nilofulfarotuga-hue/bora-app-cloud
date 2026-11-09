// deno test supabase/functions/assistant-profile-refresh/perfil_test.ts
import { assert, assertEquals } from 'https://deno.land/std@0.224.0/assert/mod.ts';
import { montarPerfil } from './perfil.ts';

const factos = {
  pedidos_entregues: 4, ultimo_pedido_em: '2026-11-06', ticket_medio_eur: '19.88',
  categorias: { restaurante: 3, mercado: 1, favores: 0, limpeza: 1 },
  lojas_favoritas: [{ id: 'jyosmi-sushi-guarda', nome: 'Jyosmi Sushi', pedidos: 3 }],
  recorrentes: [{ nome: 'Combinado Tradicional', loja: 'Jyosmi Sushi', vezes: 3 }],
  habitos: [{ dia: 5, periodo: 'noite', loja_id: 'jyosmi-sushi-guarda', loja: 'Jyosmi Sushi', vezes: 3, ultimo_pedido_id: 'o3' }],
};

Deno.test('junta factos, memórias e o que veio da conversa', () => {
  const p = montarPerfil(factos,
    [{ kind: 'restricao_alimentar', key: 'glúten', value: { text: 'sem glúten' } }, { kind: 'marca_preferida', key: 'leite', value: { text: 'Mimosa' } }],
    { nome_tratamento: 'Ana', registo: 'informal', restricoes: ['vegetariana'], gostos: ['adora sushi'], notas: 'prefere jantar cedo' }, {});
  assertEquals(p.nome_tratamento, 'Ana');
  assertEquals(p.registo, 'informal');
  assertEquals(p.restricoes, ['sem glúten', 'vegetariana']);
  assertEquals(p.gostos, ['leite: Mimosa', 'adora sushi']);
  assertEquals(p.ticket_medio_eur, 19.88);
  assertEquals(p.habitos[0].ultimo_pedido_id, 'o3');
});

Deno.test('nunca guarda dados de pagamento, telefones, emails ou moradas', () => {
  const p = montarPerfil(factos, [{ kind: 'nota', key: 'x', value: { text: 'cartão 4111 1111 1111 1111' } }],
    { nome_tratamento: 'ana@mail.pt', restricoes: ['telefone 912345678'], gostos: ['paga com MB Way', 'gosta de pizza'], notas: 'mora na Rua Direita 5' }, {});
  assertEquals(p.nome_tratamento, null);
  assertEquals(p.restricoes, []);
  assertEquals(p.gostos, ['gosta de pizza']);
  assertEquals(p.notas, null);
  assert(!JSON.stringify(p).match(/4111|912345678|@|MB Way|Rua/));
});

Deno.test('sem conversa nova mantém o que já sabia', () => {
  const p = montarPerfil(factos, [], null, { nome_tratamento: 'Ana', registo: 'formal', restricoes: ['sem lactose'], notas: 'x' });
  assertEquals([p.nome_tratamento, p.registo, p.restricoes[0], p.notas], ['Ana', 'formal', 'sem lactose', 'x']);
});
