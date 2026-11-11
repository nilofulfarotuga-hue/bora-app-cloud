-- Esqueleto mínimo do Supabase para provar as migrações das farmácias no PGlite.
create role anon nologin; create role authenticated nologin; create role service_role nologin;
create schema auth; create schema storage; create schema cron; create schema vault; create schema net; create schema extensions;
grant usage on schema public, auth, storage to anon, authenticated, service_role;
create table auth.users (id uuid primary key, email text, raw_app_meta_data jsonb default '{}', raw_user_meta_data jsonb default '{}');
create function auth.uid() returns uuid language sql stable as $$ select nullif(current_setting('request.jwt.claim.sub', true), '')::uuid $$;
grant execute on function auth.uid() to anon, authenticated, service_role;
create table storage.buckets (id text primary key, name text, public boolean, file_size_limit bigint, allowed_mime_types text[]);
create table storage.objects (id serial primary key, bucket_id text, name text, owner uuid);
alter table storage.objects enable row level security;
grant select, insert on storage.objects to authenticated;
create table cron.job (jobid serial primary key, jobname text, schedule text, command text);
create function cron.schedule(n text, s text, c text) returns int language sql as $$ insert into cron.job(jobname,schedule,command) values (n,s,c) returning jobid $$;
create function cron.unschedule(n text) returns boolean language sql as $$ delete from cron.job where jobname = n returning true $$;
create table vault.decrypted_secrets (name text, decrypted_secret text);
create table net.chamadas (id serial, url text, body jsonb);
create function net.http_post(url text, headers jsonb default '{}', body jsonb default '{}') returns bigint language sql as $$ insert into net.chamadas(url, body) values (url, body) returning id::bigint $$;
create publication supabase_realtime;

create table public.platform_settings (key text primary key, value jsonb, description text, category text, updated_at timestamptz, updated_by uuid, is_secret boolean);
insert into public.platform_settings(key, value) values ('errand_fee_normal_cents', '600'), ('errand_driver_normal_cents', '500');
create table public.restaurants (id text primary key, name text, category text, is_partner boolean, partner_commission_billing text,
  coming_soon boolean default false, coming_soon_text text, free_delivery_min_cents int, user_id uuid, user_ uuid,
  approval_status text default 'pending', approved_at timestamptz, rejection_reason text, is_active_admin boolean default true, is_online boolean default true,
  about_text text, email text, address text);
create table public.products (id text primary key, restaurant_id text, name text, price numeric, is_available boolean default true);
create table public.orders (id text primary key, restaurant_id text, user_id uuid, payment_method text, is_test_order boolean default false, status text, created_at timestamptz default now());
create table public.in_app_notifications (id uuid default gen_random_uuid() primary key, user_id uuid, kind text, title text, body text, related_id text);
create table public.admin_audit_log (id uuid default gen_random_uuid() primary key, admin_id uuid, admin_email text, action text, entity_type text, entity_id uuid, details jsonb, entity_id_text text, created_at timestamptz default now());
alter table public.restaurants enable row level security;
alter table public.products enable row level security;
grant select on public.restaurants, public.products to anon, authenticated;

create function public.is_admin() returns boolean language plpgsql stable security definer set search_path to 'public' as $$
declare v_uid uuid := auth.uid(); begin if v_uid is null then return false; end if;
return exists (select 1 from auth.users where id = v_uid and (coalesce(raw_app_meta_data->>'role','') = 'admin' or email in ('nilofulfarotuga@gmail.com'))); end $$;
create function public._push_in_app_notification(p_user_id uuid, p_kind text, p_title text, p_body text, p_related_id text) returns uuid
language plpgsql security definer as $$ declare v uuid; begin insert into in_app_notifications(user_id,kind,title,body,related_id) values (p_user_id,p_kind,p_title,p_body,p_related_id) returning id into v; return v; end $$;
create function public._modo_demo_def() returns jsonb language sql stable as $$ select value from public.platform_settings where key = 'modo_demo_loja' $$;
-- políticas existentes (cópia simplificada da produção)
create policy restaurants_public_read on public.restaurants for select to public using (approval_status = 'approved' or is_admin());
create policy products_public_read on public.products for select to public using (true);
-- gatilho demo existente (versão mínima: dinheiro + _modo_demo_loja -> is_test_order)
grant update on public.restaurants to authenticated;
create policy restaurants_update_own on public.restaurants for update to authenticated using ((user_ = auth.uid()) or is_admin());
