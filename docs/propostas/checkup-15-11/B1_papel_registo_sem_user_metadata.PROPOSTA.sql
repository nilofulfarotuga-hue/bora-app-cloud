-- PROPOSTA (checkup-geral-15-11, B1.2). Quem aplica: Claude.ai. Nao mexe em dinheiro.
-- Problema: handle_new_auth_user (gatilho trg_handle_new_auth_user em auth.users) copia
-- raw_user_meta_data->>'bora_role' para public.users.role sem filtro. O utilizador escreve o
-- proprio user_metadata no registo, por isso pode nascer com role='admin' ou outro valor
-- inventado. Hoje nenhuma funcao nem regra de acesso le public.users.role para dar admin
-- (SELECT de 15/11: is_admin() so le app_metadata.role e os 2 emails do Danilo), mas qualquer
-- codigo futuro que confie nesta coluna herdava o buraco.
-- Correcao: so os papeis que existem passam; o resto fica 'client'. 'admin' nunca vem daqui.
-- Papeis vistos a 15/11 em public.users: client, driver, partner, cleaner, placeholder.
-- Copia da funcao antiga: tabela bkp_funcoes_20261115 (criada aqui se nao existir).

create table if not exists public.bkp_funcoes_20261115 (
  nome text primary key,
  definicao text not null,
  guardado_em timestamptz not null default now()
);
revoke all on public.bkp_funcoes_20261115 from public, anon, authenticated;
alter table public.bkp_funcoes_20261115 enable row level security;

insert into public.bkp_funcoes_20261115 (nome, definicao)
values ('handle_new_auth_user', pg_get_functiondef('public.handle_new_auth_user'::regproc))
on conflict (nome) do nothing;

create or replace function public.handle_new_auth_user()
 returns trigger
 language plpgsql
 security definer
 set search_path to 'public'
as $function$
declare
  v_papel text := lower(coalesce(nullif(trim(new.raw_user_meta_data->>'bora_role'),''),
                                 nullif(trim(new.raw_user_meta_data->>'role'),''),
                                 'client'));
begin
  -- 'admin' nunca nasce do que o proprio utilizador escreve (so app_metadata.role).
  if v_papel not in ('client','driver','partner','cleaner','handyman') then
    v_papel := 'client';
  end if;

  insert into public.users (id, email, name, phone, role, tvde_access)
  values (
    new.id, new.email,
    coalesce(nullif(trim(new.raw_user_meta_data->>'bora_name'),''),
             nullif(trim(new.raw_user_meta_data->>'name'),''),
             nullif(trim(new.raw_user_meta_data->>'full_name'),'')),
    coalesce(nullif(trim(new.raw_user_meta_data->>'bora_phone'),''),
             nullif(trim(new.raw_user_meta_data->>'phone'),''),
             nullif(trim(new.phone),'')),
    v_papel,
    false
  )
  on conflict (id) do nothing;
  return new;
end;
$function$;

-- Prova (correr depois, em rollback): um registo com bora_role='admin' nasce 'client'.
-- do $$ declare v uuid := gen_random_uuid(); r text; begin
--   insert into auth.users (id, email, raw_user_meta_data, aud, role)
--   values (v, 'prova-checkup-'||v||'@exemplo.invalid', '{"bora_role":"admin"}', 'authenticated', 'authenticated');
--   select role into r from public.users where id = v;
--   raise exception 'PROVA role=%', r;   -- esperado: PROVA role=client
-- end $$;
