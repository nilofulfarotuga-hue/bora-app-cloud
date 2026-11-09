-- ============================================================================
-- Missão m1-dinheiro-favores-2026-11-08 — Bloco 4 (aplicar DEPOIS do 02; nome final:
-- 20261108210200_m1_nif_estafeta_e_recibo_cliente)
-- Regra do Danilo (08/11 18:59): "Não pode esquecer do NIF... quando fazer qualquer pedido, já
-- ir a fatura pro e-mail da pessoa."
--   a) o estafeta em loja NÃO-parceira vê o NIF que o cliente pediu (ou o NIF da Bora);
--   c) recibo por email em todo o pedido entregue (entrega, mercado, Favor), uma vez só;
--   d) painel: estado do recibo e "Reenviar recibo".
-- Não muda valores: o recibo só lê o que o pedido já tem.
-- ============================================================================

-- a) NIF para o estafeta ---------------------------------------------------------------------
-- Só o estafeta atribuído (ou admin) e só em loja não-parceira (na parceira a loja trata da
-- fatura: PartnerFaturaLinha). Sem pedido de fatura → talão com o NIF da Bora (regra 03/11 e 08/11).
CREATE OR REPLACE FUNCTION public.driver_order_invoice_nif(p_order_id text)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path TO 'public' AS $$
DECLARE
  v_uid  uuid := auth.uid();
  o      record;
  r      record;
  v_nif  text;
  c_bora constant text := '519686233';  -- Danilo Fulfaro da Silva - Unipessoal Lda
BEGIN
  IF v_uid IS NULL THEN RETURN jsonb_build_object('ok', false, 'error', 'auth_required'); END IF;
  SELECT id, user_id, assigned_driver_id, current_driver_offer_id, is_partner_store, service_type
    INTO o FROM public.orders WHERE id = p_order_id;
  IF NOT FOUND THEN RETURN jsonb_build_object('ok', false, 'error', 'pedido_nao_encontrado'); END IF;
  IF NOT COALESCE((public.is_admin() OR o.assigned_driver_id = v_uid::text OR o.current_driver_offer_id = v_uid::text
          OR o.assigned_driver_id IN (SELECT d.id::text FROM public.drivers d WHERE d.user_id = v_uid)), false) THEN  -- NULL nunca deixa passar
    RETURN jsonb_build_object('ok', false, 'error', 'nao_e_o_teu_pedido');
  END IF;
  IF COALESCE(o.is_partner_store, false) THEN
    RETURN jsonb_build_object('ok', true, 'mostrar', false, 'loja_parceira', true);
  END IF;
  SELECT i.nif, i.nome INTO r FROM public.order_invoice_requests i WHERE i.order_id = o.id;
  IF FOUND THEN
    v_nif := NULLIF(btrim(COALESCE(r.nif, '')), '');
    IF v_nif IS NULL THEN
      SELECT NULLIF(btrim(COALESCE(b.nif, '')), '') INTO v_nif FROM public.client_billing_profile b WHERE b.user_id = o.user_id;
    END IF;
  END IF;
  IF v_nif IS NOT NULL THEN
    RETURN jsonb_build_object('ok', true, 'mostrar', true, 'pediu_fatura', true, 'nif', v_nif,
      'nome', NULLIF(btrim(COALESCE(r.nome, '')), ''),
      'texto', 'Cliente pediu fatura com NIF ' || v_nif || ': pede ao balcão com este NIF');
  END IF;
  RETURN jsonb_build_object('ok', true, 'mostrar', true, 'pediu_fatura', false, 'nif', c_bora,
    'texto', 'Sem NIF do cliente → talão com o NIF da Bora ' || c_bora);
END $$;
REVOKE ALL ON FUNCTION public.driver_order_invoice_nif(text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.driver_order_invoice_nif(text) TO authenticated;

-- c) Recibo por email ------------------------------------------------------------------------
INSERT INTO public.platform_settings (key, value, description, category) VALUES
  ('recibo_cliente_email_enabled', 'true'::jsonb,
   'Recibo por email ao cliente em todo o pedido entregue (entrega, mercado, Favor). true = liga; false = desliga sem apagar nada', 'recibos')
