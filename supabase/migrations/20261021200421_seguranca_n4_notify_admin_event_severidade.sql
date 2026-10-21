-- Auditoria de segurança 21/10/2026 (missão geral-noite-21-10, agente N4).
-- A tabela admin_notifications só aceita severity low/medium/high/critical (CHECK).
-- Três funções mandam 'warning': fn_alerta_corrida_convidado e tvde_queixa_criar engoliam o erro
-- (o admin nunca era avisado de corrida de convidado nem de queixa TVDE) e tvde_conformidade_diaria
-- rebentava inteira no dia em que houvesse avisos. Traduz-se aqui, num sítio só, os nomes comuns
-- para a escala da tabela. Não mexe em dinheiro. Privilégios mantêm-se (CREATE OR REPLACE).
-- md5(pg_get_functiondef) antes: 78ec2a175dcb6b1503d71aaccf8c8fbe
CREATE OR REPLACE FUNCTION public.notify_admin_event(p_event_type text, p_severity text, p_summary text, p_entity_type text DEFAULT NULL::text, p_entity_id text DEFAULT NULL::text, p_payload jsonb DEFAULT '{}'::jsonb, p_deep_link text DEFAULT NULL::text)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE v_id uuid;
  v_sev text;
BEGIN
  v_sev := CASE lower(coalesce(p_severity, ''))
             WHEN 'warning' THEN 'medium'
             WHEN 'warn'    THEN 'medium'
             WHEN 'info'    THEN 'low'
             WHEN 'error'   THEN 'high'
             ELSE p_severity
           END;
  INSERT INTO public.admin_notifications (
    event_type, severity, summary,
    entity_type, entity_id, payload, deep_link
  ) VALUES (
    p_event_type, v_sev, p_summary,
    p_entity_type, p_entity_id, COALESCE(p_payload, '{}'::jsonb), p_deep_link
  ) RETURNING id INTO v_id;
  RETURN v_id;
END;
$function$;