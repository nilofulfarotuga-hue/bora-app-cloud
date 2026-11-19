-- APLICADA EM PRODUÇÃO pela Claude.ai via MCP a 19/11/2026 (versão 20261119163735). Cópia fiel para o repo.
-- NOTA: os km de estrada (road_km/road_min/status) foram preenchidos depois em produção pela Google
-- Distance Matrix (tabela cleaning_road_grid_requests). Esses DADOS não estão neste ficheiro; numa base
-- nova a grelha fica sem road_km e cleaning_road_km cai na estimativa (linha reta × fator).
-- 19/11/2026 (correção do Danilo): a taxa de deslocação da limpeza mede-se pela ESTRADA, não em linha reta.
-- Grelha de pontos à volta da Guarda com a distância de carro (Google Distance Matrix) desde o centro.
CREATE TABLE IF NOT EXISTS public.cleaning_road_grid (
  id bigserial PRIMARY KEY,
  nome text,
  lat double precision NOT NULL,
  lng double precision NOT NULL,
  straight_km numeric(6,2),
  road_km numeric(6,2),
  road_min numeric(6,1),
  status text,
  lote int,
  computed_at timestamptz
);
ALTER TABLE public.cleaning_road_grid ENABLE ROW LEVEL SECURITY;
-- sem políticas: só funções SECURITY DEFINER / service role leem

CREATE TABLE IF NOT EXISTS public.cleaning_road_grid_requests (
  lote int PRIMARY KEY,
  request_id bigint,
  ids bigint[],
  processed boolean NOT NULL DEFAULT false,
  created_at timestamptz NOT NULL DEFAULT now()
);
ALTER TABLE public.cleaning_road_grid_requests ENABLE ROW LEVEL SECURITY;

-- pontos com nome (localidades da zona) para conferir
INSERT INTO public.cleaning_road_grid(nome, lat, lng) VALUES
 ('Celorico da Beira', 40.6363, -7.3929),
 ('Belmonte', 40.3590, -7.3490),
 ('Sabugal', 40.3510, -7.0900),
 ('Manteigas', 40.4030, -7.5390),
 ('Trancoso', 40.7790, -7.3490),
 ('Pinhel', 40.7740, -7.0630),
 ('Vila Cortês do Mondego', 40.5735, -7.3460),
 ('Pera do Moço', 40.5800, -7.2000),
 ('Vila Fernando', 40.5490, -7.1690),
 ('Famalicão da Serra', 40.4410, -7.3700),
 ('Gonçalo', 40.4180, -7.3550),
 ('Fernão Joanes', 40.5020, -7.3460),
 ('Jarmelo', 40.6170, -7.1210),
 ('Castanheira', 40.5170, -7.1810);

-- grelha de 1,5 km até 24 km em linha reta do centro (40.5373, -7.2676)
INSERT INTO public.cleaning_road_grid(nome, lat, lng)
SELECT NULL,
       40.5373 + dy/111.32,
       -7.2676 + dx/(111.32*cos(radians(40.5373 + dy/111.32)))
FROM generate_series(-24.0, 24.0, 1.5) dy, generate_series(-24.0, 24.0, 1.5) dx
WHERE sqrt(dx*dx + dy*dy) <= 24.0;

UPDATE public.cleaning_road_grid
   SET straight_km = round(public._cleaning_distance_km(40.5373, -7.2676, lat, lng)::numeric, 2);

-- lotes de 25 destinos
WITH n AS (SELECT id, (row_number() OVER (ORDER BY id) - 1) / 25 AS l FROM public.cleaning_road_grid)
UPDATE public.cleaning_road_grid g SET lote = n.l FROM n WHERE n.id = g.id;
