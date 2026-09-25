-- MEGA-FIX 2026-07-18 Parte 3 — espelho permanente das colunas de dono de `restaurants`.
--
-- `restaurants` tem DUAS colunas para o mesmo conceito de dono, por legado nunca unificado:
--   * user_   — a que TODAS as RPCs de parceiro leem (partner_takeaway_accept, etc.)
--   * user_id — a que o cadastro (Edge Fn register-partner, "BUG-2 FIX") passou a gravar.
-- Parceiros criados após ~junho/2026 nasceram sem dono funcional porque só uma coluna era
-- gravada. Este trigger garante que, aconteça o que acontecer no insert/update, ambas ficam
-- preenchidas — rede de segurança até uma migration de unificação futura.
-- COALESCE nunca sobrescreve um valor definido com NULL: só preenche o lado em falta.
-- Ver .claude/.ai/knowledge/wiki/licoes/licao-dual-owner-column.md

CREATE OR REPLACE FUNCTION public._restaurants_mirror_owner_columns()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
  NEW.user_   := COALESCE(NEW.user_, NEW.user_id);
  NEW.user_id := COALESCE(NEW.user_id, NEW.user_);
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_restaurants_mirror_owner ON public.restaurants;
CREATE TRIGGER trg_restaurants_mirror_owner
  BEFORE INSERT OR UPDATE ON public.restaurants
  FOR EACH ROW
  EXECUTE FUNCTION public._restaurants_mirror_owner_columns();
