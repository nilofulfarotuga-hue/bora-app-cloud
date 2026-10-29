# C5 — Stripe Connect fase 2 · 02 · Proposta (repasse ao parceiro no fecho semanal)

Missão `final-app-2026-10-29`, Bloco 7 C5. Agente `pagamentos-wallet` (PROPOSE-ONLY).
**Nada disto foi aplicado, deployado nem testado em produção.** O SQL e o TypeScript abaixo
são texto de proposta; foram escritos contra as definições vivas lidas hoje (ver `01_estado_atual.md`).
Âmbito: **parceiros restaurante** (`restaurants` → `partner_weekly_settlements`). Estafetas, limpeza,
serviços e lavagem têm acertos noutras tabelas e ficam para uma fase 2c (a mesma Edge Function serve
com um segundo "adaptador").

## 1. A proposta numa frase

Uma Edge Function nova, `stripe-connect-transfer`, que para cada acerto semanal de parceiro
**aberto, a favor do parceiro, com conta Connect pronta e depois do período de espera** cria uma
transferência Stripe (`transfers.create`, em EUR) para a conta do parceiro, com **chave de
idempotência derivada do id do acerto**, regista-a numa tabela nova (`stripe_connect_transfers`,
uma transferência viva por acerto, garantido por índice único) e só depois marca o acerto como
pago **pelo caminho oficial** (`admin_set_settlement_state`, com o JWT do admin que carregou no botão).
Começa **só por botão do admin** (fase 2a); o agendamento de terça (fase 2b) só entra depois de
3 semanas limpas e de uma decisão do Danilo (secção 9, D5).

## 2. Matemática

Entrada: `partner_weekly_settlements.net_balance` (euros, 2 casas) já calculado pelo fecho
(`ROUND(partner_share − cash_kept_by_partner, 2)`, ver `01` §2.1). A fase 2 **não recalcula** o acerto.

```
gross_cents  = ROUND(net_balance × 100)                       -- o que o recibo diz
fee_cents    = 0                                              -- modo 'none' (por defeito: a Bora absorve)
             = stripe_connect_fee_cents(gross_cents,'payout') -- modo 'payout_only' (desconta ao parceiro)
amount_cents = gross_cents − fee_cents                        -- o que vai para a Stripe
condições    = net_balance > 0  E  direction = 'bora_pays_partner'
             E  amount_cents ≥ stripe_connect_min_transfer_cents (500)
             E  agora ≥ week_end_at + stripe_connect_cooldown_hours (36 h)
```

Exemplos com valores reais do histórico (acertos de Goola e Sabores de Casa Açaí):

| Acerto | gross_cents | fee 'none' | amount 'none' | fee 'payout_only' | amount 'payout_only' |
|---|---|---|---|---|---|
| 9,90 € | 990 | 0 | 990 | ROUND(990×0,0025)+25 = 2+25 = 27 | 963 |
| 30,28 € | 3028 | 0 | 3028 | ROUND(3028×0,0025)+25 = 8+25 = 33 | 2995 |
| 3,40 € (hipótese) | 340 | — | abaixo do mínimo (500): fica pendente | — | — |

- O que sai da conta Stripe da Bora é sempre `amount_cents`; o parceiro vê no extrato `sale`, `commission`,
  eventual `adjustment` (dinheiro que ele já cobrou) e `payout`, e a soma bate com `amount_cents`.
- **Negativos nunca vão por Stripe**: `partner_pays_bora` (ex.: −5,41 €) continua como hoje (o parceiro paga à Bora;
  a Stripe Connect Express não permite debitar a conta do parceiro).
- Custo para a Bora no modo `none` com os 2 parceiros de hoje: 4,00 €/mês fixos (2 € por conta) + 0,27–0,33 €
  por transferência semanal e parceiro (valores do livro, 06/08; confirmar na Stripe antes de ligar).

Idempotência: `idempotency_key = 'bora-pws-<settlement_id>-<modo>-a<tentativa>'` e `transfer_group = 'pws_<settlement_id>'`.
A mesma tentativa repetida devolve a mesma transferência (a Stripe guarda a resposta 24 h); uma tentativa nova só nasce
depois de a anterior ficar `failed` (a Stripe devolve igualmente o erro antigo para a mesma chave).

## 3. Decisões de desenho (e porquê)

1. **Uma transferência por acerto, garantida na base de dados**, não só na Stripe: índice único parcial sobre
   `(settlement_id)` para o modo `live` em estados `creating/succeeded/needs_review`. Reabrir e voltar a pagar um acerto
   já transferido (o buraco de `admin_reabrir_acerto` / `admin_unmark_settlement`) **falha por construção**.
2. **O destino é lido do banco, o valor também; nunca vêm do pedido.** O pedido só traz o id do acerto.
3. **Modo teste independente.** `CONNECT_TRANSFER_MODE` (`test` por defeito) é lido só por esta função. **Não se usa
   `BORA_STRIPE_MODE`**: esse interruptor é global e põe também o TVDE e os pagamentos em modo teste (`GUIA_DANILO_STRIPE_CONNECT.md:62-69`).
   Em `live` a chave tem de ser de produção e em `test` de teste (o prefixo da chave é verificado no arranque; impede misturar).
4. **Em modo teste a função nunca toca no estado do acerto** (nem o marca pago, nem escreve extrato). Só escreve a linha de
   `stripe_connect_transfers` com `mode='test'`.
5. **Interruptor do dinheiro novo e separado:** `stripe_connect_transfers_enabled` (começa `false`). `stripe_connect_enabled`
   fica como está (UI do Connect); ver efeito lateral na secção 8, R9.
6. **Ledger e `payouts` não são escritos nesta fase.** Motivo medido: os 5 pagamentos manuais de parceiros nunca abateram
   o saldo do ledger (122,37 € = soma das linhas `earning`) e o caminho antigo de payouts deixou 10 linhas `failed` e 20 entradas que somam 0,00
   (`01` §2.2–2.3). Escrever agora uma saída no ledger só para as semanas Stripe deixaria o saldo incoerente com as semanas pagas à mão.
   Se o Danilo quiser o ledger abatido, é uma missão própria (reconciliar o saldo antigo primeiro) e usa a função oficial de criar payout;
   não se improvisa aqui. Decisão D4.
7. **Marcar pago pelo caminho oficial.** A função oficial exige utilizador admin autenticado, por isso na fase 2a quem a chama é o
   JWT do admin que carregou no botão. A fase 2b (agendamento sem admin) precisaria de um caminho novo de escrita — secção 7, decisão D5.

## 4. SQL proposto (migration `20261102000100_stripe_connect_fase2_transferencias.sql` — NÃO aplicada)

Aplicação: pela Claude.ai com o "autorizo" do Danilo (a Trava do Claude Code recusa texto com chaves `stripe_` em `platform_settings`).
Depois de aplicada, guardar a cópia em `supabase/migrations/` (regra do repo). Todas as funções novas nascem **fechadas a `anon`**.

### 4.1 Tabela e índices

