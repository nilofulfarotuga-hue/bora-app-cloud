-- Staging + kill switch para o crawler de preços PVPR do Continente.
-- (Aplicado via MCP em 2026-06-14; este ficheiro espelha-o no repo.)
-- O crawler escreve aqui; products só é tocada pela RPC admin_continente_apply_prices.

CREATE TABLE IF NOT EXISTS public.continente_price_staging (
  id              uuid        DEFAULT gen_random_uuid() PRIMARY KEY,
  run_id          uuid        REFERENCES public.product_update_runs(id),
  product_id      text        NOT NULL,
  pid             text,
  name            text,
  continente_url  text,
  old_price       numeric,
  sales_price     numeric,
  pvpr            numeric,
  new_price       numeric,
  had_promo       boolean     DEFAULT false,
  method          text,
  confidence      text,
  status          text,
  divergence_pct  numeric,
  needs_review    boolean     DEFAULT false,
  applied         boolean     DEFAULT false,
  applied_at      timestamptz,
  reviewer_action text,
  reviewed_by     text,
  reviewed_at     timestamptz,
  created_at      timestamptz DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_cps_run     ON public.continente_price_staging(run_id);
CREATE INDEX IF NOT EXISTS idx_cps_status  ON public.continente_price_staging(status);
CREATE INDEX IF NOT EXISTS idx_cps_review  ON public.continente_price_staging(needs_review) WHERE needs_review = true;
CREATE INDEX IF NOT EXISTS idx_cps_product ON public.continente_price_staging(product_id);
CREATE INDEX IF NOT EXISTS idx_cps_applied ON public.continente_price_staging(applied);

ALTER TABLE public.continente_price_staging ENABLE ROW LEVEL SECURITY;

INSERT INTO public.platform_settings (key, value, category, description)
VALUES (
  'continente_price_crawler_enabled',
  'true'::jsonb,
  'scraping',
  'Liga/desliga o crawler de precos PVPR do Continente (corrida manual + futuro cron de Terca).'
)
ON CONFLICT (key) DO NOTHING;
