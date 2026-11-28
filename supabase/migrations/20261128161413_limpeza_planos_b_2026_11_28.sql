-- ============================================================================
-- ⚠️ PROPOSTA — ISTO MEXE EM PAGAMENTO/DINHEIRO. NÃO APLICADA por esta sessão.
-- Missão limpeza-planos-fecho-2026-11-28, Bloco B (planos de limpeza só com cartão,
-- cobrança automática). Quem aplica é a Claude.ai, por MCP, com o autorizo do Danilo
-- (28/11/2026 09:25 "faz tudo, testa, publica e pronto", 10:28 "Sim, aplica tu",
-- 11:43 "eu tô autorizando e tem que fazer tudo").
--
-- Segue À LETRA a página do livro `limpeza-planos-b-especificacao-2026-11-28` (nomes de
-- tabelas, colunas, funções, parâmetros, campos devolvidos e palavras dos erros: a app
-- do patch `patch-limpeza-planos-app-2026-11-28` já depende deles).
--
-- Reaproveita o que já existe (nada se inventa):
--   • preço: cleaning_plan_quote + cleaning_plan_prices (20261128114406, já no ar);
--   • reserva: o mesmo desenho de cleaning_bookings da equipa (20261119200000: vaga 1 leva
--     o total; share_cents/cleaner_earnings_cents/bora_fee_cents por vaga);
--   • oferta: _cleaning_next_offer (igual à de 19/11, com UMA exceção: visita de plano ativo
--     com cartão guardado é oferecida antes de estar paga);
--   • Carteira Bora: wallet_credit_refund_split, o mesmo caminho do "Parar a série"
--     (20261109003440), chave por limpeza;
--   • avisos: _cleaning_notify_user, notify_admin_urgent_push; painel: _admin_op_guard +
--     admin_audit_log; robôs: pg_cron + net.http_post com a chave do cofre.
--
-- Idempotente: create … if not exists / create or replace / add column if not exists.
-- Sem DROP de nada que exista. Funções novas nascem fechadas a anon.
-- Reservas e séries que já existem NÃO mudam (só linhas com plan_id entram nas regras novas).
-- Ordem para aplicar: este ficheiro → provas.sql (begin … rollback) → Edge Functions.
-- ============================================================================

-- ── 1. Tabelas ──────────────────────────────────────────────────────────────

CREATE TABLE IF NOT EXISTS public.cleaning_plans (
  id                        uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  client_user_id            uuid NOT NULL REFERENCES auth.users(id),
  segment                   text NOT NULL CHECK (segment IN ('casa','empresa')),
  frequency                 text NOT NULL,
  days_of_week              integer[] NOT NULL,
  visit_time                time NOT NULL,
  start_date                date NOT NULL,
  end_date                  date,
  hours                     integer NOT NULL CHECK (hours BETWEEN 1 AND 10),
  team_size                 integer NOT NULL DEFAULT 1 CHECK (team_size BETWEEN 1 AND 3),
  products_by               text NOT NULL DEFAULT 'client' CHECK (products_by IN ('client','cleaner')),
  home_size                 text CHECK (home_size IN ('t0_t1','t2','t3','t4plus')),
  billing_mode              text NOT NULL DEFAULT 'per_visit' CHECK (billing_mode IN ('per_visit','monthly')),
  status                    text NOT NULL DEFAULT 'pending_card'
                              CHECK (status IN ('pending_card','active','paused','cancelled','completed')),
  -- preços CONGELADOS ao criar (cleaning_plan_quote)
  client_cents_per_hour     integer NOT NULL CHECK (client_cents_per_hour > 0),
  pro_cents_per_hour        integer NOT NULL CHECK (pro_cents_per_hour > 0),
  travel_fee_cents_per_pro  integer NOT NULL DEFAULT 0,
  travel_distance_km        numeric,
  products_cents            integer NOT NULL DEFAULT 0,
  total_per_visit_cents     integer NOT NULL CHECK (total_per_visit_cents >= 0),
  approx_month_cents        integer NOT NULL DEFAULT 0,
  -- morada
  address_street            text NOT NULL DEFAULT '',
  address_city              text NOT NULL DEFAULT '',
  address_postal            text NOT NULL DEFAULT '',
  lat                       double precision NOT NULL,
  lng                       double precision NOT NULL,
  notes                     text NOT NULL DEFAULT '',
  requested_cleaner_id      uuid REFERENCES public.cleaners(id),
  -- cartão (conta Stripe da EMPRESA)
  stripe_account            text NOT NULL DEFAULT 'empresa' CHECK (stripe_account IN ('pessoal','empresa')),
  stripe_customer_id        text,
  stripe_payment_method_id  text,
  card_brand                text,
  card_last4                text,
  card_exp_month            integer,
  card_exp_year             integer,
  card_saved_at             timestamptz,
  skipped_dates             date[] NOT NULL DEFAULT '{}',
  -- Bora Empresas
  company_name              text,
  billing_nif               text,
  billing_email             text,
  space_type                text CHECK (space_type IN ('loja','farmacia','otica','escritorio','clinica','cafe','salao','outro')),
  area_m2                   integer CHECK (area_m2 IS NULL OR area_m2 > 0),
  tasks                     text[] NOT NULL DEFAULT '{}',
  access_instructions       text,
  idempotency_key           text,
  activated_at              timestamptz,
  paused_at                 timestamptz,
  cancelled_at              timestamptz,
  cancelled_by              text CHECK (cancelled_by IN ('client','admin')),
  cancel_reason             text,
  created_at                timestamptz NOT NULL DEFAULT now(),
  updated_at                timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT cleaning_plans_freq_ok CHECK (
    (segment = 'casa'    AND frequency IN ('biweekly','weekly','multi_weekly')) OR
    (segment = 'empresa' AND frequency IN ('once','weekly_1','weekly_2','weekly_3plus'))),
  CONSTRAINT cleaning_plans_empresa_ok CHECK (
    segment <> 'empresa' OR (company_name IS NOT NULL AND billing_nif ~ '^[0-9]{9}$' AND billing_email LIKE '%@%')),
  CONSTRAINT cleaning_plans_once_per_visit CHECK (frequency <> 'once' OR billing_mode = 'per_visit')
);
CREATE UNIQUE INDEX IF NOT EXISTS cleaning_plans_idem_uq
  ON public.cleaning_plans (client_user_id, idempotency_key) WHERE idempotency_key IS NOT NULL;
CREATE INDEX IF NOT EXISTS cleaning_plans_client_idx ON public.cleaning_plans (client_user_id, created_at DESC);
CREATE INDEX IF NOT EXISTS cleaning_plans_status_idx ON public.cleaning_plans (status);
COMMENT ON TABLE public.cleaning_plans IS
  'Planos de limpeza (casas e Bora Empresas), só com cartão (conta Stripe da empresa). Preços congelados ao criar. Escrita só pelas funções cleaning_plan_* / admin_cleaning_plan_* (28/11/2026).';

