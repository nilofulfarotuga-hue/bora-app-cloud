-- tvde-conformidade-lei-59-2026 · FASE 3.2 e 3.8 — 2026-09-30
-- 1) Cartão do motorista (art. 19): + n.º do CMTVDE, foto do carro, lugares,
--    ano de fabrico, operador e se fala português. As colunas antigas ficam
--    iguais e na mesma ordem (a app antiga lê por nome e ignora as novas).
--    Mudar o tipo de retorno obriga a recriar a função; faz-se numa só
--    transação e repõem-se os mesmos GRANTs.
-- 2) Resumo da viagem (art. 15.º n.º 8): só ACRESCENTA chaves ao que o
--    _tvde_recibo já devolvia (código único, duração, cálculo) e passa a
--    chamar-se "Resumo da viagem". Nunca se apresenta como fatura.

drop function if exists public.tvde_ride_driver_card(uuid);
create function public.tvde_ride_driver_card(p_ride_id uuid)
returns table(name text, photo_url text, phone text, avg_rating numeric, ratings_count integer,
              vehicle_make_model text, vehicle_color text, license_plate text,
              lat double precision, lng double precision, heading double precision, speed_kmh double precision,
              location_updated_at timestamp with time zone,
              cmtvde_numero text, vehicle_photo_path text, vehicle_seats integer, vehicle_year integer,
              operador text, fala_portugues boolean)
language plpgsql security definer set search_path to 'public', 'auth' as $function$
DECLARE
  v_uid  uuid := auth.uid();
  v_ride public.tvde_rides;
BEGIN
  IF v_uid IS NULL THEN RAISE EXCEPTION 'not_authenticated'; END IF;

  SELECT * INTO v_ride FROM public.tvde_rides WHERE id = p_ride_id;
  IF NOT FOUND THEN RAISE EXCEPTION 'ride_not_found'; END IF;

  -- so o cliente daquela corrida (ou o admin) ve o cartao do motorista
  IF v_ride.client_id IS DISTINCT FROM v_uid AND NOT public.is_admin() THEN
    RAISE EXCEPTION 'not_ride_client';
  END IF;

  IF v_ride.driver_id IS NULL THEN RETURN; END IF;

  RETURN QUERY
    SELECT
      NULLIF(trim(d.name), ''),
      NULLIF(trim(d.photo_url), ''),
      NULLIF(trim(d.phone), ''),
      d.avg_rating,
      d.ratings_count,
      COALESCE(NULLIF(trim(concat_ws(' ', v.marca, v.modelo)), ''), NULLIF(trim(d.vehicle_make_model), '')),
      COALESCE(NULLIF(trim(v.cor), ''), NULLIF(trim(d.vehicle_color), '')),
      COALESCE(NULLIF(trim(v.matricula), ''), NULLIF(trim(d.license_plate), '')),
      COALESCE(l.latitude,  d.lat)::double precision,
      COALESCE(l.longitude, d.lng)::double precision,
      l.heading::double precision,
      l.speed_kmh::double precision,
      l.last_updated,
      -- 2026-09-30 conformidade (art. 19): identificação legal
      NULLIF(trim(f.tvde_cert_numero), ''),
      COALESCE(v.foto_path, NULLIF(trim(d.vehicle_photo_url), '')),
      v.lugares,
      COALESCE(v.ano_fabrico, f.veiculo_ano),
      COALESCE(o.denominacao, NULLIF(trim(f.operador_nome), '')),
      d.fala_portugues
    FROM public.drivers d
    -- chave dupla tolerante: ha motoristas cuja linha viva esta por id e outros por user_id
    LEFT JOIN LATERAL (
      SELECT dl.latitude, dl.longitude, dl.heading, dl.speed_kmh, dl.last_updated
      FROM public.driver_locations dl
      WHERE dl.driver_id IN (d.user_id, d.id)
      ORDER BY dl.last_updated DESC NULLS LAST
      LIMIT 1
    ) l ON TRUE
    LEFT JOIN public.motorista_ficha_legal f ON f.user_id = d.user_id
    LEFT JOIN public.tvde_operators o ON o.id = d.tvde_operator_id
    LEFT JOIN LATERAL (
      SELECT vv.* FROM public.tvde_driver_vehicle dv JOIN public.tvde_vehicles vv ON vv.id = dv.vehicle_id
       WHERE dv.driver_user_id = d.user_id AND dv.ativo AND vv.estado = 'aprovado'
       ORDER BY dv.desde DESC LIMIT 1
    ) v ON TRUE
    WHERE d.user_id = v_ride.driver_id OR d.id = v_ride.driver_id
    LIMIT 1;
END;
$function$;
revoke all on function public.tvde_ride_driver_card(uuid) from public;
grant execute on function public.tvde_ride_driver_card(uuid) to anon, authenticated, service_role;

-- Foto do carro: o cliente da corrida pode pedir URL assinado do ficheiro do
-- veículo que o está a levar (bucket privado driver-documents).
create or replace function public.tvde_ride_vehicle_photo_path(p_ride_id uuid)
returns text language sql stable security definer set search_path to 'public' as $$
  select v.foto_path
    from public.tvde_rides r
    join public.tvde_driver_vehicle dv on dv.driver_user_id = r.driver_id and dv.ativo
    join public.tvde_vehicles v on v.id = dv.vehicle_id and v.estado = 'aprovado'
   where r.id = p_ride_id and (r.client_id = auth.uid() or public.is_admin())
   order by dv.desde desc limit 1
$$;
revoke all on function public.tvde_ride_vehicle_photo_path(uuid) from public, anon;
grant execute on function public.tvde_ride_vehicle_photo_path(uuid) to authenticated;

