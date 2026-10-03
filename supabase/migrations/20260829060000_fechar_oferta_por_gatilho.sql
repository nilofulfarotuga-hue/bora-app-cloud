-- ============================================================================
-- FECHAR A OFERTA NO REGISTO — por gatilho, num sitio so
--
-- O registo de ofertas so vale se disser tambem como CADA uma acabou. Fechar a
-- linha teria de acontecer em seis funcoes: aceitar, recusar e tempo esgotado,
-- vezes duas categorias. Seis sitios a escrever a mesma verdade e a regra dos
-- gemeos a pedir para ser quebrada.
--
-- Por isso fecha-se onde a verdade muda: na propria tabela do pedido.
--
-- Dois desfechos, e so dois, porque so dois se conseguem provar da tabela:
--   'aceite'       — o prestador a quem estava oferecido ficou com o trabalho
--   'sem_resposta' — a oferta saiu dele sem ele ficar com o trabalho
-- Distinguir "recusou" de "deixou expirar" exigiria escrever nas seis funcoes.
-- Prefiro dois desfechos verdadeiros a quatro adivinhados.
-- ============================================================================

CREATE OR REPLACE FUNCTION public._fechar_oferta_lavagem()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $function$
BEGIN
  IF OLD.offer_washer_id IS NULL THEN RETURN NEW; END IF;
  IF NEW.washer_id IS NOT NULL AND NEW.washer_id = OLD.offer_washer_id THEN
    PERFORM public.fechar_oferta(NEW.id, OLD.offer_washer_id, 'aceite');
  ELSIF NEW.offer_washer_id IS DISTINCT FROM OLD.offer_washer_id THEN
    PERFORM public.fechar_oferta(NEW.id, OLD.offer_washer_id, 'sem_resposta');
  END IF;
  RETURN NEW;
END $function$;

DROP TRIGGER IF EXISTS trg_fechar_oferta_lavagem ON public.carwash_bookings;
CREATE TRIGGER trg_fechar_oferta_lavagem
  AFTER UPDATE OF offer_washer_id, washer_id ON public.carwash_bookings
  FOR EACH ROW EXECUTE FUNCTION public._fechar_oferta_lavagem();


CREATE OR REPLACE FUNCTION public._fechar_oferta_limpeza()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $function$
BEGIN
  IF OLD.offer_cleaner_id IS NULL THEN RETURN NEW; END IF;
  IF NEW.cleaner_id IS NOT NULL AND NEW.cleaner_id = OLD.offer_cleaner_id THEN
    PERFORM public.fechar_oferta(NEW.id, OLD.offer_cleaner_id, 'aceite');
  ELSIF NEW.offer_cleaner_id IS DISTINCT FROM OLD.offer_cleaner_id THEN
    PERFORM public.fechar_oferta(NEW.id, OLD.offer_cleaner_id, 'sem_resposta');
  END IF;
  RETURN NEW;
END $function$;

DROP TRIGGER IF EXISTS trg_fechar_oferta_limpeza ON public.cleaning_bookings;
CREATE TRIGGER trg_fechar_oferta_limpeza
  AFTER UPDATE OF offer_cleaner_id, cleaner_id ON public.cleaning_bookings
  FOR EACH ROW EXECUTE FUNCTION public._fechar_oferta_limpeza();
