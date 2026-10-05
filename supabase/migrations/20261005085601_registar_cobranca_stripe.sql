-- Ronda 04/10 A.1/A.5: ninguém gravava orders.stripe_charge_cents (6 de 7 MB Way pagos a 0), e o
-- limite de reembolso (_enforce_refund_cap) compara com ele: reembolsar um pedido assim falhava.
-- Grava o valor que a Stripe cobrou (amount_received). Só preenche se estiver a 0/nulo e o PI for o do pedido.
create or replace function public.registar_cobranca_stripe(p_order_id text, p_payment_intent_id text, p_cents integer)
returns boolean
language plpgsql security definer set search_path to 'public'
as $f$
declare v_n int;
begin
  if p_cents is null or p_cents <= 0 or p_payment_intent_id is null or p_order_id is null then
    return false;
  end if;
  update public.orders o
     set stripe_charge_cents = p_cents
   where o.id = p_order_id
     and o.payment_intent_id = p_payment_intent_id
     and coalesce(o.stripe_charge_cents, 0) = 0;
  get diagnostics v_n = row_count;
  return v_n > 0;
end $f$;
revoke all on function public.registar_cobranca_stripe(text, text, integer) from public, anon, authenticated;
grant execute on function public.registar_cobranca_stripe(text, text, integer) to service_role;
comment on function public.registar_cobranca_stripe(text, text, integer) is
  'Ronda 04/10 A.1: grava em orders.stripe_charge_cents o amount_received do PaymentIntent. Só service_role. Só preenche quando está a 0.';
