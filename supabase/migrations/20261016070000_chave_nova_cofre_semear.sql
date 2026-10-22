-- 20261016070000_chave_nova_cofre_semear.sql
-- Missão chave-nova-16-10 (16/10/2026). Ver docs/SEGURANCA-CHAVES.md.
--
-- A porta por onde a Edge Function `chaves-semear` grava no cofre do banco a chave secreta
-- nova da Supabase (sb_secret "default", que a plataforma injeta nas Edge Functions) com o
-- nome `bora_server_secret`. Assim a chave nunca passa por uma pessoa nem por uma conversa:
-- viaja Edge Function -> PostgREST -> cofre, dentro da Supabase.
--
-- Só service_role chama (GRANT abaixo + verificação por dentro). Nunca devolve a chave:
-- só o prefixo (10 caracteres) e o tamanho.

create or replace function public.vault_semear_chave_servidor(p_valor text, p_origem text default 'chaves-semear')
returns jsonb
language plpgsql
security definer
set search_path = public, vault
as $$
declare
  v_id   uuid;
  v_desc text;
begin
  if coalesce(auth.role(), '') <> 'service_role'
     and session_user not in ('postgres', 'supabase_admin') then
    raise exception 'so_service_role';
  end if;
  if p_valor is null or p_valor !~ '^sb_secret_[A-Za-z0-9_-]{20,}$' then
    raise exception 'valor_nao_parece_chave_secreta_nova';
  end if;

  v_desc := 'Chave secreta nova da Supabase (sb_secret default). Semeada por '
            || coalesce(p_origem, '?') || ' em '
            || to_char(now() at time zone 'utc', 'YYYY-MM-DD HH24:MI') || ' UTC. Nunca copiar para fora.';

  select id into v_id from vault.secrets where name = 'bora_server_secret';
  if v_id is null then
    v_id := vault.create_secret(p_valor, 'bora_server_secret', v_desc);
  else
    perform vault.update_secret(v_id, p_valor, 'bora_server_secret', v_desc);
  end if;

  return jsonb_build_object('ok', true, 'id', v_id, 'prefixo', left(p_valor, 10), 'tamanho', length(p_valor));
end
$$;

revoke all on function public.vault_semear_chave_servidor(text, text) from public;
revoke all on function public.vault_semear_chave_servidor(text, text) from anon, authenticated;
grant execute on function public.vault_semear_chave_servidor(text, text) to service_role;

comment on function public.vault_semear_chave_servidor(text, text) is
  'Grava/atualiza vault.bora_server_secret com a chave secreta nova (sb_secret). Só service_role. Missão chave-nova-16-10.';
