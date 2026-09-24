-- Painel admin — reenviar o recibo de uma viagem TVDE ao passageiro (fecho-manha-2026-09-24, bloco 6).
--
-- O recibo automático (trigger trg_tvde_recibo_email) chama a Edge Function tvde-recibo-viagem
-- com a chave de serviço; essa função só envia ao passageiro por esse caminho e recusa repetir
-- quando a linha em tvde_recibos_email já está ok. Esta RPC, só para admin, marca a linha como
-- "reenvio pedido" e volta a chamar a função pelo mesmo caminho, com auditoria.
-- Não toca em preços, comissões nem valores: o recibo só LÊ a viagem já finalizada.
create or replace function public.admin_tvde_recibo_reenviar(p_ride uuid)
returns jsonb
language plpgsql
security definer
set search_path to 'public', 'net', 'vault'
as $$
declare
  v_url text;
  v_key text;
  v_req bigint;
  v_status text;
begin
  if not public.is_admin() then
    raise exception 'so_admin';
  end if;
  select status into v_status from public.tvde_rides where id = p_ride;
  if v_status is null then
    raise exception 'viagem_nao_existe';
  end if;
  if v_status <> 'finalizada' then
    raise exception 'viagem_nao_finalizada';
  end if;
  update public.tvde_recibos_email
     set ok = false, detalhe = 'reenvio pedido pelo admin em ' || to_char(now() at time zone 'Europe/Lisbon', 'YYYY-MM-DD HH24:MI')
   where ride_id = p_ride;
  select decrypted_secret into v_url from vault.decrypted_secrets where name = 'project_url';
  select decrypted_secret into v_key from vault.decrypted_secrets where name = 'service_role_key';
  if v_url is null or v_key is null then
    raise exception 'vault_sem_url_ou_chave';
  end if;
  select net.http_post(
           url := v_url || '/functions/v1/tvde-recibo-viagem',
           headers := jsonb_build_object('Authorization', 'Bearer ' || v_key, 'Content-Type', 'application/json'),
           body := jsonb_build_object('rideId', p_ride::text))
    into v_req;
  insert into public.admin_audit_log (admin_id, action, entity_type, entity_id_text, details)
  values (auth.uid(), 'tvde_recibo_reenviar', 'tvde_ride', p_ride::text,
          jsonb_build_object('request_id', v_req));
  return jsonb_build_object('ok', true, 'request_id', v_req);
end $$;
revoke all on function public.admin_tvde_recibo_reenviar(uuid) from public, anon;
grant execute on function public.admin_tvde_recibo_reenviar(uuid) to authenticated;
comment on function public.admin_tvde_recibo_reenviar(uuid) is
  'Admin: pede à Edge tvde-recibo-viagem (caminho de serviço) para voltar a enviar o recibo ao passageiro. Auditado. fecho-manha-2026-09-24';

-- Lista para o painel: recibos enviados com a viagem ao lado (só admin).
create or replace function public.admin_tvde_recibos_listar(p_limite integer default 200)
returns table (ride_id uuid, email text, enviado_em timestamptz, ok boolean, detalhe text,
               finalizada_em timestamptz, preco_eur numeric, motorista text, origem text, destino text)
language sql
stable
security definer
set search_path to 'public'
as $$
  select r.ride_id, r.email, r.enviado_em, r.ok, r.detalhe,
         t.updated_at, round(coalesce(t.final_fare_cents, t.est_fare_cents, 0) / 100.0, 2),
         coalesce(d.name, ''), left(coalesce(t.origin_label, ''), 60), left(coalesce(t.dest_label, ''), 60)
    from public.tvde_recibos_email r
    join public.tvde_rides t on t.id = r.ride_id
    left join public.drivers d on d.user_id = t.driver_id
   where public.is_admin()
   order by r.enviado_em desc
   limit greatest(1, least(coalesce(p_limite, 200), 1000));
$$;
revoke all on function public.admin_tvde_recibos_listar(integer) from public, anon;
grant execute on function public.admin_tvde_recibos_listar(integer) to authenticated;
