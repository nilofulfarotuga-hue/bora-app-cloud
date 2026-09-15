-- ═══════════════════════════════════════════════════════════
-- BLOCO 2d — Fix 2 RLS WITH CHECK true vulneráveis
-- Data: 2026-05-08 / Sessão 7-SEC-1
-- Razão:
--   messages.allow_insert_messages: anon+auth podiam inserir
--     mensagens em qualquer order, sem validação.
--   restaurants.allow_insert_restaurants: public role podia
--     criar restaurantes falsos com qualquer dado.
-- ═══════════════════════════════════════════════════════════

-- ─── 1. messages: validar que sender é participante do order ─
DROP POLICY IF EXISTS "allow_insert_messages" ON public.messages;

CREATE POLICY "messages_insert_participant" ON public.messages
  FOR INSERT TO authenticated
  WITH CHECK (
    order_id IS NOT NULL
    AND EXISTS (
      SELECT 1 FROM public.orders o
      WHERE o.id = messages.order_id::text
        AND (
          o.user_id = auth.uid()                              -- cliente do order
          OR o.assigned_driver_id::text = auth.uid()::text    -- driver atribuído
          OR EXISTS (                                          -- partner (owner do restaurant)
            SELECT 1 FROM public.restaurants r
            WHERE r.id = o.restaurant_id
              AND r.user_ = auth.uid()
          )
          OR is_admin()                                        -- admin
        )
    )
  );

-- ─── 2. restaurants: só admin pode INSERT ────────────────────
DROP POLICY IF EXISTS "allow_insert_restaurants" ON public.restaurants;

CREATE POLICY "restaurants_insert_admin_only" ON public.restaurants
  FOR INSERT TO authenticated
  WITH CHECK (is_admin());
