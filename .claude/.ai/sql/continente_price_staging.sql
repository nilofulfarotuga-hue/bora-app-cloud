-- =====================================================================
-- Continente PVPR crawler — INFRA DE STAGING (Fase 0)
-- Estado: PARA REVISÃO — NÃO aplicar até OK do Danilo.
-- Aplicar via mcp apply_migration (cria migration formal) quando aprovado.
-- Princípio: o crawler escreve AQUI; products só é tocada na Fase 3 (pós-aprovação no painel).
-- =====================================================================

-- 1) BACKUP defensivo do estado atual de preços (antes de qualquer UPDATE)
CREATE TABLE IF NOT EXISTS _backup_continente_price_pre_pvpr_2026_06_14 AS
SELECT id, price, source, last_updated, is_on_sale, needs_review
FROM products
WHERE restaurant_id = 'continente-guarda';

-- 2) TABELA DE STAGING por-produto (auditoria + revisão no painel admin)
CREATE TABLE IF NOT EXISTS continente_price_staging (
  id              uuid        DEFAULT gen_random_uuid() PRIMARY KEY,
  run_id          uuid        REFERENCES product_update_runs(id),
  product_id      text        NOT NULL,            -- products.id (cont-/cnt-)
  pid             text,                            -- PID Continente usado
  name            text,
  continente_url  text,
  old_price       numeric,                         -- snapshot products.price no momento do scrape
  sales_price     numeric,                         -- preço de venda no site (inclui promo se houver)
  pvpr            numeric,                         -- PVP recomendado (presente => promoção ativa)
  new_price       numeric,                         -- preço base decidido (regra PVPR vs venda)
  had_promo       boolean     DEFAULT false,
  method          text,                            -- sfcc_pid | name_match | skipped
  confidence      text,                            -- high | medium | low
  status          text,                            -- ok_no_promo | ok_promo | 404 | redirect_home | no_price | ambiguous_multi_pvpr | weird_pvpr_lt_sales
  divergence_pct  numeric,                         -- (new_price - old_price)/old_price
  needs_review    boolean     DEFAULT false,       -- |div|>=25% OU sanity OU ambíguo
  applied         boolean     DEFAULT false,
  applied_at      timestamptz,
  reviewer_action text,                            -- approved | rejected
  reviewed_by     text,
  reviewed_at     timestamptz,
  created_at      timestamptz DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_cps_run        ON continente_price_staging(run_id);
CREATE INDEX IF NOT EXISTS idx_cps_status     ON continente_price_staging(status);
CREATE INDEX IF NOT EXISTS idx_cps_review     ON continente_price_staging(needs_review) WHERE needs_review = true;
CREATE INDEX IF NOT EXISTS idx_cps_product    ON continente_price_staging(product_id);
CREATE INDEX IF NOT EXISTS idx_cps_applied    ON continente_price_staging(applied);

-- RLS: tabela de back-office. Sem policies => apenas service_role (Edge Fn / admin) acede.
ALTER TABLE continente_price_staging ENABLE ROW LEVEL SECURITY;

-- 3) KILL SWITCH (padrão platform_settings: key text, value jsonb, category text)
INSERT INTO platform_settings (key, value, category, description)
VALUES (
  'continente_price_crawler_enabled',
  'true'::jsonb,
  'scraping',
  'Liga/desliga o crawler de preços PVPR do Continente (cron de Terça + corrida manual).'
)
ON CONFLICT (key) DO NOTHING;

-- =====================================================================
-- NOTA: a aplicação staging -> products (Fase 3) NÃO está aqui de propósito.
-- Será uma RPC admin dedicada (continente_apply_price_staging) que:
--   * só aplica linhas status IN ('ok_no_promo','ok_promo') AND reviewer_action='approved' AND applied=false
--   * UPDATE products SET price=new_price, last_updated=<ISO>, source='continente_pt_official_2026-06-14'
--   * regista em admin_audit_log + marca applied=true, applied_at=now()
--   * NUNCA toca name/photo_url/category/unit
-- =====================================================================