CREATE TABLE IF NOT EXISTS public.cleaning_plan_charges (
  id                        uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  plan_id                   uuid NOT NULL REFERENCES public.cleaning_plans(id),
  client_user_id            uuid NOT NULL,
  kind                      text NOT NULL CHECK (kind IN ('visit','month')),
  idempotency_key           text NOT NULL UNIQUE,   -- 'visit-<reserva>' | 'month-<plano>-<AAAA-MM>'
  period_month              date,
  amount_cents              integer NOT NULL CHECK (amount_cents >= 0),
  status                    text NOT NULL DEFAULT 'scheduled'
                              CHECK (status IN ('scheduled','waiting_cleaner','pending','processing','succeeded',
                                                'failed','requires_action','failed_final','cancelled')),
  charge_after              timestamptz NOT NULL,
  deadline_at               timestamptz,
  attempts                  integer NOT NULL DEFAULT 0,
  repeat_same_key           boolean NOT NULL DEFAULT false,  -- erro de rede: a próxima volta usa a mesma chave
  next_attempt_at           timestamptz,
  processing_started_at     timestamptz,
  stripe_payment_intent_id  text UNIQUE,
  receipt_url               text,
  card_last4                text,
  last_error                text,
  notice_sent_at            timestamptz,
  no_cleaner_alerted_at     timestamptz,
  failure_notified_at       timestamptz,
  action_notified_at        timestamptz,
  paid_at                   timestamptz,
  created_at                timestamptz NOT NULL DEFAULT now(),
  updated_at                timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS cleaning_plan_charges_plan_idx ON public.cleaning_plan_charges (plan_id, created_at DESC);
CREATE INDEX IF NOT EXISTS cleaning_plan_charges_status_idx ON public.cleaning_plan_charges (status, charge_after);
COMMENT ON TABLE public.cleaning_plan_charges IS
  'Cobranças dos planos de limpeza (uma limpeza ou o mês). Um succeeded nunca volta atrás. Chave da Stripe por tentativa: cleaning-plan-<idempotency_key>-a<tentativa>.';

CREATE TABLE IF NOT EXISTS public.cleaning_plan_charge_items (
  id            uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  charge_id     uuid NOT NULL REFERENCES public.cleaning_plan_charges(id),
  booking_id    uuid NOT NULL REFERENCES public.cleaning_bookings(id),
  amount_cents  integer NOT NULL CHECK (amount_cents >= 0),
  created_at    timestamptz NOT NULL DEFAULT now(),
  UNIQUE (charge_id, booking_id)
);
CREATE INDEX IF NOT EXISTS cleaning_plan_charge_items_booking_idx ON public.cleaning_plan_charge_items (booking_id);

CREATE TABLE IF NOT EXISTS public.cleaning_plan_refunds (
  id                uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  booking_id        uuid NOT NULL UNIQUE REFERENCES public.cleaning_bookings(id),
  charge_id         uuid REFERENCES public.cleaning_plan_charges(id),
  plan_id           uuid NOT NULL REFERENCES public.cleaning_plans(id),
  client_user_id    uuid NOT NULL,
  method            text NOT NULL CHECK (method IN ('card','wallet')),
  amount_cents      integer NOT NULL CHECK (amount_cents > 0),
  reason            text,
  status            text NOT NULL DEFAULT 'pending'
                      CHECK (status IN ('pending','processing','succeeded','failed','failed_final')),
  attempts          integer NOT NULL DEFAULT 0,
  next_attempt_at   timestamptz,
  stripe_refund_id  text,
  last_error        text,
  created_at        timestamptz NOT NULL DEFAULT now(),
  updated_at        timestamptz NOT NULL DEFAULT now(),
  done_at           timestamptz
);
CREATE INDEX IF NOT EXISTS cleaning_plan_refunds_status_idx ON public.cleaning_plan_refunds (status, next_attempt_at);

-- ── 2. Reservas: plan_id e plan_visit_date ──────────────────────────────────
ALTER TABLE public.cleaning_bookings
  ADD COLUMN IF NOT EXISTS plan_id uuid REFERENCES public.cleaning_plans(id),
  ADD COLUMN IF NOT EXISTS plan_visit_date date;
COMMENT ON COLUMN public.cleaning_bookings.plan_id IS 'Plano de limpeza (28/11/2026). NULL nas reservas de sempre.';
COMMENT ON COLUMN public.cleaning_bookings.plan_visit_date IS 'Dia de Lisboa desta visita do plano.';
-- uma visita viva por plano, dia e vaga
CREATE UNIQUE INDEX IF NOT EXISTS cleaning_bookings_plan_visit_uq
  ON public.cleaning_bookings (plan_id, plan_visit_date, team_slot)
  WHERE plan_id IS NOT NULL AND status NOT LIKE 'cancelled%';
CREATE INDEX IF NOT EXISTS cleaning_bookings_plan_idx
  ON public.cleaning_bookings (plan_id, scheduled_at) WHERE plan_id IS NOT NULL;

-- ── 3. Acesso: o cliente lê só o seu, o admin lê tudo, ninguém escreve direto ──
ALTER TABLE public.cleaning_plans             ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.cleaning_plan_charges      ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.cleaning_plan_charge_items ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.cleaning_plan_refunds      ENABLE ROW LEVEL SECURITY;

DO $p$ BEGIN
  CREATE POLICY cleaning_plans_ler ON public.cleaning_plans FOR SELECT TO authenticated
    USING (client_user_id = auth.uid() OR public.is_admin());
EXCEPTION WHEN duplicate_object THEN NULL; END $p$;
DO $p$ BEGIN
  CREATE POLICY cleaning_plan_charges_ler ON public.cleaning_plan_charges FOR SELECT TO authenticated
    USING (client_user_id = auth.uid() OR public.is_admin());
EXCEPTION WHEN duplicate_object THEN NULL; END $p$;
DO $p$ BEGIN
  CREATE POLICY cleaning_plan_charge_items_ler ON public.cleaning_plan_charge_items FOR SELECT TO authenticated
    USING (EXISTS (SELECT 1 FROM public.cleaning_plan_charges c
                    WHERE c.id = charge_id AND (c.client_user_id = auth.uid() OR public.is_admin())));
EXCEPTION WHEN duplicate_object THEN NULL; END $p$;
DO $p$ BEGIN
  CREATE POLICY cleaning_plan_refunds_ler ON public.cleaning_plan_refunds FOR SELECT TO authenticated
    USING (client_user_id = auth.uid() OR public.is_admin());
EXCEPTION WHEN duplicate_object THEN NULL; END $p$;

REVOKE ALL ON public.cleaning_plans, public.cleaning_plan_charges,
              public.cleaning_plan_charge_items, public.cleaning_plan_refunds FROM anon, authenticated;
-- Leitura só das colunas sem ids da Stripe (os ids ficam para as funções do servidor e do painel).
GRANT SELECT (id, client_user_id, segment, frequency, days_of_week, visit_time, start_date, end_date, hours,
              team_size, products_by, home_size, billing_mode, status, client_cents_per_hour, pro_cents_per_hour,
              travel_fee_cents_per_pro, travel_distance_km, products_cents, total_per_visit_cents,
              approx_month_cents, address_street, address_city, address_postal, lat, lng, notes,
              requested_cleaner_id, stripe_account, card_brand, card_last4, card_exp_month, card_exp_year,
              card_saved_at, skipped_dates, company_name, billing_nif, billing_email, space_type, area_m2, tasks,
              access_instructions, activated_at, paused_at, cancelled_at, cancelled_by, cancel_reason,
              created_at, updated_at)
  ON public.cleaning_plans TO authenticated;
GRANT SELECT (id, plan_id, client_user_id, kind, period_month, amount_cents, status, charge_after, deadline_at,
              attempts, next_attempt_at, receipt_url, card_last4, paid_at, created_at, updated_at)
  ON public.cleaning_plan_charges TO authenticated;
GRANT SELECT (id, charge_id, booking_id, amount_cents, created_at) ON public.cleaning_plan_charge_items TO authenticated;
GRANT SELECT (id, booking_id, charge_id, plan_id, client_user_id, method, amount_cents, reason, status, created_at,
              done_at)
  ON public.cleaning_plan_refunds TO authenticated;
GRANT ALL ON public.cleaning_plans, public.cleaning_plan_charges,
             public.cleaning_plan_charge_items, public.cleaning_plan_refunds TO service_role;

-- ── 4. Ajudantes ────────────────────────────────────────────────────────────
-- Definições (valor por defeito; NÃO se cria nada em platform_settings):
--   cleaning_plans_enabled (true) · cleaning_plan_min_lead_hours (36) ·
--   cleaning_plan_horizon_days (14) · cleaning_plan_charge_hours_before (24)

CREATE OR REPLACE FUNCTION public._cleaning_plan_dias_ok(p_frequency text, p_days integer[])
RETURNS boolean LANGUAGE sql IMMUTABLE SET search_path TO 'public' AS $$
  SELECT p_days IS NOT NULL
     AND cardinality(p_days) = (SELECT count(DISTINCT d) FROM unnest(p_days) d)
     AND NOT EXISTS (SELECT 1 FROM unnest(p_days) d WHERE d IS NULL OR d < 1 OR d > 7)
     AND CASE p_frequency
           WHEN 'weekly_2'     THEN cardinality(p_days) = 2
           WHEN 'multi_weekly' THEN cardinality(p_days) BETWEEN 2 AND 7
           WHEN 'weekly_3plus' THEN cardinality(p_days) BETWEEN 3 AND 7
           ELSE cardinality(p_days) = 1   -- once, biweekly, weekly, weekly_1
         END;
$$;

-- 'HH:MM' (ou HH:MM:SS) → time; entre 06:00 e 23:00.
CREATE OR REPLACE FUNCTION public._cleaning_plan_hora(p_time text)
RETURNS time LANGUAGE plpgsql IMMUTABLE SET search_path TO 'public' AS $$
DECLARE v time;
BEGIN
  IF p_time IS NULL OR btrim(p_time) !~ '^[0-9]{1,2}:[0-9]{2}(:[0-9]{2})?$' THEN
    RAISE EXCEPTION 'hora_invalida: %', COALESCE(p_time, 'NULL');
  END IF;
  BEGIN
    v := btrim(p_time)::time;
  EXCEPTION WHEN others THEN
    RAISE EXCEPTION 'hora_invalida: %', p_time;
  END;
  IF v < time '06:00' OR v > time '23:00' THEN
    RAISE EXCEPTION 'hora_entre_6_e_23: %', p_time;
  END IF;
  RETURN v;
END $$;

-- Visitas por mês (a mesma conta de cleaning_plan_quote).
CREATE OR REPLACE FUNCTION public._cleaning_plan_visitas_mes(p_frequency text, p_days integer)
RETURNS numeric LANGUAGE sql IMMUTABLE SET search_path TO 'public' AS $$
  SELECT CASE WHEN p_frequency = 'once' THEN 1
              ELSE round((CASE p_frequency
                            WHEN 'biweekly' THEN 0.5
                            WHEN 'weekly' THEN 1 WHEN 'weekly_1' THEN 1
                            WHEN 'weekly_2' THEN 2
                            WHEN 'multi_weekly' THEN GREATEST(2, LEAST(COALESCE(p_days, 2), 7))
                            WHEN 'weekly_3plus' THEN GREATEST(3, LEAST(COALESCE(p_days, 3), 7))
                            ELSE 1 END) * 52.0 / 12.0, 2) END;
$$;

-- O dinheiro de UMA vaga de uma visita do plano, com os preços congelados.
-- cliente = preço/h × horas + deslocação (+ produtos na vaga 1)
-- profissional = ganho/h × horas + deslocação (+ produtos na vaga 1); Bora = a diferença por hora.
CREATE OR REPLACE FUNCTION public._cleaning_plan_vaga(p_plan public.cleaning_plans, p_slot integer)
RETURNS jsonb LANGUAGE sql STABLE SET search_path TO 'public' AS $$
  SELECT jsonb_build_object(
    'client_cents', p_plan.client_cents_per_hour * p_plan.hours + p_plan.travel_fee_cents_per_pro
                    + CASE WHEN p_slot = 1 THEN p_plan.products_cents ELSE 0 END,
    'pro_cents',    p_plan.pro_cents_per_hour * p_plan.hours + p_plan.travel_fee_cents_per_pro
                    + CASE WHEN p_slot = 1 THEN p_plan.products_cents ELSE 0 END,
    'bora_cents',   (p_plan.client_cents_per_hour - p_plan.pro_cents_per_hour) * p_plan.hours,
    'products_cents', CASE WHEN p_slot = 1 THEN p_plan.products_cents ELSE 0 END,
    'labor_cents',  p_plan.client_cents_per_hour * p_plan.hours);
$$;

-- Todas as vagas vivas da visita têm profissional aceite?
CREATE OR REPLACE FUNCTION public._cleaning_plan_visita_confirmada(p_booking_id uuid)
RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path TO 'public' AS $$
  WITH v AS (SELECT * FROM cleaning_bookings WHERE id = p_booking_id)
  SELECT EXISTS (SELECT 1 FROM v WHERE v.status IN ('accepted','on_the_way','in_progress','done','completed')
                                   AND v.cleaner_id IS NOT NULL)
     AND NOT EXISTS (
       SELECT 1 FROM cleaning_bookings t, v
        WHERE v.team_group_id IS NOT NULL AND t.team_group_id = v.team_group_id
          AND (t.status NOT IN ('accepted','on_the_way','in_progress','done','completed') OR t.cleaner_id IS NULL));
$$;

-- Quanto já se cobrou (com sucesso) por esta visita (vaga 1) e em que cobrança.
CREATE OR REPLACE FUNCTION public._cleaning_plan_pago(p_booking_id uuid)
RETURNS TABLE (charge_id uuid, amount_cents integer) LANGUAGE sql STABLE SECURITY DEFINER SET search_path TO 'public' AS $$
  SELECT i.charge_id, i.amount_cents
    FROM cleaning_plan_charge_items i JOIN cleaning_plan_charges c ON c.id = i.charge_id
   WHERE i.booking_id = p_booking_id AND c.status = 'succeeded'
   ORDER BY c.paid_at DESC NULLS LAST LIMIT 1;
$$;

CREATE OR REPLACE FUNCTION public._cleaning_plan_euro(p_cents integer)
RETURNS text LANGUAGE sql IMMUTABLE AS $$ SELECT replace(to_char(COALESCE(p_cents, 0) / 100.0, 'FM999990D00'), '.', ',') || ' €' $$;

CREATE OR REPLACE FUNCTION public._cleaning_plan_quando(p_at timestamptz)
RETURNS text LANGUAGE sql STABLE AS $$ SELECT to_char(p_at AT TIME ZONE 'Europe/Lisbon', 'DD/MM "às" HH24:MI') $$;

-- O plano como a app o lê (cleaning_plan_mine). Sem ids da Stripe.
CREATE OR REPLACE FUNCTION public._cleaning_plan_json(p_plan_id uuid)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path TO 'public' AS $$
DECLARE
  p cleaning_plans;
  v_mes_ini timestamptz := (date_trunc('month', now() AT TIME ZONE 'Europe/Lisbon')) AT TIME ZONE 'Europe/Lisbon';
BEGIN
  SELECT * INTO p FROM cleaning_plans WHERE id = p_plan_id;
  IF p.id IS NULL THEN RETURN NULL; END IF;
  RETURN jsonb_build_object(
    'id', p.id, 'segment', p.segment, 'frequency', p.frequency,
    'label', COALESCE((SELECT label_pt FROM cleaning_plan_prices pr WHERE pr.segment = p.segment AND pr.frequency = p.frequency), p.frequency),
    'status', p.status, 'days_of_week', to_jsonb(p.days_of_week), 'visit_time', p.visit_time::text,
    'start_date', p.start_date, 'hours', p.hours, 'team_size', p.team_size, 'products_by', p.products_by,
    'home_size', p.home_size, 'billing_mode', p.billing_mode,
    'client_cents_per_hour', p.client_cents_per_hour, 'total_per_visit_cents', p.total_per_visit_cents,
    'approx_month_cents', p.approx_month_cents,
    'month_paid_cents', COALESCE((SELECT sum(c.amount_cents) FROM cleaning_plan_charges c
                                   WHERE c.plan_id = p.id AND c.status = 'succeeded' AND c.paid_at >= v_mes_ini), 0),
    'card_brand', p.card_brand, 'card_last4', p.card_last4,
    'cleaner', (SELECT jsonb_build_object('name', c.name, 'photo_url', c.photo_url, 'rating_avg', c.rating_avg)
                  FROM cleaners c WHERE c.id = p.requested_cleaner_id),
    'company_name', p.company_name, 'address_street', p.address_street,
    'needs_action', EXISTS (SELECT 1 FROM cleaning_plan_charges c
                             WHERE c.plan_id = p.id AND c.status IN ('requires_action','failed')),
    'next_visits', COALESCE((
      SELECT jsonb_agg(jsonb_build_object(
               'booking_id', b.id, 'scheduled_at', b.scheduled_at, 'date', b.plan_visit_date,
               'status', b.status, 'payment_status', b.payment_status, 'total_cents', b.total_cents,
               'confirmed', public._cleaning_plan_visita_confirmada(b.id),
               'cleaner_name', (SELECT c.name FROM cleaners c WHERE c.id = b.cleaner_id),
               'can_skip', b.scheduled_at > now() + interval '24 hours') ORDER BY b.scheduled_at)
        FROM (SELECT * FROM cleaning_bookings
               WHERE plan_id = p.id AND team_slot = 1 AND status NOT LIKE 'cancelled%'
                 AND scheduled_at > now() - interval '6 hours'
               ORDER BY scheduled_at LIMIT 8) b), '[]'::jsonb),
    'charges', COALESCE((
      SELECT jsonb_agg(jsonb_build_object(
               'id', c.id, 'kind', c.kind, 'amount_cents', c.amount_cents, 'status', c.status,
               'charge_after', c.charge_after, 'paid_at', c.paid_at, 'card_last4', c.card_last4,
               'receipt_url', c.receipt_url) ORDER BY c.created_at DESC)
        FROM (SELECT * FROM cleaning_plan_charges WHERE plan_id = p.id
               ORDER BY created_at DESC LIMIT 24) c), '[]'::jsonb));
END $$;

-- ── 5. Desmarcar uma visita do plano e devolver o dinheiro ──────────────────
-- Desmarca a visita (todas as vagas). p_by: 'client' (saltar, cancelar o plano) | 'admin'
-- (pausa/cancelamento no painel, mudança de horário/horas, pagamento falhado).
-- O dinheiro volta pelo gatilho _trg_cleaning_plan_visita_caiu (abaixo).
CREATE OR REPLACE FUNCTION public._cleaning_plan_cancel_visit(p_booking_id uuid, p_by text, p_reason text)
RETURNS boolean LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $$
DECLARE v_b cleaning_bookings; r record;
BEGIN
  SELECT * INTO v_b FROM cleaning_bookings WHERE id = p_booking_id FOR UPDATE;
  IF v_b.id IS NULL OR v_b.plan_id IS NULL OR v_b.status LIKE 'cancelled%'
     OR v_b.status IN ('in_progress','done','completed') THEN
    RETURN false;
  END IF;
  -- irmãs primeiro (a vaga 1 é a que faz a devolução)
  FOR r IN SELECT id, cleaner_id FROM cleaning_bookings
            WHERE v_b.team_group_id IS NOT NULL AND team_group_id = v_b.team_group_id
              AND team_slot > 1 AND status IN ('scheduled','accepted','on_the_way')
            FOR UPDATE
  LOOP
    UPDATE cleaning_bookings
       SET status = 'cancelled_client', cancelled_at = now(), cancelled_by = p_by, cancel_reason = p_reason,
           cancel_fee_cents = 0,
           payment_status = CASE WHEN payment_status = 'held' THEN 'estornado' ELSE payment_status END,
           offer_cleaner_id = NULL, offer_expires_at = NULL
     WHERE id = r.id;
    IF r.cleaner_id IS NOT NULL THEN
      PERFORM public._cleaning_notify_user((SELECT user_id FROM cleaners WHERE id = r.cleaner_id),
        'cleaning_cancelled', 'Limpeza desmarcada',
        'A limpeza de ' || public._cleaning_plan_quando(v_b.scheduled_at) || ' foi desmarcada.', r.id::text);
    END IF;
  END LOOP;
  UPDATE cleaning_bookings
     SET status = 'cancelled_client', cancelled_at = now(), cancelled_by = p_by, cancel_reason = p_reason,
         cancel_fee_cents = 0,
         payment_status = CASE WHEN payment_status = 'held' THEN 'estornado' ELSE payment_status END,
         offer_cleaner_id = NULL, offer_expires_at = NULL
   WHERE id = v_b.id;
  IF v_b.cleaner_id IS NOT NULL THEN
    PERFORM public._cleaning_notify_user((SELECT user_id FROM cleaners WHERE id = v_b.cleaner_id),
      'cleaning_cancelled', 'Limpeza desmarcada',
      'A limpeza de ' || public._cleaning_plan_quando(v_b.scheduled_at) || ' foi desmarcada.', v_b.id::text);
  END IF;
  RETURN true;
END $$;

-- Tira a visita das cobranças que ainda não passaram (o mês recalcula; a da visita cancela-se).
CREATE OR REPLACE FUNCTION public._cleaning_plan_soltar_da_cobranca(p_booking_id uuid)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $$
DECLARE r record; v_total integer;
BEGIN
  FOR r IN SELECT i.id AS item_id, c.id AS charge_id
             FROM cleaning_plan_charge_items i JOIN cleaning_plan_charges c ON c.id = i.charge_id
            WHERE i.booking_id = p_booking_id
              AND c.status IN ('scheduled','waiting_cleaner','pending','failed','requires_action')
            FOR UPDATE OF c
  LOOP
    DELETE FROM cleaning_plan_charge_items WHERE id = r.item_id;
    SELECT COALESCE(sum(amount_cents), 0) INTO v_total FROM cleaning_plan_charge_items WHERE charge_id = r.charge_id;
    UPDATE cleaning_plan_charges
       SET amount_cents = v_total,
           status = CASE WHEN v_total = 0 THEN 'cancelled' ELSE status END,
           updated_at = now()
     WHERE id = r.charge_id;
  END LOOP;
  -- 'processing': deixa-se; se a cobrança entrar, _cleaning_plan_marcar_pago devolve esta visita ao cartão.
END $$;

-- Devolve o que se cobrou por uma visita (ou por uma vaga de equipa que ficou sem profissional).
-- p_method 'wallet' → Carteira Bora, na hora, pelo caminho do "Parar a série" (wallet_credit_refund_split,
-- chave 'limpeza_plano_<reserva>'); 'card' → fica 'pending' e o robô cleaning-plan-charge devolve na Stripe.
-- Nunca mais do que se cobrou nessa cobrança (cartão e carteira juntos). Uma devolução por reserva.
CREATE OR REPLACE FUNCTION public._cleaning_plan_devolver(p_booking_id uuid, p_method text, p_reason text,
                                                          p_menos_cents integer DEFAULT 0)
RETURNS integer LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $$
DECLARE
  v_b cleaning_bookings; v_slot1 uuid; v_pago record; v_ja integer; v_cap integer; v_valor integer; v_id uuid;
BEGIN
  SELECT * INTO v_b FROM cleaning_bookings WHERE id = p_booking_id;
  IF v_b.id IS NULL OR v_b.plan_id IS NULL THEN RETURN 0; END IF;
  v_slot1 := CASE WHEN v_b.team_slot = 1 THEN v_b.id
                  ELSE (SELECT id FROM cleaning_bookings WHERE team_group_id = v_b.team_group_id AND team_slot = 1) END;
  SELECT * INTO v_pago FROM public._cleaning_plan_pago(v_slot1);
  IF v_pago.charge_id IS NULL THEN RETURN 0; END IF;   -- nada cobrado: nada a devolver

  -- já devolvido por esta visita (todas as vagas) e por esta cobrança
  SELECT COALESCE(sum(r.amount_cents), 0) INTO v_ja FROM cleaning_plan_refunds r
   WHERE r.status NOT IN ('failed_final')
     AND (r.booking_id = v_slot1 OR r.booking_id IN (SELECT id FROM cleaning_bookings
                                                      WHERE v_b.team_group_id IS NOT NULL AND team_group_id = v_b.team_group_id));
  SELECT (SELECT amount_cents FROM cleaning_plan_charges WHERE id = v_pago.charge_id)
         - COALESCE((SELECT sum(amount_cents) FROM cleaning_plan_refunds
                      WHERE charge_id = v_pago.charge_id AND status NOT IN ('failed_final')), 0)
    INTO v_cap;

  v_valor := CASE WHEN v_b.team_slot = 1 THEN v_pago.amount_cents - v_ja ELSE COALESCE(v_b.share_cents, 0) END;
  v_valor := LEAST(v_valor - COALESCE(p_menos_cents, 0), v_cap);
  IF v_valor <= 0 THEN RETURN 0; END IF;

  INSERT INTO cleaning_plan_refunds (booking_id, charge_id, plan_id, client_user_id, method, amount_cents, reason,
                                     status, next_attempt_at)
  VALUES (p_booking_id, v_pago.charge_id, v_b.plan_id, v_b.client_user_id, p_method, v_valor, p_reason,
          CASE WHEN p_method = 'wallet' THEN 'processing' ELSE 'pending' END, now())
  ON CONFLICT (booking_id) DO NOTHING
  RETURNING id INTO v_id;
  IF v_id IS NULL THEN RETURN 0; END IF;   -- já havia devolução desta reserva

  IF p_method = 'wallet' THEN
    -- Se a carteira falhar, a exceção sobe e o cancelamento desfaz-se: nunca há visita
    -- desmarcada sem o dinheiro devolvido.
    PERFORM public.wallet_credit_refund_split(
      p_booking_id::text, v_b.client_user_id, v_valor,
      'Limpeza do plano desmarcada: devolvido à Carteira Bora',
      'limpeza_plano_' || p_booking_id::text);
    UPDATE cleaning_plan_refunds SET status = 'succeeded', done_at = now(), updated_at = now() WHERE id = v_id;
    PERFORM public._cleaning_notify_user(v_b.client_user_id, 'cleaning_plan_refund', 'Dinheiro na carteira',
      'Devolvemos ' || public._cleaning_plan_euro(v_valor) || ' à tua Carteira Bora (limpeza de '
      || public._cleaning_plan_quando(v_b.scheduled_at) || ').', v_slot1::text);
  END IF;
  RETURN v_valor;
END $$;

-- Gatilho: uma visita de plano caiu → solta das cobranças por fazer e devolve o que já se cobrou.
-- Cliente desmarcou (saltar, cancelar o plano, cancelar só essa) → Carteira Bora, menos a taxa se a houver.
-- Falha da Bora (sem profissional, admin pausou/cancelou, mudança de horário/horas) → cartão.
CREATE OR REPLACE FUNCTION public._trg_cleaning_plan_visita_caiu()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $$
DECLARE v_slot1_caiu boolean;
BEGIN
  IF NEW.team_slot = 1 THEN
    PERFORM public._cleaning_plan_soltar_da_cobranca(NEW.id);
    IF NEW.cancelled_by = 'client' THEN
      PERFORM public._cleaning_plan_devolver(NEW.id, 'wallet', 'cliente desmarcou: ' || COALESCE(NEW.cancel_reason, ''),
                                             COALESCE(NEW.cancel_fee_cents, 0));
    ELSE
      PERFORM public._cleaning_plan_devolver(NEW.id, 'card', COALESCE(NEW.cancel_reason, NEW.status), 0);
    END IF;
  ELSIF NEW.status = 'cancelled_no_cleaner' THEN
    -- equipa: uma vaga ficou sem ninguém e a principal continua → devolve a parte dessa vaga ao cartão
    SELECT status LIKE 'cancelled%' INTO v_slot1_caiu FROM cleaning_bookings
     WHERE team_group_id = NEW.team_group_id AND team_slot = 1;
    IF NOT COALESCE(v_slot1_caiu, true) THEN
      PERFORM public._cleaning_plan_devolver(NEW.id, 'card', 'vaga sem profissional', 0);
    END IF;
  END IF;
  RETURN NULL;
END $$;

DROP TRIGGER IF EXISTS trg_cleaning_plan_visita_caiu ON public.cleaning_bookings;
CREATE TRIGGER trg_cleaning_plan_visita_caiu
  AFTER UPDATE OF status ON public.cleaning_bookings
  FOR EACH ROW
  WHEN (NEW.plan_id IS NOT NULL AND NEW.status LIKE 'cancelled%' AND OLD.status NOT LIKE 'cancelled%')
  EXECUTE FUNCTION public._trg_cleaning_plan_visita_caiu();

-- Gatilho: a primeira profissional que aceita uma visita do plano fica a profissional fixa.
CREATE OR REPLACE FUNCTION public._trg_cleaning_plan_profissional_fixa()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $$
BEGIN
  UPDATE cleaning_plans SET requested_cleaner_id = NEW.cleaner_id, updated_at = now()
   WHERE id = NEW.plan_id AND requested_cleaner_id IS NULL;
  RETURN NULL;
END $$;

DROP TRIGGER IF EXISTS trg_cleaning_plan_profissional_fixa ON public.cleaning_bookings;
CREATE TRIGGER trg_cleaning_plan_profissional_fixa
  AFTER UPDATE OF cleaner_id ON public.cleaning_bookings
  FOR EACH ROW
  WHEN (NEW.plan_id IS NOT NULL AND NEW.team_slot = 1 AND NEW.cleaner_id IS NOT NULL
        AND OLD.cleaner_id IS DISTINCT FROM NEW.cleaner_id)
  EXECUTE FUNCTION public._trg_cleaning_plan_profissional_fixa();

-- ── 6. Gerador de visitas ───────────────────────────────────────────────────
-- Até 14 dias à frente ("A cada limpeza") ou até ao fim do mês ("O mês de uma vez"; a partir do
-- dia 17, até ao fim do mês seguinte). Só a partir de 36 h. De 15 em 15 dias conta as semanas a
-- partir da semana do início. Dias saltados não se geram; visita desmarcada não volta a nascer
-- (só as desmarcadas por mudança de horário ou de horas se refazem).
CREATE OR REPLACE FUNCTION public._cleaning_plan_gerar_visitas(p_plan_id uuid)
RETURNS integer LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $$
DECLARE
  p cleaning_plans;
  v_lead int := public._cleaning_setting_int('cleaning_plan_min_lead_hours', 36);
  v_horizonte int := public._cleaning_setting_int('cleaning_plan_horizon_days', 14);
  v_hoje date := (now() AT TIME ZONE 'Europe/Lisbon')::date;
  v_fim date; d date; v_at timestamptz; v_team uuid; v_s int; v_vaga jsonb; v_total int;
  v_id uuid; v_ids uuid[]; v_n int := 0; v_notas text; v_tarefas text;
BEGIN
  SELECT * INTO p FROM cleaning_plans WHERE id = p_plan_id FOR UPDATE;
  IF p.id IS NULL OR p.status <> 'active' OR p.stripe_payment_method_id IS NULL THEN RETURN 0; END IF;

  IF p.billing_mode = 'monthly' THEN
    v_fim := (date_trunc('month', v_hoje)
              + CASE WHEN extract(day FROM v_hoje) >= 17 THEN interval '2 months' ELSE interval '1 month' END
              - interval '1 day')::date;
  ELSE
    v_fim := v_hoje + v_horizonte;
  END IF;
  IF p.end_date IS NOT NULL THEN v_fim := LEAST(v_fim, p.end_date); END IF;
  IF p.frequency = 'once' AND EXISTS (
       SELECT 1 FROM cleaning_bookings b WHERE b.plan_id = p.id AND b.team_slot = 1
          AND NOT (b.status LIKE 'cancelled%' AND b.cancel_reason IN ('plano_mudou_horario','plano_mudou_horas'))) THEN
    RETURN 0;
  END IF;

  v_total := p.total_per_visit_cents;
  IF p.segment = 'empresa' THEN
    SELECT string_agg(COALESCE(CASE t WHEN 'varrer_aspirar' THEN 'varrer e aspirar' WHEN 'po' THEN 'tirar o pó'
                                       WHEN 'casa_de_banho' THEN 'casa de banho' WHEN 'lixo' THEN 'lixo'
                                       WHEN 'vidros_montra' THEN 'vidros e montra' WHEN 'copa' THEN 'copa / cozinha' END, t), ', ')
      INTO v_tarefas FROM unnest(p.tasks) t;
    -- nunca o acesso (chave/código): esse só a profissional vê, e só no dia (cleaning_plan_visit_info)
    v_notas := 'Bora Empresas: ' || COALESCE(p.company_name, '') || ' · ' || COALESCE(p.space_type, '')
               || COALESCE(' · ' || p.area_m2 || ' m²', '') || COALESCE(' · Tarefas: ' || v_tarefas, '')
               || ' · produtos incluídos' || CASE WHEN COALESCE(p.notes, '') <> '' THEN ' · ' || p.notes ELSE '' END;
  ELSE
    v_notas := COALESCE(p.notes, '');
  END IF;

  d := GREATEST(p.start_date, v_hoje);
  WHILE d <= v_fim LOOP
    IF extract(isodow FROM d)::int = ANY (p.days_of_week)
       AND NOT (p.frequency = 'biweekly'
                AND ((date_trunc('week', d)::date - date_trunc('week', p.start_date)::date) / 7) % 2 <> 0)
       AND NOT (d = ANY (p.skipped_dates)) THEN
      v_at := (d + p.visit_time) AT TIME ZONE 'Europe/Lisbon';
      IF v_at >= now() + make_interval(hours => v_lead)
         AND NOT EXISTS (SELECT 1 FROM cleaning_bookings b
                          WHERE b.plan_id = p.id AND b.plan_visit_date = d AND b.team_slot = 1
                            AND NOT (b.status LIKE 'cancelled%'
                                     AND b.cancel_reason IN ('plano_mudou_horario','plano_mudou_horas'))) THEN
        v_team := CASE WHEN p.team_size > 1 THEN gen_random_uuid() END;
        v_ids := '{}';
        FOR v_s IN 1..p.team_size LOOP
          v_vaga := public._cleaning_plan_vaga(p, v_s);
          INSERT INTO cleaning_bookings (
            client_user_id, requested_cleaner_id, recurrence_group_id, recurrence,
            cleaning_type, pricing_mode, home_size, hours, scheduled_at, duration_min,
            address_street, address_city, address_postal, lat, lng, notes, products_by,
            payment_method, payment_status,
            base_cents, type_surcharge_cents, recurring_discount_cents, products_fee_cents,
            total_cents, cleaner_earnings_cents, bora_fee_cents,
            travel_fee_cents, travel_distance_km,
            team_group_id, team_size, team_slot, team_total_cents, share_cents,
            stripe_account, plan_id, plan_visit_date
          ) VALUES (
            p.client_user_id, CASE WHEN v_s = 1 THEN p.requested_cleaner_id END, NULL, 'single',
            'standard', 'hourly', p.home_size, p.hours, v_at, p.hours * 60,
            p.address_street, p.address_city, p.address_postal, p.lat, p.lng, v_notas, p.products_by,
            'card', 'unpaid',
            (v_vaga->>'labor_cents')::int, 0, 0, (v_vaga->>'products_cents')::int,
            CASE WHEN v_s = 1 THEN v_total ELSE 0 END, (v_vaga->>'pro_cents')::int, (v_vaga->>'bora_cents')::int,
            p.travel_fee_cents_per_pro, p.travel_distance_km,
            v_team, p.team_size, v_s, v_total, (v_vaga->>'client_cents')::int,
            'empresa', p.id, d
          ) RETURNING id INTO v_id;
          v_ids := v_ids || v_id;
        END LOOP;
        -- cada vaga toca à parte (exceção de 28/11: plano ativo com cartão toca antes de pagar)
        FOREACH v_id IN ARRAY v_ids LOOP
          PERFORM public._cleaning_next_offer(v_id);
        END LOOP;
        v_n := v_n + 1;
        EXIT WHEN p.frequency = 'once';
      END IF;
    END IF;
    d := d + 1;
  END LOOP;
  RETURN v_n;
END $$;

-- Agendamento diário (cleaning-plan-generate): todos os planos ativos com cartão.
CREATE OR REPLACE FUNCTION public.cleaning_plan_generate()
RETURNS integer LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $$
DECLARE r record; v_n int := 0;
BEGIN
  FOR r IN SELECT id FROM cleaning_plans WHERE status = 'active' AND stripe_payment_method_id IS NOT NULL LOOP
    BEGIN
      v_n := v_n + public._cleaning_plan_gerar_visitas(r.id);
    EXCEPTION WHEN others THEN
      RAISE WARNING 'cleaning_plan_generate: plano % saltado (%)', r.id, sqlerrm;
    END;
  END LOOP;
  RETURN v_n;
END $$;

-- ── 7. Oferta à profissional antes de cobrar (exceção única à regra de 19/10) ──
-- Igual à versão de 19/11/2026 (20261119200000), com UMA linha nova: a visita de um plano
-- ATIVO com cartão guardado é oferecida logo, sem estar paga, para a profissional confirmar
-- antes da cobrança (a cobrança só se faz com todas as vagas confirmadas).
CREATE OR REPLACE FUNCTION public._cleaning_next_offer(p_booking_id uuid)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_b cleaning_bookings;
  v_next uuid;
  v_next_user uuid;
  v_next_nome text;
  v_tem boolean;
  v_timeout int := public._cleaning_setting_int('cleaning_offer_timeout_min', 30);
  v_curto int;
BEGIN
  SELECT * INTO v_b FROM cleaning_bookings WHERE id = p_booking_id FOR UPDATE;
  IF v_b.id IS NULL OR v_b.status <> 'scheduled' THEN RETURN; END IF;
  -- 19/10/2026 (regra do Danilo): só se chama a limpadora se a limpeza estiver paga.
  -- MB Way/cartão por pagar → ninguém é chamado; o gatilho trg_cleaning_paid_offer
  -- chama quando o pagamento entra. Dinheiro chama logo.
  -- 28/11/2026 (planos): EXCEÇÃO ÚNICA — visita de plano ativo com cartão guardado toca já.
  IF v_b.payment_method IN ('mbway','card') AND v_b.payment_status = 'unpaid'
     AND NOT (v_b.plan_id IS NOT NULL AND EXISTS (
               SELECT 1 FROM cleaning_plans pl
                WHERE pl.id = v_b.plan_id AND pl.status = 'active' AND pl.stripe_payment_method_id IS NOT NULL)) THEN
    RETURN;
  END IF;

  SELECT c.id, c.user_id, c.name INTO v_next, v_next_user, v_next_nome
  FROM cleaners c
  WHERE c.approval_status = 'approved' AND c.is_active
    AND c.user_id <> v_b.client_user_id
    AND NOT (c.id = ANY (v_b.offered_cleaner_ids))
    AND (c.base_lat IS NULL OR v_b.lat IS NULL
         OR public._cleaning_distance_km(c.base_lat, c.base_lng, v_b.lat, v_b.lng) <= c.service_radius_km)
    AND public._cleaning_is_available(c.id, v_b.scheduled_at, v_b.duration_min)
    AND public.aceita_papel(c.user_id, 'cleaner')  -- 2026-10-14: papel desligado nao recebe
    -- 19/11/2026 equipa: a mesma profissional nunca fica com duas vagas da mesma limpeza
    AND NOT EXISTS (SELECT 1 FROM cleaning_bookings t
                     WHERE v_b.team_group_id IS NOT NULL
                       AND t.team_group_id = v_b.team_group_id AND t.id <> v_b.id
                       AND t.status NOT LIKE 'cancelled%'
                       AND (t.cleaner_id = c.id OR t.offer_cleaner_id = c.id))
  ORDER BY (c.id = v_b.requested_cleaner_id) DESC,
           public.tem_aparelho(c.user_id, 'cleaner') DESC,
           c.rating_avg DESC, c.cleanings_done DESC
  LIMIT 1;

  IF v_next IS NULL THEN
    UPDATE cleaning_bookings
    SET offer_cleaner_id = NULL, offer_expires_at = NULL
    WHERE id = p_booking_id;
    PERFORM public._cleaning_notify_admin(
      'Limpeza sem profissional',
      'Reserva ' || p_booking_id::text || ' para ' ||
      to_char(v_b.scheduled_at AT TIME ZONE 'Europe/Lisbon', 'DD/MM HH24:MI') ||
      CASE WHEN v_b.team_size > 1
           THEN ' — EQUIPA: falta a vaga ' || v_b.team_slot || ' de ' || v_b.team_size
           ELSE '' END ||
      ' sem profissional disponível.');
    RETURN;
  END IF;

  v_tem := public.tem_aparelho(v_next_user, 'cleaner');
  SELECT COALESCE((value #>> '{}')::int, 1) INTO v_curto
    FROM platform_settings WHERE key = 'oferta_sem_aparelho_min';
  IF NOT v_tem THEN v_timeout := LEAST(v_timeout, COALESCE(v_curto, 1)); END IF;

  UPDATE cleaning_bookings
  SET offer_cleaner_id = v_next,
      offer_expires_at = now() + make_interval(mins => v_timeout),
      offered_cleaner_ids = offered_cleaner_ids || v_next
  WHERE id = p_booking_id;

  PERFORM public.registar_oferta('limpeza', p_booking_id, v_next, v_next_user,
                                 v_next_nome, v_tem, v_timeout);

  PERFORM public._cleaning_notify_user(
    v_next_user,
    'cleaning_offer', 'Nova limpeza disponível',
    'Limpeza a ' || to_char(v_b.scheduled_at AT TIME ZONE 'Europe/Lisbon', 'DD/MM às HH24:MI') ||
    CASE WHEN v_b.team_size > 1
         THEN ' (equipa de ' || v_b.team_size || ' — tu e mais ' || (v_b.team_size - 1) || ')'
         ELSE '' END ||
    ' — ' || 'ganhas ' || (COALESCE(v_b.cleaner_earnings_cents, v_b.total_cents) / 100.0)::numeric(10,2) || ' EUR. Tens ' || v_timeout || ' min para aceitar.',
    p_booking_id::text);
END $function$;

-- ── 8. Funções do cliente ───────────────────────────────────────────────────

CREATE OR REPLACE FUNCTION public.cleaning_plan_create(
  p_segment text, p_frequency text, p_hours integer, p_days integer[], p_time text, p_start_date date,
  p_team_size integer DEFAULT 1, p_products_by text DEFAULT 'client', p_home_size text DEFAULT NULL,
  p_billing_mode text DEFAULT 'per_visit',
  p_address_street text DEFAULT '', p_address_city text DEFAULT '', p_address_postal text DEFAULT '',
  p_lat double precision DEFAULT NULL, p_lng double precision DEFAULT NULL, p_notes text DEFAULT '',
  p_company_name text DEFAULT NULL, p_billing_nif text DEFAULT NULL, p_billing_email text DEFAULT NULL,
  p_space_type text DEFAULT NULL, p_area_m2 integer DEFAULT NULL, p_tasks text[] DEFAULT '{}',
  p_access_instructions text DEFAULT NULL, p_idempotency_key text DEFAULT NULL)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $$
DECLARE
  v_uid uuid := auth.uid();
  v_key text := NULLIF(btrim(COALESCE(p_idempotency_key, '')), '');
  v_ja uuid; v_hora time; v_hoje date := (now() AT TIME ZONE 'Europe/Lisbon')::date;
  v_team int; v_prod text; v_q jsonb; v_nif text; v_id uuid; v_tasks text[];
  v_pr record;
BEGIN
  IF v_uid IS NULL THEN RAISE EXCEPTION 'not_authenticated' USING ERRCODE = '42501'; END IF;

  IF v_key IS NOT NULL THEN
    SELECT id INTO v_ja FROM cleaning_plans WHERE client_user_id = v_uid AND idempotency_key = v_key;
    IF v_ja IS NOT NULL THEN RETURN public._cleaning_plan_json(v_ja); END IF;
    PERFORM pg_advisory_xact_lock(hashtextextended('cleaning_plan_create|' || v_uid::text || '|' || v_key, 0));
    SELECT id INTO v_ja FROM cleaning_plans WHERE client_user_id = v_uid AND idempotency_key = v_key;
    IF v_ja IS NOT NULL THEN RETURN public._cleaning_plan_json(v_ja); END IF;
  END IF;

  IF NOT public._cleaning_setting_bool('cleaning_enabled', true)
     OR NOT public._cleaning_setting_bool('cleaning_plans_enabled', true) THEN
    RAISE EXCEPTION 'planos_desligados';
  END IF;
  IF NOT public._cleaning_setting_bool('cleaning_stripe_enabled', false) THEN
    RAISE EXCEPTION 'card_mbway_not_yet_enabled';
  END IF;
  IF p_segment NOT IN ('casa','empresa') THEN RAISE EXCEPTION 'segmento_invalido: %', p_segment; END IF;
  IF (p_segment = 'casa' AND p_frequency NOT IN ('biweekly','weekly','multi_weekly'))
     OR (p_segment = 'empresa' AND p_frequency NOT IN ('once','weekly_1','weekly_2','weekly_3plus')) THEN
    RAISE EXCEPTION 'frequencia_invalida: %', p_frequency;
  END IF;
  SELECT * INTO v_pr FROM cleaning_plan_prices WHERE segment = p_segment AND frequency = p_frequency;
  IF p_hours IS NULL OR p_hours < COALESCE(v_pr.min_hours, CASE WHEN p_segment = 'empresa' THEN 1 ELSE 2 END) THEN
    RAISE EXCEPTION 'horas_minimas: % h', COALESCE(v_pr.min_hours, 2);
  END IF;
  IF p_hours > 10 THEN RAISE EXCEPTION 'horas_maximas: 10 h'; END IF;
  IF NOT public._cleaning_plan_dias_ok(p_frequency, p_days) THEN
    RAISE EXCEPTION 'dias_da_semana: a frequência % não aceita % dia(s)', p_frequency, COALESCE(cardinality(p_days), 0);
  END IF;
  v_hora := public._cleaning_plan_hora(p_time);
  IF p_start_date IS NULL OR p_start_date < v_hoje OR p_start_date > v_hoje + 90 THEN
    RAISE EXCEPTION 'data_de_inicio: entre hoje e 90 dias';
  END IF;
  IF COALESCE(p_billing_mode, 'per_visit') NOT IN ('per_visit','monthly')
     OR (p_frequency = 'once' AND p_billing_mode = 'monthly') THEN
    RAISE EXCEPTION 'billing_mode_invalido: o mês de uma vez não existe para uma vez';
  END IF;
  IF p_lat IS NULL OR p_lng IS NULL OR COALESCE(btrim(p_address_street), '') = '' THEN
    RAISE EXCEPTION 'morada_obrigatoria';
  END IF;

  v_team := GREATEST(1, LEAST(COALESCE(p_team_size, 1), public._cleaning_setting_int('cleaning_max_professionals', 3), 3));
  IF p_segment = 'empresa' THEN
    v_prod := 'cleaner';
    IF COALESCE(btrim(p_company_name), '') = '' THEN RAISE EXCEPTION 'empresa_nome'; END IF;
    v_nif := regexp_replace(COALESCE(p_billing_nif, ''), '\D', '', 'g');
    IF v_nif = '' THEN RAISE EXCEPTION 'empresa_nif'; END IF;
    IF v_nif !~ '^[0-9]{9}$' THEN RAISE EXCEPTION 'nif_invalido: %', p_billing_nif; END IF;
    IF COALESCE(btrim(p_billing_email), '') !~ '^[^@\s]+@[^@\s]+\.[^@\s]+$' THEN RAISE EXCEPTION 'empresa_email'; END IF;
    IF COALESCE(p_space_type, 'outro') NOT IN ('loja','farmacia','otica','escritorio','clinica','cafe','salao','outro') THEN
      RAISE EXCEPTION 'espaco_invalido: %', p_space_type;
    END IF;
    SELECT COALESCE(array_agg(DISTINCT t), '{}') INTO v_tasks FROM unnest(COALESCE(p_tasks, '{}')) t
     WHERE t IN ('varrer_aspirar','po','casa_de_banho','lixo','vidros_montra','copa');
  ELSE
    v_prod := CASE WHEN p_products_by = 'cleaner' THEN 'cleaner' ELSE 'client' END;
    IF p_home_size IS NOT NULL AND p_home_size NOT IN ('t0_t1','t2','t3','t4plus') THEN
      RAISE EXCEPTION 'tipologia_invalida: %', p_home_size;
    END IF;
    v_tasks := '{}';
  END IF;

  -- o preço vem SEMPRE do servidor (fora_da_area / horas_minimas saem daqui)
  v_q := public.cleaning_plan_quote(p_segment, p_frequency, p_hours::numeric, cardinality(p_days), v_team,
                                    v_prod, p_lat, p_lng);

  INSERT INTO cleaning_plans (
    client_user_id, segment, frequency, days_of_week, visit_time, start_date, hours, team_size, products_by,
    home_size, billing_mode, status,
    client_cents_per_hour, pro_cents_per_hour, travel_fee_cents_per_pro, travel_distance_km, products_cents,
    total_per_visit_cents, approx_month_cents,
    address_street, address_city, address_postal, lat, lng, notes,
    company_name, billing_nif, billing_email, space_type, area_m2, tasks, access_instructions, idempotency_key)
  VALUES (
    v_uid, p_segment, p_frequency, (SELECT array_agg(d ORDER BY d) FROM unnest(p_days) d), v_hora, p_start_date,
    p_hours, v_team, v_prod,
    CASE WHEN p_segment = 'casa' THEN p_home_size END, COALESCE(p_billing_mode, 'per_visit'), 'pending_card',
    (v_q->>'client_cents_per_hour')::int, (v_q->>'pro_cents_per_hour')::int,
    COALESCE((v_q->>'travel_fee_cents_per_pro')::int, 0), NULLIF(v_q #>> '{travel,distance_km}', '')::numeric,
    COALESCE((v_q->>'products_cents')::int, 0),
    (v_q->>'total_per_visit_cents')::int, (v_q->>'approx_month_cents')::int,
    btrim(p_address_street), COALESCE(btrim(p_address_city), ''), COALESCE(btrim(p_address_postal), ''),
    p_lat, p_lng, COALESCE(p_notes, ''),
    CASE WHEN p_segment = 'empresa' THEN btrim(p_company_name) END,
    CASE WHEN p_segment = 'empresa' THEN v_nif END,
    CASE WHEN p_segment = 'empresa' THEN lower(btrim(p_billing_email)) END,
    CASE WHEN p_segment = 'empresa' THEN COALESCE(p_space_type, 'outro') END,
    CASE WHEN p_segment = 'empresa' THEN p_area_m2 END,
    v_tasks,
    CASE WHEN p_segment = 'empresa' THEN NULLIF(btrim(COALESCE(p_access_instructions, '')), '') END,
    v_key)
  RETURNING id INTO v_id;
  RETURN public._cleaning_plan_json(v_id);
EXCEPTION WHEN unique_violation THEN
  SELECT id INTO v_ja FROM cleaning_plans WHERE client_user_id = v_uid AND idempotency_key = v_key;
  IF v_ja IS NOT NULL THEN RETURN public._cleaning_plan_json(v_ja); END IF;
  RAISE;
END $$;

CREATE OR REPLACE FUNCTION public.cleaning_plan_mine()
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path TO 'public' AS $$
DECLARE v_uid uuid := auth.uid();
BEGIN
  IF v_uid IS NULL THEN RAISE EXCEPTION 'not_authenticated' USING ERRCODE = '42501'; END IF;
  RETURN COALESCE((
    SELECT jsonb_agg(public._cleaning_plan_json(p.id) ORDER BY p.created_at DESC)
      FROM cleaning_plans p
     WHERE p.client_user_id = v_uid
       AND (p.status <> 'pending_card' OR p.created_at > now() - interval '2 days')), '[]'::jsonb);
END $$;

-- O plano do cliente, trancado; 'plan_closed' se já não está aberto.
CREATE OR REPLACE FUNCTION public._cleaning_plan_do_cliente(p_plan_id uuid, p_estados text[])
RETURNS public.cleaning_plans LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $$
DECLARE p cleaning_plans;
BEGIN
  IF auth.uid() IS NULL THEN RAISE EXCEPTION 'not_authenticated' USING ERRCODE = '42501'; END IF;
  SELECT * INTO p FROM cleaning_plans WHERE id = p_plan_id AND client_user_id = auth.uid() FOR UPDATE;
  IF p.id IS NULL THEN RAISE EXCEPTION 'plan_not_found'; END IF;
  IF NOT (p.status = ANY (p_estados)) THEN
    RAISE EXCEPTION 'plano_nao_ativo (plan_closed): %', p.status;
  END IF;
  RETURN p;
END $$;

-- Saltar uma limpeza (só a mais de 24 h); já paga → Carteira Bora.
CREATE OR REPLACE FUNCTION public.cleaning_plan_skip(p_plan_id uuid, p_date date)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $$
DECLARE p cleaning_plans; v_b cleaning_bookings; v_at timestamptz;
BEGIN
  p := public._cleaning_plan_do_cliente(p_plan_id, ARRAY['active','paused']);
  IF p_date IS NULL THEN RAISE EXCEPTION 'data_invalida'; END IF;
  SELECT * INTO v_b FROM cleaning_bookings
   WHERE plan_id = p.id AND plan_visit_date = p_date AND team_slot = 1 AND status NOT LIKE 'cancelled%'
   ORDER BY scheduled_at LIMIT 1;
  v_at := COALESCE(v_b.scheduled_at, (p_date + p.visit_time) AT TIME ZONE 'Europe/Lisbon');
  IF v_at <= now() + interval '24 hours' THEN RAISE EXCEPTION 'saltar_so_ate_24h'; END IF;
  UPDATE cleaning_plans
     SET skipped_dates = CASE WHEN p_date = ANY (skipped_dates) THEN skipped_dates ELSE skipped_dates || p_date END,
         updated_at = now()
   WHERE id = p.id;
  IF v_b.id IS NOT NULL THEN
    PERFORM public._cleaning_plan_cancel_visit(v_b.id, 'client', 'plano_saltada');
  END IF;
  RETURN public._cleaning_plan_json(p.id);
END $$;

-- Desmarca as visitas a mais de 24 h para as refazer (mudança de horário/horas → cartão).
CREATE OR REPLACE FUNCTION public._cleaning_plan_refazer(p_plan_id uuid, p_reason text)
RETURNS integer LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $$
DECLARE r record; v_n int := 0;
BEGIN
  FOR r IN SELECT id FROM cleaning_bookings
            WHERE plan_id = p_plan_id AND team_slot = 1 AND status IN ('scheduled','accepted')
              AND scheduled_at > now() + interval '24 hours'
            ORDER BY scheduled_at
  LOOP
    IF public._cleaning_plan_cancel_visit(r.id, 'admin', p_reason) THEN v_n := v_n + 1; END IF;
  END LOOP;
  PERFORM public._cleaning_plan_gerar_visitas(p_plan_id);
  RETURN v_n;
END $$;

CREATE OR REPLACE FUNCTION public.cleaning_plan_change_schedule(p_plan_id uuid, p_days integer[], p_time text)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $$
DECLARE p cleaning_plans; v_hora time;
BEGIN
  p := public._cleaning_plan_do_cliente(p_plan_id, ARRAY['active','paused','pending_card']);
  IF NOT public._cleaning_plan_dias_ok(p.frequency, p_days) THEN
    RAISE EXCEPTION 'dias_da_semana: a frequência % não aceita % dia(s)', p.frequency, COALESCE(cardinality(p_days), 0);
  END IF;
  v_hora := public._cleaning_plan_hora(p_time);
  UPDATE cleaning_plans
     SET days_of_week = (SELECT array_agg(d ORDER BY d) FROM unnest(p_days) d), visit_time = v_hora,
         approx_month_cents = CASE WHEN frequency = 'once' THEN total_per_visit_cents
                                   ELSE round(total_per_visit_cents * public._cleaning_plan_visitas_mes(frequency, cardinality(p_days)))::int END,
         updated_at = now()
   WHERE id = p.id;
  PERFORM public._cleaning_plan_refazer(p.id, 'plano_mudou_horario');
  RETURN public._cleaning_plan_json(p.id);
END $$;

CREATE OR REPLACE FUNCTION public.cleaning_plan_change_hours(p_plan_id uuid, p_hours integer)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $$
DECLARE p cleaning_plans; v_min numeric; v_total int;
BEGIN
  p := public._cleaning_plan_do_cliente(p_plan_id, ARRAY['active','paused','pending_card']);
  SELECT min_hours INTO v_min FROM cleaning_plan_prices WHERE segment = p.segment AND frequency = p.frequency;
  v_min := COALESCE(v_min, CASE WHEN p.segment = 'empresa' THEN 1 ELSE 2 END);
  IF p_hours IS NULL OR p_hours < v_min THEN RAISE EXCEPTION 'horas_minimas: % h', v_min; END IF;
  IF p_hours > 10 THEN RAISE EXCEPTION 'horas_maximas: 10 h'; END IF;
  IF p_hours = p.hours THEN RETURN public._cleaning_plan_json(p.id); END IF;
  -- o preço por hora do plano fica o mesmo
  v_total := (p.client_cents_per_hour * p_hours + p.travel_fee_cents_per_pro) * p.team_size + p.products_cents;
  UPDATE cleaning_plans
     SET hours = p_hours, total_per_visit_cents = v_total,
         approx_month_cents = CASE WHEN frequency = 'once' THEN v_total
                                   ELSE round(v_total * public._cleaning_plan_visitas_mes(frequency, cardinality(days_of_week)))::int END,
         updated_at = now()
   WHERE id = p.id;
  PERFORM public._cleaning_plan_refazer(p.id, 'plano_mudou_horas');
  RETURN public._cleaning_plan_json(p.id);
END $$;

-- Cancelar o plano, sem taxa. Desmarca as visitas a mais de 24 h e as que ainda não têm
-- profissional; as já pagas voltam à Carteira Bora. DECISÃO A CONFIRMAR (Danilo): a visita das
-- próximas 24 h com profissional confirmada mantém-se (e cobra-se). O ecrã diz isso.
CREATE OR REPLACE FUNCTION public.cleaning_plan_cancel(p_plan_id uuid, p_reason text DEFAULT 'cliente')
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $$
DECLARE p cleaning_plans; r record;
BEGIN
  p := public._cleaning_plan_do_cliente(p_plan_id, ARRAY['active','paused','pending_card']);
  UPDATE cleaning_plans
     SET status = 'cancelled', cancelled_at = now(), cancelled_by = 'client',
         cancel_reason = COALESCE(NULLIF(btrim(p_reason), ''), 'cliente'), updated_at = now()
   WHERE id = p.id;
  FOR r IN SELECT id, scheduled_at FROM cleaning_bookings
            WHERE plan_id = p.id AND team_slot = 1 AND status IN ('scheduled','accepted','on_the_way')
            ORDER BY scheduled_at
  LOOP
    IF r.scheduled_at > now() + interval '24 hours' OR NOT public._cleaning_plan_visita_confirmada(r.id) THEN
      BEGIN
        PERFORM public._cleaning_plan_cancel_visit(r.id, 'client', 'plano_cancelado');
      EXCEPTION WHEN others THEN
        -- uma visita cuja devolução falhou não trava o resto; a dela desfaz-se com o bloco
        RAISE WARNING 'cleaning_plan_cancel: visita % saltada (%)', r.id, sqlerrm;
      END;
    END IF;
  END LOOP;
  -- cobranças que ainda não passaram e já não têm visitas
  UPDATE cleaning_plan_charges SET status = 'cancelled', updated_at = now()
   WHERE plan_id = p.id AND status IN ('scheduled','waiting_cleaner','pending','failed','requires_action')
     AND NOT EXISTS (SELECT 1 FROM cleaning_plan_charge_items i WHERE i.charge_id = cleaning_plan_charges.id);
  RETURN public._cleaning_plan_json(p.id);
END $$;

-- Para a PROFISSIONAL: o que precisa de saber da visita do plano. O acesso (chave/código) só
-- aparece para quem aceitou e no próprio dia de Lisboa.
CREATE OR REPLACE FUNCTION public.cleaning_plan_visit_info(p_booking_id uuid)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path TO 'public' AS $$
DECLARE v_me cleaners; v_b cleaning_bookings; p cleaning_plans; v_hoje boolean; v_ve boolean;
BEGIN
  v_me := public._cleaning_current_cleaner();
  SELECT * INTO v_b FROM cleaning_bookings WHERE id = p_booking_id;
  IF v_b.id IS NULL OR v_b.plan_id IS NULL THEN RETURN NULL; END IF;
  IF v_b.cleaner_id IS DISTINCT FROM v_me.id AND v_b.offer_cleaner_id IS DISTINCT FROM v_me.id THEN
    RAISE EXCEPTION 'booking_not_yours';
  END IF;
  SELECT * INTO p FROM cleaning_plans WHERE id = v_b.plan_id;
  v_hoje := (v_b.scheduled_at AT TIME ZONE 'Europe/Lisbon')::date = (now() AT TIME ZONE 'Europe/Lisbon')::date;
  v_ve := v_b.cleaner_id = v_me.id AND v_hoje AND v_b.status NOT LIKE 'cancelled%';
  RETURN jsonb_build_object(
    'segment', p.segment, 'frequency', p.frequency, 'company_name', p.company_name,
    'space_type', p.space_type, 'area_m2', p.area_m2, 'tasks', to_jsonb(p.tasks),
    'products_included', p.segment = 'empresa',
    'access_instructions', CASE WHEN v_ve THEN p.access_instructions END,
    'access_available_on_the_day', COALESCE(p.access_instructions, '') <> '' AND NOT v_ve);
END $$;

-- ── 9. Cartão guardado, cobranças e devoluções (só o servidor: Edge cleaning-plan,
--       cleaning-plan-charge e stripe-webhook-empresa) ─────────────────────────

-- O cartão ficou guardado (confirm_setup ou setup_intent.succeeded). Idempotente.
CREATE OR REPLACE FUNCTION public.cleaning_plan_card_saved(
  p_plan_id uuid, p_user_id uuid, p_customer_id text, p_payment_method_id text,
  p_brand text DEFAULT NULL, p_last4 text DEFAULT NULL, p_exp_month integer DEFAULT NULL, p_exp_year integer DEFAULT NULL)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $$
DECLARE p cleaning_plans; v_era text; v_n int := 0;
BEGIN
  SELECT * INTO p FROM cleaning_plans WHERE id = p_plan_id FOR UPDATE;
  IF p.id IS NULL OR p.client_user_id IS DISTINCT FROM p_user_id THEN RAISE EXCEPTION 'plan_not_found'; END IF;
  IF p.status NOT IN ('pending_card','active','paused') THEN RAISE EXCEPTION 'plan_closed: %', p.status; END IF;
  IF COALESCE(p_payment_method_id, '') = '' OR COALESCE(p_customer_id, '') = '' THEN RAISE EXCEPTION 'setup_not_completed'; END IF;
  v_era := p.status;
  IF p.stripe_payment_method_id = p_payment_method_id AND p.status <> 'pending_card' THEN
    RETURN jsonb_build_object('ok', true, 'already', true, 'status', p.status);
  END IF;
  UPDATE cleaning_plans
     SET stripe_customer_id = p_customer_id, stripe_payment_method_id = p_payment_method_id,
         card_brand = p_brand, card_last4 = p_last4, card_exp_month = p_exp_month, card_exp_year = p_exp_year,
         card_saved_at = now(),
         status = CASE WHEN status = 'pending_card' THEN 'active' ELSE status END,
         activated_at = COALESCE(activated_at, CASE WHEN status = 'pending_card' THEN now() END),
         updated_at = now()
   WHERE id = p.id;
  IF v_era = 'pending_card' THEN
    v_n := public._cleaning_plan_gerar_visitas(p.id);
    PERFORM public._cleaning_notify_user(p.client_user_id, 'cleaning_plan_active', 'Plano de limpeza ativo',
      'O teu plano começou. Cobramos cada limpeza 24 h antes, e só com a profissional confirmada. Cancelas quando quiseres, sem taxa.',
      NULL);
  ELSE
    -- troca de cartão: as cobranças falhadas ou à espera do banco tentam já com o cartão novo
    UPDATE cleaning_plan_charges
       SET status = 'pending', repeat_same_key = false, next_attempt_at = NULL, charge_after = LEAST(charge_after, now()),
           card_last4 = p_last4, updated_at = now()
     WHERE plan_id = p.id AND status IN ('failed','requires_action')
       AND (deadline_at IS NULL OR deadline_at > now());
  END IF;
  RETURN jsonb_build_object('ok', true, 'status', (SELECT status FROM cleaning_plans WHERE id = p.id), 'visitas', v_n);
END $$;

-- Uma cobrança paga: a(s) visita(s) ficam pagas; visita que já caiu ou já estava paga → cartão.
CREATE OR REPLACE FUNCTION public._cleaning_plan_marcar_pago(p_charge_id uuid, p_payment_intent_id text,
                                                             p_receipt_url text, p_card_last4 text)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $$
DECLARE c cleaning_plan_charges; r record; v_last4 text;
BEGIN
  SELECT * INTO c FROM cleaning_plan_charges WHERE id = p_charge_id FOR UPDATE;
  IF c.id IS NULL OR c.status = 'succeeded' THEN RETURN; END IF;
  UPDATE cleaning_plan_charges
     SET status = 'succeeded', paid_at = now(), processing_started_at = NULL, repeat_same_key = false,
         stripe_payment_intent_id = COALESCE(p_payment_intent_id, stripe_payment_intent_id),
         receipt_url = COALESCE(p_receipt_url, receipt_url), card_last4 = COALESCE(p_card_last4, card_last4),
         last_error = NULL, updated_at = now()
   WHERE id = c.id;
  FOR r IN SELECT i.booking_id, b.status, b.payment_status,
                  EXISTS (SELECT 1 FROM cleaning_plan_charge_items i2 JOIN cleaning_plan_charges c2 ON c2.id = i2.charge_id
                           WHERE i2.booking_id = i.booking_id AND c2.status = 'succeeded' AND c2.id <> c.id) AS ja_pago
             FROM cleaning_plan_charge_items i JOIN cleaning_bookings b ON b.id = i.booking_id
            WHERE i.charge_id = c.id
  LOOP
    IF r.status LIKE 'cancelled%' OR r.ja_pago THEN
      -- a visita caiu entretanto, ou foi paga duas vezes → devolve ao cartão (desta cobrança)
      INSERT INTO cleaning_plan_refunds (booking_id, charge_id, plan_id, client_user_id, method, amount_cents, reason, next_attempt_at)
      SELECT r.booking_id, c.id, c.plan_id, c.client_user_id, 'card', i.amount_cents,
             CASE WHEN r.ja_pago THEN 'visita paga duas vezes' ELSE 'cobrança entrou depois de a visita cair' END, now()
        FROM cleaning_plan_charge_items i WHERE i.charge_id = c.id AND i.booking_id = r.booking_id AND i.amount_cents > 0
      ON CONFLICT (booking_id) DO NOTHING;
      IF NOT FOUND THEN
        PERFORM public.notify_admin_urgent_push('cleaning_plan_refund_conflito',
          '💳 PLANO DE LIMPEZA — cobrança ' || c.id || ' entrou para uma visita que já tem devolução. Ver na Stripe.',
          'cleaning_plan_charges', c.id::text, jsonb_build_object('charge_id', c.id, 'booking_id', r.booking_id),
          '/admin/limpeza/planos');
      END IF;
    ELSIF r.payment_status = 'unpaid' THEN
      UPDATE cleaning_bookings SET payment_status = 'held', stripe_account = 'empresa' WHERE id = r.booking_id;
    END IF;
  END LOOP;
  v_last4 := COALESCE(p_card_last4, c.card_last4, (SELECT card_last4 FROM cleaning_plans WHERE id = c.plan_id));
  PERFORM public._cleaning_notify_user(c.client_user_id, 'cleaning_plan_charged', 'Pagamento feito',
    'Cobrámos ' || public._cleaning_plan_euro(c.amount_cents) || ' no cartão terminado em ' || COALESCE(v_last4, '••••')
    || '. O recibo vai para o teu email.',
    (SELECT booking_id::text FROM cleaning_plan_charge_items WHERE charge_id = c.id LIMIT 1));
END $$;

-- Arruma as cobranças (corre no início de cada volta do robô cleaning-plan-charge).
CREATE OR REPLACE FUNCTION public._cleaning_plan_arrumar()
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $$
DECLARE
  v_antes int := public._cleaning_setting_int('cleaning_plan_charge_hours_before', 24);
  v_hoje date := (now() AT TIME ZONE 'Europe/Lisbon')::date;
  v_mes date; r record; v_id uuid; v_total int; v_criadas int := 0; v_meses int := 0; v_sem int := 0; v_caidas int := 0;
BEGIN
  -- a) "A cada limpeza": 48 h antes cria a cobrança e avisa
  FOR r IN SELECT b.id, b.scheduled_at, b.total_cents, b.client_user_id, p.id AS plan_id, p.card_last4
             FROM cleaning_bookings b JOIN cleaning_plans p ON p.id = b.plan_id
            WHERE b.team_slot = 1 AND b.status IN ('scheduled','accepted','on_the_way')
              AND b.payment_status = 'unpaid' AND b.total_cents > 0
              AND b.scheduled_at > now() AND b.scheduled_at <= now() + make_interval(hours => v_antes + 24)
              AND p.status IN ('active','cancelled','paused') AND p.stripe_payment_method_id IS NOT NULL
              AND NOT EXISTS (SELECT 1 FROM cleaning_plan_charge_items i JOIN cleaning_plan_charges c ON c.id = i.charge_id
                               WHERE i.booking_id = b.id AND c.status NOT IN ('cancelled','failed_final'))
              AND NOT EXISTS (SELECT 1 FROM cleaning_plan_charges c WHERE c.idempotency_key = 'visit-' || b.id)
  LOOP
    INSERT INTO cleaning_plan_charges (plan_id, client_user_id, kind, idempotency_key, period_month, amount_cents,
                                       status, charge_after, deadline_at, card_last4, notice_sent_at)
    VALUES (r.plan_id, r.client_user_id, 'visit', 'visit-' || r.id,
            date_trunc('month', r.scheduled_at AT TIME ZONE 'Europe/Lisbon')::date, r.total_cents, 'scheduled',
            GREATEST(now(), r.scheduled_at - make_interval(hours => v_antes)), r.scheduled_at - interval '12 hours',
            r.card_last4, now())
    ON CONFLICT (idempotency_key) DO NOTHING
    RETURNING id INTO v_id;
    IF v_id IS NOT NULL THEN
      INSERT INTO cleaning_plan_charge_items (charge_id, booking_id, amount_cents) VALUES (v_id, r.id, r.total_cents);
      PERFORM public._cleaning_notify_user(r.client_user_id, 'cleaning_plan_notice', 'Próxima limpeza do plano',
        'Vamos cobrar ' || public._cleaning_plan_euro(r.total_cents) || ' no cartão terminado em ' || COALESCE(r.card_last4, '••••')
        || ' 24 h antes da limpeza de ' || public._cleaning_plan_quando(r.scheduled_at) || ', e só com a profissional confirmada.',
        r.id::text);
      v_criadas := v_criadas + 1;
    END IF;
  END LOOP;

  -- b) "O mês de uma vez": na véspera do dia 1 (ou no dia 1) junta as visitas JÁ confirmadas a mais de 24 h
  IF (v_hoje + 1) = date_trunc('month', v_hoje + 1)::date OR extract(day FROM v_hoje) = 1 THEN
    v_mes := CASE WHEN extract(day FROM v_hoje) = 1 THEN v_hoje ELSE v_hoje + 1 END;
    FOR r IN SELECT p.* FROM cleaning_plans p
              WHERE p.status = 'active' AND p.billing_mode = 'monthly' AND p.stripe_payment_method_id IS NOT NULL
                AND NOT EXISTS (SELECT 1 FROM cleaning_plan_charges c
                                 WHERE c.idempotency_key = 'month-' || p.id || '-' || to_char(v_mes, 'YYYY-MM'))
    LOOP
      SELECT COALESCE(sum(b.total_cents), 0) INTO v_total
        FROM cleaning_bookings b
       WHERE b.plan_id = r.id AND b.team_slot = 1 AND b.status IN ('scheduled','accepted')
         AND b.payment_status = 'unpaid' AND b.total_cents > 0
         AND date_trunc('month', b.plan_visit_date)::date = v_mes
         AND b.scheduled_at > now() + interval '24 hours'
         AND public._cleaning_plan_visita_confirmada(b.id)
         AND NOT EXISTS (SELECT 1 FROM cleaning_plan_charge_items i JOIN cleaning_plan_charges c ON c.id = i.charge_id
                          WHERE i.booking_id = b.id AND c.status NOT IN ('cancelled','failed_final'));
      CONTINUE WHEN v_total = 0;
      INSERT INTO cleaning_plan_charges (plan_id, client_user_id, kind, idempotency_key, period_month, amount_cents,
                                         status, charge_after, card_last4, notice_sent_at)
      VALUES (r.id, r.client_user_id, 'month', 'month-' || r.id || '-' || to_char(v_mes, 'YYYY-MM'), v_mes, v_total,
              'pending', now() + interval '1 hour', r.card_last4, now())
      ON CONFLICT (idempotency_key) DO NOTHING
      RETURNING id INTO v_id;
      CONTINUE WHEN v_id IS NULL;
      INSERT INTO cleaning_plan_charge_items (charge_id, booking_id, amount_cents)
      SELECT v_id, b.id, b.total_cents FROM cleaning_bookings b
       WHERE b.plan_id = r.id AND b.team_slot = 1 AND b.status IN ('scheduled','accepted')
         AND b.payment_status = 'unpaid' AND b.total_cents > 0
         AND date_trunc('month', b.plan_visit_date)::date = v_mes
         AND b.scheduled_at > now() + interval '24 hours'
         AND public._cleaning_plan_visita_confirmada(b.id)
         AND NOT EXISTS (SELECT 1 FROM cleaning_plan_charge_items i JOIN cleaning_plan_charges c ON c.id = i.charge_id
                          WHERE i.booking_id = b.id AND c.status NOT IN ('cancelled','failed_final'));
      PERFORM public._cleaning_notify_user(r.client_user_id, 'cleaning_plan_notice', 'Cobrança do mês',
        'Vamos cobrar ' || public._cleaning_plan_euro(v_total) || ' no cartão terminado em ' || COALESCE(r.card_last4, '••••')
        || ' pelas limpezas de ' || to_char(v_mes, 'MM/YYYY') || ' já confirmadas. As outras cobram-se uma a uma, 24 h antes.',
        NULL);
      v_meses := v_meses + 1;
    END LOOP;
  END IF;

  -- c) a hora chegou: com TODAS as vagas confirmadas → pronta; sem profissional → não cobra, avisa uma vez
  FOR r IN SELECT c.id, c.client_user_id, c.no_cleaner_alerted_at, i.booking_id, b.scheduled_at
             FROM cleaning_plan_charges c
             JOIN cleaning_plan_charge_items i ON i.charge_id = c.id
             JOIN cleaning_bookings b ON b.id = i.booking_id
            WHERE c.kind = 'visit' AND c.status IN ('scheduled','waiting_cleaner') AND c.charge_after <= now()
            FOR UPDATE OF c SKIP LOCKED
  LOOP
    IF public._cleaning_plan_visita_confirmada(r.booking_id) THEN
      UPDATE cleaning_plan_charges SET status = 'pending', updated_at = now() WHERE id = r.id;
    ELSE
      UPDATE cleaning_plan_charges SET status = 'waiting_cleaner', updated_at = now(),
             no_cleaner_alerted_at = COALESCE(no_cleaner_alerted_at, now())
       WHERE id = r.id;
      IF r.no_cleaner_alerted_at IS NULL THEN
        PERFORM public._cleaning_notify_user(r.client_user_id, 'cleaning_plan_no_cleaner', 'Ainda à procura de profissional',
          'A limpeza de ' || public._cleaning_plan_quando(r.scheduled_at)
          || ' ainda não tem profissional, não cobrámos nada. Cobramos só quando alguém confirmar.', r.booking_id::text);
        BEGIN
          PERFORM public.notify_admin_urgent_push('cleaning_plan_no_cleaner',
            '🧹 PLANO DE LIMPEZA SEM PROFISSIONAL a 24 h · ' || public._alerta_quem(r.client_user_id)
            || E'\nLimpeza de ' || public._cleaning_plan_quando(r.scheduled_at) || '. Não foi cobrada.',
            'cleaning_booking', r.booking_id::text,
            jsonb_build_object('charge_id', r.id, 'booking_id', r.booking_id), '/admin/limpeza/' || r.booking_id::text);
        EXCEPTION WHEN others THEN
          RAISE WARNING '_cleaning_plan_arrumar: alerta falhou (%)', sqlerrm;
        END;
      END IF;
      v_sem := v_sem + 1;
    END IF;
  END LOOP;

  -- d) antes de cobrar o mês: tira as visitas que caíram, perderam a profissional ou já estão pagas
  FOR r IN SELECT i.id AS item_id, i.charge_id FROM cleaning_plan_charge_items i
             JOIN cleaning_plan_charges c ON c.id = i.charge_id
             JOIN cleaning_bookings b ON b.id = i.booking_id
            WHERE c.kind = 'month' AND c.status IN ('pending','failed')
              AND (b.status LIKE 'cancelled%' OR b.payment_status <> 'unpaid'
                   OR NOT public._cleaning_plan_visita_confirmada(b.id))
  LOOP
    DELETE FROM cleaning_plan_charge_items WHERE id = r.item_id;
    SELECT COALESCE(sum(amount_cents), 0) INTO v_total FROM cleaning_plan_charge_items WHERE charge_id = r.charge_id;
    UPDATE cleaning_plan_charges SET amount_cents = v_total,
           status = CASE WHEN v_total = 0 THEN 'cancelled' ELSE status END, updated_at = now()
     WHERE id = r.charge_id;
  END LOOP;

  -- e) prazos: visita com pagamento por resolver depois das 12 h antes → desmarcada
  FOR r IN SELECT c.id, c.client_user_id, i.booking_id, b.scheduled_at, b.cleaner_id
             FROM cleaning_plan_charges c
             JOIN cleaning_plan_charge_items i ON i.charge_id = c.id
             JOIN cleaning_bookings b ON b.id = i.booking_id
            WHERE c.kind = 'visit' AND c.status IN ('failed','requires_action')
              AND c.deadline_at IS NOT NULL AND now() > c.deadline_at + interval '40 minutes'
            FOR UPDATE OF c SKIP LOCKED
  LOOP
    UPDATE cleaning_plan_charges SET status = 'failed_final', updated_at = now() WHERE id = r.id;
    PERFORM public._cleaning_plan_cancel_visit(r.booking_id, 'admin', 'plano_pagamento_falhou');
    PERFORM public._cleaning_notify_user(r.client_user_id, 'cleaning_plan_failed', 'Limpeza desmarcada',
      'Não conseguimos cobrar a limpeza de ' || public._cleaning_plan_quando(r.scheduled_at)
      || ', por isso foi desmarcada e não pagas nada. Troca o cartão em Limpeza → O meu plano para as próximas.',
      r.booking_id::text);
    BEGIN
      PERFORM public.notify_admin_urgent_push('cleaning_plan_charge_failed',
        '💳 PLANO DE LIMPEZA — pagamento falhou de vez · ' || public._alerta_quem(r.client_user_id)
        || E'\nLimpeza de ' || public._cleaning_plan_quando(r.scheduled_at) || ' desmarcada.',
        'cleaning_plan_charges', r.id::text, jsonb_build_object('charge_id', r.id, 'booking_id', r.booking_id),
        '/admin/limpeza/' || r.booking_id::text);
    EXCEPTION WHEN others THEN
      RAISE WARNING '_cleaning_plan_arrumar: alerta falhou (%)', sqlerrm;
    END;
    v_caidas := v_caidas + 1;
  END LOOP;

  -- f) mês à espera do banco há mais de 24 h → falha de vez e cai para visita a visita
  UPDATE cleaning_plan_charges SET status = 'failed_final', last_error = COALESCE(last_error, 'sem confirmação do banco em 24 h'),
         updated_at = now()
   WHERE kind = 'month' AND status = 'requires_action' AND updated_at < now() - interval '24 hours';

  RETURN jsonb_build_object('criadas', v_criadas, 'meses', v_meses, 'sem_profissional', v_sem, 'desmarcadas', v_caidas);
