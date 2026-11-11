-- R7 (11/11/2026, missão fechar-tudo-2026-11-11, Bloco 9, ordem do Danilo de 11/11 07:54):
-- os 6 degraus de DESCONTO do check-in (Continente 3/5/7/10 €, Mercadona Beleza 3/5 €; dias 9, 10, 15,
-- 16, 22 e 25) passam a poder ser ligados. Esta migração prepara tudo; os degraus continuam DESLIGADOS
-- (ligam-se na 20261111100100, só depois das provas em dinheiro).
--
-- Regras: o desconto vale só sobre os PRODUTOS (nunca entrega, taxa de serviço, sacos, pedido pequeno
-- ou depósito Volta), numa compra nessa loja nos 30 dias seguintes (checkin_marco_validade_dias), uma
-- vez; conta no teto do mês (R6, _checkin_custo_mes_cents já soma custo_cents de todos os tipos); segue
-- o "Quero este / Continuar"; é pago pela Bora (sai da platform_commission, o estafeta ganha igual) e
-- aparece em linha própria no recibo, no extrato do dono e no fecho do contabilista. O vale só fica
-- gasto com o pedido pago: cancelado/recusado, volta a "por usar".
--
-- Funções grandes de dinheiro (_create_order_core, quote_order_pricing, admin_monthly_closeout,
-- admin_fecho_contabilista, admin_extrato_dono, _recibo_pedido, checkin_lembretes_processar,
-- _checkin_marcos_apos_checkin) são remendadas por âncora: cada âncora tem de existir o número exato
-- de vezes, senão a migração inteira falha e nada muda.

CREATE OR REPLACE FUNCTION pg_temp._r7_patch(p_fn regprocedure, p_old text, p_new text, p_n int DEFAULT 1)
RETURNS void LANGUAGE plpgsql AS $p$
DECLARE d text; n int;
BEGIN
  d := pg_get_functiondef(p_fn);
  n := (length(d) - length(replace(d, p_old, ''))) / length(p_old);
  IF n <> p_n THEN
    RAISE EXCEPTION 'R7: âncora encontrada % vez(es), esperava %, em %: %', n, p_n, p_fn, left(p_old, 90);
  END IF;
  EXECUTE replace(d, p_old, p_new);
END $p$;

-- 1. Desconto só sobre os produtos (o pedido pequeno já está no customer_total neste ponto; o depósito
--    Volta entra depois). Igual no orçamento e na criação do pedido.
SELECT pg_temp._r7_patch('public._create_order_core(jsonb)',
  'v_ck_desc := LEAST(v_ck.valor_cents / 100.0, v_customer_total);',
  'v_ck_desc := LEAST(v_ck.valor_cents / 100.0, v_subtotal_server, v_customer_total);  -- 11/11/2026 R7: só sobre os produtos');
SELECT pg_temp._r7_patch('public.quote_order_pricing(jsonb)',
  'v_ck_desc := LEAST(v_ck.valor_cents / 100.0, v_customer_total);',
  'v_ck_desc := LEAST(v_ck.valor_cents / 100.0, v_subtotal_server, v_customer_total);  -- 11/11/2026 R7: só sobre os produtos');

-- 2. A escada (R4) e a emissão passam a incluir os degraus de desconto (ligados ou não decide o "ativo").
SELECT pg_temp._r7_patch('public._checkin_marcos_apos_checkin()',
  'IF (m ->> ''tipo'') IN (''produto'',''servico'')',
  'IF (m ->> ''tipo'') IN (''produto'',''servico'',''desconto'')  -- 11/11/2026 R7');

-- 3. O lembrete diário também anuncia o próximo desconto ("Faltam 2 dias para 3 € de desconto…").
SELECT pg_temp._r7_patch('public.checkin_lembretes_processar()',
  'LIMIT 1) NOT IN (''produto'',''servico'') THEN ''''',
  'LIMIT 1) NOT IN (''produto'',''servico'',''desconto'') THEN ''''', 2);

