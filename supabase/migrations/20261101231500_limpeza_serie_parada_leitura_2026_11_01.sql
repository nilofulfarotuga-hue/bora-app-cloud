-- Missão app-fechar-2026-11-01 · B5 série de limpeza (achado S1 de
-- docs/propostas/revisao-casa-peso-convidado-2026-11-01.md).
--
-- cleaning_recurrence_stops tinha RLS ligada e 0 políticas: ninguém a lia, e a app não sabia
-- se a série estava parada. Passa a poder ler a linha da série o próprio cliente e a
-- profissional da série (atribuída, pedida ou com oferta). A escrita continua só pela
-- função cancel_cleaning_series (SECURITY DEFINER): tiram-se as permissões de escrita
-- diretas a anon/authenticated e a leitura a anon. Não mexe em valores nem em dinheiro.

REVOKE INSERT, UPDATE, DELETE, TRUNCATE, REFERENCES, TRIGGER ON public.cleaning_recurrence_stops FROM anon, authenticated;
REVOKE SELECT ON public.cleaning_recurrence_stops FROM anon;
GRANT SELECT ON public.cleaning_recurrence_stops TO authenticated;

DROP POLICY IF EXISTS cleaning_recurrence_stops_ler_participantes ON public.cleaning_recurrence_stops;
CREATE POLICY cleaning_recurrence_stops_ler_participantes
  ON public.cleaning_recurrence_stops
  FOR SELECT TO authenticated
  USING (
    EXISTS (
      SELECT 1 FROM public.cleaning_bookings b
       WHERE b.recurrence_group_id = cleaning_recurrence_stops.group_id
         AND (
           b.client_user_id = auth.uid()
           OR EXISTS (
             SELECT 1 FROM public.cleaners c
              WHERE c.user_id = auth.uid()
                AND c.id IN (b.cleaner_id, b.requested_cleaner_id, b.offer_cleaner_id)
           )
         )
    )
  );
