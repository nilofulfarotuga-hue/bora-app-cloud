-- =====================================================================================
-- R1a — RECIBOS VERDES (SERVIDOR) — PROPOSTA, NÃO APLICADA
-- Missão 12 "recibos-verdes-15-11", ramo ai/2026-11-15-recibos-verdes.
-- Ordem: caixa_guardados 69 (escrita pela Claude.ai), com a autorização literal do Danilo
--        de 15/11/2026 16:25: "1, 2, 4 e 5. Pode fazer."  Escrito pelo Claude Code
--        (ajudante backend-supabase) a 15/11/2026, só com leituras (SELECT) à produção.
-- Quem aplica: a Claude.ai, depois de rever. Aplicar o ficheiro inteiro de uma vez
--        (apply_migration, ou execute_sql com o texto todo: sem BEGIN/COMMIT aqui dentro,
--        o Postgres corre tudo numa transação só — ou entra tudo, ou nada).
--        Depois de aplicado, guardar igual em supabase/migrations/ (regra 5 do AGENTS.md).
-- Prova: R1a_prova_rollback.sql (corre DEPOIS de aplicar; acaba sempre em ROLLBACK).
-- Contrato para a app, o painel e as Edge Functions: CONTRATO.md (mesma pasta).
--
-- ⚠️ ISTO MEXE NO MOMENTO DE PAGAR AOS PRESTADORES. Não muda nenhum preço, comissão,
--    ganho nem valor: só impede marcar "pago" enquanto falta o recibo verde com PDF.
--    Quem DEVE à Bora continua a ser cobrado como hoje ("recebido" nunca é travado).
--
-- O QUE CADA BLOCO FAZ
--   0  Pré-voo: confirma que as funções que vou substituir são as que li a 15/11 (md5) e que
--      nada disto já existe. Se algo não bater, pára tudo antes de mexer.
--   1  Cópia de segurança das definições atuais (tabela bkp_fn_recibos_verdes_20261115) e do
--      comando da tarefa 89 — o rollback lê daqui.
--   2  Ponto 5 + interruptor: fecho_dono_passa_recibo = false; recibos_trava_ativa = true.
--   3  Ponto 1: colunas recibo_pdf_path e recibo_verificacao; bucket privado recibos-verdes
--      e as suas regras (cada um só a sua pasta; admin vê tudo).
--   4  Ajudantes internos (data de hoje, semana, dia útil, conta do dono, validar PDF).
--   5  Ponto 2: fonte única prestador_recibo_mensal_resumo (um recibo por pessoa por mês).
--   6  Ponto 1: driver_mark_invoice_issued ganha p_pdf_path (sem sobrecarga ambígua: a versão
--      antiga muda de nome, não é apagada) + marcar/desmarcar à mão pelo painel.
--   7  Ponto 4: a trava (tabela de solturas, cálculo, gatilho nas 4 tabelas de acertos,
--      prestador_recibo_trava, admin_soltar_retido_recibo).
--   8  Ponto 4: as listas do painel dizem "retido" e o motivo (embrulho das funções atuais,
--      sem copiar os corpos delas).
--   9  Ponto 2: aviso do dia 10 a TODOS os prestadores (admin + push + email) e tarefa 89.
--  10  Ponto 4e: pagamento automático (auto_payout_pending, desligado) respeita a trava.
--      ZONA PROTEGIDA ADJACENTE: esta função chama create_payout, que escreve em ledger_entries.
--      A mudança só SALTA quem está retido; não toca em create_payout nem em valores.
--  11  Permissões finais, recarregar a API e um resumo do que ficou.
--  Fim: bloco de rollback comentado.
--
-- REGRAS SEGUIDAS: funções novas SECURITY DEFINER com search_path public; guardas com
-- is_admin(), auth.uid(), o papel do JWT (service_role) e session_user = 'postgres' (ligação
-- direta: cron, MCP) — nunca current_user. Funções da API: REVOKE de PUBLIC/anon, GRANT a
-- authenticated (+ service_role). Ajudantes internos (nome a começar por "_"): fechados também
-- a authenticated (só os chamam outras funções SECURITY DEFINER) — mais apertado que a regra
-- geral, de propósito. Auditoria por public.log_admin_action(text, text, text, jsonb).
-- =====================================================================================


-- =====================================================================================
-- BLOCO 0 — PRÉ-VOO
-- =====================================================================================
DO $prevoo$
DECLARE
  -- md5(pg_get_functiondef(...)) lido em produção a 15/11/2026 (funções cujo corpo muda aqui)
  v_esperado jsonb := jsonb_build_object(
    'public.driver_mark_invoice_issued(integer,integer,text,date)', 'ae5cc3948bac90093ea04ee93dd6b02c',
    'public.auto_payout_pending(numeric)',                          'e63865cad2c732fb6d911b311da14e83');
  v_k text;
  v_v text;
  v_oid regprocedure;
  v_md5 text;
BEGIN
  FOR v_k, v_v IN SELECT key, value FROM jsonb_each_text(v_esperado) LOOP
    v_oid := to_regprocedure(v_k);
    IF v_oid IS NULL THEN
      RAISE EXCEPTION 'PRE-VOO: a função % não existe — rever a proposta', v_k;
    END IF;
    v_md5 := md5(pg_get_functiondef(v_oid));
    IF v_md5 <> v_v THEN
      RAISE EXCEPTION 'PRE-VOO: a função % mudou desde a leitura de 15/11 (md5 % em vez de %) — rever antes de aplicar', v_k, v_md5, v_v;
    END IF;
  END LOOP;

  -- Funções que vão ser embrulhadas (mudam de nome e ganham um embrulho): têm de existir.
  IF to_regprocedure('public.admin_weekly_closeout_list(date)') IS NULL
     OR to_regprocedure('public.admin_acerto_unificado(date)') IS NULL
     OR to_regprocedure('public.admin_casa_acertos(date)') IS NULL
     OR to_regprocedure('public.admin_list_carwash_settlements(text)') IS NULL THEN
    RAISE EXCEPTION 'PRE-VOO: falta uma das listas do painel que vão ser embrulhadas';
  END IF;

  -- O que a proposta usa por dentro tem de existir.
  IF to_regprocedure('public._fecho_pedidos(timestamp with time zone,timestamp with time zone)') IS NULL
     OR to_regprocedure('public._fecho_limites(integer,integer)') IS NULL
     OR to_regprocedure('public.settlement_subject_user_id(text,text)') IS NULL
     OR to_regprocedure('public._semana_bate(timestamp with time zone,date)') IS NULL
     OR to_regprocedure('public.is_demo_user(uuid)') IS NULL
     OR to_regprocedure('public.is_demo_driver(text)') IS NULL
     OR to_regprocedure('public._push_in_app_notification(uuid,text,text,text,text)') IS NULL
     OR to_regprocedure('public.log_admin_action(text,text,text,jsonb)') IS NULL
     OR to_regclass('public.v_acerto_semanal_unificado') IS NULL
     OR to_regclass('public.notification_failures') IS NULL THEN
    RAISE EXCEPTION 'PRE-VOO: falta uma função, vista ou tabela de que a proposta depende';
  END IF;

  -- Nada desta proposta pode já existir (evita aplicar duas vezes).
  IF to_regclass('public.recibo_retencao_solturas') IS NOT NULL
     OR to_regclass('public.bkp_fn_recibos_verdes_20261115') IS NOT NULL
     OR to_regprocedure('public._driver_mark_invoice_issued_v1(integer,integer,text,date)') IS NOT NULL
     OR to_regprocedure('public._admin_weekly_closeout_list_base(date)') IS NOT NULL
     OR to_regprocedure('public.prestador_recibo_mensal_resumo(integer,integer,uuid)') IS NOT NULL
     OR EXISTS (SELECT 1 FROM pg_policies WHERE schemaname = 'storage' AND tablename = 'objects' AND policyname LIKE 'recibos_verdes_%')
     OR EXISTS (SELECT 1 FROM pg_trigger WHERE tgname = 'trg_recibo_trava_pagamento')
     OR EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema = 'public' AND table_name = 'driver_monthly_invoices' AND column_name = 'recibo_pdf_path') THEN
    RAISE EXCEPTION 'PRE-VOO: parte desta proposta já existe — foi aplicada antes? Rever.';
  END IF;

  -- A tarefa 89 tem de ser a do aviso antigo (é ela que muda de comando no bloco 9).
  IF NOT EXISTS (SELECT 1 FROM cron.job WHERE jobid = 89 AND command ILIKE '%aviso_recibos_estafetas_em_falta%') THEN
    RAISE EXCEPTION 'PRE-VOO: a tarefa 89 não é a do aviso de recibos — rever o bloco 9';
  END IF;
END
$prevoo$;


-- =====================================================================================
-- BLOCO 1 — CÓPIA DE SEGURANÇA (o rollback lê daqui)
-- =====================================================================================
CREATE TABLE public.bkp_fn_recibos_verdes_20261115 (
  criado_em  timestamptz NOT NULL DEFAULT now(),
  assinatura text NOT NULL,
  definicao  text NOT NULL,
  acl        text
);
ALTER TABLE public.bkp_fn_recibos_verdes_20261115 ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.bkp_fn_recibos_verdes_20261115 FROM anon, authenticated;

INSERT INTO public.bkp_fn_recibos_verdes_20261115 (assinatura, definicao, acl)
SELECT p.oid::regprocedure::text, pg_get_functiondef(p.oid), p.proacl::text
FROM pg_proc p
WHERE p.oid IN (
  'public.driver_mark_invoice_issued(integer,integer,text,date)'::regprocedure,
  'public.auto_payout_pending(numeric)'::regprocedure,
  'public.admin_weekly_closeout_list(date)'::regprocedure,
  'public.admin_acerto_unificado(date)'::regprocedure,
  'public.admin_casa_acertos(date)'::regprocedure,
  'public.admin_list_carwash_settlements(text)'::regprocedure);

INSERT INTO public.bkp_fn_recibos_verdes_20261115 (assinatura, definicao)
SELECT 'cron.job:89', j.command FROM cron.job j WHERE j.jobid = 89;


-- =====================================================================================
-- BLOCO 2 — DEFINIÇÕES (ponto 5 + interruptor da trava)
-- =====================================================================================
INSERT INTO public.platform_settings (key, value, description, category, is_secret)
VALUES
  ('fecho_dono_passa_recibo', 'false'::jsonb,
   'Recibos verdes: se ligado, a partir de novembro/2026 a conta de estafeta do dono (boraappbora) entra como qualquer prestador (email do dia 1, botão, aviso do dia 10 e trava do pagamento). Desligado = a conta é saltada, como até outubro. Liga-se quando o contabilista responder.',
   'fecho', false),
  ('recibos_trava_ativa', 'true'::jsonb,
   'Recibos verdes: liga a trava do pagamento semanal (quem não tem o recibo do mês anterior com PDF até ao dia 10 fica com o pagamento retido, sem perder nada). Desligar só em emergência; cada linha também pode ser solta à mão com motivo.',
   'fecho', false)
ON CONFLICT (key) DO NOTHING;


-- =====================================================================================
-- BLOCO 3 — PONTO 1: COLUNAS, BUCKET E REGRAS DO ARMAZENAMENTO
-- =====================================================================================
ALTER TABLE public.driver_monthly_invoices
  ADD COLUMN IF NOT EXISTS recibo_pdf_path text,
  ADD COLUMN IF NOT EXISTS recibo_verificacao jsonb;

COMMENT ON COLUMN public.driver_monthly_invoices.recibo_pdf_path IS
  'Recibos verdes (15/11/2026): caminho do PDF/foto no bucket privado recibos-verdes, {user_id}/{ano}-{mês com 2 dígitos}.pdf|jpg|png. Sem isto o recibo não conta como entregue para a trava.';
COMMENT ON COLUMN public.driver_monthly_invoices.recibo_verificacao IS
  'Recibos verdes (15/11/2026): resultado da conferência automática (OCR) escrito pela Edge (R1b): {ok, nif_lido, valor_lido, problemas[], conferido_em}. Limpa-se sozinho quando entra um PDF novo.';

-- Bucket privado, igual ao modelo provider-atividade: 10 MB, PDF/JPG/PNG.
INSERT INTO storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
VALUES ('recibos-verdes', 'recibos-verdes', false, 10485760,
        ARRAY['application/pdf', 'image/jpeg', 'image/jpg', 'image/png'])
ON CONFLICT (id) DO NOTHING;
-- Conserto do Juiz (16/11, R1a-5): se a pasta já existia pública, parar tudo.
DO $$BEGIN
  IF (SELECT public FROM storage.buckets WHERE id = 'recibos-verdes') THEN
    RAISE EXCEPTION 'bucket recibos-verdes publico';
  END IF;
END$$;

-- Cada prestador lê só a sua pasta.
CREATE POLICY recibos_verdes_proprio_ler ON storage.objects
  FOR SELECT TO authenticated
  USING (bucket_id = 'recibos-verdes'
         AND (storage.foldername(name))[1] = (SELECT auth.uid())::text);

