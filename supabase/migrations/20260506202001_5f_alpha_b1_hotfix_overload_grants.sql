-- ═══════════════════════════════════════════════════════════
-- Sessão 5F-α B1 hotfix — drop overload 4-arg + revoke anon/PUBLIC
-- ═══════════════════════════════════════════════════════════
--
-- Detectado durante smokes B1:
--   1. CREATE OR REPLACE com NOVA signature (5 args) NÃO substitui
--      a 4-arg — cria overload. Ambas funções coexistiam.
--      Risco: ambiguidade em chamadas com 4 named args.
--   2. Função nova (5-arg) ganhou EXECUTE TO PUBLIC por default,
--      logo `anon` herdou — regressão segurança vs design 5F.
--
-- Versão 5-arg com p_urgency DEFAULT 'normal' é totalmente
-- backward-compatible: chamadas com 4 args usam o default.
-- Chatbot v7 continua a funcionar até v8 deploy (B2).
-- ═══════════════════════════════════════════════════════════

-- 1. Remove overload 4-arg (5F original)
DROP FUNCTION IF EXISTS public.agent_ask_robot_b(text, uuid, text, jsonb);

-- 2. Remove acesso herdado por default em CREATE OR REPLACE
REVOKE ALL ON FUNCTION public.agent_ask_robot_b(text, uuid, text, jsonb, text)
  FROM PUBLIC, anon;

-- 3. Re-afirma GRANT auth+service_role (Opção A — match prod 5F)
GRANT EXECUTE ON FUNCTION public.agent_ask_robot_b(text, uuid, text, jsonb, text)
  TO authenticated, service_role;
