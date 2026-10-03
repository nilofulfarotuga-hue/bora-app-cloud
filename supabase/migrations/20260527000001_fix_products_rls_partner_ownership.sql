-- Fix BUG-2: Products RLS policy must verify partner ownership
-- Step 1: Add user_id column to restaurants (links to auth.users.id)
-- Step 2: Update RLS policy on products to verify ownership via restaurant.user_id

ALTER TABLE public.restaurants
  ADD COLUMN IF NOT EXISTS user_id UUID REFERENCES auth.users(id) ON DELETE CASCADE;

-- Drop old permissive policy
DROP POLICY IF EXISTS "products_auth_write" ON public.products;

-- Create new restrictive policies per operation
CREATE POLICY "products_insert_owner"
  ON public.products
  FOR INSERT
  WITH CHECK (
    auth.uid() = (SELECT user_id FROM public.restaurants WHERE id = restaurant_id)
  );

CREATE POLICY "products_update_owner"
  ON public.products
  FOR UPDATE
  USING (
    auth.uid() = (SELECT user_id FROM public.restaurants WHERE id = restaurant_id)
  )
  WITH CHECK (
    auth.uid() = (SELECT user_id FROM public.restaurants WHERE id = restaurant_id)
  );

CREATE POLICY "products_delete_owner"
  ON public.products
  FOR DELETE
  USING (
    auth.uid() = (SELECT user_id FROM public.restaurants WHERE id = restaurant_id)
  );

-- SELECT remains public (original policy untouched)
