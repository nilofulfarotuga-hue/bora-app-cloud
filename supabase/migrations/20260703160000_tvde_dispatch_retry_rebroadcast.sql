-- ─────────────────────────────────────────────────────────────────────────────
-- TVDE — Item E (correção do teste de campo): re-oferecer ao ÚNICO motorista.
--
-- Bug apanhado pelo Danilo no device real (build 353), NÃO pela simulação SQL:
--   Com 1 só motorista, ao expirar/recusar a oferta ele entra em
--   `tried_driver_ids` → `tvde_offer_to_next` (Tier1) exclui-o → não há mais
--   ninguém → a corrida espera e cancela ('sem_motorista'). NUNCA volta a ele.
--
-- A migration 20260703150000 (retry-window) mantinha 'solicitada' mais tempo,
-- mas o 2.º loop do sweep re-chamava offer_to_next SEM limpar tried_driver_ids
-- → continuava a excluir o único motorista → cancelava na mesma. Falso positivo.
--
-- Correção CIRÚRGICA (só o 2.º loop do sweep; motor de matching e loop 1 intactos):
--   ao re-tentar uma corrida em espera (no_driver_since ativo), começa um NOVO
--   ROUND limpando `tried_driver_ids` → dá a TODOS (incl. o único motorista)
--   outra chance. offer_to_next volta a oferecer-lhe. Se ninguém estiver mesmo
--   online, o offer_to_next mantém no_driver_since e a janela (120s) ainda
--   decide o 'sem_motorista' — o auto-cancel só acontece sem motorista NENHUM.
-- ─────────────────────────────────────────────────────────────────────────────

CREATE OR REPLACE FUNCTION public.tvde_dispatch_sweep()
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE r record;
BEGIN
  -- LOOP 1 (intacto): ofertas ativas que expiraram → rotação normal.
  FOR r IN
    SELECT id, current_offer_driver_id FROM public.tvde_rides
    WHERE status='solicitada' AND offer_expires_at IS NOT NULL AND offer_expires_at < now()
      AND current_offer_driver_id IS NOT NULL
  LOOP
    UPDATE public.tvde_rides
       SET tried_driver_ids = array_append(tried_driver_ids, r.current_offer_driver_id),
           current_offer_driver_id = NULL, offer_expires_at = NULL, updated_at = now()
     WHERE id = r.id;
    INSERT INTO public.tvde_ride_events(ride_id,status,actor,meta)
      VALUES (r.id,'oferta_expirada','system', jsonb_build_object('driver_id', r.current_offer_driver_id));
    PERFORM public.tvde_offer_to_next(r.id);
  END LOOP;

  -- [Item E — correção] LOOP 2: corridas em ESPERA (retry-window ativo, sem
  -- oferta) → NOVO ROUND: limpa tried_driver_ids para re-oferecer a todos os
  -- motoristas elegíveis (incl. o ÚNICO que já tinha recusado/expirado). Sem
  -- isto, com 1 motorista a corrida cancelava em vez de voltar a ele.
  FOR r IN
    SELECT id FROM public.tvde_rides
    WHERE status='solicitada' AND current_offer_driver_id IS NULL
      AND no_driver_since IS NOT NULL
  LOOP
    UPDATE public.tvde_rides SET tried_driver_ids = '{}' WHERE id = r.id;
    PERFORM public.tvde_offer_to_next(r.id);
  END LOOP;
END; $function$;
