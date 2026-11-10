# Volta — PARTE 2 de 3: a cobrança (proposta de dinheiro para o Claude.ai aplicar)

Missão `volta-deposito-kfc-2026-11-09`. Ordem do Danilo (09/11/2026 20:08, voz): "sempre quando houver
qualquer bebida de lata ou garrafa que tenha Volta, tem que cobrar mais os 10 cêntimos do cliente.
Mercado, KFC; Burger King não (...) Quando for fechar [o talão] e tiver lá, tem que colocar os 10
cêntimos também pro cliente pagar. Corrige tudo."

**⚠️ ISTO MEXE EM PAGAMENTO/DINHEIRO.** A sessão do PC não pode gravar isto em `supabase/migrations`
(bora-tranca: "migration que toca tokens/wallet/pagamentos/ledger") nem aplicar em produção (modo
automático: publicar é do Claude.ai). Está pronto e provado no PGlite (ver `prova-pglite.md`).

## Ordem de aplicação

1. `supabase/migrations/20261109220000_volta_catalogo_e_talao.sql` (PARTE 1, sem dinheiro).
2. Este SQL (PARTE 2). Gravar também em `supabase/migrations/20261109220100_volta_cobranca.sql`.
3. `passo-3-marcar-catalogo.sql` (marca as latas e garrafas). Só depois da 2.
4. Edge `ocr-receipt` v13 (NIF do cliente + linhas de depósito) e as apps (Play, App Store, web).

Enquanto as apps novas não estão nas lojas, nada muda para quem tem a app antiga: o servidor só cobra
o depósito quando os `items` do pedido trazem a chave `deposit_units` (só a app nova a manda, e é a
mesma app que mostra a linha "Depósito Volta"). O fecho do talão (`talao_aplicar_deposito_volta`)
vale para todos os pedidos de lojas não-parceiras, como hoje já valem os sacos e os pesos.

## O que faz

- `_create_order_core` e `quote_order_pricing`: depósito = soma de `deposit_units` (produto + opções
  escolhidas) × quantidade × `volta_deposit_cents`, pelo catálogo; entra no total do cliente numa linha
  própria, FORA do subtotal (sem margem 15 %, comissão, markup oculto, taxa de serviço, taxa de pedido
  pequeno, entrega grátis). O tecto dos tokens calcula-se sem o depósito (não se paga com tokens).
  Colunas `deposit_units`/`deposit_cents` no pedido e por linha em `items[]`. PaymentIntent: o
  `create-payment-intent` (modo carrinho) usa o `quote_order_pricing`, e o MB Way o
  `payment_buffer_total` do pedido — os dois já levam o depósito sem mexer nas Edge Functions.
- `fn_award_tokens_on_delivery`: tokens do cliente sobre o preço SEM o depósito.
- `post_order_to_ledger`: linha `deposit_volta` — parceiro recebe 100 %; não-parceiro fica na Bora.
- `compute_partner_weekly_settlement`: depósito somado ao que a Bora paga ao parceiro, em linha própria
  (`partner_weekly_settlements.deposit_volta_total`).
- `finalizar_talao_nao_parceiro`: o depósito dos produtos "Não há" volta ao cliente com o produto.
- `enforce_financial_immutability`: as colunas do depósito ficam fechadas como as outras de dinheiro.
- `talao_aplicar_deposito_volta` + gatilho em `order_receipts_v2.receipt_parsed`: quando o robô lê o
  talão, soma as linhas de depósito (DEPOSITO, VALOR DE DEPOSITO, VASILHAME, SDR, VOLTA, DEP.EMB).
  Talão com MAIS depósito do que o pedido cobrou → dinheiro: entra no `cash_total_due` antes da
  entrega; cartão/MB Way (ou dinheiro já entregue): dívida na carteira (o mecanismo que já existe, a
  `weight_adjust_card_charge_enabled` está desligada). E o produto fica marcado para a próxima vez
  (um só candidato → `deposit_units` fica certo; vários → lista "rever"). Talão com MENOS depósito →
  dinheiro: desconta no que o estafeta cobra; cartão/MB Way: volta à Carteira Bora. Diferença acima
  de 10 € não se aplica sozinha (aviso ao admin). É a única exceção à regra de 25/10.

## SQL