ON CONFLICT (key) DO NOTHING;

CREATE TABLE IF NOT EXISTS public.recibos_clientes (
  order_id      text PRIMARY KEY,
  user_id       uuid,
  email         text,
  estado        text NOT NULL DEFAULT 'pendente'
                CHECK (estado IN ('pendente','enviado','falhou','sem_email','desligado')),
  detalhe       text,
  resend_id     text,
  storage_path  text,
  tentativas    integer NOT NULL DEFAULT 0,
  enviado_em    timestamptz,
  criado_em     timestamptz NOT NULL DEFAULT now(),
  atualizado_em timestamptz NOT NULL DEFAULT now()
);
ALTER TABLE public.recibos_clientes ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.recibos_clientes FROM anon;
GRANT SELECT ON public.recibos_clientes TO authenticated;
DROP POLICY IF EXISTS recibos_clientes_ler ON public.recibos_clientes;
CREATE POLICY recibos_clientes_ler ON public.recibos_clientes FOR SELECT TO authenticated
  USING (user_id = auth.uid() OR public.is_admin());

INSERT INTO storage.buckets (id, name, public) VALUES ('recibos-clientes', 'recibos-clientes', false)
ON CONFLICT (id) DO NOTHING;
DROP POLICY IF EXISTS recibos_clientes_admin_ler ON storage.objects;
CREATE POLICY recibos_clientes_admin_ler ON storage.objects FOR SELECT TO authenticated
  USING (bucket_id = 'recibos-clientes' AND public.is_admin());

-- Os números do recibo (a Edge recibo-pedido-cliente só desenha). Itens com o preço que o
-- cliente viu na app; total pago = total do pedido + gorjeta − saldo − tokens − crédito.
CREATE OR REPLACE FUNCTION public._recibo_pedido(p_order_id text)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path TO 'public' AS $$
DECLARE
  o        record;
  v_itens  jsonb := '[]'::jsonb;
  v_linhas jsonb := '[]'::jsonb;
  v_desc   jsonb := '[]'::jsonb;
  v_total  integer;
  v_gorj   integer;
  v_d      integer;
  v_nif    text;
  v_nome   text;
  v_fav    boolean;
