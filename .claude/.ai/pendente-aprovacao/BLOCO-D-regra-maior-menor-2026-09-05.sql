-- ============================================================================
-- BLOCO D — REGRA "MAIS CARO APLICA / MAIS BARATO PENDURA"
-- Missão nao-parceiros-fotos-e-talao · 2026-09-05
--
-- ⚠️ NÃO APLICADO. ISTO MEXE EM PAGAMENTO/DINHEIRO.
--    Está tudo pronto — falta o Danilo dizer "vai".
--
-- PORQUE ESTÁ PARADO
--   Muda a regra que decide quando um preço de produto se corrige SOZINHO.
--   Cai na Lista Vermelha (CLAUDE.md §Validation Gate) e também esbarra na
--   regra número um desta missão ("nenhum preço de produto existente muda").
--   Por isso escreve-se, prova-se, e espera-se.
--
-- O QUE MUDA, EM UMA FRASE
--   Hoje o motor decide pelo TAMANHO do desvio: até ±30% aplica sozinho,
--   acima disso pendura. Ou seja, um preço MAIS BARATO com desvio pequeno é
--   aplicado automaticamente — exactamente o que o Danilo NÃO quer.
--   Passa a decidir pela DIRECÇÃO:
--     • talão MAIS CARO que o catálogo  -> aplica (protege a margem)
--     • talão MAIS BARATO               -> 'pending', fica para ele decidir
--
-- SALVAGUARDAS QUE SE MANTÊM
--   • kill switch `catalog_price_live_update_enabled` continua a mandar;
--   • lojas parceiras continuam de fora;
--   • tudo passa a ficar em `admin_audit_log` (não ficava);
--   • tecto de 3× para não deixar um OCR disparatado triplicar um preço.
--
-- COMO PROVAR DEPOIS DE APLICAR (está no fim do ficheiro)
-- ============================================================================

