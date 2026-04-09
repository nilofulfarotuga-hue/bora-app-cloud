-- Products table for non-partner stores (supermarkets, pharmacies, etc.)
CREATE TABLE IF NOT EXISTS public.products (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  name TEXT NOT NULL,
  category TEXT NOT NULL,
  store TEXT NOT NULL,
  type TEXT NOT NULL CHECK (type IN ('budget', 'mid', 'premium')),
  price_original NUMERIC(10, 2) NOT NULL,
  price_app NUMERIC(10, 2) NOT NULL,
  created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- Index for fast store+category queries
CREATE INDEX IF NOT EXISTS idx_products_store ON public.products(store);
CREATE INDEX IF NOT EXISTS idx_products_category ON public.products(category);
CREATE INDEX IF NOT EXISTS idx_products_store_category ON public.products(store, category);

-- RLS: anyone can read products
ALTER TABLE public.products ENABLE ROW LEVEL SECURITY;

CREATE POLICY "products_read_all" ON public.products
  FOR SELECT USING (true);
