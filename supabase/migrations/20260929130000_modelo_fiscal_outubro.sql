-- Modelo fiscal a partir de 01/10/2026 (missão fecho-mensal-2026-09, B6A/B6B/B6C).
-- Decisão do Danilo (29/09): o estafeta fatura a parte dele; a Bora cobra por conta
-- dele (mandatária/agente de cobrança) e só declara a sua taxa.
-- NÃO mexe em preços, comissões nem no que o estafeta ganha. Só muda quem fatura o quê.

-- =====================================================================
-- B6A.1 — Termos e condições com versão e aceitação obrigatória
-- =====================================================================
CREATE TABLE IF NOT EXISTS public.legal_terms_versions (
  version text NOT NULL,
  audience text NOT NULL CHECK (audience IN ('cliente','estafeta')),
  effective_date date NOT NULL,
  title text NOT NULL,
  body text NOT NULL,
  created_at timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (version, audience));
ALTER TABLE public.legal_terms_versions ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS legal_terms_versions_read ON public.legal_terms_versions;
CREATE POLICY legal_terms_versions_read ON public.legal_terms_versions
  FOR SELECT TO anon, authenticated USING (true);

CREATE TABLE IF NOT EXISTS public.legal_terms_acceptances (
  user_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  audience text NOT NULL,
  version text NOT NULL,
  accepted_at timestamptz NOT NULL DEFAULT now(),
  platform text,
  PRIMARY KEY (user_id, audience, version));
ALTER TABLE public.legal_terms_acceptances ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS legal_terms_acceptances_own ON public.legal_terms_acceptances;
CREATE POLICY legal_terms_acceptances_own ON public.legal_terms_acceptances
  FOR SELECT TO authenticated USING (user_id = auth.uid() OR public.is_admin());

-- Devolve a versão em vigor que o utilizador ainda NÃO aceitou (ou null).
CREATE OR REPLACE FUNCTION public.legal_terms_pending(p_audience text)
RETURNS jsonb
LANGUAGE sql STABLE SECURITY DEFINER SET search_path TO 'public'
AS $$
  SELECT to_jsonb(v) FROM public.legal_terms_versions v
   WHERE v.audience = p_audience AND auth.uid() IS NOT NULL
     AND NOT EXISTS (SELECT 1 FROM public.legal_terms_acceptances a
                      WHERE a.user_id = auth.uid() AND a.audience = v.audience AND a.version = v.version)
   ORDER BY v.effective_date DESC, v.created_at DESC
   LIMIT 1;
