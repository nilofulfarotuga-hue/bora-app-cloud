-- =============================================================================
-- PROPOSTA — NÃO APLICADA — Botão do painel "Devolver ao meio de pagamento"
-- Missão: chamada-grita-2026-10-10 · agente pagamentos-wallet (PROPOSE-ONLY)
-- Projeto Supabase: ojykpzwqrtusfeakzrna
--
-- ⚠️ ISTO MEXE EM PAGAMENTO/DINHEIRO. Está tudo pronto — confirma que eu aplico.
--
-- Para que serve: um pedido pago por MB Way/cartão foi parar à carteira (saldo + tokens) e
-- deve voltar ao meio de pagamento. Ex.: Divan, pedido d383a09e (6,00 € MB Way →
-- 4,80 € saldo + 240 tokens = 1,20 €).
--
-- Fluxo (a Edge está descrita em PROPOSTA_botao_devolver_ao_meio_de_pagamento.md):
--   1) admin_devolucao_plano(pedido)      — só lê: quanto se pode devolver, quanto já foi gasto.
--   2) admin_devolucao_iniciar(...)       — cria a "devolução" (1 ativa por pedido) = trava + chave.
--   3) Edge → Stripe refunds.create(payment_intent, amount, idempotencyKey 'admin-devolver-meio-<id>')
--   4) SÓ se a Stripe disser status='succeeded' → admin_devolucao_confirmar(...) retira da carteira,
--      numa única transação, o que foi creditado por ESSE pedido (tokens livres primeiro, depois saldo).
--      'pending' → admin_devolucao_marcar('aguarda_stripe'); o stripe-webhook chama o confirmar
--      quando chegar refund.updated com status 'succeeded'.  'failed' → nada sai da carteira.
--
-- Prova da conta (SELECT só de leitura, corrido 10/10/2026 com a mesma lógica do plano):
--   d383a09e  stripe 600 · saldo creditado 480 · saldo atual 1031 · tokens livres 240 (=120 c)
--             → a devolver 600 c ao MB Way · já gasto 0
--   dcc8c509  stripe 0 → nada a devolver ao MB Way (o MB Way falhou; ver "DECISÃO" no outro .sql)
--   bba0f503  saldo atual 0, tokens todos gastos → a devolver 0 (a cliente já usou tudo)
--   947f7206  já devolvido ao MB Way em 07/10 (saldo líquido do pedido = 0) → a devolver 0
--   6c102c39  stripe 0 → nada
-- =============================================================================


-- -----------------------------------------------------------------------------
-- A) Registo das devoluções (trava + histórico). Só a service_role escreve.
-- -----------------------------------------------------------------------------
create table if not exists public.devolucoes_ao_meio (
  id                      uuid primary key default gen_random_uuid(),
  order_id                text not null,
  user_id                 uuid not null,
  admin_id                uuid,
  admin_email             text,
  estado                  text not null default 'planeada'
                          check (estado in ('planeada','aguarda_stripe','confirmada','falhou')),
  payment_intent_id       text not null,
  plano                   jsonb not null,
  a_devolver_cents        integer not null check (a_devolver_cents >= 50),  -- mínimo Stripe 0,50 €
  stripe_refund_id        text,
  stripe_estado           text,
  devolvido_cents         integer,
  saldo_retirado_cents    integer,
  tokens_revogados        integer,
  tokens_revogados_cents  integer,
  saldo_depois_cents      integer,
  erro                    text,
  created_at              timestamptz not null default now(),
  updated_at              timestamptz not null default now()
);
-- uma só devolução viva/confirmada por pedido → o 2.º clique não cria outra
create unique index if not exists uq_devolucao_ao_meio_ativa
  on public.devolucoes_ao_meio (order_id)
  where estado in ('planeada','aguarda_stripe','confirmada');

alter table public.devolucoes_ao_meio enable row level security;
drop policy if exists devolucoes_ao_meio_admin_le on public.devolucoes_ao_meio;
create policy devolucoes_ao_meio_admin_le on public.devolucoes_ao_meio
  for select to authenticated using (public.is_admin());


