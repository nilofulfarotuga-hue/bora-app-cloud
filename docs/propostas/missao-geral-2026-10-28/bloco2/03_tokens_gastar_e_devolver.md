# Proposta 03 — Tokens: o servidor gasta-os (e regista quais) e os cancelamentos devolvem-nos como TOKENS

Missão `missao-geral-2026-10-28`, Bloco 2. Agente `pagamentos-wallet` (só propõe). **Nada aplicado.**
Os passos (1) e (2) saem SEMPRE juntos, no mesmo SQL, e só DEPOIS de publicadas as 4 Edge Functions
com o `_shared/cobranca_stripe.ts` v2 (proposta 01).

## O que se leu (SELECT, 28/10)

- `bora_tokens`: `id uuid`, `user_id uuid`, `role text` (client|driver|cleaner), `amount int > 0`,
  `created_at`, `expires_at timestamptz NOT NULL` (a validade), `source_order_id text`,
  `is_used bool`, `used_at`. Índice único `(source_order_id, role) WHERE source_order_id IS NOT NULL`.
  RLS ligada, só `tokens_select_own` (SELECT do próprio). Não há "estado" além de `is_used`.
  Nenhum cron apaga linhas; nenhuma FK aponta para `bora_tokens`.
- `consume_tokens(p_user_id, p_amount)`: gasta por ordem de validade, **sem filtro de papel**
  (gasta também tokens de estafeta), marca a linha inteira usada e cria uma linha nova com a sobra
  e a mesma validade. Não sabe de que pedido é.