```sql
CREATE TABLE IF NOT EXISTS public.stripe_connect_transfers (
  id                 uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  settlement_id      uuid NOT NULL REFERENCES public.partner_weekly_settlements(id),
  partner_id         text NOT NULL,
  mode               text NOT NULL CHECK (mode IN ('test','live')),
  attempt            int  NOT NULL DEFAULT 1 CHECK (attempt >= 1),
  status             text NOT NULL DEFAULT 'creating'
                     CHECK (status IN ('creating','succeeded','failed','needs_review','reversed')),
  gross_cents        int  NOT NULL CHECK (gross_cents > 0),
  fee_cents          int  NOT NULL DEFAULT 0 CHECK (fee_cents >= 0),
  amount_cents       int  NOT NULL CHECK (amount_cents > 0),
  currency           text NOT NULL DEFAULT 'eur' CHECK (currency = 'eur'),
  stripe_account_id  text NOT NULL,
  stripe_transfer_id text,
  idempotency_key    text NOT NULL,
  transfer_group     text NOT NULL,
  requested_by       text NOT NULL,                -- 'admin:<uuid>' ou 'cron'
  error              text,
  created_at         timestamptz NOT NULL DEFAULT now(),
  updated_at         timestamptz NOT NULL DEFAULT now(),
  completed_at       timestamptz,
  CONSTRAINT stripe_connect_transfers_amount_ck CHECK (amount_cents = gross_cents - fee_cents)
);

-- Uma transferência VIVA por acerto (modo live). 'failed' e 'reversed' deixam tentar de novo.
CREATE UNIQUE INDEX IF NOT EXISTS ux_connect_transfer_live_per_settlement
  ON public.stripe_connect_transfers (settlement_id)
  WHERE mode = 'live' AND status IN ('creating','succeeded','needs_review');
CREATE UNIQUE INDEX IF NOT EXISTS ux_connect_transfer_idem
  ON public.stripe_connect_transfers (idempotency_key);
CREATE UNIQUE INDEX IF NOT EXISTS ux_connect_transfer_stripe_id
  ON public.stripe_connect_transfers (stripe_transfer_id) WHERE stripe_transfer_id IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_connect_transfer_partner
  ON public.stripe_connect_transfers (partner_id, created_at DESC);

ALTER TABLE public.stripe_connect_transfers ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.stripe_connect_transfers FROM PUBLIC, anon, authenticated;
GRANT SELECT ON public.stripe_connect_transfers TO authenticated;
CREATE POLICY connect_transfers_admin_select ON public.stripe_connect_transfers
  FOR SELECT TO authenticated USING (public.is_admin());
-- Escrita: nenhuma policy → só service_role (as funções abaixo).
```

### 4.2 Settings (todos nascem desligados/conservadores; aparecem no ecrã "Pagamentos Connect", categoria `stripe_connect`)

```sql
INSERT INTO public.platform_settings (key, value, description, category) VALUES
 ('stripe_connect_transfers_enabled', 'false'::jsonb,
  'Interruptor do dinheiro: só com true o servidor cria transferencias Stripe para parceiros.', 'stripe_connect'),
 ('stripe_connect_auto_transfer_enabled', 'false'::jsonb,
  'Se true, o agendamento de terca envia sozinho. Se false, so o admin envia pelo botao.', 'stripe_connect'),
 ('stripe_connect_min_transfer_cents', '500'::jsonb,
  'Abaixo deste valor o acerto fica pendente (acumula ou paga-se a mao).', 'stripe_connect'),
 ('stripe_connect_start_week', '"2026-10-26"'::jsonb,
  'So acertos de semanas que comecam nesta data (segunda, Lisboa) ou depois podem ir por Stripe.', 'stripe_connect'),
 ('stripe_connect_cooldown_hours', '36'::jsonb,
  'Horas depois do fim da semana antes de poder enviar (margem para reembolsos).', 'stripe_connect'),
 ('stripe_connect_fee_mode', '"none"'::jsonb,
  'none = a Bora absorve a taxa; payout_only = desconta a taxa de payout ao parceiro.', 'stripe_connect'),
 ('stripe_connect_fee_overrides', '{}'::jsonb,
  'Excecoes por parceiro: {"<partner_id>":"none"|"payout_only"}.', 'stripe_connect')
ON CONFLICT (key) DO NOTHING;
```

(`stripe_connect_start_week = 2026-10-26`: é a segunda da semana que fecha a 02/11 às 00:05; assim o primeiro acerto elegível é o desta semana e
nenhuma semana antiga pode ir por Stripe.)

### 4.3 Verificação de elegibilidade — uma só, usada pelo preview e pelo envio

```sql
CREATE OR REPLACE FUNCTION public._connect_partner_transfer_check(p_settlement_id uuid, p_mode text)
RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public
AS $fn$
DECLARE
  s record; r record;
  v_on boolean; v_min int; v_start date; v_cool numeric; v_fee_mode text;
  v_gross int; v_fee int := 0; v_amount int;
BEGIN
  SELECT * INTO s FROM public.partner_weekly_settlements WHERE id = p_settlement_id;
  IF NOT FOUND THEN RETURN jsonb_build_object('ok', false, 'reason', 'acerto_nao_existe'); END IF;

  IF p_mode = 'live' THEN
    SELECT COALESCE((value #>> '{}')::boolean, false) INTO v_on
      FROM public.platform_settings WHERE key = 'stripe_connect_transfers_enabled';
    IF NOT COALESCE(v_on, false) THEN
      RETURN jsonb_build_object('ok', false, 'reason', 'interruptor_desligado');
    END IF;
  END IF;

  IF s.status NOT IN ('pending','closed') THEN
    RETURN jsonb_build_object('ok', false, 'reason', 'estado_' || s.status);
  END IF;
  IF s.direction <> 'bora_pays_partner' OR s.net_balance <= 0 THEN
    RETURN jsonb_build_object('ok', false, 'reason', 'direcao_nao_e_bora_paga');
  END IF;

  SELECT (value #>> '{}')::date INTO v_start
    FROM public.platform_settings WHERE key = 'stripe_connect_start_week';
  v_start := COALESCE(v_start, DATE '2026-10-26');
  IF (s.week_start_at AT TIME ZONE 'Europe/Lisbon')::date < v_start THEN
    RETURN jsonb_build_object('ok', false, 'reason', 'semana_anterior_ao_arranque');
  END IF;

  SELECT (value #>> '{}')::numeric INTO v_cool
    FROM public.platform_settings WHERE key = 'stripe_connect_cooldown_hours';
  v_cool := COALESCE(v_cool, 36);
  IF s.week_end_at > now() - make_interval(hours => v_cool::int) THEN
    RETURN jsonb_build_object('ok', false, 'reason', 'periodo_de_espera');
  END IF;

  SELECT id, stripe_account_id, stripe_account_status, stripe_payouts_enabled
    INTO r FROM public.restaurants WHERE id = s.partner_id;
  IF p_mode = 'live' THEN
    IF r.stripe_account_id IS NULL THEN
      RETURN jsonb_build_object('ok', false, 'reason', 'parceiro_sem_conta_connect');
    END IF;
    IF r.stripe_account_status <> 'enabled' OR NOT r.stripe_payouts_enabled THEN
      RETURN jsonb_build_object('ok', false, 'reason', 'conta_nao_pronta');
    END IF;
  END IF;

  v_gross := ROUND(s.net_balance * 100)::int;
  v_fee_mode := COALESCE(
    (SELECT value ->> s.partner_id FROM public.platform_settings WHERE key = 'stripe_connect_fee_overrides'),
    (SELECT value #>> '{}'          FROM public.platform_settings WHERE key = 'stripe_connect_fee_mode'),
    'none');
  IF v_fee_mode = 'payout_only' THEN
    v_fee := public.stripe_connect_fee_cents(v_gross, 'payout');
  ELSIF v_fee_mode <> 'none' THEN
    RETURN jsonb_build_object('ok', false, 'reason', 'modo_de_taxa_invalido');
  END IF;
  v_amount := v_gross - v_fee;

  v_min := COALESCE((SELECT (value #>> '{}')::int FROM public.platform_settings
                      WHERE key = 'stripe_connect_min_transfer_cents'), 500);
  IF v_amount < v_min THEN
    RETURN jsonb_build_object('ok', false, 'reason', 'abaixo_do_minimo', 'amount_cents', v_amount);
  END IF;

  IF p_mode = 'live' AND EXISTS (
       SELECT 1 FROM public.stripe_connect_transfers t
        WHERE t.settlement_id = s.id AND t.mode = 'live'
          AND t.status IN ('creating','succeeded','needs_review')) THEN
    RETURN jsonb_build_object('ok', false, 'reason', 'transferencia_ja_existe');
  END IF;

  RETURN jsonb_build_object(
    'ok', true, 'reason', 'ok',
    'settlement_id', s.id, 'partner_id', s.partner_id,
    'gross_cents', v_gross, 'fee_cents', v_fee, 'amount_cents', v_amount,
    'account_id', r.stripe_account_id,
    'week_start', (s.week_start_at AT TIME ZONE 'Europe/Lisbon')::date,
    'week_end', s.week_end_at);
END;
$fn$;
```