```sql
-- 20261109220100_volta_cobranca.sql — PARTE 2 (dinheiro). Requer a PARTE 1 aplicada.
create or replace function pg_temp.volta_remendo(p_fn regprocedure, p_nome text, p_anc text[], p_rep text[])
returns void language plpgsql as $$
declare v_def text; v_new text; i int; v_n int;
begin
  v_def := pg_get_functiondef(p_fn);
  insert into public.bkp_fn_volta_20261109 (nome, definicao) values (p_nome, v_def)
  on conflict (nome) do nothing;
  v_new := v_def;
  for i in 1 .. array_length(p_anc, 1) loop
    v_n := (length(v_new) - length(replace(v_new, p_anc[i], ''))) / length(p_anc[i]);
    if v_n <> 1 then
      raise exception 'VOLTA_ANCORA % de % aparece % vezes (esperado 1)', i, p_nome, v_n;
    end if;
    v_new := replace(v_new, p_anc[i], p_rep[i]);
  end loop;
  execute v_new;
end $$;

-- A app mostra a linha do depósito? (a app nova manda deposit_units em cada item)
create or replace function public.volta_app_mostra_deposito(p_input jsonb)
returns boolean language sql immutable as $$
  select coalesce(p_input->>'mostra_deposito', '') in ('true', '1')
      or exists (select 1 from jsonb_array_elements(case when jsonb_typeof(p_input->'items') = 'array'
                                                         then p_input->'items' else '[]'::jsonb end) x
                  where jsonb_typeof(x) = 'object' and x ? 'deposit_units')
$$;
revoke all on function public.volta_app_mostra_deposito(jsonb) from public, anon;

-- 1) _create_order_core
select pg_temp.volta_remendo('public._create_order_core(jsonb)'::regprocedure, '_create_order_core',
  array[
$a$  v_small_order_fee    NUMERIC := 0;   -- CONTAS CLARAS C7
$a$,
$a$  -- B3a (2026-06-12): cap de pagamento com tokens — máx$a$,
$a$    v_token_cap_cents := FLOOR(v_customer_total * v_token_max_pct)::INTEGER;$a$,
$a$    small_order_fee,
    deixar_a_porta
  ) VALUES ($a$,
$a$    v_small_order_fee,
    v_deixar_a_porta
  );$a$,
$a$    'checkin_vale_id', CASE WHEN v_ck_desc > 0 THEN v_ck_id END
  );$a$
  ],
  array[
$b$  v_small_order_fee    NUMERIC := 0;   -- CONTAS CLARAS C7
  v_dep_units          INTEGER := 0;   -- 09/11/2026 Volta
  v_dep_cents          INTEGER := 0;   -- 09/11/2026 Volta
  v_dep_items          JSONB;          -- 09/11/2026 Volta
$b$,
$b$  -- 09/11/2026 (Danilo, missão volta-deposito-kfc): depósito Volta, 0,10 € por lata/garrafa de plástico.
  -- Passagem de dinheiro: fora do subtotal (sem margem, comissão, taxa de serviço, pedido pequeno nem
  -- tokens). Calculado aqui pelo catálogo, nunca pelo valor da app; só quando a app mostra a linha.
  IF public.volta_deposito_ativo()
     AND public.volta_app_mostra_deposito(p_input)
     AND v_service_type IN ('restaurant', 'storeShopping', 'takeaway') THEN
    SELECT d.units, d.items INTO v_dep_units, v_dep_items FROM public.volta_deposito_itens(v_items_enriched) d;
    v_dep_units := COALESCE(v_dep_units, 0);
    v_dep_cents := v_dep_units * public.volta_deposito_cents_unidade();
    IF v_dep_cents > 0 THEN
      v_items_enriched := v_dep_items;
      v_customer_total := ROUND((v_customer_total + v_dep_cents / 100.0)::numeric, 2);
    ELSE
      v_dep_units := 0;
      v_dep_cents := 0;
    END IF;
  END IF;

  -- B3a (2026-06-12): cap de pagamento com tokens — máx$b$,
$b$    v_token_cap_cents := FLOOR((v_customer_total - v_dep_cents / 100.0) * v_token_max_pct)::INTEGER;  -- 09/11/2026: o depósito Volta não se paga com tokens$b$,
$b$    small_order_fee,
    deixar_a_porta,
    deposit_units, deposit_cents
  ) VALUES ($b$,
$b$    v_small_order_fee,
    v_deixar_a_porta,
    v_dep_units, v_dep_cents
  );$b$,
$b$    'checkin_vale_id', CASE WHEN v_ck_desc > 0 THEN v_ck_id END,
    'deposit_units', v_dep_units,
    'deposit_cents', v_dep_cents
  );$b$
  ]);

-- 2) quote_order_pricing (carrinho e PaymentIntent do modo carrinho)
select pg_temp.volta_remendo('public.quote_order_pricing(jsonb)'::regprocedure, 'quote_order_pricing',
  array[
$a$  v_token_cap INTEGER;
BEGIN$a$,
$a$  v_max_wallet_cents := ROUND(v_customer_total * 100)::INTEGER;
  IF v_wallet_cents > v_max_wallet_cents THEN v_wallet_cents := v_max_wallet_cents; END IF;$a$,
$a$    v_token_cap := FLOOR(v_customer_total * COALESCE($a$,
$a$    'free_delivery_min_cents', (SELECT$a$
  ],
  array[
$b$  v_token_cap INTEGER;
  v_dep_units INTEGER := 0;   -- 09/11/2026 Volta
  v_dep_cents INTEGER := 0;   -- 09/11/2026 Volta
  v_dep_items JSONB;          -- 09/11/2026 Volta
BEGIN$b$,
$b$  -- 09/11/2026 Volta: igual ao create_order (fora do subtotal; só quando a app mostra a linha).
  IF public.volta_deposito_ativo()
     AND public.volta_app_mostra_deposito(p_input)
     AND v_service_type IN ('restaurant', 'storeShopping', 'takeaway') THEN
    SELECT d.units, d.items INTO v_dep_units, v_dep_items
      FROM public.volta_deposito_itens(COALESCE(p_input->'items', '[]'::jsonb)) d;
    v_dep_units := COALESCE(v_dep_units, 0);
    v_dep_cents := v_dep_units * public.volta_deposito_cents_unidade();
    IF v_dep_cents > 0 THEN
      v_customer_total := ROUND((v_customer_total + v_dep_cents / 100.0)::numeric, 2);
    ELSE
      v_dep_units := 0;
      v_dep_cents := 0;
    END IF;
  END IF;

  v_max_wallet_cents := ROUND(v_customer_total * 100)::INTEGER;
  IF v_wallet_cents > v_max_wallet_cents THEN v_wallet_cents := v_max_wallet_cents; END IF;$b$,
$b$    v_token_cap := FLOOR((v_customer_total - v_dep_cents / 100.0) * COALESCE($b$,
$b$    'deposit_units', v_dep_units, 'deposit_cents', v_dep_cents,
    'deposit_unit_cents', public.volta_deposito_cents_unidade(),
    'free_delivery_min_cents', (SELECT$b$
  ]);

-- 3) Tokens do cliente na entrega: o depósito não gera tokens.
select pg_temp.volta_remendo('public.fn_award_tokens_on_delivery()'::regprocedure, 'fn_award_tokens_on_delivery',
  array[$a$    v_client_tokens := GREATEST(1, ROUND(NEW.price * 3)::INTEGER);$a$],
  array[$b$    v_client_tokens := GREATEST(1, ROUND((NEW.price - (COALESCE(NEW.deposit_cents, 0) + COALESCE(NEW.deposit_ajuste_cents, 0)) / 100.0) * 3)::INTEGER);  -- 09/11/2026: sem o depósito Volta$b$]);

-- 4) Livro-razão na entrega: deposit_volta (parceiro recebe 100 %; não-parceiro = Bora).
alter table public.ledger_entries drop constraint if exists ledger_entries_type_check;
alter table public.ledger_entries add constraint ledger_entries_type_check
  check (type = any (array['earning','cash_adjustment','commission','payout','deposit_volta']));

select pg_temp.volta_remendo('public.post_order_to_ledger()'::regprocedure, 'post_order_to_ledger',
  array[
$a$  v_total            NUMERIC(12, 2);$a$,
$a$  END IF;

  RETURN NEW;
END;$a$
  ],
  array[
$b$  v_total            NUMERIC(12, 2);
  v_dep              NUMERIC(12, 2);   -- 09/11/2026 Volta$b$,
$b$  END IF;

  -- 09/11/2026 Volta: o depósito é passagem de dinheiro. Parceiro: 100 % à loja, à parte da comissão.
  -- Não-parceiro: fica com a Bora (o estafeta pagou-o ao balcão e foi reembolsado pelo talão).
  v_dep := ROUND((COALESCE(NEW.deposit_cents, 0) + COALESCE(NEW.deposit_ajuste_cents, 0)) / 100.0, 2);
  IF v_dep > 0 THEN
    IF v_is_partner AND v_vendor_ref IS NOT NULL THEN
      INSERT INTO public.ledger_entries (user_id, user_type, order_id, amount, type, reference)
      VALUES (v_vendor_ref, 'restaurant', NEW.id::UUID, v_dep, 'deposit_volta', 'deposit_volta')
      ON CONFLICT (order_id, user_id, type, reference) DO NOTHING;
    ELSE
      INSERT INTO public.ledger_entries (user_id, user_type, order_id, amount, type, reference)
      VALUES ('platform', 'platform', NEW.id::UUID, v_dep, 'deposit_volta', 'deposit_volta')
      ON CONFLICT (order_id, user_id, type, reference) DO NOTHING;
    END IF;
  END IF;

  RETURN NEW;
END;$b$
  ]);

-- 5) Acerto semanal do parceiro: o depósito à parte, somado ao que a Bora lhe paga.
alter table public.partner_weekly_settlements add column if not exists deposit_volta_total numeric not null default 0;
select pg_temp.volta_remendo('public.compute_partner_weekly_settlement(text,timestamp with time zone,boolean)'::regprocedure,
  'compute_partner_weekly_settlement',
  array[
$a$  v_net numeric := 0;$a$,
$a$  v_net := ROUND(v_share - v_cash_partner, 2);$a$,
$a$      cash_kept_by_partner, net_balance, direction, status
    ) VALUES ($a$,
$a$      v_cash_partner, v_net, v_direction, 'pending'
    )$a$,
$a$      net_balance          = EXCLUDED.net_balance,$a$,
$a$    'net_balance', v_net,$a$
  ],
  array[
$b$  v_net numeric := 0;
  v_deposit numeric := 0;   -- 09/11/2026 Volta$b$,
$b$  -- 09/11/2026 Volta: depósitos dos pedidos da semana, 100 % do parceiro, à parte da comissão.
  SELECT COALESCE(SUM(le.amount), 0) INTO v_deposit
    FROM public.ledger_entries le
    JOIN public.orders o ON o.id = le.order_id::text
   WHERE le.user_type = 'restaurant' AND le.type = 'deposit_volta'
     AND o.restaurant_id = p_partner_id
     AND o.status = 'delivered'
     AND o.delivered_at >= v_bounds.week_start
     AND o.delivered_at <= v_bounds.week_end;
  v_net := ROUND(v_share + v_deposit - v_cash_partner, 2);$b$,
$b$      cash_kept_by_partner, net_balance, direction, status, deposit_volta_total
    ) VALUES ($b$,
$b$      v_cash_partner, v_net, v_direction, 'pending', v_deposit
    )$b$,
$b$      net_balance          = EXCLUDED.net_balance,
      deposit_volta_total  = EXCLUDED.deposit_volta_total,$b$,
$b$    'net_balance', v_net,
    'deposit_volta_total', v_deposit,$b$
  ]);

-- 6) Fecho do talão: o depósito dos produtos "Não há" volta ao cliente com o produto.
select pg_temp.volta_remendo('public.finalizar_talao_nao_parceiro(text,text,integer,jsonb,integer)'::regprocedure,
  'finalizar_talao_nao_parceiro',
  array[
$a$  v_premio_cents        integer := 0;  -- 04/11/2026 premio check-in$a$,
$a$      v_final_value_cents := v_purchased_cents + v_replaced_cents + v_added_cents;$a$,
$a$    -- 4) Totais do pedido (bypass financeiro so aqui dentro).$a$
  ],
  array[
$b$  v_premio_cents        integer := 0;  -- 04/11/2026 premio check-in
  v_dep_falta_cents     integer := 0;  -- 09/11/2026 Volta$b$,
$b$      v_final_value_cents := v_purchased_cents + v_replaced_cents + v_added_cents;
      -- 09/11/2026 Volta: o depósito do que "Não há" volta ao cliente junto com o produto.
      SELECT COALESCE(SUM(COALESCE((oi->>'deposit_cents')::int, 0)), 0)::int INTO v_dep_falta_cents
        FROM jsonb_array_elements(COALESCE((SELECT o.items FROM public.orders o WHERE o.id = p_order_id), '[]'::jsonb)) oi
       WHERE COALESCE((oi->>'deposit_cents')::int, 0) > 0
         AND EXISTS (SELECT 1 FROM jsonb_array_elements(p_items) x
                      WHERE x->>'status' = 'unavailable' AND x->>'original_name' = oi->>'name');
      v_unavailable_cents := v_unavailable_cents + v_dep_falta_cents;$b$,
$b$    IF v_dep_falta_cents > 0 THEN
      UPDATE public.orders SET deposit_ajuste_cents = COALESCE(deposit_ajuste_cents, 0) - v_dep_falta_cents
       WHERE id = p_order_id;
    END IF;

    -- 4) Totais do pedido (bypass financeiro so aqui dentro).$b$
  ]);

-- 7) As colunas do depósito ficam fechadas como as outras de dinheiro do pedido.
select pg_temp.volta_remendo('public.enforce_financial_immutability()'::regprocedure, 'enforce_financial_immutability',
  array[$a$     OR NEW.payment_buffer_total IS DISTINCT FROM OLD.payment_buffer_total$a$],
  array[$b$     OR NEW.payment_buffer_total IS DISTINCT FROM OLD.payment_buffer_total
     OR NEW.deposit_units        IS DISTINCT FROM OLD.deposit_units
     OR NEW.deposit_cents        IS DISTINCT FROM OLD.deposit_cents
     OR NEW.deposit_ajuste_cents IS DISTINCT FROM OLD.deposit_ajuste_cents
     OR NEW.deposit_from_receipt_cents IS DISTINCT FROM OLD.deposit_from_receipt_cents$b$]);

-- 8) Fecho do talão pelo robô: diferença de depósito entre o talão e o que o pedido cobrou.
create or replace function public.talao_aplicar_deposito_volta(p_receipt_id uuid)
returns jsonb language plpgsql security definer set search_path to 'public' as $$
declare
  v_r      record;
  v_o      record;
  v_unit   integer := public.volta_deposito_cents_unidade();
  v_talao  integer;
  v_atual  integer;
  v_delta  integer;
  v_cash   boolean;
  v_aberto boolean;
  v_via    text;
  v_falta  integer;
  v_cands  jsonb := '[]'::jsonb;
  v_ncand  integer := 0;
  v_auto   text := null;
  v_c      record;
begin
  if not public.volta_deposito_ativo() then
    return jsonb_build_object('ok', true, 'skipped', 'volta_desligado');
  end if;
  select r.id, r.order_id, r.receipt_parsed into v_r from public.order_receipts_v2 r where r.id = p_receipt_id;
  if v_r.id is null then return jsonb_build_object('ok', false, 'error', 'receipt_not_found'); end if;
  if jsonb_typeof(v_r.receipt_parsed->'lines') is distinct from 'array'
     or jsonb_array_length(v_r.receipt_parsed->'lines') = 0 then
    return jsonb_build_object('ok', true, 'skipped', 'talao_sem_linhas');
  end if;

  select coalesce(sum(round(greatest(coalesce((l->>'qty')::numeric, 1), 0)
                            * greatest(coalesce((l->>'unit_price_cents')::numeric, 0), 0))), 0)::int
    into v_talao
    from jsonb_array_elements(v_r.receipt_parsed->'lines') l
   where jsonb_typeof(l) = 'object' and public._talao_e_deposito(l->>'name');

  select o.id, o.user_id, o.status, o.payment_method, o.service_type, o.is_partner_store, o.restaurant_id,
         o.deposit_cents, o.deposit_ajuste_cents, o.cash_total_due, o.final_total, o.price, o.items
    into v_o from public.orders o where o.id = v_r.order_id for update;
  if v_o.id is null then return jsonb_build_object('ok', false, 'error', 'order_not_found'); end if;
  if coalesce(v_o.is_partner_store, false) then return jsonb_build_object('ok', true, 'skipped', 'loja_parceira'); end if;
  if v_o.service_type not in ('restaurant', 'storeShopping') then
    return jsonb_build_object('ok', true, 'skipped', 'tipo_' || coalesce(v_o.service_type, '?'));
  end if;
  if v_o.status in ('cancelled', 'canceled', 'rejected') then
    return jsonb_build_object('ok', true, 'skipped', 'pedido_cancelado');
  end if;

  perform set_config('app.financial_bypass', 'true', true);
  update public.orders set deposit_from_receipt_cents = v_talao, deposit_talao_em = now() where id = v_o.id;

  v_atual := coalesce(v_o.deposit_cents, 0) + coalesce(v_o.deposit_ajuste_cents, 0);
  v_delta := v_talao - v_atual;
  if v_delta = 0 then
    return jsonb_build_object('ok', true, 'talao_cents', v_talao, 'pedido_cents', v_atual, 'diferenca_cents', 0);
  end if;
  if abs(v_delta) > 100 * greatest(v_unit, 1) then
    insert into public.admin_notifications (event_type, severity, entity_type, entity_id, summary, payload)
    values ('volta_talao_diferenca_grande', 'medium', 'order', v_o.id,
            'Talão do pedido ' || left(v_o.id, 8) || ': depósito Volta lido (' || v_talao || ' cênt.) muito diferente do cobrado ('
              || v_atual || ' cênt.). Não se aplicou sozinho — rever o talão.',
            jsonb_build_object('receipt_id', p_receipt_id, 'talao_cents', v_talao, 'pedido_cents', v_atual));
    return jsonb_build_object('ok', true, 'skipped', 'diferenca_grande_revisao_manual', 'diferenca_cents', v_delta);
  end if;

  v_cash := (v_o.payment_method = 'cash');
  v_aberto := v_o.status not in ('delivered');

  if v_delta > 0 then
    -- o talão tem MAIS depósito do que o pedido cobrou: a diferença é do cliente
    if v_cash and v_aberto then
      update public.orders
         set cash_total_due = round(coalesce(cash_total_due, final_total, price, 0) + v_delta / 100.0, 2),
             final_total = round(coalesce(final_total, price, 0) + v_delta / 100.0, 2),
             deposit_ajuste_cents = coalesce(deposit_ajuste_cents, 0) + v_delta
       where id = v_o.id;
      v_via := 'dinheiro_na_entrega';
    else
      insert into public.wallet_transactions (user_id, amount_cents, kind, reason, related_order_id, idempotency_key)
      values (v_o.user_id, -v_delta, 'debit', 'volta_deposito_talao', v_o.id, 'volta_dep_' || v_o.id || '_' || v_talao)
      on conflict (idempotency_key) do nothing;
      update public.orders
         set final_total = round(coalesce(final_total, price, 0) + v_delta / 100.0, 2),
             deposit_ajuste_cents = coalesce(deposit_ajuste_cents, 0) + v_delta
       where id = v_o.id;
      v_via := 'divida_na_carteira';
    end if;

    -- e o produto que o gerou fica marcado para a próxima vez
    v_falta := v_delta / greatest(v_unit, 1);
    for v_c in
      select p.id, p.name, greatest(1, round(coalesce((oi->>'quantity')::numeric, 1))::int) as qtd,
             public.volta_classificar(p.name, p.category, p.restaurant_id) as cls
        from jsonb_array_elements(case when jsonb_typeof(v_o.items) = 'array' then v_o.items else '[]'::jsonb end) oi
        join public.products p on p.id = oi->>'productId'
       where coalesce(p.deposit_units, 0) = 0
    loop
      continue when (v_c.cls->>'estado') not in ('marcar', 'duvidoso');
      v_ncand := v_ncand + 1;
      v_cands := v_cands || jsonb_build_object('product_id', v_c.id, 'nome', v_c.name, 'qtd', v_c.qtd, 'regra', v_c.cls);
    end loop;
    if v_ncand = 1 and v_falta > 0 and mod(v_falta, (v_cands->0->>'qtd')::int) = 0
       and v_falta / (v_cands->0->>'qtd')::int between 1 and 48 then
      update public.products
         set deposit_units = v_falta / (v_cands->0->>'qtd')::int, deposit_review = true, deposit_origem = 'talao'
       where id = v_cands->0->>'product_id';
      v_auto := v_cands->0->>'product_id';
    elsif v_ncand > 0 then
      update public.products set deposit_review = true
       where id in (select x->>'product_id' from jsonb_array_elements(v_cands) x);
    end if;
    insert into public.admin_notifications (event_type, severity, entity_type, entity_id, summary, payload)
    values ('volta_talao_deposito_a_mais', 'low', 'order', v_o.id,
            'Talão do pedido ' || left(v_o.id, 8) || ': ' || v_delta || ' cênt. de depósito Volta a mais do que o pedido cobrou ('
              || replace(v_via, '_', ' ') || '). ' || case when v_auto is not null then 'Produto marcado: ' || v_auto
                                                           when v_ncand > 0 then v_ncand || ' produto(s) na lista "rever" do Volta.'
                                                           else 'Nenhum produto candidato — rever o pedido.' end,
            jsonb_build_object('receipt_id', p_receipt_id, 'talao_cents', v_talao, 'pedido_cents', v_atual,
                               'diferenca_cents', v_delta, 'via', v_via, 'candidatos', v_cands, 'marcado', v_auto));
  else
    -- o talão tem MENOS depósito do que o pedido cobrou: devolve-se a diferença
    if v_cash and v_aberto then
      update public.orders
         set cash_total_due = greatest(0, round(coalesce(cash_total_due, final_total, price, 0) + v_delta / 100.0, 2)),
             final_total = greatest(0, round(coalesce(final_total, price, 0) + v_delta / 100.0, 2)),
             deposit_ajuste_cents = coalesce(deposit_ajuste_cents, 0) + v_delta
       where id = v_o.id;
      v_via := 'desconto_na_entrega';
    else
      insert into public.wallet_transactions (user_id, amount_cents, kind, reason, related_order_id, idempotency_key)
      values (v_o.user_id, -v_delta, 'refund_credit_free', 'volta_deposito_talao_devolvido', v_o.id,
              'volta_dev_' || v_o.id || '_' || v_talao)
      on conflict (idempotency_key) do nothing;
      update public.orders
         set final_total = greatest(0, round(coalesce(final_total, price, 0) + v_delta / 100.0, 2)),
             deposit_ajuste_cents = coalesce(deposit_ajuste_cents, 0) + v_delta
       where id = v_o.id;
      v_via := 'carteira';
    end if;
  end if;

  return jsonb_build_object('ok', true, 'talao_cents', v_talao, 'pedido_cents', v_atual,
                            'diferenca_cents', v_delta, 'via', v_via, 'candidatos', v_ncand, 'marcado', v_auto);
end $$;
revoke all on function public.talao_aplicar_deposito_volta(uuid) from public, anon, authenticated;
grant execute on function public.talao_aplicar_deposito_volta(uuid) to service_role;

create or replace function public._trg_talao_deposito_volta()
returns trigger language plpgsql security definer set search_path to 'public' as $$
begin
  if new.receipt_parsed is distinct from old.receipt_parsed then
    begin
      perform public.talao_aplicar_deposito_volta(new.id);
    exception when others then
      raise warning 'talao_aplicar_deposito_volta falhou: %', sqlerrm;
    end;
  end if;
  return null;
end $$;
create or replace trigger trg_talao_deposito_volta
  after update of receipt_parsed on public.order_receipts_v2
  for each row execute function public._trg_talao_deposito_volta();
```

## Provas a fazer depois de aplicar (SELECT, em rollback)

1. `select pg_get_functiondef('public._create_order_core(jsonb)'::regprocedure) ~ 'volta_deposito_itens';` → true
   (idem quote, tokens, ledger, acerto do parceiro, finalizar, imutabilidade).
2. Em rollback (DO + RAISE): um pedido em dinheiro no Continente com um pack de 6 latas
   (`deposit_units = 6`) e itens com `deposit_units` → `deposit_cents = 60`, `price` = antes + 0,60,
   `cash_total_due` + 0,60; o mesmo pedido sem a chave nos itens → `deposit_cents = 0`.
3. Em rollback: `update order_receipts_v2 set receipt_parsed = …` com "2 DEPOSITO 10" num pedido que
   cobrou 0 → `deposit_ajuste_cents = 20` e `cash_total_due` + 0,20 (dinheiro) / dívida de 20 na
   carteira (cartão).
