-- ════════════════════════════════════════════════════════════════════════════
-- PROVA — "Quando chamamos o estafeta?" (migração 20261117130000_quando_chamar_estafeta.sql)
-- Missão a3-parte2-quando-chamar-17-11 (17/11/2026).
--
-- Corre DEPOIS da migração, na MESMA transação, e acaba SEMPRE com
--   ERROR:  RESULT {"falhas": 0, ...}
-- O erro final desfaz tudo (migração incluída, se foi corrida junto): nenhum pedido fica,
-- nenhum aviso sai (o pg_net só envia no fim de uma transação que se grava).
-- Pedidos de teste: is_test_order, dinheiro, na a3-guarda (loja escondida) e num
-- restaurante de comida parceiro. O travão "loja fechada" desliga-se só nesta transação
-- (app.parceiro_chama_estafeta, o mesmo do botão "Chamar estafeta").
-- ════════════════════════════════════════════════════════════════════════════
do $prova$
declare
  c_loja      constant text := 'a3-guarda';
  c_dono      constant uuid := '0420ab5b-7f14-4cf3-aa81-7c5125699801'; -- a3teste@bora.app
  c_cliente   constant uuid := 'da324f7c-8e4b-40e4-9663-0328521732f8'; -- a3cliente@bora.app
  v_rest      text;
  v_rest_dono uuid;
  v_out       jsonb := '[]'::jsonb;
  v_falhas    int := 0;
  v_res       jsonb;
  v_o1        text := 'teste-qc-2dias-'   || substr(gen_random_uuid()::text, 1, 8);
  v_o2        text := 'teste-qc-sexta-'   || substr(gen_random_uuid()::text, 1, 8);
  v_o3        text := 'teste-qc-comida-'  || substr(gen_random_uuid()::text, 1, 8);
  v_o4        text := 'teste-qc-semhora-' || substr(gen_random_uuid()::text, 1, 8);
  v_sexta     timestamptz;
  v_estado    text;
  v_ready     timestamptz;
  v_prep      int;
  v_n         int;
  v_txt       text;
