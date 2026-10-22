-- Missão cadastro-estafeta-fotos-22-10 (22/10/2026).
--
-- 1) driver_enviar_documento: o estafeta com candidatura pendente ou recusada
--    reenvia, a partir do ecrã "Conta em análise", só o que lhe falta (selfie,
--    foto do documento, foto do veículo, documento do veículo, número do
--    documento, matrícula) sem refazer o cadastro. Só o próprio (auth.uid()),
--    só pending/rejected, e a foto tem de estar mesmo no bucket
--    driver-documents na pasta dele. Aditiva: não mexe no estado da candidatura.
--
-- 2) admin_driver_pedir_documentos: o botão "Pedir documentos em falta" do
--    painel. Aviso na app + push ao estafeta com a lista exata, e rasto no
--    e2e_log e no log de ações do admin. Só admin.
--
-- Funções novas nascem fechadas (05/10/2026): EXECUTE só para authenticated.

create or replace function public.driver_enviar_documento(p_kind text, p_valor text)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid    uuid := auth.uid();
  v_driver public.drivers;
  v_valor  text := nullif(btrim(coalesce(p_valor, '')), '');
  v_path   text;
begin
  if v_uid is null then
    raise exception 'sem_sessao' using errcode = '42501';
  end if;
  select * into v_driver from public.drivers where user_id = v_uid for update;
  if not found then
    raise exception 'sem_candidatura';
  end if;
  if coalesce(v_driver.approval_status, '') not in ('pending', 'rejected') then
    raise exception 'candidatura_fechada';
  end if;
  if v_valor is null then
    raise exception 'valor_vazio';
  end if;

  if p_kind in ('selfie', 'document', 'vehicle', 'vehicle_doc') then
    -- Aceita o caminho 'uid/…', 'driver-documents/uid/…' ou o URL assinado
    -- que a Edge upload-driver-document devolve.
    v_path := case
      when v_valor like 'http%' then
        split_part(substring(v_valor from '/driver-documents/(.*)$'), '?', 1)
      when v_valor like 'driver-documents/%' then
        substr(v_valor, length('driver-documents/') + 1)
      else v_valor
    end;
    if v_path is null or v_path not like v_uid::text || '/%' then
      raise exception 'foto_de_outra_pessoa' using errcode = '42501';
    end if;
    if not exists (
      select 1 from storage.objects
       where bucket_id = 'driver-documents' and name = v_path
    ) then
      raise exception 'foto_nao_encontrada';
    end if;
    update public.drivers set
      registration_selfie_url = case when p_kind = 'selfie' then v_valor else registration_selfie_url end,
      document_photo_url      = case when p_kind = 'document' then v_valor else document_photo_url end,
      vehicle_photo_url       = case when p_kind = 'vehicle' then v_valor else vehicle_photo_url end,
      vehicle_doc_url         = case when p_kind = 'vehicle_doc' then v_valor else vehicle_doc_url end,
      updated_at = now()
    where id = v_driver.id;
  elsif p_kind = 'document_number' then
    if length(v_valor) > 40 then
      raise exception 'valor_invalido';
    end if;
    update public.drivers
       set document_number = upper(regexp_replace(v_valor, '\s', '', 'g')),
           updated_at = now()
     where id = v_driver.id;
  elsif p_kind = 'license_plate' then
    if length(v_valor) > 15 then
      raise exception 'valor_invalido';
    end if;
    update public.drivers
       set license_plate = upper(v_valor),
           updated_at = now()
     where id = v_driver.id;
  else
    raise exception 'kind_invalido';
  end if;

  insert into public.e2e_log (fluxo, passo, estado, detalhe, device)
  values ('cadastro-estafeta-fotos', 'reenvio-' || p_kind, 'ok',
          'driver=' || left(v_driver.id::text, 8), 'servidor');

  return jsonb_build_object('ok', true, 'kind', p_kind);
end
$$;

revoke all on function public.driver_enviar_documento(text, text) from public;
revoke all on function public.driver_enviar_documento(text, text) from anon;
grant execute on function public.driver_enviar_documento(text, text) to authenticated;


