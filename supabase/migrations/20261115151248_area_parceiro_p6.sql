-- Texto aplicado em produção a 15/11/2026 (schema_migrations.statements, versão 20261115151248); antes não estava em supabase/migrations.
-- No servidor, statements guardou um carregador (copiado abaixo, comentado) que executou a cópia de
-- docs/propostas/painel-admin-15-11/P6_parceiro_admin.PROPOSTA.sql (commit 2d988f30; net._http_response 157807;
-- sha256 8b29f51f164585d4563414b856cd1d5b4befd15c8cc11bdf7b1fe72521d04f92) com uma guarda a mais: recusar uma
-- reserva PAGA dá erro (ainda não devolve os 3 EUR). O texto depois do carregador é exatamente o que correu.
--
-- >>> carregador gravado em schema_migrations.statements (versão 20261115151248):
-- do $$
-- declare
--   v_sql text;
--   v_anchor text := $q$v_new_status := case when p_aceitar then 'approved' else 'rejected_refunded' end;$q$;
--   v_guard text := $q$-- 15/11/2026 Claude.ai: recusar reserva PAGA ainda nao tem reembolso automatico dos 3 EUR
--   if not p_aceitar and coalesce(v_rsv.prepayment_cents, 0) > 0 then
--     raise exception 'reserva_paga: recusar ainda nao devolve os 3 EUR; usa Cancelar reserva (devolve o dinheiro)' using errcode = '22023';
--   end if;
--
--   $q$;
-- begin
--   select content into v_sql from net._http_response where id = 157807;
--   if v_sql is null or encode(sha256(convert_to(v_sql,'UTF8')),'hex') <> '8b29f51f164585d4563414b856cd1d5b4befd15c8cc11bdf7b1fe72521d04f92' then
--     raise exception 'sha256 nao confere ou resposta vazia';
--   end if;
--   if (length(v_sql) - length(replace(v_sql, v_anchor, ''))) / length(v_anchor) <> 1 then
--     raise exception 'ancora da reserva nao e unica';
--   end if;
--   v_sql := replace(v_sql, v_anchor, v_guard || v_anchor);
--   execute v_sql;
-- end $$;
-- <<< fim do carregador; a seguir, o que ele executou.