-- 4. Cancelar/recusar um pedido devolve o vale de DESCONTO sempre (só fica gasto com o pedido pago);
--    os vales de produto/serviço seguem a regra de antes (_checkin_premio_pode_voltar).
CREATE OR REPLACE FUNCTION public._checkin_premio_pedido_cancelado()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
BEGIN
  -- 11/11/2026 R7: o desconto do check-in só se gasta com o pedido pago.
  UPDATE public.checkin_premios_vales
     SET estado = CASE WHEN valido_ate IS NOT NULL AND valido_ate > now() THEN 'por_usar' ELSE 'expirado' END,
         usado_em = NULL, pedido_id = NULL, reservado_ate = NULL,
         motivo = COALESCE(motivo || ' | ', '') || 'pedido ' || NEW.id || ' ' || NEW.status || ': o desconto volta',
         atualizado_em = now()
   WHERE pedido_id = NEW.id AND estado = 'usado' AND tipo = 'desconto';

  IF NOT (NEW.items::text LIKE '%premio-checkin-%') THEN
    RETURN NULL;
  END IF;
  IF NOT public._checkin_premio_pode_voltar(NEW.id, OLD.status) THEN
    UPDATE public.checkin_premios_vales
       SET motivo = COALESCE(motivo || ' | ', '') || 'pedido ' || NEW.id || ' passou a ' || NEW.status
                    || ' depois de ' || OLD.status || ': o vale não volta',
           atualizado_em = now()
     WHERE pedido_id = NEW.id AND estado = 'usado';
    RETURN NULL;
  END IF;
  UPDATE public.checkin_premios_vales
     SET estado = CASE WHEN valido_ate IS NOT NULL AND valido_ate > now() THEN 'por_usar' ELSE 'expirado' END,
         usado_em = NULL, pedido_id = NULL, reservado_ate = NULL,
         motivo = COALESCE(motivo || ' | ', '') || 'pedido ' || NEW.id || ' ' || NEW.status,
         atualizado_em = now()
   WHERE pedido_id = NEW.id AND estado = 'usado' AND pago_loja_em IS NULL;
  RETURN NULL;
END;
$function$;

-- O gatilho deixa de exigir um artigo 'premio-checkin-' (um pedido com vale de desconto não o tem).
CREATE OR REPLACE TRIGGER trg_checkin_premio_pedido_cancelado
  AFTER UPDATE OF status ON public.orders FOR EACH ROW
  WHEN ((new.status = ANY (ARRAY['cancelled'::text, 'rejected'::text]))
        AND (old.status IS DISTINCT FROM new.status))
  EXECUTE FUNCTION public._checkin_premio_pedido_cancelado();

-- 5. Quanto a Bora pagou em descontos do check-in nos pedidos entregues de um período (os mesmos
--    pedidos que o fecho conta). O desconto aplicado é o valor do vale: o mínimo de produtos de cada
--    degrau é sempre maior do que o valor.
CREATE OR REPLACE FUNCTION public._fecho_descontos_checkin(p_ini timestamptz, p_fim timestamptz)
 RETURNS numeric
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  SELECT COALESCE(round(sum(v.valor_cents) / 100.0, 2), 0)
    FROM public.checkin_premios_vales v
   WHERE v.tipo = 'desconto' AND v.estado = 'usado'
     AND v.pedido_id IN (SELECT f.order_id FROM public._fecho_pedidos(p_ini, p_fim) f)
$function$;

-- Resumo dos vales de desconto (painel e extrato do dono).
CREATE OR REPLACE FUNCTION public._checkin_descontos_resumo(p_de timestamptz, p_ate timestamptz)
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  SELECT jsonb_build_object(
    'emitidos_n',     count(*) FILTER (WHERE v.emitido_em >= p_de AND v.emitido_em < p_ate),
    'emitidos_cents', COALESCE(sum(v.valor_cents) FILTER (WHERE v.emitido_em >= p_de AND v.emitido_em < p_ate), 0),
    'usados_n',       count(*) FILTER (WHERE v.estado = 'usado' AND v.usado_em >= p_de AND v.usado_em < p_ate),
    'usados_cents',   COALESCE(sum(v.valor_cents) FILTER (WHERE v.estado = 'usado' AND v.usado_em >= p_de AND v.usado_em < p_ate), 0),
    'por_usar_n',     count(*) FILTER (WHERE v.estado IN ('por_usar','reservado')),
    'por_usar_cents', COALESCE(sum(v.valor_cents) FILTER (WHERE v.estado IN ('por_usar','reservado')), 0))
    FROM public.checkin_premios_vales v
   WHERE v.tipo = 'desconto'
$function$;