create or replace function public.admin_driver_pedir_documentos(p_driver_id uuid, p_itens text[])
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_driver public.drivers;
  v_itens  text[];
  v_n      int;
  v_lista  text;
  v_titulo text := 'Faltam documentos na tua candidatura';
  v_corpo  text;
  v_inapp  uuid;
  v_key    text;
  v_url    text;
  v_header jsonb;
  v_req    bigint;
  v_push   text := 'nao_enviado';
begin
  if not public.is_admin() then
    raise exception 'admin_required' using errcode = '42501';
  end if;
  select * into v_driver from public.drivers where id = p_driver_id;
  if not found or v_driver.user_id is null then
    raise exception 'estafeta_nao_encontrado';
  end if;

  select array_agg(btrim(i) order by o) into v_itens
    from unnest(coalesce(p_itens, '{}'::text[])) with ordinality as t(i, o)
   where btrim(coalesce(i, '')) <> '';
  v_n := coalesce(array_length(v_itens, 1), 0);
  if v_n = 0 then
    raise exception 'nada_a_pedir';
  end if;
  if v_n > 12 then
    raise exception 'itens_demais';
  end if;
  v_lista := case when v_n = 1 then v_itens[1]
                  else array_to_string(v_itens[1:v_n - 1], ', ') || ' e ' || v_itens[v_n] end;
  v_corpo := 'Para aprovarmos a tua conta de estafeta falta: ' || v_lista
          || '. Abre a app Bora e envia no ecrã "Conta em análise".';

  -- Aviso dentro da app (fica mesmo sem push).
  v_inapp := public._push_in_app_notification(v_driver.user_id, 'driver_documentos',
                                              v_titulo, v_corpo, 'driver_documentos');
  -- Push, pelo mesmo caminho do painel (notify-admin-message).
  begin
    select decrypted_secret into v_key from vault.decrypted_secrets where name = 'sb_secret_backend';
    if v_key is not null then
      v_header := jsonb_build_object('apikey', v_key, 'Content-Type', 'application/json');
    else
      select decrypted_secret into v_key from vault.decrypted_secrets where name = 'service_role_key';
      if v_key is not null then
        v_header := jsonb_build_object('apikey', v_key, 'Authorization', 'Bearer ' || v_key,
                                       'Content-Type', 'application/json');
      end if;
    end if;
    select decrypted_secret into v_url from vault.decrypted_secrets where name = 'project_url';
    if v_header is not null then
      select net.http_post(
        url     := coalesce(v_url, 'https://ojykpzwqrtusfeakzrna.supabase.co') || '/functions/v1/notify-admin-message',
        headers := v_header,
        body    := jsonb_build_object('targetUserId', v_driver.user_id::text, 'title', v_titulo,
                                      'body', v_corpo, 'kind', 'driver_documentos',
                                      'relatedId', 'driver_documentos'))
        into v_req;
      v_push := 'pedido_' || v_req::text;
    else
      v_push := 'sem_chave';
    end if;
  exception when others then
    v_push := 'erro: ' || sqlerrm;
  end;

  insert into public.e2e_log (fluxo, passo, estado, detalhe, device)
  values ('cadastro-estafeta-fotos', 'pedir-documentos',
          case when v_push like 'pedido_%' then 'ok' else 'aviso' end,
          'driver=' || left(p_driver_id::text, 8) || ' itens=' || v_lista
            || ' inapp=' || (v_inapp is not null)::text || ' push=' || v_push,
          'servidor');
  perform public.log_admin_action('driver_pedir_documentos'::text, 'driver'::text,
                                  p_driver_id::text,
                                  jsonb_build_object('itens', to_jsonb(v_itens), 'push', v_push));

  return jsonb_build_object('ok', true, 'titulo', v_titulo, 'corpo', v_corpo,
                            'inapp', v_inapp is not null, 'push', v_push);
end
$$;

revoke all on function public.admin_driver_pedir_documentos(uuid, text[]) from public;
revoke all on function public.admin_driver_pedir_documentos(uuid, text[]) from anon;
grant execute on function public.admin_driver_pedir_documentos(uuid, text[]) to authenticated;
