-- Grava a chave do Resend no vault sem ela passar por ficheiro, log ou conversa.
-- Escrita fechada: so o papel de servidor a pode chamar (regra PADRAO_BORA 6: REVOKE FROM PUBLIC).
create or replace function public.admin_set_resend_key(p_key text)
returns jsonb
language plpgsql
security definer
set search_path to 'public'
as $function$
declare
  v_id uuid;
  v_key text := trim(both from coalesce(p_key, ''));
begin
  if length(v_key) < 10 then
    raise exception 'chave invalida (comprimento %)', length(v_key);
  end if;

  select id into v_id from vault.secrets where name = 'resend_api_key';

  if v_id is null then
    perform vault.create_secret(v_key, 'resend_api_key',
      'Chave Resend do fecho semanal (2026-09-07)');
  else
    perform vault.update_secret(v_id, v_key, 'resend_api_key',
      'Chave Resend do fecho semanal (2026-09-07)');
  end if;

  -- devolve so o comprimento e o prefixo, nunca a chave
  return jsonb_build_object('ok', true, 'len', length(v_key), 'prefix', left(v_key, 3));
end
$function$;

revoke all on function public.admin_set_resend_key(text) from public;
revoke all on function public.admin_set_resend_key(text) from anon;
revoke all on function public.admin_set_resend_key(text) from authenticated;
grant execute on function public.admin_set_resend_key(text) to service_role;;
