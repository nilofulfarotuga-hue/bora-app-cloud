-- =============================================================================
-- PROPOSTA — NÃO APLICADA — Reembolso ao meio de pagamento (regra do Danilo, 10/10/2026)
-- Missão: chamada-grita-2026-10-10 · agente pagamentos-wallet (PROPOSE-ONLY, zona vermelha)
-- Projeto Supabase: ojykpzwqrtusfeakzrna
--
-- ⚠️ ISTO MEXE EM PAGAMENTO/DINHEIRO. Está tudo pronto — confirma que eu aplico.
--
-- REGRA NOVA (todas as categorias):
--   • MB Way  → 100 % volta ao MB Way, automático, sem tokens.
--   • Cartão  → 100 % volta ao cartão por defeito; só vai para a carteira se o cliente carregar
--               em "Quero já em saldo na carteira" (consentimento registado) — e aí 100 % saldo,
--               nunca tokens.
--   • Pagamento só reservado (não capturado) → cancela-se a reserva (paymentIntents.cancel).
--   • Nunca tokens em vez de dinheiro pago. Nunca taxa quando não havia profissional.
--   • Aviso ao cliente quando a Stripe confirmar o reembolso (webhook).
--
-- O QUE ESTE FICHEIRO FAZ (só SQL; as Edges estão nos .md/.ts ao lado):
--   §1  Backup das funções e do setting que se mudam (bkp_*_20261010, RLS ligada).
--   §2  wallet_split_free_pct 0.80 → 1.00  (trava JÁ os tokens nas 4 Edges antigas que usam o split:
--       execute-cancellation, admin-cancel-order, reprocess-refund, client-cancel-order fora da graça).
--   §3  Tabela refund_choices — o consentimento "quero em saldo" fica escrito (só acrescentar).
--   §4  wallet_credit_refund_100 — crédito 100 % saldo, idempotente, exige consentimento quando é
--       dinheiro de cartão; serve também para devolver a parte paga com saldo.
--   §5  devolver_tokens_do_pedido — tokens usados num pedido cancelado voltam COMO TOKENS (nunca
--       viram saldo), só se houver prova de que foram mesmo gastos (o caso dcc8c509).
--   §6  fn_reembolso_cancelado_pelo_sistema v2 — corrige 3 falhas do gatilho de hoje.
--   §7  notificar_reembolso_confirmado — para o stripe-webhook avisar o cliente e fechar o estado.
--   §8  Permissões (fechado a anon/authenticated; só service_role).
--   §9  Prova em transação desfeita (como correr, o que tem de dar).
--   §10 Como desfazer.
--
-- ORDEM DE APLICAÇÃO (depois do "vai"):
--   1) este ficheiro (§1→§8) numa migration   supabase/migrations/20261010xxxxxx_reembolso_ao_meio.sql
--   2) PROPOSTA_devolver_ao_meio_de_pagamento.sql (botão do admin)
--   3) Edge cancel-order-with-choice v19 (PROPOSTA_cancel-order-with-choice_v19_index.ts)
--   4) stripe-webhook (diff descrito em PROPOSTA_cancel-order-with-choice.md §6)
--   5) app: refund_choice_dialog.dart (descrito no mesmo .md §5) — vai no próximo build
--   O passo 1 sozinho já é seguro: nada aqui muda dinheiro de pedidos antigos.
-- =============================================================================


-- =============================================================================
-- §1 BACKUP (antes de tudo)
-- =============================================================================
create table if not exists public.bkp_fn_reembolso_meio_20261010 (
  nome        text primary key,
  guardado_em timestamptz not null default now(),
  definicao   text not null
);
alter table public.bkp_fn_reembolso_meio_20261010 enable row level security;

insert into public.bkp_fn_reembolso_meio_20261010 (nome, definicao)
select p.oid::regprocedure::text, pg_get_functiondef(p.oid)
  from pg_proc p
 where p.pronamespace = 'public'::regnamespace
   and p.proname in ('fn_reembolso_cancelado_pelo_sistema',
                     'wallet_credit_refund_split',
                     'wallet_credit_refund_full')
on conflict (nome) do nothing;

create table if not exists public.bkp_platform_settings_reembolso_20261010 as
  select * from public.platform_settings where key = 'wallet_split_free_pct';
