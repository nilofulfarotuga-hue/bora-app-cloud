-- Bloco C5 (21/09, 10h05–10h20 UTC) — SÓ INVESTIGAÇÃO, zero alterações.

-- ============================================================================
-- C5.1 — as duas contas "Danilo"
-- ============================================================================
-- auth.users:
--   4f61dd31-5e9e-4a7c-a557-7d53d2ceded7 · boraappbora@gmail.com · criada 26/06/2026 · bora_role=driver · telefone +351931992662
--   c9fccf85-03ee-4efc-83bf-613f211a78ff · nilofulfarotuga@gmail.com · criada 28/04/2026 · app_metadata.role=admin · bora_role=client
--   (tem email no auth; o "sem email" é em public.users: email NULL, phone +351937501673, role driver, criada 28/04)
-- Onde cada uma aparece (varrimento de todas as colunas *_id / *_by de public, contagem por conta):
--   c9fccf85 (ADMIN + CLIENTE — a conta do dono no painel e a conta com que ele compra e anda de TVDE como passageiro):
--     admin_audit_log.admin_id 287 · admin_ai_sessions 21 · robot_suggestions.reviewed_by 27 · skill_suggestions.reviewed_by 17 ·
--     platform_settings.updated_by 2 · push_broadcasts.created_by 3 · drivers.approved_by 5 · tvde_subscriptions.granted_by 4 ·
--     driver_weekly_settlements.paid_by 7 · partner_weekly_settlements.paid_by 2 · appointment_payouts.paid_by 1 ·
--     orders.user_id 5 (compras) · tvde_rides.client_id 22 (passageiro) · client_wallets 1 · wallet_transactions 2 · bora_tokens 5 ·
--     client_push_tokens 186 · driver_push_tokens 3 · in_app_notifications 19 · user_roles: client (31/07) + driver (20/09 15:31 UTC)
--   4f61dd31 (ESTAFETA / MOTORISTA — a conta que trabalha):
--     tvde_rides.driver_id 48 · orders.assigned_driver_id 14 · orders.driver_id 12 · driver_transactions 21 · ledger_entries 28 ·
--     driver_weekly_settlements.driver_id 5 · driver_balances 1 · tvde_driver_balances 1 · user_balance_snapshots 1 · payouts 2 ·
--     weekly_digest_log.subject_id 4 · settlement_receipts 3 · ratings.driver_id 10 · bora_tokens 18 · drivers.user_id 1 (approved, online) ·
--     cleaners.user_id 1 · washers.user_id 1 · user_roles: driver (31/07), client/delivery/cleaner/washer (28/08) · admin_audit_log.admin_id 2
-- O que a segunda conta ESCREVE hoje: só auditoria/aprovações (paid_by, approved_by, reviewed_by, updated_by) e as compras/corridas
--   de cliente. Nada de dinheiro de estafeta. Por isso aparece como `paid_by` nos acertos: é quem carrega em "Marcar pago".
-- ACHADO NOVO: a 20/09 às 15:31:45 UTC nasceram, no mesmo instante, uma linha em drivers (user_id c9fccf85, pending, offline,
--   email '', nunca teve heartbeat) e um user_roles 'driver' para a conta admin — alguém entrou na app de estafeta com a conta do
--   painel (ou um teste fê-lo). Não trabalhou, não tem corridas, não entra em acertos. Está a mais.
-- O QUE PARTIRIA SE SE FUNDISSEM (não fundir):
--   1. user_id manda em tudo: ~60 colunas apontam a uma ou à outra (rides, pedidos, acertos, saldos, ledger, tokens, carteira).
--      Reescrever isso é UPDATE em massa em orders/ledger/wallet_transactions/driver_weekly_settlements — tabelas com trava
--      (wallet append-only, orders_financial_lock, order_driver_assignment_audit) e regra "o histórico não se reescreve".
--   2. Únicos que colidem: drivers.user_id, user_roles(user_id, role), client_wallets(user_id), driver_balances(driver_id),
--      tvde_driver_balances, driver_weekly_settlements(driver_id, week_start_at) — a conta admin já tem carteira, tokens, roles.
--   3. Admin: is_admin() lê app_metadata.role='admin' OU o email nilofulfarotuga/nilofulfaro. Fundir para 4f61dd31 (gmail
--      boraappbora) tirava o admin do JWT actual; fundir para c9fccf85 punha as 48 corridas e os acertos no uid do dono/admin —
--      e o vigia/relatórios passavam a misturar "a Bora" com "o estafeta Danilo".
--   4. Sessões e push: tokens por uid nos três apps; o telemóvel do estafeta ficaria a apontar a uma conta apagada.
--   5. Stripe/MB Way: clientes Stripe por uid (a conta admin é a que compra).
-- PLANO (a executar só com o "vai"; nada disto foi feito):
--   a) manter as duas: c9fccf85 = dono (admin + cliente); 4f61dd31 = estafeta/motorista de trabalho;
--   b) limpar a candidatura acidental de 20/09: rejeitar/apagar a linha drivers(user_id c9fccf85) e o user_roles driver — pela
--      função de admin da fila de aprovação, não por DELETE directo;
--   c) public.users.email da c9fccf85 → nilofulfarotuga@gmail.com (hoje NULL; é o que faz o nome sair sem email nos avisos);
--   d) no painel, mostrar "(conta do painel)" ao lado do nome quando o uid é o admin, para nunca mais parecer duplicado.

