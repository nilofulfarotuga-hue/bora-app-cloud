-- 2026-09-20 — CONTAS CLARAS · Bloco 1 — UMA VERDADE SÓ na carteira.
--
-- Regra que fica: o saldo (client_wallets.free_balance_cents) é SEMPRE a soma do
-- histórico (wallet_transactions), excluindo as linhas que não são saldo livre
-- (hoje só 'refund_credit_tokens', que é o valor dos tokens dados, não dinheiro).
--
-- Desenho escolhido: "saldo calculado do histórico", garantido por gatilhos na
-- própria tabela do histórico — e não pela reescrita das catorze funções que lá
-- escrevem. Porquê:
--   1. Cobre TODAS as funções, presentes e futuras, por construção. Uma função que
--      insira no histórico sem tocar no saldo (foi o caso do talão pago pelo admin)
--      fica certa sem ninguém lhe mexer.
--   2. Várias dessas funções estão na zona vermelha e a Trava recusa reescrevê-las.
--      Um gatilho aditivo é o caminho previsto no PADRAO_BORA §6 ("alternativas aditivas").
--   3. O gatilho de sincronização é DIFERIDO (corre no commit): não interessa se a
--      função actualiza o saldo antes ou depois de inserir a linha — no fim, a soma do
--      histórico é a que fica. Sem contagens a dobrar.
--
-- Peças:
--   a) wallet_kinds_fora_do_saldo()      — a lista dos tipos que não contam para o saldo.
--   b) wallet_recompute_balance(uid)     — recalcula o saldo de uma pessoa a partir do histórico.
--   c) _wallet_tx_before_insert()        — BEFORE INSERT: preenche balance_after_cents com a
--                                          soma do histórico (a "terceira verdade" passa a ser
--                                          sempre igual às outras duas).
--   d) _wallet_tx_sync_balance()         — AFTER INSERT, diferido ao commit: saldo = soma.
--   e) _wallet_tx_append_only()          — BEFORE UPDATE/DELETE: o histórico só se acrescenta;
--                                          corrige-se com linha nova de estorno, com motivo.
--   f) backfill: recalcula quem já bate (sem efeito) e NÃO toca em quem diverge — o único
--      caso é a Isabel Rebelo (fechado pelo Danilo a 20/09); fica registado como achado.
--
-- Prova: bloco DO em rollback com SET CONSTRAINTS ALL IMMEDIATE (ver
-- .claude/.ai/provas/contas-claras-20260920/bloco1-prova.sql).

-- a) tipos que não são saldo livre ------------------------------------------------
CREATE OR REPLACE FUNCTION public.wallet_kinds_fora_do_saldo()
RETURNS text[]
LANGUAGE sql IMMUTABLE PARALLEL SAFE
AS $$ SELECT ARRAY['refund_credit_tokens']::text[] $$;

COMMENT ON FUNCTION public.wallet_kinds_fora_do_saldo() IS
  'Contas claras (20/09/2026): tipos de wallet_transactions que NÃO entram no saldo livre. refund_credit_tokens é o valor em cêntimos dos tokens dados; os tokens vivem em bora_tokens.';

-- b) recalcular o saldo de uma pessoa a partir do histórico -------------------------
CREATE OR REPLACE FUNCTION public.wallet_recompute_balance(p_user_id uuid)
RETURNS integer
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_sum integer;
BEGIN
  IF p_user_id IS NULL THEN RETURN NULL; END IF;
  SELECT COALESCE(SUM(amount_cents), 0)::int INTO v_sum
    FROM public.wallet_transactions
   WHERE user_id = p_user_id
     AND kind <> ALL (public.wallet_kinds_fora_do_saldo());
  INSERT INTO public.client_wallets (user_id, free_balance_cents, updated_at)
  VALUES (p_user_id, v_sum, now())
  ON CONFLICT (user_id) DO UPDATE
    SET free_balance_cents = EXCLUDED.free_balance_cents,
        updated_at         = now()
    WHERE public.client_wallets.free_balance_cents IS DISTINCT FROM EXCLUDED.free_balance_cents;
  RETURN v_sum;
END;
$$;

REVOKE ALL ON FUNCTION public.wallet_recompute_balance(uuid) FROM PUBLIC, anon, authenticated;

COMMENT ON FUNCTION public.wallet_recompute_balance(uuid) IS
  'Contas claras (20/09/2026): saldo = soma do histórico (sem os tipos fora do saldo). Só o servidor a chama (gatilhos e manutenção).';

