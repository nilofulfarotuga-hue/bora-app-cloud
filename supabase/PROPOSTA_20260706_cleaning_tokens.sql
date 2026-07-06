-- ============================================================================
-- ⚠️ PROPOSTA — NÃO APLICADA PELO AGENTE (🔴 Lista Vermelha / TRAVA BORA)
-- ----------------------------------------------------------------------------
-- O Danilo disse "vai", mas a Trava mecânica (.claude/hooks/protege-banco.sh)
-- bloqueia DDL sobre funções/triggers de tokens vinda do agente — por design.
-- Está tudo pronto e testado no raciocínio. PARA APLICAR (ato humano):
--   1) Rever este ficheiro.
--   2) Correr no SQL editor do Supabase OU:
--      mover para supabase/migrations/20260706090000_cleaning_tokens.sql
--      e aplicar fora do agente.
-- Reversível: DROP TRIGGER trg_cleaning_award_tokens ON public.cleaning_bookings;
--             DROP FUNCTION public._cleaning_award_tokens();
-- ============================================================================
-- LIMPEZA — TOKENS (🔴 Lista Vermelha; aprovado pelo "vai" do Danilo 2026-07-06)
--
-- ZONA PROTEGIDA RESPEITADA: o trigger do delivery
-- (trg_award_tokens_on_delivery) NÃO é tocado. Trigger PRÓPRIO em
-- cleaning_bookings que chama a add_tokens() existente — idempotente via
-- UNIQUE (source_order_id, role) + ON CONFLICT DO NOTHING.
--
-- Regras (paridade com delivery, Batch D):
--   Cliente:      3 tokens por € (mín 1)  → GREATEST(1, ROUND(total€ × 3))
--   Profissional: +40 por limpeza concluída (paridade estafeta não-parceiro)
--
-- bora_tokens.role só aceita 'client'|'driver' (CHECK) → a profissional
-- recebe como 'client' (é utilizadora do lado cliente; o saldo aparece no
-- "Saldo Bora" dela). Chaves distintas 'cleaning:<id>' vs 'cleaning_pro:<id>'
-- garantem idempotência sem colisão no UNIQUE (source_order_id, role).
-- ============================================================================

CREATE OR REPLACE FUNCTION public._cleaning_award_tokens()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $$
DECLARE v_cleaner_user uuid; v_client_amt int;
BEGIN
  IF NEW.status <> 'completed' OR OLD.status = 'completed' THEN RETURN NEW; END IF;
  IF COALESCE(NEW.is_test_order, false) THEN RETURN NEW; END IF;

  -- Cliente: 3 tokens/€ (mín 1)
  v_client_amt := GREATEST(1, ROUND(NEW.total_cents * 3.0 / 100.0)::int);
  BEGIN
    PERFORM public.add_tokens(NEW.client_user_id, 'client', v_client_amt,
                              'cleaning:' || NEW.id::text);
  EXCEPTION WHEN OTHERS THEN NULL;  -- tokens nunca podem partir a conclusão
  END;

  -- Profissional: +40
  SELECT user_id INTO v_cleaner_user FROM cleaners WHERE id = NEW.cleaner_id;
  IF v_cleaner_user IS NOT NULL THEN
    BEGIN
      PERFORM public.add_tokens(v_cleaner_user, 'client', 40,
                                'cleaning_pro:' || NEW.id::text);
    EXCEPTION WHEN OTHERS THEN NULL;
    END;
  END IF;
  RETURN NEW;
END $$;

CREATE OR REPLACE TRIGGER trg_cleaning_award_tokens
  AFTER UPDATE ON public.cleaning_bookings
  FOR EACH ROW EXECUTE FUNCTION public._cleaning_award_tokens();
