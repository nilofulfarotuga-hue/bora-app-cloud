-- ============================================================================
-- Serviços / Barbearias — RLS
-- Padrão do projeto: leitura pública dos catálogos; escrita só pelo dono do
-- provider (service_providers.user_id = auth.uid()) ou admin (public.is_admin()).
-- As RPCs de ação são SECURITY DEFINER e contornam estas policies; as policies
-- protegem o acesso direto via PostgREST.
-- ============================================================================

ALTER TABLE public.service_providers   ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.staff_members       ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.provider_services   ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.staff_availability  ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.appointments        ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.appointment_payouts ENABLE ROW LEVEL SECURITY;

-- ---------- service_providers ----------
DROP POLICY IF EXISTS sp_select ON public.service_providers;
CREATE POLICY sp_select ON public.service_providers FOR SELECT
  USING ((is_online AND approval_status = 'approved')
         OR user_id = auth.uid()
         OR public.is_admin());

DROP POLICY IF EXISTS sp_insert ON public.service_providers;
CREATE POLICY sp_insert ON public.service_providers FOR INSERT
  WITH CHECK (user_id = auth.uid() OR public.is_admin());

DROP POLICY IF EXISTS sp_update ON public.service_providers;
CREATE POLICY sp_update ON public.service_providers FOR UPDATE
  USING (user_id = auth.uid() OR public.is_admin())
  WITH CHECK (user_id = auth.uid() OR public.is_admin());

DROP POLICY IF EXISTS sp_delete ON public.service_providers;
CREATE POLICY sp_delete ON public.service_providers FOR DELETE
  USING (public.is_admin());

-- helper inline: dono do provider X?
-- (usado nas tabelas-filhas via EXISTS)

-- ---------- staff_members ----------
DROP POLICY IF EXISTS sm_select ON public.staff_members;
CREATE POLICY sm_select ON public.staff_members FOR SELECT USING (true);

DROP POLICY IF EXISTS sm_write ON public.staff_members;
CREATE POLICY sm_write ON public.staff_members FOR ALL
  USING (EXISTS (SELECT 1 FROM public.service_providers sp
                 WHERE sp.id = staff_members.provider_id
                   AND (sp.user_id = auth.uid() OR public.is_admin())))
  WITH CHECK (EXISTS (SELECT 1 FROM public.service_providers sp
                 WHERE sp.id = staff_members.provider_id
                   AND (sp.user_id = auth.uid() OR public.is_admin())));

-- ---------- provider_services ----------
DROP POLICY IF EXISTS ps_select ON public.provider_services;
CREATE POLICY ps_select ON public.provider_services FOR SELECT USING (true);

DROP POLICY IF EXISTS ps_write ON public.provider_services;
CREATE POLICY ps_write ON public.provider_services FOR ALL
  USING (EXISTS (SELECT 1 FROM public.service_providers sp
                 WHERE sp.id = provider_services.provider_id
                   AND (sp.user_id = auth.uid() OR public.is_admin())))
  WITH CHECK (EXISTS (SELECT 1 FROM public.service_providers sp
                 WHERE sp.id = provider_services.provider_id
                   AND (sp.user_id = auth.uid() OR public.is_admin())));

-- ---------- staff_availability ----------
DROP POLICY IF EXISTS sa_select ON public.staff_availability;
CREATE POLICY sa_select ON public.staff_availability FOR SELECT USING (true);

DROP POLICY IF EXISTS sa_write ON public.staff_availability;
CREATE POLICY sa_write ON public.staff_availability FOR ALL
  USING (EXISTS (SELECT 1 FROM public.staff_members sm
                 JOIN public.service_providers sp ON sp.id = sm.provider_id
                 WHERE sm.id = staff_availability.staff_id
                   AND (sp.user_id = auth.uid() OR public.is_admin())))
  WITH CHECK (EXISTS (SELECT 1 FROM public.staff_members sm
                 JOIN public.service_providers sp ON sp.id = sm.provider_id
                 WHERE sm.id = staff_availability.staff_id
                   AND (sp.user_id = auth.uid() OR public.is_admin())));

-- ---------- appointments ----------
DROP POLICY IF EXISTS ap_select ON public.appointments;
CREATE POLICY ap_select ON public.appointments FOR SELECT
  USING (client_user_id = auth.uid()
         OR EXISTS (SELECT 1 FROM public.service_providers sp
                    WHERE sp.id = appointments.provider_id
                      AND (sp.user_id = auth.uid() OR public.is_admin())));

DROP POLICY IF EXISTS ap_insert ON public.appointments;
CREATE POLICY ap_insert ON public.appointments FOR INSERT
  WITH CHECK (client_user_id = auth.uid()
         OR EXISTS (SELECT 1 FROM public.service_providers sp
                    WHERE sp.id = appointments.provider_id
                      AND (sp.user_id = auth.uid() OR public.is_admin())));

DROP POLICY IF EXISTS ap_update ON public.appointments;
CREATE POLICY ap_update ON public.appointments FOR UPDATE
  USING (client_user_id = auth.uid()
         OR EXISTS (SELECT 1 FROM public.service_providers sp
                    WHERE sp.id = appointments.provider_id
                      AND (sp.user_id = auth.uid() OR public.is_admin())))
  WITH CHECK (client_user_id = auth.uid()
         OR EXISTS (SELECT 1 FROM public.service_providers sp
                    WHERE sp.id = appointments.provider_id
                      AND (sp.user_id = auth.uid() OR public.is_admin())));

-- ---------- appointment_payouts ----------
DROP POLICY IF EXISTS apo_select ON public.appointment_payouts;
CREATE POLICY apo_select ON public.appointment_payouts FOR SELECT
  USING (EXISTS (SELECT 1 FROM public.service_providers sp
                 WHERE sp.id = appointment_payouts.provider_id
                   AND (sp.user_id = auth.uid() OR public.is_admin())));

DROP POLICY IF EXISTS apo_write ON public.appointment_payouts;
CREATE POLICY apo_write ON public.appointment_payouts FOR ALL
  USING (public.is_admin())
  WITH CHECK (public.is_admin());
