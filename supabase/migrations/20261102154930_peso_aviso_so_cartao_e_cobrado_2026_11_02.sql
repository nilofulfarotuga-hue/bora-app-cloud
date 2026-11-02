-- Missão zerar-2026-11-02, B3 (autorização do Danilo 02/11/2026 14:46, item 4). Só o texto do aviso:
-- com weight_adjust_card_charge_enabled ligado, só o CARTÃO é cobrado no fecho do talão
-- (cobrar-diferenca-peso); o MB Way dizia "Diferença: X" sem nunca ser cobrado. Interruptor desligado:
-- igual a antes. Nenhum valor nem cobrança muda aqui.
-- Aplicada em produção pelo MCP a 02/11/2026 (schema_migrations 20261102154930).
do $migr$
declare v_def text; v_novo text;
  v_old text := $o$      IF v_total_delta > 0 AND NOT COALESCE((public.get_setting('weight_adjust_card_charge_enabled') #>> '{}')::boolean, false) THEN
        v_body := v_body || ' O peso real saiu mais caro; a diferença fica por conta do Bora.';
      ELSIF v_total_delta > 0 THEN
        v_body := v_body || format(' Diferença: %s.', public._euros_pt(v_total_delta));$o$;
  v_new text := $n$      -- 02/11/2026 (zerar B3): só o CARTÃO é cobrado (cobrar-diferenca-peso, no fecho do talão, com
      -- weight_adjust_card_charge_enabled ligado). MB Way e interruptor desligado: a Bora assume.
      IF v_total_delta > 0 AND lower(COALESCE(v_order.payment_method, '')) IN ('card', 'stripe')
         AND COALESCE((public.get_setting('weight_adjust_card_charge_enabled') #>> '{}')::boolean, false) THEN
        v_body := v_body || format(' A diferença de %s vai ser cobrada no cartão com que pagaste, quando o estafeta fechar a compra.', public._euros_pt(v_total_delta));
      ELSIF v_total_delta > 0 THEN
        v_body := v_body || ' O peso real saiu mais caro; a diferença fica por conta do Bora.';$n$;
begin
  v_def := pg_get_functiondef('public.estafeta_ajustar_peso(text,text,integer)'::regprocedure);
  if position(v_old in v_def) = 0 then raise exception 'estafeta_ajustar_peso: trecho antigo nao encontrado'; end if;
  v_novo := replace(v_def, v_old, v_new);
  execute v_novo;
end $migr$;
