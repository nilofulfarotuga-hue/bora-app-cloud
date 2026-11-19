-- APLICADA EM PRODUÇÃO pela Claude.ai via MCP a 19/11/2026 (versão 20261119161433). Cópia fiel para o repo.
-- Superada pelo texto de 20261119163927 (km de estrada, máx. 32).
-- 19/11/2026 Claude.ai via MCP, ordem do Danilo: a LIMPEZA vai até 28 km do centro da Guarda com taxa
-- de deslocação (entregas continuam só na Guarda, 15 km). Os robôs tinham "Celorico fica fora" para tudo.

create table if not exists public.bkp_support_skills_20261119 as
  select * from public.support_skills where skill_name in ('GENERAL_FAQ','CLEANING_INFO');
create table if not exists public.bkp_assistant_learned_20261119 as
  select * from public.assistant_learned where id in ('52cc00c1-fe1e-450e-95e5-71393bee6fb8','d056bea9-299f-47c5-802a-48dd16a2b2fc');

update public.assistant_learned
   set answer = answer || ' ATENÇÃO, a LIMPEZA é diferente das entregas: a limpeza vai até 28 km do centro da Guarda (ex.: Celorico da Beira, Belmonte, Sabugal, Manteigas, Trancoso), com taxa de deslocação que entra no total: até 10 km não há taxa, de 10 a 15 km são 8 €, acima de 15 km são 15 € mais 1 € por cada km a mais. Pinhel e Covilhã ficam fora também para a limpeza.',
       updated_at = now()
 where id in ('52cc00c1-fe1e-450e-95e5-71393bee6fb8','d056bea9-299f-47c5-802a-48dd16a2b2fc')
   and answer not like '%LIMPEZA é diferente%';

insert into public.assistant_learned (question_norm, question, answer, source, kind, active)
values
('fazem limpeza em celorico da beira',
 'Fazem limpezas fora da Guarda (Celorico, Belmonte, Sabugal, Trancoso, Manteigas)?',
 'Sim. A limpeza vai até 28 km do centro da Guarda — Celorico da Beira, Belmonte, Sabugal, Manteigas e Trancoso entram. Há uma taxa de deslocação que entra no total da limpeza e vai para a profissional: até 10 km do centro da Guarda não há taxa, de 10 a 15 km são 8 €, acima de 15 km são 15 € mais 1 € por cada km a mais (Celorico da Beira fica a cerca de 15 km em linha reta: 15 €). É só marcar na app com a morada da casa. Mais de 28 km (ex.: Pinhel, Covilhã) ainda não fazemos.',
 'admin', 'resposta', true)
on conflict do nothing;

update public.support_skills
   set playbook_md = replace(playbook_md,
         'diz com simpatia que por agora só fazemos a Guarda.',
         'diz com simpatia que por agora só fazemos a Guarda. EXCEÇÃO — LIMPEZA: a limpeza vai até 28 km do centro da Guarda (Celorico da Beira, Belmonte, Sabugal, Manteigas, Trancoso entram) com taxa de deslocação: até 10 km sem taxa, 10 a 15 km 8 €, acima de 15 km 15 € + 1 € por km a mais. Mais de 28 km (Pinhel, Covilhã) não.'),
       updated_at = now()
 where skill_name = 'GENERAL_FAQ' and active and playbook_md not like '%EXCEÇÃO — LIMPEZA%';

update public.support_skills
   set playbook_md = playbook_md || E'\n\n## Zona e taxa de deslocação (19/11/2026)\n- A limpeza vai até **28 km do centro da Guarda** (Celorico da Beira, Belmonte, Sabugal, Manteigas, Trancoso entram; Pinhel e Covilhã não).\n- Taxa de deslocação, entra no total e vai para a profissional: até 10 km **sem taxa**; de 10 a 15 km **8 €**; acima de 15 km **15 € + 1 € por cada km a mais**. Ex.: Celorico da Beira = 15 €.\n- O desconto da limpeza semanal não se aplica à taxa; numa série, a taxa conta em cada visita.\n\n## Mais do que uma profissional\n- Casa grande: o cliente pode escolher **Por horas** e pôr mais horas.\n- Se quiser **2 ou mais profissionais** ao mesmo tempo e a app ainda não mostrar essa opção, a equipa trata disso pelo WhatsApp da Bora (937 501 673). Cada profissional conta as suas horas (2 profissionais = o dobro do preço).',
       updated_at = now()
 where skill_name = 'CLEANING_INFO' and active and playbook_md not like '%Zona e taxa de deslocação%';
