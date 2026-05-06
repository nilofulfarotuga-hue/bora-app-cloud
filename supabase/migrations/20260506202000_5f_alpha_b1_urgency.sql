-- ═══════════════════════════════════════════════════════════
-- Sessão 5F-α B1 — Urgência em robot_crosstalk + RPCs update
-- ═══════════════════════════════════════════════════════════
--
-- Decisão A4.1 Opção A: manter GRANT authenticated + service_role
-- em agent_ask_robot_b (chatbot v7 chama via userClient/userJwt).
-- Anti-spam vem de support_settings.rate_limit_per_user_day.
--
-- Inclui:
--   1. ALTER ADD COLUMN urgency (CHECK + default 'normal')
--   2. INDEX parcial críticas pendentes
--   3. CREATE OR REPLACE agent_ask_robot_b (+ p_urgency, sanitização)
--      — GRANT preservado por CREATE OR REPLACE (não REVOKE/GRANT)
--   4. DROP + CREATE admin_list_crosstalk (+ p_urgency, +urgency col,
--      ORDER BY CASE críticas primeiro) — RE-GRANT explícito
--   5. UPDATE skill ASK_ROBOT_B playbook v2 + version+1 + updated_at
--   6. DO block validação ROW_COUNT=1
-- ═══════════════════════════════════════════════════════════

-- ───────────────────────────────────────────────────────────
-- 1. ALTER ADD COLUMN urgency
-- ───────────────────────────────────────────────────────────
ALTER TABLE public.robot_crosstalk
  ADD COLUMN IF NOT EXISTS urgency text
    NOT NULL DEFAULT 'normal'
    CHECK (urgency IN ('critical', 'medium', 'normal'));

-- ───────────────────────────────────────────────────────────
-- 2. Index parcial — críticas pendentes (drill-down rápido)
-- ───────────────────────────────────────────────────────────
CREATE INDEX IF NOT EXISTS idx_crosstalk_urgency_critical
  ON public.robot_crosstalk (urgency, status, created_at DESC)
  WHERE urgency = 'critical' AND status = 'pending';

-- ───────────────────────────────────────────────────────────
-- 3. agent_ask_robot_b — adicionar p_urgency
--    GRANT preservado por CREATE OR REPLACE (Opção A — não mexer)
-- ───────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.agent_ask_robot_b(
  p_question         text,
  p_session_id       uuid    DEFAULT NULL,
  p_skill_triggered  text    DEFAULT NULL,
  p_context          jsonb   DEFAULT '{}'::jsonb,
  p_urgency          text    DEFAULT 'normal'
)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_id      uuid;
  v_urgency text;
BEGIN
  -- Sanitização: aceita 3 valores, fallback 'normal' caso contrário.
  -- Não falha hard se Gemini mandar valor inválido.
  v_urgency := CASE
    WHEN p_urgency IN ('critical', 'medium', 'normal') THEN p_urgency
    ELSE 'normal'
  END;

  INSERT INTO robot_crosstalk (
    direction,
    question,
    question_context,
    asked_by,
    session_id,
    skill_triggered,
    urgency
  ) VALUES (
    'a_to_b',
    public._anonymize_pii(p_question),
    COALESCE(p_context, '{}'::jsonb),
    'robot_a',
    p_session_id,
    p_skill_triggered,
    v_urgency
  )
  RETURNING id INTO v_id;

  RETURN v_id;
END;
$$;

-- ───────────────────────────────────────────────────────────
-- 4. admin_list_crosstalk — adicionar p_urgency + col urgency
--    DROP + CREATE porque RETURNS TABLE muda
--    RE-GRANT authenticated + service_role (estado prod 5F)
-- ───────────────────────────────────────────────────────────
DROP FUNCTION IF EXISTS public.admin_list_crosstalk(text, text, integer);
DROP FUNCTION IF EXISTS public.admin_list_crosstalk(text, text, text, integer);

