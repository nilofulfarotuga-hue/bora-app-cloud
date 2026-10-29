create table if not exists public.bkp_fn_produto_e_maior_18_v2_teste_20261028 as
  select now() as guardado_em, 'produto_e_maior_18_v2_teste(text,text,text,text)'::text as assinatura,
         pg_get_functiondef('public.produto_e_maior_18_v2_teste(text,text,text,text)'::regprocedure) as definicao;
alter table public.bkp_fn_produto_e_maior_18_v2_teste_20261028 enable row level security;
drop function public.produto_e_maior_18_v2_teste(text,text,text,text);