- `add_tokens(...)`: cria uma linha com validade **now() + 60 dias** (não serve para devolver "com a
  validade que tinham") e não cria nada se já houver linha com o mesmo `source_order_id`+papel.
- `create_order(jsonb)` (linhas 93, 545-561, 584, 632/655): grava `tokens_applied_value_cents`
  (já cortado a 50% do pedido e a metade do valor dos tokens que o cliente tem) e desconta-o no
  valor a cobrar, mas **não gasta tokens e não grava `tokens_applied_count`**.
- A app gasta-os depois: `lib/screens/payment_method_screen.dart:1531-1549`
  (`_consumeTokensAndNavigate` → `rpc('consume_tokens')`, erro "non-fatal"), chamado nas linhas
  1224, 1393, 1474 e 1527. Se o servidor cortou o desconto, a app gasta na mesma o número que pediu.
- Dados: 21 pedidos com tokens nos últimos 60 dias, **0** com `tokens_applied_count > 0`. Pedido
  6361fa99 (hoje 17:20, cancelado): 70 tokens gastos (linhas marcadas usadas = 156, sobra 86),
  nada devolvido.
- `fn_reembolso_cancelado_pelo_sistema` (gatilho BEFORE UPDATE OF status): devolve tokens
  "desmarcando" tudo o que o cliente usou entre `created_at − 2 min` e `+30 min`. Dois defeitos:
  apanha tokens de OUTRO pedido feito nessa meia hora, e desmarca a linha inteira que o
  `consume_tokens` partiu (a sobra já existe noutra linha) → devolve A MAIS. No 6361fa99 teria
  devolvido 156 em vez de 70.

## Recomendação para o passo (1) — quem gasta os tokens

**Recomendo:** função nova idempotente `consumir_tokens_do_pedido(p_order_id)`, chamada pelo
servidor **na mesma transação do `create_order`**, por um gatilho `AFTER INSERT` em `orders`
(sem reescrever o `create_order`).

- Pró: atómico — o pedido só existe se os tokens foram gastos; acaba o desconto de borla quando a
  chamada da app falha ("non-fatal").
- Pró: não se reescreve o `create_order` (≈700 linhas, zona protegida); a função testa-se sozinha
  e pode ser chamada outra vez sem gastar 2× (idempotente pela tabela de ligação).
- Pró: gasta exatamente o valor que o servidor aceitou (a app hoje gasta o que pediu, mesmo cortado).
- Contra: lógica num gatilho (menos à vista); se faltarem tokens (dois pedidos ao mesmo tempo), o
  pedido falha com `TOKENS_INSUFICIENTES` e o cliente tem de repetir.
- Contra: as apps antigas continuam a chamar `consume_tokens` → precisa da PONTE (§3) para não
  gastar 2× até toda a gente ter a app nova (passo 3).

A alternativa "a app chama `consumir_tokens_do_pedido` depois do pagamento" mantém o buraco do
"non-fatal" e depende de todos atualizarem a app; por isso não a recomendo.

## SQL proposto (aplicar tudo de uma vez, numa só migração, pelo Claude.ai)

Nome sugerido: `20261028xxxxxx_tokens_gastos_pelo_servidor_e_devolvidos_como_tokens`.

```sql
-- [APLICAR 0] BACKUPS — um por função mudada (consume_tokens e fn_reembolso_cancelado_pelo_sistema)
create table if not exists public.bkp_consume_tokens_20261028 (
  nome text primary key,
  definicao text not null,
  guardado_em timestamptz not null default now()
);
alter table public.bkp_consume_tokens_20261028 enable row level security;
revoke all on public.bkp_consume_tokens_20261028 from public, anon, authenticated;
insert into public.bkp_consume_tokens_20261028 (nome, definicao)
  values ('consume_tokens(uuid,integer)',
          pg_get_functiondef('public.consume_tokens(uuid,integer)'::regprocedure))
  on conflict (nome) do nothing;

create table if not exists public.bkp_fn_reembolso_cancelado_pelo_sistema_20261028 (
  nome text primary key,
  definicao text not null,
  guardado_em timestamptz not null default now()
);
alter table public.bkp_fn_reembolso_cancelado_pelo_sistema_20261028 enable row level security;
revoke all on public.bkp_fn_reembolso_cancelado_pelo_sistema_20261028 from public, anon, authenticated;
insert into public.bkp_fn_reembolso_cancelado_pelo_sistema_20261028 (nome, definicao)
  values ('fn_reembolso_cancelado_pelo_sistema()',
          pg_get_functiondef('public.fn_reembolso_cancelado_pelo_sistema()'::regprocedure))
  on conflict (nome) do nothing;
```

```sql
-- [APLICAR 1] TABELA DE LIGAÇÃO pedido ↔ token gasto (só o servidor escreve; o cliente lê as suas)
create table if not exists public.pedido_tokens_gastos (
  id                  bigint generated always as identity primary key,
  order_id            text not null references public.orders(id) on delete cascade,
  user_id             uuid not null,
  token_id            uuid not null,            -- linha de bora_tokens gasta (sem FK de propósito)
  role                text not null,            -- papel do token gasto (volta ao mesmo papel)
  quantidade          integer not null check (quantidade > 0),
  expira_em           timestamptz not null,     -- a validade ORIGINAL desse token
  gasto_em            timestamptz not null default now(),
  app_absorvido_em    timestamptz,              -- PONTE: a app antiga chamou consume_tokens depois
  devolvido_em        timestamptz,
  devolvido_token_id  uuid,                     -- linha nova de bora_tokens criada na devolução
  devolucao_resultado text check (devolucao_resultado in ('devolvido', 'expirado')),
  motivo_devolucao    text
);
create unique index if not exists uq_pedido_tokens_gastos_pedido_token
  on public.pedido_tokens_gastos (order_id, token_id);
create index if not exists idx_pedido_tokens_gastos_ponte
  on public.pedido_tokens_gastos (user_id, gasto_em) where app_absorvido_em is null;
alter table public.pedido_tokens_gastos enable row level security;
revoke all on public.pedido_tokens_gastos from public, anon, authenticated;
grant select on public.pedido_tokens_gastos to authenticated;
drop policy if exists pedido_tokens_gastos_ler_os_meus on public.pedido_tokens_gastos;
create policy pedido_tokens_gastos_ler_os_meus on public.pedido_tokens_gastos
  for select to authenticated
  using (user_id = auth.uid() or public.is_admin());
comment on table public.pedido_tokens_gastos is
  'Regra do Danilo 28/10/2026: que tokens cada pedido gastou (consumir_tokens_do_pedido) e a devolução '
  'como TOKENS com a validade original (devolver_tokens_do_pedido). Só se acrescenta/marca; nunca se apaga.';
```

```sql
-- [APLICAR 2] PASSO (1): o servidor gasta os tokens do pedido, na transação do create_order
create or replace function public.consumir_tokens_do_pedido(p_order_id text)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_o       record;
  v_x100    numeric;
  v_precisa integer;
  v_falta   integer;
  v_row     record;
  v_usa     integer;
  v_total   integer := 0;
begin
  select id, user_id,
         coalesce(tokens_applied_value_cents, 0) as tv
    into v_o
    from public.orders where id = p_order_id
    for update;
  if not found then
    return jsonb_build_object('ok', false, 'motivo', 'pedido_nao_encontrado');
  end if;
  if v_o.tv <= 0 or v_o.user_id is null then
    return jsonb_build_object('ok', true, 'tokens', 0, 'motivo', 'pedido_sem_tokens');
  end if;
  -- idempotente: se já gastou, devolve o que gastou
  if exists (select 1 from public.pedido_tokens_gastos where order_id = p_order_id) then
    return jsonb_build_object('ok', true, 'already_applied', true,
      'tokens', (select coalesce(sum(quantidade), 0) from public.pedido_tokens_gastos
                  where order_id = p_order_id));
  end if;

  -- 1 token = token_value_cents_x100 / 100 cêntimos (hoje 50 → 0,5 cêntimo → valor × 2)
  v_x100 := coalesce(nullif(public.get_setting('token_value_cents_x100') #>> '{}', '')::numeric, 50);
  v_precisa := ceil(v_o.tv * 100.0 / v_x100)::integer;
  v_falta := v_precisa;

  -- mesma ordem e mesmos papéis que o consume_tokens (o create_order corta pelo get_user_tokens,
  -- que soma todos os papéis): primeiro os que expiram mais cedo
  for v_row in
    select id, amount, expires_at, role
      from public.bora_tokens
     where user_id = v_o.user_id and is_used = false and expires_at > now()
     order by expires_at asc, created_at asc
     for update
  loop
    exit when v_falta = 0;
    v_usa := least(v_row.amount, v_falta);
    update public.bora_tokens set is_used = true, used_at = now() where id = v_row.id;
    if v_row.amount > v_usa then
      -- a sobra fica numa linha nova, com a MESMA validade (como o consume_tokens)
      insert into public.bora_tokens (user_id, role, amount, expires_at)
        values (v_o.user_id, v_row.role, v_row.amount - v_usa, v_row.expires_at);
    end if;
    insert into public.pedido_tokens_gastos (order_id, user_id, token_id, role, quantidade, expira_em)
      values (p_order_id, v_o.user_id, v_row.id, v_row.role, v_usa, v_row.expires_at);
    v_falta := v_falta - v_usa;
    v_total := v_total + v_usa;
  end loop;

  if v_falta > 0 then
    raise exception 'TOKENS_INSUFICIENTES: pedido % precisa de % tokens e faltam %',
      p_order_id, v_precisa, v_falta using errcode = 'P0001';
  end if;

  update public.orders set tokens_applied_count = v_total where id = p_order_id;
  return jsonb_build_object('ok', true, 'tokens', v_total, 'valor_cents', v_o.tv);
end;
$$;
revoke all on function public.consumir_tokens_do_pedido(text) from public, anon, authenticated;

create or replace function public.fn_orders_consumir_tokens()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if coalesce(new.tokens_applied_value_cents, 0) > 0 then
    perform public.consumir_tokens_do_pedido(new.id);   -- se faltar, rebenta e o pedido não nasce
  end if;
  return null;
end;
$$;
revoke all on function public.fn_orders_consumir_tokens() from public, anon, authenticated;

drop trigger if exists trg_orders_consumir_tokens on public.orders;
create trigger trg_orders_consumir_tokens
  after insert on public.orders
  for each row execute function public.fn_orders_consumir_tokens();
```

```sql
-- [APLICAR 3] PONTE para as apps antigas: consume_tokens não gasta 2× o que o servidor já gastou
-- (igual à definição no ar a 28/10, mais o bloco PONTE)
create or replace function public.consume_tokens(p_user_id uuid, p_amount integer)
 returns boolean
 language plpgsql
 security definer
 set search_path to 'public'
as $function$
DECLARE
  v_current_balance  INTEGER;
  v_remaining        INTEGER := p_amount;
  v_row              RECORD;
  v_ponte            INTEGER := 0;
BEGIN
  IF auth.uid() IS NOT NULL
     AND auth.uid() <> p_user_id
     AND NOT public.is_admin()
     AND COALESCE(current_setting('bora.internal_token_consume', true), '') <> 'on' THEN
    RAISE EXCEPTION 'consume_tokens: caller % cannot consume tokens of user %',
      auth.uid(), p_user_id USING ERRCODE = '42501';
  END IF;
  IF p_amount <= 0 THEN
    RAISE EXCEPTION 'consume_tokens: p_amount must be > 0, got %', p_amount;
  END IF;

  -- PONTE 28/10/2026: o servidor já gastou os tokens do pedido (consumir_tokens_do_pedido).
  -- A app antiga chama consume_tokens logo a seguir ao pedido: "absorve-se" essa chamada (TRUE sem
  -- gastar) se houver um pedido deste cliente com tokens gastos pelo servidor nos últimos 30 min,
  -- ainda não absorvido, e o pedido da app for >= ao que o servidor gastou (o servidor corta).
  IF COALESCE(current_setting('bora.internal_token_consume', true), '') <> 'on'
     AND auth.uid() IS NOT NULL AND auth.uid() = p_user_id THEN
    UPDATE public.pedido_tokens_gastos g
       SET app_absorvido_em = now()
     WHERE g.app_absorvido_em IS NULL
       AND g.order_id = (
             SELECT x.order_id
               FROM public.pedido_tokens_gastos x
              WHERE x.user_id = p_user_id
                AND x.app_absorvido_em IS NULL
                AND x.gasto_em > now() - interval '30 minutes'
              GROUP BY x.order_id
             HAVING SUM(x.quantidade) <= p_amount
              ORDER BY MAX(x.gasto_em) DESC
              LIMIT 1);
    GET DIAGNOSTICS v_ponte = ROW_COUNT;
    IF v_ponte > 0 THEN
      RETURN TRUE;
    END IF;
  END IF;

  v_current_balance := get_user_tokens(p_user_id);
  IF v_current_balance < p_amount THEN
    RAISE NOTICE 'consume_tokens: insufficient balance for user %. Have %, need %',
      p_user_id, v_current_balance, p_amount;
    RETURN FALSE;
  END IF;
  FOR v_row IN
    SELECT id, amount, expires_at, role FROM bora_tokens
    WHERE user_id = p_user_id AND is_used = FALSE AND expires_at > now()
    ORDER BY expires_at ASC, created_at ASC FOR UPDATE
  LOOP
    EXIT WHEN v_remaining = 0;
    IF v_row.amount <= v_remaining THEN
      UPDATE bora_tokens SET is_used = TRUE, used_at = now() WHERE id = v_row.id;
      v_remaining := v_remaining - v_row.amount;
    ELSE
      UPDATE bora_tokens SET is_used = TRUE, used_at = now() WHERE id = v_row.id;
      INSERT INTO bora_tokens (user_id, role, amount, expires_at)
      VALUES (p_user_id, v_row.role, v_row.amount - v_remaining, v_row.expires_at);
      v_remaining := 0;
    END IF;
  END LOOP;
  IF v_remaining > 0 THEN
    RAISE EXCEPTION 'consume_tokens: consumed less than requested (remaining=%). Rolling back.', v_remaining;
  END IF;
  RETURN TRUE;
END;
$function$;
```

```sql
-- [APLICAR 4] PASSO (2): qualquer cancelamento (cliente, admin, sistema) devolve EXATAMENTE os
-- tokens gastos, como TOKENS, com a validade que tinham. Os já expirados não voltam.
create or replace function public.devolver_tokens_do_pedido(p_order_id text, p_motivo text default null)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_g      record;
  v_novo   uuid;
  v_dev    integer := 0;
  v_exp    integer := 0;
  v_linhas integer := 0;
  v_tv     integer;
begin
  for v_g in
    select * from public.pedido_tokens_gastos
     where order_id = p_order_id and devolvido_em is null
     order by id
     for update
  loop
    v_linhas := v_linhas + 1;
    if v_g.expira_em > now() then
      insert into public.bora_tokens (user_id, role, amount, expires_at)
        values (v_g.user_id, v_g.role, v_g.quantidade, v_g.expira_em)
        returning id into v_novo;
      update public.pedido_tokens_gastos
         set devolvido_em = now(), devolvido_token_id = v_novo,
             devolucao_resultado = 'devolvido', motivo_devolucao = p_motivo
       where id = v_g.id;
      v_dev := v_dev + v_g.quantidade;
    else
      update public.pedido_tokens_gastos
         set devolvido_em = now(), devolucao_resultado = 'expirado', motivo_devolucao = p_motivo
       where id = v_g.id;
      v_exp := v_exp + v_g.quantidade;
    end if;
  end loop;

  if v_linhas > 0 then
    return jsonb_build_object('ok', true, 'tokens', v_dev, 'expirados', v_exp, 'already_applied', false);
  end if;
  if exists (select 1 from public.pedido_tokens_gastos where order_id = p_order_id) then
    return jsonb_build_object('ok', true, 'tokens', 0, 'already_applied', true);
  end if;

  -- pedido de ANTES desta regra: tinha tokens mas não se sabe quais → não se adivinha; avisa o admin
  select coalesce(tokens_applied_value_cents, 0) into v_tv from public.orders where id = p_order_id;
  if coalesce(v_tv, 0) > 0 then
    begin
      perform public.notify_admin_event('tokens_pedido_antigo_por_devolver', 'medium',
        format('Pedido #%s cancelado: tinha %s cêntimos em tokens gastos antes de 28/10 — não se sabe quais, ver à mão',
               left(p_order_id, 8), v_tv),
        'order', p_order_id, jsonb_build_object('tokens_value_cents', v_tv),
        '/admin/orders/' || p_order_id);
    exception when others then
      raise warning 'devolver_tokens_do_pedido: aviso falhou % %', p_order_id, sqlerrm;
    end;
    return jsonb_build_object('ok', false, 'tokens', 0, 'motivo', 'pedido_antigo_sem_registo');
  end if;
  return jsonb_build_object('ok', true, 'tokens', 0, 'motivo', 'pedido_sem_tokens');
end;
$$;
revoke all on function public.devolver_tokens_do_pedido(text, text) from public, anon, authenticated;

create or replace function public.fn_orders_devolver_tokens()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  begin
    perform public.devolver_tokens_do_pedido(new.id,
      'cancelado:' || coalesce(new.cancellation_initiator::text, 'desconhecido'));
  exception when others then
    -- nunca impede o cancelamento; avisa o admin
    raise warning 'fn_orders_devolver_tokens: pedido % — %', new.id, sqlerrm;
    begin
      perform public.notify_admin_event('tokens_devolucao_falhou', 'high',
        format('Pedido #%s cancelado: os tokens não voltaram (%s)', left(new.id, 8), sqlerrm),
        'order', new.id, '{}'::jsonb, '/admin/orders/' || new.id);
    exception when others then null;
    end;
  end;
  return null;
end;
$$;
revoke all on function public.fn_orders_devolver_tokens() from public, anon, authenticated;

drop trigger if exists trg_orders_devolver_tokens on public.orders;
create trigger trg_orders_devolver_tokens
  after update of status on public.orders
  for each row
  when (new.status in ('cancelled', 'rejected') and old.status is distinct from new.status)
  execute function public.fn_orders_devolver_tokens();
```

```sql
-- [APLICAR 5] fn_reembolso_cancelado_pelo_sistema v3 (28/10):
--  (a) sai a "janela de tempo" dos tokens (agora é o trg_orders_devolver_tokens, exato);
--  (b) pedido cancelado pelo SISTEMA que NÃO vai ter reembolso automático da Stripe (dinheiro, ou
--      MB Way/cartão por pagar) e usou SALDO: o saldo volta ao saldo (antes ficava perdido —
--      dispatch_cancel_expired_order não devolve nada). Com MB Way/cartão pago, a parte do saldo
--      volta pelo auto-refund-order v4 (index.ts preparado no repo).
--  O resto é igual à definição no ar a 28/10.
create or replace function public.fn_reembolso_cancelado_pelo_sistema()
 returns trigger
 language plpgsql
 security definer
 set search_path to 'public', 'vault'
as $function$
declare
  v_eur numeric;
  v_key text;
  v_vai_stripe boolean;
  v_saldo integer;
begin
  if new.status::text not in ('cancelled','rejected') or old.status is not distinct from new.status then return new; end if;
  if new.cancellation_initiator is null or new.cancellation_initiator::text <> 'system' then return new; end if;
  if coalesce(new.is_test_order,false) then return new; end if;
  if new.refund_status is not null then return new; end if;

  v_vai_stripe := new.payment_method::text in ('card','mbway')
                  and coalesce(new.payment_status::text,'') = 'paid';

  -- (b) sem reembolso automático da Stripe: o saldo usado volta já ao saldo (chave = id do pedido)
  if not v_vai_stripe then
    v_saldo := coalesce(new.wallet_applied_cents, 0);
    if v_saldo > 0 and new.user_id is not null then
      begin
        perform public.wallet_credit_refund_split(new.id::text, new.user_id, v_saldo,
          'Cancelado pelo sistema: o saldo usado volta ao saldo', new.id::text);
        new.refund_amount := round(v_saldo / 100.0, 2)::double precision;
        new.refund_method := 'wallet';
        new.refund_status := 'completed';
        new.refunded_at   := now();
      exception when others then
        raise warning 'fn_reembolso_cancelado_pelo_sistema: saldo % %', new.id, sqlerrm;
        begin
          perform public.notify_admin_event('order_refund_failed', 'critical',
            format('Pedido #%s cancelado pelo sistema: o saldo usado (%s €) não voltou — %s',
                   substring(new.id::text,1,8), to_char(v_saldo / 100.0, 'FM999990.00'), sqlerrm),
            'order', new.id::text, jsonb_build_object('wallet_cents', v_saldo), '/admin/cancellations');
        exception when others then null;
        end;
      end;
    end if;
    return new;
  end if;

  v_eur := round(coalesce(new.stripe_charge_cents::numeric/100, new.payment_buffer_total::numeric, new.customer_total, new.total), 2);
  if coalesce(v_eur,0) <= 0 then return new; end if;
  new.refund_amount := v_eur::double precision;
  new.refund_method := 'stripe';
  new.refund_status := 'pending_auto';

  begin
    insert into public.cancellation_requests
      (order_id, requester_role, requester_id, reason, status, refund_method, auto_resolved, cancel_stage, fee_cents, refund_cents, reviewed_at)
    values
      (new.id, 'client', new.user_id,
       'Cancelado pelo sistema (' || coalesce(new.cancel_reason,'sem motivo') || ') — reembolso total automático ao meio de pagamento',
       'approved', 'stripe', true, 'grace', 0, round(v_eur*100)::int, now());
  exception when others then
    raise warning 'fn_reembolso_cancelado_pelo_sistema: cancellation_requests % %', new.id, sqlerrm;
  end;

  -- (a) 28/10: os tokens já não se devolvem aqui — trg_orders_devolver_tokens devolve os exatos.

  -- dispara o reembolso no Stripe (corre depois do commit)
  begin
    select decrypted_secret into v_key from vault.decrypted_secrets where name='service_role_key';
    if v_key is not null then
      perform net.http_post(
        url := 'https://ojykpzwqrtusfeakzrna.supabase.co/functions/v1/auto-refund-order',
        headers := jsonb_build_object('Content-Type','application/json','Authorization','Bearer '||v_key),
        body := jsonb_build_object('order_id', new.id::text, 'motivo', coalesce(new.cancel_reason,'cancelado_pelo_sistema')));
    end if;
  exception when others then
    raise warning 'fn_reembolso_cancelado_pelo_sistema: http % %', new.id, sqlerrm;
  end;

  begin
    perform public.notify_admin_event(
      'order_refund_auto', 'high',
      format('Pedido pago #%s cancelado pelo sistema — %s € a voltar ao %s do cliente', substring(new.id::text,1,8), to_char(v_eur,'FM999990.00'), case when new.payment_method::text='mbway' then 'MB Way' else 'cartão' end),
      'order', new.id::text,
      jsonb_build_object('refund_amount', v_eur, 'refund_method', 'stripe', 'cancel_reason', new.cancel_reason),
      '/admin/cancellations');
  exception when others then
    raise warning 'fn_reembolso_cancelado_pelo_sistema: notify % %', new.id, sqlerrm;
  end;
  return new;
exception when others then
  raise warning 'fn_reembolso_cancelado_pelo_sistema: %', sqlerrm;
  return new;
end;
$function$;
```

Nota sobre o §5(b): depende de `wallet_split_free_pct = 1` para ser 100% saldo (como todas as
devoluções para a carteira). Se o Danilo preferir não depender do setting, troca-se por
`wallet_credit_refund_full`, mas essa não tem chave de idempotência.

## Prova já feita (local, PGlite = Postgres 16 em WASM, base falsa)

Guião: `C:\Users\danil\AppData\Local\Temp\claude\C--BoraLocal-projetosflutter-bora-app-bora-app\84fbcd7f-d493-4816-b0cd-9144ae9fabd3\scratchpad\provar_tokens.mjs`
(lê ESTE ficheiro, corre os blocos `[APLICAR n]` tal e qual, com stubs de `auth.uid()`, `is_admin`,
`get_setting`, `notify_admin_event`, `wallet_credit_refund_split`, `net.http_post`, `vault`).
O resultado está no fim deste ficheiro, na secção "Saída da prova local".

## Prova esperada em produção (Claude.ai, EM ROLLBACK, depois de aplicar)

Tudo dentro de `begin; … rollback;` (ou `DO $$ … RAISE EXCEPTION 'fim da prova' $$` — memória
`prova-em-rollback-por-do-raise`), com uma conta de teste (memória `contas-demo`):

1. `select set_config('request.jwt.claims', json_build_object('sub', '<uuid conta teste>', 'role', 'authenticated')::text, true);`
2. Dar à conta 2 linhas: 100 tokens a expirar em 10 dias, 300 a expirar em 40 dias (INSERT em
   `bora_tokens`, só dentro da transação).
3. Criar um pedido a dinheiro pelo `create_order` com `token_discount_cents = 150` (300 tokens).
   Esperado: `pedido_tokens_gastos` com 2 linhas (100 com validade +10 d; 200 com +40 d);
   `orders.tokens_applied_count = 300`; `get_user_tokens` = 100 (sobra de 100 com validade +40 d).
4. `select consume_tokens('<uuid>', 300);` como o cliente → `true` e saldo de tokens continua 100
   (ponte); a 2.ª chamada → `false` (saldo insuficiente, não gasta).
5. Cancelar o pedido (UPDATE `status = 'cancelled'` só dentro da transação, ou o caminho
   `client-cancel-order` em teste) → `get_user_tokens` = 400; as 2 linhas novas têm as validades
   +10 d e +40 d; `devolucao_resultado = 'devolvido'`.
6. Repetir o cancelamento (`cancelled → created → cancelled`) → `already_applied`, continua 400.
7. Pedido de teste a dinheiro com saldo 3,00 € cancelado com `cancellation_initiator = 'system'`
   → `wallet_transactions` com `refund_credit_free 300` e `orders.refund_status = 'completed'`.
8. `rollback;` e confirmar que nada ficou: `select count(*) from pedido_tokens_gastos where order_id = '<id>'` = 0.

Se um guarda do INSERT de `orders` recusar o pedido sintético, usa-se o `create_order` da conta demo
(nunca um pedido real).

## Como reverter

```sql
-- [REVERTER] (não faz parte da aplicação)
drop trigger if exists trg_orders_consumir_tokens on public.orders;
drop trigger if exists trg_orders_devolver_tokens on public.orders;
-- repor as duas funções a partir dos backups:
--   select definicao from public.bkp_consume_tokens_20261028;                 → executar o texto
--   select definicao from public.bkp_fn_reembolso_cancelado_pelo_sistema_20261028; → executar o texto
-- a tabela pedido_tokens_gastos fica (é histórico); as funções novas podem ficar sem gatilho.
```

Depois de reverter, a app antiga volta a ser a única a gastar tokens (como hoje).

## Passo (3) — a app (só depois de (1) e (2) estarem no ar)

`lib/screens/payment_method_screen.dart`: `_consumeTokensAndNavigate(int tokensUsed)` (linhas
1531-1549) deixa de chamar `rpc('consume_tokens')` e passa só a navegar (o nome fica
`_navegarDepoisDoPedido`); as 4 chamadas (1224, 1393, 1474, 1527) continuam iguais. Opcional:
mostrar no recibo `orders.tokens_applied_count` (o que o servidor gastou mesmo). Quando a versão
mínima obrigatória da app for a que já não chama `consume_tokens`, a PONTE do §3 pode sair
(repor o `consume_tokens` do backup). A ponte não atrapalha o TVDE (`bora.internal_token_consume`
= 'on' salta-a) nem o `driver_convert_tokens`, salvo o caso raro de um estafeta converter tokens
nos 30 min a seguir a um pedido seu de cliente com tokens cuja chamada da app ainda não chegou.

## PARA O DANILO (decisões só dele; o resto segue)

1. Depois da recolha (taxa = 100% do pedido), os tokens gastos também voltam? A regra diz "os tokens
   gastos voltam" e é isso que está proposto; a Bora fica só com o dinheiro pago.
2. O `consume_tokens` gasta hoje também tokens de ESTAFETA no checkout de cliente (não filtra o
   papel). A proposta mantém igual (para não falhar pedidos) e devolve cada token ao papel de onde saiu.

⚠️ ISTO MEXE EM PAGAMENTO/DINHEIRO. Está tudo pronto — confirma que eu aplico.

## Saída da prova local

Corrida a 28/10 com `bun provar_tokens.mjs <pglite> 03_tokens_gastar_e_devolver.md` (saída inteira
em `...\scratchpad\prova_tokens.saida.txt`). Resultado: **6 blocos aplicados, 21 verificações OK,
0 falhas.** Resumo:

- Defeito de hoje confirmado com a definição no ar: 156 tokens, gasta 70, sistema cancela →
  saldo 242 em vez de 156 (devolve 86 a mais).
- S1: pedido com 1,50 € em tokens → ligação (100 com validade +10 d, 200 com +40 d),
  `tokens_applied_count = 300`, saldo 100.
- S2: app antiga chama `consume_tokens(300)` → TRUE e não gasta 2×; 2.ª chamada → FALSE.
- S3: cliente cancela → saldo 400; linhas novas com validades +10 d e +40 d.
- S4: cancelar outra vez → continua 400.
- S5: faltam tokens → `TOKENS_INSUFICIENTES`, o pedido não fica, tokens intactos.
- S6: token expirado entretanto → `expirado`, não volta.
- S7: pedido antigo sem registo → aviso ao admin, não adivinha.
- S8: sistema cancela pedido a dinheiro com 3,00 € de saldo → 300 c ao saldo, `refund_status
  completed`, sem duplicar.
- S9: sistema cancela pedido pago a cartão com tokens → `pending_auto` + 1 chamada ao
  auto-refund-order; tokens voltam a 156 exatos.
