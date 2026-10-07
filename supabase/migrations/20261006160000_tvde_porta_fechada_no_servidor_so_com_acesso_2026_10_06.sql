-- 2026-10-06 (caso Beatriz): APLICADA EM PRODUCAO pela Claude.ai por MCP.
-- A 30/09 os novos cadastros passaram a nascer com tvde_access=false, mas o
-- servidor nao verificava nada e o app mostrava o ladrilho a todos. Porta
-- fechada aqui: so pede corrida, reserva ou plano quem tem acesso (aprovado
-- pelo Danilo no painel, Pedidos de acesso TVDE) ou admin.
create or replace function public._tvde_exige_acesso(p_uid uuid)
returns void language plpgsql stable security definer set search_path to 'public' as $$
begin
  if p_uid is null then return; end if;
  if public.is_admin() then return; end if;
  if coalesce((select tvde_access from public.users where id = p_uid), false) is not true then
    raise exception 'no_tvde_access';
  end if;
end $$;
revoke all on function public._tvde_exige_acesso(uuid) from public, anon;
grant execute on function public._tvde_exige_acesso(uuid) to authenticated, service_role;

-- Injeta a verificacao logo a seguir ao "not_authenticated" das 4 portas de
-- entrada (sem retranscrever as funcoes, que sao grandes).
do $$
declare
  f text; def text; novo text;
begin
  foreach f in array array['tvde_request_ride','tvde_schedule_ride','tvde_schedule_roundtrip','tvde_request_plan'] loop
    select pg_get_functiondef(p.oid) into def
      from pg_proc p join pg_namespace n on n.oid=p.pronamespace
     where n.nspname='public' and p.proname=f;
    if def is null then raise exception 'funcao % nao encontrada', f; end if;
    if position('_tvde_exige_acesso' in def) > 0 then continue; end if;
    novo := regexp_replace(def,
      '(raise\s+exception\s+''not_authenticated''\s*;\s*end\s+if\s*;)',
      E'\\1\n  PERFORM public._tvde_exige_acesso(v_uid);', 'i');
    if novo = def then raise exception 'ponto de insercao nao encontrado em %', f; end if;
    execute novo;
  end loop;
end $$;
