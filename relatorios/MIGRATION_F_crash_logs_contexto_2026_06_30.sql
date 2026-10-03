-- [F] 2026-06-30 — Enriquecer debug_crash_logs com contexto de aparelho.
-- DB NÃO-financeira (tabela de diagnóstico). Idempotente. Backward-compatible:
-- a função antiga de 6 args é substituída por uma de 10 (novos params DEFAULT
-- NULL). O Dart (main.dart::_logCrashToSupabase) já passa os 10 params nomeados.
--
-- Aplicar via MCP apply_migration (name sugerido: enrich_debug_crash_logs_context).

-- 1) Colunas novas (a tabela já tinha: id, created_at, screen, route,
--    error_message, stack_trace, platform, app_version, extra).
ALTER TABLE public.debug_crash_logs
  ADD COLUMN IF NOT EXISTS device_model    text,
  ADD COLUMN IF NOT EXISTS android_version text,
  ADD COLUMN IF NOT EXISTS gms_status      text,
  ADD COLUMN IF NOT EXISTS user_id         uuid;

-- 2) Remover a assinatura antiga de 6 args (evita ambiguidade de overload).
DROP FUNCTION IF EXISTS public.log_client_crash(text, text, text, text, text, text);

-- 3) Nova função com contexto completo.
CREATE OR REPLACE FUNCTION public.log_client_crash(
  p_screen          text DEFAULT NULL,
  p_route           text DEFAULT NULL,
  p_error_message   text DEFAULT NULL,
  p_stack_trace     text DEFAULT NULL,
  p_platform        text DEFAULT NULL,
  p_app_version     text DEFAULT NULL,
  p_device_model    text DEFAULT NULL,
  p_android_version text DEFAULT NULL,
  p_gms_status      text DEFAULT NULL,
  p_user_id         uuid DEFAULT NULL
) RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_id uuid;
BEGIN
  INSERT INTO public.debug_crash_logs
    (screen, route, error_message, stack_trace, platform, app_version,
     device_model, android_version, gms_status, user_id)
  VALUES
    (p_screen, p_route, left(p_error_message, 8000), left(p_stack_trace, 8000),
     p_platform, p_app_version,
     p_device_model, p_android_version, p_gms_status, p_user_id)
  RETURNING id INTO v_id;
  RETURN v_id;
END;
$function$;

-- 4) (Opcional) índices para o ecrã admin de crash logs filtrar rápido.
CREATE INDEX IF NOT EXISTS idx_debug_crash_logs_created_at
  ON public.debug_crash_logs (created_at DESC);
CREATE INDEX IF NOT EXISTS idx_debug_crash_logs_device_model
  ON public.debug_crash_logs (device_model);
