-- Product option groups (modifiers) — e.g. açaí cups: "Escolha os Acompanhamentos"
-- (pick N free) + "Deseja Extras?" (+€ each). Applied via MCP 2026-06-08; this file
-- mirrors the DB so the schema lives in version control. Idempotent.

CREATE TABLE IF NOT EXISTS product_option_groups (
  id            TEXT PRIMARY KEY DEFAULT gen_random_uuid(),
  product_id    TEXT NOT NULL REFERENCES products(id) ON DELETE CASCADE,
  name          TEXT NOT NULL,
  description   TEXT,
  is_required   BOOLEAN NOT NULL DEFAULT false,
  min_choices   INTEGER NOT NULL DEFAULT 0,
  max_choices   INTEGER NOT NULL DEFAULT 1,
  sort_order    INTEGER NOT NULL DEFAULT 0,
  created_at    TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at    TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS product_option_items (
  id            TEXT PRIMARY KEY DEFAULT gen_random_uuid(),
  group_id      TEXT NOT NULL REFERENCES product_option_groups(id) ON DELETE CASCADE,
  name          TEXT NOT NULL,
  price_add     NUMERIC NOT NULL DEFAULT 0,  -- € extra (0 = included)
  is_available  BOOLEAN NOT NULL DEFAULT true,
  sort_order    INTEGER NOT NULL DEFAULT 0,
  created_at    TIMESTAMPTZ NOT NULL DEFAULT now()
);

ALTER TABLE product_option_groups ENABLE ROW LEVEL SECURITY;
ALTER TABLE product_option_items ENABLE ROW LEVEL SECURITY;

-- Public read; partner (owner of the product's restaurant) manages.
DROP POLICY IF EXISTS "public_read_option_groups" ON product_option_groups;
CREATE POLICY "public_read_option_groups" ON product_option_groups
  FOR SELECT USING (true);

DROP POLICY IF EXISTS "partner_manage_option_groups" ON product_option_groups;
CREATE POLICY "partner_manage_option_groups" ON product_option_groups
  FOR ALL USING (
    EXISTS (
      SELECT 1 FROM products p
      JOIN restaurants r ON r.id = p.restaurant_id
      WHERE p.id = product_option_groups.product_id
      AND r.user_id = auth.uid()
    )
  );

DROP POLICY IF EXISTS "public_read_option_items" ON product_option_items;
CREATE POLICY "public_read_option_items" ON product_option_items
  FOR SELECT USING (true);

DROP POLICY IF EXISTS "partner_manage_option_items" ON product_option_items;
CREATE POLICY "partner_manage_option_items" ON product_option_items
  FOR ALL USING (
    EXISTS (
      SELECT 1 FROM product_option_groups g
      JOIN products p ON p.id = g.product_id
      JOIN restaurants r ON r.id = p.restaurant_id
      WHERE g.id = product_option_items.group_id
      AND r.user_id = auth.uid()
    )
  );

CREATE INDEX IF NOT EXISTS idx_option_groups_product ON product_option_groups(product_id);
CREATE INDEX IF NOT EXISTS idx_option_items_group ON product_option_items(group_id);
