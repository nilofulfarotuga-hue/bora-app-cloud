-- Reembolso automático quando uma corrida TVDE imediata paga é cancelada.
-- Aplicado em produção a 2026-09-25 por MCP; esta é a cópia no repositório.
--
-- A CICATRIZ: a Izilda pagou 8 € por MB Way pelo pacote ida-e-volta, o motorista aceitou e
-- desistiu, ela cancelou sem motorista atribuído (taxa 0) e NINGUÉM devolveu o dinheiro.
-- Três buracos ao mesmo tempo: (1) a `tvde_cancel_ride` não tinha passo de reembolso — só
-- as RESERVAS devolviam; (2) no pacote o PaymentIntent fica no VALE e não na corrida, por
-- isso nem o caminho das reservas o encontraria; (3) o vale ficava `ativo` para sempre.
--
-- PORQUÊ UM GATILHO E NÃO UM REMENDO NA `tvde_cancel_ride`: o estado final também é posto
-- noutros sítios — o `tvde_offer_to_next` marca `sem_motorista` quando a janela acaba, e
-- isso é código de DESPACHO, que não se toca. Um gatilho no estado apanha todos os caminhos
-- (cliente, motorista, sweep, painel) sem mexer em nenhum deles.
create or replace function public.tvde_ride_auto_refund(p_ride_id uuid, p_motivo text)
returns boolean
language plpgsql security definer set search_path = public, vault as $$
DECLARE
  v_ride public.tvde_rides;
  v_pi text;
  v_key text;
  v_url text;
BEGIN
  SELECT * INTO v_ride FROM public.tvde_rides WHERE id = p_ride_id;
  IF NOT FOUND THEN RETURN false; END IF;

  -- Só dinheiro que entrou mesmo por MB Way ou cartão.
  IF COALESCE(v_ride.payment_method,'cash') NOT IN ('mbway','card') THEN RETURN false; END IF;
  IF COALESCE(v_ride.payment_status,'') <> 'succeeded' THEN RETURN false; END IF;

  -- O pagamento está na corrida OU no vale do pacote.
  v_pi := v_ride.payment_intent_id;
  IF v_pi IS NULL AND v_ride.roundtrip_credit_id IS NOT NULL THEN
    SELECT payment_intent_id INTO v_pi FROM public.tvde_roundtrip_credits
     WHERE id = v_ride.roundtrip_credit_id;
  END IF;
  IF v_pi IS NULL THEN RETURN false; END IF;

  SELECT decrypted_secret INTO v_key FROM vault.decrypted_secrets WHERE name='service_role_key';
  SELECT decrypted_secret INTO v_url FROM vault.decrypted_secrets WHERE name='project_url';
  IF v_key IS NULL THEN RETURN false; END IF;
  v_url := COALESCE(v_url, 'https://ojykpzwqrtusfeakzrna.supabase.co');

  PERFORM net.http_post(
    url := v_url || '/functions/v1/tvde-payment',
    headers := jsonb_build_object('Content-Type','application/json','Authorization','Bearer '||v_key),
    body := jsonb_build_object('action','auto_refund_ride','ride_id', p_ride_id::text, 'motivo', p_motivo));

  INSERT INTO public.tvde_ride_events (ride_id, status, actor, meta)
    VALUES (p_ride_id, 'reembolso_pedido', 'system',
            jsonb_build_object('motivo', p_motivo, 'payment_intent', v_pi,
                               'taxa_cents', COALESCE(v_ride.cancel_fee_cents,0)));
  RETURN true;
END $$;
revoke all on function public.tvde_ride_auto_refund(uuid, text) from public;
revoke all on function public.tvde_ride_auto_refund(uuid, text) from anon;
grant execute on function public.tvde_ride_auto_refund(uuid, text) to authenticated, service_role;