-- Cada prestador envia só para a sua pasta, com o nome certo, e só enquanto o recibo desse mês
-- ainda não está marcado com PDF (depois de marcado, trocar o ficheiro passa pelo admin).
CREATE POLICY recibos_verdes_proprio_enviar ON storage.objects
  FOR INSERT TO authenticated
  WITH CHECK (bucket_id = 'recibos-verdes'
              AND (storage.foldername(name))[1] = (SELECT auth.uid())::text
              AND name ~* '^[0-9a-f-]{36}/[0-9]{4}-(0[1-9]|1[0-2])\.(pdf|jpe?g|png)$'
              AND NOT EXISTS (
                SELECT 1 FROM public.driver_monthly_invoices m
                WHERE m.user_id = (SELECT auth.uid())
                  AND m.recibo_pdf_path IS NOT NULL
                  AND m.ano = (substring(objects.name FROM '/([0-9]{4})-'))::int
                  AND m.mes = (substring(objects.name FROM '/[0-9]{4}-([0-9]{2})\.'))::int));

-- Substituir (upsert) o próprio ficheiro, nas mesmas condições.
CREATE POLICY recibos_verdes_proprio_substituir ON storage.objects
  FOR UPDATE TO authenticated
  USING (bucket_id = 'recibos-verdes'
         AND (storage.foldername(name))[1] = (SELECT auth.uid())::text
         AND NOT EXISTS (
           SELECT 1 FROM public.driver_monthly_invoices m
           WHERE m.user_id = (SELECT auth.uid())
             AND m.recibo_pdf_path IS NOT NULL
             AND m.ano = (substring(objects.name FROM '/([0-9]{4})-'))::int
             AND m.mes = (substring(objects.name FROM '/[0-9]{4}-([0-9]{2})\.'))::int))
  WITH CHECK (bucket_id = 'recibos-verdes'
              AND (storage.foldername(name))[1] = (SELECT auth.uid())::text
              AND name ~* '^[0-9a-f-]{36}/[0-9]{4}-(0[1-9]|1[0-2])\.(pdf|jpe?g|png)$');

-- O admin vê tudo.
CREATE POLICY recibos_verdes_admin_ler ON storage.objects
  FOR SELECT TO authenticated
  USING (bucket_id = 'recibos-verdes' AND (SELECT public.is_admin()));

-- O admin pode pôr o ficheiro na pasta de alguém (recibo que chegou por email/WhatsApp).
CREATE POLICY recibos_verdes_admin_enviar ON storage.objects
  FOR INSERT TO authenticated
  WITH CHECK (bucket_id = 'recibos-verdes' AND (SELECT public.is_admin())
              AND name ~* '^[0-9a-f-]{36}/[0-9]{4}-(0[1-9]|1[0-2])\.(pdf|jpe?g|png)$');

CREATE POLICY recibos_verdes_admin_substituir ON storage.objects
  FOR UPDATE TO authenticated
  USING (bucket_id = 'recibos-verdes' AND (SELECT public.is_admin()))
  WITH CHECK (bucket_id = 'recibos-verdes' AND (SELECT public.is_admin())
              AND name ~* '^[0-9a-f-]{36}/[0-9]{4}-(0[1-9]|1[0-2])\.(pdf|jpe?g|png)$');
-- Ninguém apaga pela API (o armazenamento já tem a guarda protect_objects_delete).


-- =====================================================================================
-- BLOCO 4 — AJUDANTES INTERNOS
-- =====================================================================================

-- Data de hoje em Lisboa. Só numa ligação direta (postgres) e só dentro de uma transação de
-- prova é que se pode fingir outro dia (bora.recibo_hoje_teste) — pela app/painel nunca vale.
CREATE OR REPLACE FUNCTION public._recibo_hoje()
RETURNS date
LANGUAGE plpgsql
STABLE
SET search_path TO 'public'
AS $fn$
DECLARE
  v_teste text := nullif(current_setting('bora.recibo_hoje_teste', true), '');
BEGIN
  IF v_teste IS NOT NULL AND session_user = 'postgres' THEN
    RETURN v_teste::date;
  END IF;
  RETURN (now() AT TIME ZONE 'Europe/Lisbon')::date;
END
$fn$;

-- Segunda-feira (Lisboa) da semana de um acerto — a mesma conta do admin_marcar_acerto_pago
-- e da vista v_acerto_semanal_unificado.
CREATE OR REPLACE FUNCTION public._recibo_semana(p_ts timestamptz)
RETURNS date
LANGUAGE sql
STABLE
SET search_path TO 'public'
AS $fn$
  SELECT (date_trunc('week', p_ts AT TIME ZONE 'Europe/Lisbon'))::date
$fn$;

-- N.º dia útil a contar de uma data (segunda a sexta, sem os feriados nacionais fixos).
-- Os feriados móveis (Carnaval, Sexta-feira Santa, Corpo de Deus) não entram — é só informativo.
CREATE OR REPLACE FUNCTION public._recibo_dia_util(p_inicio date, p_n integer)
RETURNS date
LANGUAGE sql
STABLE
SET search_path TO 'public'
AS $fn$
  SELECT g.d::date
  FROM generate_series(p_inicio::timestamp, p_inicio::timestamp + interval '45 days', interval '1 day') AS g(d)
  WHERE extract(isodow FROM g.d) < 6
    AND to_char(g.d, 'MM-DD') NOT IN ('01-01','04-25','05-01','06-10','08-15','10-05','11-01','12-01','12-08','12-25')
  ORDER BY g.d
  OFFSET greatest(coalesce(p_n, 1), 1) - 1
  LIMIT 1
$fn$;

-- A conta de estafeta do dono (boraappbora) — a mesma regra do campo proprio_adquirente de hoje.
CREATE OR REPLACE FUNCTION public._recibo_e_conta_dono(p_user_id uuid)
RETURNS boolean
LANGUAGE sql
STABLE SECURITY DEFINER
SET search_path TO 'public'
AS $fn$
  SELECT p_user_id IS NOT NULL AND (
       EXISTS (SELECT 1 FROM auth.users u
               WHERE u.id = p_user_id AND lower(coalesce(u.email, '')) = 'boraappbora@gmail.com')
    OR EXISTS (SELECT 1 FROM public.drivers d
               WHERE d.user_id = p_user_id AND lower(btrim(coalesce(d.email, ''))) = 'boraappbora@gmail.com'))
$fn$;

-- Confere o caminho do PDF e que o ficheiro já está no armazenamento.
CREATE OR REPLACE FUNCTION public._recibo_validar_pdf(p_user_id uuid, p_year integer, p_month integer, p_path text)
RETURNS void
LANGUAGE plpgsql
STABLE SECURITY DEFINER
SET search_path TO 'public'
AS $fn$
BEGIN
  IF p_user_id IS NULL OR p_path IS NULL
     OR p_path !~* ('^' || p_user_id::text || '/' || p_year::text || '-' || lpad(p_month::text, 2, '0') || '\.(pdf|jpe?g|png)$') THEN
    RAISE EXCEPTION 'pdf_caminho_invalido'
      USING HINT = 'O caminho tem de ser {user_id}/{ano}-{mês com 2 dígitos}.pdf (ou .jpg/.png) no bucket recibos-verdes.';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM storage.objects o WHERE o.bucket_id = 'recibos-verdes' AND o.name = p_path) THEN
    RAISE EXCEPTION 'pdf_nao_encontrado'
      USING HINT = 'Primeiro envia-se o ficheiro para o armazenamento; só depois se marca o recibo.';
  END IF;
END
$fn$;


-- =====================================================================================
-- BLOCO 5 — PONTO 2: FONTE ÚNICA DO RECIBO MENSAL (um recibo por pessoa por mês)
-- =====================================================================================
-- Soma por user_id: entregas (_fecho_pedidos, como o driver_monthly_invoice_summary),
-- limpezas e lavagens (os mesmos critérios do fecho_mensal_prestadores) e Casa e Manutenção
-- (os mesmos critérios do casa_calcular_acerto: confirmado, sem teste, sem reembolso por decidir).
-- TVDE fica fora (o fecho_mensal_prestadores já diz "TVDE fora da plataforma: não entra em fecho").
-- Valores lidos, nunca calculados de novo: nada aqui muda dinheiro.
CREATE OR REPLACE FUNCTION public._recibo_resumo_calc(p_year integer, p_month integer, p_user_id uuid DEFAULT NULL::uuid)
RETURNS jsonb
LANGUAGE plpgsql
STABLE SECURITY DEFINER
SET search_path TO 'public'
AS $fn$
DECLARE
  v_ini timestamptz;
  v_fim timestamptz;
  v_nome_mes text;
  v_sociedade boolean;
  v_dono_passa boolean;
  v_prox date;
  v_trava_desde CONSTANT date := date '2026-11-01';   -- a trava começa nos recibos de novembro/2026
  v_conta_trava boolean;
  v_adq jsonb;
  v_regras jsonb;
  v_lista jsonb;
