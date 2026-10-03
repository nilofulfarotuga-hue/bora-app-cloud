-- Sessão 2026-05-26 — RLS policy to block direct restaurant INSERT
-- Força todo INSERT em restaurants via Edge Function register-partner
-- com service_role (que bypassa RLS). Clientes e parceiros não conseguem
-- inserir diretamente — obriga fluxo controlado de aprovação.

DROP POLICY IF EXISTS "restaurants_insert_via_edge_function_only" ON public.restaurants;

-- Lê: todos (existente) — public browse
-- Escreve: apenas service_role via Edge Function (bloqueia resto)
CREATE POLICY "restaurants_insert_via_edge_function_only"
  ON public.restaurants
  FOR INSERT
  WITH CHECK (false);  -- NUNCA permite INSERT via cliente/parceiro JWT

-- UPDATE e DELETE: apenas admin (não implementado aqui — admin_service_role)
-- Por enquanto, qualquer um com auth pode UPDATE (compatibilidade com logo upload)