END $$;

-- O que cobrar agora (o robô cobra fora de sessão no cartão guardado). Marca 'processing'.
-- Tentativa presa há mais de 15 min, ou erro de rede: repete com a MESMA chave.
CREATE OR REPLACE FUNCTION public.cleaning_plan_charges_due(p_limit integer DEFAULT 25)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $$
DECLARE v_arr jsonb; r record; v_out jsonb := '[]'::jsonb; v_tent int; v_presa boolean; v_email text;
BEGIN
  v_arr := public._cleaning_plan_arrumar();
  FOR r IN SELECT c.*, p.stripe_customer_id, p.stripe_payment_method_id, p.billing_email, p.company_name,
                  p.billing_nif, p.segment, p.card_last4 AS plan_last4
             FROM cleaning_plan_charges c JOIN cleaning_plans p ON p.id = c.plan_id
            WHERE p.stripe_payment_method_id IS NOT NULL AND c.amount_cents >= 50
              AND ((c.status = 'pending' AND c.charge_after <= now())
                OR (c.status = 'failed' AND c.attempts < 3 AND c.next_attempt_at <= now())
                OR (c.status = 'processing' AND c.processing_started_at < now() - interval '15 minutes'))
            ORDER BY c.charge_after
            LIMIT GREATEST(1, LEAST(COALESCE(p_limit, 25), 100))
            FOR UPDATE OF c SKIP LOCKED
  LOOP
    -- visita: ainda com todas as vagas confirmadas e viva?
    IF r.kind = 'visit' AND r.status <> 'processing' AND NOT EXISTS (
         SELECT 1 FROM cleaning_plan_charge_items i JOIN cleaning_bookings b ON b.id = i.booking_id
          WHERE i.charge_id = r.id AND b.status NOT LIKE 'cancelled%' AND public._cleaning_plan_visita_confirmada(b.id)) THEN
      UPDATE cleaning_plan_charges SET status = 'waiting_cleaner', updated_at = now() WHERE id = r.id;
      CONTINUE;
    END IF;
    v_presa := r.status = 'processing' OR r.repeat_same_key;
    v_tent := CASE WHEN v_presa THEN GREATEST(r.attempts, 1) ELSE r.attempts + 1 END;
    UPDATE cleaning_plan_charges
       SET status = 'processing', attempts = v_tent, repeat_same_key = false, processing_started_at = now(),
           updated_at = now()
     WHERE id = r.id;
    SELECT u.email INTO v_email FROM auth.users u WHERE u.id = r.client_user_id;
    v_out := v_out || jsonb_build_object(
      'charge_id', r.id, 'plan_id', r.plan_id, 'user_id', r.client_user_id, 'kind', r.kind,
      'amount_cents', r.amount_cents, 'attempt', v_tent, 'repeat', v_presa,
      'stripe_idempotency_key', 'cleaning-plan-' || r.idempotency_key || '-a' || v_tent,
      'customer_id', r.stripe_customer_id, 'payment_method_id', r.stripe_payment_method_id,
      'receipt_email', COALESCE(r.billing_email, v_email),
      'segment', r.segment, 'company_name', r.company_name, 'billing_nif', r.billing_nif,
      'period_month', to_char(COALESCE(r.period_month, (now() AT TIME ZONE 'Europe/Lisbon')::date), 'MM/YYYY'),
      'card_last4', COALESCE(r.card_last4, r.plan_last4));
  END LOOP;
  RETURN jsonb_build_object('arrumacao', v_arr, 'cobrar', v_out);
