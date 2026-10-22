-- Bloco D · fechar-pendencias-2026-10-20 — marcos do check-in (Bora Todo Dia).
-- Parte 3/4 (leitura e uso do cliente). Base: tabela dos vales, sequencia continua, emissao no check-in, leitura do cliente,
-- manutencao horaria e funcoes do painel. Nao mexe nos tokens do check-in (Dia1..Dia7
-- continuam como estao) nem em nenhuma funcao de cobranca.
-- Marcos por sequencia continua: 7 (os tokens do Dia 7, so se mostra), 10, 15 e 30.
-- Falhou um dia -> volta a 1. Depois do dia 30 o ciclo recomeca no 1.

-- 9) Leitura do cliente --------------------------------------------------------------
CREATE OR REPLACE FUNCTION public._checkin_vale_json(v public.checkin_premios_vales)
RETURNS jsonb
LANGUAGE sql
STABLE SECURITY DEFINER
SET search_path TO 'public'
AS $function$
  SELECT jsonb_build_object(
    'id', v.id, 'marco', v.marco, 'chave', v.marco_chave, 'tipo', v.tipo, 'estado', v.estado,
    'titulo', v.titulo, 'loja_id', v.loja_id,
    'loja_nome', (SELECT r.name FROM public.restaurants r WHERE r.id = v.loja_id),
    'produto_id', v.produto_id, 'quantidade', v.quantidade, 'opcoes', to_jsonb(v.opcoes), 'opcao', v.opcao,
    'valor_cents', v.valor_cents, 'emitido_em', v.emitido_em, 'valido_ate', v.valido_ate,
    'ativar_em', v.ativar_em, 'esperar_ate', v.esperar_ate, 'reservado_ate', v.reservado_ate,
    'usado_em', v.usado_em, 'pedido_id', v.pedido_id, 'marcacao_tipo', v.marcacao_tipo,
    'marcacao_id', v.marcacao_id, 'origem', v.origem, 'visto', v.visto_em IS NOT NULL)
$function$;

CREATE OR REPLACE FUNCTION public.client_checkin_premios()
RETURNS jsonb
LANGUAGE plpgsql
STABLE SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_uid   uuid := auth.uid();
  v_est   jsonb;
  v_vales jsonb;
  v_novos jsonb;
BEGIN
  IF v_uid IS NULL THEN
    RETURN jsonb_build_object('ok', false, 'reason', 'sem_sessao');
  END IF;
  v_est := public._checkin_estado_marcos(v_uid);
  SELECT COALESCE(jsonb_agg(public._checkin_vale_json(s.v) ORDER BY s.emitido_em DESC), '[]'::jsonb)
    INTO v_vales
    FROM (SELECT x AS v, x.emitido_em FROM public.checkin_premios_vales x
           WHERE x.user_id = v_uid ORDER BY x.emitido_em DESC LIMIT 60) s;
  SELECT COALESCE(jsonb_agg(x.id), '[]'::jsonb) INTO v_novos
    FROM public.checkin_premios_vales x
   WHERE x.user_id = v_uid AND x.visto_em IS NULL
     AND x.estado IN ('por_usar','guardado','a_espera_pedido');
  RETURN v_est || jsonb_build_object(
    'ok', true,
    'texto', COALESCE(public._checkin_marco_cfg('checkin_marco_texto', 'null'::jsonb) #>> '{}',
      'Faz o check-in todos os dias. Aos 10 dias seguidos ganhas 2 salgados da Keli (pagas só a entrega e as taxas). Aos 15, um açaí do Goola. Aos 30, escolhes 2 horas de limpeza ou uma lavagem exterior do carro.'),
    'vales', v_vales,
    'novos', v_novos);
END;
$function$;

CREATE OR REPLACE FUNCTION public.client_checkin_premio_visto(p_ids uuid[])
RETURNS integer
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_n integer;
BEGIN
  IF auth.uid() IS NULL THEN RETURN 0; END IF;
  UPDATE public.checkin_premios_vales
     SET visto_em = now(), atualizado_em = now()
   WHERE user_id = auth.uid() AND id = ANY (COALESCE(p_ids, '{}'::uuid[])) AND visto_em IS NULL;
  GET DIAGNOSTICS v_n = ROW_COUNT;
  RETURN v_n;
END;
$function$;