alter table public.bkp_platform_settings_reembolso_20261010 enable row level security;

-- prova do backup (tem de dar 3 funções + 1 setting com 0.80):
--   select nome, length(definicao) from public.bkp_fn_reembolso_meio_20261010;
--   select key, value from public.bkp_platform_settings_reembolso_20261010;


-- =============================================================================
-- §2 SPLIT 80/20 → 100 % SALDO (mitigação imediata)
-- Hoje (SELECT 10/10): wallet_split_free_pct = 0.80 → em wallet_credit_refund_split
--   free = ROUND(total × 0.80), tokens = (total − free) × 2  (1 token = 0,5 cêntimo,
--   token_value_cents_x100 = 50). Ex.: Divan 600 c → 480 c saldo + 240 tokens (= 120 c).
-- Com 1.00: free = total, tokens = 0 → o bloco "IF v_tokens_count > 0" não corre.
-- Isto não mexe em nenhum pedido passado.
-- Caminho preferido (fica no histórico do painel): Danilo no painel, ou
--   select public.admin_update_money_setting('wallet_split_free_pct', '1.00'::jsonb,
--          'Regra 10/10/2026: nunca tokens em vez de dinheiro pago');
-- Caminho por SQL (se aplicado pela migration):
update public.platform_settings
   set value = '1.00'::jsonb, updated_at = now()
 where key = 'wallet_split_free_pct';


-- =============================================================================
-- §3 CONSENTIMENTO "QUERO JÁ EM SALDO NA CARTEIRA"
-- Uma escolha por pedido (vertical + referência). Escrito só pela Edge (service_role).
-- O cliente lê a sua; o admin lê todas. Só acrescentar (como wallet_transactions).
-- =============================================================================
create table if not exists public.refund_choices (
  id             uuid primary key default gen_random_uuid(),
  vertical       text not null default 'order'
                 check (vertical in ('order','tvde','cleaning','carwash','appointment','reservation')),
  referencia_id  text not null,
  user_id        uuid not null references auth.users(id) on delete cascade,
  escolha        text not null check (escolha in ('meio_original','carteira')),
  meio_pagamento text,                       -- 'card' | 'mbway' (no momento da escolha)
  valor_cents    integer not null check (valor_cents >= 0),
  texto_mostrado text not null,              -- o texto exato que o cliente viu ao carregar
  app_version    text,
  plataforma     text,
  created_at     timestamptz not null default now()
);
create unique index if not exists uq_refund_choices_ref
  on public.refund_choices (vertical, referencia_id);
create index if not exists idx_refund_choices_user
  on public.refund_choices (user_id, created_at desc);

alter table public.refund_choices enable row level security;

drop policy if exists refund_choices_select on public.refund_choices;
create policy refund_choices_select on public.refund_choices
  for select to authenticated
  using (user_id = auth.uid() or public.is_admin());
-- sem policy de insert/update/delete → só service_role escreve.

create or replace function public._refund_choices_so_acrescentar()
returns trigger language plpgsql as $$
begin
  raise exception 'refund_choices é só de acrescentar (consentimento não se apaga nem se altera)'
    using errcode = '55000';
end $$;

drop trigger if exists trg_refund_choices_so_acrescentar on public.refund_choices;
create trigger trg_refund_choices_so_acrescentar
  before update or delete on public.refund_choices
  for each row execute function public._refund_choices_so_acrescentar();


-- =============================================================================
-- §4 CRÉDITO 100 % SALDO, IDEMPOTENTE (substitui o split nos caminhos novos)
--   p_origem = 'parte_paga_com_carteira' → devolve ao saldo o que foi pago com saldo
--              (é o "meio de pagamento original" dessa parte; não precisa de consentimento)
--   p_origem = 'consentimento_cliente'   → dinheiro de cartão que o cliente PEDIU em saldo;
--              exige linha em refund_choices (escolha='carteira').
-- Nunca cria tokens. Chave = 'refund100_<origem>_<pedido>' → 2.º toque = already_applied.
-- O saldo de client_wallets é recalculado no commit a partir de wallet_transactions
-- (_wallet_tx_sync_balance → wallet_recompute_balance); dívida antiga abate-se sozinha pela soma.
-- =============================================================================
create or replace function public.wallet_credit_refund_100(
  p_order_id text,
  p_user_id  uuid,
  p_cents    integer,
  p_reason   text,
  p_origem   text
) returns jsonb
language plpgsql
security definer
set search_path to 'public'
as $$
declare
  v_key text;
  v_id  uuid;
  v_ex  record;