END $$;

-- O resultado de uma tentativa. p_outcome: 'succeeded' | 'processing' | 'requires_action' |
-- 'card_error' (cartão recusado/expirado: conta) | 'transient' (rede/Stripe: não conta, mesma chave).
-- Um 'succeeded' nunca volta atrás; resultados de uma tentativa antiga não mexem em nada.
CREATE OR REPLACE FUNCTION public.cleaning_plan_charge_result(
  p_charge_id uuid, p_attempt integer, p_outcome text, p_payment_intent_id text DEFAULT NULL,
  p_receipt_url text DEFAULT NULL, p_card_last4 text DEFAULT NULL, p_error text DEFAULT NULL)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $$
DECLARE c cleaning_plan_charges; v_email text; v_final boolean := false; r record; v_quando text; v_primeira timestamptz;
BEGIN
  SELECT * INTO c FROM cleaning_plan_charges WHERE id = p_charge_id FOR UPDATE;
  IF c.id IS NULL THEN RAISE EXCEPTION 'charge_not_found'; END IF;
  IF c.status = 'succeeded' THEN RETURN jsonb_build_object('ok', true, 'status', 'succeeded', 'already', true); END IF;
  IF p_outcome = 'succeeded' THEN
    PERFORM public._cleaning_plan_marcar_pago(c.id, p_payment_intent_id, p_receipt_url, p_card_last4);
    RETURN jsonb_build_object('ok', true, 'status', 'succeeded');
  END IF;
  IF p_attempt IS DISTINCT FROM c.attempts OR c.status IN ('cancelled','failed_final') THEN
    RETURN jsonb_build_object('ok', true, 'status', c.status, 'stale', true);
  END IF;
  SELECT u.email INTO v_email FROM auth.users u WHERE u.id = c.client_user_id;
  SELECT min(b.scheduled_at) INTO v_primeira FROM cleaning_plan_charge_items i JOIN cleaning_bookings b ON b.id = i.booking_id
   WHERE i.charge_id = c.id;
  v_quando := COALESCE(public._cleaning_plan_quando(v_primeira), '');

  IF p_outcome = 'processing' THEN
    UPDATE cleaning_plan_charges SET stripe_payment_intent_id = COALESCE(p_payment_intent_id, stripe_payment_intent_id),
           processing_started_at = now() + interval '6 hours', updated_at = now()   -- o webhook acaba
     WHERE id = c.id;
    RETURN jsonb_build_object('ok', true, 'status', 'processing');
  ELSIF p_outcome = 'transient' THEN
    UPDATE cleaning_plan_charges SET status = 'pending', repeat_same_key = true, processing_started_at = NULL,
           last_error = left(COALESCE(p_error, 'erro de rede'), 500), updated_at = now()
     WHERE id = c.id;
    RETURN jsonb_build_object('ok', true, 'status', 'pending', 'repeat', true);
  ELSIF p_outcome = 'requires_action' THEN
    UPDATE cleaning_plan_charges SET status = 'requires_action', processing_started_at = NULL,
           stripe_payment_intent_id = COALESCE(p_payment_intent_id, stripe_payment_intent_id),
           last_error = left(COALESCE(p_error, 'o banco pede confirmação'), 500), action_notified_at = now(),
           updated_at = now()
     WHERE id = c.id;
    PERFORM public._cleaning_notify_user(c.client_user_id, 'cleaning_plan_action', 'Confirma o pagamento',
      'O teu banco pede para confirmares o pagamento de ' || public._cleaning_plan_euro(c.amount_cents)
      || '. Abre Limpeza → O meu plano e toca em "Confirmar pagamento".', NULL);
    RETURN jsonb_build_object('ok', true, 'status', 'requires_action');
  ELSIF p_outcome = 'card_error' THEN
    v_final := c.attempts >= 3 OR (c.kind = 'visit' AND c.deadline_at IS NOT NULL AND now() >= c.deadline_at);
    UPDATE cleaning_plan_charges
       SET status = CASE WHEN v_final THEN 'failed_final' ELSE 'failed' END,
           stripe_payment_intent_id = COALESCE(p_payment_intent_id, stripe_payment_intent_id),
           processing_started_at = NULL, last_error = left(COALESCE(p_error, 'cartão recusado'), 500),
           next_attempt_at = CASE WHEN v_final THEN NULL
                                  WHEN c.kind = 'month' THEN now() + interval '6 hours'
                                  WHEN c.attempts = 1 THEN LEAST(now() + interval '6 hours', c.deadline_at)
                                  ELSE c.deadline_at END,
           failure_notified_at = now(), updated_at = now()
     WHERE id = c.id;
    IF v_final AND c.kind = 'visit' THEN
      FOR r IN SELECT booking_id FROM cleaning_plan_charge_items WHERE charge_id = c.id LOOP
        PERFORM public._cleaning_plan_cancel_visit(r.booking_id, 'admin', 'plano_pagamento_falhou');
      END LOOP;
      PERFORM public._cleaning_notify_user(c.client_user_id, 'cleaning_plan_failed', 'Limpeza desmarcada',
        'Não conseguimos cobrar a limpeza de ' || v_quando || ', por isso foi desmarcada e não pagas nada. Troca o cartão em Limpeza → O meu plano.',
        NULL);
      BEGIN
        PERFORM public.notify_admin_urgent_push('cleaning_plan_charge_failed',
          '💳 PLANO DE LIMPEZA — pagamento falhou de vez · ' || public._alerta_quem(c.client_user_id)
          || E'\nLimpeza de ' || v_quando || ' desmarcada (' || COALESCE(p_error, 'cartão recusado') || ').',
          'cleaning_plan_charges', c.id::text, jsonb_build_object('charge_id', c.id), '/admin/limpeza/planos');
      EXCEPTION WHEN others THEN RAISE WARNING 'cleaning_plan_charge_result: alerta falhou (%)', sqlerrm; END;
    ELSIF NOT v_final THEN
      PERFORM public._cleaning_notify_user(c.client_user_id, 'cleaning_plan_failed', 'O pagamento não passou',
        'O pagamento de ' || public._cleaning_plan_euro(c.amount_cents) || ' não passou. Vamos tentar outra vez; para não perderes a limpeza, troca o cartão em Limpeza → O meu plano.',
        NULL);
    END IF;
    -- mês falhado de vez: as visitas soltam-se e cobram-se uma a uma (a arrumação cria as cobranças)
    RETURN jsonb_build_object('ok', true, 'status', CASE WHEN v_final THEN 'failed_final' ELSE 'failed' END,
      'email', jsonb_build_object('to', v_email, 'tipo', 'trocar_cartao', 'amount_cents', c.amount_cents,
                                  'final', v_final, 'quando', v_quando));
  END IF;
  RAISE EXCEPTION 'outcome_invalido: %', p_outcome;
