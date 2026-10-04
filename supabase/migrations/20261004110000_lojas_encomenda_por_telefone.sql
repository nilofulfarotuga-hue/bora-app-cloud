-- ============================================================================
-- Missão única 2026-10-03 · Bloco 6 — Lojas NÃO-parceiras que se encomendam por TELEFONE
-- Escrita 04/10 no PC; APLICAR pela Claude.ai (conector do PC prende nas escritas;
-- PAT do CLI expirado). Depois: correr supabase/provas/20261004_b6_prova_telefone.sql.
--
-- Problema: a Pôr do Sol (e Fuku Sushi, Jyosmi Sushi, Tiago's Pizza, DaVinci, Amaya)
-- não usam a app de parceiro. Quando entra um pedido, a Bora tem de LIGAR à loja a
-- encomendar e só depois mandar o estafeta.
--
-- Desenho (sem mexer no motor de despacho, no webhook nem em preços):
--   • restaurants.order_by_phone / phone_order_number / dispatch_delay_minutes /
--     phone_prep_minutes — editáveis no painel admin.
--   • PORTEIRO (gatilho BEFORE em orders, corre primeiro): quando um pedido destas
--     lojas, já pago (ou a dinheiro), tenta passar a 'callingDriver' antes da hora,
--     fica em 'preparing'. Nasce uma linha em encomendas_telefone e sai o alerta ao
--     admin (Telegram + push persistente) com o resumo a ler ao telefone.
--   • RELÓGIO (pg_cron, cada minuto): repete o alerta aos 3 e 6 min se ninguém carregou
--     em "Encomendado à loja"; liberta o pedido (callingDriver) quando passa a hora:
--     (encomendado_em OU hora do pedido) + dispatch_delay_minutes.
--   • O cliente vê "A loja está a preparar o teu pedido" com a hora prevista
--     (orders.prep_time_minutes, coluna NÃO financeira).
--   • Preço de BALCÃO = basePrice do item (preço da loja, sem os 15%). Só leitura.
-- ============================================================================

-- ── 1. Marca na loja ───────────────────────────────────────────────────────
ALTER TABLE public.restaurants
  ADD COLUMN IF NOT EXISTS order_by_phone boolean NOT NULL DEFAULT false,
  ADD COLUMN IF NOT EXISTS phone_order_number text,
  ADD COLUMN IF NOT EXISTS dispatch_delay_minutes integer NOT NULL DEFAULT 15
    CHECK (dispatch_delay_minutes BETWEEN 0 AND 120),
  ADD COLUMN IF NOT EXISTS phone_prep_minutes integer NOT NULL DEFAULT 20
    CHECK (phone_prep_minutes BETWEEN 0 AND 180);

COMMENT ON COLUMN public.restaurants.order_by_phone IS
  'Loja não-parceira que se encomenda por telefone: a Bora liga antes de chamar o estafeta.';
COMMENT ON COLUMN public.restaurants.dispatch_delay_minutes IS
  'Minutos entre "Encomendado à loja" (ou a hora do pedido) e chamar o estafeta.';

UPDATE public.restaurants
   SET order_by_phone = true,
       phone_order_number = COALESCE(phone_order_number, phone),
       dispatch_delay_minutes = 15,
       phone_prep_minutes = 20
 WHERE id IN ('pordosol-guarda', 'fuku-sushi-guarda', 'jyosmi-sushi-guarda',
              'tiagos-pizza-guarda', 'davinci-guarda', 'amaya-sushi-guarda')
   AND is_partner = false;

-- ── 2. Tarefas "ligar à loja" ──────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS public.encomendas_telefone (
  order_id              text PRIMARY KEY,
  restaurant_id         text NOT NULL,
  criado_em             timestamptz NOT NULL DEFAULT now(),
  alertas               integer NOT NULL DEFAULT 0,
  ultimo_alerta_em      timestamptz,
  encomendado_em        timestamptz,
  encomendado_por       uuid,
  encomendado_por_nome  text,
  libertado_em          timestamptz,
  cancelado_em          timestamptz,
  resumo                text,
  total_balcao          numeric(10, 2)
);
CREATE INDEX IF NOT EXISTS encomendas_telefone_abertas
  ON public.encomendas_telefone(criado_em) WHERE libertado_em IS NULL AND cancelado_em IS NULL;
ALTER TABLE public.encomendas_telefone ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS encomendas_telefone_admin_le ON public.encomendas_telefone;
CREATE POLICY encomendas_telefone_admin_le ON public.encomendas_telefone
  FOR SELECT TO authenticated USING (public.is_admin());
REVOKE INSERT, UPDATE, DELETE ON public.encomendas_telefone FROM anon, authenticated;
GRANT SELECT ON public.encomendas_telefone TO authenticated;

-- ── 3. Resumo para ler ao telefone (preço de BALCÃO, sem os 15%) ───────────
CREATE OR REPLACE FUNCTION public.encomenda_telefone_resumo(p_order_id text)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path TO 'public' AS $f$
DECLARE
  o public.orders%ROWTYPE;
  r public.restaurants%ROWTYPE;
  it jsonb; g jsonb;
  v_txt text := ''; v_total numeric := 0; v_unit numeric; v_q int; v_ops text;
BEGIN
  SELECT * INTO o FROM public.orders WHERE id = p_order_id;
  IF NOT FOUND THEN RETURN NULL; END IF;
  SELECT * INTO r FROM public.restaurants WHERE id = o.restaurant_id;
  FOR it IN SELECT * FROM jsonb_array_elements(COALESCE(o.items, '[]'::jsonb)) LOOP
    v_q := COALESCE((it->>'quantity')::int, 1);
    -- basePrice = preço da loja (puro). Sem ele, tira-se os 15% do preço de cartaz.
    v_unit := ROUND(COALESCE((it->>'basePrice')::numeric, (it->>'price')::numeric / 1.15, 0), 2);
    v_ops := '';
    FOR g IN SELECT * FROM jsonb_array_elements(COALESCE(it->'selected_options', '[]'::jsonb)) LOOP
      v_ops := v_ops || E'\n     · ' || COALESCE(g->>'group', '') || ': '
            || COALESCE((SELECT string_agg(x, ', ') FROM jsonb_array_elements_text(g->'items') x), '');
    END LOOP;
    v_txt := v_txt || E'\n• ' || v_q || '× ' || COALESCE(it->>'name', '?')
          || ' — ' || to_char(v_unit, 'FM9990.00') || ' €' || v_ops;
    v_total := v_total + v_unit * v_q;
  END LOOP;
  RETURN jsonb_build_object(
    'loja', r.name,
    'telefone', COALESCE(r.phone_order_number, r.phone),
    'cliente', COALESCE(o.customer_name, 'cliente'),
    'hora', to_char(o.created_at AT TIME ZONE 'Europe/Lisbon', 'HH24:MI'),
    'itens', v_txt,
    'notas', o.customer_notes,
    'total_balcao', ROUND(v_total, 2),
    'texto', 'Pedido ' || left(o.id, 8) || ' · ' || r.name || ' · '
             || to_char(o.created_at AT TIME ZONE 'Europe/Lisbon', 'HH24:MI')
             || E'\nCliente: ' || COALESCE(o.customer_name, 'cliente')
             || v_txt
             || CASE WHEN COALESCE(o.customer_notes, '') <> '' THEN E'\nNotas: ' || o.customer_notes ELSE '' END
             || E'\nTOTAL BALCÃO: ' || to_char(ROUND(v_total, 2), 'FM9990.00') || ' €'
             || E'\nLigar: ' || COALESCE(r.phone_order_number, r.phone, '?'));
END $f$;
REVOKE ALL ON FUNCTION public.encomenda_telefone_resumo(text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.encomenda_telefone_resumo(text) TO authenticated;

CREATE OR REPLACE FUNCTION public._encomenda_telefone_alertar(p_order_id text, p_vez int)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $f$
DECLARE j jsonb; v_msg text;
BEGIN
  j := public.encomenda_telefone_resumo(p_order_id);
  IF j IS NULL THEN RETURN; END IF;
  v_msg := CASE WHEN p_vez <= 1 THEN '📞 LIGAR À LOJA — pedido novo'
                ELSE '📞 AINDA POR ENCOMENDAR (' || p_vez || '.º aviso)' END
        || E'\n' || (j->>'texto')
        || E'\nNo painel: "Encomendado à loja" depois de ligar.';
  BEGIN PERFORM public._telegram_admin(v_msg);
  EXCEPTION WHEN others THEN RAISE WARNING 'encomenda_telefone: telegram falhou: %', sqlerrm; END;
  BEGIN
    PERFORM public.notify_admin_urgent_push(
      'phone_order_call', v_msg, 'order', p_order_id,
      jsonb_build_object('telefone', j->>'telefone', 'tel_link', 'tel:' || replace(COALESCE(j->>'telefone', ''), ' ', ''),
                         'total_balcao', j->'total_balcao', 'aviso', p_vez),
      '/admin/encomendas-telefone');
  EXCEPTION WHEN others THEN RAISE WARNING 'encomenda_telefone: push falhou: %', sqlerrm; END;
  UPDATE public.encomendas_telefone
     SET alertas = p_vez, ultimo_alerta_em = now(),
         resumo = j->>'texto', total_balcao = (j->>'total_balcao')::numeric
   WHERE order_id = p_order_id;
END $f$;
REVOKE ALL ON FUNCTION public._encomenda_telefone_alertar(text, int) FROM PUBLIC, anon, authenticated;

-- ── 4. Porteiro ────────────────────────────────────────────────────────────
-- Nome começa por "aa_" para correr ANTES dos outros gatilhos BEFORE (o que
-- marca dispatch_calling_since, o pré-atribuído, etc. passam a ver 'preparing').
CREATE OR REPLACE FUNCTION public.fn_orders_encomenda_telefone_porteiro()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $f$
DECLARE
  r record; e record; v_base timestamptz;
BEGIN
  IF NEW.status IS DISTINCT FROM 'callingDriver'
     OR (TG_OP = 'UPDATE' AND OLD.status IS NOT DISTINCT FROM 'callingDriver')
     OR NEW.restaurant_id IS NULL
     OR COALESCE(current_setting('app.phone_order_release', true), '') = 'true' THEN
    RETURN NEW;
  END IF;
  SELECT order_by_phone, is_partner, dispatch_delay_minutes, phone_prep_minutes INTO r
    FROM public.restaurants WHERE id = NEW.restaurant_id;
  IF NOT FOUND OR NOT COALESCE(r.order_by_phone, false) OR COALESCE(r.is_partner, false) THEN
    RETURN NEW;
  END IF;
  -- Por pagar (cartão/MB Way): não se liga à loja; o guarda de pagamento trata.
  IF COALESCE(NEW.payment_method, 'cash') IN ('card', 'mbway')
     AND COALESCE(NEW.payment_status, '') <> 'paid' THEN
    RETURN NEW;
  END IF;

  SELECT * INTO e FROM public.encomendas_telefone WHERE order_id = NEW.id;
  IF FOUND THEN
    v_base := COALESCE(e.encomendado_em, NEW.created_at, now());
    IF now() >= v_base + make_interval(mins => r.dispatch_delay_minutes) THEN
      UPDATE public.encomendas_telefone SET libertado_em = now()
       WHERE order_id = NEW.id AND libertado_em IS NULL;
      RETURN NEW;   -- já passou a hora: segue para o despacho
    END IF;
  ELSE
    INSERT INTO public.encomendas_telefone(order_id, restaurant_id)
    VALUES (NEW.id, NEW.restaurant_id) ON CONFLICT (order_id) DO NOTHING;
    -- o alerta lê o pedido; num INSERT ele ainda não existe → o relógio avisa
    -- no minuto seguinte. Num UPDATE avisa já.
    IF TG_OP = 'UPDATE' THEN
      PERFORM public._encomenda_telefone_alertar(NEW.id, 1);
    END IF;
  END IF;

  NEW.status := 'preparing';
  NEW.prep_time_minutes := COALESCE(NEW.prep_time_minutes, r.phone_prep_minutes);
  RETURN NEW;
END $f$;

DROP TRIGGER IF EXISTS aa_orders_encomenda_telefone_porteiro ON public.orders;
CREATE TRIGGER aa_orders_encomenda_telefone_porteiro
  BEFORE INSERT OR UPDATE OF status ON public.orders
  FOR EACH ROW EXECUTE FUNCTION public.fn_orders_encomenda_telefone_porteiro();

-- ── 5. Relógio ─────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.encomendas_telefone_relogio()
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $f$
DECLARE
  x record; v_alertas int := 0; v_libertados int := 0; v_n int;
BEGIN
  FOR x IN
    SELECT e.*, o.status AS o_status, o.created_at AS o_criado, r.dispatch_delay_minutes AS atraso
      FROM public.encomendas_telefone e
      JOIN public.orders o ON o.id = e.order_id
      JOIN public.restaurants r ON r.id = e.restaurant_id
     WHERE e.libertado_em IS NULL AND e.cancelado_em IS NULL
  LOOP
    IF x.o_status IN ('cancelled', 'rejected', 'delivered') THEN
      UPDATE public.encomendas_telefone SET cancelado_em = now() WHERE order_id = x.order_id;
      CONTINUE;
    END IF;
    IF x.o_status <> 'preparing' THEN
      -- outro caminho já o tirou de 'preparing' (ex.: admin): deixa de vigiar.
      UPDATE public.encomendas_telefone SET libertado_em = now() WHERE order_id = x.order_id;
      CONTINUE;
    END IF;
    -- Alertas: 1.º logo; repete aos 3 e aos 6 minutos se ninguém encomendou.
    IF x.encomendado_em IS NULL AND (
         (x.alertas = 0)
      OR (x.alertas = 1 AND now() >= x.criado_em + interval '3 minutes')
      OR (x.alertas = 2 AND now() >= x.criado_em + interval '6 minutes')) THEN
      PERFORM public._encomenda_telefone_alertar(x.order_id, x.alertas + 1);
      v_alertas := v_alertas + 1;
    END IF;
    -- Libertar para o despacho quando passa a hora.
    IF now() >= COALESCE(x.encomendado_em, x.o_criado) + make_interval(mins => x.atraso) THEN
      PERFORM set_config('app.phone_order_release', 'true', true);
      PERFORM set_config('app.order_transition_source', 'encomendas_telefone_relogio', true);
      BEGIN
        UPDATE public.orders SET status = 'callingDriver'
         WHERE id = x.order_id AND status = 'preparing';
        GET DIAGNOSTICS v_n = ROW_COUNT;
        IF v_n = 1 THEN
          UPDATE public.encomendas_telefone SET libertado_em = now() WHERE order_id = x.order_id;
          v_libertados := v_libertados + 1;
        END IF;
      EXCEPTION WHEN others THEN
        RAISE WARNING 'encomendas_telefone_relogio: % não libertou: %', x.order_id, sqlerrm;
      END;
      PERFORM set_config('app.phone_order_release', 'false', true);
    END IF;
  END LOOP;
  RETURN jsonb_build_object('alertas', v_alertas, 'libertados', v_libertados);
END $f$;
REVOKE ALL ON FUNCTION public.encomendas_telefone_relogio() FROM PUBLIC, anon, authenticated;

SELECT cron.unschedule(jobid) FROM cron.job WHERE jobname = 'encomendas-telefone-relogio';
SELECT cron.schedule('encomendas-telefone-relogio', '* * * * *',
                     $$SELECT public.encomendas_telefone_relogio();$$);

-- ── 6. Painel admin ────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.admin_encomendado_a_loja(p_order_id text)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $f$
DECLARE v_nome text; v_atraso int; v_prep int; v_n int;
BEGIN
  IF NOT public.is_admin() THEN RAISE EXCEPTION 'so_admin' USING ERRCODE = '42501'; END IF;
  SELECT COALESCE(u.name, u.email) INTO v_nome FROM public.users u WHERE u.id = auth.uid();
  UPDATE public.encomendas_telefone
     SET encomendado_em = now(), encomendado_por = auth.uid(), encomendado_por_nome = v_nome
   WHERE order_id = p_order_id AND encomendado_em IS NULL AND cancelado_em IS NULL;
  GET DIAGNOSTICS v_n = ROW_COUNT;
  IF v_n = 0 THEN RETURN jsonb_build_object('ok', false, 'motivo', 'ja_encomendado_ou_inexistente'); END IF;
  SELECT r.dispatch_delay_minutes, r.phone_prep_minutes INTO v_atraso, v_prep
    FROM public.encomendas_telefone e JOIN public.restaurants r ON r.id = e.restaurant_id
   WHERE e.order_id = p_order_id;
  -- O cliente passa a ver "pronto por volta de" contado a partir da chamada.
  UPDATE public.orders
     SET prep_time_minutes = CEIL(EXTRACT(epoch FROM now() - created_at) / 60)::int + v_prep
   WHERE id = p_order_id AND status = 'preparing';
  RETURN jsonb_build_object('ok', true, 'estafeta_chamado_as',
    to_char((now() + make_interval(mins => v_atraso)) AT TIME ZONE 'Europe/Lisbon', 'HH24:MI'));
END $f$;
REVOKE ALL ON FUNCTION public.admin_encomendado_a_loja(text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.admin_encomendado_a_loja(text) TO authenticated;

CREATE OR REPLACE FUNCTION public.admin_listar_encomendas_telefone(p_dias int DEFAULT 7)
RETURNS TABLE (order_id text, loja text, telefone text, criado_em timestamptz, alertas int,
               encomendado_em timestamptz, encomendado_por_nome text, libertado_em timestamptz,
               cancelado_em timestamptz, estado_pedido text, resumo text, total_balcao numeric,
               chama_estafeta_as timestamptz)
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path TO 'public' AS $f$
BEGIN
  IF NOT public.is_admin() THEN RAISE EXCEPTION 'so_admin' USING ERRCODE = '42501'; END IF;
  RETURN QUERY
  SELECT e.order_id, r.name, COALESCE(r.phone_order_number, r.phone), e.criado_em, e.alertas,
         e.encomendado_em, e.encomendado_por_nome, e.libertado_em, e.cancelado_em, o.status::text,
         COALESCE(e.resumo, public.encomenda_telefone_resumo(e.order_id)->>'texto'),
         COALESCE(e.total_balcao, (public.encomenda_telefone_resumo(e.order_id)->>'total_balcao')::numeric),
         COALESCE(e.encomendado_em, o.created_at) + make_interval(mins => r.dispatch_delay_minutes)
    FROM public.encomendas_telefone e
    JOIN public.orders o ON o.id = e.order_id
    JOIN public.restaurants r ON r.id = e.restaurant_id
   WHERE e.criado_em > now() - make_interval(days => p_dias)
   ORDER BY (e.libertado_em IS NULL AND e.cancelado_em IS NULL) DESC, e.criado_em DESC;
END $f$;
REVOKE ALL ON FUNCTION public.admin_listar_encomendas_telefone(int) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.admin_listar_encomendas_telefone(int) TO authenticated;

CREATE OR REPLACE FUNCTION public.admin_definir_loja_telefone(
  p_restaurant_id text, p_ligado boolean, p_numero text, p_atraso int, p_prep int)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $f$
BEGIN
  IF NOT public.is_admin() THEN RAISE EXCEPTION 'so_admin' USING ERRCODE = '42501'; END IF;
  UPDATE public.restaurants
     SET order_by_phone = p_ligado,
         phone_order_number = NULLIF(trim(p_numero), ''),
         dispatch_delay_minutes = LEAST(GREATEST(COALESCE(p_atraso, 15), 0), 120),
         phone_prep_minutes = LEAST(GREATEST(COALESCE(p_prep, 20), 0), 180)
   WHERE id = p_restaurant_id;
  RETURN jsonb_build_object('ok', FOUND);
END $f$;
REVOKE ALL ON FUNCTION public.admin_definir_loja_telefone(text, boolean, text, int, int) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.admin_definir_loja_telefone(text, boolean, text, int, int) TO authenticated;

-- Para o estafeta: "Pagar ao balcão: X €" (preço da loja, sem os 15%).
-- Só o estafeta do pedido (ou a quem está a ser oferecido) e o admin.
CREATE OR REPLACE FUNCTION public.pedido_total_balcao(p_order_id text)
RETURNS numeric LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path TO 'public' AS $f$
DECLARE o public.orders%ROWTYPE;
BEGIN
  SELECT * INTO o FROM public.orders WHERE id = p_order_id;
  IF NOT FOUND THEN RETURN NULL; END IF;
  IF NOT (public.is_admin()
          OR o.assigned_driver_id = auth.uid()::text
          OR o.current_driver_offer_id = auth.uid()::text) THEN
    RETURN NULL;
  END IF;
  RETURN (public.encomenda_telefone_resumo(p_order_id)->>'total_balcao')::numeric;
END $f$;
REVOKE ALL ON FUNCTION public.pedido_total_balcao(text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.pedido_total_balcao(text) TO authenticated;