### 4.4 Preparar, confirmar, falhar (só `service_role`)

```sql
CREATE OR REPLACE FUNCTION public.connect_partner_transfer_prepare(
  p_settlement_id uuid, p_mode text, p_requested_by text)
RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public
AS $fn$
DECLARE
  s record; t record; c jsonb; v_attempt int; v_id uuid; v_key text;
BEGIN
  IF p_mode NOT IN ('test','live') THEN RAISE EXCEPTION 'modo_invalido'; END IF;

  SELECT * INTO s FROM public.partner_weekly_settlements WHERE id = p_settlement_id FOR UPDATE; -- serializa por acerto
  IF NOT FOUND THEN RETURN jsonb_build_object('ok', false, 'reason', 'acerto_nao_existe'); END IF;

  -- Já há tentativa deste acerto? Retoma (mesma chave) em vez de criar outra.
  SELECT * INTO t FROM public.stripe_connect_transfers
   WHERE settlement_id = s.id AND mode = p_mode AND status IN ('creating','needs_review','succeeded')
   ORDER BY attempt DESC LIMIT 1;
  IF FOUND THEN
    IF t.status = 'succeeded' THEN
      RETURN jsonb_build_object('ok', true, 'already', 'succeeded', 'transfer_id', t.id,
                                'stripe_transfer_id', t.stripe_transfer_id);
    ELSIF t.status = 'creating' AND t.created_at > now() - interval '20 hours' THEN
      RETURN jsonb_build_object('ok', true, 'already', 'creating', 'transfer_id', t.id,
        'idempotency_key', t.idempotency_key, 'transfer_group', t.transfer_group,
        'account_id', t.stripe_account_id, 'gross_cents', t.gross_cents,
        'fee_cents', t.fee_cents, 'amount_cents', t.amount_cents, 'partner_id', t.partner_id,
        'week_start', (s.week_start_at AT TIME ZONE 'Europe/Lisbon')::date);
    ELSE
      UPDATE public.stripe_connect_transfers
         SET status = 'needs_review', updated_at = now(),
             error = COALESCE(error, 'tentativa antiga sem resposta (>20h): ver a Stripe antes de repetir')
       WHERE id = t.id AND status = 'creating';
      RETURN jsonb_build_object('ok', false, 'reason', 'precisa_de_revisao', 'transfer_id', t.id);
    END IF;
  END IF;

  c := public._connect_partner_transfer_check(s.id, p_mode);
  IF NOT COALESCE((c ->> 'ok')::boolean, false) THEN RETURN c; END IF;

  SELECT COALESCE(MAX(attempt), 0) + 1 INTO v_attempt
    FROM public.stripe_connect_transfers WHERE settlement_id = s.id AND mode = p_mode;
  v_key := format('bora-pws-%s-%s-a%s', s.id, p_mode, v_attempt);

  INSERT INTO public.stripe_connect_transfers
    (settlement_id, partner_id, mode, attempt, gross_cents, fee_cents, amount_cents,
     stripe_account_id, idempotency_key, transfer_group, requested_by)
  VALUES
    (s.id, s.partner_id, p_mode, v_attempt,
     (c ->> 'gross_cents')::int, (c ->> 'fee_cents')::int, (c ->> 'amount_cents')::int,
     COALESCE(c ->> 'account_id', 'acct_modo_teste'), v_key, 'pws_' || s.id, p_requested_by)
  RETURNING id INTO v_id;

  RETURN c || jsonb_build_object('transfer_id', v_id, 'idempotency_key', v_key,
                                 'transfer_group', 'pws_' || s.id, 'attempt', v_attempt);
END;
$fn$;

CREATE OR REPLACE FUNCTION public.connect_partner_transfer_confirm(
  p_transfer_id uuid, p_stripe_transfer_id text)
RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public
AS $fn$
DECLARE t record; s record; v_desc text;
BEGIN
  IF p_stripe_transfer_id IS NULL OR p_stripe_transfer_id !~ '^tr_' THEN
    RAISE EXCEPTION 'id_de_transferencia_invalido';
  END IF;
  SELECT * INTO t FROM public.stripe_connect_transfers WHERE id = p_transfer_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'transferencia_nao_existe'; END IF;
  IF t.status = 'succeeded' THEN
    RETURN jsonb_build_object('ok', true, 'already', true, 'stripe_transfer_id', t.stripe_transfer_id);
  END IF;
  IF t.status NOT IN ('creating','needs_review') THEN RAISE EXCEPTION 'estado_invalido: %', t.status; END IF;

  UPDATE public.stripe_connect_transfers
     SET status = 'succeeded', stripe_transfer_id = p_stripe_transfer_id,
         completed_at = now(), updated_at = now(), error = NULL
   WHERE id = t.id;

  IF t.mode = 'live' THEN
    SELECT * INTO s FROM public.partner_weekly_settlements WHERE id = t.settlement_id;
    v_desc := to_char(s.week_start_at AT TIME ZONE 'Europe/Lisbon', 'DD/MM') || '–' ||
              to_char(s.week_end_at   AT TIME ZONE 'Europe/Lisbon', 'DD/MM');

    -- Linhas do extrato do parceiro (idempotentes; o FOR UPDATE acima serializa).
    INSERT INTO public.partner_statement_lines
      (owner_type, owner_id, occurred_at, kind, reference, gross_cents, amount_cents, description, settlement_id)
    SELECT 'partner', s.partner_id, s.week_end_at, 'sale', NULL,
           ROUND(s.gross_sales * 100)::int, ROUND(s.gross_sales * 100)::int, 'Vendas da semana ' || v_desc, s.id
     WHERE NOT EXISTS (SELECT 1 FROM public.partner_statement_lines l WHERE l.settlement_id = s.id AND l.kind = 'sale');

    INSERT INTO public.partner_statement_lines
      (owner_type, owner_id, occurred_at, kind, reference, gross_cents, amount_cents, description, settlement_id)
    SELECT 'partner', s.partner_id, s.week_end_at, 'commission', NULL,
           0, -ROUND(s.commission_total * 100)::int, 'Comissão Bora da semana', s.id
     WHERE ROUND(s.commission_total * 100)::int <> 0
       AND NOT EXISTS (SELECT 1 FROM public.partner_statement_lines l WHERE l.settlement_id = s.id AND l.kind = 'commission');

    INSERT INTO public.partner_statement_lines
      (owner_type, owner_id, occurred_at, kind, reference, gross_cents, amount_cents, description, settlement_id)
    SELECT 'partner', s.partner_id, s.week_end_at, 'adjustment', NULL,
           0, -ROUND(s.cash_kept_by_partner * 100)::int, 'Dinheiro cobrado diretamente por si', s.id
     WHERE ROUND(s.cash_kept_by_partner * 100)::int <> 0
       AND NOT EXISTS (SELECT 1 FROM public.partner_statement_lines l WHERE l.settlement_id = s.id AND l.kind = 'adjustment');

    INSERT INTO public.partner_statement_lines
      (owner_type, owner_id, occurred_at, kind, reference, gross_cents, amount_cents, description, settlement_id)
    SELECT 'partner', s.partner_id, now(), 'stripe_fee', p_stripe_transfer_id,
           0, -t.fee_cents, 'Taxa de transferência', s.id
     WHERE t.fee_cents > 0
       AND NOT EXISTS (SELECT 1 FROM public.partner_statement_lines l WHERE l.settlement_id = s.id AND l.kind = 'stripe_fee');

    INSERT INTO public.partner_statement_lines
      (owner_type, owner_id, occurred_at, kind, reference, gross_cents, amount_cents, description, settlement_id)
    SELECT 'partner', s.partner_id, now(), 'payout', p_stripe_transfer_id,
           0, -t.amount_cents, 'Pagamento semanal (Stripe)', s.id
     WHERE NOT EXISTS (SELECT 1 FROM public.partner_statement_lines l WHERE l.settlement_id = s.id AND l.kind = 'payout');
  END IF;

  RETURN jsonb_build_object('ok', true, 'transfer_id', t.id, 'mode', t.mode,
                            'stripe_transfer_id', p_stripe_transfer_id);
END;
$fn$;

CREATE OR REPLACE FUNCTION public.connect_partner_transfer_fail(
  p_transfer_id uuid, p_error text, p_needs_review boolean DEFAULT false)
RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public
AS $fn$
BEGIN
  UPDATE public.stripe_connect_transfers
     SET status = CASE WHEN p_needs_review THEN 'needs_review' ELSE 'failed' END,
         error = left(COALESCE(p_error, 'erro'), 500), updated_at = now()
   WHERE id = p_transfer_id AND status = 'creating';
  RETURN jsonb_build_object('ok', FOUND);
END;
$fn$;
```

