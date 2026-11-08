-- ============================================================================
-- Missão m1, ADENDO 1 (pedido do Danilo 08/11/2026 20:39): "toda foto de talão que o estafeta tira
-- tem de ficar guardada num sítio certo, para sempre (papel fiscal, 10 anos), e nunca se pode perder."
-- Aplicar DEPOIS do 03 (usa order_invoice_requests). Nome final: 20261108220000_m1_taloes_guardados.
--
-- Encontrado a 08/11: a Edge upload-receipt grava sempre receipts/<order_id>.jpg com upsert:true e a
-- chave de servidor → a 2.ª foto do mesmo pedido APAGA a 1.ª sem aviso. Daqui para a frente cada foto
-- tem o seu ficheiro (receipts/AAAA/MM/<order_id>/<foto_id>.jpg, nunca substituído) e uma linha aqui.
-- As 46 fotos antigas (<order_id>.jpg / receipts/<order_id>.jpg) continuam a ler-se como estão.
-- Nada se apaga: sem DELETE nem UPDATE para utilizadores; só o servidor escreve.
-- ============================================================================

CREATE TABLE IF NOT EXISTS public.order_receipt_fotos (
  id              uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  order_id        text NOT NULL,
  bucket          text NOT NULL DEFAULT 'receipts',
  path            text NOT NULL UNIQUE,
  foto_id         text,
  total_cents     integer,
  driver_uid      uuid,
  tirada_em       timestamptz,
  recebida_em     timestamptz NOT NULL DEFAULT now(),
  tamanho_bytes   bigint,
  origem          text NOT NULL DEFAULT 'upload-receipt' CHECK (origem IN ('upload-receipt','antigo')),
  copia_em        timestamptz,          -- 2.ª cópia (Google Drive da Bora) feita
  copia_destino   text,                 -- id/caminho do ficheiro na cópia
  copia_erro      text
);
CREATE INDEX IF NOT EXISTS order_receipt_fotos_pedido ON public.order_receipt_fotos (order_id, recebida_em);
CREATE INDEX IF NOT EXISTS order_receipt_fotos_mes ON public.order_receipt_fotos (recebida_em);
CREATE INDEX IF NOT EXISTS order_receipt_fotos_sem_copia ON public.order_receipt_fotos (recebida_em) WHERE copia_em IS NULL;
ALTER TABLE public.order_receipt_fotos ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.order_receipt_fotos FROM anon;
GRANT SELECT ON public.order_receipt_fotos TO authenticated;
DROP POLICY IF EXISTS order_receipt_fotos_ler ON public.order_receipt_fotos;
CREATE POLICY order_receipt_fotos_ler ON public.order_receipt_fotos FOR SELECT TO authenticated
  USING (driver_uid = auth.uid() OR public.is_admin());

-- As fotos antigas entram no registo tal como estão (uma por pedido; o ficheiro não muda de sítio).
INSERT INTO public.order_receipt_fotos (order_id, bucket, path, total_cents, tirada_em, recebida_em, tamanho_bytes, origem)
SELECT r.order_id, 'receipts', o.name, r.driver_typed_total_cents, r.photo_taken_at,
       COALESCE(r.photo_taken_at, o.created_at, now()), NULLIF(o.metadata->>'size', '')::bigint, 'antigo'
  FROM public.order_receipts_v2 r
  JOIN storage.objects o ON o.bucket_id = 'receipts'
                        AND o.name = regexp_replace(r.photo_url, '^receipts/', '')
ON CONFLICT (path) DO NOTHING;

-- O estafeta lê as fotos do pedido dele também no caminho novo (AAAA/MM/<order_id>/…).
-- O admin já lê o bucket inteiro (admin_select_all_receipts_storage). Ninguém atualiza nem apaga.
DROP POLICY IF EXISTS driver_select_own_receipt_pasta ON storage.objects;
CREATE POLICY driver_select_own_receipt_pasta ON storage.objects FOR SELECT TO authenticated
  USING (bucket_id = 'receipts'
         AND EXISTS (SELECT 1 FROM public.orders o
                      WHERE o.id = (storage.foldername(objects.name))[3]
                        AND (o.assigned_driver_id = auth.uid()::text
                             OR o.assigned_driver_id IN (SELECT d.id::text FROM public.drivers d WHERE d.user_id = auth.uid()))));

