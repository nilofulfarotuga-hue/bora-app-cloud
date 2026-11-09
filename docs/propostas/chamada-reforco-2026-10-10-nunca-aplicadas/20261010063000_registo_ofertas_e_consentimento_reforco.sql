-- =============================================================================
-- 20261010063000 · Registo de ofertas (entregas, Favores, TVDE) + consentimento
--                  "chamadas de reforço" + definições.  SÓ OBSERVAÇÃO.
-- Missão "a chamada grita sempre" (10/10/2026), Bloco C.
--
-- Isto NÃO muda quem é chamado nem quando: não toca no motor de despacho, nas
-- funções de candidatos, nos tempos nem nos cancelamentos. Só:
--   1. regista cada oferta feita a um estafeta/motorista (para quem foi, quando,
--      se estava online, se tinha aparelho, quanto tempo teve, como acabou) no
--      mesmo registo da limpeza e da lavagem (ofertas_prestador_log);
--   2. guarda se o FCM aceitou o toque (o notify-driver v43 escreve na linha;
--      o TVDE já regista em tvde_ride_events e um gatilho copia para a linha);
--   3. cria o interruptor de consentimento de cada profissional
--      "Aceito chamadas de reforço quando estou desligado" (desligado por
--      defeito) — decisão do Danilo de 10/10 (risco legal/lojas);
--   4. cria as definições da chamada de reforço (DESLIGADA por defeito: o
--      comportamento só existe quando o Danilo aprovar a proposta do despacho).
-- =============================================================================

-- 1) Definições — a chamada de reforço nasce DESLIGADA.
INSERT INTO public.platform_settings (key, value, category, description) VALUES
  ('dispatch_forcado_ligado', 'false', 'dispatch',
   'Chamada de reforço (entregas e Favores): se nenhum estafeta online aceitar, chamar quem está desligado MAS consentiu, um de cada vez.'),
  ('dispatch_voltas_online_antes_forcado', '2', 'dispatch',
   'Voltas completas aos estafetas online antes da chamada de reforço.'),
  ('dispatch_forcado_tentativas', '2', 'dispatch',
   'Quantos estafetas desligados (que consentiram) se chamam, um de cada vez, antes de voltar aos online.'),
  ('dispatch_forcado_prioridade', '["e355fde0-b634-48ba-bce1-e2a4466c4cc2"]', 'dispatch',
   'Ordem fixa de quem é chamado no reforço (user_id). Os restantes vêm a seguir, do visto mais recentemente.'),
  ('dispatch_forcado_visto_horas', '168', 'dispatch',
   'Só entra no reforço quem tem aparelho registado e abriu a app nas últimas N horas.'),
  ('dispatch_forcado_horario_inicio', '"08:00"', 'dispatch',
   'Hora de Lisboa a partir da qual se pode fazer a chamada de reforço.'),
  ('dispatch_forcado_horario_fim', '"23:00"', 'dispatch',
   'Hora de Lisboa a partir da qual já não se faz a chamada de reforço.'),
  ('dispatch_forcado_max_por_dia', '3', 'dispatch',
   'Máximo de chamadas de reforço por pessoa por dia (recusar nunca penaliza).'),
  ('dispatch_voltas_online_depois_forcado', '1', 'dispatch',
   'Depois do reforço, voltas aos online antes de dizer "não há estafeta".'),
  ('dispatch_cancelar_so_no_fim', 'true', 'dispatch',
   'O cancelamento automático por tempo espera que as fases acabem (só vale com a chamada de reforço ligada).'),
  ('dispatch_cancelar_limite_absoluto_segundos', '3600', 'dispatch',
   'Limite absoluto: passado este tempo a procurar, o pedido pode ser cancelado mesmo a meio das fases.'),
  ('tvde_forcado_ligado', 'false', 'tvde',
   'Chamada de reforço (TVDE): antes de "sem motorista", chamar motoristas desligados que consentiram, um de cada vez.'),
  ('tvde_forcado_tentativas', '2', 'tvde',
   'TVDE: quantos motoristas desligados (que consentiram) se chamam antes de "sem motorista".'),
  ('tvde_forcado_prioridade', '["e355fde0-b634-48ba-bce1-e2a4466c4cc2"]', 'tvde',
   'TVDE: ordem fixa de quem é chamado no reforço (user_id).')
