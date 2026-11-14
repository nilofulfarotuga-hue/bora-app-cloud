-- Missão fechar-app-15-11, Bloco 9 (14/11/2026) — POR APLICAR (aplica a Claude.ai).
--
-- Medido por SELECT a 14/11 22:55: há 20 tabelas de cópia de segurança
-- (bkp_*) no esquema public SEM a proteção por linha ligada, e 13 delas podem
-- ser lidas E escritas por qualquer pessoa com a chave pública da app (sem
-- login). Entre elas: cópias do código de funções (bkp_fn_create_order_20261104,
-- bkp_fn_finalize_storeshopping_v2_20261104, bkp_funcoes_nif_20261110), uma
-- página do livro (bkp_claude_ai_memoria_dsh_como_usar_20261108) e 224
-- identificadores de utilizadores (bkp_users_tvde_access_20261104).
--
-- A regra da casa é "cópia de segurança com a proteção ligada". Isto liga-a em
-- TODAS as bkp_* que a tenham desligada e tira o acesso a quem não é servidor.
-- Nenhuma app lê estas tabelas (são só para repor dados à mão): quem repõe é o
-- servidor (postgres / service_role), que passa por cima da proteção.
-- Não apaga nem muda nenhuma linha.

do $$
declare
  t record;
  n int := 0;
begin
  for t in
    select c.oid::regclass as tabela
      from pg_class c
      join pg_namespace ns on ns.oid = c.relnamespace
     where ns.nspname = 'public'
       and c.relkind in ('r', 'p')
       and c.relname like 'bkp\_%' escape '\'
     order by c.relname
  loop
    execute format('alter table %s enable row level security', t.tabela);
    execute format('revoke all on %s from public, anon, authenticated', t.tabela);
    n := n + 1;
  end loop;
  raise notice 'bkp_tabelas_fechadas: % tabelas de cópia fechadas', n;
end
$$;

-- Prova dentro da própria migração: se ficar alguma bkp_* aberta, falha e nada muda.
do $$
declare
  v_abertas text;
begin
  select string_agg(c.relname, ', ')
    into v_abertas
    from pg_class c
    join pg_namespace ns on ns.oid = c.relnamespace
   where ns.nspname = 'public'
     and c.relkind in ('r', 'p')
     and c.relname like 'bkp\_%' escape '\'
     and (not c.relrowsecurity
          or has_table_privilege('anon', c.oid, 'select')
          or has_table_privilege('anon', c.oid, 'insert')
          or has_table_privilege('authenticated', c.oid, 'select'));
  if v_abertas is not null then
    raise exception 'bkp_tabelas_fechadas: ainda abertas: %', v_abertas;
  end if;
end
$$;
