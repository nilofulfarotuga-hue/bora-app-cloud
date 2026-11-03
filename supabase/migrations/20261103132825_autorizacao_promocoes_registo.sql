-- Missão boom-hamburguer-mes, bloco H (ordem do Danilo de 03/11/2026): autorização de promoções.
-- Só 2 de 192 clientes tinham aceitado porque nunca se perguntava. Padrão Glovo/Uber: pergunta-se UMA vez
-- (logo a seguir ao registo, e aos clientes antigos que nunca responderam, ao abrir a app), nunca
-- pré-marcado. Grava users.marketing_opt_in / marketing_opt_in_at e quando respondeu.

alter table public.users add column if not exists marketing_respondido_em timestamptz;
comment on column public.users.marketing_respondido_em is
  'Quando o cliente respondeu à pergunta das promoções (Sim ou Agora não). Nulo = nunca respondeu.';

-- Quem já mexeu no interruptor do Perfil conta como tendo respondido.
update public.users set marketing_respondido_em = marketing_opt_in_at
 where marketing_respondido_em is null and marketing_opt_in_at is not null;

-- O interruptor do Perfil passa a marcar também a resposta.
create or replace function public.set_marketing_opt_in(p_opt_in boolean)
 returns jsonb language plpgsql security definer set search_path to 'public'
as $function$
declare v_uid uuid := auth.uid();
begin
  if v_uid is null then raise exception 'unauthenticated' using errcode = '42501'; end if;
  update public.users set marketing_opt_in = coalesce(p_opt_in, false),
                          marketing_opt_in_at = case when coalesce(p_opt_in, false) then now() else marketing_opt_in_at end,
                          marketing_respondido_em = now()
   where id = v_uid;
  if not found then
    insert into public.users (id, role, marketing_opt_in, marketing_opt_in_at, marketing_respondido_em)
    values (v_uid, 'client', coalesce(p_opt_in, false), case when coalesce(p_opt_in, false) then now() end, now())
    on conflict (id) do update set marketing_opt_in = excluded.marketing_opt_in,
                                   marketing_opt_in_at = excluded.marketing_opt_in_at,
                                   marketing_respondido_em = excluded.marketing_respondido_em;
  end if;
  return jsonb_build_object('ok', true, 'marketing_opt_in', coalesce(p_opt_in, false));
end;
$function$;

-- A app pergunta isto ao abrir: deve mostrar a pergunta? Só clientes que nunca responderam.
create or replace function public.marketing_pergunta_pendente()
 returns boolean language sql stable security definer set search_path to 'public'
as $function$
  select exists (select 1 from public.users u
                  where u.id = auth.uid()
                    and coalesce(u.role, 'client') = 'client'
                    and u.marketing_respondido_em is null
                    and u.marketing_opt_in_at is null);
$function$;

revoke all on function public.marketing_pergunta_pendente() from public, anon;
grant execute on function public.marketing_pergunta_pendente() to authenticated;

-- Painel admin (PT-BR): quantos aceitaram, recusaram e nunca responderam, e a lista de quem aceitou.
create or replace function public.admin_marketing_opt_in_resumo()
 returns jsonb language plpgsql stable security definer set search_path to 'public'
as $function$
declare v jsonb;
begin
  if not public.is_admin() then raise exception 'so_admin' using errcode = '42501'; end if;
  select jsonb_build_object(
    'clientes', count(*),
    'aceitaram', count(*) filter (where u.marketing_opt_in),
    'recusaram', count(*) filter (where not u.marketing_opt_in and u.marketing_respondido_em is not null),
    'sem_resposta', count(*) filter (where not u.marketing_opt_in and u.marketing_respondido_em is null),
    'lista', coalesce((select jsonb_agg(jsonb_build_object('nome', x.name, 'email', x.email, 'telefone', x.phone,
                                                         'aceitou_em', x.marketing_opt_in_at)
                                        order by x.marketing_opt_in_at desc nulls last)
                         from public.users x
                        where x.marketing_opt_in and coalesce(x.role, 'client') = 'client'), '[]'::jsonb))
    into v
    from public.users u
   where coalesce(u.role, 'client') = 'client';
  return v;
end;
$function$;

revoke all on function public.admin_marketing_opt_in_resumo() from public, anon;
grant execute on function public.admin_marketing_opt_in_resumo() to authenticated;