ON CONFLICT (key) DO NOTHING;

-- 2) Consentimento de cada profissional (só a própria pessoa liga/desliga).
CREATE TABLE IF NOT EXISTS public.chamada_reforco_consentimento (
  user_id       uuid PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
  ligado        boolean NOT NULL DEFAULT false,
  atualizado_em timestamptz NOT NULL DEFAULT now()
);
ALTER TABLE public.chamada_reforco_consentimento ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS reforco_ver_o_meu ON public.chamada_reforco_consentimento;
CREATE POLICY reforco_ver_o_meu ON public.chamada_reforco_consentimento
  FOR SELECT TO authenticated USING (user_id = auth.uid() OR public.is_admin());
DROP POLICY IF EXISTS reforco_criar_o_meu ON public.chamada_reforco_consentimento;
CREATE POLICY reforco_criar_o_meu ON public.chamada_reforco_consentimento
  FOR INSERT TO authenticated WITH CHECK (user_id = auth.uid());
DROP POLICY IF EXISTS reforco_mudar_o_meu ON public.chamada_reforco_consentimento;
CREATE POLICY reforco_mudar_o_meu ON public.chamada_reforco_consentimento
  FOR UPDATE TO authenticated USING (user_id = auth.uid()) WITH CHECK (user_id = auth.uid());
GRANT SELECT, INSERT, UPDATE ON public.chamada_reforco_consentimento TO authenticated;

CREATE OR REPLACE FUNCTION public._reforco_carimbo()
 RETURNS trigger LANGUAGE plpgsql SET search_path TO 'public' AS $function$
BEGIN
  NEW.atualizado_em := now();
  RETURN NEW;
END $function$;
DROP TRIGGER IF EXISTS trg_reforco_carimbo ON public.chamada_reforco_consentimento;
CREATE TRIGGER trg_reforco_carimbo BEFORE INSERT OR UPDATE ON public.chamada_reforco_consentimento
  FOR EACH ROW EXECUTE FUNCTION public._reforco_carimbo();

-- 3) Registo de ofertas: colunas para entregas, Favores e TVDE.
ALTER TABLE public.ofertas_prestador_log
  ALTER COLUMN booking_id DROP NOT NULL,
  ADD COLUMN IF NOT EXISTS pedido_ref     text,
  ADD COLUMN IF NOT EXISTS fase           text,
  ADD COLUMN IF NOT EXISTS estava_online  boolean,
  ADD COLUMN IF NOT EXISTS janela_s       integer,
  ADD COLUMN IF NOT EXISTS push_aparelhos integer,
  ADD COLUMN IF NOT EXISTS push_enviados  integer,
  ADD COLUMN IF NOT EXISTS push_em        timestamptz,
  ADD COLUMN IF NOT EXISTS push_detalhe   text;
CREATE INDEX IF NOT EXISTS ofertas_prestador_log_pedido_idx
  ON public.ofertas_prestador_log (pedido_ref, oferecida_em);
CREATE INDEX IF NOT EXISTS ofertas_prestador_log_abertas_idx
  ON public.ofertas_prestador_log (pedido_ref) WHERE desfecho IS NULL;
CREATE INDEX IF NOT EXISTS ofertas_prestador_log_user_dia_idx
  ON public.ofertas_prestador_log (user_id, oferecida_em) WHERE fase = 'forcado';

-- 4) Entregas e Favores: uma linha por oferta (gatilho que SÓ escreve no registo).
CREATE OR REPLACE FUNCTION public._registar_oferta_entrega()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_mudou    boolean;
  v_desfecho text;
  v_d        record;
  v_janela   integer;
  v_online   boolean;
