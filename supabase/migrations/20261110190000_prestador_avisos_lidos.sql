-- ═══════════════════════════════════════════════════════════════════════════
-- Missão fechar-tudo-2026-11-10 · Bloco E4 · "Como o Bora decide" — quem leu.
--
-- Diretiva (UE) 2024/2831, art. 9.º: a plataforma informa POR ESCRITO cada
-- pessoa que trabalha através dela sobre os sistemas automáticos (o que é
-- automático, o que decide sempre uma pessoa, como pedir revisão), no
-- primeiro dia e sempre que houver mudança. Prazo de transposição: 02/12/2026.
-- A app mostra o ecrã "Como o Bora decide" com o botão "Li e percebi"; aqui
-- fica a prova: quem, quando, que versão (e em que papel estava a trabalhar).
--
--   prestador_avisos_lidos            — 1 linha por pessoa × aviso × versão
--   prestador_marcar_aviso_lido(...)  — a app grava "Li e percebi" (idempotente)
--   admin_avisos_prestadores(...)     — painel: todos os prestadores, leu/falta
--
-- Regras da casa:
--   · RLS: cada um lê e insere o seu; admin (public.is_admin()) lê tudo.
--     Sem UPDATE nem DELETE para ninguém da app: é um registo de prova.
--   · Funções novas nascem fechadas a anon (revoke de public E de anon).
--   · Guarda de admin com public.is_admin() (auth.uid()), NUNCA o papel da ligação (em SECURITY DEFINER é sempre o dono).
--   · Sem FK para auth.users de propósito: apagar uma conta não pode falhar
--     por causa deste registo (cicatriz "FKs ao encerrar conta").
-- ═══════════════════════════════════════════════════════════════════════════

-- ─── 1. Tabela ───────────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS public.prestador_avisos_lidos (
  id          bigserial PRIMARY KEY,
  user_id     uuid NOT NULL DEFAULT auth.uid(),
  aviso       text NOT NULL CHECK (aviso IN ('como_o_bora_decide')),
  versao      text NOT NULL CHECK (length(btrim(versao)) BETWEEN 1 AND 40),
  papel       text CHECK (papel IS NULL OR papel IN
                ('estafeta','motorista','limpeza','lavagem','casa','parceiro','servico')),
  plataforma  text CHECK (plataforma IS NULL OR length(plataforma) <= 20),
  lido_em     timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT prestador_avisos_lidos_um_por_versao UNIQUE (user_id, aviso, versao)
);

COMMENT ON TABLE public.prestador_avisos_lidos IS
  'E4 fechar-tudo-2026-11-10: prova de que cada prestador leu "Como o Bora decide" '
  '(Diretiva UE 2024/2831, art. 9.º). Uma linha por pessoa, aviso e versão.';

CREATE INDEX IF NOT EXISTS prestador_avisos_lidos_aviso_versao_idx
  ON public.prestador_avisos_lidos (aviso, versao);

-- A hora e o dono são sempre os do servidor: ninguém grava "li ontem" nem em
-- nome de outra pessoa, mesmo inserindo direto na tabela.
CREATE OR REPLACE FUNCTION public._prestador_avisos_lidos_carimbo()
RETURNS trigger
LANGUAGE plpgsql
SET search_path TO 'public'
AS $$
BEGIN
  NEW.lido_em := now();
  IF auth.uid() IS NOT NULL THEN
    NEW.user_id := auth.uid();
  END IF;
  RETURN NEW;
END $$;

DROP TRIGGER IF EXISTS trg_prestador_avisos_lidos_carimbo ON public.prestador_avisos_lidos;
CREATE TRIGGER trg_prestador_avisos_lidos_carimbo
  BEFORE INSERT ON public.prestador_avisos_lidos
  FOR EACH ROW EXECUTE FUNCTION public._prestador_avisos_lidos_carimbo();

REVOKE ALL ON FUNCTION public._prestador_avisos_lidos_carimbo() FROM public, anon, authenticated;

-- ─── 2. RLS ──────────────────────────────────────────────────────────────────
ALTER TABLE public.prestador_avisos_lidos ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS prestador_avisos_lidos_le ON public.prestador_avisos_lidos;
CREATE POLICY prestador_avisos_lidos_le ON public.prestador_avisos_lidos
  FOR SELECT TO authenticated
  USING (user_id = auth.uid() OR public.is_admin());

DROP POLICY IF EXISTS prestador_avisos_lidos_insere ON public.prestador_avisos_lidos;
CREATE POLICY prestador_avisos_lidos_insere ON public.prestador_avisos_lidos
  FOR INSERT TO authenticated
  WITH CHECK (user_id = auth.uid());

REVOKE ALL ON public.prestador_avisos_lidos FROM public, anon;
GRANT SELECT, INSERT ON public.prestador_avisos_lidos TO authenticated;
REVOKE ALL ON SEQUENCE public.prestador_avisos_lidos_id_seq FROM public, anon;
GRANT USAGE, SELECT ON SEQUENCE public.prestador_avisos_lidos_id_seq TO authenticated;