create policy tvde_ride_client_reads_vehicle_photo on storage.objects
  for select to authenticated using (
    bucket_id = 'driver-documents'
    and exists (select 1 from public.tvde_rides r
                  join public.tvde_driver_vehicle dv on dv.driver_user_id = r.driver_id and dv.ativo
                  join public.tvde_vehicles v on v.id = dv.vehicle_id
                 where v.foto_path = storage.objects.name
                   and r.client_id = auth.uid()
                   and r.status in ('motorista_atribuido','motorista_a_caminho','motorista_chegou','em_andamento','finalizada')));

-- Resumo da viagem: acrescenta chaves; o resto do objeto fica igual.
create or replace function public._tvde_recibo(p_ride uuid)
returns jsonb language plpgsql stable security definer set search_path to 'public' as $$
declare r public.tvde_rides; v_total int; v_desc int; v_inicio timestamptz; v_fim timestamptz;
  v_mot text; v_bate boolean;
  v_iva_disc boolean := coalesce((public.get_setting('tvde_iva_discriminar') #>> '{}')::boolean, false);
  v_iva_pct numeric := coalesce((public.get_setting('tvde_iva_transporte_pct') #>> '{}')::numeric, 6);
  v_km numeric; v_fat public.tvde_invoices;
begin
  select * into r from public.tvde_rides where id = p_ride;
  if not found or r.status <> 'finalizada' then return null; end if;
  v_total := coalesce(nullif(r.final_fare_cents, 0), r.est_fare_cents, 0);
  v_desc := coalesce(r.tokens_applied_value_cents, 0) + coalesce(r.promo_credit_applied_cents, 0);
  v_bate := v_total > 0 and r.bora_cut_cents is not null and r.driver_earn_cents is not null
            and r.bora_cut_cents + r.driver_earn_cents = v_total;
  select min(at) filter (where status = 'em_andamento'), max(at) filter (where status = 'finalizada')
    into v_inicio, v_fim from public.tvde_ride_events where ride_id = r.id;
  select coalesce(nullif(trim(d.legal_name), ''), d.name) || coalesce(' · ' || d.license_plate, '')
    into v_mot from public.drivers d where d.user_id = r.driver_id limit 1;
  v_km := coalesce(r.final_distance_km, r.est_distance_km);
  select * into v_fat from public.tvde_invoices where ride_id = r.id and estado = 'emitida';
  return jsonb_build_object(
    'ride_id', r.id, 'numero', upper(left(replace(r.id::text, '-', ''), 8)),
    'data', coalesce(v_fim, r.updated_at), 'inicio', coalesce(v_inicio, r.created_at),
    'origem', r.origin_label, 'destino', r.dest_label,
    'distancia_km', v_km,
    'motorista', v_mot,
    'plataforma', coalesce(public.get_setting('plataforma_nome') #>> '{}', 'Bora'),
    'plataforma_nif', nullif(public.get_setting('plataforma_nif') #>> '{}', ''),
    'pagamento', r.payment_method,
    'valor_viagem_cents', v_total,
    'discriminado', v_bate,
    'transporte_cents', case when v_bate then r.driver_earn_cents end,
    'taxa_intermediacao_cents', case when v_bate then r.bora_cut_cents end,
    'paragens_cents', nullif(r.extra_stops_fee_cents, 0),
    'descontos_cents', nullif(v_desc, 0),
    'total_pago_cents', greatest(v_total - v_desc, 0),
    'razao', case
      when v_total = 0 then 'Viagem incluída num pacote ou assinatura já pago.'
      when not v_bate then 'Viagem com ajuste de pacote ida-e-volta: a divisão entre motorista e Bora está no teu extrato de pacote.'
      end,
    -- 2026-09-30 conformidade (art. 15.º n.º 8)
    'titulo', 'Resumo da viagem',
    'codigo_viagem', upper(replace(r.id::text, '-', '')),
    'duracao_min', case when v_inicio is not null and v_fim is not null
                        then round(extract(epoch from (v_fim - v_inicio)) / 60.0) end,
    'taxa_intermediacao_pct', case when v_bate and v_total > 0 then round(100.0 * r.bora_cut_cents / v_total, 1) end,
    'calculo', case when r.agreed_fare_cents is null and not coalesce(r.used_subscription_ride, false)
                     and r.roundtrip_credit_id is null then jsonb_build_object(
        'tarifa_base_cents', (public.get_setting('tvde_base_fare_cents') #>> '{}')::int,
        'km_incluidos', (public.get_setting('tvde_base_distance_km') #>> '{}')::int,
        'km_extra', greatest(0, ceil(coalesce(v_km, 0) - (public.get_setting('tvde_base_distance_km') #>> '{}')::int))::int,
        'preco_km_extra_cents', (public.get_setting('tvde_extra_per_km_cents') #>> '{}')::int,
        'preco_por_minuto_cents', 0, 'fator_dinamico', 1.0) end,
    'iva_pct', case when v_iva_disc then v_iva_pct end,
    'iva_cents', case when v_iva_disc then round(greatest(v_total - v_desc, 0) - greatest(v_total - v_desc, 0) / (1 + v_iva_pct / 100.0)) end,
    'fatura', case when v_fat.ride_id is null then null else jsonb_build_object(
        'numero', v_fat.numero, 'atcud', v_fat.atcud, 'url', v_fat.documento_url, 'fornecedor', v_fat.fornecedor) end,
    'aviso_legal', 'Resumo da viagem. Não é uma fatura: a fatura é emitida por software certificado pela Autoridade Tributária.');
end $$;
revoke all on function public._tvde_recibo(uuid) from public;
