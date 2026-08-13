-- =============================================================================
-- PROPOSTA 🔴 ZONA VERMELHA — BUG 6: despacho imediato só para dinheiro a sério.
-- Missão `tvde-pagamento-tokens-despacho` (2026-08-13). Aplicar DEPOIS de
-- `20260813200000_PROPOSTA_tvde_tokens_e_cancelamento.sql`.
-- =============================================================================
-- PROVA (corrida 81d1bd09-cbd1-40d6-b78a-feefd58ca8ad, tvde_ride_events):
--   20:10:43.398  solicitada        client   payment_method: "cash"   <-- MB Way!
--   20:10:43.398  oferta            system   driver 4f61dd31, ttl 40s <-- MESMO ms
--   20:10:44.846  push_enviado      system   driver 4f61dd31
--   20:10:58.757  motorista_atribuido/motorista_a_caminho  driver    <-- ACEITOU
--   20:12:44.126  cancelada_cliente admin    reason=payment_failed, elapsed=121
-- payment_intent_id = NULL. O motorista foi chamado, aceitou e pôs-se a caminho
-- de uma corrida que nunca foi paga, com o cliente ainda no ecrã do MB Way.
--
-- CAUSA (duas, encadeadas):
--   1. O Flutter criava a corrida de IDA do pacote ida-e-volta sem passar
--      `p_payment_method`, caindo no DEFAULT 'cash'
--      (`_solicitarRoundtripOnline`, corrigido no mesmo commit).
--   2. `fn_tvde_dispatch_on_request` despacha na hora TODA a corrida 'cash' —
--      e "cash" era, na prática, "o cliente não disse nada".
--
-- Sem a correcção (2), qualquer caminho futuro que se esqueça do método volta a
-- pôr um motorista na estrada de graça. O gate tem de estar no servidor.
--
-- ⚠️ INTERACÇÃO com `20260804000000_PROPOSTA_tvde_roundtrip_tokens.sql`:
-- essa proposta redefine `tvde_create_roundtrip_credit` com 6 argumentos. Se
-- for aplicada DEPOIS desta, tem de levar a mesma linha do `payment_status`
-- que está aqui, senão a corrida de ida do pacote ONLINE deixa de ser
-- despachada de todo (é esta linha que substitui o despacho no INSERT).
-- =============================================================================

BEGIN;

-- ── 1. Despacho no INSERT: só dinheiro, e só dinheiro explícito ─────────────
-- Era `coalesce(new.payment_method,'cash') = 'cash'`. A coluna é NOT NULL
-- DEFAULT 'cash' (confirmado em information_schema), por isso o COALESCE nunca
-- fazia nada de útil — mas dizia "na dúvida, despacha". A dúvida passa a ser
-- resolvida ao contrário: na dúvida, NÃO despacha.
--
-- Cartão e MB Way passam a depender exclusivamente de `payment_status =
-- 'succeeded'` (trigger `tr_tvde_dispatch_on_paid`), que é quem sabe se o
-- dinheiro entrou.
CREATE OR REPLACE FUNCTION public.fn_tvde_dispatch_on_request()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
begin
  if new.status = 'solicitada' and new.payment_method = 'cash' then
    perform public.tvde_offer_to_next(new.id);
  else
    insert into public.tvde_ride_events (ride_id, status, actor, meta)
    values (new.id, new.status, 'system',
      jsonb_build_object('dispatch_deferred', true,
        'payment_method', new.payment_method,
        'reason', 'aguarda payment_status=succeeded'));
  end if;
  return new;
end; $function$;


-- ── 2. A válvula que substitui o despacho no INSERT (pacote ida-e-volta) ────
-- Com (1), a corrida de IDA do pacote — agora criada como 'card'/'mbway' — já
-- não é despachada no INSERT. Quem a liberta passa a ser a criação do vale:
-- o pacote está pago (o PaymentIntent dos €8 vive no VALE, não na corrida),
-- por isso marcar `payment_status='succeeded'` nesta corrida é a verdade — e
-- faz o `tr_tvde_dispatch_on_paid` despachá-la pelo mesmo caminho de qualquer
-- outra corrida paga online. Um só mecanismo.
--
-- Idempotente: o early-return do vale já existente não repete o UPDATE.
-- Só o corpo do UPDATE muda face à versão em produção.
CREATE OR REPLACE FUNCTION public.tvde_create_roundtrip_credit(
  p_client_id uuid, p_outbound_ride_id uuid, p_paid_cents integer,
  p_payment_intent_id text)
RETURNS public.tvde_roundtrip_credits
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE v_hours INT; v_credit public.tvde_roundtrip_credits;
BEGIN
  v_hours := COALESCE((public.get_setting('tvde_roundtrip_validity_hours') #>> '{}')::int, 6);
  SELECT * INTO v_credit FROM public.tvde_roundtrip_credits
    WHERE payment_intent_id = p_payment_intent_id LIMIT 1;
  IF FOUND THEN RETURN v_credit; END IF;
  INSERT INTO public.tvde_roundtrip_credits
    (client_id, outbound_ride_id, paid_cents, payment_intent_id, expires_at)
  VALUES
    (p_client_id, p_outbound_ride_id, p_paid_cents, p_payment_intent_id, now() + make_interval(hours => v_hours))
  RETURNING * INTO v_credit;
  IF p_outbound_ride_id IS NOT NULL THEN
    -- ⭐ 2026-08-13 (BUG 6): `payment_status` entra aqui. O pacote está pago,
    -- logo esta perna está paga — e é isto que dispara o despacho.
    UPDATE public.tvde_rides
       SET roundtrip_credit_id = v_credit.id,
           payment_status = 'succeeded',
           updated_at = now()
     WHERE id = p_outbound_ride_id;
  END IF;
  RETURN v_credit;
END; $function$;

COMMIT;
