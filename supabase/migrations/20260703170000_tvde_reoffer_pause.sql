-- ─────────────────────────────────────────────────────────────────────────────
-- TVDE — Item E (afinação UX pedida pelo Danilo): re-oferecer COM PAUSA.
--
-- Decisão do Danilo (device real): ao expirar OU recusar sendo o único motorista,
-- a oferta deve voltar — mas com uma PAUSA (~30-45s), não a cada sweep (15s). A
-- re-oferta agressiva (150000/160000) parecia spam e, pior, não deixava o ecrã
-- de oferta fechar → contagem presa em "0 s" (o "travou").
--
-- Correção: o 2.º loop do sweep só faz o NOVO ROUND (limpa tried_driver_ids)
-- quando já passou `tvde_reoffer_pause_seconds` desde que ficou sem motorista
-- (no_driver_since). Durante a pausa NÃO há oferta ativa → o ecrã fecha limpo e
-- reabre fresco no re-offer. Continua a chamar offer_to_next para a janela de
-- 120s ainda decidir 'sem_motorista' quando não há motorista NENHUM (offline).
--
-- Recusa e expiração convergem no mesmo caminho (retry-window) → a pausa aplica-se
-- a ambos, como pedido ("voltar após uma pausa" nos dois casos).
-- ─────────────────────────────────────────────────────────────────────────────

INSERT INTO public.platform_settings (key, value, description, category)
VALUES ('tvde_reoffer_pause_seconds', '35',
        'TVDE: pausa (s) entre re-ofertas ao mesmo motorista quando é o único', 'tvde')
ON CONFLICT (key) DO NOTHING;

CREATE OR REPLACE FUNCTION public.tvde_dispatch_sweep()
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  r record;
  v_pause INT := COALESCE((public.get_setting('tvde_reoffer_pause_seconds') #>> '{}')::int, 35);
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

  -- [Item E] LOOP 2: corridas em ESPERA → re-oferece COM PAUSA. Só começa novo
  -- round (limpa tried) quando já passou v_pause desde no_driver_since. Chama
  -- sempre offer_to_next (mantém a janela de 120s p/ 'sem_motorista' se offline).
  FOR r IN
    SELECT id, no_driver_since FROM public.tvde_rides
    WHERE status='solicitada' AND current_offer_driver_id IS NULL
      AND no_driver_since IS NOT NULL
  LOOP
    IF now() - r.no_driver_since >= make_interval(secs => v_pause) THEN
      UPDATE public.tvde_rides SET tried_driver_ids = '{}' WHERE id = r.id;
    END IF;
    PERFORM public.tvde_offer_to_next(r.id);
  END LOOP;
END; $function$;