-- =====================================================================================
-- P6 — ÁREA DO PARCEIRO NO PAINEL: o admin faz pela loja o que o parceiro faz na app
-- PROPOSTA (nada aplicado). 15/11/2026, missão painel-admin-15-11.
-- Projeto Supabase: ojykpzwqrtusfeakzrna. Autor: agente backend-supabase (Claude Code).
-- =====================================================================================
--
-- O QUE ISTO É
--   O ecrã "Área do parceiro" (lib/screens/admin/admin_area_parceiro_screen.dart +
--   lib/services/admin_area_parceiro_service.dart) mostra os botões "Aceitar pedido",
--   "Recusar pedido", "Marcar pronto", "Pronto para retirada" e "Decidir reserva"
--   DESLIGADOS com a frase "Precisa de uma função nova no servidor (proposta enviada)".
--   Motivo: as funções do parceiro só aceitam o dono da loja:
--     • partner_accept_order / partner_reject_order / partner_mark_ready usam
--       _partner_owns_order(p_order_id, auth.uid()) — exige r.user_id/r.user_ = quem chama;
--     • partner_takeaway_accept / _mark_ready / _mark_picked_up e
--       partner_decide_reservation exigem restaurants.user_ = auth.uid();
--     • partner_mark_arrival exige auth.users.email = restaurants.email.
--   Nenhuma delas conhece is_admin(). (Ao contrário de partner_set_ready_at,
--   partner_pausar_loja e partner_set_busy, que já aceitam o admin por _parceiro_pode_loja.)
--
--   Este ficheiro propõe 7 funções admin_* que correm EXATAMENTE as mesmas verificações e
--   as mesmas mudanças de estado das funções do parceiro (lidas do servidor a 15/11/2026
--   com pg_get_functiondef), trocando só a pergunta "és o dono?" por "és admin?".
--   Nenhuma faz UPDATE a orders fora dessa lógica. Cada uma grava no admin_audit_log
--   (log_admin_action, entidade = a loja) com o pedido/reserva, o antes, o depois e o motivo.
--
-- COMO SE LÊ CADA SECÇÃO
--   • Secções 1 a 4 (pedidos): "ciclo do pedido / despacho — precisa de ordem explícita do
--     Danilo". Mudar o estado de um pedido dispara gatilhos de despacho e avisos ao cliente.
--   • Secção 5 (reservas): "dinheiro — precisa de AUTORIZO". Marcar a chegada move os 3 €
--     pré-pagos (crédito de 2 € ao cliente + 2 € devidos ao parceiro). Recusar deixa o
--     reembolso dos 3 € marcado como "em curso".
--   • Secção 6 (lista): só leitura.
--
-- EFEITOS SECUNDÁRIOS ENCONTRADOS (gatilhos em public.orders, lidos de pg_trigger a 15/11)
--   created → preparing (aceitar):
--     - enforce_payment_before_preparing: cartão/MB WAY sem payment_status='paid' → erro
--       PAYMENT_NOT_CONFIRMED (igual para o parceiro).
--     - trg_push_cliente_fase_pedido + trg_fila_avisar_cliente: aviso ao cliente.
--     - _record_order_status_event: linha em order_status_events com source =
--       app.order_transition_source (aqui fica 'admin_loja_aceitar_pedido').
--   preparing → callingDriver (marcar pronto):
--     - trg_dispatch_on_calling_driver: chama a Edge Function dispatch-engine (DESPACHO).
--     - trg_zy_preassign_to_offer, trg_set_dispatch_calling_since, trg_fila_0_em_curso.
--     - trg_guard_dispatch_payment: exige pagamento confirmado.
--   created → rejected (recusar):
--     - trg_orders_devolver_tokens: os tokens usados VOLTAM ao cliente (devolver_tokens_do_pedido).
--     - trg_orders_gorjeta_acompanha: gorjetas ainda não cobradas ficam canceladas.
--     - trg_checkin_premio_pedido_cancelado: prémio do check-in volta.
--     - trg_reembolso_cancelado_pelo_sistema NÃO atua (só quando cancellation_initiator='system').
--       → Um pedido PAGO por cartão/MB WAY recusado fica com refund_status NULL: o reembolso
--       não é automático. Não encontrei cron (cron.job), Edge Function nem gatilho que o faça.
--       É assim hoje também para o parceiro. Dinheiro: aviso no relatório.
--   takeaway preparing → readyForPickup (pronto para retirada): aviso ao cliente (push).
--   takeaway readyForPickup → delivered (entregue no balcão):  *** DINHEIRO ***
--     - orders_financial_split (loja parceira paga), orders_post_to_ledger, trg_award_tokens_on_delivery,
--       orders_cash_settlement / orders_auto_confirm_cod (dinheiro vivo), zzzz_bora_fatura_on_delivered
--       (fatura), zzzzz_recibo_cliente_on_delivered (recibo), trg_referral_reward.
--     - trg_orders_maior_18_guarda: bloqueia a entrega de pedidos +18 sem documento confirmado,
--       MAS deixa passar quando quem chama é admin. Para a função admin se comportar como a do
--       parceiro, a verificação +18 é repetida dentro de admin_loja_retirada('entregue').
--     - _guard_order_driver_state: pedidos takeaway não precisam de estafeta (igual ao parceiro).
--   Guardas que não mudam com o admin:
--     - a00_pedido_cliente_guarda (_pedido_cliente_guarda) só atua quando current_user é
--       'authenticated'/'anon'; dentro de SECURITY DEFINER (dono postgres, como as funções do
--       parceiro) o current_user é postgres → não atua, tal como hoje para o parceiro.
--     - orders_financial_lock (enforce_financial_immutability): só colunas de dinheiro; estas
--       funções não lhes tocam.
--   Reservas (gatilhos em public.reservations):
--     - partner_decide_reservation: aceitar → 'approved'; recusar → 'rejected_refunded' + push ao
--       cliente "Reembolso em curso". Quem devolve os 3 €? Não encontrei função SQL, gatilho,
--       cron nem Edge Function que faça o refund Stripe para 'rejected_refunded' (a app do
--       parceiro só chama a RPC). O caminho admin já provado COM reembolso é a Edge Function
--       admin-cancel-reservation → admin_cancel_reservation_on_behalf_of + stripe.refunds.create.
--     - partner_mark_arrival: 'arrived' + INSERT restaurant_menu_credits (crédito ao cliente) +
--       INSERT partner_reservation_payouts (Bora deve ao parceiro) + aviso in-app + log.
--       platform_settings lidas a 15/11: reservation_partner_payout_cents=200,
--       reservation_credit_expiry_days=30.
--
-- AUDITORIA
--   log_admin_action(p_action_type text, p_entity_type text, p_entity_id text, p_details jsonb):
--   _audit_chamada_direta_nao_admin() devolve false para admins → grava sempre; nunca levanta
--   erro (apanha a exceção e faz RAISE WARNING). entity_type='restaurant', entity_id = id da loja,
--   details = {order_id|reservation_id, antes, depois, motivo, origem}.
--
-- REGRAS COMUNS A TODAS AS FUNÇÕES
--   SECURITY DEFINER · SET search_path TO 'public' · 1.ª instrução: is_admin() ou erro 42501 ·
--   motivo com pelo menos 3 letras · REVOKE ALL FROM public, anon · GRANT EXECUTE TO authenticated.
--
-- COMO APLICAR (só com ordem do Danilo)
--   Copiar para supabase/migrations/<AAAAMMDDHHMMSS>_p6_area_parceiro_admin.sql e aplicar
--   (regra 5: migração aplicada em produção fica também no repo). Depois correr as PROVAS no fim.
--   Rollback comentado no fim.
-- =====================================================================================


-- =====================================================================================
-- 1. ACEITAR PEDIDO (restaurante parceiro)
--    ciclo do pedido / despacho: precisa de ordem explícita do Danilo
--    Espelha partner_aceitar_pedido(p_order_id, p_prep_minutes) → partner_accept_order(p_order_id):
--    minutos entre 5 e 120 (ou nulo) · pedido existe (FOR UPDATE) · loja elegível (a parte de
--    _partner_owns_order que não é "ser o dono": parceira, ativa, aprovada) · is_partner_store e
--    service_type='restaurant' · 'preparing' é idempotente · só sai de 'created' ·
--    UPDATE status='preparing' com app.order_transition_source · prep_time_minutes se vier.
-- =====================================================================================
create or replace function public.admin_loja_aceitar_pedido(
  p_order_id     text,
  p_prep_minutes integer,
  p_motivo       text
)
returns jsonb
language plpgsql
security definer
set search_path to 'public'
as $fn$
declare
  v_order public.orders%rowtype;
  v_rest  public.restaurants%rowtype;
  v_rows  integer;
  v_antes text;
