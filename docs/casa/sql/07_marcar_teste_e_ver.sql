-- PUBLICAÇÃO 2 da Casa — depois de tool/casa/teste_pedido_casa.mjs: marca o pedido de prova como TESTE pelo botão
-- do painel (admin_casa_marcar_teste), para nunca entrar em acertos nem relatórios, e lê tudo de volta.
-- Só toca nos pedidos da conta de TESTE e2e_client_a@boraapp.test com a descrição "TESTE M11…" de hoje.
-- Admin simulado como na M10 (claims do JWT da conta do painel, só dentro da transação). Idempotente.
do $pub$
declare
  v_admin constant uuid := 'c9fccf85-03ee-4efc-83bf-613f211a78ff';
  v_cliente constant uuid := 'e3126381-2252-46b8-afc0-71a4134d712d';
  v_id uuid;
begin
  perform set_config('request.jwt.claims', json_build_object(
    'sub', v_admin, 'role', 'authenticated',
    'email', (select email from auth.users where id = v_admin),
    'app_metadata', json_build_object('role', 'admin'))::text, true);
  if not public.is_admin() then raise exception 'as claims de admin nao pegaram'; end if;
  for v_id in
    select id from public.casa_pedidos
     where client_user_id = v_cliente and descricao like 'TESTE M11%' and created_at > now() - interval '1 day'
  loop
    perform public.admin_casa_marcar_teste(v_id, true);
  end loop;
end
$pub$;

select p.id, p.estado, p.payment_method, p.payment_status, p.total_cents, p.ganho_cents, p.cancel_fee_cents,
       p.is_test_order, p.respostas ->> 'material' as material,
       (select string_agg(o.resposta || ' tinha_aparelho=' || o.tinha_aparelho, '; ') from public.casa_ofertas o where o.pedido_id = p.id) as ofertas,
       (select string_agg(coalesce(e.estado_de, '-') || '>' || e.estado_para, ' | ' order by e.created_at)
          from public.casa_pedido_eventos e where e.pedido_id = p.id) as eventos
  from public.casa_pedidos p
 where p.client_user_id = 'e3126381-2252-46b8-afc0-71a4134d712d' and p.descricao like 'TESTE M11%'
   and p.created_at > now() - interval '1 day';
