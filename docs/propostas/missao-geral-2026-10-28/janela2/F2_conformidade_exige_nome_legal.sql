-- F2 (missao-geral-2026-10-28, Bloco 3): _conformidade_em_falta passa a exigir o NOME LEGAL escrito.
--
-- O que estava (definição viva lida a 28/10, igual à migração 20261027220207):
--   o 'nome' contava como preenchido com legal_name OU, nas linhas SEM a chave business_hours
--   (estafetas, limpeza, lavagem), com o campo "name" — o nome que aparece na app, que pode ser um
--   nome comercial ou só o primeiro nome, não o nome do documento que o DAC7 pede.
--   As lojas e os prestadores de serviços (com business_hours) já só aceitavam legal_name.
-- Agora: o 'nome' só conta com legal_name escrito (sem espaços à volta), para TODOS os tipos.
-- O resto (NIF, morada, IBAN, data de nascimento só para pessoa singular, autocertificação) fica igual.
-- A app já obriga a escrever o nome completo (LegalFieldsValidators.legalName, mínimo 3 letras) em
-- todos os papéis, por isso os registos novos não mudam. Muda para as linhas antigas sem legal_name:
-- passam a aparecer com 'nome' em falta no painel de conformidade e no DAC7, e o portão
-- trg_conformidade_antes_de_ativar pede o nome legal na próxima vez que alguém for aprovado.
-- Função interna (só chamada por outras funções e gatilhos): fecha-se a public/anon.
-- Não toca em dinheiro. Aplicar na JANELA 2.

-- 0. Cópia da definição de antes
create table if not exists public.bkp_fn_conformidade_em_falta_20261028 as
  select now() as guardado_em,
         'public._conformidade_em_falta(jsonb)'::text as assinatura,
         pg_get_functiondef('public._conformidade_em_falta(jsonb)'::regprocedure) as definicao;
alter table public.bkp_fn_conformidade_em_falta_20261028 enable row level security;

-- 1. Função nova (mesma assinatura)
create or replace function public._conformidade_em_falta(p_row jsonb)
 returns text[]
 language sql
 immutable
as $function$
  SELECT ARRAY(
    SELECT x FROM unnest(ARRAY[
      CASE WHEN NULLIF(btrim(COALESCE(p_row->>'legal_name', '')), '') IS NULL THEN 'nome' END,
      CASE WHEN regexp_replace(COALESCE(p_row->>'nif', ''), '[^0-9]', '', 'g') !~ '^[0-9]{9}$' THEN 'nif' END,
      CASE WHEN NULLIF(btrim(COALESCE(p_row->>'address', p_row->>'base_address', '')), '') IS NULL THEN 'morada' END,
      CASE WHEN upper(regexp_replace(COALESCE(p_row->>'iban', ''), '\s', '', 'g')) !~ '^PT[0-9]{23}$' THEN 'iban' END,
      CASE WHEN NULLIF(p_row->>'birth_date', '') IS NULL
            AND regexp_replace(COALESCE(p_row->>'nif', ''), '[^0-9]', '', 'g') !~ '^[5679][0-9]{8}$'
           THEN 'data_nascimento' END,
      CASE WHEN NULLIF(p_row->>'dsa_self_certified_at', '') IS NULL THEN 'autocertificacao' END
    ]) AS x WHERE x IS NOT NULL);
$function$;

-- 2. Interna: fecha a public e anon (authenticated e service_role mantêm a permissão que já têm;
--    os gatilhos de conformidade correm como quem escreve, que nunca é anon).
revoke all on function public._conformidade_em_falta(jsonb) from public, anon;
grant execute on function public._conformidade_em_falta(jsonb) to authenticated, service_role;

-- PROVA ESPERADA (feita a 28/10 em transação desfeita, com a função nova criada como
-- _tmp_f2_conformidade_em_falta e comparada linha a linha com a viva):
--   {"name":"Loja X"}                                 viva: sem 'nome'   nova: com 'nome'
--   {"name":"Loja X","legal_name":"  "}               viva e nova: com 'nome'
--   {"name":"Loja X","legal_name":"Pessoa Y"}         viva e nova: sem 'nome'
--   {"name":"Loja X","business_hours":{}}             viva e nova: com 'nome'
--   lojas (6) e prestadores de serviços (4): 0 linhas mudam
--   ganham 'nome' em falta: estafetas 12 de 17 (7 aprovados), limpeza 3 de 5 (1 aprovado),
--   lavagem 2 de 2 (2 aprovados); nenhuma linha perde 'nome'
--   todas as outras faltas (nif, morada, iban, data_nascimento, autocertificacao): 0 diferenças
-- Depois de aplicar, conferir:
--   select public._conformidade_em_falta('{"name":"Loja X"}'::jsonb) @> array['nome'];  -- true
--   select has_function_privilege('anon', 'public._conformidade_em_falta(jsonb)', 'execute');  -- false
