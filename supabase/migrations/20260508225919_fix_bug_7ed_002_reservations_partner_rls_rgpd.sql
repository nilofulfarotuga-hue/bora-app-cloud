-- ═══════════════════════════════════════════════════════════
-- BUG-7E-D-002 (HIGH RGPD) FIX
-- Data: 2026-05-08 / Sessao 7-alpha-7E-D-TESTS post-mortem
--
-- Problema: policy reservations_partner_read_all tinha
-- qual='true' -> qualquer partner autenticado via TODAS as
-- reservations de TODOS os restaurantes (nome cliente,
-- telefone, data, num pessoas).
--
-- RGPD violation: dados pessoais clientes expostos a partners
-- nao relacionados.
--
-- Fix: restringir SELECT a partners donos do restaurante
-- da reserva (via restaurants.user_ FK directo).
--
-- HIGH severity: bloqueante RGPD para launch comercial em PT/UE.
--
-- Aplicada via MCP em prod antes do ficheiro local.
--
-- Compatibilidade: clientes mantem reservations_client_owner
-- ALL policy (ver suas proprias reservas). Partner UPDATE
-- (aceitar/rejeitar) via RPC partner_decide_reservation
-- SECURITY DEFINER (BUG-7E-C-003 ja fixed).
-- ═══════════════════════════════════════════════════════════

DROP POLICY IF EXISTS reservations_partner_read_all ON public.reservations;

CREATE POLICY reservations_partner_read_own
  ON public.reservations
  FOR SELECT
  TO authenticated
  USING (
    restaurant_id IN (
      SELECT id FROM public.restaurants
      WHERE user_ = auth.uid()
    )
  );

COMMENT ON POLICY reservations_partner_read_own ON public.reservations IS
  'BUG-7E-D-002 FIX (2026-05-08): partner so ve reservas dos seus restaurantes (RGPD compliance). Substitui reservations_partner_read_all.qual=true.';