### 4.5 Para o painel admin (PT-BR): ver o que se pode pagar e o histórico

```sql
CREATE OR REPLACE FUNCTION public.admin_connect_transfer_preview(p_week date DEFAULT NULL)
RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public
AS $fn$
BEGIN
  IF NOT public.is_admin() THEN RAISE EXCEPTION 'admin_required'; END IF;
  RETURN COALESCE((
    SELECT jsonb_agg(jsonb_build_object(
             'settlement_id', s.id, 'partner_id', s.partner_id, 'name', r.name,
             'week_start', (s.week_start_at AT TIME ZONE 'Europe/Lisbon')::date,
             'net_cents', ROUND(s.net_balance * 100)::int,
             'status', s.status, 'direction', s.direction,
             'check', public._connect_partner_transfer_check(s.id, 'live'))
           ORDER BY s.week_start_at DESC, r.name)
      FROM public.partner_weekly_settlements s
      JOIN public.restaurants r ON r.id = s.partner_id
     WHERE (p_week IS NULL OR public._semana_bate(s.week_start_at, p_week))
       AND s.status IN ('pending','closed')), '[]'::jsonb);
END;
$fn$;

CREATE OR REPLACE FUNCTION public.admin_list_connect_transfers(p_limit int DEFAULT 50)
RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public
AS $fn$
BEGIN
  IF NOT public.is_admin() THEN RAISE EXCEPTION 'admin_required'; END IF;
  RETURN COALESCE((
    SELECT jsonb_agg(q.x ORDER BY q.created_at DESC) FROM (
      SELECT t.created_at,
             jsonb_build_object(
               'id', t.id, 'settlement_id', t.settlement_id, 'partner_id', t.partner_id, 'name', r.name,
               'mode', t.mode, 'attempt', t.attempt, 'status', t.status,
               'gross_cents', t.gross_cents, 'fee_cents', t.fee_cents, 'amount_cents', t.amount_cents,
               'stripe_transfer_id', t.stripe_transfer_id, 'error', t.error,
               'requested_by', t.requested_by, 'created_at', t.created_at, 'completed_at', t.completed_at) AS x
        FROM public.stripe_connect_transfers t
        LEFT JOIN public.restaurants r ON r.id = t.partner_id
       ORDER BY t.created_at DESC LIMIT LEAST(GREATEST(p_limit, 1), 200)) q), '[]'::jsonb);
END;
$fn$;
```

### 4.6 Permissões (fechadas a `anon`; só o serviço escreve)

```sql
REVOKE ALL ON FUNCTION public._connect_partner_transfer_check(uuid, text)               FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.connect_partner_transfer_prepare(uuid, text, text)        FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.connect_partner_transfer_confirm(uuid, text)              FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.connect_partner_transfer_fail(uuid, text, boolean)        FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public._connect_partner_transfer_check(uuid, text)            TO service_role;
GRANT EXECUTE ON FUNCTION public.connect_partner_transfer_prepare(uuid, text, text)     TO service_role;
GRANT EXECUTE ON FUNCTION public.connect_partner_transfer_confirm(uuid, text)           TO service_role;
GRANT EXECUTE ON FUNCTION public.connect_partner_transfer_fail(uuid, text, boolean)     TO service_role;

REVOKE ALL ON FUNCTION public.admin_connect_transfer_preview(date) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.admin_list_connect_transfers(int)    FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.admin_connect_transfer_preview(date) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.admin_list_connect_transfers(int)    TO authenticated, service_role;
```

## 5. Edge Function proposta — `supabase/functions/stripe-connect-transfer/index.ts` (NÃO deployada)

`verify_jwt = false` (autentica no código: JWT de admin **ou** cabeçalho `x-cron-key`). O slug **não** está na lista de funções
protegidas da Trava; ainda assim o deploy é dinheiro: só depois do "autorizo".
Secrets novos (só os nomes): `STRIPE_TEST_SECRET_KEY`, `CONNECT_TRANSFER_MODE` (valor `test` ou `live`; por defeito `test`),
`CONNECT_TEST_DESTINATION` (a conta de teste, id `acct_...`), `CONNECT_CRON_KEY` (só para a fase 2b e para os testes). Em `live` usa o
secret `STRIPE_SECRET_KEY` que já existe.