CREATE OR REPLACE FUNCTION public.catalog_price_update_from_receipt(p_receipt_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'extensions'
AS $function$
DECLARE
  v_r          record;
  v_order      record;
  v_item       jsonb;
  v_line       jsonb;
  v_best_line  jsonb;
  v_best_sim   numeric;
  v_sim        numeric;
  v_prod       record;
  v_new_base   numeric(12,2);
  v_update_id  uuid;
  v_aplicadas  int := 0;
  v_pendentes  int := 0;
  v_sem_match  int := 0;
  v_iguais     int := 0;
  v_absurdas   int := 0;
  v_enabled    boolean;
BEGIN
  SELECT (value::text IN ('true', '"true"')) INTO v_enabled
    FROM platform_settings WHERE key='catalog_price_live_update_enabled';
  IF NOT COALESCE(v_enabled, false) THEN
    RETURN jsonb_build_object('ok', true, 'skipped', 'kill_switch_off');
  END IF;

  SELECT r.id, r.order_id, r.receipt_parsed INTO v_r
    FROM order_receipts_v2 r WHERE r.id = p_receipt_id;
  IF v_r.id IS NULL THEN
    RETURN jsonb_build_object('ok', false, 'error', 'receipt_not_found');
  END IF;
  IF v_r.receipt_parsed IS NULL
     OR jsonb_typeof(v_r.receipt_parsed->'lines') IS DISTINCT FROM 'array'
     OR jsonb_array_length(v_r.receipt_parsed->'lines') = 0 THEN
    RETURN jsonb_build_object('ok', true, 'skipped', 'sem_linhas_no_talao');
  END IF;

  SELECT o.id, o.restaurant_id, o.is_partner_store, o.items INTO v_order
    FROM orders o WHERE o.id = v_r.order_id;
  IF v_order.id IS NULL THEN
    RETURN jsonb_build_object('ok', false, 'error', 'order_not_found');
  END IF;
  IF COALESCE(v_order.is_partner_store, false) THEN
    RETURN jsonb_build_object('ok', true, 'skipped', 'loja_parceira');
  END IF;

  FOR v_item IN SELECT * FROM jsonb_array_elements(COALESCE(v_order.items, '[]'::jsonb))
  LOOP
    v_best_line := NULL; v_best_sim := 0;
    FOR v_line IN SELECT * FROM jsonb_array_elements(v_r.receipt_parsed->'lines')
    LOOP
      IF COALESCE((v_line->>'qty')::numeric, 1) = COALESCE((v_item->>'quantity')::numeric, 1)
         AND COALESCE((v_line->>'unit_price_cents')::int, 0) > 0 THEN
        v_sim := extensions.similarity(upper(v_item->>'name'), upper(v_line->>'name'));
        IF v_sim > v_best_sim THEN
          v_best_sim := v_sim; v_best_line := v_line;
        END IF;
      END IF;
    END LOOP;

    IF v_best_line IS NULL OR v_best_sim < 0.45 THEN
      v_sem_match := v_sem_match + 1;
      CONTINUE;
    END IF;

    SELECT p.id, p.price, p.restaurant_id INTO v_prod
      FROM products p
      WHERE p.id = (v_item->>'productId')
        AND p.restaurant_id::text = v_order.restaurant_id::text;
    IF v_prod.id IS NULL OR v_prod.price IS NULL OR v_prod.price <= 0 THEN
      v_sem_match := v_sem_match + 1;
      CONTINUE;
    END IF;

    v_new_base := ROUND(((v_best_line->>'unit_price_cents')::numeric) / 100.0, 2);
    IF v_new_base <= 0 THEN CONTINUE; END IF;

    IF v_new_base = ROUND(v_prod.price::numeric, 2) THEN
      v_iguais := v_iguais + 1;
      CONTINUE;
    END IF;

    -- Rede contra OCR disparatado: nada triplica um preço sozinho.
    IF v_new_base > v_prod.price * 3 THEN
      INSERT INTO catalog_price_updates
        (product_id, restaurant_id, order_id, receipt_id, old_base, new_base,
         confianca, linha_talao, status)
      VALUES (v_prod.id, v_prod.restaurant_id::text, v_order.id, p_receipt_id,
              ROUND(v_prod.price::numeric,2), v_new_base, ROUND(v_best_sim,3),
              v_best_line->>'name', 'pending');
      v_absurdas := v_absurdas + 1;
      CONTINUE;
    END IF;

    IF v_new_base > v_prod.price THEN
      -- ── TALÃO MAIS CARO: aplica. Protege o Danilo de vender abaixo do que paga.
      UPDATE products SET price = v_new_base WHERE id = v_prod.id;

      INSERT INTO catalog_price_updates
        (product_id, restaurant_id, order_id, receipt_id, old_base, new_base,
         confianca, linha_talao, status)
      VALUES (v_prod.id, v_prod.restaurant_id::text, v_order.id, p_receipt_id,
              ROUND(v_prod.price::numeric,2), v_new_base, ROUND(v_best_sim,3),
              v_best_line->>'name', 'applied')
      RETURNING id INTO v_update_id;

      -- entity_id_text porque products.id é TEXT
      PERFORM public.log_admin_action(
        'catalog_price_auto_applied', 'product', v_prod.id,
        jsonb_build_object('de', ROUND(v_prod.price::numeric,2), 'para', v_new_base,
                           'origem', 'talao_ocr', 'order_id', v_order.id,
                           'receipt_id', p_receipt_id, 'update_id', v_update_id,
                           'confianca', ROUND(v_best_sim,3),
                           'linha_talao', v_best_line->>'name'));
      v_aplicadas := v_aplicadas + 1;
    ELSE
      -- ── TALÃO MAIS BARATO: não aplica. Fica para decisão do Danilo.
      INSERT INTO catalog_price_updates
        (product_id, restaurant_id, order_id, receipt_id, old_base, new_base,
         confianca, linha_talao, status)
      VALUES (v_prod.id, v_prod.restaurant_id::text, v_order.id, p_receipt_id,
              ROUND(v_prod.price::numeric,2), v_new_base, ROUND(v_best_sim,3),
              v_best_line->>'name', 'pending');
      v_pendentes := v_pendentes + 1;
    END IF;
  END LOOP;

  RETURN jsonb_build_object('ok', true, 'aplicadas', v_aplicadas,
    'pendentes', v_pendentes, 'sem_match', v_sem_match,
    'ja_batiam', v_iguais, 'absurdas_penduradas', v_absurdas);
END $function$;


-- ── Ligar o motor aos talões automaticamente ────────────────────────────────
-- Hoje NADA chama esta função: as 5 linhas que existem em catalog_price_updates
-- foram criadas à mão. Com o trigger, todo o talão lido pelo OCR passa por cá —
-- mercados E restaurantes não-parceiros, que é o que o Bloco D pede.
-- Fica junto da regra nova de propósito: ligar o automatismo com a regra ANTIGA
-- seria pior do que não ligar nada (baixaria preços sozinho).

CREATE OR REPLACE FUNCTION public.fn_corrige_preco_apos_ocr()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'extensions'
AS $function$
BEGIN
  IF NEW.receipt_parsed IS NOT NULL
     AND (OLD.receipt_parsed IS NULL OR OLD.receipt_parsed <> NEW.receipt_parsed) THEN
    BEGIN
      PERFORM public.catalog_price_update_from_receipt(NEW.id);
    EXCEPTION WHEN OTHERS THEN
      -- nunca partir a gravação do talão por causa da correcção de preço
      RAISE WARNING 'catalog_price_update_from_receipt falhou p/ %: %', NEW.id, SQLERRM;
    END;
  END IF;
  RETURN NEW;
END $function$;

CREATE OR REPLACE TRIGGER trg_corrige_preco_apos_ocr
  AFTER UPDATE OF receipt_parsed ON public.order_receipts_v2
  FOR EACH ROW
  EXECUTE FUNCTION public.fn_corrige_preco_apos_ocr();


-- ============================================================================
-- PROVA A CORRER DEPOIS DE APLICAR
-- ============================================================================
-- 1) talão mais caro -> tem de ficar 'applied' e o preço subir
-- 2) talão mais barato -> tem de ficar 'pending' e o preço NÃO mexer
-- 3) tem de aparecer linha em admin_audit_log
--
-- SELECT status, count(*) FROM catalog_price_updates
--  WHERE created_at > now() - interval '1 hour' GROUP BY 1;
--
-- SELECT action, entity_id_text, details FROM admin_audit_log
--  WHERE action LIKE 'catalog_price%' ORDER BY created_at DESC LIMIT 10;
-- ============================================================================
