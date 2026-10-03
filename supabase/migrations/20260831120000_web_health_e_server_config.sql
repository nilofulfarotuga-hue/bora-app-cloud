-- Missão endereco-web-2026-08-31.
--
-- 1) server_config: valores de configuração SÓ-SERVIDOR. Sem policies de RLS
--    de propósito — apenas o service role (Edge Functions) lê/escreve. Nasceu
--    para a Edge Function places-proxy usar a chave Google do lado do servidor
--    em vez de depender do script no browser (o valor é inserido à parte,
--    nunca em migration versionada).
--
-- 2) web_health_events: diagnóstico de falhas da web (autocomplete de morada
--    que morre em silêncio — cliente TVDE perdida 2x). O cliente escreve
--    (anon ou autenticado, com limites), só admin lê (painel PT-BR).

CREATE TABLE IF NOT EXISTS public.server_config (
  chave text PRIMARY KEY,
  valor text NOT NULL,
  atualizado_em timestamptz NOT NULL DEFAULT now()
);

ALTER TABLE public.server_config ENABLE ROW LEVEL SECURITY;
-- Sem policies: deny-all para anon/authenticated; service role passa por cima.

CREATE TABLE IF NOT EXISTS public.web_health_events (
  id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  criado_em timestamptz NOT NULL DEFAULT now(),
  motivo text NOT NULL CHECK (motivo IN (
    'script_bloqueado',
    'timeout_sdk',
    'sem_resultados',
    'geocode_manual_falhou',
    'proxy_falhou'
  )),
  ecra text CHECK (char_length(ecra) <= 80),
  detalhe text CHECK (char_length(detalhe) <= 500),
  plataforma text CHECK (char_length(plataforma) <= 20),
  user_id uuid
);

ALTER TABLE public.web_health_events ENABLE ROW LEVEL SECURITY;

-- Quem usa a app pode registar uma falha (mesmo sem sessão — os ecrãs de
-- registo também têm campo de morada). Os CHECKs em cima limitam o conteúdo.
CREATE POLICY web_health_events_insert ON public.web_health_events
  FOR INSERT TO anon, authenticated
  WITH CHECK (true);

-- Só o admin lê (painel PT-BR).
CREATE POLICY web_health_events_admin_select ON public.web_health_events
  FOR SELECT TO authenticated
  USING (public.is_admin());

CREATE INDEX IF NOT EXISTS web_health_events_criado_idx
  ON public.web_health_events (criado_em DESC);
