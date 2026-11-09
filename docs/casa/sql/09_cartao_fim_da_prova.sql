-- CASA — cartão e MB Way: fim da prova sem cobrar (m11, 09/11/2026). Tira a conta de teste dos testadores
-- (a lista volta a vazia, como estava) e lê de volta o pedido de prova: nunca foi a nenhum profissional,
-- cancelado a 0 €, marcado como teste, sem pagamento retido.
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
  perform public.admin_casa_guardar_definicao('casa_testadores', '[]'::jsonb);
end
$pub$;

select (select value::text from public.platform_settings where key = 'casa_testadores') as testadores,
       (public.casa_config() ->> 'pagamento_cartao') as pagamento_cartao,
       p.id, p.estado, p.payment_method, p.payment_status, p.total_cents, p.cancel_fee_cents, p.is_test_order,
       p.stripe_payment_intent_id, p.reembolso_pendente,
       (select count(*) from public.casa_ofertas o where o.pedido_id = p.id) as ofertas,
       (select string_agg(coalesce(e.estado_de, '-') || '>' || e.estado_para, ' | ' order by e.created_at)
          from public.casa_pedido_eventos e where e.pedido_id = p.id) as eventos
  from public.casa_pedidos p
 where p.client_user_id = 'e3126381-2252-46b8-afc0-71a4134d712d' and p.descricao like 'TESTE M11 cartao%'
   and p.created_at > now() - interval '1 day';
