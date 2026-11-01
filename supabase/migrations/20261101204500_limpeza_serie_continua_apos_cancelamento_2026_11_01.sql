-- Série de limpeza continua depois de o cliente cancelar UMA marcação (ordem do Danilo 01/11/2026 19:56,
-- ponto 13: "Quando o cliente cancela uma limpeza da série, a próxima para de aparecer (o que aconteceu com o
-- Divan). Tem que consertar isso.")
--
-- CAUSA: generate_recurring_bookings tinha, desde 05/07 ("escolha documentada"), a linha
--   CONTINUE WHEN v_last.status = 'cancelled_client' AND v_last.cancelled_by IN ('client','admin');
-- ou seja, se a ÚLTIMA marcação da série estava cancelada pelo cliente (ou pelo admin), a série morria em
-- silêncio: nunca mais se gerava a seguinte. Foi isso que aconteceu ao Divan: cancelou a de sáb 31/10 e a de
-- 07/11 nunca nasceu. A app já tem o botão "Parar série" (cancel_cleaning_series → cleaning_recurrence_stops),
-- que é o único caminho certo para acabar uma série.
--
-- AGORA:
--   • a série só pára com cleaning_recurrence_stops (botão "Parar série" do cliente ou admin);
--   • cancelar uma marcação tira só essa marcação; a seguinte nasce na mesma (7 dias antes, como sempre);
--   • 3 cancelamentos seguidos do cliente na mesma série → avisa o admin (uma vez por 30 dias), mas NÃO pára;
--   • cleaning_series_next_at(gid): a próxima data da série, só leitura, para o painel e para provar;
--   • o texto do alerta ao admin no cancelamento (_alerta_txt_limpeza_cancelada) deixa de dizer
--     "acaba aqui, não se cria a próxima" e passa a dizer que as seguintes continuam.

-- ── próxima data da série (mesma conta que o gerador; só leitura) ──
create or replace function public.cleaning_series_next_at(p_gid uuid)
returns timestamptz language plpgsql stable security definer set search_path to 'public' as $f$
declare
  v_last cleaning_bookings; v_first cleaning_bookings;
  v_interval interval; v_anchor timestamp; v_last_local timestamp; v_k int; v_n int;
begin
  select * into v_last from cleaning_bookings where recurrence_group_id = p_gid order by scheduled_at desc limit 1;
  if v_last.id is null or v_last.recurrence not in ('weekly','biweekly') then return null; end if;
  v_interval := case v_last.recurrence when 'weekly' then interval '7 days' else interval '14 days' end;
  select * into v_first from cleaning_bookings where recurrence_group_id = p_gid order by created_at asc limit 1;
  v_anchor     := v_first.scheduled_at at time zone 'Europe/Lisbon';
  v_last_local := v_last.scheduled_at at time zone 'Europe/Lisbon';
  v_k := floor(extract(epoch from (v_last_local - v_anchor)) / extract(epoch from v_interval))::int + 1;
  select count(*) into v_n from cleaning_bookings where recurrence_group_id = p_gid;
  v_k := greatest(v_k, v_n, 1);
  return (v_anchor + v_interval * v_k) at time zone 'Europe/Lisbon';
end
$f$;
revoke all on function public.cleaning_series_next_at(uuid) from public, anon;
grant execute on function public.cleaning_series_next_at(uuid) to authenticated, service_role;

-- ── gerador ──
CREATE OR REPLACE FUNCTION public.generate_recurring_bookings()
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_count int := 0; v_rec record; v_last cleaning_bookings;
  v_next timestamptz; v_quote jsonb; v_id uuid; v_seguidos int;