-- -----------------------------------------------------------------------------
-- B) PLANO — só leitura. O painel mostra isto antes do admin confirmar.
-- -----------------------------------------------------------------------------
create or replace function public.admin_devolucao_plano(p_order_id text)
returns jsonb
language plpgsql
stable
security definer
set search_path to 'public'
as $$
declare
  v_o             record;
  v_x100          numeric;
  v_net_free      integer;
  v_saldo         integer;
  v_por_gastar    integer;
  v_tok_livres    integer;
  v_tok_gastos    integer;
  v_tok_livres_c  integer;
  v_tok_gastos_c  integer;
  v_a_devolver    integer;
  v_motivo        text := null;
begin
  -- admin com sessão OU service_role (auth.uid() nulo)
  if auth.uid() is not null and not public.is_admin() then
    raise exception 'so_admin' using errcode = '42501';
  end if;

  select id::text as oid, user_id, status::text as st, payment_method::text as pm,
         payment_intent_id as pi, coalesce(stripe_charge_cents,0) as sc
    into v_o from public.orders where id::text = p_order_id;
  if not found then return jsonb_build_object('pode', false, 'motivo', 'pedido_nao_encontrado'); end if;

  v_x100 := coalesce(nullif(public.get_setting('token_value_cents_x100') #>> '{}', '')::numeric, 50);

  -- saldo líquido creditado por este pedido (créditos − estornos já feitos). Inclui correções
  -- antigas sem related_order_id mas com o id do pedido na chave (ex.: 'admin-fix-full-refund-bba0f503').
  select coalesce(sum(t.amount_cents), 0)::int into v_net_free
    from public.wallet_transactions t
   where t.user_id = v_o.user_id
     and t.kind <> 'refund_credit_tokens'
     and t.kind <> 'order_payment'
     and (t.related_order_id = p_order_id
          or (t.related_order_id is null and t.idempotency_key ilike '%' || substring(p_order_id,1,8) || '%'));
  v_net_free := greatest(v_net_free, 0);

  select coalesce(free_balance_cents, 0) into v_saldo from public.client_wallets where user_id = v_o.user_id;
  v_saldo := coalesce(v_saldo, 0);
  v_por_gastar := least(v_net_free, greatest(v_saldo, 0));

  -- tokens que o reembolso deste pedido criou (add_tokens com source_order_id = pedido, ao lado de
  -- uma linha refund_credit_tokens do mesmo pedido — exclui tokens GANHOS numa entrega)
  select coalesce(sum(b.amount) filter (where not b.is_used), 0)::int,
         coalesce(sum(b.amount) filter (where b.is_used), 0)::int
    into v_tok_livres, v_tok_gastos
    from public.bora_tokens b
   where b.user_id = v_o.user_id and b.role = 'client' and b.source_order_id = p_order_id
     and exists (select 1 from public.wallet_transactions t
                  where t.user_id = b.user_id and t.related_order_id = p_order_id
                    and t.kind = 'refund_credit_tokens' and t.amount_cents > 0);
  v_tok_livres_c := round(v_tok_livres * v_x100 / 100)::int;
  v_tok_gastos_c := round(v_tok_gastos * v_x100 / 100)::int;

  v_a_devolver := least(v_o.sc, v_por_gastar + v_tok_livres_c);

  if v_o.st not in ('cancelled','rejected') then v_motivo := 'pedido_nao_esta_cancelado';
  elsif v_o.pm not in ('card','mbway') then v_motivo := 'nao_foi_pago_por_cartao_nem_mbway';
  elsif v_o.pi is null or v_o.sc <= 0 then v_motivo := 'stripe_nao_cobrou_nada';
  elsif exists (select 1 from public.devolucoes_ao_meio d where d.order_id = p_order_id and d.estado = 'confirmada')
       then v_motivo := 'ja_devolvido_por_este_botao';
  elsif v_a_devolver < 50 then v_motivo := 'abaixo_do_minimo_stripe_0_50';
  end if;

  return jsonb_build_object(
    'pode', v_motivo is null, 'motivo', v_motivo,
    'order_id', p_order_id, 'user_id', v_o.user_id, 'meio', v_o.pm, 'payment_intent_id', v_o.pi,
    'stripe_cobrado_cents', v_o.sc,
    'saldo_creditado_cents', v_net_free, 'saldo_atual_cents', v_saldo, 'saldo_por_gastar_cents', v_por_gastar,
    'tokens_livres', v_tok_livres, 'tokens_livres_cents', v_tok_livres_c,
    'tokens_gastos', v_tok_gastos, 'tokens_gastos_cents', v_tok_gastos_c,
    'a_devolver_cents', case when v_motivo is null then v_a_devolver else 0 end,
    'ja_gasto_cents', (v_net_free - v_por_gastar) + v_tok_gastos_c);
end $$;


-- -----------------------------------------------------------------------------
-- C) INICIAR — cria a devolução (trava). Idempotente: se já há uma viva, devolve-a.
--    p_stripe_disponivel_cents = amount_received − amount_refunded lido NA STRIPE pela Edge.
-- -----------------------------------------------------------------------------
create or replace function public.admin_devolucao_iniciar(
  p_order_id                text,
  p_admin_id                uuid,
  p_admin_email             text,
  p_stripe_disponivel_cents integer
) returns jsonb
language plpgsql
security definer
set search_path to 'public'
as $$
declare
  v_plano jsonb;
  v_viva  record;
  v_cents integer;
  v_id    uuid;
begin
  select * into v_viva from public.devolucoes_ao_meio
   where order_id = p_order_id and estado in ('planeada','aguarda_stripe','confirmada')
   limit 1;
  if found then
    return jsonb_build_object('devolucao_id', v_viva.id, 'estado', v_viva.estado,
                              'a_devolver_cents', v_viva.a_devolver_cents, 'ja_existia', true,
                              'idempotency_key', 'admin-devolver-meio-' || v_viva.id);
  end if;

  v_plano := public.admin_devolucao_plano(p_order_id);
  if not coalesce((v_plano->>'pode')::boolean, false) then
    raise exception 'nao_pode_devolver: %', v_plano->>'motivo';
  end if;

  v_cents := least((v_plano->>'a_devolver_cents')::int, greatest(coalesce(p_stripe_disponivel_cents,0), 0));
  if v_cents < 50 then raise exception 'stripe_ja_nao_tem_o_que_devolver: % c', v_cents; end if;

  insert into public.devolucoes_ao_meio
    (order_id, user_id, admin_id, admin_email, payment_intent_id, plano, a_devolver_cents)
  values
    (p_order_id, (v_plano->>'user_id')::uuid, p_admin_id, p_admin_email,
     v_plano->>'payment_intent_id', v_plano || jsonb_build_object('stripe_disponivel_cents', p_stripe_disponivel_cents),
     v_cents)
  returning id into v_id;

  return jsonb_build_object('devolucao_id', v_id, 'estado', 'planeada', 'a_devolver_cents', v_cents,
                            'ja_existia', false, 'idempotency_key', 'admin-devolver-meio-' || v_id,
                            'payment_intent_id', v_plano->>'payment_intent_id');
end $$;


-- -----------------------------------------------------------------------------
-- D) MARCAR — 'aguarda_stripe' (refund pending) ou 'falhou' (nada sai da carteira).
-- -----------------------------------------------------------------------------
create or replace function public.admin_devolucao_marcar(
  p_devolucao_id     uuid,
  p_estado           text,
  p_stripe_refund_id text,
  p_stripe_estado    text,
  p_erro             text
) returns jsonb
language plpgsql
security definer
set search_path to 'public'
as $$
begin
  if p_estado not in ('aguarda_stripe','falhou') then raise exception 'estado_invalido'; end if;
  update public.devolucoes_ao_meio
     set estado = p_estado,
         stripe_refund_id = coalesce(p_stripe_refund_id, stripe_refund_id),
         stripe_estado = coalesce(p_stripe_estado, stripe_estado),
         erro = p_erro, updated_at = now()
   where id = p_devolucao_id and estado in ('planeada','aguarda_stripe');
  if not found then return jsonb_build_object('ok', false, 'motivo', 'nao_esta_viva'); end if;
  if p_estado = 'falhou' then
    begin
      perform public.notify_admin_event('devolucao_ao_meio_falhou', 'high',
        format('Devolução ao meio de pagamento falhou na Stripe (%s). Nada foi retirado da carteira.', coalesce(p_erro,'?')),
        'order', (select order_id from public.devolucoes_ao_meio where id = p_devolucao_id),
        jsonb_build_object('devolucao_id', p_devolucao_id, 'refund_id', p_stripe_refund_id),
        '/admin/cancellations');
    exception when others then null;
    end;
  end if;
  return jsonb_build_object('ok', true, 'estado', p_estado);
