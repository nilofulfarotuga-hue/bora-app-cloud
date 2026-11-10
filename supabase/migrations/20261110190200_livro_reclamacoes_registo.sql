-- ═══════════════════════════════════════════════════════════════════════════
-- Missão fechar-tudo-2026-11-10 · Bloco E2e · Registo das reclamações do
-- Livro de Reclamações (eletrónico ou físico) e de entidades reguladoras.
--
-- DL 156/2005, art. 5.º-B: a Bora responde ao consumidor em 15 dias ÚTEIS.
-- O painel admin regista cada reclamação recebida, conta os dias úteis e
-- avisa o Danilo quando faltam 3 ou menos, ou quando o prazo passou.
--
-- O prazo (data) é calculado pela app ao registar (lib/utils/dias_uteis.dart:
-- 15 dias úteis depois da receção, sem fins de semana nem feriados nacionais;
-- o municipal da Guarda não entra, para o prazo nunca ficar mais longo do que
-- o legal) e fica gravado: é o que o painel mostra e exporta.
--
-- Não é a tabela `complaints` (queixas feitas DENTRO da app, com foto e
-- pedido): esta é a das reclamações oficiais, com prazo legal.
--
-- Só o admin (public.is_admin()) lê, cria e atualiza. Ninguém apaga: é um
-- registo para mostrar à Direção-Geral do Consumidor/ASAE se pedirem.
-- ═══════════════════════════════════════════════════════════════════════════

CREATE TABLE IF NOT EXISTS public.livro_reclamacoes_registo (
  id               bigserial PRIMARY KEY,
  recebida_em      date NOT NULL,
  canal            text NOT NULL CHECK (canal IN
                     ('livro_eletronico','livro_fisico','entidade_reguladora','email','outro')),
  numero           text CHECK (numero IS NULL OR length(numero) <= 80),
  quem             text CHECK (quem IS NULL OR length(quem) <= 200),
  resumo           text NOT NULL CHECK (length(btrim(resumo)) BETWEEN 3 AND 2000),
  prazo            date NOT NULL,
  estado           text NOT NULL DEFAULT 'aberta' CHECK (estado IN ('aberta','respondida','encerrada')),
  respondida_em    timestamptz,
  resposta_resumo  text CHECK (resposta_resumo IS NULL OR length(resposta_resumo) <= 2000),
  registada_por    uuid DEFAULT auth.uid(),
  created_at       timestamptz NOT NULL DEFAULT now(),
  updated_at       timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT livro_reclamacoes_prazo_depois CHECK (prazo > recebida_em),
  CONSTRAINT livro_reclamacoes_respondida_com_data CHECK (estado <> 'respondida' OR respondida_em IS NOT NULL)
);

COMMENT ON TABLE public.livro_reclamacoes_registo IS
  'E2e fechar-tudo-2026-11-10: reclamações oficiais recebidas (Livro de Reclamações, '
  'entidades reguladoras). Resposta em 15 dias úteis (DL 156/2005, art. 5.º-B). Só admin.';

CREATE INDEX IF NOT EXISTS livro_reclamacoes_registo_abertas_idx
  ON public.livro_reclamacoes_registo (prazo) WHERE estado = 'aberta';

CREATE OR REPLACE FUNCTION public._livro_reclamacoes_registo_updated_at()
RETURNS trigger
LANGUAGE plpgsql
SET search_path TO 'public'
AS $$
BEGIN
  NEW.updated_at := now();
  RETURN NEW;
END $$;

REVOKE ALL ON FUNCTION public._livro_reclamacoes_registo_updated_at() FROM public, anon, authenticated;

DROP TRIGGER IF EXISTS trg_livro_reclamacoes_registo_updated_at ON public.livro_reclamacoes_registo;
CREATE TRIGGER trg_livro_reclamacoes_registo_updated_at
  BEFORE UPDATE ON public.livro_reclamacoes_registo
  FOR EACH ROW EXECUTE FUNCTION public._livro_reclamacoes_registo_updated_at();

ALTER TABLE public.livro_reclamacoes_registo ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS livro_reclamacoes_admin_le ON public.livro_reclamacoes_registo;
CREATE POLICY livro_reclamacoes_admin_le ON public.livro_reclamacoes_registo
  FOR SELECT TO authenticated USING (public.is_admin());

DROP POLICY IF EXISTS livro_reclamacoes_admin_cria ON public.livro_reclamacoes_registo;
CREATE POLICY livro_reclamacoes_admin_cria ON public.livro_reclamacoes_registo
  FOR INSERT TO authenticated WITH CHECK (public.is_admin());

DROP POLICY IF EXISTS livro_reclamacoes_admin_atualiza ON public.livro_reclamacoes_registo;
CREATE POLICY livro_reclamacoes_admin_atualiza ON public.livro_reclamacoes_registo
  FOR UPDATE TO authenticated USING (public.is_admin()) WITH CHECK (public.is_admin());

REVOKE ALL ON public.livro_reclamacoes_registo FROM public, anon;
GRANT SELECT, INSERT, UPDATE ON public.livro_reclamacoes_registo TO authenticated;
REVOKE ALL ON SEQUENCE public.livro_reclamacoes_registo_id_seq FROM public, anon;
GRANT USAGE, SELECT ON SEQUENCE public.livro_reclamacoes_registo_id_seq TO authenticated;