BEGIN
  FOR v_rec IN
    SELECT DISTINCT recurrence_group_id AS gid FROM cleaning_bookings
    WHERE recurrence_group_id IS NOT NULL
      AND recurrence IN ('weekly','biweekly')
      AND NOT EXISTS (SELECT 1 FROM cleaning_recurrence_stops s
                      WHERE s.group_id = cleaning_bookings.recurrence_group_id)
  LOOP
    SELECT * INTO v_last FROM cleaning_bookings
    WHERE recurrence_group_id = v_rec.gid
    ORDER BY scheduled_at DESC LIMIT 1;

    -- 01/11/2026 (regra do Danilo): cancelar UMA marcação não acaba a série. A série só acaba
    -- com "Parar série" (cleaning_recurrence_stops). Antes havia aqui um CONTINUE quando a última
    -- estava cancelled_client, e a série morria em silêncio (caso do Divan, 31/10).

    -- 19/10/2026: a série segue o dia e a hora da 1.ª reserva, em hora de Lisboa (conta em
    -- cleaning_series_next_at, partilhada com o painel).
    v_next := public.cleaning_series_next_at(v_rec.gid);
    CONTINUE WHEN v_next IS NULL;
    CONTINUE WHEN v_next - now() > interval '7 days';
    CONTINUE WHEN v_next < now();

    v_quote := public.cleaning_quote(v_last.cleaning_type, v_last.pricing_mode,
                                     v_last.home_size, v_last.hours,
                                     v_last.recurrence, v_last.products_by);

    INSERT INTO cleaning_bookings (
      client_user_id, requested_cleaner_id, recurrence_group_id, recurrence,
      cleaning_type, pricing_mode, home_size, hours, scheduled_at, duration_min,
      address_street, address_city, address_postal, lat, lng, notes, products_by,
      payment_method, payment_status,
      base_cents, type_surcharge_cents, recurring_discount_cents, products_fee_cents,
      total_cents, cleaner_earnings_cents, bora_fee_cents
    ) VALUES (
      v_last.client_user_id,
      COALESCE(v_last.cleaner_id, v_last.requested_cleaner_id),
      v_rec.gid, v_last.recurrence,
      v_last.cleaning_type, v_last.pricing_mode, v_last.home_size, v_last.hours,
      v_next, (v_quote ->> 'duration_min')::int,
      v_last.address_street, v_last.address_city, v_last.address_postal,
      v_last.lat, v_last.lng, v_last.notes, v_last.products_by,
      v_last.payment_method, 'unpaid',
      (v_quote ->> 'base_cents')::int, (v_quote ->> 'type_surcharge_cents')::int,
      (v_quote ->> 'recurring_discount_cents')::int, (v_quote ->> 'products_fee_cents')::int,
      (v_quote ->> 'total_cents')::int, (v_quote ->> 'cleaner_earnings_cents')::int,
      (v_quote ->> 'bora_fee_cents')::int
    ) RETURNING id INTO v_id;

    -- Dinheiro: chama já. MB Way/cartão: _cleaning_next_offer sai logo (por pagar).
    PERFORM public._cleaning_next_offer(v_id);

    IF v_last.payment_method = 'mbway' THEN
      PERFORM public.cleaning_request_payment(v_id);
      PERFORM public._cleaning_notify_user(v_last.client_user_id, 'cleaning_recurring',
        'Próxima limpeza agendada 🔁',
        'A tua limpeza recorrente de ' ||
        to_char(v_next AT TIME ZONE 'Europe/Lisbon', 'DD/MM às HH24:MI') ||
        ' foi criada. Aprova o pagamento MB Way no teu telemóvel para confirmarmos a profissional.',
        v_id::text);
    ELSE
      PERFORM public._cleaning_notify_user(v_last.client_user_id, 'cleaning_recurring',
        'Próxima limpeza agendada 🔁',
        'A tua limpeza recorrente de ' ||
        to_char(v_next AT TIME ZONE 'Europe/Lisbon', 'DD/MM às HH24:MI') ||
        ' foi criada. Podes cancelar na app.',
        v_id::text);
    END IF;
    v_count := v_count + 1;

    -- 3 cancelamentos seguidos do cliente nesta série → o Danilo fica a saber (não pára nada).
    SELECT count(*) INTO v_seguidos FROM (
      SELECT status, cancelled_by FROM cleaning_bookings
       WHERE recurrence_group_id = v_rec.gid AND id <> v_id
       ORDER BY scheduled_at DESC LIMIT 3) u
     WHERE u.status = 'cancelled_client' AND u.cancelled_by = 'client';
    IF v_seguidos >= 3 AND NOT EXISTS (
         SELECT 1 FROM admin_notifications n
          WHERE n.event_type = 'cleaning_series_cancelamentos' AND n.entity_id = v_rec.gid::text
            AND n.created_at > now() - interval '30 days') THEN
      BEGIN
        PERFORM public.notify_admin_urgent_push('cleaning_series_cancelamentos',
          E'🔁 SÉRIE DE LIMPEZA — o cliente cancelou as últimas 3\n'
          || public._alerta_quem(v_last.client_user_id) || E'\nA série continua (próxima '
          || to_char(v_next AT TIME ZONE 'Europe/Lisbon', 'DD/MM HH24:MI')
          || '). Se já não quer, o cliente pára a série na app ("Parar série").',
          'cleaning_series', v_rec.gid::text,
          jsonb_build_object('group_id', v_rec.gid, 'client_user_id', v_last.client_user_id, 'booking_id', v_id),
          '/admin/limpeza/' || v_id::text);
      EXCEPTION WHEN OTHERS THEN
        RAISE NOTICE 'generate_recurring_bookings: alerta falhou (%)', sqlerrm;
      END;
    END IF;
  END LOOP;
  RETURN v_count;
