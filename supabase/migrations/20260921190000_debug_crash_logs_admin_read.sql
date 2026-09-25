-- Paridade 3 plataformas (2026-09-21): o painel admin passa a ter o quadro
-- "Erros da app (crashes)" (lib/screens/admin/admin_crash_logs_screen.dart).
--
-- A tabela debug_crash_logs tinha RLS ligada e só a policy de INSERT
-- (anon + authenticated) — ninguém conseguia LER a partir da app, nem o admin.
-- Esta policy de leitura só-admin é a mesma que notification_failures usa
-- (migration 20260904230000): is_admin() é SECURITY DEFINER e lê auth.users.
--
-- Não toca em dinheiro, pedidos, estafetas nem em nenhuma zona protegida.

create policy debug_crash_logs_select_admin
  on public.debug_crash_logs
  for select
  to authenticated
  using (public.is_admin());
