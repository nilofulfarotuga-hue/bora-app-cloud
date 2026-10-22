-- 20261016071500_chave_nova_cofre_nome_sb_secret_backend.sql
-- Missão chave-nova-16-10 (16/10/2026): o segredo do cofre passa a chamar-se `sb_secret_backend`
-- (nome fixado na ordem). A RPC da semeadura passa a gravar nesse nome.
-- Em produção o segredo foi renomeado com vault.update_secret (id 15a67b53-0815-44a6-9e58-8dddb9e8d05d)
-- a 16/10/2026 07:04 UTC; o valor nunca saiu do banco.
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

  v_desc := 'Chave secreta nova da Supabase (sb_secret). Semeada por '
            || coalesce(p_origem, '?') || ' em '
            || to_char(now() at time zone 'utc', 'YYYY-MM-DD HH24:MI') || ' UTC. Nunca copiar para fora.';

  select id into v_id from vault.secrets where name = 'sb_secret_backend';
  if v_id is null then
    v_id := vault.create_secret(p_valor, 'sb_secret_backend', v_desc);
  else
    perform vault.update_secret(v_id, p_valor, 'sb_secret_backend', v_desc);
  end if;

  return jsonb_build_object('ok', true, 'id', v_id, 'prefixo', left(p_valor, 10), 'tamanho', length(p_valor));
end
$$;

comment on function public.vault_semear_chave_servidor(text, text) is
  'Grava/atualiza vault.sb_secret_backend com a chave secreta nova (sb_secret). Só service_role. Missão chave-nova-16-10.';