begin
  if not public.is_admin() then raise exception 'admin_required' using errcode = '42501'; end if;

  if length(regexp_replace(coalesce(p_motivo, ''), '[^[:alpha:]]', '', 'g')) < 3 then
    raise exception 'motivo_obrigatorio: escreve pelo menos 3 letras' using errcode = '22023';
  end if;

  -- igual a partner_aceitar_pedido
  if p_prep_minutes is not null and (p_prep_minutes < 5 or p_prep_minutes > 120) then
    return jsonb_build_object('ok', false, 'error', 'invalid_prep_minutes');
  end if;

  -- igual a partner_accept_order
  select * into v_order from public.orders where id = p_order_id for update;
  if not found then
    return jsonb_build_object('ok', false, 'error', 'order_not_found');
  end if;

  -- _partner_owns_order sem a parte do dono (quem chama é o admin): a loja tem de ser
  -- parceira, ativa e aprovada; a ligação ao pedido é a mesma (restaurant_id ou vendor_name).
  select r.* into v_rest
    from public.restaurants r
   where (r.id = v_order.restaurant_id
          or (v_order.restaurant_id is null and r.name = v_order.vendor_name))
     and coalesce(r.is_partner, false)
     and coalesce(r.is_active_admin, true)
     and r.approval_status = 'approved'
   limit 1;
  if not found then
    return jsonb_build_object('ok', false, 'error', 'forbidden', 'detalhe', 'loja_nao_elegivel');
  end if;

  if not coalesce(v_order.is_partner_store, false) or v_order.service_type <> 'restaurant' then
    return jsonb_build_object('ok', false, 'error', 'wrong_order_type');
  end if;
  if v_order.status = 'preparing' then
    return jsonb_build_object('ok', true, 'status', 'preparing', 'idempotent', true);
  end if;
  if v_order.status <> 'created' then
    return jsonb_build_object('ok', false, 'error', 'invalid_status', 'status', v_order.status);
  end if;

  v_antes := v_order.status;
  perform set_config('app.order_transition_source', 'admin_loja_aceitar_pedido', true);
  update public.orders set status = 'preparing'
   where id = p_order_id and status = 'created';
  get diagnostics v_rows = row_count;
  if v_rows <> 1 then
    return jsonb_build_object('ok', false, 'error', 'concurrent_transition');
  end if;

  -- igual a partner_aceitar_pedido: minutos de preparo só depois de aceitar
  if p_prep_minutes is not null then
    update public.orders set prep_time_minutes = p_prep_minutes
     where id = p_order_id and status = 'preparing';
  end if;

  perform public.log_admin_action(
    'admin_loja_aceitar_pedido', 'restaurant', v_rest.id,
    jsonb_build_object('order_id', p_order_id, 'antes', v_antes, 'depois', 'preparing',
                       'prep_time_minutes', p_prep_minutes, 'motivo', p_motivo,
                       'origem', 'painel: área do parceiro'));

  return jsonb_build_object('ok', true, 'status', 'preparing',
                            'prep_time_minutes', p_prep_minutes, 'admin', true);
end;
$fn$;

revoke all on function public.admin_loja_aceitar_pedido(text, integer, text) from public, anon;
grant execute on function public.admin_loja_aceitar_pedido(text, integer, text) to authenticated;


-- =====================================================================================
-- 2. RECUSAR PEDIDO (restaurante parceiro)
--    ciclo do pedido / despacho: precisa de ordem explícita do Danilo
--    DINHEIRO (aviso): ao passar a 'rejected' o gatilho trg_orders_devolver_tokens devolve os
--    tokens ao cliente e trg_orders_gorjeta_acompanha cancela gorjetas não cobradas. O reembolso
--    de cartão/MB WAY NÃO é automático (ver cabeçalho) — igual ao que acontece hoje ao parceiro.
--    Espelha partner_reject_order(p_order_id): pedido existe (FOR UPDATE) · loja elegível ·
--    'rejected' idempotente · só sai de 'created' · UPDATE status='rejected'.
--    (Como no parceiro, o motivo não fica no pedido: fica no admin_audit_log.)
-- =====================================================================================
create or replace function public.admin_loja_recusar_pedido(
  p_order_id text,
  p_motivo   text
)
returns jsonb
language plpgsql
security definer
set search_path to 'public'
as $fn$
declare
  v_order public.orders%rowtype;
  v_rest  public.restaurants%rowtype;
  v_rows  integer;
  v_antes text;
