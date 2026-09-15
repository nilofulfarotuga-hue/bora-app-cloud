-- 2026-09-13 -- os pedidos das contas demo deixaram de nascer a 12/09.
--
-- O gatilho _guard_order_driver_state (migracao fix_partner_order_lifecycle do
-- ChatGPT, 12/09) exige driver_id E assigned_driver_id em driverAccepted. A
-- caixa fechada dos pedidos demo (_pedido_demo_em_caixa_fechada, BEFORE INSERT,
-- corre primeiro por ordem alfabetica) so preenchia assigned_driver_id.
-- Resultado: INSERT recusado com 23514 ("order_driver_required") para
-- demo@bora.app, demo.cliente@bora.app e demo.apagar@bora.app -- exactamente
-- as contas que a Apple usa na revisao e que a loja anuncia. Provado em
-- rollback a 13/09 (auditoria FABLE). Passa a preencher tambem driver_id com o
-- user_id do estafeta demo (drivers.id dede...0002 -> user_id dede...0001),
-- que e' o formato que o dispatch v59 e driver_accept_offer usam.
CREATE OR REPLACE FUNCTION public._pedido_demo_em_caixa_fechada()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_demo_estafeta constant text := 'dede0000-0000-4000-8000-000000000002';
  v_demo_estafeta_user constant uuid := 'dede0000-0000-4000-8000-000000000001';
begin
  if new.user_id is null then
    return new;
  end if;

  -- So contas demo. Qualquer outra passa intacta.
  if not exists (
    select 1 from auth.users u
    where u.id = new.user_id
      and u.email in ('demo@bora.app', 'demo.cliente@bora.app', 'demo.apagar@bora.app')
  ) then
    return new;
  end if;

  new.is_test_order      := true;
  new.payment_method     := 'cash';
  new.payment_status     := 'pending';
  new.status             := 'driverAccepted';
  new.assigned_driver_id := v_demo_estafeta;
  -- 2026-09-13: a guarda de integridade exige tambem driver_id.
  new.driver_id          := v_demo_estafeta_user;

  return new;
end;
$function$;