```ts
import Stripe from 'https://esm.sh/stripe@14.21.0?target=deno';
import { createClient, type SupabaseClient } from 'https://esm.sh/@supabase/supabase-js@2';

const env = (n: string) => Deno.env.get(n) ?? '';

const MODE: 'live' | 'test' = env('CONNECT_TRANSFER_MODE').toLowerCase() === 'live' ? 'live' : 'test';
const stripeCreds = MODE === 'live' ? env('STRIPE_SECRET_KEY') : env('STRIPE_TEST_SECRET_KEY');
// A chave tem de ser do mesmo modo (impede usar a de produção em teste e vice-versa).
const credsOk = new RegExp('^(sk|rk)_' + MODE + '_').test(stripeCreds);
const stripe = new Stripe(stripeCreds || 'ausente', {
  apiVersion: '2023-10-16',
  httpClient: Stripe.createFetchHttpClient(),
});

const svc = createClient(env('SUPABASE_URL'), env('SUPABASE_SERVICE_ROLE_KEY'));

const cors = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type, x-cron-key',
  'Access-Control-Allow-Methods': 'POST, OPTIONS',
};
const json = (b: unknown, status = 200) =>
  new Response(JSON.stringify(b), { status, headers: { ...cors, 'Content-Type': 'application/json' } });

function sameText(a: string, b: string): boolean {
  if (!a || !b || a.length !== b.length) return false;
  let d = 0;
  for (let i = 0; i < a.length; i++) d |= a.charCodeAt(i) ^ b.charCodeAt(i);
  return d === 0;
}

type Caller =
  | { kind: 'admin'; uid: string; email: string; client: SupabaseClient }
  | { kind: 'cron' };

async function authorize(req: Request): Promise<Caller | null> {
  if (sameText(req.headers.get('x-cron-key') ?? '', env('CONNECT_CRON_KEY'))) return { kind: 'cron' };
  const client = createClient(env('SUPABASE_URL'), env('SUPABASE_ANON_KEY'), {
    global: { headers: { Authorization: req.headers.get('Authorization') ?? '' } },
  });
  const { data } = await client.auth.getUser();
  if (!data?.user) return null;
  const { data: isAdmin } = await client.rpc('is_admin');
  if (isAdmin !== true) return null;
  return { kind: 'admin', uid: data.user.id, email: data.user.email ?? '', client };
}

async function audit(caller: Caller, action: string, partnerId: string | null, details: Record<string, unknown>) {
  await svc.from('admin_audit_log').insert({
    admin_id: caller.kind === 'admin' ? caller.uid : null,
    admin_email: caller.kind === 'admin' ? caller.email : 'cron',
    action: `stripe_connect_transfer_${action}`,
    entity_type: 'partner',
    entity_id_text: partnerId,
    details: { mode: MODE, ...details },
  });
}

async function failRow(id: string, reason: string, needsReview: boolean) {
  await svc.rpc('connect_partner_transfer_fail', { p_transfer_id: id, p_error: reason, p_needs_review: needsReview });
  return { ok: false, reason, needs_review: needsReview };
}

async function sendOne(settlementId: string, caller: Caller) {
  const who = caller.kind === 'admin' ? `admin:${caller.uid}` : 'cron';
  const { data: prep, error: pErr } = await svc.rpc('connect_partner_transfer_prepare', {
    p_settlement_id: settlementId, p_mode: MODE, p_requested_by: who,
  });
  if (pErr) return { ok: false, reason: 'prepare_error', detail: pErr.message };
  if (!prep?.ok) return { ok: false, reason: prep?.reason ?? 'nao_elegivel' };
  if (prep.already === 'succeeded') return { ok: true, already: true, stripe_transfer_id: prep.stripe_transfer_id };

  const destination: string = MODE === 'live' ? prep.account_id : env('CONNECT_TEST_DESTINATION');
  if (!destination) return await failRow(prep.transfer_id, 'sem_destino', true);

  try {
    // 1. A conta está mesmo pronta na Stripe? (o espelho no banco pode estar atrasado)
    const acct = await stripe.accounts.retrieve(destination);
    if (acct.capabilities?.transfers !== 'active' || !acct.payouts_enabled) {
      return await failRow(prep.transfer_id, 'conta_nao_pronta_na_stripe', false);
    }
    // 2. Uma tentativa anterior cortada a meio já criou a transferência? Adotar, nunca duplicar.
    const prior = await stripe.transfers.list({ transfer_group: prep.transfer_group, limit: 10 });
    const adopted = prior.data.find((t) => t.metadata?.transfer_row_id === prep.transfer_id && !t.reversed);
    // 3. Criar, com a chave de idempotência da linha.
    const transfer = adopted ?? await stripe.transfers.create({
      amount: prep.amount_cents,
      currency: 'eur',
      destination,
      transfer_group: prep.transfer_group,
      description: `Bora - acerto semanal ${prep.week_start}`,
      metadata: {
        settlement_id: settlementId, transfer_row_id: prep.transfer_id,
        partner_id: prep.partner_id, week_start: prep.week_start, bora_mode: MODE,
      },
    }, { idempotencyKey: prep.idempotency_key });

    // 4. Gravar. Se isto falhar, o dinheiro JÁ saiu: não repetir; alertar.
    const { error: cErr } = await svc.rpc('connect_partner_transfer_confirm', {
      p_transfer_id: prep.transfer_id, p_stripe_transfer_id: transfer.id,
    });
    if (cErr) {
      await audit(caller, 'confirm_falhou', prep.partner_id, { stripe_transfer_id: transfer.id, erro: cErr.message });
      return { ok: false, reason: 'transferencia_criada_mas_nao_gravada', stripe_transfer_id: transfer.id };
    }

    // 5. Marcar o acerto pago PELO CAMINHO OFICIAL (só live e só com admin: a função oficial exige is_admin()).
    let markedPaid = false;
    if (MODE === 'live' && caller.kind === 'admin') {
      const { error: mErr } = await caller.client.rpc('admin_set_settlement_state', {
        p_subject_type: 'partner', p_subject_id: prep.partner_id, p_week_start: prep.week_start,
        p_status: 'paid', p_payment_reference: `stripe:${transfer.id}`,
      });
      markedPaid = !mErr;
      if (mErr) await audit(caller, 'marcar_pago_falhou', prep.partner_id, { stripe_transfer_id: transfer.id, erro: mErr.message });
    }
    await audit(caller, 'enviada', prep.partner_id, {
      settlement_id: settlementId, stripe_transfer_id: transfer.id,
      gross_cents: prep.gross_cents, fee_cents: prep.fee_cents, amount_cents: prep.amount_cents, marked_paid: markedPaid,
    });
    return { ok: true, mode: MODE, stripe_transfer_id: transfer.id, amount_cents: prep.amount_cents,
             fee_cents: prep.fee_cents, marked_paid: markedPaid };
  } catch (e) {
    const err = e as { type?: string; code?: string; message?: string };
    if (err.type === 'StripeConnectionError' || err.type === 'StripeAPIError' || err.type === 'StripeRateLimitError') {
      // Fica 'creating': repetir com a MESMA chave é seguro.
      return { ok: false, reason: 'stripe_indisponivel_repetir', retry: true };
    }
    if (err.code === 'balance_insufficient') {
      return await failRow(prep.transfer_id, 'saldo_insuficiente_na_plataforma', false);
    }
    return await failRow(prep.transfer_id, `${err.code ?? err.type ?? 'erro'}: ${err.message ?? ''}`, true);
  }
}

Deno.serve(async (req: Request) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: cors });
  if (!credsOk) return json({ ok: false, reason: 'chave_stripe_invalida_para_o_modo', mode: MODE }, 500);

  const caller = await authorize(req);
  if (!caller) return json({ ok: false, reason: 'nao_autorizado' }, 401);

  const body = await req.json().catch(() => ({}));
  const action = String(body.action ?? '');

  if (action === 'send') {
    const id = String(body.settlement_id ?? '');
    if (!/^[0-9a-f-]{36}$/i.test(id)) return json({ ok: false, reason: 'settlement_id_invalido' }, 400);
    const r = await sendOne(id, caller);
    return json(r, r.ok ? 200 : 409);
  }

  if (action === 'send_all') {
    if (caller.kind === 'cron') {
      const { data: on } = await svc.from('platform_settings').select('value')
        .eq('key', 'stripe_connect_auto_transfer_enabled').maybeSingle();
      if ((on?.value as unknown) !== true) return json({ ok: true, skipped: 'automatico_desligado' });
    }
    const { data: rows } = await svc.from('partner_weekly_settlements').select('id')
      .in('status', ['pending', 'closed']).eq('direction', 'bora_pays_partner')
      .order('week_start_at', { ascending: true }).limit(100);
    const results: unknown[] = [];
    for (const row of rows ?? []) {
      const r = await sendOne(row.id as string, caller);
      results.push({ settlement_id: row.id, ...r });
      if ((r as { reason?: string }).reason === 'saldo_insuficiente_na_plataforma') break; // erro de sistema: não insistir
    }
    return json({ ok: true, mode: MODE, processed: results.length, results });
  }

  if (action === 'test_ping') { // só em modo teste: valor pequeno para a conta de teste, sem tocar no banco
    const dest = env('CONNECT_TEST_DESTINATION');
    if (MODE !== 'test' || !dest) return json({ ok: false, reason: 'so_em_modo_teste_com_destino' }, 400);
    const pingKey = String(body.ping_key ?? `ping-${new Date().toISOString().slice(0, 10)}`).slice(0, 80);
    try {
      const tr = await stripe.transfers.create(
        { amount: Math.max(50, Math.min(Number(body.amount_cents ?? 100), 5000)), currency: 'eur',
          destination: dest, description: 'Bora - ping de teste' },
        { idempotencyKey: `bora-ping-${pingKey}` });
      return json({ ok: true, mode: MODE, stripe_transfer_id: tr.id, amount_cents: tr.amount });
    } catch (e) {
      const err = e as { code?: string; message?: string };
      return json({ ok: false, reason: err.code ?? 'erro', detail: err.message }, 409);
    }
  }

  return json({ ok: false, reason: 'action_invalida (send|send_all|test_ping)' }, 400);
});
```