-- NIF usado no talão (o que o estafeta devia pedir ao balcão). Interno.
CREATE OR REPLACE FUNCTION public._talao_nif_usado(p_order_id text)
RETURNS jsonb LANGUAGE sql STABLE SECURITY DEFINER SET search_path TO 'public' AS $$
  SELECT CASE
    WHEN COALESCE(o.is_partner_store, false) THEN jsonb_build_object('nif', NULL, 'origem', 'loja_parceira')
    WHEN i.order_id IS NOT NULL AND COALESCE(NULLIF(btrim(i.nif), ''), NULLIF(btrim(b.nif), '')) IS NOT NULL
      THEN jsonb_build_object('nif', COALESCE(NULLIF(btrim(i.nif), ''), NULLIF(btrim(b.nif), '')), 'origem', 'cliente')
    ELSE jsonb_build_object('nif', '519686233', 'origem', 'bora')
  END
  FROM public.orders o
  LEFT JOIN public.order_invoice_requests i ON i.order_id = o.id
  LEFT JOIN public.client_billing_profile b ON b.user_id = o.user_id
  WHERE o.id = p_order_id
$$;
REVOKE ALL ON FUNCTION public._talao_nif_usado(text) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public._talao_nif_usado(text) TO service_role;   -- Edge taloes-zip-mes

-- Painel: o talão do pedido (todas as fotos + valor escrito + NIF usado).
CREATE OR REPLACE FUNCTION public.admin_talao_do_pedido(p_order_id text)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path TO 'public' AS $$
BEGIN
  IF NOT public.is_admin() THEN RAISE EXCEPTION 'forbidden' USING ERRCODE = '42501'; END IF;
  RETURN jsonb_build_object(
    'ok', true,
    'valor_escrito_cents', (SELECT r.driver_typed_total_cents FROM public.order_receipts_v2 r WHERE r.order_id = p_order_id),
    'foto_atual', (SELECT r.photo_url FROM public.order_receipts_v2 r WHERE r.order_id = p_order_id),
    'nif', public._talao_nif_usado(p_order_id),
    'fotos', COALESCE((SELECT jsonb_agg(jsonb_build_object(
                 'path', f.path, 'bucket', f.bucket, 'total_cents', f.total_cents, 'tirada_em', f.tirada_em,
                 'recebida_em', f.recebida_em, 'tamanho_bytes', f.tamanho_bytes, 'origem', f.origem,
                 'copia_em', f.copia_em) ORDER BY f.recebida_em)
               FROM public.order_receipt_fotos f WHERE f.order_id = p_order_id), '[]'::jsonb));
