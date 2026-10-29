-- N4 (missao-geral-2026-10-28, Bloco 3): o "Fecho do mês" do painel está PARTIDO desde 28/10 20:34.
--
-- A migração 20261028203348_iva_normal_faturas_bora pôs a frase nova do IVA DENTRO do format() do
-- texto "para as Finanças" do admin_monthly_closeout. A frase tem "23% incluído", e para o format()
-- "% " é um marcador inválido: TODA a chamada falha, em qualquer mês, com
--   ERROR 22023: unrecognized format() type specifier " "
-- (provado a 28/10 com admin_monthly_closeout(2026,10) como admin). O ecrã mostra "Não consegui
-- carregar o fecho".
-- Correção: dentro do format() o "%" passa a "%%" (o texto que sai fica igual, com "23%").
-- E acrescenta 'nota_iva' ao bloco para_as_financas: a frase do IVA tirada do próprio texto, para o
-- painel a mostrar à parte sem a escrever à mão.
-- Não muda nenhuma conta nem nenhum valor. Aplicar na JANELA 2.

-- 0. Cópia da definição de antes (a bkp_fn_admin_monthly_closeout_20261028 já existe, com a de
--    antes da migração do IVA; esta guarda a que está partida)
create table if not exists public.bkp_fn_admin_monthly_closeout_20261028_n4 as
  select now() as guardado_em,
         'public.admin_monthly_closeout(integer,integer)'::text as assinatura,
         pg_get_functiondef('public.admin_monthly_closeout(integer,integer)'::regprocedure) as definicao;
alter table public.bkp_fn_admin_monthly_closeout_20261028_n4 enable row level security;

-- 1. Troca de texto exata (falha se não encontrar cada pedaço exatamente uma vez)
do $$
declare
  v_def text := pg_get_functiondef('public.admin_monthly_closeout(integer,integer)'::regprocedure);
  v_old1 text := 'regime normal (trimestral), com IVA 23% incluído nas faturas da Bora.';
  v_new1 text := 'regime normal (trimestral), com IVA 23%% incluído nas faturas da Bora.';
  v_old2 text := '''texto'', v_texto)';
  v_new2 text := '''texto'', v_texto, ''nota_iva'', substring(v_texto from ''IVA: .*$''))';
  v_n1 int; v_n2 int;
begin
  v_n1 := (length(v_def) - length(replace(v_def, v_old1, ''))) / length(v_old1);
  v_n2 := (length(v_def) - length(replace(v_def, v_old2, ''))) / length(v_old2);
  if v_n1 <> 1 or v_n2 <> 1 then
    raise exception 'admin_monthly_closeout: esperava 1 e 1 ocorrencias, achei % e %', v_n1, v_n2;
  end if;
  execute replace(replace(v_def, v_old1, v_new1), v_old2, v_new2);
end $$;

-- PROVA ESPERADA (feita a 28/10 em transação desfeita, com a definição corrigida criada como
-- _tmp_n4_closeout e chamada como admin):
--   viva  admin_monthly_closeout(2026,10)  -> ERROR 22023 unrecognized format() type specifier " "
--   nova  (2026,10) -> total_a_declarar 107.63; texto acaba em "... com IVA 23% incluído nas faturas da Bora."
--         nota_iva = "IVA: até outubro de 2026, isenção do art. 53.º do CIVA (M10); a partir de novembro
--         de 2026, regime normal (trimestral), com IVA 23% incluído nas faturas da Bora."
--   nova  (2026,11) -> corre sem erro
-- Depois de aplicar, conferir (como admin, num DO com set_config do JWT):
--   admin_monthly_closeout(2026,10)->'para_as_financas'->>'nota_iva' começa por 'IVA:'