begin
  if p_cents is null or p_cents <= 0 then raise exception 'valor_tem_de_ser_positivo'; end if;
  if p_user_id is null then raise exception 'user_required'; end if;
  if p_order_id is null or length(trim(p_order_id)) = 0 then raise exception 'order_required'; end if;
  if p_reason is null or length(trim(p_reason)) < 3 then raise exception 'reason_required'; end if;
  if p_origem not in ('parte_paga_com_carteira', 'consentimento_cliente') then
    raise exception 'origem_invalida: %', p_origem;
  end if;

  if p_origem = 'consentimento_cliente' and not exists (
       select 1 from public.refund_choices
        where referencia_id = p_order_id and user_id = p_user_id and escolha = 'carteira') then
    raise exception 'sem_consentimento_do_cliente' using errcode = '42501';
  end if;

  v_key := 'refund100_' || p_origem || '_' || p_order_id;

  insert into public.wallet_transactions
    (user_id, amount_cents, kind, reason, related_order_id, idempotency_key)
  values
    (p_user_id, p_cents, 'refund_credit_free', p_reason, p_order_id, v_key)
  on conflict (idempotency_key) do nothing
  returning id into v_id;

  if v_id is null then
    select amount_cents, balance_after_cents into v_ex
      from public.wallet_transactions where idempotency_key = v_key;
    return jsonb_build_object('success', true, 'already_applied', true,
                              'free_cents', v_ex.amount_cents, 'tokens_count', 0,
                              'tokens_value_cents', 0);
  end if;

  begin
    perform public.log_admin_action('wallet_refund_100', 'order', p_order_id::text,
      jsonb_build_object('order_id', p_order_id, 'user_id', p_user_id, 'cents', p_cents,
                         'origem', p_origem, 'idempotency_key', v_key));
  exception when others then
    raise notice 'wallet_credit_refund_100: log falhou (%): %', p_order_id, sqlerrm;
  end;

  return jsonb_build_object('success', true, 'already_applied', false,
                            'free_cents', p_cents, 'tokens_count', 0, 'tokens_value_cents', 0,
                            'transaction_id', v_id);
end $$;


-- =============================================================================
-- §5 TOKENS USADOS VOLTAM COMO TOKENS (nunca como saldo)
-- Factos (SELECT 10/10):
--   • A app só gasta os tokens DEPOIS do pagamento passar (payment_method_screen.dart
--     _consumeTokensAndNavigate → consume_tokens), e consume_tokens não sabe de que pedido é.
--   • orders.tokens_applied_count está a 0 em TODOS os 13 pedidos com tokens dos últimos 60 dias,
--     por isso lerPagoDoPedido (desde 05/10) ignora os tokens → hoje, quem cancela um pedido
--     pago com tokens PERDE os tokens; antes de 05/10 eles viravam saldo (caso dcc8c509: 5,51 €
--     de saldo por tokens que nunca chegaram a ser gastos).
-- Regra: se o meio era cartão/MB Way e a Stripe não cobrou nada → os tokens nunca saíram → 0.
--        Senão, só devolve se houver prova de consumo (tokens gastos entre −2 min e +30 min da
--        criação do pedido, em quantidade ≥ à devida). Sem prova → 0 + aviso ao admin.
-- Idempotente pelo índice único bora_tokens(source_order_id, role): source = 'devolucao:<pedido>'.
-- Arredondamento: o pedido guarda ROUND(tokens × 0,5) cêntimos → a contagem pode sair com +1
-- token (0,5 cêntimo). Aceite.
-- =============================================================================
create or replace function public.devolver_tokens_do_pedido(p_order_id text, p_motivo text)
returns jsonb
language plpgsql
security definer
set search_path to 'public'
as $$
declare
  v_o     record;
  v_x100  numeric;
  v_count integer;
  v_prova integer;
  v_id    uuid;
