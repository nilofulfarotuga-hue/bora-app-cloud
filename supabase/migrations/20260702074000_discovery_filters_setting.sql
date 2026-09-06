-- Item 30 do goal paridade-admin-360: filtros de descoberta (config cliente).
-- Chave NÃO-financeira em platform_settings, gerida pelo AdminDiscoveryFiltersScreen
-- via admin_update_setting. Começa DESLIGADA: o lado cliente ainda não consome
-- estes filtros (follow-up sinalizado na Central) — ligar só quando consumir.

INSERT INTO public.platform_settings (key, value)
VALUES ('discovery_filters', '{
  "open_now_enabled": false,
  "dietary_enabled": false,
  "dietary_tags": ["vegetariano", "vegan", "sem_gluten", "sem_lactose"]
}'::jsonb)
ON CONFLICT (key) DO NOTHING;
