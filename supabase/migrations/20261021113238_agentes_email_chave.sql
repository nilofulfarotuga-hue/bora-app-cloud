do $$
begin
  if not exists (select 1 from vault.secrets where name = 'agentes_email_key') then
    perform vault.create_secret(encode(extensions.gen_random_bytes(32),'hex'), 'agentes_email_key', 'Segredo partilhado entre o Worker agentes-email (Cloudflare) e a Edge Function agentes-email-receber');
  end if;
end $$;

create or replace function public.get_agentes_email_key()
returns text language sql security definer set search_path to 'public' as $$
  select decrypted_secret from vault.decrypted_secrets where name = 'agentes_email_key' limit 1;
$$;
revoke all on function public.get_agentes_email_key() from public, anon, authenticated;
grant execute on function public.get_agentes_email_key() to service_role;