begin
  if not public.is_admin() then raise exception 'admin_required' using errcode = '42501'; end if;

  if length(regexp_replace(coalesce(p_motivo, ''), '[^[:alpha:]]', '', 'g')) < 3 then
    raise exception 'motivo_obrigatorio: escreve pelo menos 3 letras' using errcode = '22023';
  end if;

  select * into v_order from public.orders where id = p_order_id for update;
  if not found then
    return jsonb_build_object('ok', false, 'error', 'order_not_found');
  end if;

  select r.* into v_rest
    from public.restaurants r
   where (r.id = v_order.restaurant_id
          or (v_order.restaurant_id is null and r.name = v_order.vendor_name))
     and coalesce(r.is_partner, false)
     and coalesce(r.is_active_admin, true)
     and r.approval_status = 'approved'
   limit 1;
  if not found then
    return jsonb_build_object('ok', false, 'error', 'forbidden', 'detalhe', 'loja_nao_elegivel');
  end if;

  if v_order.status = 'rejected' then
    return jsonb_build_object('ok', true, 'status', 'rejected', 'idempotent', true);
  end if;
  if v_order.status <> 'created' then
    return jsonb_build_object('ok', false, 'error', 'invalid_status', 'status', v_order.status);
  end if;

  v_antes := v_order.status;
  perform set_config('app.order_transition_source', 'admin_loja_recusar_pedido', true);
  update public.orders set status = 'rejected'
   where id = p_order_id and status = 'created';
  get diagnostics v_rows = row_count;
  if v_rows <> 1 then
    return jsonb_build_object('ok', false, 'error', 'concurrent_transition');
  end if;

  perform public.log_admin_action(
    'admin_loja_recusar_pedido', 'restaurant', v_rest.id,
    jsonb_build_object('order_id', p_order_id, 'antes', v_antes, 'depois', 'rejected',
                       'payment_method', v_order.payment_method,
                       'payment_status', v_order.payment_status,
                       'motivo', p_motivo, 'origem', 'painel: área do parceiro'));

  return jsonb_build_object('ok', true, 'status', 'rejected', 'admin', true,
                            'aviso', case when coalesce(v_order.payment_method, '') <> 'cash'
                                               and v_order.payment_status = 'paid'
                                          then 'pedido pago: reembolso do cliente nao e automatico'
                                          else null end);
end;
$fn$;

revoke all on function public.admin_loja_recusar_pedido(text, text) from public, anon;
grant execute on function public.admin_loja_recusar_pedido(text, text) to authenticated;


-- =====================================================================================
-- 3. MARCAR PRONTO (restaurante parceiro) → chama estafeta
--    ciclo do pedido / despacho: precisa de ordem explícita do Danilo
--    Espelha partner_mark_ready(p_order_id): pedido existe (FOR UPDATE) · loja elegível ·
--    is_partner_store e service_type='restaurant' · idempotente se já em callingDriver/
--    driverAccepted/pickedUp/onTheWay/delivered · só sai de 'preparing' · não-dinheiro vivo
--    exige payment_status='paid' · UPDATE status='callingDriver' (dispara dispatch-engine).
-- =====================================================================================
create or replace function public.admin_loja_marcar_pronto(
  p_order_id text,
  p_motivo   text
)
returns jsonb
language plpgsql
security definer
set search_path to 'public'
as $fn$
declare
  v_order public.orders%rowtype;
  v_rest  public.restaurants%rowtype;
  v_rows  integer;
  v_antes text;
begin
  if not public.is_admin() then raise exception 'admin_required' using errcode = '42501'; end if;

  if length(regexp_replace(coalesce(p_motivo, ''), '[^[:alpha:]]', '', 'g')) < 3 then
    raise exception 'motivo_obrigatorio: escreve pelo menos 3 letras' using errcode = '22023';
  end if;

  select * into v_order from public.orders where id = p_order_id for update;
  if not found then
    return jsonb_build_object('ok', false, 'error', 'order_not_found');
  end if;

  select r.* into v_rest
    from public.restaurants r
   where (r.id = v_order.restaurant_id
          or (v_order.restaurant_id is null and r.name = v_order.vendor_name))
     and coalesce(r.is_partner, false)
     and coalesce(r.is_active_admin, true)
     and r.approval_status = 'approved'
   limit 1;
  if not found then
    return jsonb_build_object('ok', false, 'error', 'forbidden', 'detalhe', 'loja_nao_elegivel');
  end if;

  if not coalesce(v_order.is_partner_store, false) or v_order.service_type <> 'restaurant' then
    return jsonb_build_object('ok', false, 'error', 'wrong_order_type');
  end if;
  if v_order.status in ('callingDriver', 'driverAccepted', 'pickedUp', 'onTheWay', 'delivered') then
    return jsonb_build_object('ok', true, 'status', v_order.status, 'idempotent', true);
  end if;
  if v_order.status <> 'preparing' then
    return jsonb_build_object('ok', false, 'error', 'invalid_status', 'status', v_order.status);
  end if;
  if coalesce(v_order.payment_method, '') <> 'cash' and v_order.payment_status <> 'paid' then
    return jsonb_build_object('ok', false, 'error', 'payment_not_confirmed');
  end if;

  v_antes := v_order.status;
  perform set_config('app.order_transition_source', 'admin_loja_marcar_pronto', true);
  update public.orders set status = 'callingDriver'
   where id = p_order_id and status = 'preparing';
  get diagnostics v_rows = row_count;
  if v_rows <> 1 then
    return jsonb_build_object('ok', false, 'error', 'concurrent_transition');
  end if;

  perform public.log_admin_action(
    'admin_loja_marcar_pronto', 'restaurant', v_rest.id,
    jsonb_build_object('order_id', p_order_id, 'antes', v_antes, 'depois', 'callingDriver',
                       'motivo', p_motivo, 'origem', 'painel: área do parceiro'));

  return jsonb_build_object('ok', true, 'status', 'callingDriver', 'admin', true);
end;
$fn$;

revoke all on function public.admin_loja_marcar_pronto(text, text) from public, anon;
grant execute on function public.admin_loja_marcar_pronto(text, text) to authenticated;


