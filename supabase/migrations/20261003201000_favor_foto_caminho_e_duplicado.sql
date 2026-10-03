-- 2026-10-03 — FAVORES: foto não aparecia ao estafeta + Favor duplicado.
--
-- (a) FOTO. O bucket `order-photos` é PRIVADO (e fica privado: fotos de
-- clientes). A app gravava em orders.errand_request_photo_url o link
-- /object/public/... (404 num bucket privado). A app do estafeta já assina o
-- link (PrivateBucketImage), mas a política de leitura só deixava ler a quem
-- participa no pedido quando o 2.º nível da pasta é o id do pedido — e a foto
-- do Favor é enviada ANTES de o pedido existir, para `{cliente}/errand_request_*`.
-- O estafeta não conseguia assinar. Correção:
--   1. política nova: lê a foto do Favor o estafeta atribuído (ou com a oferta)
--      ao pedido que a referencia;
--   2. gatilho: qualquer link de order-photos passa a ser gravado como CAMINHO
--      `order-photos/<pasta>/<ficheiro>` (cobre create_order, webhook e versões
--      antigas da app);
--   3. linhas antigas convertidas para caminho, com backup.
--
-- (b) DUPLICADO. Mesmo Favor 2x em 15 s (c20f61b8 / 1a2c3afe). Guarda no
-- servidor: recusa um Favor do mesmo cliente, mesma morada e mesmo total dentro
-- de `errand_duplicate_window_seconds` (60). Só pedidos criados pelo próprio
-- cliente (auth.uid() = user_id): o webhook do cartão (service_role) não é
-- travado, para nunca ficar dinheiro cobrado sem pedido.

-- ── (a1) política de leitura da foto do Favor ──────────────────────────────
CREATE POLICY order_photos_select_errand_driver ON storage.objects
  FOR SELECT TO authenticated
  USING (
    bucket_id = 'order-photos'
    AND name LIKE '%errand_request_%'
    AND EXISTS (
      SELECT 1 FROM public.orders o
      WHERE o.service_type = 'errand'
        AND o.errand_request_photo_url IN (
              'order-photos/' || objects.name,
              objects.name,
              'https://ojykpzwqrtusfeakzrna.supabase.co/storage/v1/object/public/order-photos/' || objects.name)
        AND (o.assigned_driver_id = (auth.uid())::text
             OR o.current_driver_offer_id = (auth.uid())::text)
    )
  );

-- ── (a2) gravar caminho em vez de link ─────────────────────────────────────
CREATE OR REPLACE FUNCTION public.fn_orders_errand_photo_caminho()
RETURNS trigger LANGUAGE plpgsql SET search_path TO 'public' AS $f$
BEGIN
  IF NEW.errand_request_photo_url IS NOT NULL
     AND NEW.errand_request_photo_url ~ '^https?://[^/]+/storage/v1/object/(public|sign|authenticated)/order-photos/' THEN
    NEW.errand_request_photo_url := regexp_replace(
      NEW.errand_request_photo_url,
      '^https?://[^/]+/storage/v1/object/(public|sign|authenticated)/(order-photos/[^?]+).*$',
      '\2');
  END IF;
  RETURN NEW;
END $f$;

CREATE OR REPLACE TRIGGER trg_orders_errand_photo_caminho
  BEFORE INSERT OR UPDATE OF errand_request_photo_url ON public.orders
  FOR EACH ROW EXECUTE FUNCTION public.fn_orders_errand_photo_caminho();

-- ── (a3) linhas antigas → caminho (backup antes) ───────────────────────────
CREATE TABLE IF NOT EXISTS public.bkp_orders_errand_photo_20261003 (
  id text PRIMARY KEY, errand_request_photo_url text, guardado_em timestamptz DEFAULT now());
ALTER TABLE public.bkp_orders_errand_photo_20261003 ENABLE ROW LEVEL SECURITY;
INSERT INTO public.bkp_orders_errand_photo_20261003(id, errand_request_photo_url)
SELECT id, errand_request_photo_url FROM public.orders
WHERE errand_request_photo_url ~ '^https?://[^/]+/storage/v1/object/(public|sign|authenticated)/order-photos/'
ON CONFLICT (id) DO NOTHING;
-- O gatilho de cima faz a conversão.
UPDATE public.orders SET errand_request_photo_url = errand_request_photo_url
WHERE errand_request_photo_url ~ '^https?://[^/]+/storage/v1/object/(public|sign|authenticated)/order-photos/';

-- ── (b) Favor duplicado ────────────────────────────────────────────────────
INSERT INTO public.platform_settings(key, value, category, description)
VALUES ('errand_duplicate_window_seconds', '60'::jsonb, 'errand',
        'Segundos em que o servidor recusa um Favor IGUAL (mesmo cliente, mesma morada e mesmo total) — evita pedido duplicado por toque duplo. 0 = desliga.')
ON CONFLICT (key) DO NOTHING;

CREATE OR REPLACE FUNCTION public.fn_orders_errand_duplicado()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $f$
DECLARE
  v_janela int := COALESCE((public.get_setting('errand_duplicate_window_seconds') #>> '{}')::int, 60);
  v_outro text;
BEGIN
  IF NEW.service_type IS DISTINCT FROM 'errand' OR v_janela <= 0
     OR auth.uid() IS NULL OR auth.uid() IS DISTINCT FROM NEW.user_id THEN
    RETURN NEW;
  END IF;
  SELECT o.id INTO v_outro FROM public.orders o
  WHERE o.user_id = NEW.user_id
    AND o.service_type = 'errand'
    AND o.id IS DISTINCT FROM NEW.id
    AND COALESCE(o.dropoff_address, '') = COALESCE(NEW.dropoff_address, '')
    -- total/customer_total são colunas geradas de `price` (vazias num BEFORE).
    AND o.price IS NOT DISTINCT FROM NEW.price
    AND o.created_at > now() - make_interval(secs => v_janela)
    AND o.status NOT IN ('cancelled', 'rejected')
  LIMIT 1;
  IF v_outro IS NOT NULL THEN
    RAISE EXCEPTION 'duplicate_errand: já há um Favor igual (%) criado há menos de % s', v_outro, v_janela
      USING ERRCODE = 'P0001';
  END IF;
  RETURN NEW;
END $f$;

CREATE OR REPLACE TRIGGER trg_orders_errand_duplicado
  BEFORE INSERT ON public.orders
  FOR EACH ROW EXECUTE FUNCTION public.fn_orders_errand_duplicado();