BEGIN
  v_mudou := NEW.current_driver_offer_id IS DISTINCT FROM OLD.current_driver_offer_id
          OR NEW.driver_offer_expires_at IS DISTINCT FROM OLD.driver_offer_expires_at;

  -- Fechar a oferta que acabou.
  IF OLD.current_driver_offer_id IS NOT NULL
     AND (v_mudou OR NEW.status IS DISTINCT FROM OLD.status
          OR NEW.assigned_driver_id IS DISTINCT FROM OLD.assigned_driver_id) THEN
    v_desfecho := CASE
      WHEN NEW.assigned_driver_id IS NOT NULL
           AND (NEW.assigned_driver_id = OLD.current_driver_offer_id
                OR EXISTS (SELECT 1 FROM public.drivers d
                            WHERE (d.user_id::text = OLD.current_driver_offer_id OR d.id::text = OLD.current_driver_offer_id)
                              AND NEW.assigned_driver_id IN (d.id::text, COALESCE(d.user_id, d.id)::text)))
        THEN 'aceite'
      WHEN NEW.status = 'cancelled' THEN 'pedido_cancelado'
      WHEN NEW.status IS DISTINCT FROM 'callingDriver' THEN 'pedido_mudou'
      WHEN OLD.driver_offer_expires_at IS NOT NULL
           AND OLD.driver_offer_expires_at > now() + interval '2 seconds' THEN 'recusou'
      ELSE 'expirou' END;
    UPDATE public.ofertas_prestador_log
       SET desfecho = v_desfecho, fechada_em = now()
     WHERE pedido_ref = NEW.id AND categoria IN ('entrega', 'favor') AND desfecho IS NULL;
  END IF;

  -- Abrir a oferta nova.
  IF v_mudou AND NEW.current_driver_offer_id IS NOT NULL AND NEW.driver_offer_expires_at IS NOT NULL
     AND NEW.status = 'callingDriver' AND NEW.assigned_driver_id IS NULL THEN
    SELECT d.id, COALESCE(d.user_id, d.id) AS uid, d.name, d.is_online, d.last_heartbeat_at, d.fcm_token
      INTO v_d
      FROM public.drivers d
     WHERE d.user_id::text = NEW.current_driver_offer_id OR d.id::text = NEW.current_driver_offer_id
     LIMIT 1;
    v_janela := GREATEST(1, EXTRACT(EPOCH FROM (NEW.driver_offer_expires_at - now()))::int);
    v_online := COALESCE(v_d.is_online, false) AND v_d.last_heartbeat_at > now() - interval '90 seconds';
    INSERT INTO public.ofertas_prestador_log
      (categoria, booking_id, pedido_ref, prestador_id, user_id, nome, tem_aparelho,
       janela_min, janela_s, fase, estava_online)
    VALUES
      (CASE WHEN NEW.service_type = 'errand' THEN 'favor' ELSE 'entrega' END,
       CASE WHEN NEW.id ~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$' THEN NEW.id::uuid END,
       NEW.id, v_d.id, v_d.uid, v_d.name,
       COALESCE(v_d.fcm_token, '') <> ''
         OR EXISTS (SELECT 1 FROM public.driver_push_tokens t WHERE t.user_id = v_d.uid AND t.active),
       CEIL(v_janela / 60.0)::int, v_janela,
       CASE WHEN v_online THEN 'online' ELSE 'desligado' END,
       v_online);
  END IF;
  RETURN NULL;
EXCEPTION WHEN OTHERS THEN
  -- O registo nunca pode partir o despacho; mas fica rasto.
  BEGIN
    INSERT INTO public.notification_failures (kind, source, erro)
    VALUES ('registo_oferta', '_registar_oferta_entrega', left(NEW.id || ': ' || SQLERRM, 500));
  EXCEPTION WHEN OTHERS THEN
    RAISE WARNING '[_registar_oferta_entrega] % (registo da falha também falhou: %)', NEW.id, SQLERRM;
  END;
  RETURN NULL;
