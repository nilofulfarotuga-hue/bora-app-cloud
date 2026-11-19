-- APLICADA EM PRODUÇÃO pela Claude.ai via MCP a 19/11/2026 (versão 20261119163927). Cópia fiel para o repo.
-- 19/11/2026: a taxa da limpeza passou a ser por km de ESTRADA (máximo 32 km). Atualiza o que os robôs dizem.
update public.assistant_learned
   set answer = regexp_replace(answer, ' ATENÇÃO, a LIMPEZA é diferente das entregas:.*$',
     ' ATENÇÃO, a LIMPEZA é diferente das entregas: a limpeza vai até 32 km de estrada desde o centro da Guarda (ex.: Celorico da Beira, Belmonte, Jarmelo, Gonçalo), com taxa de deslocação que entra no total: até 10 km de estrada não há taxa, de 10 a 15 km são 8 €, acima de 15 km são 15 € mais 1 € por cada km a mais (Celorico da Beira ≈ 29 €). Sabugal, Trancoso, Manteigas, Pinhel e Covilhã ficam fora também para a limpeza.'),
       updated_at = now()
 where id in ('52cc00c1-fe1e-450e-95e5-71393bee6fb8','d056bea9-299f-47c5-802a-48dd16a2b2fc');

update public.assistant_learned
   set question = 'Fazem limpezas fora da Guarda (Celorico, Belmonte, Jarmelo, Gonçalo)?',
       answer = 'Sim. A limpeza vai até 32 km de estrada desde o centro da Guarda — Celorico da Beira, Belmonte, Jarmelo e Gonçalo entram. Há uma taxa de deslocação que entra no total da limpeza e vai para a profissional: até 10 km de estrada não há taxa, de 10 a 15 km são 8 €, acima de 15 km são 15 € mais 1 € por cada km a mais (Celorico da Beira fica a cerca de 29 km de estrada: cerca de 29 €). É só marcar na app com a morada da casa. Mais longe (ex.: Sabugal, Trancoso, Manteigas, Pinhel, Covilhã) ainda não fazemos.',
       updated_at = now()
 where question_norm = 'fazem limpeza em celorico da beira';

update public.support_skills
   set playbook_md = regexp_replace(playbook_md,
         'EXCEÇÃO — LIMPEZA:[^\n]*',
         'EXCEÇÃO — LIMPEZA: a limpeza vai até 32 km de ESTRADA do centro da Guarda (Celorico da Beira, Belmonte, Jarmelo, Gonçalo entram) com taxa de deslocação: até 10 km sem taxa, 10 a 15 km 8 €, acima de 15 km 15 € + 1 € por km a mais (Celorico ≈ 29 €). Sabugal, Trancoso, Manteigas, Pinhel e Covilhã não.'),
       updated_at = now()
 where skill_name = 'GENERAL_FAQ' and active;

update public.support_skills
   set playbook_md = regexp_replace(playbook_md,
         '## Zona e taxa de deslocação \(19/11/2026\).*?(\n\n## Mais do que uma profissional)',
         E'## Zona e taxa de deslocação (19/11/2026)\n- Conta-se em **km de estrada** (de carro) desde o centro da Guarda, não em linha reta.\n- A limpeza vai até **32 km de estrada** (Celorico da Beira, Belmonte, Jarmelo, Gonçalo entram; Sabugal, Trancoso, Manteigas, Pinhel e Covilhã não).\n- Taxa de deslocação, entra no total e vai para a profissional: até 10 km **sem taxa**; de 10 a 15 km **8 €**; acima de 15 km **15 € + 1 € por cada km a mais**. Ex.: Celorico da Beira ≈ 29 €, Belmonte ≈ 31 €.\n- O desconto da limpeza semanal não se aplica à taxa; numa série, a taxa conta em cada visita.\\1'),
       updated_at = now()
 where skill_name = 'CLEANING_INFO' and active;
