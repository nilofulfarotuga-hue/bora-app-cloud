-- Robo "fiscal de documentos" (missao final-app-2026-10-29, adendo 3, R3): gatilhos.
-- Quando entra ou muda um documento, o banco chama a Edge Function verificar-documento (pg_net, depois do
-- commit, nunca antes). O gatilho NUNCA estraga a gravacao do candidato: qualquer erro e so registado.
-- service_providers nao tem colunas de documentos (so fotos da loja); o comprovativo dessa gente vive
-- em provider_atividade, que tem o seu gatilho. tvde_driver_documents fica para depois.

create or replace function public._robo_documentos_gatilho()
returns trigger language plpgsql security definer set search_path to 'public' as $f$
declare
  v_uid uuid;
  v_mudou boolean := false;
begin
  v_uid := NEW.user_id;
  if TG_TABLE_NAME = 'provider_atividade' then
    if NEW.documento_path is not null then
      if TG_OP = 'INSERT' then
        v_mudou := true;
      else
        v_mudou := NEW.documento_path is distinct from OLD.documento_path or NEW.enviado_em is distinct from OLD.enviado_em;
      end if;
    end if;
  elsif TG_TABLE_NAME = 'drivers' then
    if TG_OP = 'INSERT' then
      v_mudou := NEW.registration_selfie_url is not null or NEW.document_photo_url is not null
              or NEW.vehicle_photo_url is not null or NEW.vehicle_doc_url is not null;
    else
      v_mudou := NEW.registration_selfie_url is distinct from OLD.registration_selfie_url
              or NEW.document_photo_url is distinct from OLD.document_photo_url
              or NEW.vehicle_photo_url is distinct from OLD.vehicle_photo_url
              or NEW.vehicle_doc_url is distinct from OLD.vehicle_doc_url;
    end if;
  elsif TG_TABLE_NAME in ('cleaners', 'washers') then
    if TG_OP = 'INSERT' then
      v_mudou := NEW.docs is not null and NEW.docs <> '{}'::jsonb;
    else
      v_mudou := NEW.docs is distinct from OLD.docs;
    end if;
  end if;
  if v_mudou and v_uid is not null and not public.is_demo_user(v_uid) then
    perform public._robo_documentos_chamar(jsonb_build_object('user_id', v_uid, 'tabela', TG_TABLE_NAME));
  end if;
  return NEW;
exception when others then
  begin
    insert into public.e2e_log (fluxo, passo, estado, detalhe, device)
    values ('robo-documentos', 'gatilho', 'falhou', TG_TABLE_NAME || ' ' || sqlerrm, 'servidor');
  exception when others then
    null;
  end;
  return NEW;
end
$f$;
revoke all on function public._robo_documentos_gatilho() from public, anon, authenticated;

create trigger trg_robo_documentos_atividade
  after insert or update of documento_path, enviado_em on public.provider_atividade
  for each row execute function public._robo_documentos_gatilho();

create trigger trg_robo_documentos_drivers
  after insert or update of registration_selfie_url, document_photo_url, vehicle_photo_url, vehicle_doc_url on public.drivers
  for each row execute function public._robo_documentos_gatilho();

create trigger trg_robo_documentos_cleaners
  after insert or update of docs on public.cleaners
  for each row execute function public._robo_documentos_gatilho();

create trigger trg_robo_documentos_washers
  after insert or update of docs on public.washers
  for each row execute function public._robo_documentos_gatilho();

-- Varredura: manda analisar todos os candidatos pendentes (sombra por defeito: sem mensagens nem mudancas).
create or replace function public.robo_documentos_varrer(p_forcar_sombra boolean default true, p_reverificar boolean default false)
returns jsonb language plpgsql security definer set search_path to 'public' as $f$
declare
  v_uid uuid;
  n integer := 0;
begin
  for v_uid in
    select distinct x.u from (
      select user_id as u from public.drivers where approval_status = 'pending' and deleted_at is null
      union select user_id from public.cleaners where approval_status = 'pending'
      union select user_id from public.washers where approval_status = 'pending'
      union select user_id from public.service_providers where approval_status = 'pending'
    ) x
    where x.u is not null and not public.is_demo_user(x.u)
  loop
    perform public._robo_documentos_chamar(jsonb_build_object(
      'user_id', v_uid, 'forcar_sombra', coalesce(p_forcar_sombra, true), 'reverificar', coalesce(p_reverificar, false)));
    n := n + 1;
  end loop;
  return jsonb_build_object('ok', true, 'candidatos', n);
end
$f$;
revoke all on function public.robo_documentos_varrer(boolean, boolean) from public, anon, authenticated;
grant execute on function public.robo_documentos_varrer(boolean, boolean) to service_role;
