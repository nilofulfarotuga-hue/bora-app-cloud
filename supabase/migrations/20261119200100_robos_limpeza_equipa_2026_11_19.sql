-- 19/11/2026 — missão limpeza-longe-e-equipa-2026-11-19, BLOCO B ponto 10.
-- A app já deixa escolher "Quantas profissionais?" (modo Por hora). Os robôs deixam de mandar o
-- cliente para o WhatsApp para pedir 2 profissionais e passam a explicar a opção nova.

create table if not exists public.bkp_support_skills_20261119_equipa as
  select * from public.support_skills where skill_name in ('GENERAL_FAQ','CLEANING_INFO');

update public.support_skills
   set playbook_md = regexp_replace(playbook_md,
         '## Mais do que uma profissional.*$',
         E'## Mais do que uma profissional (equipa, 19/11/2026)\n'
         || E'- Na app, no modo **Por hora**, o cliente escolhe **Quantas profissionais?** (1, 2 ou 3). Cada uma faz as horas escolhidas, todas à mesma hora.\n'
         || E'- Preço = preço de uma profissional × nº de profissionais + produtos de limpeza (uma vez só) + a taxa de deslocação de cada uma. Ex.: Celorico da Beira, Standard, 4 h, 2 profissionais = 154 €.\n'
         || E'- No modo por tamanho, em T3 e T4+ a app mostra "Casa grande ou vivenda? Com 2 profissionais fica pronto mais depressa" e passa sozinha para Por hora com 2 profissionais.\n'
         || E'- Paga-se uma vez só (MB Way ou cartão). Em dinheiro, entrega-se a cada profissional a sua parte; a app diz quanto.\n'
         || E'- Cada profissional tem o seu chat com o cliente. Se uma desistir, só a vaga dela volta a ser oferecida; o cliente não perde nada.\n'
         || E'- Numa limpeza semanal ou quinzenal, a equipa repete-se (as mesmas profissionais primeiro).'),
       updated_at = now()
 where skill_name = 'CLEANING_INFO' and active and playbook_md like '%## Mais do que uma profissional%';

insert into public.assistant_learned (question_norm, question, answer, source, kind, active)
values
('posso marcar mais do que uma profissional para a limpeza',
 'Posso marcar 2 ou mais profissionais para a mesma limpeza?',
 'Sim. Na app, em Limpeza, escolhe "Por hora" e depois "Quantas profissionais?" (1, 2 ou 3). Cada profissional faz as horas que escolheres, todas à mesma hora, e o preço é o de uma profissional vezes o número de profissionais, mais os produtos (uma vez só) e a taxa de deslocação de cada uma. Pagas uma vez só por MB Way ou cartão; em dinheiro, entregas a cada uma a sua parte e a app diz quanto. Para uma casa grande (T3, T4 ou vivenda) a própria app sugere 2 profissionais.',
 'admin', 'resposta', true)
on conflict do nothing;