-- =====================================================================================
-- 4. RETIRADA NO BALCÃO (takeaway): p_passo em ('aceitar','pronto','entregue')
--    ciclo do pedido / despacho: precisa de ordem explícita do Danilo
--    Passo 'entregue' = DINHEIRO: precisa de AUTORIZO (passa a 'delivered' e disparam o split
--    financeiro, o livro, os tokens, a fatura e o recibo — os mesmos gatilhos de qualquer entrega).
--    Espelha:
--      'aceitar'  → partner_takeaway_accept(p_order_id, p_prep_minutes): minutos em
--                   (3,5,10,15,20,30,45,60) · takeaway · estado em created/preparing ·
--                   UPDATE status='preparing', takeaway_prep_minutes.
--                   p_prep_minutes é opcional aqui: se vier nulo usa
--                   restaurants.takeaway_default_prep_minutes (ou 15) e valida na mesma lista.
--      'pronto'   → partner_takeaway_mark_ready(p_order_id): só de 'preparing' ·
--                   UPDATE status='readyForPickup', takeaway_ready_at=now() · devolve pickup_code.
--      'entregue' → partner_takeaway_mark_picked_up(p_order_id): de readyForPickup/preparing ·
--                   UPDATE status='delivered', takeaway_picked_up_at=now(), delivered_at=now().
--                   + verificação +18 repetida aqui (o gatilho deixa o admin passar; o parceiro não).
--    As funções do parceiro levantam exceções (não devolvem ok=false): mantém-se o mesmo estilo
--    e as mesmas mensagens para a app tratar igual.
-- =====================================================================================
create or replace function public.admin_loja_retirada(
  p_order_id     text,
  p_passo        text,
  p_motivo       text,
  p_prep_minutes integer default null
)
returns jsonb
language plpgsql
security definer
set search_path to 'public'
as $fn$
declare
  v_order   record;
  v_rest    public.restaurants%rowtype;
  v_minutos integer;
  v_antes   text;
  v_depois  text;
  v_res     jsonb;
begin
  if not public.is_admin() then raise exception 'admin_required' using errcode = '42501'; end if;

  if length(regexp_replace(coalesce(p_motivo, ''), '[^[:alpha:]]', '', 'g')) < 3 then
    raise exception 'motivo_obrigatorio: escreve pelo menos 3 letras' using errcode = '22023';
  end if;
  if p_passo not in ('aceitar', 'pronto', 'entregue') then
    raise exception 'passo_invalido: usa aceitar, pronto ou entregue' using errcode = '22023';
  end if;

  select id, status, service_type, restaurant_id, is_partner_store, takeaway_pickup_code,
         has_age_restricted
    into v_order
    from public.orders where id = p_order_id for update;
  if not found then raise exception 'order_not_found'; end if;
  if v_order.service_type <> 'takeaway' then raise exception 'not_takeaway_order'; end if;

  -- o parceiro prova que é o dono de orders.restaurant_id; o admin só precisa que a loja exista
  select r.* into v_rest from public.restaurants r where r.id = v_order.restaurant_id;
  if not found then raise exception 'not_your_order'; end if;

  v_antes := v_order.status;

  if p_passo = 'aceitar' then
    v_minutos := coalesce(p_prep_minutes, v_rest.takeaway_default_prep_minutes, 15);
    if v_minutos not in (3, 5, 10, 15, 20, 30, 45, 60) then
      raise exception 'invalid_prep_minutes';
    end if;
    if v_order.status not in ('created', 'preparing') then
      raise exception 'order_already_processed: %', v_order.status;
    end if;
    perform set_config('app.order_transition_source', 'admin_loja_retirada:aceitar', true);
    update public.orders set
      status                = 'preparing',
      takeaway_prep_minutes = v_minutos
    where id = p_order_id;
    v_depois := 'preparing';
    v_res := jsonb_build_object('ok', true, 'order_id', p_order_id, 'prep_minutes', v_minutos,
                                'estimated_ready_at', now() + (v_minutos || ' minutes')::interval);

  elsif p_passo = 'pronto' then
    if v_order.status <> 'preparing' then
      raise exception 'order_not_preparing: %', v_order.status;
    end if;
    perform set_config('app.order_transition_source', 'admin_loja_retirada:pronto', true);
    update public.orders set
      status            = 'readyForPickup',
      takeaway_ready_at = now()
    where id = p_order_id;
    v_depois := 'readyForPickup';
    v_res := jsonb_build_object('ok', true, 'order_id', p_order_id,
                                'pickup_code', v_order.takeaway_pickup_code, 'ready_at', now());

  else -- 'entregue'  *** DINHEIRO: precisa de AUTORIZO ***
    if v_order.status not in ('readyForPickup', 'preparing') then
      raise exception 'order_not_ready: %', v_order.status;
    end if;
    -- mesma regra do gatilho trg_orders_maior_18_guarda, que para o admin não bloqueia
    if coalesce(v_order.has_age_restricted, false)
       and not exists (select 1 from public.order_age_checks c
                        where c.order_id = p_order_id and c.status = 'confirmado') then
      raise exception 'AGE_CHECK_REQUIRED: este pedido tem produtos para maiores de 18. Confirma o documento do cliente antes de entregar.'
        using errcode = 'P0001';
    end if;
    perform set_config('app.order_transition_source', 'admin_loja_retirada:entregue', true);
    update public.orders set
      status                = 'delivered',
      takeaway_picked_up_at = now(),
      delivered_at          = now()
    where id = p_order_id;
    v_depois := 'delivered';
    v_res := jsonb_build_object('ok', true, 'order_id', p_order_id, 'picked_up_at', now());
  end if;

  perform public.log_admin_action(
    'admin_loja_retirada_' || p_passo, 'restaurant', v_rest.id,
    jsonb_build_object('order_id', p_order_id, 'passo', p_passo, 'antes', v_antes, 'depois', v_depois,
                       'prep_minutes', v_minutos, 'motivo', p_motivo,
                       'origem', 'painel: área do parceiro'));

  return v_res || jsonb_build_object('admin', true, 'passo', p_passo);