$$;
REVOKE ALL ON FUNCTION public.legal_terms_pending(text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.legal_terms_pending(text) TO authenticated;

CREATE OR REPLACE FUNCTION public.legal_terms_accept(p_audience text, p_version text, p_platform text DEFAULT NULL)
RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public'
AS $$
BEGIN
  IF auth.uid() IS NULL THEN RAISE EXCEPTION 'sem_sessao'; END IF;
  IF NOT EXISTS (SELECT 1 FROM public.legal_terms_versions WHERE audience = p_audience AND version = p_version) THEN
    RAISE EXCEPTION 'versao_desconhecida';
  END IF;
  INSERT INTO public.legal_terms_acceptances (user_id, audience, version, platform)
  VALUES (auth.uid(), p_audience, p_version, p_platform)
  ON CONFLICT (user_id, audience, version) DO NOTHING;
  RETURN jsonb_build_object('ok', true, 'version', p_version);
END $$;
REVOKE ALL ON FUNCTION public.legal_terms_accept(text, text, text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.legal_terms_accept(text, text, text) TO authenticated;

INSERT INTO public.legal_terms_versions (version, audience, effective_date, title, body) VALUES
('2026-10-01', 'cliente', '2026-10-01', 'Termos e Condições — versão de 01/10/2026',
$t$A partir de 1 de outubro de 2026 mudam os Termos e Condições da Bora. O que muda para si:

1. A Bora é uma plataforma de intermediação. Liga-o às lojas (restaurantes, mercados, farmácias e outras) e aos estafetas independentes que fazem as entregas.

2. O valor da entrega pertence ao estafeta. Cada estafeta é um profissional independente, com atividade aberta nas Finanças, e é ele quem presta o serviço de entrega. A Bora recebe esse valor em nome e por conta do estafeta e entrega-lho no acerto semanal.

3. Os produtos pertencem à loja. O preço dos produtos é recebido pela Bora por conta da loja (lojas parceiras) ou corresponde à compra feita em seu nome pelo estafeta (lojas não parceiras).

4. A Bora cobra apenas as suas próprias taxas: taxa de serviço, sacos, taxa de pedido pequeno e a sua comissão ou margem. É sobre essa parte que a Bora emite fatura.

5. Os preços que paga não mudam. O total do pedido continua a ser o que vê no ecrã antes de confirmar.

6. Se indicar o seu NIF, a fatura da parte da Bora sai em seu nome; se não indicar, sai como consumidor final.

7. Problemas com um produto resolvem-se com a loja; problemas com a entrega podem ser comunicados à Bora pelo suporte na app, que os encaminha ao estafeta.

Ao tocar em "Aceito" confirma que leu e aceita estes termos.$t$),
('2026-10-01', 'estafeta', '2026-10-01', 'Termos e Condições do Estafeta — versão de 01/10/2026',
$t$A partir de 1 de outubro de 2026 mudam as regras entre a Bora e os estafetas. O que muda para si:

1. É um profissional independente. Presta o serviço de entrega por sua conta, sem contrato de trabalho com a Bora.

2. O valor da entrega é seu. O que ganha em cada entrega (o número grande que vê na oferta) é pago pelo cliente a si. A Bora apenas o recebe em seu nome e por sua conta (agente de cobrança) e entrega-lho no acerto semanal, como já acontece hoje.

3. Tem de ter atividade aberta nas Finanças e indicar o seu NIF na app. Quem já trabalha com a Bora tem 14 dias (até 15/10/2026) para o fazer; depois disso não pode aceitar entregas enquanto não o fizer.

4. Uma vez por mês passa um recibo verde. No dia 1 de cada mês a app mostra-lhe o total do mês anterior e o texto pronto para o recibo ("Serviços de entrega — N entregas intermediadas pela plataforma Bora"), a consumidor final. Depois de o passar, toca em "Já passei o recibo" e indica o número.

5. O que ganha não muda. Os valores por entrega, os bónus e os tokens continuam iguais.

6. A Bora comunica às Finanças, uma vez por ano, o total que lhe pagou (obrigação DAC7 das plataformas digitais).

Ao tocar em "Aceito" confirma que leu e aceita estes termos.$t$)
ON CONFLICT (version, audience) DO NOTHING;

-- =====================================================================
-- B6A.2 — NIF + "atividade aberta nas Finanças" do estafeta
-- =====================================================================
INSERT INTO public.platform_settings (key, value, description, category) VALUES
  ('estafeta_fiscal_em_vigor_desde', '"2026-10-01"'::jsonb,
   'Data a partir da qual o estafeta fatura a sua parte (recibo verde).', 'fiscal'),
  ('estafeta_fiscal_prazo', '"2026-10-15"'::jsonb,
   'Até esta data (exclusive, hora de Lisboa) quem já trabalha só vê aviso; a partir dela sem NIF+atividade não aceita entregas.', 'fiscal')
ON CONFLICT (key) DO NOTHING;

CREATE TABLE IF NOT EXISTS public.driver_fiscal_status (
  user_id uuid PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
  nif text,
  atividade_aberta boolean NOT NULL DEFAULT false,
  confirmado_em timestamptz,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now());
ALTER TABLE public.driver_fiscal_status ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS driver_fiscal_status_own ON public.driver_fiscal_status;
CREATE POLICY driver_fiscal_status_own ON public.driver_fiscal_status
  FOR SELECT TO authenticated USING (user_id = auth.uid() OR public.is_admin());

-- NIF português: 9 dígitos + controlo mod 11 (mesma regra de LegalFieldsValidators).
CREATE OR REPLACE FUNCTION public._nif_valido(p_nif text)
RETURNS boolean LANGUAGE plpgsql IMMUTABLE
AS $$
DECLARE d text := regexp_replace(coalesce(p_nif,''), '\D', '', 'g'); s int := 0; c int; i int;
BEGIN
  IF length(d) <> 9 OR d IN ('111111111','123456789','999999999','000000000') THEN RETURN false; END IF;
  IF substr(d,1,1) NOT IN ('1','2','3','5','6','8','9') THEN RETURN false; END IF;
  FOR i IN 1..8 LOOP s := s + substr(d,i,1)::int * (10 - i); END LOOP;
  c := 11 - (s % 11); IF c >= 10 THEN c := 0; END IF;
  RETURN c = substr(d,9,1)::int;
END $$;

CREATE OR REPLACE FUNCTION public.driver_fiscal_status_get()
RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path TO 'public'
AS $$
DECLARE
  v_uid uuid := auth.uid(); v_nif text; v_ok boolean := false; v_em timestamptz;
  v_desde date; v_prazo date; v_hoje date := (now() AT TIME ZONE 'Europe/Lisbon')::date;
BEGIN
  IF v_uid IS NULL THEN RAISE EXCEPTION 'sem_sessao'; END IF;
  SELECT (value #>> '{}')::date INTO v_desde FROM public.platform_settings WHERE key = 'estafeta_fiscal_em_vigor_desde';
  SELECT (value #>> '{}')::date INTO v_prazo FROM public.platform_settings WHERE key = 'estafeta_fiscal_prazo';
  v_desde := coalesce(v_desde, date '2026-10-01'); v_prazo := coalesce(v_prazo, date '2026-10-15');
  SELECT f.nif, f.atividade_aberta, f.confirmado_em INTO v_nif, v_ok, v_em
    FROM public.driver_fiscal_status f WHERE f.user_id = v_uid;
  IF v_nif IS NULL THEN SELECT d.nif INTO v_nif FROM public.drivers d WHERE d.user_id = v_uid; END IF;
  v_ok := coalesce(v_ok, false) AND public._nif_valido(v_nif);
  RETURN jsonb_build_object(
    'nif', v_nif, 'atividade_aberta', v_ok, 'confirmado_em', v_em,
    'em_vigor_desde', v_desde, 'prazo', v_prazo,
    'completo', v_ok,
    'mostrar_aviso', NOT v_ok,
    'dias_restantes', greatest(v_prazo - v_hoje, 0),
    'bloqueado', (NOT v_ok) AND v_hoje >= v_prazo);
END $$;
REVOKE ALL ON FUNCTION public.driver_fiscal_status_get() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.driver_fiscal_status_get() TO authenticated;

CREATE OR REPLACE FUNCTION public.driver_confirm_fiscal_activity(p_nif text)
RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public'
AS $$
DECLARE v_uid uuid := auth.uid(); v_nif text := regexp_replace(coalesce(p_nif,''), '\D', '', 'g');
BEGIN
  IF v_uid IS NULL THEN RAISE EXCEPTION 'sem_sessao'; END IF;
  IF NOT EXISTS (SELECT 1 FROM public.drivers WHERE user_id = v_uid) THEN RAISE EXCEPTION 'nao_e_estafeta'; END IF;
  IF NOT public._nif_valido(v_nif) THEN RAISE EXCEPTION 'nif_invalido'; END IF;
  INSERT INTO public.driver_fiscal_status (user_id, nif, atividade_aberta, confirmado_em, updated_at)
  VALUES (v_uid, v_nif, true, now(), now())
  ON CONFLICT (user_id) DO UPDATE SET nif = excluded.nif, atividade_aberta = true,
                                      confirmado_em = now(), updated_at = now();
  RETURN public.driver_fiscal_status_get();
END $$;
REVOKE ALL ON FUNCTION public.driver_confirm_fiscal_activity(text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.driver_confirm_fiscal_activity(text) TO authenticated;

-- =====================================================================
-- B6A.3 — Resumo mensal para o recibo verde do estafeta
-- =====================================================================
CREATE TABLE IF NOT EXISTS public.driver_monthly_invoices (
  user_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  ano int NOT NULL,
  mes int NOT NULL CHECK (mes BETWEEN 1 AND 12),
  total_faturar numeric NOT NULL DEFAULT 0,
  entregas int NOT NULL DEFAULT 0,
  recibo_numero text,
  recibo_data date,
  marcado_em timestamptz,
  created_at timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (user_id, ano, mes));
ALTER TABLE public.driver_monthly_invoices ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS driver_monthly_invoices_own ON public.driver_monthly_invoices;
CREATE POLICY driver_monthly_invoices_own ON public.driver_monthly_invoices
  FOR SELECT TO authenticated USING (user_id = auth.uid() OR public.is_admin());

-- Estafeta: só a linha dele. Admin: todos os que entregaram no mês.
CREATE OR REPLACE FUNCTION public.driver_monthly_invoice_summary(p_year int, p_month int)
RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path TO 'public'
AS $$
DECLARE v_ini timestamptz; v_fim timestamptz; v_admin boolean := public.is_admin(); v_out jsonb;
  v_nome_mes text := (ARRAY['janeiro','fevereiro','março','abril','maio','junho','julho',
                            'agosto','setembro','outubro','novembro','dezembro'])[p_month];
BEGIN
  IF auth.uid() IS NULL AND coalesce(auth.jwt()->>'role','') <> 'service_role' THEN RAISE EXCEPTION 'sem_sessao'; END IF;
  IF p_month NOT BETWEEN 1 AND 12 THEN RAISE EXCEPTION 'mes_invalido'; END IF;
  SELECT ini, fim INTO v_ini, v_fim FROM public._fecho_limites(p_year, p_month);
  SELECT coalesce(jsonb_agg(jsonb_build_object(
           'user_id', x.driver_user_id, 'nome', d.name,
           'nif', coalesce(fs.nif, d.nif),
           'atividade_aberta', coalesce(fs.atividade_aberta, false),
           'ano', p_year, 'mes', p_month,
           'entregas', x.n, 'total_a_faturar', x.total,
           'cliente', 'Consumidor final',
           'texto_recibo', format('Serviços de entrega — %s entregas intermediadas pela plataforma Bora, mês de %s de %s',
                                  x.n, v_nome_mes, p_year),
           'iva', 'IVA — regime de isenção (art. 53.º CIVA)',
           'recibo_numero', mi.recibo_numero, 'recibo_data', mi.recibo_data, 'marcado_em', mi.marcado_em,
           'recibo_passado', mi.marcado_em IS NOT NULL)
         ORDER BY d.name), '[]'::jsonb)
    INTO v_out
    FROM (SELECT driver_user_id, count(*) n, sum(estafeta) total
            FROM public._fecho_pedidos(v_ini, v_fim)
           WHERE driver_user_id IS NOT NULL
             AND (v_admin OR coalesce(auth.jwt()->>'role','') = 'service_role'
                  OR driver_user_id = auth.uid()::text)
           GROUP BY driver_user_id) x
    LEFT JOIN public.drivers d ON d.user_id::text = x.driver_user_id
    LEFT JOIN public.driver_fiscal_status fs ON fs.user_id::text = x.driver_user_id
    LEFT JOIN public.driver_monthly_invoices mi
           ON mi.user_id::text = x.driver_user_id AND mi.ano = p_year AND mi.mes = p_month;
  RETURN jsonb_build_object('ano', p_year, 'mes', p_month, 'nome_mes', v_nome_mes, 'estafetas', v_out);
END $$;
REVOKE ALL ON FUNCTION public.driver_monthly_invoice_summary(int, int) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.driver_monthly_invoice_summary(int, int) TO authenticated, service_role;

CREATE OR REPLACE FUNCTION public.driver_mark_invoice_issued(p_year int, p_month int, p_numero text, p_data date DEFAULT NULL)
RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public'
AS $$
DECLARE v_uid uuid := auth.uid(); v_ini timestamptz; v_fim timestamptz; v_n int; v_total numeric;
BEGIN
  IF v_uid IS NULL THEN RAISE EXCEPTION 'sem_sessao'; END IF;
  IF coalesce(trim(p_numero),'') = '' THEN RAISE EXCEPTION 'numero_em_falta'; END IF;
  SELECT ini, fim INTO v_ini, v_fim FROM public._fecho_limites(p_year, p_month);
  SELECT count(*), coalesce(sum(estafeta),0) INTO v_n, v_total
    FROM public._fecho_pedidos(v_ini, v_fim) WHERE driver_user_id = v_uid::text;
  INSERT INTO public.driver_monthly_invoices (user_id, ano, mes, total_faturar, entregas, recibo_numero, recibo_data, marcado_em)
  VALUES (v_uid, p_year, p_month, v_total, v_n, trim(p_numero),
          coalesce(p_data, (now() AT TIME ZONE 'Europe/Lisbon')::date), now())
  ON CONFLICT (user_id, ano, mes) DO UPDATE
     SET recibo_numero = excluded.recibo_numero, recibo_data = excluded.recibo_data,
         total_faturar = excluded.total_faturar, entregas = excluded.entregas, marcado_em = now();
  RETURN jsonb_build_object('ok', true, 'total_faturar', v_total, 'entregas', v_n);
END $$;
REVOKE ALL ON FUNCTION public.driver_mark_invoice_issued(int, int, text, date) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.driver_mark_invoice_issued(int, int, text, date) TO authenticated;

-- Dia 10: avisa o admin de quem ainda não passou o recibo do mês anterior.
CREATE OR REPLACE FUNCTION public.aviso_recibos_estafetas_em_falta()
RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public'
AS $$
DECLARE
  v_ref date := ((now() AT TIME ZONE 'Europe/Lisbon')::date - interval '1 month')::date;
  v_ano int := extract(year FROM v_ref); v_mes int := extract(month FROM v_ref);
  v_lista jsonb; v_txt text; v_req bigint;
BEGIN
  IF make_date(v_ano, v_mes, 1) < date '2026-10-01' THEN
    RETURN jsonb_build_object('ok', true, 'nota', 'modelo ainda não estava em vigor');
  END IF;
  PERFORM set_config('request.jwt.claims', '{"role":"service_role"}', true);
  SELECT coalesce(jsonb_agg(e), '[]'::jsonb) INTO v_lista
    FROM jsonb_array_elements(public.driver_monthly_invoice_summary(v_ano, v_mes)->'estafetas') e
   WHERE NOT coalesce((e->>'recibo_passado')::boolean, false);
  IF jsonb_array_length(v_lista) = 0 THEN
    RETURN jsonb_build_object('ok', true, 'em_falta', 0);
  END IF;
  SELECT string_agg('• ' || coalesce(e->>'nome','?') || ' — ' || (e->>'total_a_faturar') || ' € (' || (e->>'entregas') || ' entregas)', chr(10))
    INTO v_txt FROM jsonb_array_elements(v_lista) e;
  SELECT net.http_post(
    url := (SELECT decrypted_secret FROM vault.decrypted_secrets WHERE name='project_url') || '/functions/v1/notify-admin-urgent',
    headers := jsonb_build_object('Authorization', 'Bearer ' || (SELECT decrypted_secret FROM vault.decrypted_secrets WHERE name='service_role_key'),
                                  'Content-Type', 'application/json'),
    body := jsonb_build_object('kind', 'generic',
                               'title', 'Recibos verdes em falta (' || v_mes || '/' || v_ano || ')',
                               'body', left('Estes estafetas ainda não passaram o recibo:' || chr(10) || v_txt, 900),
                               'route', '/admin/fecho-mensal',
                               'ref', 'recibos_estafetas_' || v_ano || '_' || v_mes)
  ) INTO v_req;
  RETURN jsonb_build_object('ok', true, 'em_falta', jsonb_array_length(v_lista), 'request_id', v_req);
END $$;
REVOKE ALL ON FUNCTION public.aviso_recibos_estafetas_em_falta() FROM PUBLIC, anon, authenticated;

-- =====================================================================
-- B6B — Fatura da Bora por pedido (a partir de 01/10/2026)
-- =====================================================================
CREATE TABLE IF NOT EXISTS public.bora_invoices_pending (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  order_id text NOT NULL UNIQUE,
  data date NOT NULL,
  valor numeric NOT NULL DEFAULT 0,
  cliente_nif text,
  cliente_nome text NOT NULL DEFAULT 'Consumidor final',
  descricao text NOT NULL DEFAULT 'Taxa de serviço e intermediação — plataforma Bora',
  iva text NOT NULL DEFAULT 'IVA — regime de isenção (art. 53.º CIVA), M10',
  estado text NOT NULL DEFAULT 'por_lancar' CHECK (estado IN ('por_lancar','lancada','sem_valor')),
  numero_documento text,
  lancada_em timestamptz,
  created_at timestamptz NOT NULL DEFAULT now());
ALTER TABLE public.bora_invoices_pending ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS bora_invoices_pending_admin ON public.bora_invoices_pending;
CREATE POLICY bora_invoices_pending_admin ON public.bora_invoices_pending
  FOR SELECT TO authenticated USING (public.is_admin());

-- Valor = receita da Bora no pedido no modelo novo (pago − mercadoria − estafeta).
CREATE OR REPLACE FUNCTION public._bora_invoice_upsert(p_order_id text)
RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public'
AS $$
DECLARE f record; v_dt timestamptz;
BEGIN
  SELECT delivered_at INTO v_dt FROM public.orders WHERE id = p_order_id;
  IF v_dt IS NULL OR v_dt < make_timestamptz(2026,10,1,0,0,0,'Europe/Lisbon') THEN RETURN; END IF;
  SELECT * INTO f FROM public._fecho_pedidos(v_dt - interval '1 second', v_dt + interval '1 second') x
   WHERE x.order_id = p_order_id;
  IF NOT FOUND THEN RETURN; END IF;
  INSERT INTO public.bora_invoices_pending (order_id, data, valor, estado)
  VALUES (p_order_id, (v_dt AT TIME ZONE 'Europe/Lisbon')::date, greatest(f.lucro, 0),
          CASE WHEN f.lucro > 0 THEN 'por_lancar' ELSE 'sem_valor' END)
  ON CONFLICT (order_id) DO UPDATE
     SET valor = excluded.valor, estado = excluded.estado
   WHERE public.bora_invoices_pending.estado <> 'lancada';
END $$;
REVOKE ALL ON FUNCTION public._bora_invoice_upsert(text) FROM PUBLIC, anon, authenticated;

-- Gatilho ao passar a 'delivered'. Nunca pode partir a entrega: qualquer erro
-- vira WARNING e o painel refaz a linha quando abre o mês.
CREATE OR REPLACE FUNCTION public.fn_bora_invoice_on_delivered()
RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public'
AS $$
BEGIN
  IF coalesce(NEW.is_test_order, false) THEN RETURN NULL; END IF;
  BEGIN
    PERFORM public._bora_invoice_upsert(NEW.id);
  EXCEPTION WHEN OTHERS THEN
    RAISE WARNING '[bora_invoice] pedido % : %', NEW.id, SQLERRM;
  END;
  RETURN NULL;
END $$;

DROP TRIGGER IF EXISTS zzzz_bora_fatura_on_delivered ON public.orders;
CREATE TRIGGER zzzz_bora_fatura_on_delivered
  AFTER UPDATE OF status ON public.orders
  FOR EACH ROW
  WHEN (NEW.status = 'delivered' AND OLD.status IS DISTINCT FROM 'delivered')
  EXECUTE FUNCTION public.fn_bora_invoice_on_delivered();

-- Lista do mês para o painel (refaz linhas em falta e recalcula as por lançar).
CREATE OR REPLACE FUNCTION public.admin_bora_invoices_month(p_year int, p_month int)
RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public'
AS $$
DECLARE v_ini timestamptz; v_fim timestamptz; v_id text; v_linhas jsonb; v_dias jsonb;
BEGIN
  IF NOT public.is_admin() THEN RAISE EXCEPTION 'admin_required'; END IF;
  SELECT ini, fim INTO v_ini, v_fim FROM public._fecho_limites(p_year, p_month);
  FOR v_id IN
    SELECT o.id FROM public.orders o
     WHERE o.status = 'delivered' AND coalesce(o.is_test_order,false) = false
       AND o.delivered_at >= greatest(v_ini, make_timestamptz(2026,10,1,0,0,0,'Europe/Lisbon'))
       AND o.delivered_at < v_fim
       AND coalesce(o.service_type,'') NOT ILIKE 'tvde%'
  LOOP
    PERFORM public._bora_invoice_upsert(v_id);
  END LOOP;
  SELECT coalesce(jsonb_agg(to_jsonb(b) ORDER BY b.data, b.created_at), '[]'::jsonb) INTO v_linhas
    FROM public.bora_invoices_pending b
   WHERE b.data >= (v_ini AT TIME ZONE 'Europe/Lisbon')::date AND b.data < (v_fim AT TIME ZONE 'Europe/Lisbon')::date;
  SELECT coalesce(jsonb_agg(jsonb_build_object('data', data, 'documentos', n, 'total', t,
                                               'por_lancar', pl) ORDER BY data), '[]'::jsonb) INTO v_dias
    FROM (SELECT data, count(*) FILTER (WHERE estado <> 'sem_valor') n,
                 sum(valor) t, count(*) FILTER (WHERE estado = 'por_lancar') pl
            FROM public.bora_invoices_pending
           WHERE data >= (v_ini AT TIME ZONE 'Europe/Lisbon')::date AND data < (v_fim AT TIME ZONE 'Europe/Lisbon')::date
           GROUP BY data) d;
  RETURN jsonb_build_object('ano', p_year, 'mes', p_month, 'linhas', v_linhas, 'por_dia', v_dias,
    'nota', 'Emitir no Portal das Finanças (fatura-recibo, isento art. 53.º, M10). Não é comunicado à AT automaticamente.');
END $$;
REVOKE ALL ON FUNCTION public.admin_bora_invoices_month(int, int) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.admin_bora_invoices_month(int, int) TO authenticated;

CREATE OR REPLACE FUNCTION public.admin_mark_bora_invoice(p_ids uuid[], p_numero text DEFAULT NULL)
RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public'
AS $$
DECLARE v_n int;
BEGIN
  IF NOT public.is_admin() THEN RAISE EXCEPTION 'admin_required'; END IF;
  UPDATE public.bora_invoices_pending
     SET estado = 'lancada', lancada_em = now(), numero_documento = coalesce(p_numero, numero_documento)
   WHERE id = ANY(p_ids) AND estado = 'por_lancar';
  GET DIAGNOSTICS v_n = ROW_COUNT;
  PERFORM public.log_admin_action('mark_bora_invoice', 'bora_invoices_pending', coalesce(p_numero,'sem numero'),
                                  jsonb_build_object('ids', p_ids, 'n', v_n));
  RETURN jsonb_build_object('ok', true, 'marcadas', v_n);
END $$;
REVOKE ALL ON FUNCTION public.admin_mark_bora_invoice(uuid[], text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.admin_mark_bora_invoice(uuid[], text) TO authenticated;

-- =====================================================================
-- B6C — Relatório DAC7 (só prepara, não envia)
-- Reaproveita admin_dac7_export (estafetas, parceiros, faxineiros, lavadores,
-- feito a 23/09) e junta o que lhe faltava: os prestadores de serviços
-- (barbearias/salões, appointment_payouts) e o NIF dado na confirmação fiscal.
-- =====================================================================
CREATE OR REPLACE FUNCTION public.admin_dac7_report(p_year int)
RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path TO 'public'
AS $$
DECLARE
  v_base jsonb; v_prov jsonb; v_linhas jsonb;
  v_ini timestamptz := make_timestamptz(p_year, 1, 1, 0, 0, 0, 'Europe/Lisbon');
  v_fim timestamptz := make_timestamptz(p_year + 1, 1, 1, 0, 0, 0, 'Europe/Lisbon');
BEGIN
  IF NOT public.is_admin() THEN RAISE EXCEPTION 'not_admin'; END IF;
  v_base := public.admin_dac7_export(p_year);

  WITH t AS (
    SELECT a.provider_id,
           extract(quarter FROM (a.week_start_at AT TIME ZONE 'Europe/Lisbon'))::int tri,
           coalesce(a.net_payout_cents,0)::bigint cents,
           (coalesce(a.bora_deposit_cut_cents,0))::bigint com,
           coalesce(a.total_appointments,0) + coalesce(a.total_walkins,0) n
      FROM public.appointment_payouts a
     WHERE a.week_start_at >= v_ini AND a.week_start_at < v_fim)
  SELECT coalesce(jsonb_agg(jsonb_build_object(
           'ano', p_year, 'tipo', 'service_provider', 'id', t.provider_id,
           'nome', coalesce(sp.legal_name, sp.name), 'nome_comercial', sp.name,
           'nif', sp.nif, 'morada', sp.address, 'data_nascimento', sp.birth_date, 'iban', sp.iban, 'pais', 'PT',
           'autocertificado_em', sp.dsa_self_certified_at,
           'trimestre_1_cents', t.t1, 'trimestre_2_cents', t.t2, 'trimestre_3_cents', t.t3, 'trimestre_4_cents', t.t4,
           'total_cents', t.total, 'comissoes_bora_cents', t.com, 'transacoes', t.n,
           'campos_em_falta', to_jsonb(coalesce(public._conformidade_em_falta(coalesce(to_jsonb(sp), '{}'::jsonb)), ARRAY[]::text[])))),
         '[]'::jsonb)
    INTO v_prov
    FROM (SELECT provider_id,
                 coalesce(sum(cents) FILTER (WHERE tri=1),0) t1, coalesce(sum(cents) FILTER (WHERE tri=2),0) t2,
                 coalesce(sum(cents) FILTER (WHERE tri=3),0) t3, coalesce(sum(cents) FILTER (WHERE tri=4),0) t4,
                 sum(cents) total, sum(com) com, sum(n) n
            FROM t GROUP BY provider_id) t
    LEFT JOIN public.service_providers sp ON sp.id::text = t.provider_id;

  -- NIF confirmado pelo estafeta na app entra quando a ficha não o tem.
  SELECT coalesce(jsonb_agg(
           CASE WHEN l->>'tipo' = 'driver' AND coalesce(l->>'nif','') = '' AND fs.nif IS NOT NULL
                THEN l || jsonb_build_object('nif', fs.nif,
                                             'campos_em_falta', (SELECT coalesce(jsonb_agg(c), '[]'::jsonb)
                                                                   FROM jsonb_array_elements_text(l->'campos_em_falta') c
                                                                  WHERE c NOT ILIKE '%nif%'))
                ELSE l END), '[]'::jsonb)
    INTO v_linhas
    FROM jsonb_array_elements(coalesce(v_base->'linhas','[]'::jsonb) || v_prov) l
    LEFT JOIN public.driver_fiscal_status fs ON fs.user_id::text = l->>'id';

  RETURN jsonb_build_object(
    'ano', p_year, 'gerado_em', now(), 'linhas', v_linhas,
    'falta_morada', (SELECT coalesce(jsonb_agg(jsonb_build_object('tipo', l->>'tipo', 'id', l->>'id', 'nome', l->>'nome')), '[]'::jsonb)
                       FROM jsonb_array_elements(v_linhas) l WHERE coalesce(l->>'morada','') = ''),
    'falta_nif', (SELECT coalesce(jsonb_agg(jsonb_build_object('tipo', l->>'tipo', 'id', l->>'id', 'nome', l->>'nome')), '[]'::jsonb)
                    FROM jsonb_array_elements(v_linhas) l WHERE coalesce(l->>'nif','') = ''),
    'nota', 'DAC7 (DL 26/2023): reportar à AT em janeiro do ano seguinte. Só preparado — NÃO foi enviado.');
END $$;
REVOKE ALL ON FUNCTION public.admin_dac7_report(int) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.admin_dac7_report(int) TO authenticated;

-- Bloqueio fiscal do estafeta (a partir do prazo): só leitura. Ligar isto ao
-- driver_accept_offer / dispatch é zona protegida — SQL deixado em
-- platform_settings.staged_fecho_mensal_20260929, à espera do "vai" do Danilo.
create or replace function public._estafeta_fiscal_bloqueado(p_uid uuid)
returns boolean language sql stable security definer set search_path to 'public'
as $$
  select (now() at time zone 'Europe/Lisbon')::date >= coalesce((select (value #>> '{}')::date from public.platform_settings where key='estafeta_fiscal_prazo'), date '2026-10-15')
     and not exists (select 1 from public.driver_fiscal_status f
                      where f.user_id = p_uid and f.atividade_aberta and public._nif_valido(f.nif));
$$;
revoke all on function public._estafeta_fiscal_bloqueado(uuid) from public, anon, authenticated;
