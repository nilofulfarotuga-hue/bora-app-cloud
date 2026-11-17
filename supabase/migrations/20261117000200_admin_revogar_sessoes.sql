-- noite-farmacia-17-11 (7.2c): "Forçar saída" do estafeta não fechava as sessões.
-- A Edge admin-force-driver-logout chamava auth.admin.signOut(<id da conta>, 'global'), mas
-- esse método espera o TOKEN de sessão (JWT) e não o id: falhava sempre e o estafeta
-- continuava com a sessão aberta. Esta função fecha no banco todas as sessões de UMA conta
-- (refresh tokens + sessões). Só a service role a chama (a Edge confere antes que é admin).
create or replace function public.admin_revogar_sessoes(p_user_id uuid)
returns jsonb language plpgsql security definer set search_path = public, auth as $$
declare v_tokens int; v_sessoes int;
begin
  if p_user_id is null then raise exception 'conta em falta' using errcode = '22004'; end if;
  delete from auth.refresh_tokens where user_id = p_user_id::text;
  get diagnostics v_tokens = row_count;
  delete from auth.sessions where user_id = p_user_id;
  get diagnostics v_sessoes = row_count;
  return jsonb_build_object('sessoes', v_sessoes, 'refresh_tokens', v_tokens);
end $$;
revoke all on function public.admin_revogar_sessoes(uuid) from public, anon, authenticated;
grant execute on function public.admin_revogar_sessoes(uuid) to service_role;
