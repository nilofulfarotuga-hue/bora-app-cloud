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
