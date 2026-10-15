-- Missão tvde-pedir-nunca-trava-2026-10-14 · Bloco F.
--
-- Cicatriz (14/10/2026): a cliente Stela abriu o ecrã do Bora Motorista,
-- escreveu a morada, e o botão de pedir ficou cinzento sem dizer porquê. Ligou
-- ao Danilo. Os logs provaram que o preço nunca chegou a ser pedido — a recolha
-- ou o destino ficaram sem coordenadas. Ninguém soube a não ser por telefone.
--
-- 1) web_health_events passa a aceitar 'pedido_travado' (o cliente tocou em
--    pedir e não conseguiu; o detalhe diz porquê: sem_recolha / sem_destino /
--    geocode_falhou / gps_falhou).
-- 2) admin_web_health_eventos(p_dias): o painel "Saúde da Web" (PT-BR) vê os
--    eventos com o nome, telefone e email do cliente, para lhe ligar. Só admin.
-- 3) Alarme: ao 3.º 'pedido_travado' do mesmo cliente em 10 minutos, avisa o
--    admin pelo caminho que já existe (notify_admin_urgent_push: inbox + push
--    persistente + Telegram).

ALTER TABLE public.web_health_events
  DROP CONSTRAINT IF EXISTS web_health_events_motivo_check;

ALTER TABLE public.web_health_events
  ADD CONSTRAINT web_health_events_motivo_check CHECK (motivo IN (
    'script_bloqueado',
    'timeout_sdk',
    'sem_resultados',
    'geocode_manual_falhou',
    'proxy_falhou',
    'pedido_travado'
  ));

CREATE INDEX IF NOT EXISTS web_health_events_travado_user_idx
  ON public.web_health_events (user_id, criado_em DESC)
  WHERE motivo = 'pedido_travado';

-- ── 2) Leitura do painel, com quem é ─────────────────────────────────────
CREATE OR REPLACE FUNCTION public.admin_web_health_eventos(p_dias int DEFAULT 7)
RETURNS TABLE (
  id bigint,
  criado_em timestamptz,
  motivo text,
  ecra text,
  detalhe text,
  plataforma text,
  user_id uuid,
  nome text,
  telefone text,
  email text
)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF NOT public.is_admin() THEN
    RAISE EXCEPTION 'Só o admin pode ver a saúde da web' USING ERRCODE = '42501';
  END IF;

  RETURN QUERY
  SELECT e.id, e.criado_em, e.motivo, e.ecra, e.detalhe, e.plataforma,
         e.user_id, u.name, u.phone, u.email
  FROM public.web_health_events e
  LEFT JOIN public.users u ON u.id = e.user_id
  WHERE e.criado_em > now() - make_interval(days => GREATEST(1, LEAST(coalesce(p_dias, 7), 90)))
  ORDER BY e.criado_em DESC
  LIMIT 300;
END;
$$;

REVOKE ALL ON FUNCTION public.admin_web_health_eventos(int) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.admin_web_health_eventos(int) TO authenticated;

-- ── 3) Alarme: 3 toques sem conseguir em 10 min ──────────────────────────
CREATE OR REPLACE FUNCTION public.fn_web_health_pedido_travado_alarme()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_n        int;
  v_motivos  text;
  v_nome     text;
  v_tel      text;
BEGIN
  IF NEW.motivo <> 'pedido_travado' OR NEW.user_id IS NULL THEN
    RETURN NULL;
  END IF;

  SELECT count(*),
         string_agg(DISTINCT CASE e.detalhe
           WHEN 'sem_recolha'    THEN 'faltou o ponto de partida'
           WHEN 'sem_destino'    THEN 'faltou o destino'
           WHEN 'geocode_falhou' THEN 'endereço não encontrado no mapa'
           WHEN 'gps_falhou'     THEN 'GPS desligado ou negado'
           ELSE coalesce(nullif(e.detalhe, ''), 'motivo desconhecido')
         END, ', ')
    INTO v_n, v_motivos
  FROM public.web_health_events e
  WHERE e.motivo = 'pedido_travado'
    AND e.user_id = NEW.user_id
    AND e.criado_em > now() - interval '10 minutes';

  -- Só ao 3.º: um aviso por aperto, não um por toque.
  IF v_n <> 3 THEN
    RETURN NULL;
  END IF;

  SELECT u.name, u.phone INTO v_nome, v_tel
  FROM public.users u WHERE u.id = NEW.user_id;

  BEGIN
    PERFORM public.notify_admin_urgent_push(
      'cliente_pedido_travado',
      E'🚕 ' || coalesce(nullif(trim(v_nome), ''), 'Cliente') || ' não consegue pedir\n'
        || 'Tocou em pedir 3 vezes em 10 min sem conseguir (' || coalesce(v_motivos, '?')
        || ', ' || coalesce(nullif(NEW.plataforma, ''), '?') || ').'
        || coalesce(' Ligue: ' || nullif(trim(v_tel), ''), ' Sem telefone na conta.'),
      'user', NEW.user_id::text,
      jsonb_build_object('user_id', NEW.user_id, 'nome', v_nome, 'telefone', v_tel,
                         'plataforma', NEW.plataforma, 'motivos', v_motivos,
                         'ecra', NEW.ecra),
      '/admin/saude-web');
  EXCEPTION WHEN others THEN
    -- O registo do evento nunca falha por causa do alarme.
    RAISE NOTICE 'pedido_travado alarme: %', SQLERRM;
  END;

  RETURN NULL;
END;
$$;

REVOKE ALL ON FUNCTION public.fn_web_health_pedido_travado_alarme() FROM PUBLIC, anon, authenticated;

DROP TRIGGER IF EXISTS trg_web_health_pedido_travado_alarme ON public.web_health_events;
CREATE TRIGGER trg_web_health_pedido_travado_alarme
  AFTER INSERT ON public.web_health_events
  FOR EACH ROW
  WHEN (NEW.motivo = 'pedido_travado')
  EXECUTE FUNCTION public.fn_web_health_pedido_travado_alarme();
