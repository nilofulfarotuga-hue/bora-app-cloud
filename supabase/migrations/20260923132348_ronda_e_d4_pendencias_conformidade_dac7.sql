-- =============================================================================
-- ronda-fecho-2026-09-22 · BLOCO E + D4 — painel admin (PT-BR)
--   E)  admin_pendencias_operacao(): talões pending_admin, corridas com pagamento
--       falhado, pacotes ida-e-volta sem volta, voltas retidas (correção manual),
--       cancelamentos com taxa sem estafeta, reservas falhadas, motoristas online
--       com GPS parado, estafetas online sem notificações — cada linha com a ação.
--       admin_driver_avisar_gps(p_driver): push "Sem sinal de GPS" ao estafeta.
--   D4) admin_conformidade_legal(): estado de cada item legal (dados) e o que
--       falta a cada prestador; admin_dac7_export(p_ano): linhas por vendedor
--       com os totais por trimestre (DAC7) para o CSV anual.
-- Guarda is_admin() (JWT do admin no painel; a central sem JWT usa o caminho ops_*).
-- =============================================================================

CREATE OR REPLACE FUNCTION public.admin_pendencias_operacao()
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_taloes jsonb; v_pag jsonb; v_pacotes jsonb; v_voltas jsonb; v_cancel jsonb; v_reservas jsonb; v_gps jsonb; v_push jsonb;
  v_gps_secs int := COALESCE((public.get_setting('dispatch_gps_fresh_seconds') #>> '{}')::int, 180);
BEGIN
  IF NOT public.is_admin() THEN RAISE EXCEPTION 'not_admin'; END IF;

  -- 1) talões por reembolsar
  SELECT COALESCE(jsonb_agg(x ORDER BY x->>'created_at'), '[]'::jsonb) INTO v_taloes FROM (
    SELECT jsonb_build_object(
      'receipt_id', rc.id, 'order_id', rc.order_id, 'vendor_name', o.vendor_name,
      'driver_uid', o.assigned_driver_id, 'driver_name', d.name,
      'valor_cents', COALESCE(rc.reimbursement_amount_cents, rc.driver_typed_total_cents),
      'created_at', rc.created_at, 'is_test_order', COALESCE(o.is_test_order, false),
      'accao', jsonb_build_object('rpc', 'admin_mark_receipt_paid | admin_mark_receipt_paid_external | admin_reject_receipt',
                                  'rota', '/admin/reembolsos', 'p_receipt_id', rc.id)) AS x
    FROM public.order_receipts_v2 rc
    JOIN public.orders o ON o.id = rc.order_id
    LEFT JOIN public.drivers d ON d.user_id::text = o.assigned_driver_id
    WHERE rc.reimbursement_status = 'pending_admin'
      AND COALESCE(o.is_test_order, false) = false) s;

  -- 2) corridas TVDE online com pagamento falhado / preso (14 dias)
  SELECT COALESCE(jsonb_agg(x ORDER BY x->>'created_at' DESC), '[]'::jsonb) INTO v_pag FROM (
    SELECT jsonb_build_object(
      'ride_id', r.id, 'created_at', r.created_at, 'status', r.status,
      'payment_method', r.payment_method, 'payment_status', r.payment_status, 'cancel_reason', r.cancel_reason,
      'payment_intent_id', r.payment_intent_id, 'est_fare_cents', r.est_fare_cents,
      'origin_label', r.origin_label, 'dest_label', r.dest_label,
      'client_id', r.client_id,
      'client_name', COALESCE(NULLIF(trim(u.name), ''), au.raw_user_meta_data->>'bora_name', ''),
      'client_phone', COALESCE(NULLIF(trim(u.phone), ''), au.raw_user_meta_data->>'bora_phone', ''),
      'preso', (r.status = 'solicitada'),
      'accao', jsonb_build_object('rota', '/admin/tvde/pagamentos',
                                  'rpc', CASE WHEN r.status = 'solicitada' THEN 'tvde_cancel_ride(p_ride_id, ''cliente'', ''admin_stuck_payment'')' ELSE NULL END,
                                  'tel', COALESCE(NULLIF(trim(u.phone), ''), au.raw_user_meta_data->>'bora_phone'))) AS x
    FROM public.tvde_rides r
    LEFT JOIN auth.users au ON au.id = r.client_id
    LEFT JOIN public.users u ON u.id = r.client_id
    WHERE r.payment_method IN ('card','mbway')
      AND r.created_at >= now() - interval '14 days'
      AND NOT COALESCE(public.is_demo_user(r.client_id), false)
      AND ((r.status = 'solicitada' AND COALESCE(r.payment_status, '') IN ('requires_payment_method','requires_action','requires_confirmation','processing'))
           OR (r.status LIKE 'cancelada%' AND COALESCE(r.cancel_reason, '') IN ('payment_failed','payment_abandoned','payment_timeout')))) s;

  -- 3) pacotes ida-e-volta sem volta (vale ativo ou expirado sem corrida de volta, 14 dias)
  SELECT COALESCE(jsonb_agg(x ORDER BY x->>'created_at' DESC), '[]'::jsonb) INTO v_pacotes FROM (
    SELECT jsonb_build_object(
      'credit_id', c.id, 'status', c.status, 'paid_cents', c.paid_cents, 'pago_online', c.payment_intent_id IS NOT NULL,
      'created_at', c.created_at, 'expires_at', c.expires_at, 'outbound_ride_id', c.outbound_ride_id,
      'ida_status', o.status, 'origin_label', o.origin_label, 'dest_label', o.dest_label,
      'client_id', c.client_id,
      'client_name', COALESCE(NULLIF(trim(u.name), ''), au.raw_user_meta_data->>'bora_name', ''),
      'client_phone', COALESCE(NULLIF(trim(u.phone), ''), au.raw_user_meta_data->>'bora_phone', ''),
      'accao', jsonb_build_object('rota', '/admin/tvde/ida-e-volta',
                                  'tel', COALESCE(NULLIF(trim(u.phone), ''), au.raw_user_meta_data->>'bora_phone'),
                                  'nota', CASE WHEN c.status = 'ativo' THEN 'Vale ativo: o cliente pode chamar a volta na app.'
                                               ELSE 'Vale expirado sem volta: decidir com o Danilo (devolução é dinheiro).' END)) AS x
    FROM public.tvde_roundtrip_credits c
    LEFT JOIN public.tvde_rides o ON o.id = c.outbound_ride_id
    LEFT JOIN auth.users au ON au.id = c.client_id
    LEFT JOIN public.users u ON u.id = c.client_id
    WHERE c.return_ride_id IS NULL
      AND c.status IN ('ativo','expirado')
      AND c.created_at >= now() - interval '14 days'
      AND NOT COALESCE(public.is_demo_user(c.client_id), false)
      AND COALESCE(o.status, '') NOT LIKE 'cancelada%') s;

  -- 4) voltas retidas para correção manual (distância suspeita)
  SELECT COALESCE(jsonb_agg(x ORDER BY x->>'created_at'), '[]'::jsonb) INTO v_voltas FROM (
    SELECT jsonb_build_object(
      'ride_id', r.id, 'created_at', r.created_at, 'hold_reason', r.dispatch_hold_reason, 'hold_at', r.dispatch_hold_at,
      'est_distance_km', r.est_distance_km, 'driver_earn_cents', r.driver_earn_cents,
      'origin_label', r.origin_label, 'dest_label', r.dest_label,
      'ida_km', (SELECT COALESCE(o.final_distance_km, o.est_distance_km) FROM public.tvde_roundtrip_credits c JOIN public.tvde_rides o ON o.id = c.outbound_ride_id WHERE c.id = r.roundtrip_credit_id),
      'detalhe', (SELECT e.meta->>'detalhe' FROM public.tvde_ride_events e WHERE e.ride_id = r.id AND e.status = 'correcao_manual' ORDER BY e.at DESC LIMIT 1),
      'client_id', r.client_id,
      'client_name', COALESCE(NULLIF(trim(u.name), ''), au.raw_user_meta_data->>'bora_name', ''),
      'client_phone', COALESCE(NULLIF(trim(u.phone), ''), au.raw_user_meta_data->>'bora_phone', ''),
      'accao', jsonb_build_object('rpc', 'admin_tvde_ride_release_hold', 'p_ride_id', r.id,
                                  'nota', 'Corrigir a distância (km) e libertar, ou cancelar e devolver o vale.')) AS x
    FROM public.tvde_rides r
    LEFT JOIN auth.users au ON au.id = r.client_id
    LEFT JOIN public.users u ON u.id = r.client_id
    WHERE r.dispatch_hold_reason IS NOT NULL AND r.status = 'solicitada') s;

  -- 5) cancelamentos com taxa cobrada sem estafeta (30 dias) — pedidos e corridas
  SELECT COALESCE(jsonb_agg(x ORDER BY x->>'cancelled_at' DESC), '[]'::jsonb) INTO v_cancel FROM (
    SELECT jsonb_build_object(
      'kind', 'pedido', 'id', o.id, 'customer_name', o.customer_name, 'vendor_name', o.vendor_name,
      'fee_cents', ROUND(COALESCE(o.cancel_fee, 0) * 100)::int, 'cancelled_at', COALESCE(o.cancelled_at, o.status_updated_at),
      'cancel_reason', o.cancel_reason, 'refund_status', o.refund_status, 'payment_method', o.payment_method,
      'accao', jsonb_build_object('rota', '/admin/orders/' || o.id, 'nota', 'Perdoar a taxa é dinheiro real: só com o vai do Danilo (wallet_*).')) AS x
    FROM public.orders o
    WHERE o.status ILIKE 'cancel%'
      AND COALESCE(o.cancel_fee, 0) > 0
      AND o.assigned_driver_id IS NULL
      AND COALESCE(o.is_test_order, false) = false
      AND COALESCE(o.cancelled_at, o.status_updated_at, o.created_at) >= now() - interval '30 days'
    UNION ALL
    SELECT jsonb_build_object(
      'kind', 'corrida', 'id', r.id, 'customer_name', COALESCE(NULLIF(trim(u.name), ''), ''), 'vendor_name', NULL,
      'fee_cents', r.cancel_fee_cents, 'cancelled_at', r.updated_at,
      'cancel_reason', r.cancel_reason, 'refund_status', r.payment_status, 'payment_method', r.payment_method,
      'accao', jsonb_build_object('rota', '/admin/tvde/cancelamentos', 'nota', 'Perdoar a taxa é dinheiro real: só com o vai do Danilo.')) AS x
    FROM public.tvde_rides r
    LEFT JOIN public.users u ON u.id = r.client_id
    WHERE r.status LIKE 'cancelada%'
      AND COALESCE(r.cancel_fee_cents, 0) > 0
      AND r.driver_id IS NULL
      AND NOT COALESCE(public.is_demo_user(r.client_id), false)
      AND r.updated_at >= now() - interval '30 days') s;

  -- 6) reservas falhadas: corridas marcadas sem motorista / por pagar, e mesas presas
  SELECT COALESCE(jsonb_agg(x ORDER BY x->>'quando'), '[]'::jsonb) INTO v_reservas FROM (
    SELECT jsonb_build_object(
      'kind', 'corrida_marcada', 'id', r.id, 'quando', r.scheduled_at, 'status', r.status, 'reservation_status', r.reservation_status,
      'origin_label', r.origin_label, 'dest_label', r.dest_label, 'payment_method', r.payment_method,
      'client_name', COALESCE(NULLIF(trim(u.name), ''), au.raw_user_meta_data->>'bora_name', ''),
      'client_phone', COALESCE(NULLIF(trim(u.phone), ''), au.raw_user_meta_data->>'bora_phone', ''),
      'motivo', CASE r.reservation_status WHEN 'sem_motorista' THEN 'Ninguém aceitou a reserva'
                                          WHEN 'aguarda_pagamento' THEN 'Cliente não concluiu o pagamento'
                                          ELSE COALESCE(r.reservation_status, r.status) END,
      'accao', jsonb_build_object('rota', '/admin/tvde/reservas',
                                  'rpc', CASE WHEN r.status = 'agendada' THEN 'admin_tvde_reservation_force_search | admin_tvde_reservation_set_driver | admin_tvde_reservation_cancel' ELSE NULL END,
                                  'p_ride_id', r.id)) AS x
    FROM public.tvde_rides r
    LEFT JOIN auth.users au ON au.id = r.client_id
    LEFT JOIN public.users u ON u.id = r.client_id
    WHERE r.scheduled_at IS NOT NULL
      AND r.scheduled_at >= now() - interval '7 days'
      AND NOT COALESCE(public.is_demo_user(r.client_id), false)
      AND (r.reservation_status IN ('sem_motorista','aguarda_pagamento') OR r.status = 'sem_motorista')
    UNION ALL
    SELECT jsonb_build_object(
      'kind', 'mesa', 'id', rs.id, 'quando', rs.reserved_for, 'status', rs.status, 'reservation_status', NULL,
      'origin_label', rt.name, 'dest_label', NULL, 'payment_method', CASE WHEN rs.prepayment_pi IS NOT NULL THEN 'card' ELSE 'cash' END,
      'client_name', rs.client_name, 'client_phone', rs.client_phone,
      'motivo', 'Reserva de mesa presa em ' || rs.status || ' há mais de 60 min',
      'accao', jsonb_build_object('rota', '/admin/reservas/presas', 'rpc', 'admin_release_stuck_reservation', 'p_reservation_id', rs.id)) AS x
    FROM public.reservations rs
    LEFT JOIN public.restaurants rt ON rt.id = rs.restaurant_id
    WHERE rs.status IN ('pending','pending_payment')
      AND rs.created_at < now() - interval '60 minutes'
      AND rs.reserved_for >= now() - interval '1 day') s;

  -- 7) motoristas/estafetas online com GPS parado
  SELECT COALESCE(jsonb_agg(x ORDER BY (x->>'gps_age_s')::int DESC NULLS FIRST), '[]'::jsonb) INTO v_gps FROM (
    SELECT jsonb_build_object(
      'user_id', COALESCE(d.user_id, d.id), 'driver_id', d.id, 'name', d.name, 'phone', d.phone, 'vehicle_type', d.vehicle_type,
      'heartbeat_age_s', extract(epoch FROM (now() - d.last_heartbeat_at))::int,
      'gps_age_s', public.driver_gps_age_seconds(d.user_id, d.id),
      'gps_fresco', public.driver_gps_fresh(d.user_id, d.id),
      'last_platform', d.last_platform,
      'tem_notificacoes', (d.fcm_token IS NOT NULL
         OR EXISTS (SELECT 1 FROM public.driver_push_tokens t WHERE t.user_id = COALESCE(d.user_id, d.id) AND t.active)),
      'accao', jsonb_build_object('rpc', 'admin_driver_avisar_gps', 'p_driver', COALESCE(d.user_id, d.id)::text,
                                  'rota', '/admin/drivers', 'tel', d.phone)) AS x
    FROM public.drivers d
    WHERE COALESCE(d.is_online, false)
      AND NOT public.driver_gps_fresh(d.user_id, d.id)
      AND NOT COALESCE(public.is_demo_user(COALESCE(d.user_id, d.id)), false)) s;

  -- 8) estafetas online sem notificações
  SELECT COALESCE(jsonb_agg(x ORDER BY x->>'name'), '[]'::jsonb) INTO v_push FROM (
    SELECT jsonb_build_object(
      'user_id', COALESCE(d.user_id, d.id), 'driver_id', d.id, 'name', d.name, 'phone', d.phone,
      'heartbeat_age_s', extract(epoch FROM (now() - d.last_heartbeat_at))::int,
      'last_platform', d.last_platform,
      'accao', jsonb_build_object('rota', '/admin/drivers', 'tel', d.phone,
                                  'nota', 'Pedir para abrir a app e tocar em Ativar notificações.')) AS x
    FROM public.drivers d
    WHERE COALESCE(d.is_online, false)
      AND NOT COALESCE(public.is_demo_user(COALESCE(d.user_id, d.id)), false)
      AND (d.fcm_token IS NULL OR length(d.fcm_token) = 0)
      AND NOT EXISTS (SELECT 1 FROM public.driver_push_tokens t WHERE t.user_id = COALESCE(d.user_id, d.id) AND t.active)
      AND NOT EXISTS (SELECT 1 FROM public.provider_push_tokens t WHERE t.user_id = COALESCE(d.user_id, d.id) AND t.active)) s;

  RETURN jsonb_build_object(
    'gerado_em', now(),
    'gps_limite_s', v_gps_secs,
    'taloes', v_taloes,
    'pagamentos_falhados', v_pag,
    'pacotes_sem_volta', v_pacotes,
    'voltas_retidas', v_voltas,
    'cancelamentos_taxa_sem_estafeta', v_cancel,
    'reservas_falhadas', v_reservas,
    'motoristas_gps_parado', v_gps,
    'estafetas_sem_push', v_push,
    'totais', jsonb_build_object(
      'taloes', jsonb_array_length(v_taloes),
      'pagamentos_falhados', jsonb_array_length(v_pag),
      'pacotes_sem_volta', jsonb_array_length(v_pacotes),
      'voltas_retidas', jsonb_array_length(v_voltas),
      'cancelamentos_taxa_sem_estafeta', jsonb_array_length(v_cancel),
      'reservas_falhadas', jsonb_array_length(v_reservas),
      'motoristas_gps_parado', jsonb_array_length(v_gps),
      'estafetas_sem_push', jsonb_array_length(v_push)));
