-- PROPOSTA P1 (missão painel-admin-15-11, 15/11/2026, Claude Code). Aplica a Claude.ai com execute_sql.
-- ZONA PROTEGIDA: mexe em RLS de orders (e de duas tabelas de saldo). A ordem explícita existe: Danilo
-- 15/11 13:34, transmitida pela Claude.ai às 13:38 (caixa 57, ponto A: "regra de leitura de admin em
-- orders, driver_balances, driver_transactions, support_tickets"; "admin_update_driver uma versão só").
-- É só LEITURA para o admin: não muda escrita, valores, comissões nem quem paga o quê.
--
-- O problema (provado a 15/11 por SELECT em pg_policies e pelos relatórios S1, S2, S3 e S4):
--   * orders só tem regras de leitura para o cliente, o estafeta e o parceiro. Nenhuma migração criou
--     uma regra de admin. O painel lê orders diretamente em 11 sítios (ecrã Pedidos, detalhe do pedido,
--     ficha do estafeta, pesquisa global, avaliações, reembolsos de estafetas, substituições) e o admin
--     vê só os pedidos da própria conta: no ecrã Pedidos, 10 de 108 (S1; o registo da API de 14/11
--     18:50 mostra content-range 0-9). Abrir o pedido de outra pessoa dá "Pedido não encontrado".
--   * driver_balances e driver_transactions só deixam ler "o próprio" (driver_id = auth.uid()): o saldo
--     na ficha do estafeta e o ecrã "Saques dos estafetas" mostram sempre zero (0 de 5 saldos, 0 de 122
--     transações com um JWT de admin simulado, S2 e S3).
--   * appointment_reschedules só tem regras para cliente e parceiro: o "Histórico" da agenda de
--     marcações mostra "Sem registos" (S4).
--   * support_tickets só deixa cada pessoa ler os seus: o ecrã "Suporte — Tickets" fica vazio (25
--     tickets, 7 abertos; S6). A regra abaixo é a mesma da proposta das conversas ao vivo (caixa 55,
--     mesmo nome support_tickets_admin_ler): aplicar uma ou as duas não duplica nada.
--   * admin_update_driver tem 2 versões (8 e 10 parâmetros, todos com valor por defeito a partir do
--     3.º). Quando a cor e o modelo do veículo não mudam, a app manda 8 chaves e as duas versões servem:
--     o servidor recusa por ambiguidade (PGRST203) e "Editar dados" do estafeta dá erro (S3). A versão
--     de 10 só muda a cor e o modelo quando vêm preenchidos (IF p_vehicle_color IS NOT NULL ...,
--     conferido a 15/11), por isso apagar a de 8 resolve já, também para a app que está publicada.
--     A de 10 fica igual; o texto dela vai para o repo em
--     supabase/migrations/20260702182113_admin_update_driver_10_params_doc.sql.
-- As regras de leitura têm a mesma forma das outras 266 regras do projeto que usam is_admin(). O
-- (select ...) faz o Postgres avaliar is_admin() uma vez por consulta, não uma vez por linha.

drop policy if exists orders_select_admin on public.orders;
create policy orders_select_admin on public.orders
  for select to authenticated using ((select public.is_admin()));

drop policy if exists driver_balances_select_admin on public.driver_balances;
create policy driver_balances_select_admin on public.driver_balances
  for select to authenticated using ((select public.is_admin()));

drop policy if exists driver_transactions_select_admin on public.driver_transactions;
create policy driver_transactions_select_admin on public.driver_transactions
  for select to authenticated using ((select public.is_admin()));

drop policy if exists appointment_reschedules_select_admin on public.appointment_reschedules;
create policy appointment_reschedules_select_admin on public.appointment_reschedules
  for select to authenticated using ((select public.is_admin()));

drop policy if exists support_tickets_admin_ler on public.support_tickets;
create policy support_tickets_admin_ler on public.support_tickets
  for select to authenticated using (coalesce(public.is_admin(), false));

-- admin_update_driver: fica só a versão de 10 parâmetros.
drop function if exists public.admin_update_driver(uuid, text, text, text, text, text, text, text);

-- PROVA depois de aplicar:
--   select tablename, policyname from pg_policies
--    where schemaname = 'public' and policyname in ('orders_select_admin', 'driver_balances_select_admin',
--          'driver_transactions_select_admin', 'appointment_reschedules_select_admin',
--          'support_tickets_admin_ler');                                                      -- 5 linhas
--   select count(*) from pg_proc where proname = 'admin_update_driver';                       -- 1
--   No painel (conta admin): Pedidos mostra os pedidos de todos; a ficha de um estafeta mostra o saldo
--   e as transações dele (o código do ramo ai/2026-11-15-app já filtra pelos dois ids do estafeta).
--
-- ALTERNATIVA sem tocar em RLS (se o Danilo não quiser a regra): funções SECURITY DEFINER com
-- is_admin() (admin_list_orders, admin_get_order, admin_saldo_estafeta) e mudar o código dos 11 sítios.
-- Dá o mesmo acesso ao admin, mas demora mais a pôr no ar (código novo, CI, publicação nas 3 lojas).
