-- M10 b2-limpeza (09/11/2026) — ordem do Danilo de 08/11/2026, AUTORIZADA: "Parar a série" da
-- limpeza devolve à CARTEIRA BORA as limpezas futuras já pagas (antes, desde 20261102153510, o
-- servidor marcava 'estornado' e a app pedia o estorno ao cartão/MB Way pelo cleaning-checkout).
--
-- O que muda (create or replace, idempotente; NENHUM valor muda):
--   * cancel_cleaning_series: cada limpeza continua a ser cancelada pelo cancel_cleaning_booking
--     (mesma taxa, mesmo estado, mesmo aviso). Se estava PAGA (cartão/MB Way com payment_status
--     'held' — cobrada na reserva desde a v2 do cleaning-checkout de 05/07), o que sobra da taxa
--     (fora das 24 h a taxa é zero, logo é o total) entra na carteira pela MESMA função que o
--     cancelamento de um pedido usa para creditar a carteira: wallet_credit_refund_split
--     (client-cancel-order, refund_target 'wallet'), que reparte por wallet_split_free_pct
--     (no ar = 1.0 → 100 % saldo livre, podes usar já). Chave de idempotência por limpeza
--     ('limpeza_serie_<id>'): a mesma limpeza nunca credita duas vezes.
--     Se o crédito falhar, o cancelamento DESSA limpeza desfaz-se (bloco próprio) e ela fica
--     marcada: nunca há limpeza cancelada sem o dinheiro devolvido.
--   * cleaning_series_preview: a mesma conta; acrescenta 'destino' = 'carteira' (aditivo).
--
-- A app (cleaning_store.dart) deixa de pedir o 'reverse' do cleaning-checkout ao parar a série.
-- Fica por fazer FORA deste ficheiro (zona Stripe, proposta no relatório): o 'reverse' do
-- cleaning-checkout recusar limpezas já devolvidas à carteira.
-- Prova em rollback: relatório M10 b2-limpeza (PROVA_OK com série de teste dentro do DO).

create or replace function public.cancel_cleaning_series(p_group_id uuid)
returns integer language plpgsql security definer set search_path to 'public'
as $function$
declare
  v_uid uuid := auth.uid();
  v_count int := 0;
  v_free int := public._cleaning_setting_int('cleaning_cancel_free_hours', 24);
  v_rec record;
  v_antes record;
  v_depois record;
  v_devolve int;
begin
  if not exists (select 1 from cleaning_bookings
                 where recurrence_group_id = p_group_id and client_user_id = v_uid) then
    raise exception 'series_not_yours';
  end if;
  insert into cleaning_recurrence_stops (group_id, stopped_by)
  values (p_group_id, v_uid)
  on conflict (group_id) do nothing;
  for v_rec in
    select id from cleaning_bookings
    where recurrence_group_id = p_group_id
      and client_user_id = v_uid
      and status in ('scheduled', 'accepted')
      and scheduled_at > now() + make_interval(hours => v_free)
    order by scheduled_at
  loop
    begin
      -- Como estava ANTES de cancelar (o cancelamento passa 'held' a 'estornado').
      select payment_method, payment_status into v_antes
        from cleaning_bookings where id = v_rec.id for update;
      -- O mesmo cancelamento de uma limpeza só (taxa, estado do pagamento, aviso à profissional).
      perform public.cancel_cleaning_booking(v_rec.id, 'serie_terminada', false);
      -- 08/11/2026 (Danilo): a parte paga volta à CARTEIRA BORA, pelo caminho do cancelamento de
      -- um pedido (wallet_credit_refund_split). Dinheiro e prémio não têm nada a devolver.
      if v_antes.payment_method in ('card', 'mbway') and v_antes.payment_status = 'held' then
        select total_cents, coalesce(cancel_fee_cents, 0) as fee into v_depois
          from cleaning_bookings where id = v_rec.id;
        v_devolve := greatest(coalesce(v_depois.total_cents, 0) - v_depois.fee, 0);
        if v_devolve > 0 then
          perform public.wallet_credit_refund_split(
            v_rec.id::text, v_uid, v_devolve,
            'Limpeza cancelada ao parar a série: devolvido à Carteira Bora',
            'limpeza_serie_' || v_rec.id::text);
        end if;
      end if;
      v_count := v_count + 1;
    exception when others then
      -- Uma limpeza que mudou de estado entretanto (ou cujo crédito falhou) não trava o resto
      -- da série; o cancelamento dela desfaz-se com o bloco.
      raise warning 'cancel_cleaning_series: % saltada (%)', v_rec.id, sqlerrm;
    end;
  end loop;
  return v_count;
end
$function$;

-- Só leitura: o que "Parar a série toda" vai cancelar e quanto volta À CARTEIRA (mesma conta da
-- taxa do cancel_cleaning_booking para o cliente). pago = cobrada na reserva (payment_status 'held').
create or replace function public.cleaning_series_preview(p_group_id uuid)
returns jsonb language plpgsql stable security definer set search_path to 'public'
as $function$
declare
  v_uid uuid := auth.uid();
  v_free int := public._cleaning_setting_int('cleaning_cancel_free_hours', 24);
  v_half int := public._cleaning_setting_int('cleaning_cancel_half_hours', 2);
  v_grace int := public._cleaning_setting_int('cleaning_cancel_grace_minutes', 5);
  v_lista jsonb;
begin
  if v_uid is null or not exists (select 1 from cleaning_bookings
                 where recurrence_group_id = p_group_id and client_user_id = v_uid) then
    raise exception 'series_not_yours';
  end if;
  with alvo as (
    select b.id, b.scheduled_at, b.total_cents, b.payment_method, b.payment_status,
           (b.payment_status = 'held' and b.payment_method in ('card', 'mbway')) as pago,
           case
             when extract(epoch from (b.scheduled_at - now())) / 3600.0 >= v_free
                  or now() - b.created_at <= make_interval(mins => v_grace) then 0
             when extract(epoch from (b.scheduled_at - now())) / 3600.0 >= v_half
                  then round(b.total_cents * 0.5)::int
             else b.total_cents
           end as taxa_cents
    from cleaning_bookings b
    where b.recurrence_group_id = p_group_id
      and b.client_user_id = v_uid
      and b.status in ('scheduled', 'accepted')
      and b.scheduled_at > now() + make_interval(hours => v_free)
  )
  select coalesce(jsonb_agg(jsonb_build_object(
           'id', id, 'scheduled_at', scheduled_at, 'total_cents', total_cents,
           'payment_method', payment_method, 'pago', pago, 'taxa_cents', taxa_cents,
           'devolve_cents', case when pago then greatest(total_cents - taxa_cents, 0) else 0 end,
           'destino', 'carteira'
         ) order by scheduled_at), '[]'::jsonb)
    into v_lista
  from alvo;
  return jsonb_build_object(
    'n', jsonb_array_length(v_lista),
    'devolve_cents', coalesce((select sum((x->>'devolve_cents')::int) from jsonb_array_elements(v_lista) x), 0),
    'destino', 'carteira',
    'limpezas', v_lista);
end
$function$;

grant execute on function public.cleaning_series_preview(uuid) to authenticated;