END;
$function$;

DROP TRIGGER IF EXISTS trg_registar_oferta_entrega ON public.orders;
CREATE TRIGGER trg_registar_oferta_entrega
  AFTER UPDATE OF current_driver_offer_id, driver_offer_expires_at, status, assigned_driver_id
  ON public.orders
  FOR EACH ROW EXECUTE FUNCTION public._registar_oferta_entrega();

-- 5) TVDE: uma linha por oferta de corrida (gatilho que SÓ escreve no registo).
CREATE OR REPLACE FUNCTION public._registar_oferta_tvde()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_d        record;
  v_online   boolean;
  v_janela   integer;
  v_desfecho text;
BEGIN
  IF OLD.current_offer_driver_id IS NOT NULL
     AND (NEW.current_offer_driver_id IS DISTINCT FROM OLD.current_offer_driver_id
          OR NEW.status IS DISTINCT FROM OLD.status) THEN
    v_desfecho := CASE
      WHEN NEW.driver_id IS NOT NULL AND NEW.driver_id = OLD.current_offer_driver_id THEN 'aceite'
      WHEN NEW.status LIKE 'cancelada%' THEN 'pedido_cancelado'
      WHEN NEW.status = 'sem_motorista' THEN 'sem_motorista'
      WHEN OLD.offer_expires_at IS NOT NULL AND OLD.offer_expires_at > now() + interval '2 seconds' THEN 'recusou'
      ELSE 'expirou' END;
    UPDATE public.ofertas_prestador_log
       SET desfecho = v_desfecho, fechada_em = now()
     WHERE booking_id = NEW.id AND categoria = 'tvde' AND desfecho IS NULL;
  END IF;

  IF NEW.current_offer_driver_id IS NOT NULL
     AND NEW.current_offer_driver_id IS DISTINCT FROM OLD.current_offer_driver_id
     AND NEW.status = 'solicitada' THEN
    SELECT d.id, d.user_id AS uid, d.name, d.is_online, d.last_heartbeat_at, d.fcm_token
      INTO v_d FROM public.drivers d WHERE d.user_id = NEW.current_offer_driver_id LIMIT 1;
    v_online := COALESCE(v_d.is_online, false) AND v_d.last_heartbeat_at > now() - interval '90 seconds';
    v_janela := CASE WHEN NEW.offer_expires_at IS NULL THEN NULL
                     ELSE GREATEST(1, EXTRACT(EPOCH FROM (NEW.offer_expires_at - now()))::int) END;
    INSERT INTO public.ofertas_prestador_log
      (categoria, booking_id, pedido_ref, prestador_id, user_id, nome, tem_aparelho,
       janela_min, janela_s, fase, estava_online)
    VALUES
      ('tvde', NEW.id, NEW.id::text, v_d.id, NEW.current_offer_driver_id, v_d.name,
       COALESCE(v_d.fcm_token, '') <> ''
         OR EXISTS (SELECT 1 FROM public.driver_push_tokens t WHERE t.user_id = NEW.current_offer_driver_id AND t.active),
       CASE WHEN v_janela IS NULL THEN NULL ELSE CEIL(v_janela / 60.0)::int END, v_janela,
       CASE WHEN v_online THEN 'online' ELSE 'desligado' END,
       v_online);
  END IF;
  RETURN NULL;
EXCEPTION WHEN OTHERS THEN
  BEGIN
    INSERT INTO public.notification_failures (kind, source, erro)
    VALUES ('registo_oferta', '_registar_oferta_tvde', left(NEW.id::text || ': ' || SQLERRM, 500));
  EXCEPTION WHEN OTHERS THEN
    RAISE WARNING '[_registar_oferta_tvde] % (registo da falha também falhou: %)', NEW.id, SQLERRM;
  END;
  RETURN NULL;
END;
$function$;

