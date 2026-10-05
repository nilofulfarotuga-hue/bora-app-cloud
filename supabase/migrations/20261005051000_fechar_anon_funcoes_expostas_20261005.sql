-- 05/10: funções SECURITY DEFINER sem verificação interna que qualquer pessoa sem sessão podia chamar.
-- Aplicada em produção pela Claude.ai via MCP. Todos os chamadores da app estão em ecrãs com sessão.
revoke execute on function public.compute_provider_weekly_payout(text, timestamptz, boolean) from public, anon;
revoke execute on function public.tvde_reservation_offer_to_next(uuid) from public, anon;
revoke execute on function public.get_user_tokens(uuid) from public, anon;
revoke execute on function public.order_driver_reimbursement(text) from public, anon;
revoke execute on function public.compute_all_cleaner_weekly_settlements() from public, anon;
revoke execute on function public.compute_all_washer_weekly_settlements() from public, anon;
revoke execute on function public._cron_check_orphan_ledger() from public, anon;
revoke execute on function public._appointment_cron_expire_pending_payment() from public, anon;
grant execute on function public.compute_provider_weekly_payout(text, timestamptz, boolean) to authenticated, service_role;
grant execute on function public.tvde_reservation_offer_to_next(uuid) to service_role;
grant execute on function public.get_user_tokens(uuid) to authenticated, service_role;
grant execute on function public.order_driver_reimbursement(text) to authenticated, service_role;
grant execute on function public.compute_all_cleaner_weekly_settlements() to service_role;
grant execute on function public.compute_all_washer_weekly_settlements() to service_role;
grant execute on function public._cron_check_orphan_ledger() to service_role;
grant execute on function public._appointment_cron_expire_pending_payment() to service_role;