Notas sobre o código:
- `send` e `send_all` em modo `test` fazem tudo exceto marcar o acerto e escrever extrato (o `confirm` só escreve extrato em `live`; o passo 5 só corre em `live`).
- `caller.kind === 'cron'` em `live` **não marca o acerto pago** (não há admin): a transferência fica registada e o acerto continua `pending` até alguém o marcar pelo ecrã (a referência `stripe:tr_...` fica na linha da transferência). É por isso que a fase 2b precisa da decisão D5.
- `balance_insufficient` é o código de erro da Stripe para saldo insuficiente em transferências; a chave de idempotência dessa tentativa fica "queimada" (a Stripe repete o mesmo erro durante 24 h), e por isso a tentativa seguinte nasce com `-a2`.
- Se `test_ping` for chamado em `live`, devolve 400 (não envia nada).

## 6. Interface do painel admin (PT-BR) — paridade obrigatória (não escrita; `lib/` não foi tocado)

Ficheiro a alterar: `lib/screens/admin/admin_acertos_semana_screen.dart` (junto de `_marcar`, `:208-220`; botão "Pagar" em `:974`).
Para cada acerto de **parceiro** a favor do parceiro, ler `admin_connect_transfer_preview(<segunda>)` e:
- `check.ok = true` → botão **"Pagar via Stripe"** ao lado de "Pagar" (que continua a existir: é a saída manual);
- `check.ok = false` → texto cinzento com o motivo traduzido:

| `reason` | Texto no painel |
|---|---|
| `interruptor_desligado` | Repasse Stripe desligado nas configurações |
| `parceiro_sem_conta_connect` | Parceiro sem conta Stripe — pagar à mão |
| `conta_nao_pronta` | Conta Stripe do parceiro incompleta — ver "Pagamentos Connect" |
| `periodo_de_espera` | Aguardando o período de espera (36 h após o fecho) |
| `abaixo_do_minimo` | Valor abaixo do mínimo — acumula ou pagar à mão |
| `transferencia_ja_existe` | Transferência já enviada — não repetir |
| `semana_anterior_ao_arranque` | Semana antiga — pagar à mão |
| `direcao_nao_e_bora_paga` | O parceiro é que deve à Bora — acerto manual |

Chamada (esboço; reutiliza `confirmarDinheiro`, `_eur`, `_aviso` que já existem nesse ecrã):

```dart
Future<void> _pagarPelaStripe(Map<String, dynamic> r) async {
  final ok = await confirmarDinheiro(context,
      titulo: 'Pagar via Stripe', nome: '${r['name'] ?? '—'}',
      valor: _eur((r['amount_cents'] as num?) ?? 0),
      detalhe: 'A Stripe envia este valor para a conta do parceiro. Não se desfaz.');
  if (!ok || !mounted) return;
  setState(() => _busy = true);
  try {
    final res = await Supabase.instance.client.functions.invoke('stripe-connect-transfer',
        body: {'action': 'send', 'settlement_id': r['settlement_id']});
    final d = res.data is Map ? Map<String, dynamic>.from(res.data) : <String, dynamic>{};
    if (d['ok'] != true) throw Exception(d['reason'] ?? 'falhou');
    _aviso('${r['name']}: transferência enviada (${d['stripe_transfer_id']}).');
    await _load();
  } catch (e) {
    _aviso('Erro: $e', erro: true);
  } finally {
    if (mounted) setState(() => _busy = false);
  }
}
```

Também em `lib/screens/admin/admin_connect_payments_screen.dart`: um separador "Transferências" que lista `admin_list_connect_transfers` (estado, valor,
`tr_...`, erro, quem pediu); as 7 chaves novas da categoria `stripe_connect` aparecem sozinhas no ecrã de configurações (`:306-345`).
App do parceiro (PT-PT): **sem alterações** — o extrato já mostra "Pago pela Stripe ✅ a DD/MM" quando existe linha `payout` (`connect_statement_screen.dart:271`).

## 7. Fase 2b — agendamento de terça (só depois de 3 semanas limpas)

Cron novo (não toca no fecho nem nos crons existentes). Terça 12:00 UTC ≈ 36 h depois do fim da semana (Lisboa = UTC no inverno):

```sql
SELECT cron.schedule('stripe-connect-transfer-weekly', '0 12 * * 2', $job$
  SELECT net.http_post(
    url     := (SELECT decrypted_secret FROM vault.decrypted_secrets WHERE name = 'project_url')
               || '/functions/v1/stripe-connect-transfer',
    headers := jsonb_build_object('Content-Type', 'application/json',
                 'x-cron-key', (SELECT decrypted_secret FROM vault.decrypted_secrets WHERE name = 'connect_cron_key')),
    body    := jsonb_build_object('action', 'send_all'));
$job$);
```

Pré-requisitos: segredo `connect_cron_key` no vault (hoje só existem `project_url` e `service_role_key`) com o **mesmo** valor do secret `CONNECT_CRON_KEY`;
`stripe_connect_auto_transfer_enabled = true`.

**Problema por resolver (D5):** sem admin, a função oficial de marcar pago falha com `admin_required`. Duas saídas:
- **(i) Recomendada para começar:** o agendamento envia, a linha de `stripe_connect_transfers` fica `succeeded`, o acerto fica `pending` e o painel mostra
  "Transferido (tr_...) — confirmar" com um clique que chama a função oficial (referência `stripe:tr_...`). Um clique por semana, o mesmo de hoje.
- **(ii) Totalmente automático:** uma função nova só-`service_role` que faz o `UPDATE` do estado do acerto depois de verificar que existe transferência `succeeded`
  de valor igual. É um **caminho de escrita novo** ao lado do oficial (duplica lógica, e é exatamente o "UPDATE direto" que as regras evitam) — só com autorização expressa.

## 8. Riscos