-- ============================================================================
-- C5.2 — vigia de pedido no vermelho para PARCEIROS (hoje só cobre não-parceiros)
-- ============================================================================
-- Nos não-parceiros: sobrou = cliente pagou − mercadoria (talão) − estafeta.
-- Nos parceiros não há talão: a "mercadoria" é a parte que a Bora paga ao parceiro no acerto — e essa verdade está em
-- order_financials.restaurant_amount (é o que partner_weekly_settlements.partner_share soma: 10,90 = 12,72/1,05×0,90).
-- A conta por colunas de orders (subtotal − partner_commission_visible − partner_markup_hidden = 10,81) NÃO bate com o que se
-- paga (10,90) porque partner_store_share tem dois ramos no ar (memória 20/09); por isso a fórmula usa order_financials primeiro.
-- FÓRMULA PROPOSTA: sobrou = COALESCE(final_total, total)
--                          − COALESCE(order_financials.restaurant_amount, subtotal − partner_commission_visible − partner_markup_hidden)
--                          − driver_earnings ; VERMELHO quando ≤ 0.  (Dinheiro ou MB Way dá o mesmo: só muda quem segura as notas.)
with p as (
  select o.id, o.created_at::date as dia, o.vendor_name, o.payment_method,
         coalesce(o.final_total, o.total) as cliente_pagou,
         coalesce(f.restaurant_amount, o.subtotal - coalesce(o.partner_commission_visible,0) - coalesce(o.partner_markup_hidden,0)) as parte_do_parceiro,
         (f.restaurant_amount is not null) as parte_vem_do_financials,
         coalesce(o.driver_earnings,0) as estafeta
  from orders o left join order_financials f on f.order_id::text = o.id
  where o.is_partner_store and o.status='delivered')
select left(id,8), dia, vendor_name, payment_method, cliente_pagou, parte_do_parceiro, parte_vem_do_financials, estafeta,
       round(cliente_pagou - parte_do_parceiro - estafeta, 2) as sobrou_para_a_bora,
       case when round(cliente_pagou - parte_do_parceiro - estafeta, 2) <= 0 then 'VERMELHO' else 'ok' end as estado
from p order by dia desc;
-- SAÍDA (todos os pedidos de parceiro entregues — 4, todos Goola Açaí):
--   e1078830 16/09 mbway 16,16 − 10,90 − 4,22 = 1,04 ok · ae711470 11/09 mbway 1,04 ok · e15f2466 07/09 mbway 1,02 ok ·
--   fc07ca8d 05/09 cash 28,56 − 19,80 − 5,00 = 3,76 ok. Nenhum vermelho; margens finas (1,02–1,04) nos pedidos pequenos —
--   e seriam 2,41–2,43 se a taxa de pedido pequeno (1,39) fosse mesmo cobrada (ver C4 fora do scope).
-- Como aplicar (NÃO aplicado): no gatilho _trg_alerta_pedido_no_vermelho_fn trocar o `IF is_partner_store THEN RETURN` por um
--   ramo que use a fórmula acima, com o mesmo notify_admin_event('pedido_no_vermelho', …) e payload {parte_do_parceiro, estafeta,
--   sobrou_para_a_bora}. Precisa do "vai": mexe numa função de alerta, mas lê comissões — e a leitura pode tocar em order_financials
--   que só existe depois do webhook/entrega (o gatilho corre em delivered; nos cash a linha existe? nos 4 casos existe).
