-- 2026-10-03 — Grossura ÚNICA da linha da rota nos dois mapas (estafeta e
-- motorista TVDE). O Danilo achou a do estafeta fina (6) e a do motorista
-- certa (12, tipo Waze). Os dois ecrãs leem esta chave; editável no painel.
INSERT INTO public.platform_settings(key, value, category, description)
VALUES ('map_route_line_width', '12'::jsonb, 'mapa',
        'Grossura da linha da rota (em pontos) nos mapas do estafeta e do motorista TVDE. 12 = como o Waze. Vale na próxima vez que o ecrã do mapa abrir.')
ON CONFLICT (key) DO NOTHING;
