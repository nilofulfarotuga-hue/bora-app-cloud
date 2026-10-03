-- Missao redondo-total-2026-09-26, bloco B5: cascata de VIDEO.
-- Uma so fonte para a ordem dos geradores de video e o contador de creditos
-- por ferramenta e por dia. O robo das redes e o Bora Studio pedem o proximo
-- degrau a cascata_video_proximo() e gastam com cascata_video_usar(); se um
-- degrau esgota o limite do dia (ou esta bloqueado), passa-se ao seguinte.
-- Nunca Higgsfield nem servico pago novo.

CREATE TABLE IF NOT EXISTS public.cascata_video (
  ferramenta     text PRIMARY KEY,
  ordem          int  NOT NULL,
  como           text NOT NULL,            -- clique | kaggle | api
  perfil_chrome  text,                     -- deviceId do perfil certo, quando e por clique
  limite_dia     int  NOT NULL DEFAULT 3,  -- ritmo humano
  estado         text NOT NULL DEFAULT 'ativo' CHECK (estado IN ('ativo','bloqueado')),
  motivo         text,
  nota_maquina   int,                      -- MAQUINA x/45 do fiscal_video.py no bruto de prova
  prova          text,
  atualizado_em  timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS public.cascata_video_uso (
  dia        date NOT NULL DEFAULT (now() AT TIME ZONE 'Europe/Lisbon')::date,
  ferramenta text NOT NULL REFERENCES public.cascata_video(ferramenta),
  usados     int  NOT NULL DEFAULT 0,
  PRIMARY KEY (dia, ferramenta)
);

ALTER TABLE public.cascata_video ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.cascata_video_uso ENABLE ROW LEVEL SECURITY;
CREATE POLICY cascata_video_admin_le ON public.cascata_video FOR SELECT USING (public.is_admin());
CREATE POLICY cascata_video_uso_admin_le ON public.cascata_video_uso FOR SELECT USING (public.is_admin());

-- O proximo degrau com credito hoje (null = nenhum).
CREATE OR REPLACE FUNCTION public.cascata_video_proximo()
RETURNS TABLE(ferramenta text, como text, perfil_chrome text, restam int)
LANGUAGE sql SECURITY DEFINER SET search_path TO 'public' AS $$
  SELECT c.ferramenta, c.como, c.perfil_chrome,
         c.limite_dia - COALESCE(u.usados, 0) AS restam
    FROM public.cascata_video c
    LEFT JOIN public.cascata_video_uso u
      ON u.ferramenta = c.ferramenta
     AND u.dia = (now() AT TIME ZONE 'Europe/Lisbon')::date
   WHERE c.estado = 'ativo'
     AND COALESCE(u.usados, 0) < c.limite_dia
   ORDER BY c.ordem
   LIMIT 1;
$$;

-- Gasta um credito do dia; devolve quantos ficam (negativo = ja nao havia).
CREATE OR REPLACE FUNCTION public.cascata_video_usar(p_ferramenta text)
RETURNS int LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $$
DECLARE v_lim int; v_usados int;
BEGIN
  SELECT limite_dia INTO v_lim FROM public.cascata_video WHERE ferramenta = p_ferramenta;
  IF v_lim IS NULL THEN RAISE EXCEPTION 'ferramenta desconhecida: %', p_ferramenta; END IF;
  INSERT INTO public.cascata_video_uso(ferramenta, usados) VALUES (p_ferramenta, 1)
  ON CONFLICT (dia, ferramenta) DO UPDATE SET usados = cascata_video_uso.usados + 1
  RETURNING usados INTO v_usados;
  RETURN v_lim - v_usados;
END;
$$;

REVOKE ALL ON FUNCTION public.cascata_video_proximo() FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.cascata_video_usar(text) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.cascata_video_proximo() TO service_role;
GRANT EXECUTE ON FUNCTION public.cascata_video_usar(text) TO service_role;

INSERT INTO public.cascata_video(ferramenta, ordem, como, perfil_chrome, limite_dia, estado, motivo, nota_maquina, prova) VALUES
 ('veo-gemini-web', 1, 'clique', 'd9e862e0-a5ea-486f-b054-f333ef51b46a', 3, 'ativo', NULL, 40,
  'Bruto 2026-10-05-veo-entrega-sushi 720x1280 10 s com som; reel montado 45/45 (e2e_log 2474, 26/09)'),
 ('meta-vibes', 2, 'clique', 'd9e862e0-a5ea-486f-b054-f333ef51b46a', 5, 'bloqueado',
  'meta.ai no perfil Bora pede aceitar os Termos de IA da Meta (Continuar): o clique e do Danilo', NULL, NULL),
 ('zsky', 3, 'clique', 'd9e862e0-a5ea-486f-b054-f333ef51b46a', 3, 'bloqueado',
  'sem conta no perfil Bora (Sign in / Start Free); criar conta e do Danilo', NULL, NULL),
 ('kaggle-wan22', 4, 'kaggle', NULL, 8, 'ativo', NULL, 27,
  'Kernel boraboraapp/bora-anim 26/09 21:01: 8 clipes success, Wan2.2 S2V/I2V 14B, 768x432 16 fps 5 s, sem faixa de audio no mp4'),
 ('grok-imagine', 5, 'clique', NULL, 3, 'bloqueado', 'sem sessao em grok.com no perfil Bora', NULL, NULL)
ON CONFLICT (ferramenta) DO UPDATE SET ordem = EXCLUDED.ordem, como = EXCLUDED.como,
  perfil_chrome = EXCLUDED.perfil_chrome, limite_dia = EXCLUDED.limite_dia, estado = EXCLUDED.estado,
  motivo = EXCLUDED.motivo, nota_maquina = EXCLUDED.nota_maquina, prova = EXCLUDED.prova, atualizado_em = now();