-- c) BEFORE INSERT: balance_after_cents vem sempre do histórico ---------------------
CREATE OR REPLACE FUNCTION public._wallet_tx_before_insert()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_prev integer;
BEGIN
  -- garante a linha da carteira e tranca-a: duas escritas na mesma pessoa ficam em fila
  INSERT INTO public.client_wallets (user_id, free_balance_cents, updated_at)
  VALUES (NEW.user_id, 0, now())
  ON CONFLICT (user_id) DO NOTHING;
  PERFORM 1 FROM public.client_wallets WHERE user_id = NEW.user_id FOR UPDATE;

  SELECT COALESCE(SUM(amount_cents), 0)::int INTO v_prev
    FROM public.wallet_transactions
   WHERE user_id = NEW.user_id
     AND kind <> ALL (public.wallet_kinds_fora_do_saldo());

  NEW.balance_after_cents := v_prev
    + CASE WHEN NEW.kind = ANY (public.wallet_kinds_fora_do_saldo()) THEN 0 ELSE NEW.amount_cents END;
  RETURN NEW;
END;
$$;

-- d) AFTER INSERT, diferido: no commit o saldo passa a ser a soma do histórico -------
CREATE OR REPLACE FUNCTION public._wallet_tx_sync_balance()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  PERFORM public.wallet_recompute_balance(NEW.user_id);
  RETURN NULL;
END;
$$;

-- e) o histórico só se acrescenta -------------------------------------------------
CREATE OR REPLACE FUNCTION public._wallet_tx_append_only()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
  -- válvula de manutenção, só para o servidor: SET LOCAL bora.wallet_tx_manutencao = 'on'
  IF COALESCE(current_setting('bora.wallet_tx_manutencao', true), '') = 'on' THEN
    RETURN COALESCE(NEW, OLD);
  END IF;
  RAISE EXCEPTION 'wallet_transactions é só de acrescentar: corrige-se com uma linha nova de estorno, com o motivo escrito'
    USING ERRCODE = '55000';
END;
$$;

DO $do$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_trigger WHERE tgname = 'trg_wallet_tx_aa_before_insert' AND tgrelid = 'public.wallet_transactions'::regclass) THEN
    EXECUTE 'CREATE TRIGGER trg_wallet_tx_aa_before_insert BEFORE INSERT ON public.wallet_transactions FOR EACH ROW EXECUTE FUNCTION public._wallet_tx_before_insert()';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_trigger WHERE tgname = 'trg_wallet_tx_zz_sync_balance' AND tgrelid = 'public.wallet_transactions'::regclass) THEN
    EXECUTE 'CREATE CONSTRAINT TRIGGER trg_wallet_tx_zz_sync_balance AFTER INSERT ON public.wallet_transactions DEFERRABLE INITIALLY DEFERRED FOR EACH ROW EXECUTE FUNCTION public._wallet_tx_sync_balance()';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_trigger WHERE tgname = 'trg_wallet_tx_append_only' AND tgrelid = 'public.wallet_transactions'::regclass) THEN
    EXECUTE 'CREATE TRIGGER trg_wallet_tx_append_only BEFORE UPDATE OR DELETE ON public.wallet_transactions FOR EACH ROW EXECUTE FUNCTION public._wallet_tx_append_only()';
  END IF;
END
$do$;

-- f) backfill: só quem já bate (efeito zero) — quem diverge fica como achado ---------
-- Único caso que diverge a 20/09/2026: 4abf0e49-d44b-4356-9e17-9126f5988581 (Isabel
-- Rebelo, histórico 409 contra saldo 100). Caso FECHADO pelo Danilo: não se mexe.
-- Fica registado em payment_reconciliation_findings para o vigia não o repetir todos os dias.
DO $do$
DECLARE
  r record;
  v_hist integer;
BEGIN
  FOR r IN SELECT DISTINCT user_id FROM public.wallet_transactions LOOP
    SELECT COALESCE(SUM(amount_cents), 0)::int INTO v_hist
      FROM public.wallet_transactions
     WHERE user_id = r.user_id AND kind <> ALL (public.wallet_kinds_fora_do_saldo());
    IF v_hist = COALESCE((SELECT free_balance_cents FROM public.client_wallets WHERE user_id = r.user_id), 0) THEN
      PERFORM public.wallet_recompute_balance(r.user_id);  -- garante a linha; valor não muda
    ELSE
      INSERT INTO public.payment_reconciliation_findings (kind, severity, entity_type, entity_id, pi_id, amount_cents, details)
      VALUES ('saldo_vs_historico', 'warning', 'wallet', r.user_id::text, 'wallet:' || r.user_id::text,
              v_hist - COALESCE((SELECT free_balance_cents FROM public.client_wallets WHERE user_id = r.user_id), 0),
              jsonb_build_object('historico_cents', v_hist,
                                 'saldo_cents', (SELECT free_balance_cents FROM public.client_wallets WHERE user_id = r.user_id),
                                 'origem', 'contas-claras b1 backfill 20/09/2026',
                                 'nota', 'divergência anterior ao gatilho; não corrigida automaticamente'))
      ON CONFLICT (kind, pi_id, entity_id) DO NOTHING;
    END IF;
  END LOOP;
END
$do$;
