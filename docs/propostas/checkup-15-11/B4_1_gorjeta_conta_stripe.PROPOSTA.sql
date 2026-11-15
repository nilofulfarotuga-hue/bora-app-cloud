-- PROPOSTA (checkup-geral-15-11, B4.1). ZONA DE DINHEIRO: so proposta; a Claude.ai aplica com o
-- autorizo do Danilo se o achar preciso. Nao muda valores cobrados nem pagos: so a COLUNA que diz em que
-- conta Stripe (pessoal/empresa) esta a gorjeta cobrada junto com o pedido.
-- Caso: pedido 56fa8623 (08/11) cobrado na conta EMPRESA com a gorjeta de 2,00 EUR no mesmo PI; a linha em
-- tips nasceu stripe_account='pessoal' (DEFAULT da coluna) e foi acertada a mao a 08/11 (e2e 7084).
-- Causa (SELECT 15/11): _orders_gorjeta_checkout_na_criacao nao grava stripe_account nos 2 INSERT e
-- gorjeta_checkout_mbway_pi so grava o PI. Hoje 0 gorjetas com conta diferente da do pedido desde 02/11.
-- Copia das funcoes antigas em bkp_funcoes_20261115 (a mesma tabela da proposta B1).
create table if not exists public.bkp_funcoes_20261115 (nome text primary key, definicao text not null, guardado_em timestamptz not null default now());
revoke all on public.bkp_funcoes_20261115 from public, anon, authenticated;
alter table public.bkp_funcoes_20261115 enable row level security;
insert into public.bkp_funcoes_20261115 (nome, definicao) values
  ('_orders_gorjeta_checkout_na_criacao', pg_get_functiondef('public._orders_gorjeta_checkout_na_criacao'::regproc)),
  ('gorjeta_checkout_mbway_pi', pg_get_functiondef('public.gorjeta_checkout_mbway_pi'::regproc))
on conflict (nome) do nothing;

CREATE OR REPLACE FUNCTION public._orders_gorjeta_checkout_na_criacao()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  c_sem   constant uuid := '00000000-0000-0000-0000-000000000000';
  v_marca public.gorjeta_checkout_pendente%ROWTYPE;
  v_cents integer;
  v_prest uuid;
  v_n     integer := 0;
BEGIN
  IF NEW.user_id IS NULL THEN RETURN NEW; END IF;
  v_prest := COALESCE(NULLIF(NEW.assigned_driver_id, '')::uuid, c_sem);

  SELECT * INTO v_marca FROM public.gorjeta_checkout_pendente
   WHERE user_id = NEW.user_id AND usado_em IS NULL
   FOR UPDATE;

  IF NEW.payment_intent_id IS NOT NULL AND auth.uid() IS NULL
     AND COALESCE(NEW.payment_status, '') = 'paid' THEN
    SELECT NULLIF(d.payload->>'gorjeta_checkout_cents', '')::integer INTO v_cents
      FROM public.payment_drafts d
     WHERE d.payment_intent_id = NEW.payment_intent_id AND d.user_id = NEW.user_id
     ORDER BY d.created_at DESC
     LIMIT 1;
    IF COALESCE(v_cents, 0) >= 50 THEN
      INSERT INTO public.tips (target, order_id, client_user_id, provider_user_id, amount_cents,
                               method, moment, status, stripe_payment_intent_id, paid_at, cobrada_junto, stripe_account)
      VALUES ('order', NEW.id, NEW.user_id, v_prest, v_cents,
              'card', 'checkout', 'succeeded', NEW.payment_intent_id, now(), true,
              COALESCE(NULLIF(NEW.stripe_account, ''), 'pessoal'))  -- B4.1: a conta do pedido
      ON CONFLICT DO NOTHING;
      GET DIAGNOSTICS v_n = ROW_COUNT;
    END IF;
  ELSIF NEW.payment_method = 'mbway' AND COALESCE(NEW.payment_status, 'pending') = 'pending'
        AND NEW.service_type IN ('restaurant', 'storeShopping', 'takeaway')
        AND v_marca.user_id IS NOT NULL AND v_marca.expira_em > now()
        AND public._gorjeta_checkout_ligada()
        AND v_marca.tip_cents BETWEEN 50 AND COALESCE((public.get_setting('tip_max_cents') #>> '{}')::integer, 5000) THEN
    INSERT INTO public.tips (target, order_id, client_user_id, provider_user_id, amount_cents,
                             method, moment, status, cobrada_junto, stripe_account)
    VALUES ('order', NEW.id, NEW.user_id, v_prest, v_marca.tip_cents,
            'mbway', 'checkout', 'pending', true,
            COALESCE(NULLIF(NEW.stripe_account, ''), 'pessoal'))  -- B4.1
    ON CONFLICT DO NOTHING;
    GET DIAGNOSTICS v_n = ROW_COUNT;
    IF v_n > 0 THEN
      UPDATE public.gorjeta_checkout_pendente
         SET usado_em = now(), order_id = NEW.id, gorjeta_aplicada = true
       WHERE user_id = NEW.user_id;
    END IF;
  END IF;
  RETURN NEW;
EXCEPTION WHEN OTHERS THEN
  RAISE WARNING '_orders_gorjeta_checkout_na_criacao: pedido % — %', NEW.id, SQLERRM;
  BEGIN
    INSERT INTO public.e2e_log (fluxo, passo, estado, detalhe)
    VALUES ('gorjetas-taxa-2026-10-30', 'gorjeta_na_criacao', 'erro',
            left(format('pedido %s: %s', NEW.id, SQLERRM), 500));
  EXCEPTION WHEN OTHERS THEN NULL;
  END;
  RETURN NEW;
END $function$;

CREATE OR REPLACE FUNCTION public.gorjeta_checkout_mbway_pi(p_order_id text, p_payment_intent text)
 RETURNS boolean
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
BEGIN
  IF p_payment_intent IS NULL OR p_payment_intent = '' THEN RETURN false; END IF;
  -- B4.1 (checkup-15-11): a gorjeta fica com a MESMA conta Stripe do pedido (o PI e o mesmo).
  UPDATE public.tips t SET stripe_payment_intent_id = p_payment_intent,
         stripe_account = COALESCE(NULLIF(o.stripe_account, ''), t.stripe_account)
    FROM public.orders o
   WHERE o.id = p_order_id AND t.order_id = p_order_id AND t.cobrada_junto AND t.method = 'mbway'
     AND t.status IN ('pending', 'requires_action');
  RETURN FOUND;
END $function$;