CREATE OR REPLACE FUNCTION public.admin_checkin_descontos_resumo()
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
BEGIN
  IF NOT public.is_admin() THEN
    RAISE EXCEPTION 'forbidden_admin_only' USING ERRCODE = '42501';
  END IF;
  RETURN public._checkin_descontos_resumo(
           (date_trunc('month', now() AT TIME ZONE 'Europe/Lisbon')) AT TIME ZONE 'Europe/Lisbon',
           now() + interval '1 second')
         || jsonb_build_object(
              'degraus_total', (SELECT count(*) FROM jsonb_array_elements(public._checkin_marcos_config()) x
                                 WHERE x ->> 'tipo' = 'desconto'),
              'degraus_ligados', (SELECT count(*) FROM jsonb_array_elements(public._checkin_marcos_config()) x
                                   WHERE x ->> 'tipo' = 'desconto' AND COALESCE((x ->> 'ativo')::boolean, true)));
END;
$function$;

REVOKE ALL ON FUNCTION public._fecho_descontos_checkin(timestamptz, timestamptz) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public._checkin_descontos_resumo(timestamptz, timestamptz) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.admin_checkin_descontos_resumo() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.admin_checkin_descontos_resumo() TO authenticated;

-- 6. Fecho do contabilista: linha própria "Descontos do check-in (pagos pela Bora)", tirada dos Ajustes.
SELECT pg_temp._r7_patch('public.admin_monthly_closeout(integer, integer)',
  'v_r_ajustes := round(v_r_rec - (v_r_ent + v_r_serv + v_r_sacos + v_r_peq + v_r_parc + v_r_np - v_r_tok), 2);',
  'v_r_ajustes := round(v_r_rec - (v_r_ent + v_r_serv + v_r_sacos + v_r_peq + v_r_parc + v_r_np - v_r_tok'
  || ' - public._fecho_descontos_checkin(v_ini, v_fim)), 2);  -- 11/11/2026 R7');
SELECT pg_temp._r7_patch('public.admin_monthly_closeout(integer, integer)',
  '''ajustes_descontos'', v_r_ajustes);',
  '''descontos_checkin'', -public._fecho_descontos_checkin(v_ini, v_fim),  -- 11/11/2026 R7: pagos pela Bora'
  || chr(10) || '    ''ajustes_descontos'', v_r_ajustes);');
SELECT pg_temp._r7_patch('public.admin_fecho_contabilista(integer, integer)',
  '  v_l := v_l || (''- Ajustes: '' ||',
  '  if coalesce((v_rub->>''descontos_checkin'')::numeric, 0) <> 0 then  -- 11/11/2026 R7'
  || chr(10) || '    v_l := v_l || (''- Descontos do check-in (pagos pela Bora): '' || public._fecho_eur((v_rub->>''descontos_checkin'')::numeric));'
  || chr(10) || '  end if;'
  || chr(10) || '  v_l := v_l || (''- Ajustes: '' ||');

-- 7. Extrato do dono: bloco "descontos_checkin" (emitidos, usados e por usar no período).
SELECT pg_temp._r7_patch('public.admin_extrato_dono(date, date)',
  '    ''arcas'', v_arcas' || chr(10) || '  );',
  '    ''arcas'', v_arcas,' || chr(10)
  || '    ''descontos_checkin'', public._checkin_descontos_resumo(v_de, v_ate)  -- 11/11/2026 R7' || chr(10) || '  );');

-- 8. Recibo do cliente: linha própria, negativa, para as linhas somarem ao total pago.
SELECT pg_temp._r7_patch('public._recibo_pedido(text)',
  'v_desc   jsonb := ''[]''::jsonb;',
  'v_desc   jsonb := ''[]''::jsonb;' || chr(10) || '  v_ck_cents integer := 0;  -- 11/11/2026 R7');
SELECT pg_temp._r7_patch('public._recibo_pedido(text)',
  '  v_total := ROUND(COALESCE(CASE WHEN COALESCE(o.is_purchase_finalized, false) THEN o.final_total END,',
  '  -- 11/11/2026 R7: desconto do check-in, pago pela Bora, em linha própria.' || chr(10)
  || '  SELECT COALESCE(sum(c.valor_cents), 0)::int INTO v_ck_cents FROM public.checkin_premios_vales c' || chr(10)
  || '   WHERE c.pedido_id = o.id AND c.tipo = ''desconto'' AND c.estado = ''usado'';' || chr(10)
  || '  IF v_ck_cents > 0 THEN' || chr(10)
  || '    v_linhas := v_linhas || jsonb_build_object(''nome'', ''Desconto do check-in (pago pela Bora)'', ''valor_cents'', -v_ck_cents);' || chr(10)
  || '  END IF;' || chr(10)
  || '  v_total := ROUND(COALESCE(CASE WHEN COALESCE(o.is_purchase_finalized, false) THEN o.final_total END,');