begin
  -- quem é quem
  perform set_config('app.parceiro_chama_estafeta', 'on', true);
  select r.id, coalesce(r.user_id, r.user_) into v_rest, v_rest_dono
    from public.restaurants r
   where r.category = 'restaurant' and r.is_partner and not coalesce(r.coming_soon, false)
     and not coalesce(r.so_lista_permissao, false)
     and coalesce(r.user_id, r.user_) is not null
   order by r.id limit 1;

  -- sexta-feira às 15:00 (Lisboa) mais próxima no futuro
  v_sexta := ((date_trunc('week', now() at time zone 'Europe/Lisbon') + interval '4 days 15 hours')
              at time zone 'Europe/Lisbon');
  if v_sexta <= now() + interval '1 hour' then v_sexta := v_sexta + interval '7 days'; end if;

  -- pedidos de teste
  insert into public.orders (id, user_id, restaurant_id, service_type, is_partner_store, status,
                             payment_method, payment_status, is_test_order, vendor_name, price)
  values (v_o1, c_cliente, c_loja, 'restaurant', true, 'created', 'cash', 'pending', true, 'A3 Guarda', 5),
         (v_o2, c_cliente, c_loja, 'restaurant', true, 'created', 'cash', 'pending', true, 'A3 Guarda', 5),
         (v_o4, c_cliente, c_loja, 'restaurant', true, 'created', 'cash', 'pending', true, 'A3 Guarda', 5);
  if v_rest is not null then
    insert into public.orders (id, user_id, restaurant_id, service_type, is_partner_store, status,
                               payment_method, payment_status, is_test_order, vendor_name, price)
    values (v_o3, c_cliente, v_rest, 'restaurant', true, 'created', 'cash', 'pending', true, 'Restaurante', 5);
  end if;

  -- ── 1. A3 aceita com "2 dias" ─────────────────────────────────────────────
  perform set_config('request.jwt.claim.sub', c_dono::text, true);
  perform set_config('request.jwt.claims', json_build_object('sub', c_dono, 'role', 'authenticated')::text, true);
  v_res := public.partner_aceitar_pedido(v_o1, null, now() + interval '2 days');
  select status::text, ready_at_promised, prep_time_minutes into v_estado, v_ready, v_prep from public.orders where id = v_o1;
  v_out := v_out || jsonb_build_object('caso', '1 A3 aceita 2 dias', 'res', v_res,
    'ok', (v_res->>'ok')::boolean and v_estado = 'preparing' and v_prep is null
          and abs(extract(epoch from v_ready - (now() + interval '2 days'))) < 5);

  -- ── 2. A3 aceita com "sexta às 15:00" ─────────────────────────────────────
  v_res := public.partner_aceitar_pedido(v_o2, null, v_sexta);
  select status::text, ready_at_promised into v_estado, v_ready from public.orders where id = v_o2;
  v_out := v_out || jsonb_build_object('caso', '2 A3 aceita sexta 15:00', 'res', v_res,
    'ok', (v_res->>'ok')::boolean and v_estado = 'preparing' and v_ready = v_sexta
          and v_res->>'pronto_texto' like '%15:00');

  -- ── 3. Mais de 15 dias é recusado ─────────────────────────────────────────
  v_res := public.partner_aceitar_pedido(v_o4, null, now() + interval '16 days');
  select status::text into v_estado from public.orders where id = v_o4;
  v_out := v_out || jsonb_build_object('caso', '3 16 dias recusado', 'res', v_res,
    'ok', v_res->>'error' = 'invalid_pronto_em' and v_estado = 'created');

  -- ── 4. O despacho NÃO chama já (fica dias em preparação) ──────────────────
  perform public.partner_auto_dispatch_ready_orders();
  select count(*) into v_n from public.orders where id in (v_o1, v_o2) and status::text = 'preparing';
  v_out := v_out || jsonb_build_object('caso', '4 despacho espera', 'ok', v_n = 2);

  -- ── 5. Mudar a hora: sem hora recusa; 3 dias aceita e avisa o cliente; 20 dias recusa ─
  v_res := public.partner_set_ready_at(v_o2, null);
  v_out := v_out || jsonb_build_object('caso', '5a tirar hora recusado', 'res', v_res,
    'ok', v_res->>'error' = 'hora_obrigatoria');
  v_res := public.partner_set_ready_at(v_o2, now() + interval '3 days');
  select count(*) into v_n from public.in_app_notifications
   where user_id = c_cliente and related_id = v_o2 and kind = 'pedido_hora_mudou';
  v_out := v_out || jsonb_build_object('caso', '5b mudar para 3 dias + aviso', 'res', v_res,
    'ok', (v_res->>'ok')::boolean and v_n = 1);
  v_res := public.partner_set_ready_at(v_o2, now() + interval '20 days');
  v_out := v_out || jsonb_build_object('caso', '5c 20 dias recusado', 'res', v_res,
    'ok', v_res->>'error' = 'hora_invalida');

  -- ── 6. Perto da hora: o despacho chama (antecedência 8 min) e avisa o cliente ─
  perform set_config('request.jwt.claims', '', true);
  perform set_config('request.jwt.claim.sub', '', true);
  update public.orders set ready_at_promised = now() + interval '7 minutes' where id = v_o1;
  perform public.partner_auto_dispatch_ready_orders();
  select status::text into v_estado from public.orders where id = v_o1;
  select count(*) into v_n from public.in_app_notifications
   where user_id = c_cliente and related_id = v_o1 and kind = 'pedido_estafeta_chamado';
  v_out := v_out || jsonb_build_object('caso', '6 a 7 min da hora: chama + aviso',
    'estado', v_estado, 'avisos', v_n, 'ok', v_estado = 'callingDriver' and v_n = 1);

  -- e a 9 min ainda não
  update public.orders set ready_at_promised = now() + interval '9 minutes' where id = v_o2;
  perform public.partner_auto_dispatch_ready_orders();
  select status::text into v_estado from public.orders where id = v_o2;
  v_out := v_out || jsonb_build_object('caso', '6b a 9 min ainda espera', 'estado', v_estado,
    'ok', v_estado = 'preparing');

  -- ── 7. Restaurante de comida: tudo como hoje ─────────────────────────────
  if v_rest is null then
    v_out := v_out || jsonb_build_object('caso', '7 restaurante', 'ok', true, 'nota', 'SALTADO: sem restaurante parceiro com dono');
  else
    perform set_config('request.jwt.claim.sub', v_rest_dono::text, true);
    perform set_config('request.jwt.claims', json_build_object('sub', v_rest_dono, 'role', 'authenticated')::text, true);
    v_res := public.partner_aceitar_pedido(v_o3, null, now() + interval '2 days');
    v_out := v_out || jsonb_build_object('caso', '7a restaurante nao marca dias', 'res', v_res,
      'ok', v_res->>'error' = 'so_lojas_nao_comida');
    v_res := public.partner_aceitar_pedido(v_o3, 200);
    v_out := v_out || jsonb_build_object('caso', '7b restaurante 200 min recusado', 'res', v_res,
      'ok', v_res->>'error' = 'invalid_prep_minutes');
    v_res := public.partner_aceitar_pedido(v_o3, 30);   -- chamada antiga, 2 argumentos
    select status::text, prep_time_minutes into v_estado, v_prep from public.orders where id = v_o3;
    v_out := v_out || jsonb_build_object('caso', '7c restaurante 30 min como hoje', 'res', v_res,
      'ok', (v_res->>'ok')::boolean and v_estado = 'preparing' and v_prep = 30);
    v_res := public.partner_set_ready_at(v_o3, now() + interval '5 hours');
    v_out := v_out || jsonb_build_object('caso', '7d restaurante 5 h recusado (4 h como hoje)', 'res', v_res,
      'ok', v_res->>'error' = 'hora_invalida');
    -- despacho do restaurante ignora a promessa: conta aceite + 30 − 8
    perform set_config('request.jwt.claims', '', true);
    perform set_config('request.jwt.claim.sub', '', true);
    update public.orders set ready_at_promised = now() + interval '3 hours' where id = v_o3;
    perform public.partner_auto_dispatch_ready_orders();
    select status::text into v_estado from public.orders where id = v_o3;
    v_out := v_out || jsonb_build_object('caso', '7e restaurante aceite agora: espera 22 min', 'estado', v_estado,
      'ok', v_estado = 'preparing');
    update public.orders set accepted_at = now() - interval '25 minutes' where id = v_o3;
    perform public.partner_auto_dispatch_ready_orders();
    select status::text into v_estado from public.orders where id = v_o3;
    select count(*) into v_n from public.in_app_notifications
     where related_id = v_o3 and kind = 'pedido_estafeta_chamado';
    v_out := v_out || jsonb_build_object('caso', '7f restaurante aceite ha 25 min: chama como hoje, sem aviso novo',
      'estado', v_estado, 'avisos', v_n, 'ok', v_estado = 'callingDriver' and v_n = 0);
  end if;

  -- ── 8. "Pedido órfão" não conta o pedido marcado para daqui a dias ─────────
  update public.orders set created_at = now() - interval '15 minutes' where id = v_o2;
  update public.orders set ready_at_promised = now() + interval '2 days' where id = v_o2;
  perform public._cron_check_orphan_orders();
  select count(*) into v_n from public.admin_notifications
   where event_type = 'order_orphan' and entity_id = v_o2;
  v_out := v_out || jsonb_build_object('caso', '8 sem alerta de orfao', 'ok', v_n = 0);

  -- ── 9. Pedido de teste marcado para daqui a dias não é fechado às 6 h ──────
  update public.orders set created_at = now() - interval '7 hours' where id in (v_o2, v_o4);
  perform public.mover_pedidos_demo();
  select status::text into v_estado from public.orders where id = v_o2;
  select status::text into v_txt from public.orders where id = v_o4;
  v_out := v_out || jsonb_build_object('caso', '9 teste 2 dias vive; teste sem hora fecha',
    'o2', v_estado, 'o4', v_txt, 'ok', v_estado = 'preparing' and v_txt = 'cancelled');

  -- ── 10. Textos e permissões ──────────────────────────────────────────────
  -- 20/11/2026 é sexta (21/11 é sábado). Depois de 18/11 vira "amanhã"/"hoje": não conta.
  v_txt := public._texto_dia_hora_lisboa(timestamptz '2026-11-20 15:00:00 Europe/Lisbon');
  v_out := v_out || jsonb_build_object('caso', '10a texto sexta', 'txt', v_txt,
    'ok', now() < timestamptz '2026-11-19 00:00 Europe/Lisbon' and v_txt = 'sexta, 20/11, às 15:00'
          or now() >= timestamptz '2026-11-19 00:00 Europe/Lisbon');
  v_txt := public._texto_dia_hora_lisboa(now() + interval '1 day');
  v_out := v_out || jsonb_build_object('caso', '10b texto amanha', 'txt', v_txt, 'ok', v_txt like 'amanhã às %');
  v_out := v_out || jsonb_build_object('caso', '10c anon sem acesso, authenticated com acesso',
    'ok', not has_function_privilege('anon', 'public.partner_aceitar_pedido(text,integer,timestamptz)', 'execute')
          and has_function_privilege('authenticated', 'public.partner_aceitar_pedido(text,integer,timestamptz)', 'execute')
          and not has_function_privilege('authenticated', 'public._loja_nao_comida(text)', 'execute')
          and not has_function_privilege('anon', 'public._pedido_avisar_cliente(text,text,text,text)', 'execute')
          and to_regprocedure('public.partner_aceitar_pedido(text,integer)') is null);

  select count(*) into v_falhas from jsonb_array_elements(v_out) e where not coalesce((e->>'ok')::boolean, false);
  raise exception 'RESULT %', jsonb_build_object('falhas', v_falhas, 'casos', jsonb_array_length(v_out), 'detalhe', v_out)::text;
end
$prova$;