end;
$fn$;

revoke all on function public.admin_loja_retirada(text, text, text, integer) from public, anon;
grant execute on function public.admin_loja_retirada(text, text, text, integer) to authenticated;


-- =====================================================================================
-- 5. RESERVAS DE MESA
--    dinheiro: precisa de AUTORIZO (os 3 € pré-pagos)
--
--  5a. admin_loja_decidir_reserva — espelha partner_decide_reservation(p_reservation_id,
--      p_accept, p_reason): reserva existe · estado 'pending' · aceitar → 'approved';
--      recusar → 'rejected_refunded' com cancel_reason = motivo · decided_at=now() ·
--      push ao cliente (_reservas_pro_notify_client_push) com os mesmos textos PT-PT ·
--      devolve success/status/will_refund/prepayment_pi.
--      AVISO DINHEIRO: recusar marca "reembolso em curso" mas não encontrei quem executa o
--      refund Stripe dos 3 € para 'rejected_refunded'. O caminho admin COM reembolso já provado
--      é a Edge Function admin-cancel-reservation (cancelled_refunded + stripe.refunds.create).
--
--  5b. admin_loja_marcar_chegada — espelha partner_mark_arrival(p_reservation_id): estado
--      'approved' · ainda sem arrived_at · lê platform_settings (200 cêntimos, 30 dias) ·
--      UPDATE arrived_at=now(), status='arrived' · INSERT restaurant_menu_credits (crédito ao
--      cliente) · INSERT partner_reservation_payouts (Bora deve ao parceiro; on conflict nada) ·
--      aviso in-app ao cliente · log 'reservation_arrival_marked' (como o parceiro) + log admin.
--      *** MOVE DINHEIRO: PRECISA DE AUTORIZO DO DANILO ***
-- =====================================================================================
create or replace function public.admin_loja_decidir_reserva(
  p_reservation_id uuid,
  p_aceitar        boolean,
  p_motivo         text
)
returns jsonb
language plpgsql
security definer
set search_path to 'public'
as $fn$
declare
  v_rsv        record;
  v_new_status text;
  v_title      text;
  v_body       text;
begin
  if not public.is_admin() then raise exception 'admin_required' using errcode = '42501'; end if;

  if length(regexp_replace(coalesce(p_motivo, ''), '[^[:alpha:]]', '', 'g')) < 3 then
    raise exception 'motivo_obrigatorio: escreve pelo menos 3 letras' using errcode = '22023';
  end if;

  select * into v_rsv from public.reservations where id = p_reservation_id for update;
  if not found then raise exception 'reservation_not_found'; end if;
  if v_rsv.status <> 'pending' then
    raise exception 'reservation_not_pending: %', v_rsv.status;
  end if;

  -- o parceiro prova que restaurants.user_ = auth.uid(); o admin só precisa que a loja exista
  if not exists (select 1 from public.restaurants r where r.id = v_rsv.restaurant_id) then
    raise exception 'not_your_restaurant';
  end if;

  -- 15/11/2026 Claude.ai: recusar reserva PAGA ainda nao tem reembolso automatico dos 3 EUR
  if not p_aceitar and coalesce(v_rsv.prepayment_cents, 0) > 0 then
    raise exception 'reserva_paga: recusar ainda nao devolve os 3 EUR; usa Cancelar reserva (devolve o dinheiro)' using errcode = '22023';
  end if;

  v_new_status := case when p_aceitar then 'approved' else 'rejected_refunded' end;

  update public.reservations
     set status        = v_new_status,
         decided_at    = now(),
         cancel_reason = case when p_aceitar then cancel_reason else p_motivo end
   where id = p_reservation_id;

  -- mesmos textos PT-PT da função do parceiro
  if p_aceitar then
    v_title := 'Reserva confirmada ✅';
    v_body  := 'Vemo-nos a ' || to_char(v_rsv.reserved_for at time zone 'Europe/Lisbon', 'DD/MM HH24:MI') || '. Até já!';
  else
    v_title := 'Reserva não aceite';
    v_body  := 'O parceiro não pôde aceitar a sua reserva. Reembolso em curso.';
  end if;

  perform public._reservas_pro_notify_client_push(
    v_rsv.client_user_id, 'reservation', v_title, v_body, p_reservation_id::text);

  perform public.log_admin_action(
    'admin_loja_decidir_reserva', 'restaurant', v_rsv.restaurant_id,
    jsonb_build_object('reservation_id', p_reservation_id, 'antes', 'pending', 'depois', v_new_status,
                       'aceitar', p_aceitar, 'will_refund', not p_aceitar,
                       'prepayment_cents', v_rsv.prepayment_cents,
                       'motivo', p_motivo, 'origem', 'painel: área do parceiro'));

  return jsonb_build_object(
    'success',       true,
    'status',        v_new_status,
    'will_refund',   not p_aceitar,
    'prepayment_pi', v_rsv.prepayment_pi,
    'admin',         true,
    'aviso',         case when p_aceitar then null
                          else 'reembolso dos 3 EUR nao e automatico: usar admin-cancel-reservation ou refund manual' end);