BEGIN
  SELECT * INTO o FROM public.orders WHERE id = p_order_id;
  IF NOT FOUND OR o.status IS DISTINCT FROM 'delivered' THEN RETURN NULL; END IF;
  v_fav := o.service_type = 'errand';

  IF v_fav THEN
    IF COALESCE(o.final_purchase_value, 0) > 0 THEN
      v_itens := jsonb_build_array(jsonb_build_object('nome', 'Compra: ' || COALESCE(NULLIF(btrim(o.errand_description), ''), 'Favor'),
                                                      'qtd', 1, 'valor_cents', ROUND(o.final_purchase_value * 100)::int));
    END IF;
    v_linhas := v_linhas || jsonb_build_object('nome', 'Serviço do Favor (deslocação e entrega)',
                                               'valor_cents', ROUND(COALESCE(o.delivery_fee, 0) * 100)::int);
  ELSE
    SELECT COALESCE(jsonb_agg(jsonb_build_object(
             'nome', COALESCE(i->>'name', 'Artigo'),
             'qtd', COALESCE(NULLIF(i->>'quantity', '')::numeric, 1),
             'valor_cents', ROUND(COALESCE(NULLIF(i->>'price', '')::numeric, 0) * 100)::int)), '[]'::jsonb)
      INTO v_itens
      FROM jsonb_array_elements(CASE WHEN jsonb_typeof(o.items) = 'array' THEN o.items ELSE '[]'::jsonb END) i;
    IF COALESCE(o.delivery_fee, 0) > 0 THEN
      v_linhas := v_linhas || jsonb_build_object('nome', 'Entrega', 'valor_cents', ROUND(o.delivery_fee * 100)::int);
    END IF;
    IF COALESCE(o.service_fee, 0) > 0 THEN
      v_linhas := v_linhas || jsonb_build_object('nome', 'Taxa de serviço', 'valor_cents', ROUND(o.service_fee * 100)::int);
    END IF;
    IF COALESCE(o.bag_fee, 0) > 0 THEN
      v_linhas := v_linhas || jsonb_build_object('nome', 'Saco', 'valor_cents', ROUND(o.bag_fee * 100)::int);
    END IF;
    IF COALESCE(o.small_order_fee, 0) > 0 THEN
      v_linhas := v_linhas || jsonb_build_object('nome', 'Pedido pequeno', 'valor_cents', ROUND(o.small_order_fee * 100)::int);
    END IF;
    IF COALESCE(o.helper_fee_eur, 0) > 0 THEN
      v_linhas := v_linhas || jsonb_build_object('nome', 'Ajudante', 'valor_cents', ROUND(o.helper_fee_eur * 100)::int);
    END IF;
  END IF;

  v_total := ROUND(COALESCE(CASE WHEN COALESCE(o.is_purchase_finalized, false) THEN o.final_total END,
                            o.customer_total, o.price, o.total, 0) * 100)::int;
  v_gorj := COALESCE(o.tip_amount_cents, 0);
  IF COALESCE(o.wallet_applied_cents, 0) > 0 THEN
    v_desc := v_desc || jsonb_build_object('nome', 'Saldo da carteira', 'valor_cents', o.wallet_applied_cents);
  END IF;
  IF COALESCE(o.tokens_applied_value_cents, 0) > 0 THEN
    v_desc := v_desc || jsonb_build_object('nome', 'Tokens Bora', 'valor_cents', o.tokens_applied_value_cents);
  END IF;
  IF COALESCE(o.menu_credit_applied_cents, 0) > 0 THEN
    v_desc := v_desc || jsonb_build_object('nome', 'Crédito', 'valor_cents', o.menu_credit_applied_cents);
  END IF;
  v_d := COALESCE(o.wallet_applied_cents, 0) + COALESCE(o.tokens_applied_value_cents, 0) + COALESCE(o.menu_credit_applied_cents, 0);

  SELECT NULLIF(btrim(COALESCE(i.nif, '')), ''), NULLIF(btrim(COALESCE(i.nome, '')), '') INTO v_nif, v_nome
    FROM public.order_invoice_requests i WHERE i.order_id = o.id;

  RETURN jsonb_build_object(
    'pedido_id', o.id,
    'numero', upper(left(replace(o.id, '-', ''), 8)),
    'data', COALESCE(o.delivered_at, o.created_at),
    'loja', COALESCE(o.vendor_name, CASE WHEN v_fav THEN 'Favor Bora' ELSE 'Bora' END),
    'tipo', o.service_type,
    'itens', v_itens,
    'linhas', v_linhas,
    'total_pedido_cents', v_total,
    'gorjeta_cents', v_gorj,
    'descontos', v_desc,
    'total_pago_cents', GREATEST(0, v_total + v_gorj - v_d),
    'metodo', o.payment_method,
    'nif', v_nif,
    'nome_fatura', v_nome,
    'user_id', o.user_id,
    'teste', COALESCE(o.is_test_order, false));
END $$;
REVOKE ALL ON FUNCTION public._recibo_pedido(text) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public._recibo_pedido(text) TO service_role;

