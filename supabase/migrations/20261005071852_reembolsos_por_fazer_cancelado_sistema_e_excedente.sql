-- 05/10/2026 — pedido do Danilo: "investiga e corrige o reembolso automático quando um pedido pago é
-- cancelado e o excedente dos 15% dos mercados que não volta ao cliente. Eu autorizo."
-- Aplicado em produção pela Claude.ai (versões 20261005071631, 071652, 071759, 071852); este ficheiro é o
-- estado final consolidado. NENHUM destes gatilhos move dinheiro: marcam o pedido "por reembolsar"
-- (refund_status='failed' + refund_amount + refund_method), criam a linha em cancellation_requests para o
-- ecrã Cancelamentos do painel (botão "Reprocessar" → Edge reprocess-refund: MB Way → saldo da carteira por
-- inteiro; cartão → reembolso Stripe) e avisam o admin (notify_admin_event 'order_refund_needed').
-- Provas (transação desfeita): cancelado pelo sistema 8,81 € MB Way → failed/8.81/wallet + 1 linha;
-- McDonald's entregue buffer 17,24 / final 14,99 → failed/2.25/wallet + 1 linha; cancelado pelo cliente → intacto.
CREATE OR REPLACE FUNCTION public.fn_reembolso_cancelado_pelo_sistema()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_eur numeric;
  v_metodo text;
begin
  if new.status::text not in ('cancelled','rejected') or old.status is not distinct from new.status then return new; end if;
  if new.cancellation_initiator is null or new.cancellation_initiator::text <> 'system' then return new; end if;
  if new.payment_method::text not in ('card','mbway') then return new; end if;
  if coalesce(new.payment_status::text,'') <> 'paid' or new.refund_status is not null then return new; end if;
  if coalesce(new.is_test_order,false) then return new; end if;

  v_eur := round(coalesce(new.payment_buffer_total::numeric, new.customer_total, new.total), 2);
  if coalesce(v_eur,0) <= 0 then return new; end if;
  v_metodo := case when new.payment_method::text = 'card' then 'stripe' else 'wallet' end;
  new.refund_amount := v_eur::double precision;
  new.refund_method := v_metodo;
  new.refund_status := 'failed';

  begin
    insert into public.cancellation_requests
      (order_id, requester_role, requester_id, reason, status, refund_method, auto_resolved, cancel_stage, fee_cents, refund_cents, reviewed_at)
    values
      (new.id, 'client', new.user_id,
       'Cancelado pelo sistema (' || coalesce(new.cancel_reason,'sem motivo') || ') — reembolso total por fazer',
       'approved', v_metodo, true, 'grace', 0, round(v_eur*100)::int, now());
  exception when others then
    raise warning 'fn_reembolso_cancelado_pelo_sistema: cancellation_requests % %', new.id, sqlerrm;
  end;

  begin
    perform public.notify_admin_event(
      'order_refund_needed', 'high',
      format('Pedido pago #%s cancelado pelo sistema — reembolsar %s €', substring(new.id::text,1,8), to_char(v_eur,'FM999990.00')),
      'order', new.id::text,
      jsonb_build_object('refund_amount', v_eur, 'refund_method', v_metodo, 'cancel_reason', new.cancel_reason),
      '/admin/cancellations');
  exception when others then
    raise warning 'fn_reembolso_cancelado_pelo_sistema: notify % %', new.id, sqlerrm;
  end;
  return new;
exception when others then
  raise warning 'fn_reembolso_cancelado_pelo_sistema: %', sqlerrm;
  return new;
end;
$function$
;

CREATE OR REPLACE FUNCTION public.fn_excedente_preautorizacao()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_buffer numeric;
  v_final numeric;
  v_dif numeric;
  v_metodo text;
begin
  if new.status::text <> 'delivered' or old.status is not distinct from new.status then return new; end if;
  if new.payment_method::text not in ('card','mbway') then return new; end if;
  if coalesce(new.payment_status::text,'') <> 'paid' then return new; end if;
  if new.refund_status is not null or new.refund_amount is not null then return new; end if;
  if coalesce(new.is_test_order,false) or new.payment_buffer_total is null then return new; end if;

  v_buffer := round(new.payment_buffer_total::numeric, 2);
  v_final := coalesce(new.final_total, new.customer_total, new.total);
  if v_final is null then return new; end if;
  v_dif := round(v_buffer - v_final, 2);
  if v_dif < 0.01 then return new; end if;

  v_metodo := case when new.payment_method::text = 'card' then 'stripe' else 'wallet' end;
  new.refund_amount := v_dif::double precision;
  new.refund_method := v_metodo;
  new.refund_status := 'failed';

  begin
    insert into public.cancellation_requests
      (order_id, requester_role, requester_id, reason, status, refund_method, auto_resolved, cancel_stage, fee_cents, refund_cents, reviewed_at)
    values
      (new.id, 'client', new.user_id,
       format('Excedente da pré-autorização: pagou %s €, o pedido ficou em %s € — devolver %s €',
              to_char(v_buffer,'FM999990.00'), to_char(v_final,'FM999990.00'), to_char(v_dif,'FM999990.00')),
       'approved', v_metodo, true, 'grace', 0, round(v_dif*100)::int, now());
  exception when others then
    raise warning 'fn_excedente_preautorizacao: cancellation_requests % %', new.id, sqlerrm;
  end;

  begin
    perform public.notify_admin_event(
      'order_refund_needed', 'high',
      format('Pedido #%s entregue com excedente — devolver %s € ao cliente', substring(new.id::text,1,8), to_char(v_dif,'FM999990.00')),
      'order', new.id::text,
      jsonb_build_object('refund_amount', v_dif, 'refund_method', v_metodo, 'buffer', v_buffer, 'final', v_final),
      '/admin/cancellations');
  exception when others then
    raise warning 'fn_excedente_preautorizacao: notify % %', new.id, sqlerrm;
  end;
  return new;
exception when others then
  raise warning 'fn_excedente_preautorizacao: %', sqlerrm;
  return new;
end;
$function$
;


revoke all on function public.fn_reembolso_cancelado_pelo_sistema() from public, anon, authenticated;
revoke all on function public.fn_excedente_preautorizacao() from public, anon, authenticated;

do $$ begin
  if not exists (select 1 from pg_trigger where tgname='trg_reembolso_cancelado_pelo_sistema' and tgrelid='public.orders'::regclass) then
    create trigger trg_reembolso_cancelado_pelo_sistema before update of status on public.orders
      for each row execute function public.fn_reembolso_cancelado_pelo_sistema();
  end if;
  if not exists (select 1 from pg_trigger where tgname='trg_excedente_preautorizacao' and tgrelid='public.orders'::regclass) then
    create trigger trg_excedente_preautorizacao before update of status on public.orders
      for each row execute function public.fn_excedente_preautorizacao();
  end if;
end $$;