END $$;

-- Eventos da Stripe (stripe-webhook-empresa), só como rede: mesmo resultado, sem contar duas vezes.
CREATE OR REPLACE FUNCTION public.cleaning_plan_webhook_payment(
  p_charge_id uuid, p_event text, p_payment_intent_id text, p_amount_cents integer DEFAULT NULL,
  p_receipt_url text DEFAULT NULL, p_error text DEFAULT NULL)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $$
DECLARE c cleaning_plan_charges;
BEGIN
  SELECT * INTO c FROM cleaning_plan_charges WHERE id = p_charge_id;
  IF c.id IS NULL THEN RETURN jsonb_build_object('ok', false, 'erro', 'charge_not_found'); END IF;
  IF c.status = 'succeeded' THEN RETURN jsonb_build_object('ok', true, 'status', 'succeeded', 'already', true); END IF;
  IF c.stripe_payment_intent_id IS NOT NULL AND c.stripe_payment_intent_id <> p_payment_intent_id THEN
    -- PaymentIntent de uma tentativa antiga: só o sucesso conta (e paga a cobrança)
    IF p_event <> 'succeeded' THEN RETURN jsonb_build_object('ok', true, 'ignored', 'pi_antigo'); END IF;
  END IF;
  IF p_event = 'succeeded' THEN
    IF p_amount_cents IS NOT NULL AND p_amount_cents <> c.amount_cents THEN
      PERFORM public.notify_admin_urgent_push('cleaning_plan_valor_diferente',
        '💳 PLANO DE LIMPEZA — a Stripe cobrou ' || public._cleaning_plan_euro(p_amount_cents) || ' e a cobrança é de '
        || public._cleaning_plan_euro(c.amount_cents) || '. Ver ' || p_payment_intent_id,
        'cleaning_plan_charges', c.id::text, jsonb_build_object('charge_id', c.id, 'pi', p_payment_intent_id), '/admin/limpeza/planos');
    END IF;
    PERFORM public._cleaning_plan_marcar_pago(c.id, p_payment_intent_id, p_receipt_url, NULL);
    RETURN jsonb_build_object('ok', true, 'status', 'succeeded');
  ELSIF p_event = 'requires_action' THEN
    IF c.status IN ('processing','pending') THEN
      RETURN public.cleaning_plan_charge_result(c.id, c.attempts, 'requires_action', p_payment_intent_id, NULL, NULL, p_error);
    END IF;
  ELSIF p_event = 'failed' THEN
    IF c.status IN ('processing','requires_action') THEN
      RETURN public.cleaning_plan_charge_result(c.id, c.attempts, 'card_error', p_payment_intent_id, NULL, NULL,
                                                COALESCE(p_error, 'pagamento falhou'));
    END IF;
  END IF;
  RETURN jsonb_build_object('ok', true, 'status', c.status, 'sem_mudanca', true);
