-- Ronda 04/10 A.2 (05/10/2026): o botão "Cancelar pedido" do painel (Edge admin-cancel-order) chama
-- admin_cancel_order com a sessão do admin, mas a função só tinha EXECUTE para postgres/service_role
-- (última utilização com sucesso: 03/10 17:19). A guarda _admin_op_guard() dentro exige
-- app_metadata.role = 'admin' no token — por isso é seguro dar EXECUTE a authenticated (anon continua fora).
-- Prova (transacção desfeita): cliente demo -> "admin_required: app_metadata.role=client"; anon = false.
grant execute on function public.admin_cancel_order(uuid, public.cancellation_reason_code, text) to authenticated;
