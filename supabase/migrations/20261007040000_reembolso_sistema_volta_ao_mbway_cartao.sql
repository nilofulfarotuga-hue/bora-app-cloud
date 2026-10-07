-- 07/10/2026 (regra do Danilo): pedido PAGO (MB Way ou cartão) que o SISTEMA cancela
-- (ex.: nenhum estafeta aceitou) devolve o dinheiro TODO, sozinho, ao MB Way/cartão
-- original — nunca à carteira — igual ao TVDE. Devolve também os tokens/desconto usados.
-- Caso real: McDonald's 947f7206 de 06/10 (Solaidy, 18,68 € MB Way) ficou "por fazer".
-- Aplicado em produção por MCP a 07/10/2026; o envio ao Stripe é feito pela Edge
-- Function auto-refund-order (supabase/functions/auto-refund-order).
CREATE OR REPLACE FUNCTION public.fn_reembolso_cancelado_pelo_sistema()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'vault'
AS $function$
declare
  v_eur numeric;
  v_key text;
begin
  if new.status::text not in ('cancelled','rejected') or old.status is not distinct from new.status then return new; end if;
  if new.cancellation_initiator is null or new.cancellation_initiator::text <> 'system' then return new; end if;
  if new.payment_method::text not in ('card','mbway') then return new; end if;
  if coalesce(new.payment_status::text,'') <> 'paid' or new.refund_status is not null then return new; end if;
  if coalesce(new.is_test_order,false) then return new; end if;

  v_eur := round(coalesce(new.stripe_charge_cents::numeric/100, new.payment_buffer_total::numeric, new.customer_total, new.total), 2);
  if coalesce(v_eur,0) <= 0 then return new; end if;
  new.refund_amount := v_eur::double precision;
  new.refund_method := 'stripe';
  new.refund_status := 'pending_auto';

  begin
    insert into public.cancellation_requests
      (order_id, requester_role, requester_id, reason, status, refund_method, auto_resolved, cancel_stage, fee_cents, refund_cents, reviewed_at)
    values
      (new.id, 'client', new.user_id,
       'Cancelado pelo sistema (' || coalesce(new.cancel_reason,'sem motivo') || ') — reembolso total automático ao meio de pagamento',
       'approved', 'stripe', true, 'grace', 0, round(v_eur*100)::int, now());
  exception when others then
    raise warning 'fn_reembolso_cancelado_pelo_sistema: cancellation_requests % %', new.id, sqlerrm;
  end;

  -- devolve os tokens usados no pedido
  begin
    -- tokens_applied_count nem sempre vem preenchido; o que manda é o valor usado e os tokens gastos no momento do pedido
    if coalesce(new.tokens_applied_value_cents,0) > 0 and new.user_id is not null then
      update public.bora_tokens
         set is_used = false, used_at = null
       where user_id = new.user_id and role = 'client' and is_used = true
         and used_at between new.created_at - interval '2 minutes' and new.created_at + interval '30 minutes';
    end if;
  exception when others then
    raise warning 'fn_reembolso_cancelado_pelo_sistema: tokens % %', new.id, sqlerrm;
  end;

  -- dispara o reembolso no Stripe (corre depois do commit)
  begin
    select decrypted_secret into v_key from vault.decrypted_secrets where name='service_role_key';
    if v_key is not null then
      perform net.http_post(
        url := 'https://ojykpzwqrtusfeakzrna.supabase.co/functions/v1/auto-refund-order',
        headers := jsonb_build_object('Content-Type','application/json','Authorization','Bearer '||v_key),
        body := jsonb_build_object('order_id', new.id::text, 'motivo', coalesce(new.cancel_reason,'cancelado_pelo_sistema')));
    end if;
  exception when others then
    raise warning 'fn_reembolso_cancelado_pelo_sistema: http % %', new.id, sqlerrm;
  end;

  begin
    perform public.notify_admin_event(
      'order_refund_auto', 'high',
      format('Pedido pago #%s cancelado pelo sistema — %s € a voltar ao %s do cliente', substring(new.id::text,1,8), to_char(v_eur,'FM999990.00'), case when new.payment_method::text='mbway' then 'MB Way' else 'cartão' end),
      'order', new.id::text,
      jsonb_build_object('refund_amount', v_eur, 'refund_method', 'stripe', 'cancel_reason', new.cancel_reason),
      '/admin/cancellations');
  exception when others then
    raise warning 'fn_reembolso_cancelado_pelo_sistema: notify % %', new.id, sqlerrm;
  end;
  return new;
exception when others then
  raise warning 'fn_reembolso_cancelado_pelo_sistema: %', sqlerrm;
  return new;
end;
$function$;