DROP TRIGGER IF EXISTS trg_registar_oferta_tvde ON public.tvde_rides;
CREATE TRIGGER trg_registar_oferta_tvde
  AFTER UPDATE OF current_offer_driver_id, status
  ON public.tvde_rides
  FOR EACH ROW EXECUTE FUNCTION public._registar_oferta_tvde();

-- 6) TVDE: o "push_enviado/push_falhou" que o notify-tvde-driver já regista
--    passa também para a linha da oferta (o painel mostra se o toque saiu).
CREATE OR REPLACE FUNCTION public._registar_toque_tvde()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
BEGIN
  IF NEW.status IN ('push_enviado', 'push_falhou')
     AND COALESCE(NEW.meta->>'kind', 'offer') = 'offer' THEN
    UPDATE public.ofertas_prestador_log
       SET push_enviados = CASE WHEN NEW.status = 'push_enviado' THEN 1 ELSE 0 END,
           push_em = NEW.at,
           push_detalhe = left(COALESCE(NEW.meta::text, ''), 500)
     WHERE booking_id = NEW.ride_id AND categoria = 'tvde' AND desfecho IS NULL
       AND (NEW.meta->>'driver_id' IS NULL OR user_id::text = NEW.meta->>'driver_id');
  END IF;
  RETURN NULL;
EXCEPTION WHEN OTHERS THEN
  RAISE WARNING '[_registar_toque_tvde] %: %', NEW.ride_id, SQLERRM;
  RETURN NULL;
END;
$function$;

DROP TRIGGER IF EXISTS trg_registar_toque_tvde ON public.tvde_ride_events;
CREATE TRIGGER trg_registar_toque_tvde
  AFTER INSERT ON public.tvde_ride_events
  FOR EACH ROW EXECUTE FUNCTION public._registar_toque_tvde();

-- 7) Painel: o que aconteceu a um pedido/corrida.
CREATE OR REPLACE FUNCTION public.admin_ofertas_do_pedido(p_ref text)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE v_itens jsonb;
BEGIN
  IF NOT public.is_admin() THEN RAISE EXCEPTION 'admin_required'; END IF;
  SELECT COALESCE(jsonb_agg(jsonb_build_object(
           'categoria', l.categoria, 'nome', COALESCE(l.nome, '(sem nome)'),
           'user_id', l.user_id, 'fase', l.fase, 'estava_online', l.estava_online,
           'tem_aparelho', l.tem_aparelho, 'janela_s', COALESCE(l.janela_s, l.janela_min * 60),
           'oferecida_em', l.oferecida_em, 'fechada_em', l.fechada_em,
           'desfecho', COALESCE(l.desfecho, 'a decorrer'),
           'push_aparelhos', l.push_aparelhos, 'push_enviados', l.push_enviados,
           'push_em', l.push_em, 'push_detalhe', l.push_detalhe)
         ORDER BY l.oferecida_em), '[]'::jsonb)
    INTO v_itens
    FROM public.ofertas_prestador_log l
   WHERE l.pedido_ref = p_ref OR l.booking_id::text = p_ref;
  RETURN jsonb_build_object('ok', true, 'itens', v_itens);
END;
$function$;