CREATE OR REPLACE FUNCTION public.admin_list_crosstalk(
  p_status     text DEFAULT 'pending',
  p_direction  text DEFAULT 'all',
  p_urgency    text DEFAULT 'all',
  p_limit      integer DEFAULT 50
)
RETURNS TABLE (
  id                uuid,
  created_at        timestamptz,
  direction         text,
  status            text,
  question          text,
  answer            text,
  asked_by          text,
  answered_by       text,
  answered_at       timestamptz,
  skill_triggered   text,
  rag_chunks_count  integer,
  rag_chunks_used   jsonb,
  session_id        uuid,
  question_context  jsonb,
  urgency           text
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF NOT public.is_admin() THEN
    RAISE EXCEPTION 'NOT_ADMIN';
  END IF;

  RETURN QUERY
  SELECT
    c.id,
    c.created_at,
    c.direction,
    c.status,
    c.question,
    c.answer,
    c.asked_by,
    c.answered_by,
    c.answered_at,
    c.skill_triggered,
    COALESCE(jsonb_array_length(c.rag_chunks_used), 0)::integer AS rag_chunks_count,
    c.rag_chunks_used,
    c.session_id,
    c.question_context,
    c.urgency
  FROM robot_crosstalk c
  WHERE (p_status    = 'all' OR c.status    = p_status)
    AND (p_direction = 'all' OR c.direction = p_direction)
    AND (p_urgency   = 'all' OR c.urgency   = p_urgency)
  ORDER BY
    CASE c.urgency
      WHEN 'critical' THEN 1
      WHEN 'medium'   THEN 2
      WHEN 'normal'   THEN 3
      ELSE 4
    END,
    c.created_at DESC
  LIMIT p_limit;
END;
$$;

-- Re-GRANT espelhando estado prod 5F (auditado em A1)
REVOKE ALL ON FUNCTION public.admin_list_crosstalk(text, text, text, integer)
  FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.admin_list_crosstalk(text, text, text, integer)
  TO authenticated, service_role;

-- ───────────────────────────────────────────────────────────
-- 5. UPDATE skill ASK_ROBOT_B playbook v2 + version+1 + updated_at
-- ───────────────────────────────────────────────────────────
UPDATE public.support_skills
SET
  playbook_md = $playbook$
## ASK_ROBOT_B

Quando activar: cliente reporta problema técnico DA APP
(comportamento app — NÃO sobre pedido/pagamento/entrega).

⚠️ NOVA OBRIGAÇÃO (5F-α): classificar urgência em todas as
chamadas via parâmetro `p_urgency`.

## Classificação de Urgência

🔴 **critical** — interrompe uso ou perde dinheiro:
- "Pagamento foi cobrado mas pedido não foi feito"
- "Dinheiro descontado da carteira sem motivo"
- "Conta bloqueada sem aviso"
- "App fecha sempre ao pagar — não consigo fazer pedido"
- "Estafeta cobrou €X a mais e não consigo provar"
- Dados pessoais perdidos / acesso indevido

🟡 **medium** — atrapalha mas tem workaround:
- "App lenta no checkout"
- "Botão Y às vezes não responde"
- "Erro estranho ao tentar editar perfil"
- Crashes não-bloqueantes

🟢 **normal** — comportamento estranho mas não bloqueia:
- "A aparência está estranha em ecrã X"
- "Ícone aparece duplicado"
- "Notificação chegou tarde"

NÃO usar para:
- Estado pedido → ORDER_STATUS
- Pagamento legítimo → skills payment
- Entrega → skills delivery
- Conta legítima → ACCOUNT_UPDATE

Passos:
1. Recolher info técnica: o quê? quando? que ecrã? erro?
2. Classificar urgência conforme tabela acima
3. Soluções básicas se aplicável (medium/normal):
   - Fechar app + reabrir
   - Verificar internet
   - Reiniciar telemóvel
4. Para critical: NÃO sugerir soluções básicas — registar
   imediatamente para análise técnica
5. Chamar agent_ask_robot_b com p_urgency classificado
6. Informar cliente conforme urgência:
   - critical: "Registei como URGENTE. A equipa vai
     analisar imediatamente e contactar-te."
   - medium: "Registei para análise técnica."
   - normal: "Registei. A equipa vai dar uma olhada
     quando puder. Obrigado pelo feedback!"

Exemplo critical:
User: "paguei €15 mas o pedido não foi feito e o dinheiro
       saiu da minha conta"
→ "Lamento muito. Vou registar como URGENTE."
→ agent_ask_robot_b(
    p_question='Pagamento descontado mas pedido não criado',
    p_skill_triggered='ASK_ROBOT_B',
    p_urgency='critical',
    p_context={user_action:'pagamento_cartao'})

Exemplo medium:
User: "às vezes a app fecha quando abro o mapa"
→ "Já tentaste fechar e reabrir?"
User: "sim, intermitente"
→ agent_ask_robot_b(
    p_question='App fecha intermitente ao abrir mapa',
    p_skill_triggered='ASK_ROBOT_B',
    p_urgency='medium',
    p_context={screen_name:'mapa', frequency:'intermitente'})

Exemplo normal:
User: "o ícone do botão de ordens aparece torto"
→ "Obrigado pelo reporte! Vou registar."
→ agent_ask_robot_b(
    p_question='Ícone visualmente torto',
    p_skill_triggered='ASK_ROBOT_B',
    p_urgency='normal',
    p_context={screen_name:'home'})
$playbook$,
  version    = version + 1,
  updated_at = now()
WHERE skill_name = 'ASK_ROBOT_B';

-- ───────────────────────────────────────────────────────────
-- 6. Validação ROW_COUNT=1 — hard-fail se UPDATE não atingiu skill
-- ───────────────────────────────────────────────────────────
DO $$
DECLARE
  v_count integer;
  v_version integer;
BEGIN
  SELECT count(*), max(version) INTO v_count, v_version
  FROM public.support_skills
  WHERE skill_name = 'ASK_ROBOT_B' AND version >= 2;

  IF v_count != 1 THEN
    RAISE EXCEPTION
      '5F-alpha B1: expected 1 ASK_ROBOT_B with version>=2, got %',
      v_count;
  END IF;

  RAISE NOTICE '5F-alpha B1: ASK_ROBOT_B atualizada para version=%', v_version;
END
$$;