end;
$fn$;

revoke all on function public.admin_loja_decidir_reserva(uuid, boolean, text) from public, anon;
grant execute on function public.admin_loja_decidir_reserva(uuid, boolean, text) to authenticated;


create or replace function public.admin_loja_marcar_chegada(
  p_reservation_id uuid,
  p_motivo         text
)
returns jsonb
language plpgsql
security definer
set search_path to 'public'
as $fn$
declare
  v_rsv          record;
  v_credit_id    uuid;
  v_payout_id    uuid;
  v_payout_cents integer;
  v_expiry_days  integer;
begin
  if not public.is_admin() then raise exception 'admin_required' using errcode = '42501'; end if;

  if length(regexp_replace(coalesce(p_motivo, ''), '[^[:alpha:]]', '', 'g')) < 3 then
    raise exception 'motivo_obrigatorio: escreve pelo menos 3 letras' using errcode = '22023';
  end if;

  select * into v_rsv from public.reservations where id = p_reservation_id for update;
  if not found then raise exception 'reservation_not_found'; end if;
  if v_rsv.status <> 'approved' then
    raise exception 'reservation_not_approved: %', v_rsv.status;
  end if;
  if v_rsv.arrived_at is not null then
    raise exception 'already_arrived';
  end if;

  -- o parceiro prova que o e-mail da loja é o seu; o admin só precisa que a loja exista
  if not exists (select 1 from public.restaurants r where r.id = v_rsv.restaurant_id) then
    raise exception 'not_your_restaurant';
  end if;

  -- igual a partner_mark_arrival (v2): lê 2 € (não 3 €) das settings
  select (value::text)::int into v_payout_cents
    from public.platform_settings where key = 'reservation_partner_payout_cents';
  v_payout_cents := coalesce(v_payout_cents, 200);

  select (value::text)::int into v_expiry_days
    from public.platform_settings where key = 'reservation_credit_expiry_days';
  v_expiry_days := coalesce(v_expiry_days, 30);

  update public.reservations
     set arrived_at = now(), status = 'arrived'
   where id = p_reservation_id;

  -- crédito para o cliente gastar naquele restaurante
  insert into public.restaurant_menu_credits (
    user_id, restaurant_id, amount_cents, source_reservation_id, expires_at
  ) values (
    v_rsv.client_user_id, v_rsv.restaurant_id, v_payout_cents,
    p_reservation_id, now() + (v_expiry_days || ' days')::interval
  ) returning id into v_credit_id;

  -- obrigação de pagamento: a Bora deve este valor ao parceiro no fecho semanal
  insert into public.partner_reservation_payouts (
    partner_id, reservation_id, amount_cents
  ) values (
    v_rsv.restaurant_id, p_reservation_id, v_payout_cents
  )
  on conflict (reservation_id) do nothing
  returning id into v_payout_id;

  perform public._push_in_app_notification(
    v_rsv.client_user_id, 'reservation',
    'Crédito de €' || round(v_payout_cents / 100.0, 2)::text || ' creditado',
    'Aplicado automaticamente no teu próximo pedido neste restaurante.',
    p_reservation_id::text);

  -- o mesmo registo que a função do parceiro deixa
  perform public.log_admin_action(
    'reservation_arrival_marked', 'reservation', p_reservation_id::text,
    jsonb_build_object('credit_cents', v_payout_cents, 'payout_cents', v_payout_cents,
                       'partner_id', v_rsv.restaurant_id, 'client_user_id', v_rsv.client_user_id,
                       'by', 'admin_loja_marcar_chegada'));

  -- e o registo da área do parceiro (entidade = a loja)
  perform public.log_admin_action(
    'admin_loja_marcar_chegada', 'restaurant', v_rsv.restaurant_id,
    jsonb_build_object('reservation_id', p_reservation_id, 'antes', 'approved', 'depois', 'arrived',
                       'credit_cents', v_payout_cents, 'payout_cents', v_payout_cents,
                       'motivo', p_motivo, 'origem', 'painel: área do parceiro'));

  return jsonb_build_object(
    'success',      true,
    'credit_id',    v_credit_id,
    'credit_cents', v_payout_cents,
    'payout_id',    v_payout_id,
    'payout_cents', v_payout_cents,
    'admin',        true);
end;
$fn$;

revoke all on function public.admin_loja_marcar_chegada(uuid, text) from public, anon;
grant execute on function public.admin_loja_marcar_chegada(uuid, text) to authenticated;


