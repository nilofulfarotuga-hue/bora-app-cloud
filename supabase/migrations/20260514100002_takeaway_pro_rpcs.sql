-- ============================================================
-- TAKEAWAY PRO — RPCs (3 partner actions)
-- ============================================================
-- Aplicadas via MCP em 2026-05-13 por Claude.ai.
-- Esta migration existe APENAS para versionamento.
--
-- ⚠️ FONTE DA VERDADE: o corpo destas RPCs **em produção** vive no
--    projeto Supabase (foi criado via MCP). Esta migration é uma
--    reconstrução documental baseada no comportamento contratado:
--      - signatures confirmadas via MCP
--      - efeitos colaterais descritos no PROMPT C/B
--
-- ANTES DE APLICAR ESTA MIGRATION num ambiente novo (preview/dev),
-- valide o corpo contra o que está em produção:
--   `supabase functions/get_function_definition` no MCP
--   ou
--   `psql -c "\sf public.partner_takeaway_accept"`
--
-- Se houver divergência, a versão de produção é authoritative —
-- actualize este ficheiro para alinhar.
--
-- Ref:
--   .claude/.ai/reports/2026-05-13_takeaway_investigation.md
--   .claude/.ai/reports/2026-05-13_prompt-C-plano.md
-- ============================================================

-- ── 1) partner_takeaway_accept ────────────────────────────────
-- Parceiro aceita o pedido takeaway com ETA. Muda status para
-- 'preparing' e calcula takeaway_ready_at = NOW() + prep_minutes.
CREATE OR REPLACE FUNCTION public.partner_takeaway_accept(
  p_order_id text,
  p_prep_minutes integer
) RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_order public.orders%ROWTYPE;
  v_clamped integer;
BEGIN
  -- Valida prep_minutes (3-60).
  v_clamped := GREATEST(3, LEAST(60, p_prep_minutes));

  SELECT * INTO v_order FROM public.orders WHERE id = p_order_id FOR UPDATE;

  IF NOT FOUND THEN
    RETURN jsonb_build_object('ok', false, 'reason', 'order_not_found');
  END IF;

  IF v_order.service_type IS DISTINCT FROM 'takeaway' THEN
    RETURN jsonb_build_object('ok', false, 'reason', 'not_takeaway');
  END IF;

  IF v_order.status <> 'created' THEN
    RETURN jsonb_build_object('ok', false, 'reason', 'invalid_status',
      'current', v_order.status);
  END IF;

  UPDATE public.orders
     SET status                 = 'preparing',
         takeaway_prep_minutes  = v_clamped,
         takeaway_ready_at      = NOW() + (v_clamped || ' minutes')::interval
   WHERE id = p_order_id;

  RETURN jsonb_build_object(
    'ok', true,
    'order_id', p_order_id,
    'prep_minutes', v_clamped,
    'ready_at', (NOW() + (v_clamped || ' minutes')::interval)::text
  );
END;
$$;

COMMENT ON FUNCTION public.partner_takeaway_accept(text, integer) IS
  'BR §14.9 — parceiro aceita pedido takeaway com ETA. '
  'Muda status created→preparing e calcula takeaway_ready_at.';

-- ── 2) partner_takeaway_mark_ready ────────────────────────────
-- Parceiro marca como pronto para levantamento. Trigger DB
-- subjacente envia push ao cliente via notify-client.
CREATE OR REPLACE FUNCTION public.partner_takeaway_mark_ready(
  p_order_id text
) RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_order public.orders%ROWTYPE;
BEGIN
  SELECT * INTO v_order FROM public.orders WHERE id = p_order_id FOR UPDATE;

  IF NOT FOUND THEN
    RETURN jsonb_build_object('ok', false, 'reason', 'order_not_found');
  END IF;

  IF v_order.service_type IS DISTINCT FROM 'takeaway' THEN
    RETURN jsonb_build_object('ok', false, 'reason', 'not_takeaway');
  END IF;

  IF v_order.status <> 'preparing' THEN
    RETURN jsonb_build_object('ok', false, 'reason', 'invalid_status',
      'current', v_order.status);
  END IF;

  UPDATE public.orders
     SET status = 'readyForPickup'
   WHERE id = p_order_id;

  RETURN jsonb_build_object(
    'ok', true,
    'order_id', p_order_id,
    'pickup_code', v_order.takeaway_pickup_code
  );
END;
$$;

COMMENT ON FUNCTION public.partner_takeaway_mark_ready(text) IS
  'BR §14.11 — parceiro marca takeaway pronto. preparing→readyForPickup. '
  'Trigger de notificação envia push ao cliente (notify-client).';

-- ── 3) partner_takeaway_mark_picked_up ────────────────────────
-- Cliente apareceu e levantou. Status → delivered. Não há
-- estafeta no fluxo takeaway, portanto o servidor salta
-- directamente para o estado terminal.
CREATE OR REPLACE FUNCTION public.partner_takeaway_mark_picked_up(
  p_order_id text
) RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_order public.orders%ROWTYPE;
BEGIN
  SELECT * INTO v_order FROM public.orders WHERE id = p_order_id FOR UPDATE;

  IF NOT FOUND THEN
    RETURN jsonb_build_object('ok', false, 'reason', 'order_not_found');
  END IF;

  IF v_order.service_type IS DISTINCT FROM 'takeaway' THEN
    RETURN jsonb_build_object('ok', false, 'reason', 'not_takeaway');
  END IF;

  IF v_order.status <> 'readyForPickup' THEN
    RETURN jsonb_build_object('ok', false, 'reason', 'invalid_status',
      'current', v_order.status);
  END IF;

  UPDATE public.orders
     SET status                 = 'delivered',
         takeaway_picked_up_at  = NOW()
   WHERE id = p_order_id;

  RETURN jsonb_build_object('ok', true, 'order_id', p_order_id);
END;
$$;

COMMENT ON FUNCTION public.partner_takeaway_mark_picked_up(text) IS
  'BR §14.11 — parceiro confirma levantamento. readyForPickup→delivered. '
  'Sem estafeta no fluxo (takeaway pula pickedUp/onTheWay).';

-- ============================================================
-- FIM da migration takeaway_pro_rpcs
-- ============================================================
