-- Missão única 2026-10-03 · Bloco 1 — APLICADA pela Claude.ai a 04/10/2026 (~08h50).
-- Este ficheiro espelha o que está em produção (lido de pg_policies/pg_proc a 04/10).
-- NÃO voltar a aplicar.
-- Achado 03/10: as políticas do bucket restaurant-assets deixavam QUALQUER
-- utilizador autenticado inserir, substituir ou apagar ficheiros de QUALQUER loja.
-- Agora só escreve/apaga: o dono da pasta (1.ª pasta = auth.uid(), id da loja com
-- restaurants.user_id = auth.uid(), ou id do service_providers com user_id = auth.uid())
-- ou o admin (is_admin()). Inserir em temp-* continua permitido (registo de parceiro).
-- A leitura fica igual.

create or replace function public.can_write_restaurant_asset(p_name text)
returns boolean
language sql
stable security definer
set search_path to 'public'
as $function$
  select auth.uid() is not null and (
    public.is_admin()
    or (storage.foldername(p_name))[1] = auth.uid()::text
    or exists (select 1 from public.restaurants r where r.id = (storage.foldername(p_name))[1] and r.user_id = auth.uid())
    or exists (select 1 from public.service_providers sp where sp.id = (storage.foldername(p_name))[1] and sp.user_id = auth.uid())
  );
$function$;

drop policy if exists restaurant_assets_any_authenticated_insert on storage.objects;
drop policy if exists restaurant_assets_authenticated_update on storage.objects;
drop policy if exists restaurant_assets_authenticated_delete on storage.objects;

create policy restaurant_assets_owner_insert on storage.objects
  for insert to authenticated
  with check ((bucket_id = 'restaurant-assets') and (public.can_write_restaurant_asset(name) or ((storage.foldername(name))[1] like 'temp-%')));

create policy restaurant_assets_owner_update on storage.objects
  for update to authenticated
  using ((bucket_id = 'restaurant-assets') and public.can_write_restaurant_asset(name))
  with check ((bucket_id = 'restaurant-assets') and public.can_write_restaurant_asset(name));

create policy restaurant_assets_owner_delete on storage.objects
  for delete to authenticated
  using ((bucket_id = 'restaurant-assets') and public.can_write_restaurant_asset(name));
