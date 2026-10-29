-- Corrige _robo_documentos_faltas: texto[] || literal dava 'malformed array literal'. Usa array_append.
-- O que falta a esta candidatura (so documentos), com as mesmas palavras e a mesma regra das apps
-- (driver_documentos.dart e prestador_documentos.dart). Motorista TVDE fica de fora (tem a sua conformidade).
create or replace function public._robo_documentos_faltas(p_user_id uuid)
returns text[] language plpgsql stable security definer set search_path to 'public' as $f$
declare
  f text[] := '{}';
  r record;
  a record;
  cfg record;
  quer_atividade boolean := false;
  obrig boolean;
begin
  for r in select vehicle_type, photo_url, registration_selfie_url, document_photo_url, document_number, vehicle_photo_url, license_plate
             from public.drivers
            where user_id = p_user_id and deleted_at is null and approval_status = 'pending'
              and coalesce(vehicle_type, '') <> 'carro_passageiros'
  loop
    quer_atividade := true;
    if nullif(btrim(coalesce(r.photo_url, '')), '') is null and nullif(btrim(coalesce(r.registration_selfie_url, '')), '') is null then
      f := array_append(f, 'foto pessoal (selfie)'::text); end if;
    if nullif(btrim(coalesce(r.document_photo_url, '')), '') is null then f := array_append(f, 'foto do documento'::text); end if;
    if nullif(btrim(coalesce(r.document_number, '')), '') is null then f := array_append(f, 'número do documento'::text); end if;
    if coalesce(r.vehicle_type, '') <> 'bicycle' then
      if nullif(btrim(coalesce(r.vehicle_photo_url, '')), '') is null then f := array_append(f, 'foto do veículo'::text); end if;
      if nullif(btrim(coalesce(r.license_plate, '')), '') is null then f := array_append(f, 'matrícula'::text); end if;
    end if;
  end loop;

  for r in select photo_url, docs from public.cleaners where user_id = p_user_id and approval_status = 'pending' loop
    quer_atividade := true;
    if nullif(btrim(coalesce(r.photo_url, '')), '') is null then f := array_append(f, 'foto de perfil'::text); end if;
    if nullif(btrim(case when jsonb_typeof(r.docs -> 'id_doc') = 'string' then r.docs ->> 'id_doc' else '' end), '') is null then
      f := array_append(f, 'documento de identificação'::text); end if;
  end loop;

  for r in select photo_url, docs from public.washers where user_id = p_user_id and approval_status = 'pending' loop
    quer_atividade := true;
    if nullif(btrim(coalesce(r.photo_url, '')), '') is null then f := array_append(f, 'foto de perfil'::text); end if;
    if nullif(btrim(case when jsonb_typeof(r.docs -> 'id_doc') = 'string' then r.docs ->> 'id_doc' else '' end), '') is null then
      f := array_append(f, 'documento de identificação'::text); end if;
    if nullif(btrim(case when jsonb_typeof(r.docs -> 'driving_license') = 'string' then r.docs ->> 'driving_license' else '' end), '') is null then
      f := array_append(f, 'carta de condução'::text); end if;
  end loop;

  if exists (select 1 from public.service_providers where user_id = p_user_id and approval_status = 'pending') then
    quer_atividade := true;
  end if;

  if quer_atividade then
    select * into cfg from public._provider_atividade_config();
    select * into a from public.provider_atividade where user_id = p_user_id;
    obrig := coalesce(a.obrigatoria,
      coalesce(cfg.ligado, false) and cfg.corte is not null
        and coalesce(public._provider_atividade_ultima_candidatura(p_user_id) >= cfg.corte, false));
    if obrig and (a.documento_path is null or a.atividade_status = 'recusada') then
      f := array_append(f, 'comprovativo de atividade'::text);
    end if;
  end if;
  return f;
end
$f$;
