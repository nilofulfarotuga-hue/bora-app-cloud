-- ═══════════════════════════════════════════════════════════════════════════
-- BUG 1 (sessão 17-bugs 2026-05-11) — Trigger NOVO (#18 added) BEFORE INSERT
-- orders. Auto-define purchase_flow_version=2 para novos storeShopping
-- não-parceiro. Naming `trg_zz_*` para garantir ordem APÓS triggers
-- existentes (memória 7-DOCS-FINAL). NÃO modifica triggers existentes.
-- ═══════════════════════════════════════════════════════════════════════════

CREATE OR REPLACE FUNCTION public.trg_zz_set_purchase_flow_version()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
  IF NEW.service_type = 'storeShopping'
     AND COALESCE(NEW.is_partner_store, false) = false
     AND (NEW.purchase_flow_version IS NULL OR NEW.purchase_flow_version = 1) THEN
    NEW.purchase_flow_version := 2;
  ELSIF NEW.purchase_flow_version IS NULL THEN
    NEW.purchase_flow_version := 1;
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_zz_set_purchase_flow_version ON public.orders;
CREATE TRIGGER trg_zz_set_purchase_flow_version
  BEFORE INSERT ON public.orders
  FOR EACH ROW
  EXECUTE FUNCTION public.trg_zz_set_purchase_flow_version();

COMMENT ON FUNCTION public.trg_zz_set_purchase_flow_version() IS
  '5G BUG 1 — Auto-set purchase_flow_version=2 para storeShopping não-parceiro.
   Naming trg_zz_* garante ordem APÓS triggers existentes. Trigger #18 (adição).';
