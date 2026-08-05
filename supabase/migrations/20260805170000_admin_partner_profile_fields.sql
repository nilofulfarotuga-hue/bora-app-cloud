-- ============================================================================
-- BORA — perfil público editável pelo admin, para QUALQUER loja (BLOCO 7,
-- 2026-08-05): contacto/redes sociais + texto "sobre". Zona verde — só
-- colunas descritivas, não mexe em preço/comissão/pagamento.
--
-- `takeaway_enabled` e `reservations_enabled` já existem (ver
-- 20260601.._reservas_pro / migrations anteriores) — não recriados aqui.
--
-- Sem RPC nova: a RLS de UPDATE em `restaurants` já permite update directo
-- pela sessão admin (mesmo padrão já em produção para
-- takeaway_enabled/curbside_enabled/takeaway_default_prep_minutes/
-- partner_commission_billing — ver admin_partner_detail_screen.dart).
-- Safe to re-run.
-- ============================================================================

BEGIN;

ALTER TABLE public.restaurants
  ADD COLUMN IF NOT EXISTS whatsapp          TEXT NOT NULL DEFAULT '',
  ADD COLUMN IF NOT EXISTS social_facebook   TEXT NOT NULL DEFAULT '',
  ADD COLUMN IF NOT EXISTS social_instagram  TEXT NOT NULL DEFAULT '',
  ADD COLUMN IF NOT EXISTS about_text        TEXT NOT NULL DEFAULT '';

COMMENT ON COLUMN public.restaurants.whatsapp IS
  'Número de WhatsApp de contacto da loja (formato livre, editável no admin). Não confundir com phone.';
COMMENT ON COLUMN public.restaurants.social_facebook IS
  'URL da página de Facebook da loja, editável no admin.';
COMMENT ON COLUMN public.restaurants.social_instagram IS
  'URL/handle do Instagram da loja, editável no admin.';
COMMENT ON COLUMN public.restaurants.about_text IS
  'Texto livre "sobre a loja" mostrado ao cliente, editável no admin.';

COMMIT;
