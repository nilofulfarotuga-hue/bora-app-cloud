-- motorista-ficha-legal-2026-09-23 · correção: admin_notifications.severity só
-- aceita low/medium/high/critical ('warning' rebentava o aviso diário — apanhado
-- na prova em rollback antes de o cron correr uma única vez).
create or replace function public.motorista_docs_alerta_diario()
returns jsonb language plpgsql security definer set search_path to 'public', 'net', 'vault' as $$
declare r record; v_url text; v_key text; n int := 0; v_resumo text := ''; v_titulo text; v_corpo text;
  v_grave boolean := false;
begin
  select decrypted_secret into v_url from vault.decrypted_secrets where name = 'project_url';
  select decrypted_secret into v_key from vault.decrypted_secrets where name = 'service_role_key';
  for r in
    select d.user_id, coalesce(nullif(trim(d.name), ''), 'Motorista') nome, e->>'doc' doc, e->>'rotulo' rotulo,
           (e->>'validade')::date validade, e->>'estado' estado, (e->>'dias')::int dias
      from public.drivers d
      cross join lateral jsonb_array_elements(public._motorista_docs_estado(d.user_id)) e
     where d.vehicle_type = 'carro_passageiros' and d.deleted_at is null
       and d.approval_status = 'approved' and not coalesce(d.is_banned, false)
       and e->>'estado' in ('a_expirar','expirado')
  loop
    insert into public.motorista_docs_alertas (user_id, doc, validade, estado)
    values (r.user_id, r.doc, r.validade, r.estado) on conflict do nothing;
    if not found then continue; end if;
    n := n + 1;
    v_grave := v_grave or r.estado = 'expirado';
    v_titulo := case when r.estado = 'expirado' then r.rotulo || ' expirado'
                     else r.rotulo || ' expira em ' || r.dias || ' dias' end;
    v_corpo := case when r.estado = 'expirado'
      then 'Não podes ficar online até atualizares a validade na tua Ficha legal.'
      else 'Válido até ' || to_char(r.validade, 'DD/MM/YYYY') || '. Renova a tempo e atualiza a Ficha legal na app.' end;
    perform public._push_in_app_notification(r.user_id, 'motorista_documento', v_titulo, v_corpo, r.doc);
    if v_url is not null and v_key is not null then
      begin
        perform net.http_post(url := v_url || '/functions/v1/notify-admin-message',
          headers := jsonb_build_object('Authorization', 'Bearer ' || v_key, 'Content-Type', 'application/json'),
          body := jsonb_build_object('targetUserId', r.user_id::text, 'title', v_titulo, 'body', v_corpo,
                                     'kind', 'admin_message_driver', 'relatedId', ''));
      exception when others then
        insert into public.e2e_log (fluxo, passo, estado, detalhe, device)
        values ('motorista-docs-alerta', 'push', 'falhou', r.user_id || ' ' || sqlerrm, 'pg_cron');
      end;
    end if;
    v_resumo := v_resumo || r.nome || ': ' || v_titulo || E'\n';
  end loop;
  if n > 0 then
    perform public.notify_admin_event('motorista_documentos', case when v_grave then 'high' else 'medium' end,
      n || ' aviso(s) de documento de motorista' || E'\n' || v_resumo,
      'driver', null, jsonb_build_object('avisos', n), '/admin/motoristas-documentos');
  end if;
  return jsonb_build_object('ok', true, 'avisos', n);
end $$;