end $$;


-- -----------------------------------------------------------------------------
-- E) CONFIRMAR — atómica e idempotente. Só corre com a Stripe a dizer 'succeeded'.
--    Retira o que ESTE pedido creditou: primeiro tokens livres, depois saldo.
--    Se o cliente gastou saldo entre o plano e a confirmação (segundos/minutos), o saldo fica
--    negativo nessa diferença (permitido até −40 €, CHECK de client_wallets) e o admin é avisado;
--    o Danilo decide perdoar (kind 'forgive', já existe) ou deixar como dívida.
-- -----------------------------------------------------------------------------
create or replace function public.admin_devolucao_confirmar(
  p_devolucao_id     uuid,
  p_stripe_refund_id text,
  p_devolvido_cents  integer,
  p_stripe_estado    text
) returns jsonb
language plpgsql
security definer
set search_path to 'public'
as $$
declare
  v_d         record;
  v_x100      numeric;
  v_rest      integer;
  v_tok       record;
  v_need      integer;
  v_tok_rev   integer := 0;
  v_tok_rev_c integer := 0;
  v_saldo_rem integer := 0;
  v_net_free  integer;
  v_saldo     integer;
  v_pm        text;
  v_sc        integer;
begin
  if p_stripe_estado is distinct from 'succeeded' then
    raise exception 'so_confirma_com_stripe_succeeded (veio %)', p_stripe_estado;
  end if;
  if p_devolvido_cents is null or p_devolvido_cents <= 0 then raise exception 'valor_invalido'; end if;

  select * into v_d from public.devolucoes_ao_meio where id = p_devolucao_id for update;
  if not found then raise exception 'devolucao_nao_encontrada'; end if;
  if v_d.estado = 'confirmada' then
    return jsonb_build_object('ok', true, 'already_applied', true, 'devolucao_id', v_d.id,
                              'saldo_retirado_cents', v_d.saldo_retirado_cents,
                              'tokens_revogados', v_d.tokens_revogados);
  end if;
  if v_d.estado not in ('planeada','aguarda_stripe') then
    raise exception 'devolucao_em_estado_%', v_d.estado;
  end if;
  if p_devolvido_cents > v_d.a_devolver_cents then
    raise exception 'stripe_devolveu_mais_do_planeado: % > %', p_devolvido_cents, v_d.a_devolver_cents;
  end if;

  -- trava a carteira do cliente durante a operação
  insert into public.client_wallets (user_id, free_balance_cents) values (v_d.user_id, 0)
    on conflict (user_id) do nothing;
  perform 1 from public.client_wallets where user_id = v_d.user_id for update;

  v_x100 := coalesce(nullif(public.get_setting('token_value_cents_x100') #>> '{}', '')::numeric, 50);
  v_rest := p_devolvido_cents;

  -- 1) tokens livres criados pelo reembolso deste pedido
  for v_tok in
    select b.id, b.amount, b.expires_at
      from public.bora_tokens b
     where b.user_id = v_d.user_id and b.role = 'client' and b.source_order_id = v_d.order_id
       and not b.is_used
       and exists (select 1 from public.wallet_transactions t
                    where t.user_id = b.user_id and t.related_order_id = v_d.order_id
                      and t.kind = 'refund_credit_tokens' and t.amount_cents > 0)
     order by b.created_at
     for update
  loop
    exit when v_rest <= 0;
    v_need := ceil(v_rest * 100 / v_x100)::int;               -- tokens que cobrem o que falta
    if v_tok.amount <= v_need then
      update public.bora_tokens set is_used = true, used_at = now() where id = v_tok.id;
      v_tok_rev := v_tok_rev + v_tok.amount;
      v_rest := v_rest - least(v_rest, round(v_tok.amount * v_x100 / 100)::int);
    else
      -- revoga só parte: marca a linha e devolve o resto numa linha nova (padrão do consume_tokens)
      update public.bora_tokens set is_used = true, used_at = now() where id = v_tok.id;
      insert into public.bora_tokens (user_id, role, amount, expires_at)
        values (v_d.user_id, 'client', v_tok.amount - v_need, v_tok.expires_at);
      v_tok_rev := v_tok_rev + v_need;
      v_rest := 0;
    end if;
  end loop;
  v_tok_rev_c := p_devolvido_cents - v_rest;

  -- 2) o resto sai do saldo — nunca mais do que este pedido creditou
  select coalesce(sum(t.amount_cents), 0)::int into v_net_free
    from public.wallet_transactions t
   where t.user_id = v_d.user_id and t.kind not in ('refund_credit_tokens','order_payment')
     and (t.related_order_id = v_d.order_id
          or (t.related_order_id is null and t.idempotency_key ilike '%' || substring(v_d.order_id,1,8) || '%'));
  if v_rest > greatest(v_net_free, 0) then
    raise exception 'devolvido_acima_do_creditado: falta retirar % c, pedido só creditou % c', v_rest, v_net_free;
  end if;

  if v_rest > 0 then
    insert into public.wallet_transactions
      (user_id, amount_cents, kind, reason, related_order_id, related_admin_id, idempotency_key)
    values
      (v_d.user_id, -v_rest, 'adjustment',
       format('Devolvido %s € ao meio de pagamento (reembolso Stripe %s) — retirado o crédito deste pedido',
              to_char(p_devolvido_cents::numeric/100,'FM999990.00'), p_stripe_refund_id),
       v_d.order_id, v_d.admin_id, 'devolver_meio_saldo_' || v_d.order_id);
    v_saldo_rem := v_rest;
  end if;

  -- marcador dos tokens revogados (kind fora do saldo → não mexe no saldo, fica no histórico)
  if v_tok_rev_c > 0 then
    insert into public.wallet_transactions
      (user_id, amount_cents, kind, reason, related_order_id, related_admin_id, idempotency_key)
    values
      (v_d.user_id, -v_tok_rev_c, 'refund_credit_tokens',
       format('Revogados %s tokens (≈ %s €): o valor voltou ao meio de pagamento (Stripe %s)',
              v_tok_rev, to_char(v_tok_rev_c::numeric/100,'FM999990.00'), p_stripe_refund_id),
       v_d.order_id, v_d.admin_id, 'devolver_meio_tokens_' || v_d.order_id);
  end if;

  -- 3) o pedido passa a "reembolsado pela Stripe"
  select payment_method::text, coalesce(stripe_charge_cents,0) into v_pm, v_sc
    from public.orders where id::text = v_d.order_id;
  update public.orders
     set refund_method  = 'stripe',
         refund_id      = p_stripe_refund_id,
         refund_status  = 'refunded',
         refunded_at    = now(),
         refund_amount  = round(p_devolvido_cents::numeric / 100, 2)::double precision,
         payment_status = case when p_devolvido_cents >= v_sc then 'refunded' else 'partial_refund' end
   where id::text = v_d.order_id;

  -- 4) saldo depois (o recálculo oficial corre no commit; aqui calcula-se igual, pela soma)
  select coalesce(sum(amount_cents),0)::int into v_saldo
    from public.wallet_transactions
   where user_id = v_d.user_id and kind <> all (public.wallet_kinds_fora_do_saldo());

  update public.devolucoes_ao_meio
     set estado = 'confirmada', stripe_refund_id = p_stripe_refund_id, stripe_estado = p_stripe_estado,
         devolvido_cents = p_devolvido_cents, saldo_retirado_cents = v_saldo_rem,
         tokens_revogados = v_tok_rev, tokens_revogados_cents = v_tok_rev_c,
         saldo_depois_cents = v_saldo, updated_at = now()
   where id = v_d.id;

  -- 5) auditoria
  insert into public.admin_audit_log (admin_id, admin_email, action, entity_type, entity_id_text, details)
  values (v_d.admin_id, v_d.admin_email, 'devolver_ao_meio_de_pagamento', 'order', v_d.order_id,
          jsonb_build_object('devolucao_id', v_d.id, 'refund_id', p_stripe_refund_id,
                             'devolvido_cents', p_devolvido_cents, 'saldo_retirado_cents', v_saldo_rem,
                             'tokens_revogados', v_tok_rev, 'tokens_revogados_cents', v_tok_rev_c,
                             'saldo_depois_cents', v_saldo, 'plano', v_d.plano));

  -- 6) aviso ao cliente (in-app; a Edge manda também o push)
  begin
    perform public._push_in_app_notification(v_d.user_id, 'refund_confirmed', 'Reembolso confirmado',
      format('Devolvemos %s € %s. O valor deste pedido que estava no teu saldo Bora foi retirado.',
             to_char(p_devolvido_cents::numeric/100,'FM999990.00'),
             case when v_pm = 'mbway' then 'ao teu MB Way' else 'ao teu cartão (5 a 10 dias úteis no extrato)' end),
      v_d.order_id);
  exception when others then null;
  end;

  if v_saldo < 0 then
    begin
      perform public.notify_admin_event('devolucao_saldo_negativo', 'high',
        format('Devolução do pedido #%s: o cliente já tinha gastado parte do saldo — ficou com %s €',
               substring(v_d.order_id,1,8), to_char(v_saldo::numeric/100,'FM999990.00')),
        'client', v_d.user_id::text, jsonb_build_object('devolucao_id', v_d.id), '/admin/wallets');
    exception when others then null;
    end;
  end if;

  return jsonb_build_object('ok', true, 'already_applied', false, 'devolucao_id', v_d.id,
                            'devolvido_cents', p_devolvido_cents, 'saldo_retirado_cents', v_saldo_rem,
                            'tokens_revogados', v_tok_rev, 'tokens_revogados_cents', v_tok_rev_c,
                            'saldo_depois_cents', v_saldo);
