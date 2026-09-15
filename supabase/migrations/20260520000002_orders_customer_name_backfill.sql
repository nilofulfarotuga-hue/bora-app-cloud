-- ═══════════════════════════════════════════════════════════════════════════
-- BUG-UI customer_name no histórico parceiro
--
-- A coluna orders.customer_name JÁ existe (schema.sql:101) e o Flutter
-- (payment_method_screen.dart) já passa `customerName: authStore.currentClient?.name`
-- ao criar pedidos novos. Pedidos antigos ficaram com customer_name=NULL
-- porque foram criados antes do campo estar a ser populado.
--
-- Backfill via auth.users.raw_user_meta_data->>'full_name' para todos os
-- pedidos com user_id preenchido. Idempotente (WHERE customer_name IS NULL).
-- Não afecta pedidos onde o nome já foi gravado pelo Flutter no checkout.
-- ═══════════════════════════════════════════════════════════════════════════

UPDATE public.orders o
   SET customer_name = (au.raw_user_meta_data->>'full_name')::text
  FROM auth.users au
 WHERE o.user_id IS NOT NULL
   AND o.user_id::uuid = au.id
   AND (o.customer_name IS NULL OR o.customer_name = '')
   AND au.raw_user_meta_data->>'full_name' IS NOT NULL
   AND length(trim(au.raw_user_meta_data->>'full_name')) > 0;
