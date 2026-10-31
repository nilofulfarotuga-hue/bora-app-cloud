-- 31/10/2026 — buraco no pagamento (achado gorjetas-taxa-2026-10-30 #5454, ainda aberto): create_order(jsonb) é
-- executável por qualquer conta autenticada e confiava em p_input->>'payment_already_confirmed', marcando o pedido
-- como PAGO sem pagamento nenhum. Autorizado pelo Danilo no chat da Claude.ai 31/10 19:53 ("autorizo de 1 a 8", item 5).
-- Agora o sinal só vale quando quem chama é o servidor (service_role: finalize-order-from-intent / stripe-webhook),
-- uma chamada interna sem JWT (cron) ou o admin. Para clientes o sinal é ignorado: o pedido nasce 'pending' até a
-- Stripe confirmar. Nada mais muda (preços, taxas, carteira, tokens iguais).
DO $mig$
DECLARE
  d text := pg_get_functiondef('public.create_order(jsonb)'::regprocedure);
  n text;
BEGIN
  n := replace(d,
    $a$v_payment_already_confirmed := COALESCE((p_input->>'payment_already_confirmed')::BOOLEAN, FALSE);$a$,
    $b$v_payment_already_confirmed := COALESCE((p_input->>'payment_already_confirmed')::BOOLEAN, FALSE)
    -- 31/10/2026: só o servidor (service_role), chamada interna sem JWT ou admin podem dizer "já está pago".
    AND (auth.role() IS NULL OR auth.role() = 'service_role' OR public.is_admin());$b$);
  IF n = d THEN
    RAISE EXCEPTION 'linha do payment_already_confirmed nao encontrada em create_order; nada foi mudado';
  END IF;
  EXECUTE n;
END
$mig$;