END $function$;

-- ── texto do alerta ao admin no cancelamento: a série continua ──
CREATE OR REPLACE FUNCTION public._alerta_txt_limpeza_cancelada(b cleaning_bookings)
 RETURNS text
 LANGUAGE plpgsql
 STABLE
 SET search_path TO 'public'
AS $function$
declare
  v_prof  text;
  v_serie text := '';
  v_motivo text;
  v_next timestamptz;
begin
  if b.cleaner_id is not null then
    select name into v_prof from cleaners where id = b.cleaner_id;
  end if;

  if b.recurrence_group_id is not null and b.recurrence in ('weekly', 'biweekly') then
    v_serie := E'\nSérie ' || case b.recurrence when 'weekly' then 'semanal' else 'de 15 em 15 dias' end || ': ';
    if b.cancel_reason = 'serie_terminada'
       or exists (select 1 from cleaning_recurrence_stops s where s.group_id = b.recurrence_group_id) then
      v_serie := v_serie || 'o cliente terminou a série';
    else
      -- 01/11/2026: só esta marcação sai; a seguinte nasce na mesma (generate_recurring_bookings).
      v_next := public.cleaning_series_next_at(b.recurrence_group_id);
      v_serie := v_serie || 'as seguintes continuam'
              || coalesce(' (próxima ' || to_char(v_next at time zone 'Europe/Lisbon', 'DD/MM HH24:MI') || ')', '');
    end if;
  end if;

  v_motivo := case b.cancel_reason
                when 'serie_terminada' then 'terminou a série'
                when 'no_show_cliente' then 'cliente não estava em casa'
                else b.cancel_reason end;

  return case when coalesce(b.no_show_client, false)
              then '🚫 LIMPEZA — CLIENTE NÃO APARECEU — '
              else '❌ LIMPEZA CANCELADA PELO CLIENTE — ' end
      || public._alerta_quem(b.client_user_id)
      || E'\nEra: '    || public._alerta_quando(b.scheduled_at)
      || E'\nMorada: ' || btrim(coalesce(b.address_street, '') || ' ' || coalesce(b.address_city, ''))
      || E'\nProfissional: ' || case when coalesce(b.no_show_client, false)
                                     then coalesce(v_prof, '?')
                                     else coalesce(v_prof || ' (já foi avisada pela app)', 'nenhuma atribuída') end
      || E'\nMotivo: ' || coalesce(nullif(btrim(v_motivo), ''), 'não disse')
      || E'\nTaxa: '   || case when coalesce(b.cancel_fee_cents, 0) > 0
                              then to_char(b.cancel_fee_cents / 100.0, 'FM999990.00') || ' EUR'
                              else 'nenhuma' end
      || v_serie
      || E'\n#' || left(b.id::text, 8);
end
$function$;