-- Pede o envio (uma vez por pedido; p_forcar=true só pelo painel). Interno.
CREATE OR REPLACE FUNCTION public._recibo_pedir_envio(p_order_id text, p_forcar boolean)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public', 'net' AS $$
DECLARE v_on boolean; v_url text; v_key text; v_user uuid; v_novo boolean := false;
BEGIN
  SELECT COALESCE((SELECT (value #>> '{}')::boolean FROM public.platform_settings WHERE key = 'recibo_cliente_email_enabled'), false)
    INTO v_on;
  SELECT user_id INTO v_user FROM public.orders WHERE id = p_order_id;
  IF NOT v_on AND NOT p_forcar THEN RETURN jsonb_build_object('ok', false, 'error', 'desligado'); END IF;
  INSERT INTO public.recibos_clientes (order_id, user_id) VALUES (p_order_id, v_user)
  ON CONFLICT (order_id) DO NOTHING
  RETURNING true INTO v_novo;
  IF NOT COALESCE(v_novo, false) AND NOT p_forcar THEN
    RETURN jsonb_build_object('ok', true, 'ja_pedido', true);
  END IF;
  SELECT decrypted_secret INTO v_url FROM vault.decrypted_secrets WHERE name = 'project_url';
  SELECT decrypted_secret INTO v_key FROM vault.decrypted_secrets WHERE name = 'service_role_key';
  IF v_url IS NULL OR v_key IS NULL THEN RETURN jsonb_build_object('ok', false, 'error', 'servidor_sem_chave'); END IF;
  PERFORM net.http_post(url := v_url || '/functions/v1/recibo-pedido-cliente',
    headers := jsonb_build_object('Authorization', 'Bearer ' || v_key, 'Content-Type', 'application/json'),
    body := jsonb_build_object('order_id', p_order_id, 'force', p_forcar),
    timeout_milliseconds := 30000);
  RETURN jsonb_build_object('ok', true);
END $$;
REVOKE ALL ON FUNCTION public._recibo_pedir_envio(text, boolean) FROM PUBLIC, anon, authenticated;

-- Gatilho: ao passar a 'delivered' (PIN, "entregue sem código", Favor, mercado). Nunca parte a entrega.
CREATE OR REPLACE FUNCTION public.fn_recibo_cliente_on_delivered()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $$
BEGIN
  IF NEW.status = 'delivered' AND OLD.status IS DISTINCT FROM 'delivered'
     AND NOT COALESCE(NEW.is_test_order, false) THEN
    BEGIN
      PERFORM public._recibo_pedir_envio(NEW.id, false);
    EXCEPTION WHEN OTHERS THEN RAISE WARNING 'recibo cliente %: %', NEW.id, SQLERRM;
    END;
  END IF;
  RETURN NEW;
END $$;
DROP TRIGGER IF EXISTS zzzzz_recibo_cliente_on_delivered ON public.orders;
CREATE TRIGGER zzzzz_recibo_cliente_on_delivered
  AFTER UPDATE OF status ON public.orders
  FOR EACH ROW EXECUTE FUNCTION public.fn_recibo_cliente_on_delivered();

-- d) Painel ----------------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.admin_recibo_pedido(p_order_id text)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path TO 'public' AS $$
DECLARE r public.recibos_clientes;
BEGIN
  IF NOT public.is_admin() THEN RAISE EXCEPTION 'forbidden' USING ERRCODE = '42501'; END IF;
  SELECT * INTO r FROM public.recibos_clientes WHERE order_id = p_order_id;
  IF r.order_id IS NULL THEN RETURN jsonb_build_object('ok', true, 'existe', false); END IF;
  RETURN jsonb_build_object('ok', true, 'existe', true, 'estado', r.estado, 'email', r.email,
    'detalhe', r.detalhe, 'enviado_em', r.enviado_em, 'tentativas', r.tentativas,
    'storage_path', r.storage_path, 'bucket', 'recibos-clientes');
END $$;
REVOKE ALL ON FUNCTION public.admin_recibo_pedido(text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.admin_recibo_pedido(text) TO authenticated;

CREATE OR REPLACE FUNCTION public.admin_recibo_reenviar(p_order_id text)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $$
DECLARE r jsonb; v_status text;
BEGIN
  IF NOT public.is_admin() THEN RAISE EXCEPTION 'forbidden' USING ERRCODE = '42501'; END IF;
  SELECT status INTO v_status FROM public.orders WHERE id = p_order_id;
  IF v_status IS DISTINCT FROM 'delivered' THEN
    RETURN jsonb_build_object('ok', false, 'error', 'pedido_nao_entregue', 'status', v_status);
  END IF;
  r := public._recibo_pedir_envio(p_order_id, true);
  INSERT INTO public.admin_audit_log (admin_id, admin_email, action, entity_type, entity_id_text, details)
  VALUES (auth.uid(), auth.jwt()->>'email', 'recibo_cliente_reenviar', 'order', p_order_id, r);
  RETURN r;
END $$;
REVOKE ALL ON FUNCTION public.admin_recibo_reenviar(text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.admin_recibo_reenviar(text) TO authenticated;
