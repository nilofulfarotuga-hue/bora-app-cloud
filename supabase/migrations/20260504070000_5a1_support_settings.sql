-- Sessão 5A-1 B1 — support_settings (singleton)
-- Configuração global do agente IA suporte. Editável por admin sem redeploy.

CREATE TABLE IF NOT EXISTS public.support_settings (
  id int PRIMARY KEY CHECK (id = 1),
  whatsapp_number text NOT NULL DEFAULT '+351937501673',
  support_email text NOT NULL DEFAULT 'boraappbora@gmail.com',
  chatbot_welcome_text text NOT NULL DEFAULT
    'Olá! Sou a Bora IA. Como posso ajudar?',
  sla_hours int NOT NULL DEFAULT 24,
  gemini_model text NOT NULL DEFAULT 'gemini-1.5-flash',
  rate_limit_per_user_day int NOT NULL DEFAULT 30,
  max_messages_per_session int NOT NULL DEFAULT 30,
  max_output_tokens_per_call int NOT NULL DEFAULT 8000,
  max_user_message_chars int NOT NULL DEFAULT 2000,
  max_tool_iterations int NOT NULL DEFAULT 5,
  shadow_mode bool NOT NULL DEFAULT true,
  support_agent_enabled bool NOT NULL DEFAULT true,
  updated_at timestamptz DEFAULT now()
);

INSERT INTO public.support_settings (id) VALUES (1)
ON CONFLICT (id) DO NOTHING;

ALTER TABLE public.support_settings ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS support_settings_select_authed ON public.support_settings;
CREATE POLICY support_settings_select_authed ON public.support_settings
  FOR SELECT TO authenticated
  USING (auth.uid() IS NOT NULL);

DROP POLICY IF EXISTS support_settings_modify_admin ON public.support_settings;
CREATE POLICY support_settings_modify_admin ON public.support_settings
  FOR ALL TO authenticated
  USING (public.is_admin())
  WITH CHECK (public.is_admin());