END $$;

-- Para o 3D Secure: a cobrança do cliente que o banco pediu para confirmar.
CREATE OR REPLACE FUNCTION public.cleaning_plan_action_charge(p_charge_id uuid, p_user_id uuid)
RETURNS jsonb LANGUAGE sql STABLE SECURITY DEFINER SET search_path TO 'public' AS $$
  SELECT jsonb_build_object('charge_id', c.id, 'status', c.status, 'attempt', c.attempts,
                            'payment_intent_id', c.stripe_payment_intent_id, 'amount_cents', c.amount_cents,
                            'plan_status', p.status)
    FROM cleaning_plan_charges c JOIN cleaning_plans p ON p.id = c.plan_id
   WHERE c.id = p_charge_id AND c.client_user_id = p_user_id;
$$;

-- Devoluções ao cartão por fazer (até 5 tentativas; depois alerta ao admin).
CREATE OR REPLACE FUNCTION public.cleaning_plan_refunds_due(p_limit integer DEFAULT 25)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $$
DECLARE r record; v_out jsonb := '[]'::jsonb;
BEGIN
  FOR r IN SELECT f.*, c.stripe_payment_intent_id
             FROM cleaning_plan_refunds f JOIN cleaning_plan_charges c ON c.id = f.charge_id
            WHERE f.method = 'card' AND c.stripe_payment_intent_id IS NOT NULL
              AND ((f.status IN ('pending','failed') AND COALESCE(f.next_attempt_at, now()) <= now())
                OR (f.status = 'processing' AND f.updated_at < now() - interval '15 minutes'))
            ORDER BY f.created_at
            LIMIT GREATEST(1, LEAST(COALESCE(p_limit, 25), 100))
            FOR UPDATE OF f SKIP LOCKED
  LOOP
    UPDATE cleaning_plan_refunds SET status = 'processing',
           attempts = CASE WHEN r.status = 'processing' THEN attempts ELSE attempts + 1 END, updated_at = now()
     WHERE id = r.id;
    v_out := v_out || jsonb_build_object('refund_id', r.id, 'payment_intent_id', r.stripe_payment_intent_id,
      'amount_cents', r.amount_cents, 'booking_id', r.booking_id, 'charge_id', r.charge_id,
      'stripe_idempotency_key', 'cleaning-plan-refund-' || r.id);
  END LOOP;
  RETURN v_out;
