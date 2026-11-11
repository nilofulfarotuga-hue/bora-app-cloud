 SELECT id,
    name,
    category,
    COALESCE(is_partner, false) AS is_partner,
    lat,
    lng,
        CASE
            WHEN category = ANY (ARRAY['supermarket'::text, 'store'::text, 'pharmacy'::text]) THEN 'storeShopping'::text
            ELSE 'restaurant'::text
        END AS service_type
   FROM restaurants r
  WHERE COALESCE(is_active_admin, true) AND COALESCE(approval_status, 'approved'::text) = 'approved'::text AND COALESCE(coming_soon, false) = false AND COALESCE(is_online, true) AND lat IS NOT NULL AND lng IS NOT NULL AND id !~~ 'demo-%'::text AND (COALESCE(category, ''::text) <> ALL (ARRAY['festas'::text, 'beauty'::text, 'services'::text])) AND (pausa_ate IS NULL OR pausa_ate < now()) AND (EXISTS ( SELECT 1
           FROM products p
          WHERE p.restaurant_id = r.id AND COALESCE(p.is_available, true) AND p.price > 0::numeric));