-- Reserva o vale de produto para o carrinho (60 min) e devolve o artigo-premio.
CREATE OR REPLACE FUNCTION public.client_checkin_premio_reservar(p_vale_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_uid uuid := auth.uid();
  v     public.checkin_premios_vales;
  v_p   jsonb;
  v_l   jsonb;
BEGIN
  IF v_uid IS NULL THEN RETURN jsonb_build_object('ok', false, 'reason', 'sem_sessao'); END IF;
  SELECT * INTO v FROM public.checkin_premios_vales WHERE id = p_vale_id AND user_id = v_uid FOR UPDATE;
  IF v.id IS NULL THEN RETURN jsonb_build_object('ok', false, 'reason', 'nao_encontrado'); END IF;
  IF v.tipo <> 'produto' THEN RETURN jsonb_build_object('ok', false, 'reason', 'nao_e_produto'); END IF;
  IF v.estado NOT IN ('por_usar','reservado') THEN
    RETURN jsonb_build_object('ok', false, 'reason', v.estado);
  END IF;
  IF v.valido_ate IS NOT NULL AND v.valido_ate <= now() THEN
    UPDATE public.checkin_premios_vales SET estado = 'expirado', atualizado_em = now() WHERE id = v.id;
    RETURN jsonb_build_object('ok', false, 'reason', 'expirado');
  END IF;

  SELECT jsonb_build_object('id', p.id, 'name', p.name, 'description', p.description,
                            'photo_url', p.photo_url, 'restaurant_id', p.restaurant_id, 'price', 0)
    INTO v_p
    FROM public.products p WHERE p.id = v.produto_id;
  IF v_p IS NULL THEN RETURN jsonb_build_object('ok', false, 'reason', 'produto_em_falta'); END IF;
  SELECT jsonb_build_object('id', r.id, 'name', r.name, 'is_partner', COALESCE(r.is_partner, false))
    INTO v_l
    FROM public.restaurants r WHERE r.id = v.loja_id;

  UPDATE public.checkin_premios_vales
     SET estado = 'reservado', reservado_ate = now() + interval '60 minutes', atualizado_em = now()
   WHERE id = v.id
  RETURNING * INTO v;

  RETURN jsonb_build_object('ok', true, 'vale', public._checkin_vale_json(v), 'produto', v_p, 'loja', v_l);
END;
$function$;

CREATE OR REPLACE FUNCTION public.client_checkin_premio_libertar(p_vale_id uuid)
RETURNS boolean
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_n integer;
BEGIN
  IF auth.uid() IS NULL THEN RETURN false; END IF;
  UPDATE public.checkin_premios_vales
     SET estado = 'por_usar', reservado_ate = NULL, atualizado_em = now()
   WHERE id = p_vale_id AND user_id = auth.uid() AND estado = 'reservado' AND pedido_id IS NULL;
  GET DIAGNOSTICS v_n = ROW_COUNT;
  RETURN v_n > 0;
END;
$function$;

CREATE OR REPLACE FUNCTION public.client_checkin_premio_escolher(p_vale_id uuid, p_opcao text)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v public.checkin_premios_vales;
BEGIN
  IF auth.uid() IS NULL THEN RETURN jsonb_build_object('ok', false, 'reason', 'sem_sessao'); END IF;
  SELECT * INTO v FROM public.checkin_premios_vales WHERE id = p_vale_id AND user_id = auth.uid() FOR UPDATE;
  IF v.id IS NULL THEN RETURN jsonb_build_object('ok', false, 'reason', 'nao_encontrado'); END IF;
  IF v.estado <> 'por_usar' THEN RETURN jsonb_build_object('ok', false, 'reason', v.estado); END IF;
  IF NOT (p_opcao = ANY (v.opcoes)) THEN RETURN jsonb_build_object('ok', false, 'reason', 'opcao_invalida'); END IF;
  UPDATE public.checkin_premios_vales SET opcao = p_opcao, atualizado_em = now() WHERE id = v.id RETURNING * INTO v;
  RETURN jsonb_build_object('ok', true, 'vale', public._checkin_vale_json(v));
END;
$function$;

-- Permissoes: fechado a quem nao tem sessao
REVOKE ALL ON FUNCTION public._checkin_vale_json(public.checkin_premios_vales) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.client_checkin_premios() FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.client_checkin_premio_visto(uuid[]) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.client_checkin_premio_reservar(uuid) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.client_checkin_premio_libertar(uuid) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.client_checkin_premio_escolher(uuid, text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.client_checkin_premios() TO authenticated;
GRANT EXECUTE ON FUNCTION public.client_checkin_premio_visto(uuid[]) TO authenticated;
GRANT EXECUTE ON FUNCTION public.client_checkin_premio_reservar(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.client_checkin_premio_libertar(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.client_checkin_premio_escolher(uuid, text) TO authenticated;
