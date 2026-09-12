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


-- ── 3. DESARMAR A MINA — `tvde_create_roundtrip_credit_cash` com tokens ─────
-- O Flutter (`TvdeStore.createRoundtripCreditCash`) já envia SEMPRE
-- `p_tokens_to_apply`, mesmo quando 0. Em produção a função só aceita 1
-- argumento -> o pacote ida-e-volta em DINHEIRO parte inteiro assim que essas
-- builds saírem. Esta é a peça que faltava (a `20260804000000_PROPOSTA_tvde_
-- roundtrip_tokens.sql` avisa disto no cabeçalho e deixou-a por escrever).
--
-- ⚠️ TEM de ser DROP + CREATE, nunca CREATE OR REPLACE.
-- `CREATE OR REPLACE FUNCTION f(uuid, integer DEFAULT 0)` NÃO substitui
-- `f(uuid)` — cria um SEGUNDO `f`. A partir daí uma chamada de 1 argumento
-- casa com os dois e o Postgres devolve "function is not unique" (42725 /
-- PGRST203), partindo exactamente as builds já instaladas que se queria
-- proteger. O `DEFAULT 0` é o que as mantém a funcionar: quem chama com 1
-- argumento resolve para esta função com o default.
--
-- DROP sem IF EXISTS de propósito: se a assinatura antiga não estiver lá como
-- esperado, a transacção inteira aborta em vez de deixar meio-estado.
DROP FUNCTION public.tvde_create_roundtrip_credit_cash(uuid);

CREATE FUNCTION public.tvde_create_roundtrip_credit_cash(
  p_outbound_ride_id uuid,
  p_tokens_to_apply integer DEFAULT 0)
RETURNS public.tvde_roundtrip_credits
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_uid   UUID := auth.uid();
  v_hours INT;
  v_price INT;
  v_credit public.tvde_roundtrip_credits;
  v_ride   public.tvde_rides;
  v_tokens INT;
  v_token_value_x100 INT;
  v_max_pct INT;
  v_max_discount INT;
  v_discount INT := 0;
BEGIN
  IF v_uid IS NULL THEN RAISE EXCEPTION 'not_authenticated'; END IF;

  SELECT * INTO v_ride FROM public.tvde_rides WHERE id = p_outbound_ride_id;
  IF NOT FOUND THEN RAISE EXCEPTION 'outbound_ride_not_found'; END IF;
  IF v_ride.client_id <> v_uid THEN RAISE EXCEPTION 'not_ride_owner'; END IF;
  IF COALESCE(v_ride.is_return_leg, false) THEN RAISE EXCEPTION 'return_leg_cannot_anchor_credit'; END IF;

  v_hours := COALESCE((public.get_setting('tvde_roundtrip_validity_hours') #>> '{}')::int, 6);
  v_price := public.tvde_roundtrip_price_for_km(COALESCE(v_ride.est_distance_km, 0));

  -- Idempotência INTACTA: vale em dinheiro já criado para esta ida (o Flutter
  -- tenta 3x) devolve-se tal e qual, SEM reaplicar desconto nem reescrever
  -- nada. Tem de continuar a ser a primeira coisa depois do preço.
  SELECT * INTO v_credit FROM public.tvde_roundtrip_credits
    WHERE outbound_ride_id = p_outbound_ride_id AND payment_intent_id IS NULL
    LIMIT 1;
  IF FOUND THEN RETURN v_credit; END IF;

  v_tokens := GREATEST(0, COALESCE(p_tokens_to_apply, 0));

  -- ANTI-DUPLO: se a corrida de ida já levou desconto de tokens na sua própria
  -- tarifa (`tvde_request_ride` com p_tokens_to_apply > 0), NÃO se desconta
  -- outra vez no pacote — seriam os mesmos tokens a pagar duas coisas.
  -- Hoje `_solicitarRoundtripCash` não passa tokens à ida (só ao vale), mas o
  -- guard fica: é barato e o dia em que alguém mudar o ecrã não dá prejuízo.
  IF v_tokens > 0 AND COALESCE(v_ride.tokens_applied_count, 0) > 0 THEN
    INSERT INTO public.tvde_ride_events (ride_id, status, actor, meta)
      VALUES (p_outbound_ride_id, v_ride.status, 'system',
        jsonb_build_object('tokens_skipped_on_credit', true,
          'reason', 'ida ja tinha desconto de tokens',
          'tokens_requested', v_tokens,
          'tokens_already_on_ride', v_ride.tokens_applied_count));
    v_tokens := 0;
  END IF;

  -- Mesma fórmula do irmão ONLINE (`tvde-plan-payment`, accao create_roundtrip):
  -- valor por token de `token_value_cents_x100` e tecto `token_payment_max_pct`
  -- sobre o preço FINAL do pacote (já com o desconto ida-e-volta embutido por
  -- `tvde_roundtrip_price_for_km`), nunca sobre duas corridas separadas.
  IF v_tokens > 0 AND v_price > 0 THEN
    v_token_value_x100 := COALESCE((public.get_setting('token_value_cents_x100') #>> '{}')::int, 50);
    v_max_pct          := COALESCE((public.get_setting('token_payment_max_pct') #>> '{}')::int, 50);
    v_max_discount     := GREATEST(0, (v_price * v_max_pct) / 100);
    v_discount         := LEAST((v_tokens * v_token_value_x100) / 100, v_max_discount);
    v_price            := v_price - v_discount;
  END IF;

  -- `paid_cents` LÍQUIDO: é o que o cliente entrega em mão ao motorista.
  -- Mesma regra do `est_fare_cents` (ver secção 4 do relatório) — o valor
  -- gravado já é o final, ninguém pode voltar a subtrair o desconto.
  INSERT INTO public.tvde_roundtrip_credits
    (client_id, outbound_ride_id, paid_cents, payment_intent_id, expires_at)
  VALUES
    (v_uid, p_outbound_ride_id, v_price, NULL, now() + make_interval(hours => v_hours))
  RETURNING * INTO v_credit;

  -- Os tokens ficam registados na IDA (o vale não tem colunas para eles), o
  -- que também os põe no caminho do consumidor ÚNICO — o trigger
  -- `tr_tvde_consume_tokens` da migration 20260813200000, que os desconta
  -- quando a corrida chega a 'finalizada'. Sem segundo consumidor, sem duplo.
  UPDATE public.tvde_rides
     SET roundtrip_credit_id = v_credit.id,
         tokens_applied_count = CASE WHEN v_discount > 0 THEN v_tokens ELSE tokens_applied_count END,
         tokens_applied_value_cents = CASE WHEN v_discount > 0 THEN v_discount ELSE tokens_applied_value_cents END,
         updated_at = now()
   WHERE id = p_outbound_ride_id;

  RETURN v_credit;
END; $function$;

-- O DROP levou os grants com ele. A antiga tinha EXECUTE para PUBLIC/anon —
-- não se repõe: a função é SECURITY DEFINER, mexe em dinheiro, e rebenta com
-- `not_authenticated` para quem não tem sessão. Nada no app deixa de funcionar
-- (chama sempre autenticado).
REVOKE ALL ON FUNCTION public.tvde_create_roundtrip_credit_cash(uuid, integer) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.tvde_create_roundtrip_credit_cash(uuid, integer) TO authenticated;
GRANT EXECUTE ON FUNCTION public.tvde_create_roundtrip_credit_cash(uuid, integer) TO service_role;

COMMIT;