END $$;
REVOKE ALL ON FUNCTION public.admin_talao_do_pedido(text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.admin_talao_do_pedido(text) TO authenticated;

-- Painel: página "Talões" (filtro por mês, loja e estafeta).
CREATE OR REPLACE FUNCTION public.admin_taloes_listar(
  p_mes text DEFAULT NULL, p_loja text DEFAULT NULL, p_driver_uid uuid DEFAULT NULL, p_limite integer DEFAULT 500)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path TO 'public' AS $$
DECLARE v_ini timestamptz; v_fim timestamptz;
BEGIN
  IF NOT public.is_admin() THEN RAISE EXCEPTION 'forbidden' USING ERRCODE = '42501'; END IF;
  IF p_mes IS NOT NULL AND p_mes !~ '^\d{4}-\d{2}$' THEN RETURN jsonb_build_object('ok', false, 'error', 'mes_invalido'); END IF;
  IF p_mes IS NOT NULL THEN
    v_ini := (p_mes || '-01')::date::timestamp AT TIME ZONE 'Europe/Lisbon';
    v_fim := ((p_mes || '-01')::date + interval '1 month')::timestamp AT TIME ZONE 'Europe/Lisbon';
  END IF;
  RETURN jsonb_build_object('ok', true, 'fotos', COALESCE((
    SELECT jsonb_agg(x ORDER BY x->>'recebida_em' DESC) FROM (
      SELECT jsonb_build_object(
               'order_id', f.order_id, 'path', f.path, 'bucket', f.bucket, 'total_cents', f.total_cents,
               'recebida_em', f.recebida_em, 'origem', f.origem, 'copia_em', f.copia_em,
               'loja', COALESCE(o.vendor_name, o.restaurant_id), 'restaurant_id', o.restaurant_id,
               'service_type', o.service_type, 'payment_method', o.payment_method,
               'driver_uid', COALESCE(f.driver_uid, d.user_id),
               'estafeta', COALESCE(du.name, du.email),
               'nif', public._talao_nif_usado(f.order_id)) x
        FROM public.order_receipt_fotos f
        JOIN public.orders o ON o.id = f.order_id
        LEFT JOIN public.drivers d ON d.user_id::text = o.assigned_driver_id OR d.id::text = o.assigned_driver_id
        LEFT JOIN public.users du ON du.id = COALESCE(f.driver_uid, d.user_id)
       WHERE (v_ini IS NULL OR (f.recebida_em >= v_ini AND f.recebida_em < v_fim))
         AND (p_loja IS NULL OR o.restaurant_id = p_loja OR o.vendor_name ILIKE '%' || p_loja || '%')
         AND (p_driver_uid IS NULL OR COALESCE(f.driver_uid, d.user_id) = p_driver_uid)
       ORDER BY f.recebida_em DESC
       LIMIT LEAST(GREATEST(COALESCE(p_limite, 500), 1), 2000)) s), '[]'::jsonb));
END $$;
REVOKE ALL ON FUNCTION public.admin_taloes_listar(text, text, uuid, integer) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.admin_taloes_listar(text, text, uuid, integer) TO authenticated;

-- Pedidos não-parceiros entregues SEM talão (para o painel e para o vigia). Só leitura.
CREATE OR REPLACE FUNCTION public.admin_pedidos_sem_talao(p_desde date DEFAULT NULL)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path TO 'public' AS $$
BEGIN
  IF NOT public.is_admin() THEN RAISE EXCEPTION 'forbidden' USING ERRCODE = '42501'; END IF;
  RETURN COALESCE((SELECT jsonb_agg(jsonb_build_object('order_id', o.id, 'delivered_at', o.delivered_at,
           'loja', o.vendor_name, 'payment_method', o.payment_method,
           'foto', r.photo_url) ORDER BY o.delivered_at DESC)
    FROM public.orders o
    LEFT JOIN public.order_receipts_v2 r ON r.order_id = o.id
   WHERE o.status = 'delivered' AND NOT COALESCE(o.is_partner_store, false)
     AND o.service_type IN ('storeShopping', 'restaurant', 'errand')
     AND (o.service_type <> 'errand' OR COALESCE(o.errand_has_purchase, false))
     AND NOT COALESCE(o.is_test_order, false)
     AND (p_desde IS NULL OR o.delivered_at >= p_desde)
     AND (r.order_id IS NULL OR r.photo_url IS NULL OR r.photo_url NOT LIKE '%.jpg'
          OR NOT EXISTS (SELECT 1 FROM public.order_receipt_fotos f WHERE f.order_id = o.id))), '[]'::jsonb);
END $$;
REVOKE ALL ON FUNCTION public.admin_pedidos_sem_talao(date) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.admin_pedidos_sem_talao(date) TO authenticated;

-- 2.ª cópia diária: às 03:30 de Lisboa a Edge taloes-copia-diaria copia as fotos sem copia_em
-- para o Google Drive da Bora (pasta Talões/AAAA/MM). Liga-se só depois de a Claude.ai/Danilo
-- autorizarem o Google Drive (segredos GOOGLE_DRIVE_*; ver LEIA-PRIMEIRO). Idempotente.
INSERT INTO public.platform_settings (key, value, description, category) VALUES
  ('taloes_copia_drive_ativa', 'false'::jsonb,
   'Cópia diária dos talões para o Google Drive da Bora (pasta Talões/AAAA/MM). true liga depois de o Drive estar autorizado; nunca apaga nada', 'recibos')
ON CONFLICT (key) DO NOTHING;
DO $do$
BEGIN
  IF EXISTS (SELECT 1 FROM pg_extension WHERE extname = 'pg_cron') THEN
    PERFORM cron.unschedule(jobid) FROM cron.job WHERE jobname = 'taloes-copia-diaria';
    PERFORM cron.schedule('taloes-copia-diaria', '30 2,3 * * *', $c$
      SELECT net.http_post(
        url := (SELECT decrypted_secret FROM vault.decrypted_secrets WHERE name = 'project_url') || '/functions/v1/taloes-copia-diaria',
        headers := jsonb_build_object('Authorization', 'Bearer ' || (SELECT decrypted_secret FROM vault.decrypted_secrets WHERE name = 'service_role_key'),
                                      'Content-Type', 'application/json'),
        body := '{"cron": true}'::jsonb, timeout_milliseconds := 120000)
    $c$);
  END IF;
END $do$;