-- 8) Painel: quem ligou o interruptor de reforço (e quantas vezes foi chamado hoje).
CREATE OR REPLACE FUNCTION public.admin_reforco_lista()
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE v jsonb; v_prio jsonb := public.get_setting('dispatch_forcado_prioridade');
BEGIN
  IF NOT public.is_admin() THEN RAISE EXCEPTION 'admin_required'; END IF;
  IF v_prio IS NULL OR jsonb_typeof(v_prio) <> 'array' THEN v_prio := '[]'::jsonb; END IF;
  SELECT COALESCE(jsonb_agg(jsonb_build_object(
           'user_id', d.user_id, 'nome', d.name, 'veiculo', d.vehicle_type,
           'consentiu', COALESCE(c.ligado, false), 'consentiu_em', c.atualizado_em,
           'online', d.is_online, 'visto_em', d.last_heartbeat_at,
           'ordem', (SELECT e.ord FROM jsonb_array_elements_text(v_prio) WITH ORDINALITY e(val, ord)
                      WHERE e.val = d.user_id::text LIMIT 1),
           'reforcos_hoje', (SELECT count(*) FROM public.ofertas_prestador_log l
                              WHERE l.user_id = d.user_id AND l.fase = 'forcado'
                                AND l.oferecida_em >= date_trunc('day', now() AT TIME ZONE 'Europe/Lisbon') AT TIME ZONE 'Europe/Lisbon'))
         ORDER BY COALESCE(c.ligado, false) DESC, d.name), '[]'::jsonb)
    INTO v
    FROM public.drivers d
    LEFT JOIN public.chamada_reforco_consentimento c ON c.user_id = d.user_id
   WHERE d.approval_status = 'approved' AND d.deleted_at IS NULL AND d.user_id IS NOT NULL;
  RETURN jsonb_build_object('ok', true, 'itens', v);
END;
$function$;

-- 9) O registo geral do painel passa a mostrar as colunas novas.
CREATE OR REPLACE FUNCTION public.admin_ofertas_log(p_categoria text DEFAULT NULL::text, p_dias integer DEFAULT 7, p_limite integer DEFAULT 200)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE v_out jsonb; v_resumo jsonb;
BEGIN
  IF NOT public.is_admin() THEN RAISE EXCEPTION 'admin_required'; END IF;

  SELECT COALESCE(jsonb_agg(jsonb_build_object(
           'id', o.id, 'categoria', o.categoria, 'booking_id', o.booking_id,
           'pedido_ref', COALESCE(o.pedido_ref, o.booking_id::text),
           'nome', COALESCE(o.nome, '(sem nome)'),
           'tem_aparelho', o.tem_aparelho, 'janela_min', o.janela_min,
           'janela_s', COALESCE(o.janela_s, o.janela_min * 60),
           'fase', o.fase, 'estava_online', o.estava_online,
           'push_enviados', o.push_enviados, 'push_aparelhos', o.push_aparelhos, 'push_em', o.push_em,
           'oferecida_em', o.oferecida_em,
           'desfecho', COALESCE(o.desfecho, 'a decorrer'),
           'fechada_em', o.fechada_em) ORDER BY o.oferecida_em DESC), '[]'::jsonb)
    INTO v_out
    FROM (SELECT * FROM public.ofertas_prestador_log
           WHERE oferecida_em > now() - make_interval(days => GREATEST(COALESCE(p_dias,7),1))
             AND (p_categoria IS NULL OR categoria = p_categoria)
           ORDER BY oferecida_em DESC
           LIMIT GREATEST(COALESCE(p_limite,200),1)) o;

  SELECT jsonb_build_object(
      'total', count(*),
      'sem_aparelho', count(*) FILTER (WHERE NOT tem_aparelho),
      'expiraram', count(*) FILTER (WHERE desfecho = 'expirou'),
      'aceites', count(*) FILTER (WHERE desfecho = 'aceite'),
      'reforco', count(*) FILTER (WHERE fase = 'forcado'),
      'toque_falhou', count(*) FILTER (WHERE push_enviados = 0))
    INTO v_resumo
    FROM public.ofertas_prestador_log
   WHERE oferecida_em > now() - make_interval(days => GREATEST(COALESCE(p_dias,7),1))
     AND (p_categoria IS NULL OR categoria = p_categoria);

  RETURN jsonb_build_object('ok', true, 'resumo', v_resumo, 'itens', v_out);
END $function$;

-- 10) Quem pode chamar o quê.
REVOKE ALL ON FUNCTION public._registar_oferta_entrega() FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public._registar_oferta_tvde() FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public._registar_toque_tvde() FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public._reforco_carimbo() FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.admin_ofertas_do_pedido(text) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.admin_reforco_lista() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.admin_ofertas_do_pedido(text) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.admin_reforco_lista() TO authenticated, service_role;
