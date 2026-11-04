-- Missão checkin-escada-premios-2026-11-04, bloco A (autorização do Danilo 04/11/2026 12:42, "eu autorizo."):
-- o vale de desconto do check-in entra no ORÇAMENTO. Só atua quando o pedido traz checkin_vale_id.
-- Valida no servidor: dono, tipo desconto, por usar e válido, loja do pedido, produtos >= mínimo.
-- O desconto sai do total do cliente e da comissão da Bora; o ganho do estafeta NÃO muda.
DO $patch$
DECLARE
  v_def  text := pg_get_functiondef('public.quote_order_pricing(jsonb)'::regprocedure);
  v_novo text := v_def;
BEGIN
  IF position('checkin_desconto' in v_def) > 0 THEN RETURN; END IF;

  v_novo := regexp_replace(v_novo, 'DECLARE\s*\n', E'DECLARE\n  v_ck_id uuid := NULL;\n  v_ck record;\n  v_ck_desc numeric := 0;\n  v_ck_falta integer := 0;\n');

  v_novo := replace(v_novo,
    E'    v_customer_total := ROUND((v_pricing.customer_total + v_small_order_fee)::numeric, 2);\n  END IF;\n',
    E'    v_customer_total := ROUND((v_pricing.customer_total + v_small_order_fee)::numeric, 2);\n  END IF;\n\n'
 || E'  -- 04/11/2026: premio do check-in tipo desconto (um vale por pedido)\n'
 || E'  BEGIN v_ck_id := NULLIF(p_input->>''checkin_vale_id'', '''')::uuid; EXCEPTION WHEN OTHERS THEN v_ck_id := NULL; END;\n'
 || E'  IF v_ck_id IS NOT NULL AND NOT v_is_takeaway THEN\n'
 || E'    SELECT c.* INTO v_ck FROM public.checkin_premios_vales c\n'
 || E'     WHERE c.id = v_ck_id AND c.user_id = v_user_id AND c.tipo = ''desconto''\n'
 || E'       AND c.estado IN (''por_usar'',''reservado'') AND c.valido_ate > now()\n'
 || E'       AND c.loja_id = v_restaurant_id;\n'
 || E'    IF FOUND THEN\n'
 || E'      IF ROUND(v_subtotal_server * 100) >= COALESCE(v_ck.minimo_cents, 0) THEN\n'
 || E'        v_ck_desc := LEAST(v_ck.valor_cents / 100.0, v_customer_total);\n'
 || E'        v_customer_total := ROUND((v_customer_total - v_ck_desc)::numeric, 2);\n'
 || E'        v_platform_commission := ROUND((v_platform_commission - v_ck_desc)::numeric, 2);\n'
 || E'      ELSE\n'
 || E'        v_ck_falta := COALESCE(v_ck.minimo_cents, 0) - ROUND(v_subtotal_server * 100)::int;\n'
 || E'      END IF;\n'
 || E'    ELSE\n'
 || E'      v_ck_id := NULL;\n'
 || E'    END IF;\n'
 || E'  END IF;\n');

  v_novo := replace(v_novo,
    E'''tokens_applied_value_cents'', v_token_cents,',
    E'''tokens_applied_value_cents'', v_token_cents,\n    ''checkin_desconto'', v_ck_desc, ''checkin_desconto_falta_cents'', v_ck_falta, ''checkin_vale_id'', v_ck_id,');

  IF position('v_ck_desc numeric' in v_novo) = 0 OR position('premio do check-in tipo desconto' in v_novo) = 0
     OR position('''checkin_desconto'', v_ck_desc' in v_novo) = 0 THEN
    RAISE EXCEPTION 'ancora_nao_encontrada em quote_order_pricing';
  END IF;
  EXECUTE v_novo;
END
$patch$;
