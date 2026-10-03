-- =============================================================================
-- Resumo da viagem — linha "Mudança de destino" (missão tvde-mudar-destino, 30/09/2026)
-- ADITIVO sobre a definição no ar (30/09, conformidade): três chaves novas no
-- JSON e o cálculo passa a usar os km COBRADOS (preço fixo = distância
-- combinada, est_distance_km), não os km percorridos — senão a demonstração
-- do cálculo não batia com o valor pago depois do preço fixo e da mudança de
-- destino. `distancia_km` continua a ser a distância real (final).
--   mudanca_destino_cents  — o que o cliente pagou a mais por mudar o destino;
--   mudancas_destino       — cada mudança aplicada: de/para, km, preço antes/depois, diferença;
--   calculo.km_cobrados    — km em que o preço assentou.
-- =============================================================================
CREATE OR REPLACE FUNCTION public._tvde_recibo(p_ride uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare r public.tvde_rides; v_total int; v_desc int; v_inicio timestamptz; v_fim timestamptz;
  v_mot text; v_bate boolean;
  v_iva_disc boolean := coalesce((public.get_setting('tvde_iva_discriminar') #>> '{}')::boolean, false);
  v_iva_pct numeric := coalesce((public.get_setting('tvde_iva_transporte_pct') #>> '{}')::numeric, 6);
  v_km numeric; v_fat public.tvde_invoices;
  v_fixo boolean := coalesce((public.get_setting('tvde_fixed_price_enabled') #>> '{}')::boolean, true);
  v_km_cobrados numeric; v_mudancas jsonb;
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
  v_km_cobrados := case when v_fixo and r.est_distance_km is not null then r.est_distance_km else v_km end;
  select * into v_fat from public.tvde_invoices where ride_id = r.id and estado = 'emitida';
  select jsonb_agg(jsonb_build_object(
           'de', c.old_dest_label, 'para', c.new_dest_label,
           'km_antes', c.km_before, 'km_feitos', c.km_done, 'km_resto', c.km_remaining, 'km_novos', c.km_new_total,
           'preco_antes_cents', c.price_before_cents, 'preco_tabela_cents', c.price_new_cents,
           'pagou_cents', c.client_diff_cents, 'minimo', c.min_applied, 'quando', c.applied_at)
           order by c.applied_at)
    into v_mudancas
    from public.tvde_destination_changes c where c.ride_id = r.id and c.estado = 'aplicada';
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
    'mudanca_destino_cents', nullif(coalesce(r.dest_change_fee_cents, 0), 0),
    'mudancas_destino', v_mudancas,
    'descontos_cents', nullif(v_desc, 0),
    'total_pago_cents', greatest(v_total - v_desc, 0),
    'razao', case
      when v_total = 0 then 'Viagem incluída num pacote ou assinatura já pago.'
      when not v_bate then 'Viagem com ajuste de pacote ida-e-volta: a divisão entre motorista e Bora está no teu extrato de pacote.'
      end,
    'titulo', 'Resumo da viagem',
    'codigo_viagem', upper(replace(r.id::text, '-', '')),
    'duracao_min', case when v_inicio is not null and v_fim is not null
                        then round(extract(epoch from (v_fim - v_inicio)) / 60.0) end,
    'taxa_intermediacao_pct', case when v_bate and v_total > 0 then round(100.0 * r.bora_cut_cents / v_total, 1) end,
    'calculo', case when r.agreed_fare_cents is null and not coalesce(r.used_subscription_ride, false)
                     and r.roundtrip_credit_id is null then jsonb_build_object(
        'tarifa_base_cents', (public.get_setting('tvde_base_fare_cents') #>> '{}')::int,
        'km_incluidos', (public.get_setting('tvde_base_distance_km') #>> '{}')::int,
        'km_cobrados', v_km_cobrados,
        'km_extra', greatest(0, ceil(coalesce(v_km_cobrados, 0) - (public.get_setting('tvde_base_distance_km') #>> '{}')::int))::int,
        'preco_km_extra_cents', (public.get_setting('tvde_extra_per_km_cents') #>> '{}')::int,
        'preco_por_minuto_cents', 0, 'fator_dinamico', 1.0) end,
    'iva_pct', case when v_iva_disc then v_iva_pct end,
    'iva_cents', case when v_iva_disc then round(greatest(v_total - v_desc, 0) - greatest(v_total - v_desc, 0) / (1 + v_iva_pct / 100.0)) end,
    'fatura', case when v_fat.ride_id is null then null else jsonb_build_object(
        'numero', v_fat.numero, 'atcud', v_fat.atcud, 'url', v_fat.documento_url, 'fornecedor', v_fat.fornecedor) end,
    'aviso_legal', 'Resumo da viagem. Não é uma fatura: a fatura é emitida por software certificado pela Autoridade Tributária.');
end $function$;
