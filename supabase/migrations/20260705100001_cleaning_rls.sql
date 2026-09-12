-- ============================================================================
-- LIMPEZA — RLS completo
-- Cliente vê só as suas reservas; profissional só as dela (incl. ofertas
-- pendentes); escrita SÓ via RPCs SECURITY DEFINER; admin via RPCs com
-- _admin_op_guard (padrão existente). Perfis públicos de profissionais são
-- expostos apenas pela RPC cleaning_list_available_cleaners (sem NIF/phone).
-- (Policies criadas de forma idempotente, sem statements destrutivos.)
-- ============================================================================

ALTER TABLE public.cleaners             ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.cleaner_availability ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.cleaning_bookings    ENABLE ROW LEVEL SECURITY;

-- ---------- cleaners: a própria vê o seu registo ----------
DO $$
BEGIN
  BEGIN
    CREATE POLICY cleaners_select_own ON public.cleaners
      FOR SELECT TO authenticated
      USING (user_id = auth.uid());
  EXCEPTION WHEN duplicate_object THEN NULL;
  END;
END $$;

-- (sem INSERT/UPDATE/DELETE diretos — tudo via RPCs)

-- ---------- cleaner_availability: a própria vê as suas janelas ----------
DO $$
BEGIN
  BEGIN
    CREATE POLICY cleaner_availability_own ON public.cleaner_availability
      FOR SELECT TO authenticated
      USING (cleaner_id IN (SELECT id FROM public.cleaners WHERE user_id = auth.uid()));
  EXCEPTION WHEN duplicate_object THEN NULL;
  END;
END $$;

-- ---------- cleaning_bookings ----------
-- Cliente vê as suas; profissional vê as dela (atribuídas OU com oferta ativa p/ ela)
DO $$
BEGIN
  BEGIN
    CREATE POLICY cleaning_bookings_select_own ON public.cleaning_bookings
      FOR SELECT TO authenticated
      USING (
        client_user_id = auth.uid()
        OR cleaner_id       IN (SELECT id FROM public.cleaners WHERE user_id = auth.uid())
        OR offer_cleaner_id IN (SELECT id FROM public.cleaners WHERE user_id = auth.uid())
      );
  EXCEPTION WHEN duplicate_object THEN NULL;
  END;
END $$;

-- (sem INSERT/UPDATE/DELETE diretos — preço e transições só server-side via RPC)