-- =====================================================================================
-- 6. LISTA DOS PEDIDOS DA LOJA (só leitura)
--    Igual a admin_live_orders (mesmas colunas, mesma lista de estados, inclui readyForPickup)
--    mas filtrada pela loja com a mesma ligação de _partner_owns_order (restaurant_id, ou
--    vendor_name quando restaurant_id está vazio) e com colunas a mais no fim (a app lê por nome:
--    id, status, service_type, vendor_name, customer_name, total|price, created_at,
--    assigned_driver_id, is_test_order — PedidoDaLoja.doMapa).
--    Nota: a regra orders_select_admin (SELECT para is_admin()) já existe, por isso o ecrã também
--    pode ler orders diretamente; esta função fica para o caminho por RPC.
-- =====================================================================================
create or replace function public.admin_pedidos_da_loja(
  p_restaurant_id text,
  p_limite        integer default 50
)
returns table (
  id                    text,
  status                text,
  service_type          text,
  vendor_name           text,
  customer_name         text,
  total                 numeric,
  created_at            timestamptz,
  pickup_lat            numeric,
  pickup_lng            numeric,
  dropoff_lat           numeric,
  dropoff_lng           numeric,
  pickup_address        text,
  dropoff_address       text,
  assigned_driver_id    text,
  is_partner_store      boolean,
  is_test_order         boolean,
  restaurant_id         text,
  payment_method        text,
  payment_status        text,
  scheduled_for         timestamptz,
  prep_time_minutes     integer,
  takeaway_prep_minutes integer,
  takeaway_ready_at     timestamptz
)
language plpgsql
security definer
set search_path to 'public'
as $fn$
declare
  v_nome text;
begin
  if not public.is_admin() then raise exception 'admin_required' using errcode = '42501'; end if;

  select r.name into v_nome from public.restaurants r where r.id = p_restaurant_id;
  if not found then raise exception 'restaurant_not_found'; end if;

  return query
  select
    o.id,
    o.status,
    o.service_type,
    o.vendor_name,
    o.customer_name,
    coalesce(o.price, 0)::numeric,
    o.created_at,
    o.pickup_lat::numeric,
    o.pickup_lng::numeric,
    o.dropoff_lat::numeric,
    o.dropoff_lng::numeric,
    o.pickup_address,
    o.dropoff_address,
    o.assigned_driver_id,
    coalesce(o.is_partner_store, false),
    coalesce(o.is_test_order, false),
    o.restaurant_id,
    o.payment_method,
    o.payment_status,
    o.scheduled_for,
    o.prep_time_minutes,
    o.takeaway_prep_minutes,
    o.takeaway_ready_at
  from public.orders o
  where (o.restaurant_id = p_restaurant_id
         or (o.restaurant_id is null and o.vendor_name = v_nome))
    and o.status in ('created', 'preparing', 'readyForPickup', 'callingDriver',
                     'driverAccepted', 'pickedUp', 'onTheWay')
  order by o.created_at desc
  limit greatest(1, least(coalesce(p_limite, 50), 200));
end;
$fn$;

revoke all on function public.admin_pedidos_da_loja(text, integer) from public, anon;
grant execute on function public.admin_pedidos_da_loja(text, integer) to authenticated;


-- =====================================================================================
-- PROVAS (correr depois de aplicar; só leitura)
-- =====================================================================================
-- 1) As 7 funções existem, são SECURITY DEFINER e têm search_path fixo:
-- select p.proname, pg_get_function_identity_arguments(p.oid) as args, p.prosecdef, p.proconfig
--   from pg_proc p join pg_namespace n on n.oid = p.pronamespace
--  where n.nspname = 'public'
--    and p.proname in ('admin_loja_aceitar_pedido','admin_loja_recusar_pedido','admin_loja_marcar_pronto',
--                      'admin_loja_retirada','admin_loja_decidir_reserva','admin_loja_marcar_chegada',
--                      'admin_pedidos_da_loja')
--  order by p.proname;
--  -- esperado: 7 linhas, prosecdef = true, proconfig = {search_path=public}
--
-- 2) Permissões: authenticated pode, anon não:
-- select f, has_function_privilege('authenticated', f, 'EXECUTE') as auth_pode,
--           has_function_privilege('anon', f, 'EXECUTE') as anon_pode
--   from unnest(array[
--     'public.admin_loja_aceitar_pedido(text,integer,text)',
--     'public.admin_loja_recusar_pedido(text,text)',
--     'public.admin_loja_marcar_pronto(text,text)',
--     'public.admin_loja_retirada(text,text,text,integer)',
--     'public.admin_loja_decidir_reserva(uuid,boolean,text)',
--     'public.admin_loja_marcar_chegada(uuid,text)',
--     'public.admin_pedidos_da_loja(text,integer)']) as f;
--  -- esperado: auth_pode = true, anon_pode = false em todas
--
-- 3) A guarda admin: com um JWT que não é admin a chamada tem de dar 42501 'admin_required'
--    (testar pelo painel com uma conta sem papel admin, ou pelo PostgREST com esse token).
--
-- 4) Auditoria depois de uma ação real (pedido de teste, is_test_order = true):
-- select created_at, action, entity_type, entity_id_text, details
--   from public.admin_audit_log
--  where action like 'admin_loja_%' order by created_at desc limit 10;
--
-- 5) O caminho ficou registado no histórico de estados:
-- select order_id, from_status, to_status, source, actor_uid
--   from public.order_status_events where source like 'admin_loja_%' order by 1 desc limit 10;


-- =====================================================================================
-- ROLLBACK (comentado; apaga só o que este ficheiro cria)
-- =====================================================================================
-- drop function if exists public.admin_loja_aceitar_pedido(text, integer, text);
-- drop function if exists public.admin_loja_recusar_pedido(text, text);
-- drop function if exists public.admin_loja_marcar_pronto(text, text);
-- drop function if exists public.admin_loja_retirada(text, text, text, integer);
-- drop function if exists public.admin_loja_decidir_reserva(uuid, boolean, text);
-- drop function if exists public.admin_loja_marcar_chegada(uuid, text);
-- drop function if exists public.admin_pedidos_da_loja(text, integer);
-- -- As linhas já gravadas em admin_audit_log / order_status_events ficam (são histórico).
