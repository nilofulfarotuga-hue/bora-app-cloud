-- Chat guiado por categoria (2026-07-14) — pedido Danilo.
-- Menu "Sobre o que queres falar?" com categoria -> sub-opção -> resposta pronta,
-- editável pelo admin sem redeploy. Reusa support_chatbot_sessions/messages
-- existentes (não cria histórico paralelo).

CREATE TABLE IF NOT EXISTS public.support_categories (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  slug text NOT NULL UNIQUE,
  label text NOT NULL,
  icon text NOT NULL DEFAULT 'help_outline',
  sort_order int NOT NULL DEFAULT 0,
  active bool NOT NULL DEFAULT true,
  created_at timestamptz DEFAULT now()
);

CREATE TABLE IF NOT EXISTS public.support_category_options (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  category_id uuid NOT NULL REFERENCES public.support_categories(id) ON DELETE CASCADE,
  question text NOT NULL,
  answer_md text NOT NULL,
  sort_order int NOT NULL DEFAULT 0,
  active bool NOT NULL DEFAULT true,
  created_at timestamptz DEFAULT now(),
  updated_at timestamptz DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_support_category_options_category
  ON public.support_category_options (category_id, sort_order);

ALTER TABLE public.support_categories ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.support_category_options ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS support_categories_select_authed ON public.support_categories;
CREATE POLICY support_categories_select_authed ON public.support_categories
  FOR SELECT TO authenticated USING (auth.uid() IS NOT NULL);

DROP POLICY IF EXISTS support_categories_modify_admin ON public.support_categories;
CREATE POLICY support_categories_modify_admin ON public.support_categories
  FOR ALL TO authenticated USING (public.is_admin()) WITH CHECK (public.is_admin());

DROP POLICY IF EXISTS support_category_options_select_authed ON public.support_category_options;
CREATE POLICY support_category_options_select_authed ON public.support_category_options
  FOR SELECT TO authenticated USING (auth.uid() IS NOT NULL);

DROP POLICY IF EXISTS support_category_options_modify_admin ON public.support_category_options;
CREATE POLICY support_category_options_modify_admin ON public.support_category_options
  FOR ALL TO authenticated USING (public.is_admin()) WITH CHECK (public.is_admin());

-- Chat "falar com humano" (Hermes com persona Thayline/Thabyta) reusa a mesma
-- sessão/mensagens do chatbot IA — só muda o `mode`.
ALTER TABLE public.support_chatbot_sessions
  ADD COLUMN IF NOT EXISTS mode text NOT NULL DEFAULT 'ai' CHECK (mode IN ('ai','human_persona')),
  ADD COLUMN IF NOT EXISTS persona_name text,
  ADD COLUMN IF NOT EXISTS escalated_pending bool NOT NULL DEFAULT false;

-- Escalação ao Danilo (passo 3): Hermes não sabe resolver -> fila humana real,
-- surfaçada por push in-system (notify-admin-urgent) + ponte Telegram (Hermes).
CREATE TABLE IF NOT EXISTS public.support_escalations (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  session_id uuid NOT NULL REFERENCES public.support_chatbot_sessions(id) ON DELETE CASCADE,
  user_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  user_role text NOT NULL,
  question text NOT NULL,
  persona_name text,
  status text NOT NULL DEFAULT 'pending' CHECK (status IN ('pending','answered')),
  danilo_reply text,
  telegram_message_id text,
  created_at timestamptz DEFAULT now(),
  answered_at timestamptz
);

CREATE INDEX IF NOT EXISTS idx_support_escalations_status_created
  ON public.support_escalations (status, created_at);

ALTER TABLE public.support_escalations ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS support_escalations_select_own ON public.support_escalations;
CREATE POLICY support_escalations_select_own ON public.support_escalations
  FOR SELECT TO authenticated
  USING (user_id = auth.uid() OR public.is_admin());

DROP POLICY IF EXISTS support_escalations_modify_admin ON public.support_escalations;
CREATE POLICY support_escalations_modify_admin ON public.support_escalations
  FOR ALL TO authenticated USING (public.is_admin()) WITH CHECK (public.is_admin());

-- Watermark agregado (mesmo padrão de red_queue_watermark / real_crash_count_24h):
-- só contagem/timestamp, sem PII, executável por anon — o gatilho do Hermes (VPS)
-- só tem SUPABASE_ANON_KEY, nunca vê a pergunta do cliente aqui.
CREATE OR REPLACE FUNCTION public.support_escalation_watermark()
 RETURNS TABLE(pending_count integer, newest timestamptz, oldest_age_min numeric)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  SELECT
    count(*)::int AS pending_count,
    max(created_at) AS newest,
    COALESCE(EXTRACT(EPOCH FROM (now() - min(created_at))) / 60, 0) AS oldest_age_min
  FROM public.support_escalations
  WHERE status = 'pending';
$function$;

GRANT EXECUTE ON FUNCTION public.support_escalation_watermark() TO anon;

-- Danilo (via admin app OU Hermes/Telegram com a service role key) responde a
-- uma escalação: grava a resposta como mensagem 'assistant' na MESMA sessão
-- (o cliente vê no chat, com o nome da persona) e fecha a escalação.
CREATE OR REPLACE FUNCTION public.admin_reply_escalation(
  p_escalation_id uuid,
  p_reply text
)
 RETURNS boolean
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_session_id uuid;
  v_persona text;
BEGIN
  IF NOT (public.is_admin() OR auth.role() = 'service_role') THEN
    RAISE EXCEPTION 'forbidden';
  END IF;
  IF p_reply IS NULL OR length(trim(p_reply)) = 0 THEN
    RAISE EXCEPTION 'reply vazio';
  END IF;

  SELECT session_id, persona_name INTO v_session_id, v_persona
  FROM public.support_escalations WHERE id = p_escalation_id;

  IF v_session_id IS NULL THEN
    RAISE EXCEPTION 'escalação não encontrada';
  END IF;

  INSERT INTO public.support_chatbot_messages (session_id, role, content)
  VALUES (v_session_id, 'assistant', p_reply);

  UPDATE public.support_escalations
  SET status = 'answered', danilo_reply = p_reply, answered_at = now()
  WHERE id = p_escalation_id;

  UPDATE public.support_chatbot_sessions
  SET escalated_pending = false
  WHERE id = v_session_id;

  RETURN true;
END;
$function$;

GRANT EXECUTE ON FUNCTION public.admin_reply_escalation(uuid, text) TO authenticated, service_role;

-- Seed: categorias iniciais + Q&A prontas (respostas reusam as regras de
-- negócio já citadas no system prompt do support-chatbot — não inventa nada).
INSERT INTO public.support_categories (slug, label, icon, sort_order) VALUES
  ('pedido_restaurante', 'Pedido de restaurante', 'restaurant', 1),
  ('mercado', 'Compras no mercado', 'local_grocery_store', 2),
  ('entrega', 'Entrega / estafeta', 'delivery_dining', 3),
  ('tvde', 'Viagem TVDE', 'local_taxi', 4),
  ('limpeza', 'Serviço de limpeza', 'cleaning_services', 5),
  ('reservas', 'Reservas de mesa', 'event_seat', 6),
  ('conta', 'Conta / perfil', 'person_outline', 7)
ON CONFLICT (slug) DO NOTHING;

INSERT INTO public.support_category_options (category_id, question, answer_md, sort_order)
SELECT c.id, v.question, v.answer, v.sort_order
FROM public.support_categories c
JOIN (VALUES
  ('pedido_restaurante', 'Quero cancelar o meu pedido', 'Antes do restaurante começar a preparar (estado "criado/a preparar", sem estafeta atribuído) o cancelamento é livre com reembolso de 100%. Depois de um estafeta aceitar, aplica-se uma taxa de €2,50. Depois de o estafeta levantar o pedido já não é possível cancelar. Diz-nos o número do pedido para verificarmos o estado.', 1),
  ('pedido_restaurante', 'O meu pedido está atrasado', 'Podes acompanhar o estado em tempo real no ecrã "O meu pedido". Se estiver parado há muito tempo no mesmo estado, indica-nos o número do pedido que verificamos com o restaurante/estafeta.', 2),
  ('mercado', 'Faltou/veio errado um produto', 'Nas compras de mercado (storeShopping) o estafeta regista cada produto como ✅ comprado, ❌ não tinha (reembolsado automaticamente) ou ➕ substituição (cobrada a diferença). Confere o recibo no ecrã do pedido — qualquer diferença já está refletida no valor final.', 1),
  ('mercado', 'Como funciona o reembolso de compras de mercado?', 'Em lojas não-parceiras o estafeta compra fisicamente e fotografa o talão. O reembolso ao estafeta (se aplicável) é processado manualmente pela equipa após ver a foto — não é automático. Reembolsos ao cliente por item em falta são automáticos no recibo final.', 2),
  ('entrega', 'A taxa de entrega está errada', 'A taxa base é €2,50 até 4 km, mais €0,50/km depois disso. Em lojas não-parceiras existe um markup de 15% já incluído no subtotal (não é taxa extra). Indica o número do pedido para revermos o cálculo.', 1),
  ('entrega', 'Não consigo contactar o estafeta', 'Usa o chat dentro do ecrã do pedido para falar diretamente com o estafeta. Se não responder, avisa-nos aqui com o número do pedido.', 2),
  ('tvde', 'Quanto custa a viagem?', 'O valor da viagem TVDE é calculado por rota real (distância + tempo). Se tens um plano ativo, a viagem é cobrada ao valor do plano em vez da tarifa cheia.', 1),
  ('tvde', 'Quero cancelar/alterar a viagem', 'Podes cancelar a viagem no próprio ecrã antes de o motorista chegar. Depois de o motorista estar a caminho pode aplicar-se uma taxa — indica o número da viagem para verificarmos.', 2),
  ('limpeza', 'Como marco/cancelo uma limpeza?', 'Marca o serviço no separador Limpeza indicando data/hora. Para cancelar, usa a opção de cancelamento no ecrã do serviço — indica-nos o número do serviço se precisares de ajuda.', 1),
  ('reservas', 'Qual o valor do pré-pagamento?', 'A reserva de mesa tem um pré-pagamento de €3 (€2 fica para o restaurante quando chegas, €1 é da Bora). Se cancelares com mais de 2h de antecedência tens reembolso total; com menos de 2h ou no-show o valor não é reembolsado.', 1),
  ('conta', 'Esqueci-me da password', 'Podemos enviar-te um link de reposição de password para o email da conta. Confirma o teu nome para avançarmos.', 1),
  ('conta', 'Quero alterar o meu nome/telefone', 'Podemos atualizar nome e telefone da tua conta. Diz-nos os novos dados que a alteração fica pronta a aprovar.', 2)
) AS v(cat_slug, question, answer, sort_order) ON v.cat_slug = c.slug
ON CONFLICT DO NOTHING;