END $$;

CREATE OR REPLACE FUNCTION public.cleaning_plan_refund_result(p_refund_id uuid, p_ok boolean,
                                                              p_stripe_refund_id text DEFAULT NULL, p_error text DEFAULT NULL)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $$
DECLARE f cleaning_plan_refunds;
BEGIN
  SELECT * INTO f FROM cleaning_plan_refunds WHERE id = p_refund_id FOR UPDATE;
  IF f.id IS NULL THEN RAISE EXCEPTION 'refund_not_found'; END IF;
  IF f.status = 'succeeded' THEN RETURN jsonb_build_object('ok', true, 'already', true); END IF;
  IF p_ok THEN
    UPDATE cleaning_plan_refunds SET status = 'succeeded', stripe_refund_id = p_stripe_refund_id, done_at = now(),
           last_error = NULL, updated_at = now()
     WHERE id = f.id;
    PERFORM public._cleaning_notify_user(f.client_user_id, 'cleaning_plan_refund', 'Devolução feita',
      'Devolvemos ' || public._cleaning_plan_euro(f.amount_cents) || ' ao teu cartão (pode demorar 5 a 10 dias).',
      f.booking_id::text);
    RETURN jsonb_build_object('ok', true, 'status', 'succeeded');
  END IF;
  UPDATE cleaning_plan_refunds
     SET status = CASE WHEN attempts >= 5 THEN 'failed_final' ELSE 'failed' END,
         next_attempt_at = now() + make_interval(hours => LEAST(attempts, 5)),
         last_error = left(COALESCE(p_error, 'erro'), 500), updated_at = now()
   WHERE id = f.id;
  IF f.attempts >= 5 THEN
    BEGIN
      PERFORM public.notify_admin_urgent_push('cleaning_plan_refund_failed',
        '💸 PLANO DE LIMPEZA — devolução ao cartão falhou 5 vezes · ' || public._cleaning_plan_euro(f.amount_cents)
        || ' · ' || public._alerta_quem(f.client_user_id) || '. Devolver à mão.',
        'cleaning_plan_refunds', f.id::text, jsonb_build_object('refund_id', f.id, 'erro', p_error), '/admin/limpeza/planos');
    EXCEPTION WHEN others THEN RAISE WARNING 'cleaning_plan_refund_result: alerta falhou (%)', sqlerrm; END;
  END IF;
  RETURN jsonb_build_object('ok', true, 'status', CASE WHEN f.attempts >= 5 THEN 'failed_final' ELSE 'failed' END);
END $$;

-- ── 10. Painel admin (todas com _admin_op_guard) ─────────────────────────────

CREATE OR REPLACE FUNCTION public.admin_cleaning_plans_summary()
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path TO 'public' AS $$
DECLARE v_mes timestamptz := (date_trunc('month', now() AT TIME ZONE 'Europe/Lisbon')) AT TIME ZONE 'Europe/Lisbon';
BEGIN
  PERFORM public._admin_op_guard();
  RETURN jsonb_build_object(
    'ativos',          (SELECT count(*) FROM cleaning_plans WHERE status = 'active'),
    'ativos_casa',     (SELECT count(*) FROM cleaning_plans WHERE status = 'active' AND segment = 'casa'),
    'ativos_empresa',  (SELECT count(*) FROM cleaning_plans WHERE status = 'active' AND segment = 'empresa'),
    'pausados',        (SELECT count(*) FROM cleaning_plans WHERE status = 'paused'),
    'sem_cartao',      (SELECT count(*) FROM cleaning_plans WHERE status = 'pending_card'),
    'cancelados',      (SELECT count(*) FROM cleaning_plans WHERE status = 'cancelled'),
    'cobrado_mes_cents',   COALESCE((SELECT sum(amount_cents) FROM cleaning_plan_charges WHERE status = 'succeeded' AND paid_at >= v_mes), 0),
    'devolvido_mes_cents', COALESCE((SELECT sum(amount_cents) FROM cleaning_plan_refunds WHERE status = 'succeeded' AND done_at >= v_mes), 0),
    'cobrancas_falhadas',  (SELECT count(*) FROM cleaning_plan_charges WHERE status IN ('failed','requires_action')),
    'cobrancas_falhadas_de_vez_mes', (SELECT count(*) FROM cleaning_plan_charges WHERE status = 'failed_final' AND updated_at >= v_mes),
    'sem_profissional',    (SELECT count(*) FROM cleaning_plan_charges WHERE status = 'waiting_cleaner'),
    'devolucoes_pendentes', (SELECT count(*) FROM cleaning_plan_refunds WHERE status IN ('pending','processing')),
    'devolucoes_falhadas',  (SELECT count(*) FROM cleaning_plan_refunds WHERE status IN ('failed','failed_final')));
END $$;

-- Linha do plano para o painel (campos do plano + cliente + contas).
CREATE OR REPLACE FUNCTION public._admin_cleaning_plan_linha(p cleaning_plans)
RETURNS jsonb LANGUAGE sql STABLE SECURITY DEFINER SET search_path TO 'public' AS $$
  SELECT (to_jsonb(p) - 'stripe_payment_method_id' - 'access_instructions' - 'idempotency_key')
    || jsonb_build_object(
      'client_name',  (SELECT COALESCE(NULLIF(u.name, ''), au.raw_user_meta_data->>'name') FROM auth.users au
                        LEFT JOIN public.users u ON u.id = au.id WHERE au.id = p.client_user_id),
      'client_email', (SELECT email FROM auth.users WHERE id = p.client_user_id),
      'client_phone', (SELECT COALESCE(u.phone, au.phone) FROM auth.users au
                        LEFT JOIN public.users u ON u.id = au.id WHERE au.id = p.client_user_id),
      'label', (SELECT label_pt FROM cleaning_plan_prices pr WHERE pr.segment = p.segment AND pr.frequency = p.frequency),
      'cleaner_name', (SELECT name FROM cleaners WHERE id = p.requested_cleaner_id),
      'next_visit_at', (SELECT min(scheduled_at) FROM cleaning_bookings
                         WHERE plan_id = p.id AND team_slot = 1 AND status NOT LIKE 'cancelled%' AND scheduled_at > now()),
      'paid_cents', COALESCE((SELECT sum(amount_cents) FROM cleaning_plan_charges WHERE plan_id = p.id AND status = 'succeeded'), 0),
      'refunded_cents', COALESCE((SELECT sum(amount_cents) FROM cleaning_plan_refunds WHERE plan_id = p.id AND status = 'succeeded'), 0),
      'charges_failing', (SELECT count(*) FROM cleaning_plan_charges
                           WHERE plan_id = p.id AND status IN ('failed','requires_action','failed_final')
                             AND updated_at > now() - interval '30 days'));
