CREATE OR REPLACE FUNCTION public._pedido_demo_em_caixa_fechada()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_demo_estafeta_user constant uuid := 'dede0000-0000-4000-8000-000000000001';
begin
  if new.user_id is null then return new; end if;
  -- 27/10/2026 (boom-burger, modo demonstracao): o cliente demo da loja em demonstracao, dentro da janela,
  -- em dinheiro, faz um pedido de TESTE que segue o fluxo normal (parceiro aceita, despacho so ao estafeta
  -- demo). Nada e pre-atribuido aqui.
  if coalesce(new.payment_method, '') = 'cash' and public._modo_demo_loja(new.restaurant_id, new.user_id) then
    new.is_test_order := true;
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
  new.is_test_order := true;
  new.payment_method := 'cash';
  new.payment_status := 'pending';
  new.status := 'driverAccepted';
  -- 29/10/2026: assigned_driver_id e o USER id do estafeta (como nos pedidos reais), nao drivers.id.
  new.assigned_driver_id := v_demo_estafeta_user;
  -- 2026-09-13: a guarda de integridade exige tambem driver_id.
  new.driver_id := v_demo_estafeta_user;
  return new;
end;
$function$
;