BEGIN
  IF p_year IS NULL OR p_month IS NULL OR p_month NOT BETWEEN 1 AND 12 OR p_year NOT BETWEEN 2024 AND 2100 THEN
    RAISE EXCEPTION 'mes_invalido';
  END IF;
  SELECT l.ini, l.fim INTO v_ini, v_fim FROM public._fecho_limites(p_year, p_month) l;
  v_nome_mes := (ARRAY['janeiro','fevereiro','março','abril','maio','junho','julho',
                       'agosto','setembro','outubro','novembro','dezembro'])[p_month];
  v_sociedade := (p_year, p_month) >= (2026, 11);
  v_prox := (make_date(p_year, p_month, 1) + interval '1 month')::date;
  v_conta_trava := make_date(p_year, p_month, 1) >= v_trava_desde;
  v_dono_passa := coalesce((SELECT (s.value #>> '{}')::boolean FROM public.platform_settings s
                            WHERE s.key = 'fecho_dono_passa_recibo'), false);

  -- Quem compra o serviço (adquirente): a sociedade desde novembro/2026; antes, o Danilo em
  -- nome individual (igual ao driver_monthly_invoice_summary).
  IF v_sociedade THEN
    v_adq := jsonb_build_object('tipo', 'sociedade',
                                'nome', 'Danilo Fulfaro da Silva - Unipessoal Lda',
                                'nif', '519686233',
                                'morada', 'Rua do Torreão 14, 6300-610 Guarda');
  ELSE
    v_adq := jsonb_build_object(
      'tipo',   coalesce((SELECT value #>> '{}' FROM public.platform_settings WHERE key = 'fecho_entidade_tipo'), 'individual'),
      'nome',   coalesce(nullif((SELECT value #>> '{}' FROM public.platform_settings WHERE key = 'fecho_entidade_nome'), ''), 'Danilo Fulfaro da Silva'),
      'nif',    coalesce(nullif((SELECT value #>> '{}' FROM public.platform_settings WHERE key = 'fecho_entidade_nif'), ''), '322151171'),
      'morada', coalesce(nullif((SELECT value #>> '{}' FROM public.platform_settings WHERE key = 'fecho_entidade_morada'), ''), 'Rua do Torreão 14, 6300-610 Guarda'));
  END IF;

  -- Textos e prazos (só texto: a retenção e o IVA não mexem em contas nenhumas).
  v_regras := jsonb_build_object(
    'descricao_modelo', format('Serviços prestados em %s de %s através da plataforma Bora', v_nome_mes, p_year),
    'prazo_texto', 'Fatura-recibo até ao 5.º dia útil seguinte ao recebimento (art. 36.º CIVA / art. 115.º CIRS)',
    'prazo_legal_data', public._recibo_dia_util(v_prox, 5),
    'prazo_legal_nota', 'Conta dias úteis e feriados nacionais fixos; os feriados móveis não entram.',
    'anexar_ate', v_prox + 9,
    'anexar_texto', 'Anexe o recibo na app, em Ganhos, até ' || to_char(v_prox + 9, 'DD/MM/YYYY') || '.',
    'trava_desde', v_trava_desde,
    'conta_para_trava', v_conta_trava,
    'retencao', jsonb_build_object(
      'regra', 'Quem não passa 15.000 EUR por ano de rendimentos desta categoria está dispensado de retenção na fonte e escreve no recibo a menção abaixo (n.º 1 do artigo 101.º-B do Código do IRS). Acima disso, a empresa retém 11,5%. O contabilista confirma o caso de cada um.',
      'mencao_dispensa', 'Sem retenção, nos termos do n.º 1 do artigo 101.º-B do Código do IRS',
      'taxa_se_aplicavel', '11,5%',
      'limite_anual', '15.000 EUR'),
    'iva_texto', 'IVA: isento ao abrigo do artigo 53.º do CIVA, se for o seu caso; o contabilista confirma.');

  WITH
  ent AS (
    SELECT f.driver_user_id::uuid AS user_id, count(*)::int AS n,
           round(coalesce(sum(f.estafeta), 0)::numeric, 2) AS valor
    FROM public._fecho_pedidos(v_ini, v_fim) f
    WHERE f.driver_user_id ~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'
      AND (p_user_id IS NULL OR f.driver_user_id = p_user_id::text)
    GROUP BY 1),
  lim AS (
    SELECT c.user_id, count(*)::int AS n, round(coalesce(sum(b.cleaner_earnings_cents), 0) / 100.0, 2) AS valor
    FROM public.cleaning_bookings b
    JOIN public.cleaners c ON c.id = b.cleaner_id
    WHERE b.status IN ('completed', 'done') AND coalesce(b.is_test_order, false) = false
      AND b.scheduled_at >= v_ini AND b.scheduled_at < v_fim
      AND c.user_id IS NOT NULL AND (p_user_id IS NULL OR c.user_id = p_user_id)
    GROUP BY 1),
  lav AS (
    SELECT w.user_id, count(*)::int AS n, round(coalesce(sum(b.washer_earnings_cents), 0) / 100.0, 2) AS valor
    FROM public.carwash_bookings b
    JOIN public.washers w ON w.id = b.washer_id
    WHERE b.status IN ('completed', 'done') AND coalesce(b.is_test_order, false) = false
      AND coalesce(b.completed_at, b.done_at, b.created_at) >= v_ini
      AND coalesce(b.completed_at, b.done_at, b.created_at) < v_fim
      AND w.user_id IS NOT NULL AND (p_user_id IS NULL OR w.user_id = p_user_id)
    GROUP BY 1),
  casa_l AS (
    SELECT k.user_id, count(*)::int AS n, round(coalesce(sum(p.ganho_cents), 0) / 100.0, 2) AS valor
    FROM public.casa_pedidos p
    JOIN public.casa_profissionais k ON k.id = p.profissional_id
    WHERE p.estado = 'confirmado' AND NOT coalesce(p.is_test_order, false)
      AND NOT coalesce(p.reembolso_pendente, false)
      AND p.confirmed_at >= v_ini AND p.confirmed_at < v_fim
      AND k.user_id IS NOT NULL AND (p_user_id IS NULL OR k.user_id = p_user_id)
    GROUP BY 1),
  linhas AS (
    SELECT x.user_id, 1 AS ordem, 'entregas'::text AS servico, 'Entregas'::text AS nome, x.n, x.valor,
           CASE WHEN x.n = 1 THEN 'entrega' ELSE 'entregas' END AS rotulo
    FROM ent x
    UNION ALL
    SELECT x.user_id, 2, 'limpeza', 'Limpezas', x.n, x.valor,
           CASE WHEN x.n = 1 THEN 'limpeza' ELSE 'limpezas' END
    FROM lim x
    UNION ALL
    SELECT x.user_id, 3, 'lavagem', 'Lavagens auto', x.n, x.valor,
           CASE WHEN x.n = 1 THEN 'lavagem auto' ELSE 'lavagens auto' END
    FROM lav x
    UNION ALL
    SELECT x.user_id, 4, 'casa', 'Casa e Manutenção', x.n, x.valor,
           CASE WHEN x.n = 1 THEN 'serviço de Casa e Manutenção' ELSE 'serviços de Casa e Manutenção' END
    FROM casa_l x),
  pessoas AS (
    SELECT l.user_id,
           round(sum(l.valor), 2) AS total,
           jsonb_agg(jsonb_build_object('servico', l.servico, 'nome', l.nome,
                                        'quantidade', l.n, 'valor', l.valor) ORDER BY l.ordem) AS linhas,
           string_agg(l.n::text || ' ' || l.rotulo, ', ' ORDER BY l.ordem) AS qtd_texto
    FROM linhas l
    GROUP BY l.user_id),
  info AS (
    SELECT p.user_id, p.total, p.linhas, p.qtd_texto,
           coalesce(
             (SELECT coalesce(nullif(btrim(d.legal_name), ''), d.name) FROM public.drivers d WHERE d.user_id = p.user_id LIMIT 1),
             (SELECT coalesce(nullif(btrim(c.legal_name), ''), c.name) FROM public.cleaners c WHERE c.user_id = p.user_id LIMIT 1),
             (SELECT coalesce(nullif(btrim(w.legal_name), ''), w.name) FROM public.washers w WHERE w.user_id = p.user_id LIMIT 1),
             (SELECT coalesce(nullif(btrim(k.legal_name), ''), k.name) FROM public.casa_profissionais k WHERE k.user_id = p.user_id LIMIT 1),
             (SELECT u.email FROM auth.users u WHERE u.id = p.user_id)) AS nome,
           coalesce(
             (SELECT nullif(btrim(fs.nif), '') FROM public.driver_fiscal_status fs WHERE fs.user_id = p.user_id LIMIT 1),
             (SELECT nullif(btrim(d.nif), '') FROM public.drivers d WHERE d.user_id = p.user_id LIMIT 1),
             (SELECT nullif(btrim(c.nif), '') FROM public.cleaners c WHERE c.user_id = p.user_id LIMIT 1),
             (SELECT nullif(btrim(w.nif), '') FROM public.washers w WHERE w.user_id = p.user_id LIMIT 1),
             (SELECT nullif(btrim(k.nif), '') FROM public.casa_profissionais k WHERE k.user_id = p.user_id LIMIT 1)) AS nif,
           (SELECT u.email FROM auth.users u WHERE u.id = p.user_id) AS email,
           (public.is_demo_user(p.user_id) OR coalesce(public.is_demo_driver(p.user_id::text), false)) AS demo,
           public._recibo_e_conta_dono(p.user_id) AS conta_dono,
           m.recibo_numero, m.recibo_data, m.marcado_em, m.recibo_pdf_path, m.recibo_verificacao
    FROM pessoas p
    LEFT JOIN public.driver_monthly_invoices m
      ON m.user_id = p.user_id AND m.ano = p_year AND m.mes = p_month),
  fim_lista AS (
    SELECT i.*,
           (i.conta_dono AND (NOT v_sociedade OR NOT v_dono_passa)) AS proprio_adquirente,
           (i.total > 0 AND NOT i.demo AND NOT (i.conta_dono AND (NOT v_sociedade OR NOT v_dono_passa))) AS precisa
    FROM info i)
  SELECT coalesce(jsonb_agg(jsonb_build_object(
           'user_id', f.user_id,
           'nome', f.nome,
           'nif', f.nif,
           'email', f.email,
           'linhas', f.linhas,
           'total', f.total,
           'descricao', format('Serviços prestados em %s de %s através da plataforma Bora (%s)', v_nome_mes, p_year, f.qtd_texto),
           'demo', f.demo,
           'conta_dono', f.conta_dono,
           'proprio_adquirente', f.proprio_adquirente,
           'precisa_recibo', f.precisa,
           'conta_para_trava', f.precisa AND v_conta_trava,
           'recibo_passado', f.marcado_em IS NOT NULL,
           'tem_pdf', f.recibo_pdf_path IS NOT NULL,
           'estado', CASE WHEN NOT f.precisa THEN 'nao_precisa'
                          WHEN f.recibo_pdf_path IS NOT NULL THEN 'entregue'
                          WHEN f.marcado_em IS NOT NULL THEN 'sem_pdf'
                          ELSE 'em_falta' END,
           'recibo', jsonb_build_object('numero', f.recibo_numero, 'data', f.recibo_data,
                                        'marcado_em', f.marcado_em, 'pdf_path', f.recibo_pdf_path,
                                        'verificacao', f.recibo_verificacao))
         ORDER BY f.nome), '[]'::jsonb)
  INTO v_lista
  FROM fim_lista f;

  RETURN jsonb_build_object(
    'ano', p_year,
    'mes', p_month,
    'nome_mes', v_nome_mes,
    'periodo', jsonb_build_object('inicio', v_ini, 'fim', v_fim),
    'adquirente', v_adq,
    'regras', v_regras,
    'prestadores', v_lista,
    'prestador', CASE WHEN p_user_id IS NOT NULL THEN v_lista -> 0 END,
    'totais', (SELECT jsonb_build_object(
                 'pessoas', count(*),
                 'precisam', count(*) FILTER (WHERE (e ->> 'precisa_recibo')::boolean),
                 'entregues', count(*) FILTER (WHERE e ->> 'estado' = 'entregue'),
                 'em_falta', count(*) FILTER (WHERE e ->> 'estado' IN ('em_falta', 'sem_pdf')),
                 'total', coalesce(sum((e ->> 'total')::numeric), 0))
               FROM jsonb_array_elements(v_lista) e),
    'gerado_em', now());
END
$fn$;

-- Porta pública: o próprio vê o seu; admin, service_role (Edges) e ligação direta veem todos.
CREATE OR REPLACE FUNCTION public.prestador_recibo_mensal_resumo(p_year integer, p_month integer, p_user_id uuid DEFAULT NULL::uuid)
RETURNS jsonb
LANGUAGE plpgsql
STABLE SECURITY DEFINER
SET search_path TO 'public'
AS $fn$
DECLARE
  v_uid uuid := auth.uid();
  v_priv boolean := public.is_admin()
                    OR coalesce(auth.jwt() ->> 'role', '') = 'service_role'
                    OR session_user = 'postgres';
BEGIN
  IF v_priv THEN
    RETURN public._recibo_resumo_calc(p_year, p_month, p_user_id);   -- p_user_id NULL = todos
  END IF;
  IF v_uid IS NULL THEN
    RAISE EXCEPTION 'sem_sessao';
  END IF;
  IF p_user_id IS NOT NULL AND p_user_id <> v_uid THEN
    RAISE EXCEPTION 'sem_permissao' USING ERRCODE = '42501';
  END IF;
  RETURN public._recibo_resumo_calc(p_year, p_month, v_uid);
END
$fn$;

COMMENT ON FUNCTION public.prestador_recibo_mensal_resumo(integer, integer, uuid) IS
  'Recibos verdes (15/11/2026): UM recibo por pessoa por mês (entregas + limpezas + lavagens + Casa), com linhas, total, dados da empresa, descrição, prazos e texto da retenção. Fonte única da app, do email do dia 1, do painel, do aviso do dia 10 e da trava.';


-- =====================================================================================
-- BLOCO 6 — PONTO 1: "JÁ PASSEI O RECIBO" COM PDF + MARCAR/DESMARCAR PELO PAINEL
-- =====================================================================================
-- A versão antiga (4 parâmetros) muda de nome em vez de ser apagada: assim fica só UMA função
-- chamada driver_mark_invoice_issued e as chamadas da app publicada (3 ou 4 nomes) resolvem
-- sem ambiguidade. O rollback devolve-lhe o nome.
ALTER FUNCTION public.driver_mark_invoice_issued(integer, integer, text, date)
  RENAME TO _driver_mark_invoice_issued_v1;
REVOKE ALL ON FUNCTION public._driver_mark_invoice_issued_v1(integer, integer, text, date) FROM PUBLIC, anon, authenticated;

CREATE FUNCTION public.driver_mark_invoice_issued(
  p_year integer,
  p_month integer,
  p_numero text,
  p_data date DEFAULT NULL::date,
  p_pdf_path text DEFAULT NULL::text)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $fn$
DECLARE
  v_uid uuid := auth.uid();
  v_pdf text := nullif(btrim(coalesce(p_pdf_path, '')), '');
  v_p jsonb;
  v_total numeric := 0;
  v_n int := 0;
  v_final text;
BEGIN
  IF v_uid IS NULL THEN RAISE EXCEPTION 'sem_sessao'; END IF;
  IF coalesce(btrim(p_numero), '') = '' THEN RAISE EXCEPTION 'numero_em_falta'; END IF;
  IF p_year IS NULL OR p_month IS NULL OR p_month NOT BETWEEN 1 AND 12 OR p_year NOT BETWEEN 2024 AND 2100 THEN
    RAISE EXCEPTION 'mes_invalido';
  END IF;
  -- O PDF é opcional aqui (a app publicada não o manda); a app nova obriga a anexar.
  IF v_pdf IS NOT NULL THEN
    PERFORM public._recibo_validar_pdf(v_uid, p_year, p_month, v_pdf);
  END IF;

  -- Total do mês = tudo o que a pessoa fez (ponto 2). Para quem só faz entregas é o mesmo
  -- valor de hoje; "entregas" continua a ser o n.º de entregas.
  v_p := public._recibo_resumo_calc(p_year, p_month, v_uid) -> 'prestador';
  v_total := coalesce((v_p ->> 'total')::numeric, 0);
  v_n := coalesce((SELECT (l ->> 'quantidade')::int
                   FROM jsonb_array_elements(coalesce(v_p -> 'linhas', '[]'::jsonb)) l
                   WHERE l ->> 'servico' = 'entregas' LIMIT 1), 0);

  INSERT INTO public.driver_monthly_invoices AS m
    (user_id, ano, mes, total_faturar, entregas, recibo_numero, recibo_data, marcado_em, recibo_pdf_path)
  VALUES
    (v_uid, p_year, p_month, v_total, v_n, btrim(p_numero),
     coalesce(p_data, (now() AT TIME ZONE 'Europe/Lisbon')::date), now(), v_pdf)
  ON CONFLICT (user_id, ano, mes) DO UPDATE
    SET recibo_numero = excluded.recibo_numero,
        recibo_data = excluded.recibo_data,
        total_faturar = excluded.total_faturar,
        entregas = excluded.entregas,
        marcado_em = now(),
        -- a app antiga (sem PDF) nunca apaga um PDF que já lá esteja
        recibo_pdf_path = coalesce(excluded.recibo_pdf_path, m.recibo_pdf_path),
        recibo_verificacao = CASE WHEN excluded.recibo_pdf_path IS NOT NULL
                                       AND excluded.recibo_pdf_path IS DISTINCT FROM m.recibo_pdf_path
                                  THEN NULL ELSE m.recibo_verificacao END
  RETURNING m.recibo_pdf_path INTO v_final;

  RETURN jsonb_build_object(
    'ok', true,
    'total_faturar', v_total,
    'entregas', v_n,
    'linhas', coalesce(v_p -> 'linhas', '[]'::jsonb),
    'tem_pdf', v_final IS NOT NULL,
    'recibo_pdf_path', v_final);
END
$fn$;

COMMENT ON FUNCTION public.driver_mark_invoice_issued(integer, integer, text, date, text) IS
  'Recibos verdes (15/11/2026): "Já passei o recibo" de qualquer prestador (estafeta, limpeza, lavagem, Casa). p_pdf_path opcional no servidor (app publicada); sem PDF o recibo não conta para a trava.';

-- Painel: marcar à mão (recibo que chegou por email/WhatsApp), com motivo, auditado.
CREATE OR REPLACE FUNCTION public.admin_recibo_prestador_marcar(
  p_user_id uuid,
  p_year integer,
  p_month integer,
  p_numero text,
  p_data date DEFAULT NULL::date,
  p_pdf_path text DEFAULT NULL::text,
  p_motivo text DEFAULT NULL::text)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $fn$
DECLARE
  v_motivo text := nullif(btrim(coalesce(p_motivo, '')), '');
  v_pdf text := nullif(btrim(coalesce(p_pdf_path, '')), '');
  v_antes jsonb;
  v_p jsonb;
  v_total numeric := 0;
  v_n int := 0;
  v_final text;
BEGIN
  IF NOT public.is_admin() THEN RAISE EXCEPTION 'admin_required' USING ERRCODE = '42501'; END IF;
  IF p_user_id IS NULL THEN RAISE EXCEPTION 'faltam_argumentos'; END IF;
  IF p_year IS NULL OR p_month IS NULL OR p_month NOT BETWEEN 1 AND 12 OR p_year NOT BETWEEN 2024 AND 2100 THEN
    RAISE EXCEPTION 'mes_invalido';
  END IF;
  IF coalesce(btrim(p_numero), '') = '' THEN RAISE EXCEPTION 'numero_em_falta'; END IF;
  IF v_motivo IS NULL OR length(v_motivo) < 5 THEN
    RAISE EXCEPTION 'motivo_obrigatorio' USING HINT = 'Escreva porque marca à mão (mínimo 5 letras).';
  END IF;
  IF v_pdf IS NOT NULL THEN
    PERFORM public._recibo_validar_pdf(p_user_id, p_year, p_month, v_pdf);
  END IF;

  SELECT to_jsonb(m) INTO v_antes FROM public.driver_monthly_invoices m
  WHERE m.user_id = p_user_id AND m.ano = p_year AND m.mes = p_month;

  v_p := public._recibo_resumo_calc(p_year, p_month, p_user_id) -> 'prestador';
  v_total := coalesce((v_p ->> 'total')::numeric, 0);
  v_n := coalesce((SELECT (l ->> 'quantidade')::int
                   FROM jsonb_array_elements(coalesce(v_p -> 'linhas', '[]'::jsonb)) l
                   WHERE l ->> 'servico' = 'entregas' LIMIT 1), 0);

  INSERT INTO public.driver_monthly_invoices AS m
    (user_id, ano, mes, total_faturar, entregas, recibo_numero, recibo_data, marcado_em, recibo_pdf_path)
  VALUES
    (p_user_id, p_year, p_month, v_total, v_n, btrim(p_numero),
     coalesce(p_data, (now() AT TIME ZONE 'Europe/Lisbon')::date), now(), v_pdf)
  ON CONFLICT (user_id, ano, mes) DO UPDATE
    SET recibo_numero = excluded.recibo_numero,
        recibo_data = excluded.recibo_data,
        total_faturar = excluded.total_faturar,
        entregas = excluded.entregas,
        marcado_em = now(),
        recibo_pdf_path = coalesce(excluded.recibo_pdf_path, m.recibo_pdf_path),
        recibo_verificacao = CASE WHEN excluded.recibo_pdf_path IS NOT NULL
                                       AND excluded.recibo_pdf_path IS DISTINCT FROM m.recibo_pdf_path
                                  THEN NULL ELSE m.recibo_verificacao END
  RETURNING m.recibo_pdf_path INTO v_final;

  PERFORM public.log_admin_action('recibo_verde_marcar_admin'::text, 'driver_monthly_invoices'::text, p_user_id::text,
    jsonb_build_object('ano', p_year, 'mes', p_month, 'numero', btrim(p_numero), 'data', p_data,
                       'pdf', v_final, 'motivo', v_motivo, 'antes', v_antes));

  RETURN jsonb_build_object('ok', true, 'total_faturar', v_total, 'tem_pdf', v_final IS NOT NULL,
                            'recibo_pdf_path', v_final);
END
$fn$;

-- Painel: desmarcar à mão (recibo errado), com motivo, auditado. O ficheiro fica guardado.
CREATE OR REPLACE FUNCTION public.admin_recibo_prestador_desmarcar(
  p_user_id uuid,
  p_year integer,
  p_month integer,
  p_motivo text)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $fn$
DECLARE
  v_motivo text := nullif(btrim(coalesce(p_motivo, '')), '');
  v_antes jsonb;
BEGIN
  IF NOT public.is_admin() THEN RAISE EXCEPTION 'admin_required' USING ERRCODE = '42501'; END IF;
  IF p_user_id IS NULL OR p_year IS NULL OR p_month IS NULL THEN RAISE EXCEPTION 'faltam_argumentos'; END IF;
  IF v_motivo IS NULL OR length(v_motivo) < 5 THEN
    RAISE EXCEPTION 'motivo_obrigatorio' USING HINT = 'Escreva porque desmarca (mínimo 5 letras).';
  END IF;

  SELECT to_jsonb(m) INTO v_antes FROM public.driver_monthly_invoices m
  WHERE m.user_id = p_user_id AND m.ano = p_year AND m.mes = p_month
  FOR UPDATE;
  IF v_antes IS NULL THEN RAISE EXCEPTION 'recibo_nao_encontrado'; END IF;

  UPDATE public.driver_monthly_invoices
     SET recibo_numero = NULL, recibo_data = NULL, marcado_em = NULL,
         recibo_pdf_path = NULL, recibo_verificacao = NULL
   WHERE user_id = p_user_id AND ano = p_year AND mes = p_month;

  PERFORM public.log_admin_action('recibo_verde_desmarcar_admin'::text, 'driver_monthly_invoices'::text, p_user_id::text,
    jsonb_build_object('ano', p_year, 'mes', p_month, 'motivo', v_motivo, 'antes', v_antes));

  RETURN jsonb_build_object('ok', true,
    'nota', 'Recibo desmarcado. O ficheiro continua guardado no armazenamento; só deixa de contar como entregue.');
END
$fn$;


-- =====================================================================================
-- BLOCO 7 — PONTO 4: A TRAVA DO PAGAMENTO
-- =====================================================================================
-- Como funciona, de ponta a ponta:
--  1) A trava olha para "hoje" (Lisboa). Para cada mês desde novembro/2026 cujo prazo (dia 10
--     do mês seguinte) já passou, vê se a pessoa tinha de passar recibo (trabalhou nesse mês,
--     não é demo, não é a conta do dono salvo fecho_dono_passa_recibo) e se o recibo está
--     marcado COM PDF. Faltando um, a pessoa está "retida".
--  2) Um gatilho nas 4 tabelas de acertos (estafeta, limpeza, lavagem, Casa) impede passar uma
--     linha para "paid" quando a Bora é que paga, a pessoa está retida e ninguém soltou essa
--     semana. Cobre TODOS os caminhos (admin_set_settlement_state, admin_mark_settlement_paid,
--     admin_marcar_acerto_pago, admin_mark_cleaner_settlements_paid,
--     admin_mark_carwash_settlement_paid, admin_casa_acerto_marcar, admin_set_settlement_status
--     e qualquer UPDATE direto).
--  3) "received" (a pessoa paga à Bora) nunca é travado. Se na mesma semana a pessoa deve mais
--     do que recebe (saldo da semana <= 0, a conta da vista do acerto unificado + Casa), a linha
--     positiva é só compensação da dívida e passa, como hoje.
--  4) Nada muda nos valores: as linhas ficam "pending" com o mesmo dinheiro. Quando o PDF entra,
--     a trava cai sozinha e todas as semanas guardadas podem ser pagas (é a acumulação: cada
--     semana sai com o seu valor, todas juntas no primeiro acerto a seguir).
--  5) O admin pode soltar uma semana de uma pessoa com motivo escrito (auditado).

CREATE TABLE public.recibo_retencao_solturas (
  user_id    uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  semana     date NOT NULL,                       -- segunda-feira (Lisboa) da semana solta
  motivo     text NOT NULL CHECK (length(btrim(motivo)) >= 5),
  origem     jsonb NOT NULL DEFAULT '{}'::jsonb,  -- de que linha do painel veio (tipo, id)
  criado_por uuid,
  criado_em  timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (user_id, semana)
);
COMMENT ON TABLE public.recibo_retencao_solturas IS
  'Recibos verdes (15/11/2026): semanas soltas à mão pelo admin (com motivo) apesar de faltar o recibo. Só se escreve por admin_soltar_retido_recibo.';
ALTER TABLE public.recibo_retencao_solturas ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.recibo_retencao_solturas FROM anon, authenticated;
GRANT SELECT ON public.recibo_retencao_solturas TO authenticated;
CREATE POLICY recibo_solturas_admin_ler ON public.recibo_retencao_solturas
  FOR SELECT TO authenticated USING ((SELECT public.is_admin()));

-- O cálculo da trava para uma pessoa num dia.
CREATE OR REPLACE FUNCTION public._recibo_trava_calc(p_user_id uuid, p_hoje date)
RETURNS jsonb
LANGUAGE plpgsql
STABLE SECURITY DEFINER
SET search_path TO 'public'
AS $fn$
DECLARE
  v_hoje date := coalesce(p_hoje, (now() AT TIME ZONE 'Europe/Lisbon')::date);
  v_mes date := date '2026-11-01';      -- outubro fica de fora (era em nome individual)
  v_prazo date;
  v_ano int;
  v_m int;
  v_p jsonb;
  v_falta jsonb := '[]'::jsonb;
  v_nomes text[] := ARRAY[]::text[];
  v_nome text;
  v_voltas int := 0;
BEGIN
  IF p_user_id IS NULL THEN
    RETURN jsonb_build_object('retido', false, 'excluido', 'sem_pessoa', 'calculado_para', v_hoje);
  END IF;
  IF NOT coalesce((SELECT (s.value #>> '{}')::boolean FROM public.platform_settings s
                   WHERE s.key = 'recibos_trava_ativa'), true) THEN
    RETURN jsonb_build_object('retido', false, 'excluido', 'trava_desligada', 'calculado_para', v_hoje);
  END IF;
  IF public.is_demo_user(p_user_id) OR coalesce(public.is_demo_driver(p_user_id::text), false) THEN
    RETURN jsonb_build_object('retido', false, 'excluido', 'conta_demo', 'calculado_para', v_hoje);
  END IF;
  IF public._recibo_e_conta_dono(p_user_id)
     AND NOT coalesce((SELECT (s.value #>> '{}')::boolean FROM public.platform_settings s
                       WHERE s.key = 'fecho_dono_passa_recibo'), false) THEN
    RETURN jsonb_build_object('retido', false, 'excluido', 'conta_dono', 'calculado_para', v_hoje);
  END IF;

  LOOP
    v_prazo := (v_mes + interval '1 month')::date + 9;   -- dia 10 do mês seguinte
    EXIT WHEN v_hoje <= v_prazo OR v_voltas > 120;       -- prazo ainda não passou (nem o dos meses seguintes)
    v_voltas := v_voltas + 1;
    v_ano := extract(year FROM v_mes)::int;
    v_m := extract(month FROM v_mes)::int;
    IF NOT EXISTS (SELECT 1 FROM public.driver_monthly_invoices i
                   WHERE i.user_id = p_user_id AND i.ano = v_ano AND i.mes = v_m
                     AND i.recibo_pdf_path IS NOT NULL) THEN
      v_p := public._recibo_resumo_calc(v_ano, v_m, p_user_id) -> 'prestador';
      IF coalesce((v_p ->> 'conta_para_trava')::boolean, false) THEN
        v_nome := (ARRAY['janeiro','fevereiro','março','abril','maio','junho','julho',
                         'agosto','setembro','outubro','novembro','dezembro'])[v_m] || ' de ' || v_ano;
        v_nomes := array_append(v_nomes, v_nome);
        v_falta := v_falta || jsonb_build_array(jsonb_build_object(
          'ano', v_ano, 'mes', v_m, 'nome', v_nome, 'total', v_p -> 'total',
          'estado', v_p ->> 'estado', 'anexar_ate', v_prazo));
      END IF;
    END IF;
    v_mes := (v_mes + interval '1 month')::date;
  END LOOP;

  IF jsonb_array_length(v_falta) = 0 THEN
    RETURN jsonb_build_object('retido', false, 'meses_em_falta', v_falta, 'calculado_para', v_hoje);
  END IF;
  RETURN jsonb_build_object(
    'retido', true,
    'motivo', 'Retido — falta o recibo verde de ' || array_to_string(v_nomes, ', '),
    'texto_semanal', 'O teu pagamento desta semana fica guardado até anexares o recibo verde de '
                     || array_to_string(v_nomes, ', ') || ' na app, em Ganhos.',
    'meses_em_falta', v_falta,
    'calculado_para', v_hoje);
END
$fn$;

-- Linhas por pagar em que a Bora paga (o dinheiro "guardado"). Só soma o que já está nas
-- linhas; não calcula nada de novo.
CREATE OR REPLACE FUNCTION public._recibo_por_pagar(p_user_id uuid)
RETURNS jsonb
LANGUAGE sql
STABLE SECURITY DEFINER
SET search_path TO 'public'
AS $fn$
  WITH l AS (
    SELECT 'driver'::text AS tipo, s.id, public._recibo_semana(s.week_start_at) AS semana,
           round(coalesce(s.net_balance, 0) * 100)::bigint AS cents, s.status
    FROM public.driver_weekly_settlements s
    WHERE s.driver_id = p_user_id
       OR s.driver_id IN (SELECT d.id FROM public.drivers d WHERE d.user_id = p_user_id)
    UNION ALL
    SELECT 'cleaner', s.id, public._recibo_semana(s.week_start_at), coalesce(s.net_payout_cents, 0)::bigint, s.status
    FROM public.cleaner_weekly_settlements s
    JOIN public.cleaners c ON c.id = s.cleaner_id
    WHERE c.user_id = p_user_id
    UNION ALL
    SELECT 'washer', s.id, public._recibo_semana(s.week_start_at), coalesce(s.net_payout_cents, 0)::bigint, s.status
    FROM public.washer_weekly_settlements s
    JOIN public.washers w ON w.id = s.washer_id
    WHERE w.user_id = p_user_id
    UNION ALL
    SELECT 'casa', a.id, public._recibo_semana(a.week_start_at),
           (CASE a.direction WHEN 'bora_to_handyman' THEN a.net_payout_cents
                             WHEN 'handyman_to_bora' THEN -a.net_payout_cents
                             ELSE 0 END)::bigint,
           a.status
    FROM public.casa_acertos_semanais a
    WHERE a.user_id = p_user_id)
  SELECT jsonb_build_object(
    'total_cents', coalesce(sum(l.cents), 0),
    'semanas', coalesce(jsonb_agg(jsonb_build_object('tipo', l.tipo, 'id', l.id, 'semana', l.semana,
                                                     'cents', l.cents, 'estado', l.status)
                                  ORDER BY l.semana, l.tipo), '[]'::jsonb))
  FROM l
  WHERE l.cents > 0 AND l.status NOT IN ('paid', 'received', 'cancelled')
$fn$;

-- Saldo de uma pessoa numa semana (todas as linhas, todos os estados menos cancelado): a conta
-- da vista do acerto unificado (estafeta + limpeza + lavagem, já com a dívida por abater) + Casa.
-- <= 0 quer dizer que a pessoa deve à Bora nessa semana: a linha positiva é compensação.
CREATE OR REPLACE FUNCTION public._recibo_semana_saldo_cents(p_user_id uuid, p_semana date)
RETURNS bigint
LANGUAGE sql
STABLE SECURITY DEFINER
SET search_path TO 'public'
AS $fn$
  -- Conserto do Juiz (16/11, R1a-1): somar só os papéis ainda por acertar (o que já foi pago,
  -- recebido ou cancelado não conta). total_cents da vista = líquido − dívida por abater.
  SELECT (coalesce((SELECT sum((p.val->>'liquido_cents')::bigint
                               - CASE WHEN coalesce((p.val->>'divida_ja_abatida')::boolean, false) THEN 0
                                      ELSE coalesce((p.val->>'divida_cents')::bigint, 0) END)
                    FROM public.v_acerto_semanal_unificado v, jsonb_each(v.detalhe) AS p(papel, val)
                    WHERE v.user_id = p_user_id AND v.semana = p_semana
                      AND coalesce(p.val->>'estado', '') NOT IN ('paid', 'received', 'cancelled')), 0)
        + coalesce((SELECT sum(CASE a.direction WHEN 'bora_to_handyman' THEN a.net_payout_cents
                                                WHEN 'handyman_to_bora' THEN -a.net_payout_cents
                                                ELSE 0 END)
                    FROM public.casa_acertos_semanais a
                    WHERE a.user_id = p_user_id
                      AND a.status NOT IN ('cancelled', 'received', 'paid')
                      AND public._recibo_semana(a.week_start_at) = p_semana), 0))::bigint
$fn$;

-- O gatilho: segura o momento de pagar. Não muda nenhum valor.
CREATE OR REPLACE FUNCTION public._recibo_trava_pagamento()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $fn$
DECLARE
  v_tipo text := TG_ARGV[0];
  v_row jsonb;
  v_cents bigint;
  v_uid uuid;
  v_sem date;
  v_trava jsonb;
  v_solta text;
BEGIN
  -- Só interessa a passagem para "paid" (a Bora paga). "received" nunca é travado.
  IF NEW.status IS DISTINCT FROM 'paid' OR OLD.status IS NOT DISTINCT FROM 'paid' THEN
    RETURN NEW;
  END IF;

  v_row := to_jsonb(NEW);
  v_cents := CASE v_tipo
    WHEN 'driver'  THEN round(coalesce((v_row ->> 'net_balance')::numeric, 0) * 100)::bigint
    WHEN 'cleaner' THEN coalesce((v_row ->> 'net_payout_cents')::bigint, 0)
    WHEN 'washer'  THEN coalesce((v_row ->> 'net_payout_cents')::bigint, 0)
    WHEN 'casa'    THEN CASE WHEN v_row ->> 'direction' = 'bora_to_handyman'
                             THEN coalesce((v_row ->> 'net_payout_cents')::bigint, 0) ELSE 0 END
    ELSE 0 END;
  IF v_cents <= 0 THEN
    RETURN NEW;   -- a Bora não paga nada nesta linha
  END IF;

  v_uid := CASE v_tipo
    WHEN 'casa'    THEN (v_row ->> 'user_id')::uuid
    WHEN 'driver'  THEN public.settlement_subject_user_id('driver',  v_row ->> 'driver_id')
    WHEN 'cleaner' THEN public.settlement_subject_user_id('cleaner', v_row ->> 'cleaner_id')
    WHEN 'washer'  THEN public.settlement_subject_user_id('washer',  v_row ->> 'washer_id')
  END;
  IF v_uid IS NULL THEN
    RETURN NEW;
  END IF;

  v_trava := public._recibo_trava_calc(v_uid, public._recibo_hoje());
  IF NOT coalesce((v_trava ->> 'retido')::boolean, false) THEN
    RETURN NEW;
  END IF;

  v_sem := public._recibo_semana(NEW.week_start_at);

  SELECT s.motivo INTO v_solta FROM public.recibo_retencao_solturas s
  WHERE s.user_id = v_uid AND s.semana = v_sem;
  IF v_solta IS NOT NULL THEN
    INSERT INTO public.admin_audit_log (admin_id, action, entity_type, entity_id, entity_id_text, details)
    VALUES (auth.uid(), 'recibo_retido_pago_com_soltura', TG_TABLE_NAME, NEW.id, NEW.id::text,
            jsonb_build_object('user_id', v_uid, 'semana', v_sem, 'cents', v_cents,
                               'motivo_soltura', v_solta, 'meses_em_falta', v_trava -> 'meses_em_falta'));
    RETURN NEW;
  END IF;

  IF public._recibo_semana_saldo_cents(v_uid, v_sem) <= 0 THEN
    RETURN NEW;   -- a pessoa deve mais do que recebe nesta semana: é acerto de dívida, segue como hoje
  END IF;

  RAISE EXCEPTION '%', 'recibo_verde_em_falta: ' || coalesce(v_trava ->> 'motivo', 'Retido — falta o recibo verde')
    USING ERRCODE = 'P0001',
          DETAIL = jsonb_build_object('user_id', v_uid, 'semana', v_sem, 'cents', v_cents,
                                      'meses_em_falta', v_trava -> 'meses_em_falta')::text,
          HINT = 'O prestador anexa o recibo na app (Ganhos) ou o admin solta com motivo (admin_soltar_retido_recibo).';
END
$fn$;

CREATE TRIGGER trg_recibo_trava_pagamento
  BEFORE UPDATE OF status ON public.driver_weekly_settlements
  FOR EACH ROW EXECUTE FUNCTION public._recibo_trava_pagamento('driver');
CREATE TRIGGER trg_recibo_trava_pagamento
  BEFORE UPDATE OF status ON public.cleaner_weekly_settlements
  FOR EACH ROW EXECUTE FUNCTION public._recibo_trava_pagamento('cleaner');
CREATE TRIGGER trg_recibo_trava_pagamento
  BEFORE UPDATE OF status ON public.washer_weekly_settlements
  FOR EACH ROW EXECUTE FUNCTION public._recibo_trava_pagamento('washer');
CREATE TRIGGER trg_recibo_trava_pagamento
  BEFORE UPDATE OF status ON public.casa_acertos_semanais
  FOR EACH ROW EXECUTE FUNCTION public._recibo_trava_pagamento('casa');

-- Porta pública da trava: o próprio (app) ou admin / service_role (Edges) / ligação direta.
CREATE OR REPLACE FUNCTION public.prestador_recibo_trava(p_user_id uuid DEFAULT NULL::uuid)
RETURNS jsonb
LANGUAGE plpgsql
STABLE SECURITY DEFINER
SET search_path TO 'public'
AS $fn$
DECLARE
  v_uid uuid := auth.uid();
  v_priv boolean := public.is_admin()
                    OR coalesce(auth.jwt() ->> 'role', '') = 'service_role'
                    OR session_user = 'postgres';
  v_alvo uuid;
  v_res jsonb;
BEGIN
  v_alvo := coalesce(p_user_id, v_uid);
  IF v_alvo IS NULL THEN RAISE EXCEPTION 'sem_sessao'; END IF;
  IF NOT v_priv AND v_alvo IS DISTINCT FROM v_uid THEN
    RAISE EXCEPTION 'sem_permissao' USING ERRCODE = '42501';
  END IF;
  v_res := public._recibo_trava_calc(v_alvo, public._recibo_hoje());
  RETURN v_res || jsonb_build_object(
    'user_id', v_alvo,
    'por_pagar', public._recibo_por_pagar(v_alvo),
    'texto_app', CASE WHEN coalesce((v_res ->> 'retido')::boolean, false)
                      THEN 'O teu pagamento fica guardado até anexares o recibo verde em falta na app, em Ganhos. Não se perde: sai todo junto no primeiro pagamento depois de o anexares.'
                 END);
END
$fn$;

COMMENT ON FUNCTION public.prestador_recibo_trava(uuid) IS
  'Recibos verdes (15/11/2026): diz se a pessoa está retida (falta recibo com PDF de um mês desde novembro/2026 cujo dia 10 já passou), o motivo, os meses em falta e o dinheiro guardado (linhas por pagar).';

-- Painel: soltar uma semana de uma pessoa com motivo (auditado). Não paga nada: só permite
-- que o "Marcar pago" dessa semana passe.
CREATE OR REPLACE FUNCTION public.admin_soltar_retido_recibo(
  p_subject_type text,
  p_subject_id text,
  p_week_start date,
  p_motivo text)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $fn$
DECLARE
  v_tipo text := lower(btrim(coalesce(p_subject_type, '')));
  v_id text := btrim(coalesce(p_subject_id, ''));
  v_motivo text := nullif(btrim(coalesce(p_motivo, '')), '');
  v_uid uuid;
  v_ws timestamptz;
  v_sem date;
  v_trava jsonb;
BEGIN
  IF NOT public.is_admin() THEN RAISE EXCEPTION 'admin_required' USING ERRCODE = '42501'; END IF;
  IF v_id = '' OR p_week_start IS NULL THEN RAISE EXCEPTION 'faltam_argumentos'; END IF;
  IF v_motivo IS NULL OR length(v_motivo) < 5 THEN
    RAISE EXCEPTION 'motivo_obrigatorio' USING HINT = 'Escreva porque solta o pagamento (mínimo 5 letras).';
  END IF;

  IF v_tipo = 'user' THEN
    IF v_id !~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$' THEN
      RAISE EXCEPTION 'pessoa_nao_encontrada';
    END IF;
    v_uid := v_id::uuid;
    -- aceita a segunda-feira (Lisboa) ou o domingo (data UTC no verão) da semana
    v_sem := date_trunc('week', (p_week_start + 1)::timestamp)::date;
  ELSIF v_tipo = 'casa' THEN
    SELECT a.user_id, a.week_start_at INTO v_uid, v_ws
    FROM public.casa_acertos_semanais a
    WHERE (a.id::text = v_id OR a.profissional_id::text = v_id OR a.user_id::text = v_id)
      AND public._semana_bate(a.week_start_at, p_week_start)
    ORDER BY a.week_start_at
    LIMIT 1;
  ELSIF v_tipo IN ('driver', 'cleaner', 'washer') THEN
    v_uid := public.settlement_subject_user_id(v_tipo, v_id);
    SELECT x.ws INTO v_ws FROM (
      SELECT s.week_start_at AS ws FROM public.driver_weekly_settlements s
      WHERE v_tipo = 'driver' AND s.driver_id::text = v_id AND public._semana_bate(s.week_start_at, p_week_start)
      UNION ALL
      SELECT s.week_start_at FROM public.cleaner_weekly_settlements s
      WHERE v_tipo = 'cleaner' AND s.cleaner_id::text = v_id AND public._semana_bate(s.week_start_at, p_week_start)
      UNION ALL
      SELECT s.week_start_at FROM public.washer_weekly_settlements s
      WHERE v_tipo = 'washer' AND s.washer_id::text = v_id AND public._semana_bate(s.week_start_at, p_week_start)
    ) x
    LIMIT 1;
  ELSE
    RAISE EXCEPTION 'tipo_invalido' USING HINT = 'Use driver, cleaner, washer, casa ou user.';
  END IF;

  IF v_uid IS NULL THEN RAISE EXCEPTION 'pessoa_nao_encontrada'; END IF;
  IF v_tipo <> 'user' THEN
    IF v_ws IS NULL THEN RAISE EXCEPTION 'acerto_nao_encontrado'; END IF;
    v_sem := public._recibo_semana(v_ws);
  END IF;

  v_trava := public._recibo_trava_calc(v_uid, public._recibo_hoje());

  INSERT INTO public.recibo_retencao_solturas (user_id, semana, motivo, origem, criado_por)
  VALUES (v_uid, v_sem, v_motivo,
          jsonb_build_object('tipo', v_tipo, 'id', v_id, 'week_start', p_week_start), auth.uid())
  ON CONFLICT (user_id, semana) DO UPDATE
    SET motivo = excluded.motivo, origem = excluded.origem,
        criado_por = excluded.criado_por, criado_em = now();

  PERFORM public.log_admin_action('recibo_retido_soltar'::text, 'pessoa'::text, v_uid::text,
    jsonb_build_object('semana', v_sem, 'motivo', v_motivo, 'tipo', v_tipo, 'subject_id', v_id,
                       'estava_retido', coalesce((v_trava ->> 'retido')::boolean, false),
                       'meses_em_falta', v_trava -> 'meses_em_falta'));

  RETURN jsonb_build_object(
    'ok', true,
    'user_id', v_uid,
    'semana', v_sem,
    'motivo', v_motivo,
    'estava_retido', coalesce((v_trava ->> 'retido')::boolean, false),
    'nota', 'Semana solta. Já pode marcar como pago. Nenhum valor mudou.');
END
$fn$;


-- =====================================================================================
-- BLOCO 8 — PONTO 4: AS LISTAS DO PAINEL DIZEM "RETIDO" E O MOTIVO
-- =====================================================================================
-- Cada linha ganha: retido (bool), retido_motivo, retido_solto, retido_solto_motivo,
-- retido_compensa_divida, recibo_meses_em_falta (e retido_erro se algo falhar — a lista nunca
-- parte por causa disto). As funções de hoje mudam de nome (_..._base) e ficam iguais por
-- dentro; o embrulho chama-as e só acrescenta estas chaves.
CREATE OR REPLACE FUNCTION public._recibo_enriquecer(p_itens jsonb, p_modo text, p_semana date DEFAULT NULL::date)
RETURNS jsonb
LANGUAGE plpgsql
STABLE SECURITY DEFINER
SET search_path TO 'public'
AS $fn$
DECLARE
  v_out jsonb := '[]'::jsonb;
  v_it jsonb;
  v_uid uuid;
  v_bora_paga boolean;
  v_pago boolean;
  v_sem date;
  v_cache jsonb := '{}'::jsonb;
  v_trava jsonb;
  v_solta text;
  v_compensa boolean;
  v_hoje date := public._recibo_hoje();
BEGIN
  IF p_itens IS NULL OR jsonb_typeof(p_itens) <> 'array' THEN
    RETURN p_itens;
  END IF;

  FOR v_it IN SELECT t.e FROM jsonb_array_elements(p_itens) AS t(e) LOOP
    BEGIN
      v_uid := NULL; v_bora_paga := false; v_pago := false; v_sem := p_semana; v_solta := NULL;

      IF p_modo = 'semanal' THEN            -- admin_weekly_closeout_list (items)
        IF v_it ->> 'type' IN ('driver', 'cleaner', 'washer') THEN
          v_uid := public.settlement_subject_user_id(v_it ->> 'type', v_it ->> 'subject_id');
        END IF;
        v_bora_paga := (v_it ->> 'direction') = 'bora_pays';
        v_pago := coalesce(v_it ->> 'paid_status', 'pending') IN ('paid', 'received', 'cancelled');
        IF v_it ->> 'week_start_at' IS NOT NULL THEN
          v_sem := public._recibo_semana((v_it ->> 'week_start_at')::timestamptz);
        END IF;
      ELSIF p_modo = 'unificado' THEN       -- admin_acerto_unificado (itens)
        v_uid := (v_it ->> 'user_id')::uuid;
        v_bora_paga := (v_it ->> 'sentido') = 'bora_paga';
        v_pago := coalesce((v_it ->> 'tudo_pago')::boolean, false);
      ELSIF p_modo = 'casa' THEN            -- admin_casa_acertos
        v_uid := (v_it ->> 'user_id')::uuid;
        v_bora_paga := (v_it ->> 'direction') = 'bora_to_handyman'
                       AND coalesce((v_it ->> 'net_payout_cents')::int, 0) > 0;
        v_pago := coalesce(v_it ->> 'status', 'pending') IN ('paid', 'received', 'cancelled');
        v_sem := public._recibo_semana((v_it ->> 'week_start_at')::timestamptz);
      ELSIF p_modo = 'lavagem' THEN         -- admin_list_carwash_settlements
        v_uid := public.settlement_subject_user_id('washer', v_it ->> 'washer_id');
        v_bora_paga := coalesce((v_it ->> 'net_payout_cents')::int, 0) > 0;
        v_pago := coalesce(v_it ->> 'status', 'pending') IN ('paid', 'received', 'cancelled');
        v_sem := public._recibo_semana((v_it ->> 'week_start_at')::timestamptz);
      END IF;

      IF v_uid IS NULL OR NOT v_bora_paga OR v_pago THEN
        v_out := v_out || jsonb_build_array(v_it || jsonb_build_object('retido', false));
        CONTINUE;
      END IF;

      IF v_cache ? v_uid::text THEN
        v_trava := v_cache -> v_uid::text;
      ELSE
        v_trava := public._recibo_trava_calc(v_uid, v_hoje);
        v_cache := v_cache || jsonb_build_object(v_uid::text, v_trava);
      END IF;

      IF NOT coalesce((v_trava ->> 'retido')::boolean, false) THEN
        v_out := v_out || jsonb_build_array(v_it || jsonb_build_object('retido', false));
        CONTINUE;
      END IF;

      SELECT s.motivo INTO v_solta FROM public.recibo_retencao_solturas s
      WHERE s.user_id = v_uid AND s.semana = v_sem;
      v_compensa := v_sem IS NOT NULL AND public._recibo_semana_saldo_cents(v_uid, v_sem) <= 0;

      v_out := v_out || jsonb_build_array(v_it || jsonb_build_object(
        'retido', v_solta IS NULL AND NOT v_compensa,
        'retido_motivo', v_trava ->> 'motivo',
        'retido_solto', v_solta IS NOT NULL,
        'retido_solto_motivo', v_solta,
        'retido_compensa_divida', v_compensa,
        'recibo_meses_em_falta', v_trava -> 'meses_em_falta'));
    EXCEPTION WHEN OTHERS THEN
      v_out := v_out || jsonb_build_array(v_it || jsonb_build_object('retido', NULL, 'retido_erro', SQLERRM));
    END;
  END LOOP;

  RETURN v_out;
END
$fn$;

-- "Acertos da semana" (admin_acertos_semana_screen)
ALTER FUNCTION public.admin_weekly_closeout_list(date) RENAME TO _admin_weekly_closeout_list_base;
REVOKE ALL ON FUNCTION public._admin_weekly_closeout_list_base(date) FROM PUBLIC, anon, authenticated;
CREATE FUNCTION public.admin_weekly_closeout_list(p_week_start date DEFAULT NULL::date)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $fn$
DECLARE
  v_out jsonb;
  v_ws date;
BEGIN
  v_out := public._admin_weekly_closeout_list_base(p_week_start);   -- is_admin() continua lá dentro
  IF v_out IS NULL OR jsonb_typeof(v_out -> 'items') IS DISTINCT FROM 'array' THEN
    RETURN v_out;
  END IF;
  BEGIN
    v_ws := (v_out ->> 'week_start')::date;
    v_out := jsonb_set(v_out, '{items}',
      coalesce(public._recibo_enriquecer(v_out -> 'items', 'semanal',
                 CASE WHEN v_ws IS NULL THEN NULL ELSE date_trunc('week', (v_ws + 1)::timestamp)::date END),
               v_out -> 'items'));
  EXCEPTION WHEN OTHERS THEN
    v_out := v_out || jsonb_build_object('recibos_erro', SQLERRM);
  END;
  RETURN v_out;
END
$fn$;

-- Acerto unificado por pessoa (admin_acerto_unificado_screen, extrato do dono)
ALTER FUNCTION public.admin_acerto_unificado(date) RENAME TO _admin_acerto_unificado_base;
REVOKE ALL ON FUNCTION public._admin_acerto_unificado_base(date) FROM PUBLIC, anon, authenticated;
CREATE FUNCTION public.admin_acerto_unificado(p_semana date DEFAULT NULL::date)
RETURNS jsonb
LANGUAGE plpgsql
STABLE SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $fn$
DECLARE
  v_out jsonb;
BEGIN
  v_out := public._admin_acerto_unificado_base(p_semana);
  IF v_out IS NULL OR jsonb_typeof(v_out -> 'itens') IS DISTINCT FROM 'array' THEN
    RETURN v_out;
  END IF;
  BEGIN
    v_out := jsonb_set(v_out, '{itens}',
      coalesce(public._recibo_enriquecer(v_out -> 'itens', 'unificado', (v_out ->> 'semana')::date),
               v_out -> 'itens'));
  EXCEPTION WHEN OTHERS THEN
    v_out := v_out || jsonb_build_object('recibos_erro', SQLERRM);
  END;
  RETURN v_out;
END
$fn$;

-- Acertos da Casa (admin_casa_acertos_tab)
ALTER FUNCTION public.admin_casa_acertos(date) RENAME TO _admin_casa_acertos_base;
REVOKE ALL ON FUNCTION public._admin_casa_acertos_base(date) FROM PUBLIC, anon, authenticated;
CREATE FUNCTION public.admin_casa_acertos(p_week_start date DEFAULT NULL::date)
RETURNS jsonb
LANGUAGE plpgsql
STABLE SECURITY DEFINER
SET search_path TO 'public'
AS $fn$
DECLARE
  v_out jsonb;
BEGIN
  v_out := public._admin_casa_acertos_base(p_week_start);
  IF v_out IS NULL OR jsonb_typeof(v_out) <> 'array' THEN
    RETURN v_out;
  END IF;
  BEGIN
    v_out := coalesce(public._recibo_enriquecer(v_out, 'casa', NULL), v_out);
  EXCEPTION WHEN OTHERS THEN
    RAISE WARNING 'admin_casa_acertos: estado dos recibos verdes indisponível (%)', SQLERRM;
  END;
  RETURN v_out;
END
$fn$;

-- Acertos da lavagem (admin_carwash_screen)
ALTER FUNCTION public.admin_list_carwash_settlements(text) RENAME TO _admin_list_carwash_settlements_base;
REVOKE ALL ON FUNCTION public._admin_list_carwash_settlements_base(text) FROM PUBLIC, anon, authenticated;
CREATE FUNCTION public.admin_list_carwash_settlements(p_status text DEFAULT NULL::text)
RETURNS jsonb
LANGUAGE plpgsql
STABLE SECURITY DEFINER
SET search_path TO 'public'
AS $fn$
DECLARE
  v_out jsonb;
BEGIN
  v_out := public._admin_list_carwash_settlements_base(p_status);
  IF v_out IS NULL OR jsonb_typeof(v_out) <> 'array' THEN
    RETURN v_out;
  END IF;
  BEGIN
    v_out := coalesce(public._recibo_enriquecer(v_out, 'lavagem', NULL), v_out);
  EXCEPTION WHEN OTHERS THEN
    RAISE WARNING 'admin_list_carwash_settlements: estado dos recibos verdes indisponível (%)', SQLERRM;
  END;
  RETURN v_out;
END
$fn$;


-- =====================================================================================
-- BLOCO 9 — PONTO 2: AVISO DO DIA 10 A TODOS OS PRESTADORES + TAREFA 89
-- =====================================================================================
-- Notifica uma pessoa pelos caminhos que já existem: notificação dentro da app
-- (_push_in_app_notification), push pela porta única das mensagens do painel
-- (notify-admin-message, serve estafeta, limpeza, lavagem e Casa) e email pela
-- agentes-email-enviar (o mesmo caminho do robô dos documentos). Falhas vão para
-- notification_failures e nunca partem a transação.
CREATE OR REPLACE FUNCTION public._recibo_notificar_prestador(
  p_user_id uuid,
  p_titulo text,
  p_corpo text,
  p_assunto text,
  p_texto_email text,
  p_ref text)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $fn$
DECLARE
  v_url text;
  v_srk text;
  v_key text;
  v_hdr jsonb;
  v_to text;
  v_inapp uuid;
  v_push bigint;
  v_mail bigint;
BEGIN
  IF p_user_id IS NULL OR public.is_demo_user(p_user_id) THEN
    RETURN jsonb_build_object('ok', false, 'motivo', 'sem_pessoa_ou_demo');
  END IF;

  v_inapp := public._push_in_app_notification(p_user_id, 'recibo_verde', p_titulo, p_corpo, p_ref);

  SELECT decrypted_secret INTO v_url FROM vault.decrypted_secrets WHERE name = 'project_url' LIMIT 1;
  SELECT decrypted_secret INTO v_srk FROM vault.decrypted_secrets WHERE name = 'service_role_key' LIMIT 1;

  BEGIN
    IF v_url IS NOT NULL AND v_srk IS NOT NULL THEN
      SELECT net.http_post(
        url := v_url || '/functions/v1/notify-admin-message',
        headers := jsonb_build_object('Authorization', 'Bearer ' || v_srk, 'Content-Type', 'application/json'),
        body := jsonb_build_object('targetUserId', p_user_id::text, 'title', p_titulo, 'body', p_corpo,
                                   'kind', 'recibo_verde', 'relatedId', coalesce(p_ref, ''))
      ) INTO v_push;
    ELSE
      INSERT INTO public.notification_failures (user_id, kind, source, erro)
      VALUES (p_user_id, 'recibo_verde', '_recibo_notificar_prestador:push', 'vault project_url/service_role_key em falta');
    END IF;
  EXCEPTION WHEN OTHERS THEN
    INSERT INTO public.notification_failures (user_id, kind, source, erro)
    VALUES (p_user_id, 'recibo_verde', '_recibo_notificar_prestador:push', SQLERRM);
  END;

  BEGIN
    SELECT u.email INTO v_to FROM auth.users u WHERE u.id = p_user_id;
    -- Conserto do Juiz (16/11, R1a-2): o email de extratos do prestador manda, se existir.
    v_to := coalesce(nullif(btrim(public.driver_monthly_statement_email(p_user_id::text)), ''), v_to);
    IF v_url IS NOT NULL AND v_to ~ '^[^\s@]+@[^\s@]+\.[A-Za-z]{2,}$' THEN
      SELECT decrypted_secret INTO v_key FROM vault.decrypted_secrets WHERE name = 'sb_secret_backend' LIMIT 1;
      IF v_key IS NOT NULL THEN
        v_hdr := jsonb_build_object('apikey', v_key, 'Content-Type', 'application/json');
      ELSIF v_srk IS NOT NULL THEN
        v_hdr := jsonb_build_object('apikey', v_srk, 'Authorization', 'Bearer ' || v_srk, 'Content-Type', 'application/json');
      END IF;
      -- Conserto do Juiz (16/11, R1a-2): sem email se os emails semanais estiverem desligados
      -- ou se o endereço for de demonstração (o push continua).
      IF coalesce((SELECT (ps.value #>> '{}')::boolean FROM public.platform_settings ps
                    WHERE ps.key = 'weekly_digest_emails_enabled'), false) IS NOT TRUE
         OR public.is_demo_email(v_to) THEN
        v_hdr := NULL;
      END IF;
      IF v_hdr IS NOT NULL THEN
        SELECT net.http_post(
          url := v_url || '/functions/v1/agentes-email-enviar',
          headers := v_hdr,
          body := jsonb_build_object('agente', 'suporte', 'para', v_to, 'assunto', p_assunto,
                                     'texto', p_texto_email,
                                     'idempotencia', 'recibo-verde-' || p_user_id::text || '-' || coalesce(p_ref, ''))
        ) INTO v_mail;
      END IF;
    END IF;
  EXCEPTION WHEN OTHERS THEN
    INSERT INTO public.notification_failures (user_id, kind, source, erro)
    VALUES (p_user_id, 'recibo_verde', '_recibo_notificar_prestador:email', SQLERRM);
  END;

  RETURN jsonb_build_object('ok', true, 'in_app', v_inapp, 'push_request', v_push, 'email_request', v_mail);
END
$fn$;

-- O aviso do dia 10: ao admin (como hoje) e a cada prestador em falta (push + email, texto curto).
-- Sem argumentos = mês anterior (é assim que a tarefa 89 a chama). Não manda duas vezes à
-- mesma pessoa para o mesmo mês (fica registado em admin_audit_log).
CREATE OR REPLACE FUNCTION public.aviso_recibos_prestadores_em_falta(p_year integer DEFAULT NULL::integer, p_month integer DEFAULT NULL::integer)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $fn$
DECLARE
  v_ref date := ((now() AT TIME ZONE 'Europe/Lisbon')::date - interval '1 month')::date;
  v_ano int := coalesce(p_year, extract(year FROM v_ref)::int);
  v_mes int := coalesce(p_month, extract(month FROM v_ref)::int);
  v_ref_txt text;
  v_res jsonb;
  v_lista jsonb;
  v_adq jsonb;
  v_nome_mes text;
  v_trava boolean;
  v_anexar date;
  v_txt text;
  v_req bigint;
  e jsonb;
  v_n int := 0;
  v_valor text;
  v_linhas text;
  v_titulo text;
  v_corpo text;
  v_email text;
BEGIN
  IF NOT (public.is_admin() OR coalesce(auth.jwt() ->> 'role', '') = 'service_role' OR session_user = 'postgres') THEN
    RAISE EXCEPTION 'admin_required' USING ERRCODE = '42501';
  END IF;
  IF v_mes NOT BETWEEN 1 AND 12 THEN RAISE EXCEPTION 'mes_invalido'; END IF;
  IF make_date(v_ano, v_mes, 1) < date '2026-10-01' THEN
    RETURN jsonb_build_object('ok', true, 'nota', 'modelo ainda não estava em vigor');
  END IF;

  v_ref_txt := v_ano || '-' || lpad(v_mes::text, 2, '0');
  v_res := public._recibo_resumo_calc(v_ano, v_mes, NULL);
  v_adq := v_res -> 'adquirente';
  v_nome_mes := v_res ->> 'nome_mes';
  v_trava := coalesce((v_res -> 'regras' ->> 'conta_para_trava')::boolean, false);
  v_anexar := (v_res -> 'regras' ->> 'anexar_ate')::date;

  SELECT coalesce(jsonb_agg(x), '[]'::jsonb) INTO v_lista
  FROM jsonb_array_elements(v_res -> 'prestadores') x
  WHERE coalesce((x ->> 'precisa_recibo')::boolean, false)
    AND NOT coalesce((x ->> 'tem_pdf')::boolean, false);

  IF jsonb_array_length(v_lista) = 0 THEN
    RETURN jsonb_build_object('ok', true, 'mes', v_ref_txt, 'em_falta', 0);
  END IF;

  -- 1) Admin (como hoje, agora com todos os prestadores).
  SELECT string_agg('• ' || coalesce(x ->> 'nome', '?') || ' — '
                    || replace(to_char((x ->> 'total')::numeric, 'FM999990.00'), '.', ',') || ' € ('
                    || CASE WHEN (x ->> 'estado') = 'sem_pdf' THEN 'passou o recibo, falta o PDF' ELSE 'sem recibo' END
                    || ')', chr(10))
  INTO v_txt
  FROM jsonb_array_elements(v_lista) x;
  BEGIN
    SELECT net.http_post(
      url := (SELECT decrypted_secret FROM vault.decrypted_secrets WHERE name = 'project_url') || '/functions/v1/notify-admin-urgent',
      headers := jsonb_build_object('Authorization', 'Bearer ' || (SELECT decrypted_secret FROM vault.decrypted_secrets WHERE name = 'service_role_key'),
                                    'Content-Type', 'application/json'),
      body := jsonb_build_object('kind', 'generic',
                                 'title', 'Recibos verdes em falta (' || v_mes || '/' || v_ano || ')',
                                 'body', left('Estes prestadores ainda não entregaram o recibo verde com PDF:' || chr(10) || v_txt, 900),
                                 'route', '/admin/fecho-mensal',
                                 'ref', 'recibos_prestadores_' || v_ano || '_' || v_mes)
    ) INTO v_req;
  EXCEPTION WHEN OTHERS THEN
    INSERT INTO public.admin_audit_log (action, entity_type, entity_id_text, details)
    VALUES ('recibo_aviso_admin_falhou', 'recibos_verdes', v_ref_txt, jsonb_build_object('erro', SQLERRM));
  END;

  -- 2) Cada prestador — só recibos à sociedade (novembro/2026 em diante).
  IF (v_ano, v_mes) >= (2026, 11) THEN
    FOR e IN SELECT x FROM jsonb_array_elements(v_lista) x LOOP
      CONTINUE WHEN EXISTS (SELECT 1 FROM public.admin_audit_log a
                            WHERE a.action = 'recibo_aviso_prestador'
                              AND a.entity_id_text = e ->> 'user_id'
                              AND a.details ->> 'mes' = v_ref_txt);

      v_valor := replace(to_char((e ->> 'total')::numeric, 'FM999990.00'), '.', ',') || ' €';
      SELECT string_agg('- ' || (l ->> 'nome') || ': ' || (l ->> 'quantidade') || ' ('
                        || replace(to_char((l ->> 'valor')::numeric, 'FM999990.00'), '.', ',') || ' €)', chr(10))
      INTO v_linhas
      FROM jsonb_array_elements(coalesce(e -> 'linhas', '[]'::jsonb)) l;

      IF (e ->> 'estado') = 'sem_pdf' THEN
        v_titulo := 'Falta o PDF do teu recibo verde de ' || v_nome_mes;
        v_corpo := 'Já registaste o recibo de ' || v_valor || ', mas falta o PDF ou a foto. Anexa-o na app, em Ganhos.';
      ELSE
        v_titulo := 'Falta o teu recibo verde de ' || v_nome_mes;
        v_corpo := 'Passa o recibo verde de ' || v_valor || ' à ' || (v_adq ->> 'nome') || ' (NIPC ' || (v_adq ->> 'nif')
                   || ') e anexa-o na app, em Ganhos.';
      END IF;
      IF v_trava THEN
        v_corpo := v_corpo || ' Enquanto faltar, o pagamento semanal fica guardado (não se perde).';
      END IF;

      v_email := 'Olá ' || coalesce(split_part(e ->> 'nome', ' ', 1), '') || ',' || chr(10) || chr(10)
        || 'Ainda não recebemos o teu recibo verde de ' || v_nome_mes || ' de ' || v_ano || '.' || chr(10) || chr(10)
        || 'Valor: ' || v_valor || chr(10)
        || coalesce(v_linhas || chr(10), '')
        || chr(10)
        || 'A quem: ' || (v_adq ->> 'nome') || chr(10)
        || 'NIPC: ' || (v_adq ->> 'nif') || chr(10)
        || 'Morada: ' || (v_adq ->> 'morada') || chr(10)
        || 'Descrição: ' || coalesce(e ->> 'descricao', '') || chr(10) || chr(10)
        || 'Anexa o PDF (ou uma foto) na app, em Ganhos, no botão "Já passei o recibo".' || chr(10)
        || CASE WHEN v_trava
                THEN 'Enquanto faltar, os pagamentos semanais ficam guardados. Não se perdem: saem todos juntos no primeiro pagamento depois de anexares.' || chr(10)
                ELSE '' END
        || chr(10) || 'Obrigado,' || chr(10) || 'Equipa Bora';

      PERFORM public._recibo_notificar_prestador((e ->> 'user_id')::uuid, v_titulo, v_corpo, v_titulo, v_email,
                                                 'recibo-' || v_ref_txt);
      INSERT INTO public.admin_audit_log (action, entity_type, entity_id_text, details)
      VALUES ('recibo_aviso_prestador', 'pessoa', e ->> 'user_id',
              jsonb_build_object('mes', v_ref_txt, 'total', e -> 'total', 'estado', e ->> 'estado'));
      v_n := v_n + 1;
    END LOOP;
  END IF;

  RETURN jsonb_build_object('ok', true, 'mes', v_ref_txt, 'em_falta', jsonb_array_length(v_lista),
                            'prestadores_avisados', v_n, 'anexar_ate', v_anexar, 'request_id_admin', v_req);
END
$fn$;

COMMENT ON FUNCTION public.aviso_recibos_prestadores_em_falta(integer, integer) IS
  'Recibos verdes (15/11/2026): aviso do dia 10 (tarefa 89) a todos os prestadores sem recibo com PDF do mês anterior — admin + push + email. Substitui o aviso_recibos_estafetas_em_falta (que fica, sem uso, para rollback).';

-- Tarefa 89: mesmo horário (dia 10, 09h Lisboa), passa a chamar o aviso novo.
SELECT cron.alter_job(
  89,
  command := $cmd$ SELECT public.aviso_recibos_prestadores_em_falta() WHERE extract(hour FROM (now() AT TIME ZONE 'Europe/Lisbon')) = 9; $cmd$);


-- =====================================================================================
-- BLOCO 10 — PONTO 4e: PAGAMENTO AUTOMÁTICO RESPEITA A TRAVA
-- (ZONA PROTEGIDA ADJACENTE — ver cabeçalho. Tarefa 2 está DESLIGADA; tabela payouts é lixo.)
-- =====================================================================================
-- Igual à função de hoje (md5 conferido no bloco 0) + o salto de quem está retido.
CREATE OR REPLACE FUNCTION public.auto_payout_pending(p_min_balance numeric DEFAULT 10.0)
RETURNS integer
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
r           RECORD;
v_balance   NUMERIC(12, 2);
v_count     INT := 0;
v_uid       uuid;
BEGIN
IF p_min_balance <= 0 THEN
RAISE EXCEPTION 'auto_payout_pending: p_min_balance must be > 0';
END IF;
FOR r IN
SELECT user_id, user_type
FROM public.user_balance_snapshots
WHERE user_type IN ('driver', 'restaurant')
AND balance >= p_min_balance
LOOP
-- 15/11/2026 (recibos verdes, ponto 4e): quem tem recibo verde em falta não recebe pagamento
-- automático. Nada é apagado nem mudado: o saldo fica onde está e sai quando o recibo chegar.
IF r.user_type = 'driver' THEN
v_uid := public.settlement_subject_user_id('driver', r.user_id);
IF v_uid IS NOT NULL
   AND coalesce((public._recibo_trava_calc(v_uid, public._recibo_hoje()) ->> 'retido')::boolean, false) THEN
INSERT INTO public.admin_audit_log (action, entity_type, entity_id_text, details)
VALUES ('auto_payout_retido_recibo', 'driver', r.user_id, jsonb_build_object('user_id', v_uid));
CONTINUE;
END IF;
END IF;
SELECT COALESCE(SUM(amount), 0)::NUMERIC(12, 2)
INTO v_balance
FROM public.ledger_entries
WHERE user_id = r.user_id AND user_type = r.user_type;
IF v_balance >= p_min_balance THEN
PERFORM public.create_payout(r.user_id, r.user_type, v_balance);
v_count := v_count + 1;
END IF;
END LOOP;
RAISE NOTICE 'auto_payout_pending: % payout(s) created (threshold=EUR%)', v_count, p_min_balance;
RETURN v_count;
END;
$function$;


-- =====================================================================================
-- BLOCO 11 — PERMISSÕES, RECARREGAR A API, RESUMO
-- =====================================================================================
-- Ajudantes internos: fechados a todos menos ao dono (as funções SECURITY DEFINER chamam-nos).
REVOKE ALL ON FUNCTION public._recibo_hoje() FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public._recibo_semana(timestamptz) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public._recibo_dia_util(date, integer) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public._recibo_e_conta_dono(uuid) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public._recibo_validar_pdf(uuid, integer, integer, text) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public._recibo_resumo_calc(integer, integer, uuid) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public._recibo_trava_calc(uuid, date) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public._recibo_por_pagar(uuid) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public._recibo_semana_saldo_cents(uuid, date) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public._recibo_trava_pagamento() FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public._recibo_enriquecer(jsonb, text, date) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public._recibo_notificar_prestador(uuid, text, text, text, text, text) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public._recibo_resumo_calc(integer, integer, uuid) TO service_role;
GRANT EXECUTE ON FUNCTION public._recibo_trava_calc(uuid, date) TO service_role;

-- Funções da API: fechadas a anon; abertas a authenticated (cada uma tem a sua guarda) e service_role.
REVOKE ALL ON FUNCTION public.prestador_recibo_mensal_resumo(integer, integer, uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.prestador_recibo_mensal_resumo(integer, integer, uuid) TO authenticated, service_role;
REVOKE ALL ON FUNCTION public.driver_mark_invoice_issued(integer, integer, text, date, text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.driver_mark_invoice_issued(integer, integer, text, date, text) TO authenticated, service_role;
REVOKE ALL ON FUNCTION public.prestador_recibo_trava(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.prestador_recibo_trava(uuid) TO authenticated, service_role;
REVOKE ALL ON FUNCTION public.admin_recibo_prestador_marcar(uuid, integer, integer, text, date, text, text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.admin_recibo_prestador_marcar(uuid, integer, integer, text, date, text, text) TO authenticated, service_role;
REVOKE ALL ON FUNCTION public.admin_recibo_prestador_desmarcar(uuid, integer, integer, text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.admin_recibo_prestador_desmarcar(uuid, integer, integer, text) TO authenticated, service_role;
REVOKE ALL ON FUNCTION public.admin_soltar_retido_recibo(text, text, date, text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.admin_soltar_retido_recibo(text, text, date, text) TO authenticated, service_role;
REVOKE ALL ON FUNCTION public.aviso_recibos_prestadores_em_falta(integer, integer) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.aviso_recibos_prestadores_em_falta(integer, integer) TO authenticated, service_role;
-- Embrulhos das listas: as mesmas permissões que as funções de hoje tinham.
REVOKE ALL ON FUNCTION public.admin_weekly_closeout_list(date) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.admin_weekly_closeout_list(date) TO authenticated, service_role;
REVOKE ALL ON FUNCTION public.admin_acerto_unificado(date) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.admin_acerto_unificado(date) TO authenticated, service_role;
REVOKE ALL ON FUNCTION public.admin_casa_acertos(date) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.admin_casa_acertos(date) TO authenticated, service_role;
REVOKE ALL ON FUNCTION public.admin_list_carwash_settlements(text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.admin_list_carwash_settlements(text) TO authenticated, service_role;
-- auto_payout_pending: CREATE OR REPLACE mantém as permissões de hoje (postgres + service_role).

NOTIFY pgrst, 'reload schema';

SELECT jsonb_build_object(
  'driver_mark_invoice_issued_versoes',
    (SELECT count(*) FROM pg_proc WHERE pronamespace = 'public'::regnamespace AND proname = 'driver_mark_invoice_issued'),
  'gatilhos_trava', (SELECT count(*) FROM pg_trigger WHERE tgname = 'trg_recibo_trava_pagamento'),
  'bucket', (SELECT count(*) FROM storage.buckets WHERE id = 'recibos-verdes'),
  'politicas_bucket', (SELECT count(*) FROM pg_policies WHERE schemaname = 'storage' AND policyname LIKE 'recibos_verdes_%'),
  'definicoes', (SELECT jsonb_object_agg(key, value) FROM public.platform_settings
                 WHERE key IN ('fecho_dono_passa_recibo', 'recibos_trava_ativa')),
  'tarefa_89', (SELECT command FROM cron.job WHERE jobid = 89),
  'copias_guardadas', (SELECT count(*) FROM public.bkp_fn_recibos_verdes_20261115)
) AS resultado_r1a;


-- =====================================================================================
-- ROLLBACK (comentado — correr só se for preciso desfazer; tudo de uma vez)
-- Fica de fora de propósito: o bucket e as colunas (podem já ter PDFs reais = prova fiscal),
-- a tabela de solturas (histórico; a auditoria também o tem) e a cópia bkp_fn_….
-- =====================================================================================
-- SELECT cron.alter_job(89, command := (SELECT definicao FROM public.bkp_fn_recibos_verdes_20261115 WHERE assinatura = 'cron.job:89'));
-- DROP TRIGGER IF EXISTS trg_recibo_trava_pagamento ON public.driver_weekly_settlements;
-- DROP TRIGGER IF EXISTS trg_recibo_trava_pagamento ON public.cleaner_weekly_settlements;
-- DROP TRIGGER IF EXISTS trg_recibo_trava_pagamento ON public.washer_weekly_settlements;
-- DROP TRIGGER IF EXISTS trg_recibo_trava_pagamento ON public.casa_acertos_semanais;
-- -- listas: tira o embrulho e devolve o nome à função de hoje
-- DROP FUNCTION IF EXISTS public.admin_weekly_closeout_list(date);
-- ALTER FUNCTION public._admin_weekly_closeout_list_base(date) RENAME TO admin_weekly_closeout_list;
-- DROP FUNCTION IF EXISTS public.admin_acerto_unificado(date);
-- ALTER FUNCTION public._admin_acerto_unificado_base(date) RENAME TO admin_acerto_unificado;
-- DROP FUNCTION IF EXISTS public.admin_casa_acertos(date);
-- ALTER FUNCTION public._admin_casa_acertos_base(date) RENAME TO admin_casa_acertos;
-- DROP FUNCTION IF EXISTS public.admin_list_carwash_settlements(text);
-- ALTER FUNCTION public._admin_list_carwash_settlements_base(text) RENAME TO admin_list_carwash_settlements;
-- GRANT EXECUTE ON FUNCTION public.admin_weekly_closeout_list(date) TO authenticated, service_role;
-- GRANT EXECUTE ON FUNCTION public.admin_acerto_unificado(date) TO authenticated, service_role;
-- GRANT EXECUTE ON FUNCTION public.admin_casa_acertos(date) TO authenticated, service_role;
-- GRANT EXECUTE ON FUNCTION public.admin_list_carwash_settlements(text) TO authenticated, service_role;
-- -- "Já passei o recibo": volta a versão de 4 parâmetros
-- DROP FUNCTION IF EXISTS public.driver_mark_invoice_issued(integer, integer, text, date, text);
-- ALTER FUNCTION public._driver_mark_invoice_issued_v1(integer, integer, text, date) RENAME TO driver_mark_invoice_issued;
-- GRANT EXECUTE ON FUNCTION public.driver_mark_invoice_issued(integer, integer, text, date) TO authenticated, service_role;
-- -- pagamento automático: a definição guardada
-- DO $rb$ BEGIN EXECUTE (SELECT definicao FROM public.bkp_fn_recibos_verdes_20261115 WHERE assinatura LIKE '%auto_payout_pending(numeric)' LIMIT 1); END $rb$;
-- -- funções novas (não guardam dados)
-- DROP FUNCTION IF EXISTS public.aviso_recibos_prestadores_em_falta(integer, integer);
-- DROP FUNCTION IF EXISTS public._recibo_notificar_prestador(uuid, text, text, text, text, text);
-- DROP FUNCTION IF EXISTS public._recibo_enriquecer(jsonb, text, date);
-- DROP FUNCTION IF EXISTS public.admin_soltar_retido_recibo(text, text, date, text);
-- DROP FUNCTION IF EXISTS public.prestador_recibo_trava(uuid);
-- DROP FUNCTION IF EXISTS public._recibo_trava_pagamento();
-- DROP FUNCTION IF EXISTS public._recibo_semana_saldo_cents(uuid, date);
-- DROP FUNCTION IF EXISTS public._recibo_por_pagar(uuid);
-- DROP FUNCTION IF EXISTS public._recibo_trava_calc(uuid, date);
-- DROP FUNCTION IF EXISTS public.admin_recibo_prestador_desmarcar(uuid, integer, integer, text);
-- DROP FUNCTION IF EXISTS public.admin_recibo_prestador_marcar(uuid, integer, integer, text, date, text, text);
-- DROP FUNCTION IF EXISTS public.prestador_recibo_mensal_resumo(integer, integer, uuid);
-- DROP FUNCTION IF EXISTS public._recibo_resumo_calc(integer, integer, uuid);
-- DROP FUNCTION IF EXISTS public._recibo_validar_pdf(uuid, integer, integer, text);
-- DROP FUNCTION IF EXISTS public._recibo_e_conta_dono(uuid);
-- DROP FUNCTION IF EXISTS public._recibo_dia_util(date, integer);
-- DROP FUNCTION IF EXISTS public._recibo_semana(timestamptz);
-- DROP FUNCTION IF EXISTS public._recibo_hoje();
-- -- regras do bucket (os ficheiros ficam; só deixa de haver acesso pela app)
-- DROP POLICY IF EXISTS recibos_verdes_proprio_ler ON storage.objects;
-- DROP POLICY IF EXISTS recibos_verdes_proprio_enviar ON storage.objects;
-- DROP POLICY IF EXISTS recibos_verdes_proprio_substituir ON storage.objects;
-- DROP POLICY IF EXISTS recibos_verdes_admin_ler ON storage.objects;
-- DROP POLICY IF EXISTS recibos_verdes_admin_enviar ON storage.objects;
-- DROP POLICY IF EXISTS recibos_verdes_admin_substituir ON storage.objects;
-- UPDATE public.platform_settings SET value = 'false'::jsonb WHERE key = 'recibos_trava_ativa';
-- NOTIFY pgrst, 'reload schema';