begin
  select id, user_id, created_at, payment_method::text as pm,
         coalesce(stripe_charge_cents, 0) as sc,
         coalesce(tokens_applied_value_cents, 0) as tv
    into v_o
    from public.orders where id::text = p_order_id;
  if not found then
    return jsonb_build_object('ok', false, 'tokens', 0, 'motivo', 'pedido_nao_encontrado');
  end if;
  if v_o.tv <= 0 or v_o.user_id is null then
    return jsonb_build_object('ok', true, 'tokens', 0, 'motivo', 'pedido_sem_tokens');
  end if;
  if v_o.pm in ('card', 'mbway') and v_o.sc <= 0 then
    return jsonb_build_object('ok', true, 'tokens', 0,
                              'motivo', 'pagamento_nunca_cobrado_tokens_nunca_gastos');
  end if;

  v_x100  := coalesce(nullif(public.get_setting('token_value_cents_x100') #>> '{}', '')::numeric, 50);
  v_count := round(v_o.tv * 100 / v_x100)::int;

  select coalesce(sum(amount), 0) into v_prova
    from public.bora_tokens
   where user_id = v_o.user_id and role = 'client' and is_used
     and used_at between v_o.created_at - interval '2 minutes'
                     and v_o.created_at + interval '30 minutes';

  if v_prova < v_count then
    begin
      perform public.notify_admin_event('tokens_sem_prova_de_consumo', 'medium',  -- CHECK aceita low|medium|high|critical
        format('Pedido #%s cancelado: %s tokens por devolver sem prova de que foram gastos — ver à mão',
               substring(p_order_id, 1, 8), v_count),
        'order', p_order_id,
        jsonb_build_object('esperado', v_count, 'visto', v_prova, 'motivo', p_motivo),
        '/admin/cancellations');
    exception when others then null;
    end;
    return jsonb_build_object('ok', false, 'tokens', 0, 'motivo', 'sem_prova_de_consumo',
                              'esperado', v_count, 'visto', v_prova);
  end if;

  v_id := public.add_tokens(v_o.user_id, 'client', v_count, 'devolucao:' || p_order_id);
  return jsonb_build_object('ok', true, 'tokens', v_count,
                            'token_id', v_id, 'already_applied', v_id is null);
end $$;


-- =============================================================================
-- §6 GATILHO DO SISTEMA v2 — fn_reembolso_cancelado_pelo_sistema
-- Hoje (definição lida 10/10) está CERTO no essencial (cartão/MB Way pago + cancelado pelo
-- sistema → auto-refund-order → Stripe, cancela a reserva se 'requires_capture'; prova:
-- 947f7206, 18,68 € de volta ao MB Way em 07/10). Três falhas que esta v2 corrige:
--   (a) v_eur = coalesce(stripe_charge_cents/100, …): com stripe_charge_cents = 0 dá 0 e NÃO
--       reembolsa (o coalesce não salta o 0). Passa a nullif(…,0).
--   (b) devolve tokens por "janela de tempo" e marca como não usados tokens que podem ser de
--       OUTRO pedido feito logo a seguir. Passa a devolver_tokens_do_pedido (§5).
--   (c) a parte paga com saldo (wallet_applied_cents) não voltava. Passa a voltar 100 % ao saldo.
--   (d) rede de segurança: também dispara para cancelamento do CLIENTE sem estafeta quando
--       nenhuma Edge tratou do dinheiro (refund_status vazio e ainda 'paid'). NOTA: isto sozinho
--       NÃO corrige o caso do Divan — a Edge cancel-order-with-choice grava refund_status no
--       mesmo UPDATE, por isso o gatilho não entra. A correção do Divan está na Edge (v19) e na app.
-- =============================================================================
create or replace function public.fn_reembolso_cancelado_pelo_sistema()
returns trigger
language plpgsql
security definer
set search_path to 'public', 'vault'
as $function$
declare
  v_eur numeric;
  v_key text;
  v_init text := coalesce(new.cancellation_initiator::text, '');
begin
  if new.status::text not in ('cancelled','rejected') or old.status is not distinct from new.status then return new; end if;
  -- (d) sistema sempre; cliente só quando não havia estafeta
  if not (v_init = 'system' or (v_init = 'client' and new.assigned_driver_id is null)) then return new; end if;
  if new.payment_method::text not in ('card','mbway') then return new; end if;
  if new.refund_status is not null then return new; end if;
  if coalesce(new.payment_status::text,'') <> 'paid' and coalesce(new.stripe_charge_cents,0) <= 0 then return new; end if;
  if coalesce(new.is_test_order,false) then return new; end if;

  -- (a) o 0 já não engana o coalesce
  v_eur := round(coalesce(nullif(new.stripe_charge_cents,0)::numeric/100,
                          nullif(new.payment_buffer_total,0)::numeric,
                          nullif(new.customer_total,0)::numeric,
                          new.total::numeric), 2);
  if coalesce(v_eur,0) <= 0 then return new; end if;
  new.refund_amount := v_eur::double precision;
  new.refund_method := 'stripe';
  new.refund_status := 'pending_auto';

  begin
    insert into public.cancellation_requests
      (order_id, requester_role, requester_id, reason, status, refund_method, auto_resolved, cancel_stage, fee_cents, refund_cents, reviewed_at)
    values
      (new.id, 'client', new.user_id,
       'Cancelado (' || v_init || ': ' || coalesce(new.cancel_reason,'sem motivo') || ') — reembolso total automático ao meio de pagamento',
       'approved', 'stripe', true, 'grace', 0, round(v_eur*100)::int, now());
  exception when others then
    raise warning 'fn_reembolso_cancelado_pelo_sistema: cancellation_requests % %', new.id, sqlerrm;
  end;

  -- (b) tokens voltam como tokens, só com prova de consumo
  begin
    perform public.devolver_tokens_do_pedido(new.id::text, 'cancelado_' || v_init);
  exception when others then
    raise warning 'fn_reembolso_cancelado_pelo_sistema: tokens % %', new.id, sqlerrm;
  end;

  -- (c) a parte paga com saldo volta ao saldo (100 %, idempotente)
  begin
    if coalesce(new.wallet_applied_cents,0) > 0 and new.user_id is not null then
      perform public.wallet_credit_refund_100(new.id::text, new.user_id, new.wallet_applied_cents,
        'Devolução da parte paga com saldo — pedido ' || substring(new.id::text,1,8) || ' cancelado',
        'parte_paga_com_carteira');
    end if;
  exception when others then
    raise warning 'fn_reembolso_cancelado_pelo_sistema: saldo % %', new.id, sqlerrm;
  end;

  -- dispara o reembolso na Stripe (net.http_post só sai depois do commit)
  begin
    select decrypted_secret into v_key from vault.decrypted_secrets where name='service_role_key';
    if v_key is not null then
      perform net.http_post(
        url := 'https://ojykpzwqrtusfeakzrna.supabase.co/functions/v1/auto-refund-order',
        headers := jsonb_build_object('Content-Type','application/json','Authorization','Bearer '||v_key),
        body := jsonb_build_object('order_id', new.id::text, 'motivo', coalesce(new.cancel_reason,'cancelado_' || v_init)));
    end if;
  exception when others then
    raise warning 'fn_reembolso_cancelado_pelo_sistema: http % %', new.id, sqlerrm;
  end;

  begin
    perform public.notify_admin_event(
      'order_refund_auto', 'high',
      format('Pedido pago #%s cancelado (%s) — %s € a voltar ao %s do cliente',
             substring(new.id::text,1,8), v_init, to_char(v_eur,'FM999990.00'),
             case when new.payment_method::text='mbway' then 'MB Way' else 'cartão' end),
      'order', new.id::text,
      jsonb_build_object('refund_amount', v_eur, 'refund_method', 'stripe', 'cancel_reason', new.cancel_reason,
                         'initiator', v_init),
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
-- O gatilho trg_reembolso_cancelado_pelo_sistema (BEFORE UPDATE OF status ON orders) mantém-se;
-- CREATE OR REPLACE FUNCTION basta, não há DROP de gatilho (a Trava lê DROP em orders como DDL).


-- =============================================================================
-- §7 AVISO QUANDO A STRIPE CONFIRMA (para o stripe-webhook chamar)
-- Hoje o webhook v36 só faz console.log em charge.refunded (L917-923) e não trata refund.*
-- → refund_status fica 'pending' para sempre e o cliente nunca recebe "o reembolso chegou".
-- Esta função fecha o estado do pedido e escreve a notificação in-app (1 vez por reembolso);
-- devolve user_id + texto para o webhook mandar também o push (notify-client).
-- =============================================================================
create or replace function public.notificar_reembolso_confirmado(
  p_payment_intent_id text,
  p_refund_id         text,
  p_cents             integer,
  p_estado            text      -- 'succeeded' | 'failed' | 'canceled' | 'pending'
) returns jsonb
language plpgsql
security definer
set search_path to 'public'
as $$
declare
  v_o     record;
  v_meio  text;
  v_body  text;
begin
  select id::text as oid, user_id, payment_method::text as pm
    into v_o
    from public.orders where payment_intent_id = p_payment_intent_id
   order by created_at desc limit 1;
  if not found then
    return jsonb_build_object('ok', false, 'motivo', 'pedido_nao_encontrado');
  end if;

  if p_estado = 'succeeded' then
    update public.orders
       set refund_status = 'refunded',
           refunded_at   = coalesce(refunded_at, now()),
           refund_id     = coalesce(refund_id, p_refund_id)
     where id::text = v_o.oid
       and coalesce(refund_status,'') in ('pending','pending_auto','processing','refunded','succeeded');

    v_meio := case when v_o.pm = 'mbway' then 'ao teu MB Way' else 'ao teu cartão' end;
    v_body := format('Devolvemos %s € %s.%s',
                     to_char(p_cents::numeric/100, 'FM999990.00'), v_meio,
                     case when v_o.pm = 'card'
                          then ' Pode demorar 5 a 10 dias úteis a aparecer no extrato.' else '' end);

    if v_o.user_id is not null and not exists (
         select 1 from public.in_app_notifications
          where user_id = v_o.user_id and kind = 'refund_confirmed' and related_id = v_o.oid) then
      perform public._push_in_app_notification(v_o.user_id, 'refund_confirmed',
                                               'Reembolso confirmado', v_body, v_o.oid);
    end if;
    return jsonb_build_object('ok', true, 'order_id', v_o.oid, 'user_id', v_o.user_id,
                              'title', 'Reembolso confirmado', 'body', v_body);
  elsif p_estado in ('failed', 'canceled') then
    update public.orders set refund_status = 'failed'
     where id::text = v_o.oid and coalesce(refund_status,'') in ('pending','pending_auto','processing');
    begin
      perform public.notify_admin_event('order_refund_failed', 'high',
        format('Reembolso %s do pedido #%s FALHOU na Stripe (%s €)', p_refund_id,
               substring(v_o.oid,1,8), to_char(p_cents::numeric/100,'FM999990.00')),
        'order', v_o.oid, jsonb_build_object('refund_id', p_refund_id, 'estado', p_estado),
        '/admin/cancellations');
    exception when others then null;
    end;
    return jsonb_build_object('ok', true, 'order_id', v_o.oid, 'estado', p_estado);
  end if;
  return jsonb_build_object('ok', true, 'order_id', v_o.oid, 'estado', p_estado, 'nada_a_fazer', true);
end $$;


-- =============================================================================
-- §8 PERMISSÕES — tudo fechado; só a service_role (Edges e gatilhos SECURITY DEFINER)
-- =============================================================================
revoke all on function public.wallet_credit_refund_100(text, uuid, integer, text, text) from public, anon, authenticated;
revoke all on function public.devolver_tokens_do_pedido(text, text)                     from public, anon, authenticated;
revoke all on function public.notificar_reembolso_confirmado(text, text, integer, text) from public, anon, authenticated;
grant execute on function public.wallet_credit_refund_100(text, uuid, integer, text, text) to service_role;
grant execute on function public.devolver_tokens_do_pedido(text, text)                     to service_role;
grant execute on function public.notificar_reembolso_confirmado(text, text, integer, text) to service_role;
revoke all on table public.refund_choices from anon;
grant select on table public.refund_choices to authenticated;   -- a policy limita a "o meu" / admin
grant all    on table public.refund_choices to service_role;


-- =============================================================================
-- §9 PROVA EM TRANSAÇÃO DESFEITA (correr DEPOIS do "vai", ANTES de aplicar de vez)
-- Molde já usado no Bora ("Provas em rollback: DO + RAISE"): tudo dentro de UMA chamada
-- ao execute_sql, a terminar com RAISE EXCEPTION → o Postgres desfaz tudo. net.http_post só
-- envia depois do commit → numa transação desfeita NENHUM pedido sai para a Stripe.
--
--   BEGIN;
--     <§1 a §8 deste ficheiro>
--     -- T1: split já não dá tokens (utilizador demo@bora.app, pedido fictício)
--     select public.wallet_credit_refund_split('prova-split-20261010',
--            (select id from auth.users where email='demo@bora.app'), 600, 'prova split', 'prova-split-20261010');
--        → esperado: free_cents=600, tokens_count=0
--     -- T2: crédito de cartão sem consentimento é recusado
--     select public.wallet_credit_refund_100('prova-100-20261010',
--            (select id from auth.users where email='demo@bora.app'), 600, 'prova', 'consentimento_cliente');
--        → esperado: ERRO sem_consentimento_do_cliente
--     -- T3: com consentimento entra 1 vez; 2.ª vez already_applied=true
--     insert into public.refund_choices (referencia_id, user_id, escolha, meio_pagamento, valor_cents, texto_mostrado)
--       values ('prova-100-20261010', (select id from auth.users where email='demo@bora.app'),
--               'carteira', 'card', 600, 'Quero já em saldo na carteira');
--     select public.wallet_credit_refund_100(... mesmo ...);   → free_cents=600
--     select public.wallet_credit_refund_100(... mesmo ...);   → already_applied=true
--     -- T4: o caso dcc8c509 (MB Way falhado) já não devolve nada
--     select public.devolver_tokens_do_pedido('dcc8c509-38dd-4f66-a79e-3612336fd792', 'prova');
--        → esperado: tokens=0, motivo=pagamento_nunca_cobrado_tokens_nunca_gastos
--     -- T5: gatilho v2 num pedido real cancelado+pago (ex. c5eba567, MB Way 6 €, entregue):
--     --     update orders set status='cancelled', cancellation_initiator='system' where id='c5eba567-…';
--     --     select refund_status, refund_amount from orders where id='c5eba567-…';
--     --     → esperado: pending_auto, 6.00   (o http_post fica na fila e é DESFEITO no rollback)
--     -- T6: o 0 já não engana: pedido pago com stripe_charge_cents=0 → refund_amount = payment_buffer_total
--   ROLLBACK;
--
-- Em execute_sql: pôr os testes num DO $$ … RAISE EXCEPTION 'PROVA %', jsonb_build_object(…) $$;
-- a mensagem do erro traz os resultados e garante o rollback. Ler a mensagem, nunca só o "ok".
-- Depois do rollback: select key, value from platform_settings where key='wallet_split_free_pct'
-- tem de continuar 0.80 (prova de que nada ficou).


-- =============================================================================
-- §10 COMO DESFAZER (se algo correr mal depois de aplicado)
-- =============================================================================
--   update public.platform_settings p set value = b.value, updated_at = now()
--     from public.bkp_platform_settings_reembolso_20261010 b where p.key = b.key;
--   -- repor o gatilho antigo:
--   do $$ declare d text; begin
--     select definicao into d from public.bkp_fn_reembolso_meio_20261010
--      where nome = 'fn_reembolso_cancelado_pelo_sistema()';
--     execute d;
--   end $$;
--   -- as funções novas (§4, §5, §7) e refund_choices podem ficar: ninguém as chama sem a Edge v19.


-- =============================================================================
-- DECISÃO DO DANILO (bloco comentado; NÃO faz parte da migration)
-- Caso dcc8c509 (Divan, 03/10): 5,51 € de saldo livre criados por tokens que NUNCA foram gastos
-- (o MB Way falhou; os mesmos 1101 tokens foram gastos 2 min depois no pedido b18d2675).
-- O saldo ainda está por gastar (saldo atual do Divan = 10,31 € = 5,51 + 4,80).
-- Se o Danilo decidir anular (em vez de deixar como oferta):
--   insert into public.wallet_transactions (user_id, amount_cents, kind, reason, related_order_id, idempotency_key)
--   values ('fee289f5-d74a-49ff-8c4a-a6eed22d9006', -551, 'adjustment',
--           'Anulado: crédito de 5,51 € do pedido dcc8c509 vinha de tokens que nunca foram gastos (MB Way falhou)',
--           'dcc8c509-38dd-4f66-a79e-3612336fd792', 'anular_credito_sem_pagamento_dcc8c509');
--   (antes: backup bkp_client_wallets_divan_20261010; depois: select free_balance_cents → 480 ou 0 se
--    o botão do d383a09e já tiver corrido)
-- =============================================================================
