-- CASA — cartão e MB Way: LIGAR (m11, 09/11/2026). Autorizado pelo Danilo a 09/11/2026: "Autorizo cartão e MB Way".
-- Pelas funções do painel (Casa > Configurações): admin_casa_guardar_definicao. Admin simulado como na M10
-- (claims do JWT da conta do painel, só dentro da transação; fica no admin_audit_log).
-- Também põe a conta de TESTE e2e_client_a como testadora da Casa SÓ para a prova sem cobrar (a Casa está
-- desligada para todos até a ficha do Danilo estar completa); 09_cartao_fim_da_prova.sql tira-a.
do $pub$
declare
  v_admin constant uuid := 'c9fccf85-03ee-4efc-83bf-613f211a78ff';
  v_teste constant text := 'e3126381-2252-46b8-afc0-71a4134d712d';
begin
  perform set_config('request.jwt.claims', json_build_object(
    'sub', v_admin, 'role', 'authenticated',
    'email', (select email from auth.users where id = v_admin),
    'app_metadata', json_build_object('role', 'admin'))::text, true);
  perform set_config('bora.agente', 'publicacao-cartao-casa', true);
  if not public.is_admin() then raise exception 'as claims de admin nao pegaram'; end if;
  perform public.admin_casa_guardar_definicao('casa_pagamento_app_ativo', 'true'::jsonb);
  perform public.admin_casa_guardar_definicao('casa_testadores', jsonb_build_array(v_teste));
end
$pub$;

select (public.casa_config() ->> 'pagamento_cartao') as pagamento_cartao,
       (select value::text from public.platform_settings where key = 'casa_pagamento_app_ativo') as interruptor,
       (select value::text from public.platform_settings where key = 'casa_testadores') as testadores,
       (select value::text from public.platform_settings where key = 'casa_enabled') as casa_enabled;