$$;

CREATE OR REPLACE FUNCTION public.admin_list_cleaning_plans(p_status text DEFAULT NULL, p_segment text DEFAULT NULL,
                                                            p_search text DEFAULT NULL)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path TO 'public' AS $$
DECLARE v_q text := NULLIF(lower(btrim(COALESCE(p_search, ''))), '');
BEGIN
  PERFORM public._admin_op_guard();
  RETURN COALESCE((
    SELECT jsonb_agg(public._admin_cleaning_plan_linha(x.p) ORDER BY (x.p).created_at DESC)
      FROM (SELECT p FROM cleaning_plans p
             LEFT JOIN auth.users au ON au.id = p.client_user_id
             LEFT JOIN public.users u ON u.id = p.client_user_id
             WHERE (p_status IS NULL OR p.status = p_status)
               AND (p_segment IS NULL OR p.segment = p_segment)
               AND (v_q IS NULL OR lower(concat_ws(' ', u.name, au.email, au.phone, u.phone, p.company_name,
                                                   p.billing_nif, p.address_street, p.address_city, p.address_postal))
                                   LIKE '%' || v_q || '%')
             ORDER BY p.created_at DESC LIMIT 300) x), '[]'::jsonb);
END $$;

CREATE OR REPLACE FUNCTION public.admin_cleaning_plan_detail(p_plan_id uuid)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path TO 'public' AS $$
DECLARE p cleaning_plans;
BEGIN
  PERFORM public._admin_op_guard();
  SELECT * INTO p FROM cleaning_plans WHERE id = p_plan_id;
  IF p.id IS NULL THEN RAISE EXCEPTION 'plan_not_found'; END IF;
  RETURN public._cleaning_plan_json(p.id) || public._admin_cleaning_plan_linha(p) || jsonb_build_object(
    'client', jsonb_build_object(
      'name',  (SELECT COALESCE(NULLIF(u.name, ''), au.raw_user_meta_data->>'name') FROM auth.users au
                 LEFT JOIN public.users u ON u.id = au.id WHERE au.id = p.client_user_id),
      'email', (SELECT email FROM auth.users WHERE id = p.client_user_id),
      'phone', (SELECT COALESCE(u.phone, au.phone) FROM auth.users au LEFT JOIN public.users u ON u.id = au.id
                 WHERE au.id = p.client_user_id)),
    'stripe_customer_id', p.stripe_customer_id, 'stripe_account', p.stripe_account,
    'pro_cents_per_hour', p.pro_cents_per_hour, 'billing_nif', p.billing_nif, 'billing_email', p.billing_email,
    'space_type', p.space_type, 'area_m2', p.area_m2, 'tasks', to_jsonb(p.tasks),
    'address_city', p.address_city, 'address_postal', p.address_postal,
    'all_visits', COALESCE((SELECT jsonb_agg(jsonb_build_object(
        'booking_id', b.id, 'slot', b.team_slot, 'date', b.plan_visit_date, 'scheduled_at', b.scheduled_at,
        'status', b.status, 'payment_status', b.payment_status, 'total_cents', b.total_cents,
        'share_cents', b.share_cents, 'cleaner_earnings_cents', b.cleaner_earnings_cents,
        'bora_fee_cents', b.bora_fee_cents, 'cancel_reason', b.cancel_reason,
        'cleaner_name', (SELECT name FROM cleaners WHERE id = b.cleaner_id))
        ORDER BY b.scheduled_at DESC, b.team_slot)
      FROM cleaning_bookings b WHERE b.plan_id = p.id), '[]'::jsonb),
    'all_charges', COALESCE((SELECT jsonb_agg(to_jsonb(c) ORDER BY c.created_at DESC)
      FROM cleaning_plan_charges c WHERE c.plan_id = p.id), '[]'::jsonb),
    'all_refunds', COALESCE((SELECT jsonb_agg(to_jsonb(f) ORDER BY f.created_at DESC)
      FROM cleaning_plan_refunds f WHERE f.plan_id = p.id), '[]'::jsonb),
    'audit', COALESCE((SELECT jsonb_agg(jsonb_build_object('at', a.created_at, 'action', a.action,
                         'admin_email', a.admin_email, 'details', a.details) ORDER BY a.created_at DESC)
      FROM admin_audit_log a WHERE a.entity_type = 'cleaning_plans' AND a.entity_id = p.id), '[]'::jsonb));
END $$;

CREATE OR REPLACE FUNCTION public.admin_list_cleaning_plan_charges(p_status text DEFAULT NULL)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path TO 'public' AS $$
BEGIN
  PERFORM public._admin_op_guard();
  RETURN COALESCE((
    SELECT jsonb_agg(jsonb_build_object(
             'id', c.id, 'plan_id', c.plan_id, 'kind', c.kind, 'amount_cents', c.amount_cents, 'status', c.status,
             'created_at', c.created_at, 'charge_after', c.charge_after, 'paid_at', c.paid_at,
             'attempts', c.attempts, 'last_error', c.last_error,
             'stripe_payment_intent_id', c.stripe_payment_intent_id,
             'client_name', (SELECT COALESCE(NULLIF(u.name, ''), au.raw_user_meta_data->>'name') FROM auth.users au
                              LEFT JOIN public.users u ON u.id = au.id WHERE au.id = c.client_user_id),
             'client_email', (SELECT email FROM auth.users WHERE id = c.client_user_id),
             'segment', p.segment, 'company_name', p.company_name,
             'refunded_cents', COALESCE((SELECT sum(amount_cents) FROM cleaning_plan_refunds f
                                          WHERE f.charge_id = c.id AND f.status = 'succeeded'), 0),
             'visits', COALESCE((SELECT jsonb_agg(jsonb_build_object('booking_id', i.booking_id, 'amount_cents', i.amount_cents))
                                   FROM cleaning_plan_charge_items i WHERE i.charge_id = c.id), '[]'::jsonb))
           ORDER BY c.created_at DESC)
      FROM (SELECT * FROM cleaning_plan_charges WHERE p_status IS NULL OR status = p_status
             ORDER BY created_at DESC LIMIT 300) c
      JOIN cleaning_plans p ON p.id = c.plan_id), '[]'::jsonb);
END $$;

-- Pausar / retomar / cancelar pelo painel (motivo obrigatório, auditado). Pausar ou cancelar
-- desmarca as visitas a mais de 24 h; as já pagas voltam ao CARTÃO; o cliente é avisado.
CREATE OR REPLACE FUNCTION public.admin_cleaning_plan_set_status(p_plan_id uuid, p_status text, p_motivo text)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $$
DECLARE g record; p cleaning_plans; r record; v_n int := 0;
BEGIN
  SELECT * INTO g FROM public._admin_op_guard();
  IF COALESCE(btrim(p_motivo), '') = '' THEN RAISE EXCEPTION 'motivo_obrigatorio'; END IF;
  IF p_status NOT IN ('active','paused','cancelled') THEN RAISE EXCEPTION 'estado_invalido: %', p_status; END IF;
  SELECT * INTO p FROM cleaning_plans WHERE id = p_plan_id FOR UPDATE;
  IF p.id IS NULL THEN RAISE EXCEPTION 'plan_not_found'; END IF;
  IF p.status IN ('cancelled','completed') THEN RAISE EXCEPTION 'plan_closed: %', p.status; END IF;
  IF p_status = 'active' AND p.status <> 'paused' THEN RAISE EXCEPTION 'so_retoma_planos_em_pausa'; END IF;
  IF p_status = 'paused' AND p.status <> 'active' THEN RAISE EXCEPTION 'so_pausa_planos_ativos'; END IF;

  UPDATE cleaning_plans
     SET status = p_status,
         paused_at = CASE WHEN p_status = 'paused' THEN now() WHEN p_status = 'active' THEN NULL ELSE paused_at END,
         cancelled_at = CASE WHEN p_status = 'cancelled' THEN now() ELSE cancelled_at END,
         cancelled_by = CASE WHEN p_status = 'cancelled' THEN 'admin' ELSE cancelled_by END,
         cancel_reason = CASE WHEN p_status = 'cancelled' THEN btrim(p_motivo) ELSE cancel_reason END,
         updated_at = now()
   WHERE id = p.id;

  IF p_status IN ('paused','cancelled') THEN
    FOR r IN SELECT id FROM cleaning_bookings
              WHERE plan_id = p.id AND team_slot = 1 AND status IN ('scheduled','accepted')
                AND scheduled_at > now() + interval '24 hours'
    LOOP
      BEGIN
        IF public._cleaning_plan_cancel_visit(r.id, 'admin',
             CASE WHEN p_status = 'paused' THEN 'plano_pausado_admin' ELSE 'plano_cancelado_admin' END) THEN
          v_n := v_n + 1;
        END IF;
      EXCEPTION WHEN others THEN
        RAISE WARNING 'admin_cleaning_plan_set_status: visita % saltada (%)', r.id, sqlerrm;
      END;
    END LOOP;
    PERFORM public._cleaning_notify_user(p.client_user_id, 'cleaning_plan_status',
      CASE WHEN p_status = 'paused' THEN 'Plano em pausa' ELSE 'Plano cancelado' END,
      CASE WHEN p_status = 'paused' THEN 'O teu plano de limpeza ficou em pausa. ' ELSE 'O teu plano de limpeza foi cancelado. ' END
      || 'As limpezas a mais de 24 h foram desmarcadas; o que já pagaste por elas volta ao teu cartão (pode demorar 5 a 10 dias).',
      NULL);
  ELSE
    v_n := public._cleaning_plan_gerar_visitas(p.id);
    PERFORM public._cleaning_notify_user(p.client_user_id, 'cleaning_plan_status', 'Plano retomado',
      'O teu plano de limpeza voltou. Cobramos cada limpeza 24 h antes, e só com a profissional confirmada.', NULL);
  END IF;

  INSERT INTO admin_audit_log (admin_id, admin_email, action, entity_type, entity_id, details)
  VALUES (g.admin_id, g.admin_email, 'cleaning_plan_set_status', 'cleaning_plans', p.id,
          jsonb_build_object('antes', p.status, 'depois', p_status, 'motivo', btrim(p_motivo), 'visitas', v_n));
  RETURN public._cleaning_plan_json(p.id);
END $$;

-- ── 11. Permissões das funções (nascem fechadas a anon) ──────────────────────
DO $g$
DECLARE f text;
BEGIN
  FOREACH f IN ARRAY ARRAY[
    'public._cleaning_plan_dias_ok(text, integer[])',
    'public._cleaning_plan_hora(text)',
    'public._cleaning_plan_visitas_mes(text, integer)',
    'public._cleaning_plan_vaga(public.cleaning_plans, integer)',
    'public._cleaning_plan_visita_confirmada(uuid)',
    'public._cleaning_plan_pago(uuid)',
    'public._cleaning_plan_euro(integer)',
    'public._cleaning_plan_quando(timestamptz)',
    'public._cleaning_plan_json(uuid)',
    'public._cleaning_plan_cancel_visit(uuid, text, text)',
    'public._cleaning_plan_soltar_da_cobranca(uuid)',
    'public._cleaning_plan_devolver(uuid, text, text, integer)',
    'public._trg_cleaning_plan_visita_caiu()',
    'public._trg_cleaning_plan_profissional_fixa()',
    'public._cleaning_plan_gerar_visitas(uuid)',
    'public.cleaning_plan_generate()',
    'public._cleaning_plan_do_cliente(uuid, text[])',
    'public._cleaning_plan_refazer(uuid, text)',
    'public.cleaning_plan_card_saved(uuid, uuid, text, text, text, text, integer, integer)',
    'public._cleaning_plan_marcar_pago(uuid, text, text, text)',
    'public._cleaning_plan_arrumar()',
    'public.cleaning_plan_charges_due(integer)',
    'public.cleaning_plan_charge_result(uuid, integer, text, text, text, text, text)',
    'public.cleaning_plan_webhook_payment(uuid, text, text, integer, text, text)',
    'public.cleaning_plan_action_charge(uuid, uuid)',
    'public.cleaning_plan_refunds_due(integer)',
    'public.cleaning_plan_refund_result(uuid, boolean, text, text)',
    'public._admin_cleaning_plan_linha(public.cleaning_plans)',
    -- as da app (abertas a authenticated logo abaixo)
    'public.cleaning_plan_create(text, text, integer, integer[], text, date, integer, text, text, text, text, text, text, double precision, double precision, text, text, text, text, text, integer, text[], text, text)',
    'public.cleaning_plan_mine()',
    'public.cleaning_plan_skip(uuid, date)',
    'public.cleaning_plan_change_schedule(uuid, integer[], text)',
    'public.cleaning_plan_change_hours(uuid, integer)',
    'public.cleaning_plan_cancel(uuid, text)',
    'public.cleaning_plan_visit_info(uuid)',
    'public.admin_cleaning_plans_summary()',
    'public.admin_list_cleaning_plans(text, text, text)',
    'public.admin_cleaning_plan_detail(uuid)',
    'public.admin_list_cleaning_plan_charges(text)',
    'public.admin_cleaning_plan_set_status(uuid, text, text)']
  LOOP
    EXECUTE format('REVOKE ALL ON FUNCTION %s FROM PUBLIC, anon', f);
    EXECUTE format('GRANT EXECUTE ON FUNCTION %s TO service_role', f);
  END LOOP;
END $g$;

GRANT EXECUTE ON FUNCTION
  public.cleaning_plan_create(text, text, integer, integer[], text, date, integer, text, text, text, text, text, text, double precision, double precision, text, text, text, text, text, integer, text[], text, text),
  public.cleaning_plan_mine(),
  public.cleaning_plan_skip(uuid, date),
  public.cleaning_plan_change_schedule(uuid, integer[], text),
  public.cleaning_plan_change_hours(uuid, integer),
  public.cleaning_plan_cancel(uuid, text),
  public.cleaning_plan_visit_info(uuid),
  public.admin_cleaning_plans_summary(),
  public.admin_list_cleaning_plans(text, text, text),
  public.admin_cleaning_plan_detail(uuid),
  public.admin_list_cleaning_plan_charges(text),
  public.admin_cleaning_plan_set_status(uuid, text, text)
TO authenticated;
-- _cleaning_next_offer continua com as permissões que já tinha (create or replace não as muda).

-- ── 12. Agendamentos ────────────────────────────────────────────────────────
-- Chama a Edge cleaning-plan-charge com a chave do cofre (como os outros robôs da limpeza).
CREATE OR REPLACE FUNCTION public._cleaning_plan_chamar_cobranca()
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $$
BEGIN
  PERFORM net.http_post(
    url := (SELECT decrypted_secret FROM vault.decrypted_secrets WHERE name = 'project_url') || '/functions/v1/cleaning-plan-charge',
    headers := jsonb_build_object(
      'Authorization', 'Bearer ' || (SELECT decrypted_secret FROM vault.decrypted_secrets WHERE name = 'service_role_key'),
      'Content-Type', 'application/json'),
    body := '{}'::jsonb,
    timeout_milliseconds := 120000);
END $$;
REVOKE ALL ON FUNCTION public._cleaning_plan_chamar_cobranca() FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public._cleaning_plan_chamar_cobranca() TO service_role;

SELECT cron.schedule('cleaning-plan-generate', '10 7 * * *', 'SELECT public.cleaning_plan_generate();');
SELECT cron.schedule('cleaning-plan-charge', '3,33 * * * *', 'SELECT public._cleaning_plan_chamar_cobranca();');