-- O gatilho. Só corridas IMEDIATAS: as reservas já têm o seu caminho
-- (`tvde_reservation_auto_refund`), e chamar os dois seria arriscar devolver duas vezes.
create or replace function public.fn_tvde_ride_auto_refund_on_cancel()
returns trigger
language plpgsql security definer set search_path = public as $$
BEGIN
  IF NEW.status IS NOT DISTINCT FROM OLD.status THEN RETURN NEW; END IF;
  IF NEW.status NOT IN ('cancelada_cliente','cancelada_motorista','sem_motorista') THEN RETURN NEW; END IF;
  IF NEW.reservation_status IS NOT NULL THEN RETURN NEW; END IF;   -- reserva: caminho próprio
  IF COALESCE(NEW.payment_method,'cash') NOT IN ('mbway','card') THEN RETURN NEW; END IF;
  IF COALESCE(NEW.payment_status,'') <> 'succeeded' THEN RETURN NEW; END IF;

  PERFORM public.tvde_ride_auto_refund(NEW.id, 'estado ' || NEW.status);
  RETURN NEW;
END $$;

drop trigger if exists tr_tvde_ride_auto_refund_on_cancel on public.tvde_rides;
create trigger tr_tvde_ride_auto_refund_on_cancel
  after update of status on public.tvde_rides
  for each row execute function public.fn_tvde_ride_auto_refund_on_cancel();

-- ─────────────────────────────────────────────────────────────────────────────
-- O painel passa a ver (e a poder tratar) o reembolso.
--
-- NÃO se reescreve a `admin_tvde_rides_list`: é grande, delicada e está a funcionar. Esta
-- versão ENVOLVE-A e acrescenta, por corrida, o estado do reembolso e o valor devolvido.
create or replace function public.admin_tvde_rides_list_v2(p_scope text default 'live', p_limit integer default 200)
returns jsonb
language plpgsql security definer set search_path = public as $$
DECLARE
  v_admin RECORD;
  v_base jsonb;
  v_out jsonb;
BEGIN
  -- Filtro NOVO: «canceladas pagas sem reembolso» — a gaveta onde fica dinheiro esquecido.
  IF p_scope = 'sem_reembolso' THEN
    SELECT admin_id INTO v_admin FROM public._admin_op_guard();
    SELECT COALESCE(jsonb_agg(to_jsonb(x) ORDER BY x.created_at DESC), '[]'::jsonb) INTO v_out
    FROM (
      SELECT r.id, r.created_at, r.status, r.payment_method, r.payment_status,
             r.est_fare_cents, r.final_fare_cents, r.cancel_fee_cents,
             COALESCE(r.payment_intent_id, c.payment_intent_id) AS payment_intent_id,
             c.paid_cents AS pacote_cents, c.status AS vale_status,
             u.name AS client_name, r.origin_label, r.dest_label,
             'pendente'::text AS reembolso_estado,
             GREATEST(0, COALESCE(c.paid_cents, r.final_fare_cents, r.est_fare_cents, 0)
                         - COALESCE(r.cancel_fee_cents, 0)) AS reembolso_cents
        FROM public.tvde_rides r
        LEFT JOIN public.tvde_roundtrip_credits c ON c.id = r.roundtrip_credit_id
        LEFT JOIN public.users u ON u.id = r.client_id
       WHERE r.status IN ('cancelada_cliente','cancelada_motorista','sem_motorista','no_show')
         AND COALESCE(r.payment_method,'cash') IN ('mbway','card')
         AND COALESCE(r.payment_status,'') = 'succeeded'
         AND COALESCE(r.payment_intent_id, c.payment_intent_id) IS NOT NULL
       ORDER BY r.created_at DESC
       LIMIT GREATEST(1, LEAST(p_limit, 1000))
    ) x;
    RETURN v_out;
  END IF;

  v_base := public.admin_tvde_rides_list(p_scope, p_limit);
  SELECT COALESCE(jsonb_agg(
           linha || jsonb_build_object(
             'payment_status', r.payment_status,
             'payment_method', r.payment_method,
             'cancel_fee_cents', r.cancel_fee_cents,
             'pacote_cents', c.paid_cents,
             'vale_status', c.status,
             'payment_intent_id', COALESCE(r.payment_intent_id, c.payment_intent_id),
             'reembolso_estado', CASE
                WHEN r.payment_status = 'refunded' THEN 'devolvido'
                WHEN r.payment_status = 'partial_refund' THEN 'parcial'
                WHEN r.payment_status = 'kept_cancel_fee' THEN 'so_taxa'
                WHEN EXISTS (SELECT 1 FROM public.tvde_ride_events e
                              WHERE e.ride_id = r.id AND e.status = 'reembolso_falhou') THEN 'falhou'
                WHEN r.status IN ('cancelada_cliente','cancelada_motorista','sem_motorista','no_show')
                     AND COALESCE(r.payment_method,'cash') IN ('mbway','card')
                     AND COALESCE(r.payment_status,'') = 'succeeded'
                     AND COALESCE(r.payment_intent_id, c.payment_intent_id) IS NOT NULL THEN 'pendente'
                ELSE NULL END,
             'reembolso_cents', (SELECT (e.meta->>'devolvido_cents')::int
                                   FROM public.tvde_ride_events e
                                  WHERE e.ride_id = r.id AND e.status = 'reembolso_feito'
                                  ORDER BY e.at DESC LIMIT 1))
         ), '[]'::jsonb)
    INTO v_out
  FROM jsonb_array_elements(v_base) AS linha
  JOIN public.tvde_rides r ON r.id = (linha->>'id')::uuid
  LEFT JOIN public.tvde_roundtrip_credits c ON c.id = r.roundtrip_credit_id;

  RETURN v_out;