-- ─── 3. A app grava "Li e percebi" ───────────────────────────────────────────
-- Idempotente: carregar duas vezes na mesma versão não cria duas linhas e
-- devolve sempre a hora da PRIMEIRA leitura.
CREATE OR REPLACE FUNCTION public.prestador_marcar_aviso_lido(
  p_aviso      text,
  p_versao     text,
  p_papel      text DEFAULT NULL,
  p_plataforma text DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
  v_uid    uuid := auth.uid();
  v_versao text := btrim(coalesce(p_versao, ''));
  v_papel  text;
  v_lido   timestamptz;
BEGIN
  IF v_uid IS NULL THEN
    RAISE EXCEPTION 'SEM_SESSAO' USING ERRCODE = '42501';
  END IF;
  IF p_aviso IS DISTINCT FROM 'como_o_bora_decide' THEN
    RAISE EXCEPTION 'AVISO_DESCONHECIDO' USING ERRCODE = '22023';
  END IF;
  IF length(v_versao) NOT BETWEEN 1 AND 40 THEN
    RAISE EXCEPTION 'VERSAO_INVALIDA' USING ERRCODE = '22023';
  END IF;
  v_papel := CASE WHEN p_papel IN
    ('estafeta','motorista','limpeza','lavagem','casa','parceiro','servico')
    THEN p_papel END;

  INSERT INTO public.prestador_avisos_lidos (user_id, aviso, versao, papel, plataforma)
  VALUES (v_uid, p_aviso, v_versao, v_papel, left(nullif(btrim(coalesce(p_plataforma, '')), ''), 20))
  ON CONFLICT (user_id, aviso, versao) DO NOTHING;

  SELECT l.lido_em INTO v_lido
    FROM public.prestador_avisos_lidos l
   WHERE l.user_id = v_uid AND l.aviso = p_aviso AND l.versao = v_versao;

  RETURN jsonb_build_object('ok', true, 'aviso', p_aviso, 'versao', v_versao, 'lido_em', v_lido);
END $$;

REVOKE ALL ON FUNCTION public.prestador_marcar_aviso_lido(text, text, text, text) FROM public, anon;
GRANT EXECUTE ON FUNCTION public.prestador_marcar_aviso_lido(text, text, text, text) TO authenticated;

-- ─── 4. Painel admin: quem leu e quem falta, por papel ───────────────────────
-- Uma linha por perfil de prestador (estafeta, limpeza, lavagem, Casa; os
-- motoristas TVDE aparecem como 'motorista'). `lido_em` é a leitura da versão
-- pedida; `ultima_*` é a leitura mais recente de qualquer versão (para ver
-- quem só leu uma versão antiga). A versão em vigor vem da app
-- (ComoOBoraDecide.versaoId), a mesma que o prestador grava.
CREATE OR REPLACE FUNCTION public.admin_avisos_prestadores(
  p_aviso  text DEFAULT 'como_o_bora_decide',
  p_versao text DEFAULT NULL
)
RETURNS TABLE (
  papel              text,
  entidade_tabela    text,
  entidade_id        text,
  user_id            uuid,
  nome               text,
  email              text,
  telefone           text,
  aprovacao          text,
  ativo              boolean,
  versao_lida        text,
  lido_em            timestamptz,
  ultima_versao_lida text,
  ultima_lida_em     timestamptz
)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path TO 'public'
AS $$
#variable_conflict use_column
BEGIN
  IF NOT public.is_admin() THEN
    RAISE EXCEPTION 'SO_ADMIN' USING ERRCODE = '42501';
  END IF;

  RETURN QUERY
  WITH perfis AS (
    SELECT CASE WHEN d.vehicle_type = 'carro_passageiros' THEN 'motorista' ELSE 'estafeta' END AS p_papel,
           'drivers'::text AS p_tabela, d.id::text AS p_id, d.user_id AS p_uid,
           d.name AS p_nome, d.email AS p_email, d.phone AS p_tel, d.approval_status AS p_aprov,
           (NOT coalesce(d.is_banned, false) AND d.deleted_at IS NULL) AS p_ativo
      FROM public.drivers d
    UNION ALL
    SELECT 'limpeza', 'cleaners', c.id::text, c.user_id, c.name, c.email, c.phone,
           c.approval_status, coalesce(c.is_active, true)
      FROM public.cleaners c
    UNION ALL
    SELECT 'lavagem', 'washers', w.id::text, w.user_id, w.name, w.email, w.phone,
           w.approval_status, (coalesce(w.is_active, true) AND NOT coalesce(w.is_banned, false))
      FROM public.washers w
    UNION ALL
    SELECT 'casa', 'casa_profissionais', cp.id::text, cp.user_id, cp.name, cp.email, cp.phone,
           cp.approval_status, coalesce(cp.is_active, true)
      FROM public.casa_profissionais cp
  )
  SELECT pf.p_papel, pf.p_tabela, pf.p_id, pf.p_uid, pf.p_nome, pf.p_email, pf.p_tel,
         pf.p_aprov, pf.p_ativo,
         l.versao, l.lido_em,
         u.versao, u.lido_em
    FROM perfis pf
    LEFT JOIN public.prestador_avisos_lidos l
           ON l.user_id = pf.p_uid AND l.aviso = p_aviso AND l.versao = p_versao
    LEFT JOIN LATERAL (
           SELECT x.versao, x.lido_em
             FROM public.prestador_avisos_lidos x
            WHERE x.user_id = pf.p_uid AND x.aviso = p_aviso
            ORDER BY x.lido_em DESC
            LIMIT 1) u ON true
   ORDER BY pf.p_papel, (l.lido_em IS NULL) DESC, pf.p_nome NULLS LAST;
END $$;

REVOKE ALL ON FUNCTION public.admin_avisos_prestadores(text, text) FROM public, anon;
GRANT EXECUTE ON FUNCTION public.admin_avisos_prestadores(text, text) TO authenticated;