| # | Risco | Mitigação na proposta | Falta decidir/fazer |
|---|---|---|---|
| R1 | **Pagar duas vezes** (transferência Stripe não se "desfaz"; o ecrã deixa reabrir/desmarcar acertos pagos: `admin_reabrir_acerto`, `admin_unmark_settlement` sem limite de semana) | Índice único (uma viva por acerto), chave de idempotência, `list` por `transfer_group` antes de criar, `FOR UPDATE` no acerto | Canário com 1 acerto (secção 10, T5). Reversão só por `transfers.createReversal` + decisão humana |
| R2 | **Saldo da Stripe da plataforma insuficiente**: fundos de cartão/MB Way ficam "pendentes" alguns dias, e os payouts automáticos para o banco da Bora podem esvaziar o saldo disponível; `transfers.create` falha com `balance_insufficient` | Erro tratado (`failed`, chave nova na tentativa seguinte), `send_all` pára no primeiro; espera de 36 h | **Verificar no painel da Stripe** (Saldos → programação de payouts) se os payouts da plataforma são automáticos; se forem, passá-los a manuais ou semanais **depois** da terça, ou financiar a conta. Não consegui ler o saldo (sem sessão Stripe) |
| R3 | **Parceiro sem conta Connect** (27 de 29 restaurantes) ou com conta incompleta | `check` devolve `parceiro_sem_conta_connect`/`conta_nao_pronta`; o acerto fica pendente e paga-se à mão como hoje; a função reconfirma a conta na Stripe antes de enviar | Semana mista (uns por Stripe, outros à mão) é normal: o ecrã mostra o motivo por linha |
| R4 | **Acerto negativo** (`partner_pays_bora`, p. ex. −5,41 €) | Nunca gera transferência; fica como hoje | O Connect Express não debita o parceiro; manter cobrança manual ou ativar o transporte de dívida (`settlement_carry_over_enabled`, hoje `false`, é outra decisão) |
| R5 | **Taxas diferentes por parceiro** (Goola: nenhuma; Ouro e Prata: só a de transferência) contra um `stripe_fee_bearer` global | `stripe_connect_fee_mode='none'` por defeito + `stripe_connect_fee_overrides` por parceiro | D1 |
| R6 | **IVA / faturação** | A transferência não muda o valor do acerto nem emite documentos | Se a Bora passar a descontar taxas ao parceiro (modo `payout_only`), isso é um débito ao parceiro que entra na fatura/autofaturação da comissão. **Confirmar com a contabilista antes de usar `payout_only`**; a recomendação é manter `none` |
| R7 | **Reembolsos ou chargebacks depois da transferência** (a plataforma responde, aceite no onboarding de 06/08) | Espera de 36 h; semanas seguintes podem trazer acerto negativo | Decidir se há transporte de dívida (R4) |
| R8 | **Linha `needs_review`** (tentativa antiga sem resposta, ou erro não classificado) bloqueia o acerto | Nunca repete sozinha; erro fica gravado | Alguém confere na Stripe (Transferências, `transfer_group = pws_<id>`) e a Claude.ai resolve a linha com "vai" |
| R9 | **Ligar `stripe_connect_enabled` muda o rodapé do extrato de todos os parceiros** (`get_statement` devolve `connect_enabled` global: os 27 sem conta deixariam de ver "Pagamento ainda por transferência bancária.") | A proposta **não** liga essa chave: usa `stripe_connect_transfers_enabled` | Corrigir `get_statement` para devolver `connect_enabled` por dono (conta `enabled`) antes de alguma vez ligar `stripe_connect_enabled` |
| R10 | `BORA_STRIPE_MODE=test` global | Não é usado; modo próprio `CONNECT_TRANSFER_MODE` | — |
| R11 | Dois contabilistas (acerto semanal vs saldo do ledger) | Fase 2 segue o acerto semanal e **não escreve ledger** | D4; e não reativar o cron 2 (payouts antigos) |
| R12 | Fuso e fecho (Lisboa vs UTC, mudança de hora) | Datas do acerto sempre `AT TIME ZONE 'Europe/Lisbon'`; cron em UTC e com margem de 36 h | — |

## 9. Decisões para o Danilo (em português simples)

- **D1 — Quem paga a taxa da Stripe?** Recomendo: a Bora absorve por agora (`none`). Custa ~0,30 € por parceiro e semana. Quando houver muitos parceiros, rever com a contabilista.
- **D2 — Valor mínimo por transferência:** recomendo 5,00 €. Semanas abaixo disso ficam por pagar até acumular (ou pagas à mão).
- **D3 — Começar por botão ou automático?** Recomendo botão do admin nas primeiras 3 semanas.
- **D4 — Abater o saldo do ledger?** Recomendo **não** nesta fase (saldo antigo incoerente; missão própria).
- **D5 — Marcação automática do acerto sem admin?** Recomendo (i): um clique por semana, caminho oficial.
- **D6 — Espera de 36 h** antes de enviar. Aceitas?
- **D7 — Autorização para ligar com dinheiro real:** a frase, com a data, para o canário e depois para o agendamento (autorização é por missão, nunca "para sempre").

## 10. Ordem de aplicação e testes (passo a passo)

**Pré-voo (humanos, nada disto é por MCP):**
1. Danilo, no painel da Stripe em **Modo de teste**: copiar a chave secreta de teste e gravá-la no Supabase como secret `STRIPE_TEST_SECRET_KEY` (colar direto no painel do Supabase, nunca no chat).
2. No Modo de teste: Connect → Contas conectadas → criar uma conta **Express** (Portugal) e completar o cadastro com os dados de teste do guia (IBAN de teste `PT50000201231234567890154`, telefone `000 000 000`, código SMS `000-000`; `GUIA_DANILO_STRIPE_CONNECT.md:93-104`). Gravar o id `acct_...` dessa conta como secret `CONNECT_TEST_DESTINATION`.
3. Modo de teste: Pagamentos → criar um pagamento de 50 € com o cartão de teste `4000 0000 0000 0077` (entra direto no saldo **disponível**, sem esperar).
4. Secret `CONNECT_TRANSFER_MODE` com o valor `test`; secret `CONNECT_CRON_KEY` com um valor aleatório de 32 bytes gerado nesse momento (nunca escrito em ficheiro nem no chat).
5. Verificar na Stripe (modo live) a programação de payouts da plataforma (R2).
6. `03_roll_secret_webhook.md` feito (independente, mas convém fechar antes de ligar dinheiro).

**Ordem de aplicação (cada passo só com o "autorizo" do Danilo; aplica a Claude.ai por MCP):**
1. Migration das secções 4.1–4.6 (tudo desligado: `stripe_connect_transfers_enabled=false`). Provar por SELECT que as tabelas/funções/settings existem e que `anon` não executa nenhuma (`has_function_privilege`).
2. Deploy da Edge Function da secção 5 com `CONNECT_TRANSFER_MODE=test`.
3. Testes T1–T3 abaixo (todos em modo teste ou em transação desfeita).
4. Ecrã admin da secção 6 (agente `admin`/`flutter-ui`, com `flutter analyze` limpo e o Juiz) e teste T4.
5. Canário em modo `live` (T5).
6. Passadas 3 semanas limpas: fase 2b (secção 7).

**T1 — Só a Stripe em modo teste (nada no banco).** Com o cabeçalho `x-cron-key`, a Claude.ai chama `action: test_ping` (1,00 €):
1. Esperado: HTTP 200, `{"ok":true,"mode":"test","stripe_transfer_id":"tr_...","amount_cents":100}`; a transferência aparece no painel (Modo de teste) para a conta de teste.
2. Repetir com o mesmo `ping_key`: **o mesmo `tr_...`** (idempotência provada).
3. `amount_cents` acima do saldo disponível de teste: `409 balance_insufficient`.
4. Usar como destino uma conta de teste sem a capacidade `transfers` ativa: `409` com o motivo da Stripe (e, no `send`, `conta_nao_pronta_na_stripe`).
5. Arrancar com `CONNECT_TRANSFER_MODE=live` sem chave de produção válida: HTTP 500 `chave_stripe_invalida_para_o_modo`.

**T2 — SQL em transação desfeita (depois da migration; corre pela Claude.ai porque mexe em settings e em acertos de teste, e é desfeita no fim).**
O bloco cria um acerto fictício e liga o interruptor **dentro da transação**; termina com `RAISE EXCEPTION`, por isso nada fica gravado:

```sql
DO $t$
DECLARE s_id uuid; s2 uuid; p jsonb; out text := '';
BEGIN
  UPDATE public.platform_settings SET value = 'true'::jsonb  WHERE key = 'stripe_connect_transfers_enabled';
  UPDATE public.platform_settings SET value = '"2026-01-05"'::jsonb WHERE key = 'stripe_connect_start_week';

  INSERT INTO public.partner_weekly_settlements
    (partner_id, week_start_at, week_end_at, total_orders, gross_sales, commission_total, partner_share,
     cash_kept_by_partner, net_balance, direction, status)
  VALUES ('goola-acai-guarda', '2026-06-01 00:00+01', '2026-06-07 23:59:59+01', 3, 40, 10, 30, 0, 30, 'bora_pays_partner', 'pending')
  RETURNING id INTO s_id;

  p := public.connect_partner_transfer_prepare(s_id, 'live', 'teste');           out := out || 'S1 ' || p::text || E'\n';
  p := public.connect_partner_transfer_prepare(s_id, 'live', 'teste');           out := out || 'S2 ' || (p->>'already') || E'\n';  -- creating (mesma chave)
  p := public.connect_partner_transfer_confirm((SELECT id FROM public.stripe_connect_transfers WHERE settlement_id = s_id),
                                               'tr_TESTE_1');                    out := out || 'S3 ' || p::text || E'\n';
  out := out || 'S3 linhas extrato=' || (SELECT count(*) FROM public.partner_statement_lines WHERE settlement_id = s_id) || E'\n'; -- esperado 3 (sale, commission, payout)
  p := public.connect_partner_transfer_prepare(s_id, 'live', 'teste');           out := out || 'S4 ' || (p->>'already') || E'\n';  -- succeeded

  -- 2.º acerto (3,40 €): prova o interruptor e o mínimo. (O 1.º já tem tentativa 'succeeded',
  -- e a idempotência responde antes de olhar para o interruptor, por desenho.)
  INSERT INTO public.partner_weekly_settlements
    (partner_id, week_start_at, week_end_at, total_orders, gross_sales, commission_total, partner_share,
     cash_kept_by_partner, net_balance, direction, status)
  VALUES ('goola-acai-guarda', '2026-06-08 00:00+01', '2026-06-14 23:59:59+01', 1, 5, 1.6, 3.4, 0, 3.4, 'bora_pays_partner', 'pending')
  RETURNING id INTO s2;

  UPDATE public.platform_settings SET value = 'false'::jsonb WHERE key = 'stripe_connect_transfers_enabled';
  p := public.connect_partner_transfer_prepare(s2, 'live', 'teste');             out := out || 'S5 ' || (p->>'reason') || E'\n'; -- interruptor_desligado
  UPDATE public.platform_settings SET value = 'true'::jsonb  WHERE key = 'stripe_connect_transfers_enabled';
  p := public.connect_partner_transfer_prepare(s2, 'live', 'teste');             out := out || 'S6 ' || (p->>'reason') || E'\n'; -- abaixo_do_minimo

  RAISE EXCEPTION E'DESFEITO_OK\n%', out;
END
$t$;
```

Esperado: mensagem de erro `DESFEITO_OK` com S1 `ok:true, amount_cents:3000, fee_cents:0`, S2 `creating`, S3 `ok:true` e 3 linhas de extrato, S4 `succeeded`,
S5 `interruptor_desligado`, S6 `abaixo_do_minimo`. Depois: `SELECT count(*) FROM stripe_connect_transfers` = 0 e nenhum acerto com `week_start_at` de junho (prova de que desfez).
Casos extra, da mesma maneira: parceiro sem conta (`parceiro_sem_conta_connect`), acerto `partner_pays_bora` (`direcao_nao_e_bora_paga`), `fail` seguido de `prepare` (tentativa 2 com chave diferente),
modo `payout_only` com 3028 cêntimos (`fee_cents = 33`, `amount_cents = 2995`).

**T3 — A função inteira, modo teste, sobre um acerto REAL pendente.** O próximo fecho é **segunda 02/11 às 00:05** e cria o acerto da semana 26/10–01/11.
Depois do fecho e passadas as 36 h (ou com `stripe_connect_cooldown_hours` baixado só para este teste), com `CONNECT_TRANSFER_MODE` em `test`:
1. `action: send` com o `settlement_id` do acerto real → `{"ok":true,"mode":"test","stripe_transfer_id":"tr_...","marked_paid":false}`.
2. Prova por SELECT: a linha de `stripe_connect_transfers` tem `mode='test'`, `status='succeeded'`; o acerto **continua `pending`**; `partner_statement_lines` sem linhas novas; `admin_audit_log` com a ação `stripe_connect_transfer_enviada`.
3. Repetir `send`: `already:true` com o mesmo `tr_...`.

**T4 — Painel.** `flutter analyze` limpo; o botão aparece só com `check.ok`; os textos da tabela da secção 6; teste de widget com os 8 motivos.

**T5 — Canário em dinheiro real (só com "autorizo" datado do Danilo).**
1. Secret `CONNECT_TRANSFER_MODE` passa a `live`. Settings: `stripe_connect_transfers_enabled=true`, mínimo 500, arranque 2026-10-26, modo de taxa `none`.
2. O Danilo, no ecrã "Acertos da semana", escolhe **o acerto mais pequeno elegível** (nunca o maior) e carrega em "Pagar via Stripe".
3. Provas, uma a uma: resposta `ok:true` com `tr_...`; painel da Stripe (live) mostra a transferência do valor exato para a conta do parceiro; `stripe_connect_transfers` `live/succeeded`;
   acerto `paid` com `payment_reference = 'stripe:tr_...'`; 3 a 5 linhas novas no extrato do parceiro e a soma = `amount_cents`; comprovativo na fila (`_settlement_receipt_enqueue`);
   segundo clique devolve `transferencia_ja_existe`/`already`.
4. Dias depois, o evento `payout.paid` da conta do parceiro chega ao webhook do Connect e fica em `stripe_connect_events` (fecha o ciclo até ao banco do parceiro).
5. Só então ligar o botão para os restantes acertos.

## 11. Como reverter

| Situação | Como |
|---|---|
| Parar tudo já | `stripe_connect_transfers_enabled=false` (efeito imediato, sem deploy; as funções recusam com `interruptor_desligado`). Pelo painel "Pagamentos Connect". |
| Parar o agendamento | `SELECT cron.unschedule('stripe-connect-transfer-weekly');` e `stripe_connect_auto_transfer_enabled=false` |
| Voltar ao pagamento manual | Nada a fazer: "Pagar" (manual) nunca deixou de existir. Não reabrir acertos com transferência `succeeded` (o índice único impede o segundo envio, mas o pagamento manual por cima não é impedido pelo banco) |
| Transferência enviada por engano | Na Stripe (live): reverter a transferência (`transfers.createReversal`, possível porque a conta Express é gerida pela plataforma e tem saldo). Depois, pela Claude.ai com "vai": linha para `reversed`, e o acerto reaberto com `admin_reabrir_acerto` (motivo obrigatório; só semana em curso ou a última fechada) |
| Retirar a função | Apagar `stripe-connect-transfer` no painel do Supabase; as tabelas ficam (sem a função, só leitura) |
| Retirar o SQL | Ato humano (a Trava bloqueia `DROP` por agente). Ordem: funções `admin_*` novas, funções `connect_partner_transfer_*`, `_connect_partner_transfer_check`, a política e a tabela `stripe_connect_transfers`, e as 7 chaves de `platform_settings` da categoria `stripe_connect` acrescentadas |

⚠️ ISTO MEXE EM PAGAMENTO/DINHEIRO — à espera de autorizo. Está tudo pronto — confirma que eu aplico (ou que a Claude.ai aplica).
