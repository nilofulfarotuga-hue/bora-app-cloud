-- 09/11/2026 · missão pendencias-2026-11-09, bloco E — entrar com Google.
--
-- 1. admin_clientes_metodo_login: o painel (ecrã Clientes, PT-BR) mostra por
--    que método cada conta entra — email, google, apple — lido de
--    auth.identities (uma linha por método ligado à conta). Só admin:
--    is_admin() como as outras admin_*, fechada a anon e a PUBLIC.
-- 2. Interruptores públicos do botão no app do cliente (lidos por get_setting,
--    como visitantes_sem_conta):
--      login_google_ativo = true  — o botão "Continuar com Google" aparece no
--                                    Android e na web; o app trata a falta
--                                    da linha como ligado.
--      login_apple_ativo  = false — o Supabase ainda não tem o segredo OAuth
--                                    da Apple (/authorize?provider=apple dá
--                                    400 "missing OAuth secret"). No iPhone,
--                                    pela regra 4.8 da Apple, o Google só
--                                    aparece com a Apple ao lado: ligar esta
--                                    depois de pôr o segredo no Supabase.
--
-- Não mexe em dinheiro, pedidos, carteiras nem RLS.

create or replace function public.admin_clientes_metodo_login(
  p_user_ids uuid[] default null
)
returns table (
  user_id uuid,
  metodos text[],
  ultimo_metodo text,
  ultimo_login_em timestamptz
)
language plpgsql
stable
security definer
set search_path = public, auth
as $function$
#variable_conflict use_column
begin
  if not public.is_admin() then
    raise exception 'admin_required' using errcode = '42501';
  end if;
  if p_user_ids is not null and cardinality(p_user_ids) > 1000 then
    raise exception 'max 1000 contas por pedido';
  end if;

  return query
  select
    i.user_id,
    array_agg(distinct i.provider::text order by i.provider::text) as metodos,
    (array_agg(i.provider::text
               order by i.last_sign_in_at desc nulls last, i.created_at desc))[1]
      as ultimo_metodo,
    max(i.last_sign_in_at) as ultimo_login_em
  from auth.identities i
  where p_user_ids is null or i.user_id = any(p_user_ids)
  group by i.user_id;
end;
$function$;

comment on function public.admin_clientes_metodo_login(uuid[]) is
  'Painel admin (Clientes): métodos de entrada de cada conta (email/google/apple) lidos de auth.identities. Só admin.';

revoke all on function public.admin_clientes_metodo_login(uuid[]) from public;
revoke all on function public.admin_clientes_metodo_login(uuid[]) from anon;
grant execute on function public.admin_clientes_metodo_login(uuid[])
  to authenticated, service_role;

insert into public.platform_settings (key, value, description, category, is_secret)
values
  ('login_google_ativo', 'true'::jsonb,
   'Botão "Continuar com Google" na entrada e no registo do cliente (Android e web; no iPhone só com a Apple ligada).',
   'cliente', false),
  ('login_apple_ativo', 'false'::jsonb,
   'Botão "Continuar com a Apple" no iPhone. Ligar só depois de pôr o segredo OAuth da Apple no Supabase Auth.',
   'cliente', false)
on conflict (key) do nothing;