END $$;
revoke all on function public.admin_tvde_rides_list_v2(text, integer) from public;
revoke all on function public.admin_tvde_rides_list_v2(text, integer) from anon;
grant execute on function public.admin_tvde_rides_list_v2(text, integer) to authenticated, service_role;

-- Botão «Reembolsar agora» do painel: total (valor nulo) ou parcial (em cêntimos).
-- Passa pela MESMA porta do reembolso automático, por isso herda a protecção contra
-- devolver duas vezes — quem decide quanto falta devolver é a Stripe.
create or replace function public.admin_tvde_refund_ride(p_ride_id uuid, p_valor_cents integer default null)
returns boolean
language plpgsql security definer set search_path = public, vault as $$
DECLARE v_key text; v_url text; v_ride public.tvde_rides; v_pi text;
BEGIN
  IF NOT public.is_admin() THEN RAISE EXCEPTION 'not_admin'; END IF;
  SELECT * INTO v_ride FROM public.tvde_rides WHERE id = p_ride_id;
  IF NOT FOUND THEN RAISE EXCEPTION 'ride_not_found'; END IF;
  v_pi := v_ride.payment_intent_id;
  IF v_pi IS NULL AND v_ride.roundtrip_credit_id IS NOT NULL THEN
    SELECT payment_intent_id INTO v_pi FROM public.tvde_roundtrip_credits WHERE id = v_ride.roundtrip_credit_id;
  END IF;
  IF v_pi IS NULL THEN RAISE EXCEPTION 'sem_pagamento_online'; END IF;

  SELECT decrypted_secret INTO v_key FROM vault.decrypted_secrets WHERE name='service_role_key';
  SELECT decrypted_secret INTO v_url FROM vault.decrypted_secrets WHERE name='project_url';
  IF v_key IS NULL THEN RAISE EXCEPTION 'sem_service_role_key'; END IF;

  PERFORM net.http_post(
    url := COALESCE(v_url,'https://ojykpzwqrtusfeakzrna.supabase.co') || '/functions/v1/tvde-payment',
    headers := jsonb_build_object('Content-Type','application/json','Authorization','Bearer '||v_key),
    body := jsonb_build_object('action','auto_refund_ride','ride_id', p_ride_id::text,
                               'motivo','reembolso pedido pelo admin no painel',
                               'valor_cents', COALESCE(p_valor_cents, 0)));

  INSERT INTO public.tvde_ride_events (ride_id, status, actor, meta)
    VALUES (p_ride_id, 'reembolso_pedido', 'admin',
            jsonb_build_object('motivo','pedido no painel','valor_cents', p_valor_cents, 'payment_intent', v_pi));
  RETURN true;
END $$;
revoke all on function public.admin_tvde_refund_ride(uuid, integer) from public;
revoke all on function public.admin_tvde_refund_ride(uuid, integer) from anon;
grant execute on function public.admin_tvde_refund_ride(uuid, integer) to authenticated, service_role;
