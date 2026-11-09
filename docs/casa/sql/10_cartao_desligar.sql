-- CASA — cartão e MB Way: DESLIGAR (m11, 09/11/2026). Pelo painel: admin_casa_guardar_definicao. Pedidos novos
-- voltam a ser só em dinheiro; os já pagos continuam e as devoluções continuam a funcionar. Idempotente.
do $pub$
declare
  v_admin constant uuid := 'c9fccf85-03ee-4efc-83bf-613f211a78ff';
begin
  perform set_config('request.jwt.claims', json_build_object(
    'sub', v_admin, 'role', 'authenticated',
    'email', (select email from auth.users where id = v_admin),
    'app_metadata', json_build_object('role', 'admin'))::text, true);
  perform set_config('bora.agente', 'publicacao-cartao-casa', true);
  if not public.is_admin() then raise exception 'as claims de admin nao pegaram'; end if;
  perform public.admin_casa_guardar_definicao('casa_pagamento_app_ativo', 'false'::jsonb);
end
$pub$;

select (public.casa_config() ->> 'pagamento_cartao') as pagamento_cartao;