end $$;


-- -----------------------------------------------------------------------------
-- F) PERMISSÕES
-- -----------------------------------------------------------------------------
revoke all on function public.admin_devolucao_plano(text)                               from public, anon;
grant execute on function public.admin_devolucao_plano(text)                            to authenticated, service_role; -- guarda is_admin() lá dentro
revoke all on function public.admin_devolucao_iniciar(text, uuid, text, integer)        from public, anon, authenticated;
revoke all on function public.admin_devolucao_marcar(uuid, text, text, text, text)      from public, anon, authenticated;
revoke all on function public.admin_devolucao_confirmar(uuid, text, integer, text)      from public, anon, authenticated;
grant execute on function public.admin_devolucao_iniciar(text, uuid, text, integer)     to service_role;
grant execute on function public.admin_devolucao_marcar(uuid, text, text, text, text)   to service_role;
grant execute on function public.admin_devolucao_confirmar(uuid, text, integer, text)   to service_role;
revoke all on table public.devolucoes_ao_meio from anon;
grant select on table public.devolucoes_ao_meio to authenticated;  -- policy: só admin
grant all    on table public.devolucoes_ao_meio to service_role;


-- -----------------------------------------------------------------------------
-- G) PROVA EM TRANSAÇÃO DESFEITA (depois do "vai"; DO … RAISE EXCEPTION no fim)
--   1. select public.admin_devolucao_plano('d383a09e-2ba0-481e-82dd-ee0d9b0886e1');
--      → pode=true, a_devolver_cents=600, saldo_por_gastar_cents=480, tokens_livres=240, ja_gasto_cents=0
--   2. select public.admin_devolucao_iniciar('d383a09e-…', '<uuid admin>', 'prova', 600);  → devolucao_id X
--      2.ª chamada → ja_existia=true, mesmo X (prova do duplo clique)
--   3. select public.admin_devolucao_confirmar(X, 're_PROVA', 600, 'pending');   → ERRO so_confirma_com_stripe_succeeded
--   4. select public.admin_devolucao_confirmar(X, 're_PROVA', 600, 'succeeded'); → tokens_revogados=240,
--      tokens_revogados_cents=120, saldo_retirado_cents=480, saldo_depois_cents=551
--   5. repetir o 4 → already_applied=true (nada muda)
--   6. select is_used from bora_tokens where id='26074f4b-cbd8-4824-856e-62722280e7ed'; → true
--   7. select public.admin_devolucao_plano('d383a09e-…'); → pode=false, motivo=ja_devolvido_por_este_botao
--   RAISE EXCEPTION 'PROVA %', <json com tudo>  → rollback; confirmar depois que o saldo do Divan
--   continua 1031 e o token 26074f4b continua is_used=false.
--   NÃO se chama a Stripe na prova (o 're_PROVA' é falso).
--
-- DESFAZER: as funções e a tabela são novas; drop function/table chega (nada existente é alterado).
-- =============================================================================