END;
$function$;
REVOKE ALL ON FUNCTION public.admin_pendencias_operacao() FROM PUBLIC;
REVOKE ALL ON FUNCTION public.admin_pendencias_operacao() FROM anon;
GRANT EXECUTE ON FUNCTION public.admin_pendencias_operacao() TO authenticated, service_role;

-- push ao estafeta: "Sem sinal de GPS"
CREATE OR REPLACE FUNCTION public.admin_driver_avisar_gps(p_driver text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE v_d record; v_idade int;
BEGIN
  IF NOT public.is_admin() THEN RAISE EXCEPTION 'not_admin'; END IF;
  SELECT d.id, d.user_id, d.name INTO v_d FROM public.drivers d WHERE d.user_id::text = p_driver OR d.id::text = p_driver LIMIT 1;
  IF v_d.id IS NULL THEN RETURN jsonb_build_object('ok', false, 'error', 'estafeta_nao_encontrado'); END IF;
  v_idade := public.driver_gps_age_seconds(v_d.user_id, v_d.id);
  PERFORM public._notify_driver_assigned_http(
    COALESCE(v_d.user_id, v_d.id)::text, NULL, 'driver_offline',
    'Sem sinal de GPS',
    CASE WHEN v_idade IS NULL THEN 'A Bora não recebe a tua localização. Liga o GPS e abre a Bora para voltares a receber pedidos.'
         ELSE 'A tua localização parou há ' || GREATEST(1, v_idade / 60) || ' min. Abre a Bora (e atualiza a app) para voltares a receber pedidos.' END);
  INSERT INTO public.admin_audit_log (admin_id, admin_email, action, entity_type, entity_id_text, details)
  VALUES (auth.uid(), COALESCE(auth.jwt() ->> 'email', 'central'), 'driver_avisado_gps', 'driver', COALESCE(v_d.user_id, v_d.id)::text,
          jsonb_build_object('name', v_d.name, 'gps_age_s', v_idade));
  RETURN jsonb_build_object('ok', true, 'driver', v_d.name, 'gps_age_s', v_idade);
END;
$function$;
REVOKE ALL ON FUNCTION public.admin_driver_avisar_gps(text) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.admin_driver_avisar_gps(text) FROM anon;
GRANT EXECUTE ON FUNCTION public.admin_driver_avisar_gps(text) TO authenticated, service_role;

-- ── D4: conformidade legal (dados) ──────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.admin_conformidade_legal()
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_prest jsonb; v_opt jsonb; v_obrig boolean; v_lojas jsonb; v_itens jsonb;
BEGIN
  IF NOT public.is_admin() THEN RAISE EXCEPTION 'not_admin'; END IF;
  v_obrig := COALESCE((public.get_setting('conformidade_ativacao_obrigatoria') #>> '{}')::boolean, true);

  WITH p AS (
    SELECT 'driver' AS tipo, d.id::text AS id, d.user_id, COALESCE(d.legal_name, d.name) AS nome, d.phone, d.approval_status,
           public._conformidade_em_falta(to_jsonb(d)) AS falta
      FROM public.drivers d WHERE d.deleted_at IS NULL AND NOT COALESCE(public.is_demo_user(COALESCE(d.user_id, d.id)), false)
    UNION ALL
    SELECT 'partner', r.id, r.user_id, COALESCE(r.legal_name, r.name), r.phone, r.approval_status,
           public._conformidade_em_falta(to_jsonb(r))
      FROM public.restaurants r WHERE COALESCE(r.is_partner, false)
    UNION ALL
    SELECT 'cleaner', c.id::text, c.user_id, COALESCE(c.legal_name, c.name), c.phone, c.approval_status,
           public._conformidade_em_falta(to_jsonb(c))
      FROM public.cleaners c
    UNION ALL
    SELECT 'washer', w.id::text, w.user_id, COALESCE(w.legal_name, w.name), w.phone, w.approval_status,
           public._conformidade_em_falta(to_jsonb(w))
      FROM public.washers w
    UNION ALL
    SELECT 'provider', s.id, s.user_id, COALESCE(s.legal_name, s.name), s.phone, s.approval_status,
           public._conformidade_em_falta(to_jsonb(s))
      FROM public.service_providers s)
  SELECT jsonb_build_object(
    'resumo', (SELECT jsonb_object_agg(tipo, jsonb_build_object(
                  'total', n, 'aprovados', n_apr, 'completos', n_ok, 'incompletos', n - n_ok,
                  'aprovados_incompletos', n_apr_inc))
                 FROM (SELECT tipo, count(*) n,
                              count(*) FILTER (WHERE approval_status = 'approved') n_apr,
                              count(*) FILTER (WHERE COALESCE(array_length(falta, 1), 0) = 0) n_ok,
                              count(*) FILTER (WHERE approval_status = 'approved' AND COALESCE(array_length(falta, 1), 0) > 0) n_apr_inc
                         FROM p GROUP BY tipo) g),
    'incompletos', (SELECT COALESCE(jsonb_agg(jsonb_build_object('tipo', tipo, 'id', id, 'user_id', user_id, 'nome', nome, 'phone', phone,
                                                                  'approval_status', approval_status, 'falta', to_jsonb(falta))
                                              ORDER BY (approval_status = 'approved') DESC, tipo, nome), '[]'::jsonb)
                      FROM p WHERE COALESCE(array_length(falta, 1), 0) > 0))
    INTO v_prest;

  SELECT jsonb_build_object(
    'clientes', count(*) FILTER (WHERE role = 'client'),
    'com_opt_in', count(*) FILTER (WHERE marketing_opt_in),
    'ultimo_opt_in', max(marketing_opt_in_at))
    INTO v_opt FROM public.users;

  SELECT jsonb_build_object(
    'aprovadas', count(*),
    'sem_nif', count(*) FILTER (WHERE regexp_replace(COALESCE(nif,''), '[^0-9]', '', 'g') !~ '^[0-9]{9}$'),
    'sem_morada', count(*) FILTER (WHERE NULLIF(btrim(COALESCE(address,'')), '') IS NULL))
    INTO v_lojas FROM public.restaurants WHERE approval_status = 'approved' AND COALESCE(is_partner, false);

  v_itens := jsonb_build_array(
    jsonb_build_object('codigo', 'd3_ativacao', 'titulo', 'Ativação bloqueada sem dados legais (DSA art. 30 + DAC7)',
                       'estado', CASE WHEN v_obrig THEN 'ok' ELSE 'parcial' END,
                       'detalhe', CASE WHEN v_obrig THEN 'Gatilho ligado: nome, NIF, morada, IBAN, data de nascimento e autocertificação são exigidos antes de aprovar.'
                                       ELSE 'conformidade_ativacao_obrigatoria=false: o gatilho só avisa.' END,
                       'rota', '/admin/configuracoes'),
    jsonb_build_object('codigo', 'd3_prestadores', 'titulo', 'Prestadores com dados completos',
                       'estado', CASE WHEN (SELECT bool_and((v->>'incompletos')::int = 0) FROM jsonb_each(v_prest->'resumo') AS e(k, v)) THEN 'ok' ELSE 'parcial' END,
                       'detalhe', 'Ver a lista de incompletos abaixo; os aprovados incompletos precisam de completar na app.',
                       'rota', NULL),
    jsonb_build_object('codigo', 'd3_recibo_vendedor', 'titulo', 'Nome, NIF e morada do vendedor no recibo do cliente',
                       'estado', CASE WHEN (v_lojas->>'sem_nif')::int = 0 AND (v_lojas->>'sem_morada')::int = 0 THEN 'ok' ELSE 'parcial' END,
                       'detalhe', format('%s lojas parceiras aprovadas: %s sem NIF, %s sem morada.', v_lojas->>'aprovadas', v_lojas->>'sem_nif', v_lojas->>'sem_morada'),
                       'rota', '/admin/parceiros'),
    jsonb_build_object('codigo', 'd3_opt_in', 'titulo', 'Opt-in separado para marketing',
                       'estado', 'ok',
                       'detalhe', format('%s clientes, %s com opt-in. Push comercial (promo/cashback/referral) só vai a estes.', v_opt->>'clientes', v_opt->>'com_opt_in'),
                       'rota', '/admin/notificacoes'),
    jsonb_build_object('codigo', 'd4_dac7', 'titulo', 'Exportação DAC7 anual (CSV)',
                       'estado', 'ok',
                       'detalhe', 'admin_dac7_export(ano): uma linha por vendedor com totais por trimestre; entregar à AT até 31 de janeiro do ano seguinte.',
                       'rota', '/admin/conformidade'));

  RETURN jsonb_build_object('gerado_em', now(), 'ativacao_obrigatoria', v_obrig, 'itens', v_itens,
                            'prestadores', v_prest, 'marketing', v_opt, 'lojas', v_lojas);
END;
$function$;
REVOKE ALL ON FUNCTION public.admin_conformidade_legal() FROM PUBLIC;
REVOKE ALL ON FUNCTION public.admin_conformidade_legal() FROM anon;
GRANT EXECUTE ON FUNCTION public.admin_conformidade_legal() TO authenticated, service_role;

-- ── D4: DAC7 — uma linha por vendedor, totais por trimestre ─────────────────
CREATE OR REPLACE FUNCTION public.admin_dac7_export(p_ano integer DEFAULT NULL::integer)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_ano int := COALESCE(p_ano, extract(year FROM (now() AT TIME ZONE 'Europe/Lisbon'))::int);
  v_ini timestamptz := make_timestamptz(v_ano, 1, 1, 0, 0, 0, 'Europe/Lisbon');
  v_fim timestamptz := make_timestamptz(v_ano + 1, 1, 1, 0, 0, 0, 'Europe/Lisbon');
  v_out jsonb;
BEGIN
  IF NOT public.is_admin() THEN RAISE EXCEPTION 'not_admin'; END IF;

  WITH tot AS (
    -- estafetas/motoristas (euros; total_earnings já inclui TVDE)
    SELECT 'driver' AS tipo, s.driver_id::text AS user_id, NULL::text AS entity_id,
           extract(quarter FROM (s.week_start_at AT TIME ZONE 'Europe/Lisbon'))::int AS tri,
           ROUND(COALESCE(s.total_earnings, 0) * 100)::bigint AS cents,
           0::bigint AS comissoes_cents,
           COALESCE(s.total_deliveries, 0) + COALESCE(s.tvde_rides_count, 0) AS n
      FROM public.driver_weekly_settlements s
     WHERE s.week_start_at >= v_ini AND s.week_start_at < v_fim
    UNION ALL
    -- parceiros (euros): partner_share = o que fica para a loja; commission_total = o que a Bora reteve
    SELECT 'partner', NULL, s.partner_id,
           extract(quarter FROM (s.week_start_at AT TIME ZONE 'Europe/Lisbon'))::int,
           ROUND(COALESCE(s.partner_share, 0) * 100)::bigint,
           ROUND(COALESCE(s.commission_total, 0) * 100)::bigint,
           COALESCE(s.total_orders, 0)
      FROM public.partner_weekly_settlements s
     WHERE s.week_start_at >= v_ini AND s.week_start_at < v_fim
    UNION ALL
    -- faxineiros (cêntimos)
    SELECT 'cleaner', NULL, s.cleaner_id::text,
           extract(quarter FROM (s.week_start_at AT TIME ZONE 'Europe/Lisbon'))::int,
           COALESCE(s.total_earnings_cents, 0)::bigint, COALESCE(s.total_bora_fee_cents, 0)::bigint, COALESCE(s.total_jobs, 0)
      FROM public.cleaner_weekly_settlements s
     WHERE s.week_start_at >= v_ini AND s.week_start_at < v_fim
    UNION ALL
    -- lavadores (cêntimos)
    SELECT 'washer', NULL, s.washer_id::text,
           extract(quarter FROM (s.week_start_at AT TIME ZONE 'Europe/Lisbon'))::int,
           COALESCE(s.total_earnings_cents, 0)::bigint, COALESCE(s.total_bora_fee_cents, 0)::bigint, COALESCE(s.total_jobs, 0)
      FROM public.washer_weekly_settlements s
     WHERE s.week_start_at >= v_ini AND s.week_start_at < v_fim),
  agg AS (
    SELECT tipo, user_id, entity_id,
           SUM(cents) FILTER (WHERE tri = 1) AS t1, SUM(cents) FILTER (WHERE tri = 2) AS t2,
           SUM(cents) FILTER (WHERE tri = 3) AS t3, SUM(cents) FILTER (WHERE tri = 4) AS t4,
           SUM(cents) AS total, SUM(comissoes_cents) AS comissoes, SUM(n) AS transacoes
      FROM tot GROUP BY tipo, user_id, entity_id),
  vend AS (
    SELECT a.*,
           CASE a.tipo
             WHEN 'driver'  THEN (SELECT to_jsonb(d) FROM public.drivers d WHERE d.user_id::text = a.user_id OR d.id::text = a.user_id LIMIT 1)
             WHEN 'partner' THEN (SELECT to_jsonb(r) FROM public.restaurants r WHERE r.id = a.entity_id)
             WHEN 'cleaner' THEN (SELECT to_jsonb(c) FROM public.cleaners c WHERE c.id::text = a.entity_id)
             WHEN 'washer'  THEN (SELECT to_jsonb(w) FROM public.washers w WHERE w.id::text = a.entity_id)
           END AS p
      FROM agg a)
  SELECT COALESCE(jsonb_agg(jsonb_build_object(
           'ano', v_ano, 'tipo', v.tipo, 'id', COALESCE(v.entity_id, v.user_id),
           'nome', COALESCE(v.p->>'legal_name', v.p->>'name'),
           'nome_comercial', v.p->>'name',
           'nif', v.p->>'nif', 'morada', COALESCE(v.p->>'address', v.p->>'base_address'),
           'data_nascimento', v.p->>'birth_date', 'iban', v.p->>'iban', 'pais', 'PT',
           'autocertificado_em', v.p->>'dsa_self_certified_at',
           'trimestre_1_cents', COALESCE(v.t1, 0), 'trimestre_2_cents', COALESCE(v.t2, 0),
           'trimestre_3_cents', COALESCE(v.t3, 0), 'trimestre_4_cents', COALESCE(v.t4, 0),
           'total_cents', COALESCE(v.total, 0), 'comissoes_bora_cents', COALESCE(v.comissoes, 0),
           'transacoes', COALESCE(v.transacoes, 0),
           'campos_em_falta', to_jsonb(COALESCE(public._conformidade_em_falta(COALESCE(v.p, '{}'::jsonb)), ARRAY[]::text[]))
         ) ORDER BY v.tipo, COALESCE(v.p->>'legal_name', v.p->>'name')), '[]'::jsonb)
    INTO v_out
    FROM vend v
   WHERE COALESCE(v.total, 0) <> 0 OR COALESCE(v.transacoes, 0) > 0;

  RETURN jsonb_build_object('ano', v_ano, 'gerado_em', now(), 'linhas', v_out,
                            'nota', 'DAC7 (DL 26/2023): contraprestação paga por trimestre, comissões retidas e n.º de operações por vendedor. Faxineiros/lavadores em cêntimos na origem; estafetas/parceiros em euros x100.');
END;
$function$;
REVOKE ALL ON FUNCTION public.admin_dac7_export(integer) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.admin_dac7_export(integer) FROM anon;
GRANT EXECUTE ON FUNCTION public.admin_dac7_export(integer) TO authenticated, service_role;
