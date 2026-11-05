# Proposta — robô do suporte: painel, destaque e skills (05/11/2026)

A bora-tranca recusou o apply_migration nesta sessão ("o Danilo não autorizou (migration)").
Aplicar tal como está, por MCP, com o nome robo_suporte_painel_e_skills, e gravar em
supabase/migrations. Não toca em dinheiro: só leitura, support_settings, support_skills e
skill_suggestions. Autorização: Danilo, 05/11/2026 13:57 (cobre RPCs de leitura, skills e painel).

Depois de aplicar:
1. A "Central do robô do suporte" do painel passa a carregar.
2. Em support-chatbot, tirar o filtro skillSegura (as skills deixam de precisar dele).
3. Em agent_get_my_partner_today, trocar no texto pausar_loja "Pausar a loja" por "Pausar": é esse o nome do botão no painel do parceiro (a janela que abre é que se chama "Pausar a loja").

```sql
DO $patch$
DECLARE
  v_def text := pg_get_functiondef('public.agent_get_my_tokens_history()'::regprocedure);
  a1 text := 'floor(v_saldo * 0.005 / 2 * 100) / 100.0';
BEGIN
  IF position('round(floor(v_saldo' in v_def) > 0 THEN RETURN; END IF;
  IF position(a1 in v_def) = 0 THEN RAISE EXCEPTION 'ancora em falta'; END IF;
  EXECUTE replace(v_def, a1, 'round(floor(v_saldo * 0.005 / 2 * 100) / 100.0, 2)');
END $patch$;

CREATE OR REPLACE FUNCTION public.agent_search_products(p_query text, p_loja text DEFAULT NULL)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path TO 'public', 'extensions' AS $$
DECLARE
  v_q     text := lower(extensions.unaccent(btrim(COALESCE(p_query, ''))));
  v_loja  text;
  v_dest  jsonb;
  v_res   jsonb;
BEGIN
  IF auth.uid() IS NULL THEN RAISE EXCEPTION 'NOT_AUTHENTICATED'; END IF;
  IF length(v_q) < 2 THEN RETURN jsonb_build_object('ok', false, 'erro', 'escreve o produto'); END IF;
  IF NULLIF(btrim(COALESCE(p_loja, '')), '') IS NOT NULL THEN
    SELECT r.id INTO v_loja FROM public.restaurants r
     WHERE r.approval_status = 'approved' AND COALESCE(r.is_active_admin, false)
       AND lower(extensions.unaccent(r.name)) LIKE '%' || lower(extensions.unaccent(btrim(p_loja))) || '%'
     ORDER BY length(r.name) LIMIT 1;
  END IF;
  SELECT COALESCE(jsonb_agg(jsonb_build_object(
           'produto', s.name, 'loja', s.restaurant_name, 'destaque', r.produto_destaque_rotulo,
           'preco_na_app_eur', round(COALESCE(s.display_price, s.price), 2),
           'unidade', s.unit, 'so_maiores_18', COALESCE(s.maior_18, false))), '[]'::jsonb)
    INTO v_dest
    FROM public.restaurants r
    JOIN public.products p ON p.id = r.produto_destaque_id
    CROSS JOIN LATERAL public.assistant_search_products(p.name, r.id, 1, NULL, false) s
   WHERE r.approval_status = 'approved' AND COALESCE(r.is_active_admin, false)
     AND (v_loja IS NULL OR r.id = v_loja)
     AND NULLIF(btrim(COALESCE(r.produto_destaque_rotulo, '')), '') IS NOT NULL
     AND v_q LIKE '%' || lower(extensions.unaccent(btrim(r.produto_destaque_rotulo))) || '%';

  SELECT COALESCE(jsonb_agg(jsonb_build_object(
           'produto', s.name, 'loja', s.restaurant_name,
           'preco_na_app_eur', round(COALESCE(s.display_price, s.price), 2),
           'unidade', s.unit, 'so_maiores_18', COALESCE(s.maior_18, false))), '[]'::jsonb)
    INTO v_res
    FROM public.assistant_search_products(btrim(p_query), v_loja, 8, NULL, false) s;
  v_res := v_dest || v_res;
  RETURN jsonb_build_object('ok', jsonb_array_length(v_res) > 0, 'produtos', v_res,
    'nota', 'Preços da app. Nos mercados o valor final é o do talão.');
END $$;
REVOKE ALL ON FUNCTION public.agent_search_products(text, text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.agent_search_products(text, text) TO authenticated;

ALTER TABLE public.support_settings ADD COLUMN IF NOT EXISTS ferramentas_desligadas text[] NOT NULL DEFAULT '{}';

CREATE OR REPLACE FUNCTION public.admin_suporte_conversas(p_dias integer DEFAULT 30, p_limite integer DEFAULT 100)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path TO 'public' AS $$
BEGIN
  IF NOT public.is_admin() THEN RAISE EXCEPTION 'SO_ADMIN' USING ERRCODE = '42501'; END IF;
  RETURN COALESCE((SELECT jsonb_agg(x.j ORDER BY x.t DESC) FROM (
    SELECT s.started_at t, jsonb_build_object(
      'id', s.id, 'quando', s.started_at, 'papel', s.user_role,
      'nome', COALESCE(NULLIF(u.name, ''), u.email, '—'),
      'mensagens', s.messages_count, 'passou_a_equipa', COALESCE(s.escalated, false),
      'pedido', s.order_id,
      'primeira', (SELECT left(m.content, 120) FROM public.support_chatbot_messages m
                    WHERE m.session_id = s.id AND m.role = 'user' ORDER BY m.created_at LIMIT 1),
      'ferramentas', (SELECT COALESCE(jsonb_agg(DISTINCT m.tool_name), '[]'::jsonb) FROM public.support_chatbot_messages m
                       WHERE m.session_id = s.id AND m.role = 'tool')) j
      FROM public.support_chatbot_sessions s
      LEFT JOIN public.users u ON u.id = s.user_id
     WHERE s.started_at > now() - make_interval(days => GREATEST(1, LEAST(COALESCE(p_dias, 30), 366)))
     ORDER BY s.started_at DESC
     LIMIT LEAST(GREATEST(COALESCE(p_limite, 100), 1), 500)) x), '[]'::jsonb);
END $$;
REVOKE ALL ON FUNCTION public.admin_suporte_conversas(integer, integer) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.admin_suporte_conversas(integer, integer) TO authenticated;

CREATE OR REPLACE FUNCTION public.admin_suporte_conversa(p_sessao uuid)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path TO 'public' AS $$
BEGIN
  IF NOT public.is_admin() THEN RAISE EXCEPTION 'SO_ADMIN' USING ERRCODE = '42501'; END IF;
  RETURN COALESCE((SELECT jsonb_agg(jsonb_build_object(
      'quando', m.created_at, 'papel', m.role, 'texto', m.content,
      'ferramenta', m.tool_name, 'entrada', m.tool_input, 'saida', m.tool_output) ORDER BY m.created_at)
    FROM public.support_chatbot_messages m WHERE m.session_id = p_sessao), '[]'::jsonb);
END $$;
REVOKE ALL ON FUNCTION public.admin_suporte_conversa(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.admin_suporte_conversa(uuid) TO authenticated;

CREATE OR REPLACE FUNCTION public.admin_suporte_sem_resposta(p_dias integer DEFAULT 30)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path TO 'public' AS $$
BEGIN
  IF NOT public.is_admin() THEN RAISE EXCEPTION 'SO_ADMIN' USING ERRCODE = '42501'; END IF;
  RETURN COALESCE((SELECT jsonb_agg(x.j ORDER BY x.t DESC) FROM (
    SELECT q.created_at t, jsonb_build_object(
        'sessao', q.session_id, 'quando', q.created_at, 'pergunta', left(q.content, 300),
        'resposta', left(r.content, 300), 'papel', s.user_role,
        'motivo', CASE WHEN r.content IS NULL THEN 'sem resposta'
                       WHEN r.content ~* 'não consigo ver|nao consigo ver|não tenho acesso|nao tenho acesso|não sei|nao sei|indisponivel|indisponível' THEN 'disse que não sabia'
                       ELSE 'passou à equipa' END) j
      FROM public.support_chatbot_messages q
      JOIN public.support_chatbot_sessions s ON s.id = q.session_id
      LEFT JOIN LATERAL (SELECT m.content FROM public.support_chatbot_messages m
                          WHERE m.session_id = q.session_id AND m.role = 'assistant' AND m.created_at >= q.created_at
                          ORDER BY m.created_at LIMIT 1) r ON true
     WHERE q.role = 'user'
       AND q.created_at > now() - make_interval(days => GREATEST(1, LEAST(COALESCE(p_dias, 30), 366)))
       AND (r.content IS NULL
            OR r.content ~* 'não consigo ver|nao consigo ver|não tenho acesso|nao tenho acesso|não sei|nao sei|indisponivel|indisponível|passar .*equipa|passei .*equipa|confirmar com a equipa')) x), '[]'::jsonb);
END $$;
REVOKE ALL ON FUNCTION public.admin_suporte_sem_resposta(integer) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.admin_suporte_sem_resposta(integer) TO authenticated;

CREATE OR REPLACE FUNCTION public.admin_suporte_config()
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path TO 'public' AS $$
DECLARE s record;
BEGIN
  IF NOT public.is_admin() THEN RAISE EXCEPTION 'SO_ADMIN' USING ERRCODE = '42501'; END IF;
  SELECT gemini_model, ferramentas_desligadas INTO s FROM public.support_settings WHERE id = 1;
  RETURN jsonb_build_object(
    'modelo', s.gemini_model,
    'ferramentas_desligadas', to_jsonb(COALESCE(s.ferramentas_desligadas, '{}')),
    'skills', COALESCE((SELECT jsonb_agg(jsonb_build_object('nome', k.skill_name, 'ativa', k.active, 'modo', k.mode,
        'guia', k.playbook_md) ORDER BY k.skill_name) FROM public.support_skills k), '[]'::jsonb));
END $$;
REVOKE ALL ON FUNCTION public.admin_suporte_config() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.admin_suporte_config() TO authenticated;

CREATE OR REPLACE FUNCTION public.admin_suporte_definir(p_tipo text, p_nome text, p_valor text)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $$
BEGIN
  IF NOT public.is_admin() THEN RAISE EXCEPTION 'SO_ADMIN' USING ERRCODE = '42501'; END IF;
  IF p_tipo = 'skill' THEN
    UPDATE public.support_skills SET active = (p_valor = 'ligar'), updated_at = now() WHERE skill_name = p_nome;
    IF NOT FOUND THEN RETURN jsonb_build_object('ok', false, 'erro', 'skill_nao_encontrada'); END IF;
  ELSIF p_tipo = 'ferramenta' THEN
    UPDATE public.support_settings
       SET ferramentas_desligadas = CASE WHEN p_valor = 'ligar' THEN array_remove(ferramentas_desligadas, p_nome)
                                         ELSE array_append(array_remove(ferramentas_desligadas, p_nome), p_nome) END,
           updated_at = now()
     WHERE id = 1;
  ELSIF p_tipo = 'modelo' THEN
    IF p_valor !~ '^(claude-(sonnet|haiku)-[0-9-]+|gemini-[0-9a-z.-]+)$' THEN
      RETURN jsonb_build_object('ok', false, 'erro', 'modelo_invalido');
    END IF;
    UPDATE public.support_settings SET gemini_model = p_valor, updated_at = now() WHERE id = 1;
  ELSE
    RETURN jsonb_build_object('ok', false, 'erro', 'tipo_invalido');
  END IF;
  INSERT INTO public.admin_audit_log (admin_id, admin_email, action, entity_type, entity_id_text, details)
  VALUES (auth.uid(), auth.jwt()->>'email', 'suporte_' || p_tipo, 'support', p_nome, jsonb_build_object('valor', p_valor));
  RETURN jsonb_build_object('ok', true);
END $$;
REVOKE ALL ON FUNCTION public.admin_suporte_definir(text, text, text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.admin_suporte_definir(text, text, text) TO authenticated;

CREATE OR REPLACE FUNCTION public.admin_suporte_propor_skill(p_pergunta text, p_nome text, p_guia text)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $$
DECLARE v_id uuid;
BEGIN
  IF NOT public.is_admin() THEN RAISE EXCEPTION 'SO_ADMIN' USING ERRCODE = '42501'; END IF;
  IF length(btrim(COALESCE(p_nome, ''))) < 3 OR length(btrim(COALESCE(p_guia, ''))) < 10 THEN
    RETURN jsonb_build_object('ok', false, 'erro', 'nome_e_guia_obrigatorios');
  END IF;
  INSERT INTO public.skill_suggestions (pattern_summary, sample_messages, message_count, suggested_skill_name,
      suggested_mode, suggested_playbook_md, proposal_type, zone_type, source, status)
  VALUES (left(COALESCE(p_pergunta, p_nome), 200), jsonb_build_array(jsonb_build_object('role', 'user', 'content', left(COALESCE(p_pergunta, ''), 500))),
      1, upper(regexp_replace(btrim(p_nome), '[^A-Za-z0-9]+', '_', 'g')), 'read_only', left(p_guia, 2000),
      'new_skill', 'safe', 'admin_painel', 'pending')
  RETURNING id INTO v_id;
  RETURN jsonb_build_object('ok', true, 'id', v_id);
END $$;
REVOKE ALL ON FUNCTION public.admin_suporte_propor_skill(text, text, text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.admin_suporte_propor_skill(text, text, text) TO authenticated;

CREATE TABLE IF NOT EXISTS public.bkp_support_skills_20261105 AS SELECT * FROM public.support_skills;
ALTER TABLE public.bkp_support_skills_20261105 ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.bkp_support_skills_20261105 FROM anon, authenticated;

UPDATE public.support_skills SET allowed_tools = '["agent_get_order_full"]'::jsonb, updated_at = now(), playbook_md = $md$## ITEM_UNAVAILABLE

Quando usar: a pessoa pergunta por um produto que não veio ou foi trocado numa compra de mercado.

1. Chama agent_get_order_full e vê produtos_em_falta e produtos_trocados.
2. Diz o que aconteceu com esse produto, com o valor.
3. Regra: se um produto falta, o estafeta pergunta primeiro pelo chat; se não houver resposta, pode trocar por um parecido; produto que não veio não se paga.
4. Se a pessoa diz que falta algo e os dados não o mostram, ou pede compensação: passa à equipa com [HANDOFF_HUMAN].

Nunca fales em percentagens nem em reservas de valor.$md$
 WHERE skill_name = 'ITEM_UNAVAILABLE';

UPDATE public.support_skills SET allowed_tools = '["agent_get_order_full"]'::jsonb, updated_at = now(), playbook_md = $md$## ITEM_ADDED

Quando usar: a pessoa pergunta por um produto a mais na conta de uma compra de mercado.

1. Chama agent_get_order_full e vê produtos_acrescentados.
2. Diz qual o produto e o valor, e que foi acrescentado durante a compra.
3. Se a pessoa nega ter pedido: passa à equipa com [HANDOFF_HUMAN].

Nunca fales em percentagens, margens nem preço base.$md$
 WHERE skill_name = 'ITEM_ADDED';

UPDATE public.support_skills SET allowed_tools = '["agent_get_order_full"]'::jsonb, updated_at = now(), playbook_md = $md$## PRICE_DIFFERENCE

Quando usar: a pessoa pergunta porque o valor final é diferente do que viu na app, numa compra de mercado.

1. Chama agent_get_order_full e mostra a conta (conta.resumo) e os produtos em falta, trocados ou acrescentados.
2. Regra: nos mercados o valor final é o do talão; os preços na loja podem mudar e os produtos ao quilo dependem do peso.
3. Se a conta não explicar a diferença: passa à equipa com [HANDOFF_HUMAN].

Nunca fales em percentagens, margens nem reservas de valor.$md$
 WHERE skill_name = 'PRICE_DIFFERENCE';

UPDATE public.support_skills SET allowed_tools = '["agent_search_products","agent_get_store_info"]'::jsonb, updated_at = now(), playbook_md = $md$## FAVORES_CATALOGO_HELP

Quando usar: a pessoa quer saber onde encomendar um artigo.

1. Procura com agent_search_products. Se existir numa loja da app, diz a loja e o preço da app.
2. Se não existir (tabaco, farmácia, papelaria, loja de rua): explica o Favor, no ícone "Favores" do ecrã inicial.
3. Tabaco e álcool só para maiores de 18. Tabaco nunca está nas lojas da app.$md$
 WHERE skill_name = 'FAVORES_CATALOGO_HELP';

UPDATE public.support_skills SET allowed_tools = '["agent_get_my_driver_summary","agent_get_order_status"]'::jsonb, updated_at = now(), playbook_md = $md$## ORDER_REASSIGNMENT_HELP

Quando usar: um estafeta aceitou um pedido e quer passá-lo a outro ou não encontra como.

1. Chama agent_get_my_driver_summary e vê pedidos_em_curso.
2. Pergunta qual o pedido e o motivo.
3. A troca de estafeta é feita pela equipa: passa o caso com [HANDOFF_HUMAN], dizendo o pedido e o motivo.$md$
 WHERE skill_name = 'ORDER_REASSIGNMENT_HELP';

UPDATE public.support_skills SET allowed_tools = '["agent_get_my_partner_today","agent_get_store_info"]'::jsonb, updated_at = now(), playbook_md = $md$## PARTNER_FAQ

Quando usar: um parceiro pergunta como fazer algo na app ou pelo estado da loja.

1. Chama agent_get_my_partner_today. Usa os passos de como_fazer, sem inventar menus.
2. Se perguntar pelos pedidos de hoje ou se a loja está ligada, responde com os dados.
3. "Não me aparece o botão": pergunta que botão e em que ecrã; se for sair da conta, é em "A minha conta", no fim, "Terminar sessão".
4. Quem quer ser parceiro: passa à equipa com [HANDOFF_HUMAN].
5. Nunca dês contactos pessoais. O contacto de uma loja é a morada de agent_get_store_info.$md$
 WHERE skill_name = 'PARTNER_FAQ';

UPDATE public.support_skills SET allowed_tools = '["agent_get_order_status","agent_get_order_full"]'::jsonb, updated_at = now(), playbook_md = $md$## ORDER_STATUS

Quando usar: a pessoa pergunta onde está o pedido, quanto falta, se o estafeta chegou.

1. Usa o código que a pessoa escreveu (#BBA0F5) ou o pedido em foco; sem nenhum, agent_get_user_orders_summary e confirma o mais recente.
2. Chama agent_get_order_status e diz current_step, o primeiro nome do estafeta e driver_eta_min ("cerca de X minutos").
3. Sem driver_eta_min não dês minutos.
4. can_be_cancelled=true: podes dizer que ainda dá para cancelar na app.
5. ORDER_NOT_FOUND_OR_NOT_OWNER: pede o código que aparece em "Os meus pedidos".$md$
 WHERE skill_name = 'ORDER_STATUS';

UPDATE public.support_skills SET allowed_tools = '["agent_get_my_tokens_history","agent_get_order_full"]'::jsonb, updated_at = now(), playbook_md = $md$## TOKENS_INFO

Quando usar: dúvidas sobre tokens.

1. Chama agent_get_my_tokens_history: saldo, quanto pode usar, o que expira e quando.
2. Regras: ganhas tokens em cada pedido; 100 tokens = 0,50 €; numa compra usas no máximo metade do valor dos tokens que tens; expiram 60 dias depois de os ganhares.
3. "Não me descontaram": chama agent_get_order_full e mostra a conta (total, menos tokens, cobrado).
4. Usam-se no ecrã de pagamento, antes de confirmar o pedido. Por aqui não se aplicam a um pedido.
5. Só passas à equipa se os dados mostrarem mesmo um erro.$md$
 WHERE skill_name = 'TOKENS_INFO';

UPDATE public.support_skills SET allowed_tools = '["agent_get_my_driver_summary"]'::jsonb, updated_at = now(), playbook_md = $md$## DRIVER_EARNINGS_INFO

Quando usar: um estafeta pergunta quanto ganhou.

1. Chama agent_get_my_driver_summary e diz hoje, semana e tokens.
2. São os números do ecrã Ganhos da app; o acerto é semanal.
3. Valor que acha errado: pede o pedido e passa à equipa com [HANDOFF_HUMAN].

Só os ganhos dele; nunca de outras pessoas nem da Bora.$md$
 WHERE skill_name = 'DRIVER_EARNINGS_INFO';

UPDATE public.support_skills SET allowed_tools = '["agent_get_my_driver_summary"]'::jsonb, updated_at = now(), playbook_md = $md$## DRIVER_RIDE_EARNINGS

Quando usar: um motorista pergunta pelos ganhos.

1. Chama agent_get_my_driver_summary.
2. Detalhe por corrida: está no ecrã Ganhos da app.$md$
 WHERE skill_name = 'DRIVER_RIDE_EARNINGS';

UPDATE public.support_skills SET allowed_tools = allowed_tools || '["agent_get_my_wallet_history"]'::jsonb, updated_at = now()
 WHERE skill_name IN ('WALLET_INFO', 'WALLET_BLOCKED_HELP') AND NOT allowed_tools ? 'agent_get_my_wallet_history';

UPDATE public.support_skills SET allowed_tools = allowed_tools || '["agent_get_order_full"]'::jsonb, updated_at = now()
 WHERE skill_name = 'REFUND_STATUS' AND NOT allowed_tools ? 'agent_get_order_full';

UPDATE public.support_skills SET allowed_tools = '["agent_get_my_bookings"]'::jsonb, updated_at = now()
 WHERE skill_name = 'CLEANING_INFO';
```
