-- Missão checkin-escada-premios-2026-11-04, bloco A (parte sem dinheiro): prémio do tipo "desconto" —
-- vale de X € numa compra de pelo menos Y € (só produtos) numa loja. Aqui fica o tipo, o vale e os 6
-- degraus. Os degraus nascem DESLIGADOS ("ativo": false): o desconto ainda não entra no orçamento nem no
-- pedido (quote_order_pricing / create_order, zona protegida de preços). Proposta do checkout em
-- docs/propostas/PROPOSTA_20261104_checkin_desconto_no_checkout.sql. Não mexe em preços, comissões nem
-- nos ganhos do estafeta.

alter table public.checkin_premios_vales add column if not exists minimo_cents integer;
comment on column public.checkin_premios_vales.minimo_cents is
  'Só no tipo desconto: compra mínima em produtos (cêntimos) para o desconto valer. valor_cents = o desconto.';

alter table public.checkin_premios_vales drop constraint if exists checkin_premios_vales_tipo_check;
alter table public.checkin_premios_vales add constraint checkin_premios_vales_tipo_check
  check (tipo = any (array['produto'::text, 'servico'::text, 'desconto'::text]));

DO $patch$
DECLARE
  v_def text;
  v_novo text;
BEGIN
  -- config: aceita o tipo desconto
  v_def := pg_get_functiondef('public._checkin_marcos_config()'::regprocedure);
  IF position('''desconto''' in v_def) = 0 THEN
    v_novo := replace(v_def, 'IN (''tokens'',''produto'',''servico'')', 'IN (''tokens'',''produto'',''servico'',''desconto'')');
    IF v_novo = v_def THEN RAISE EXCEPTION 'ancora _checkin_marcos_config'; END IF;
    EXECUTE v_novo;
  END IF;

  -- degraus da escada: o desconto também é degrau
  v_def := pg_get_functiondef('public._checkin_escada_degraus()'::regprocedure);
  IF position('''desconto''' in v_def) = 0 THEN
    v_novo := replace(v_def, 'IN (''produto'',''servico'')', 'IN (''produto'',''servico'',''desconto'')');
    IF v_novo = v_def THEN RAISE EXCEPTION 'ancora _checkin_escada_degraus'; END IF;
    EXECUTE v_novo;
  END IF;

  -- emitir: aceita desconto e grava o mínimo
  v_def := pg_get_functiondef('public._checkin_vale_emitir(uuid,jsonb,date,text,uuid,text)'::regprocedure);
  IF position('minimo_cents' in v_def) = 0 THEN
    v_novo := replace(v_def, 'IF v_tipo NOT IN (''produto'',''servico'') THEN RETURN NULL; END IF;',
                             'IF v_tipo NOT IN (''produto'',''servico'',''desconto'') THEN RETURN NULL; END IF;');
    v_novo := replace(v_novo, 'quantidade, opcoes, valor_cents, custo_cents, origem, criado_por, motivo)',
                              'quantidade, opcoes, valor_cents, custo_cents, origem, criado_por, motivo, minimo_cents)');
    v_novo := replace(v_novo, '    p_origem, p_admin, p_motivo)',
                              '    p_origem, p_admin, p_motivo,' || chr(10) ||
                              '    CASE WHEN v_tipo = ''desconto'' THEN GREATEST(COALESCE((p_marco ->> ''minimo_cents'')::int, 0), 0) END)');
    IF position('minimo_cents)' in v_novo) = 0 OR position('''desconto'') THEN RETURN NULL' in v_novo) = 0 THEN
      RAISE EXCEPTION 'ancora _checkin_vale_emitir';
    END IF;
    EXECUTE v_novo;
  END IF;

  -- json do vale: o mínimo
  v_def := pg_get_functiondef('public._checkin_vale_json(checkin_premios_vales)'::regprocedure);
  IF position('minimo_cents' in v_def) = 0 THEN
    v_novo := replace(v_def, '''valor_cents'', v.valor_cents,', '''valor_cents'', v.valor_cents, ''minimo_cents'', v.minimo_cents,');
    IF v_novo = v_def THEN RAISE EXCEPTION 'ancora _checkin_vale_json'; END IF;
    EXECUTE v_novo;
  END IF;
END
$patch$;

-- Os 6 degraus de desconto (DESLIGADOS até o desconto entrar no pagamento).
insert into public.platform_settings (key, value, category) values
 ('checkin_marco_desconto_mercadona_3', jsonb_build_object('dia', 9, 'tipo', 'desconto', 'ativo', false, 'chave', 'desconto_mercadona_3',
   'titulo', '3 € de desconto na Mercadona Beleza', 'loja_id', 'mercadona-guarda', 'valor_cents', 300, 'custo_cents', 300, 'minimo_cents', 1500,
   'descricao', 'Na Mercadona · Beleza e Higiene: 3 € de desconto numa compra de pelo menos 15 € em produtos. Entrega e taxas pagas à parte.'), 'marketing'),
 ('checkin_marco_desconto_continente_3', jsonb_build_object('dia', 10, 'tipo', 'desconto', 'ativo', false, 'chave', 'desconto_continente_3',
   'titulo', '3 € de desconto no Continente', 'loja_id', 'continente-guarda', 'valor_cents', 300, 'custo_cents', 300, 'minimo_cents', 2500,
   'descricao', 'No Continente: 3 € de desconto numa compra de pelo menos 25 € em produtos. Entrega e taxas pagas à parte.'), 'marketing'),
 ('checkin_marco_desconto_mercadona_5', jsonb_build_object('dia', 15, 'tipo', 'desconto', 'ativo', false, 'chave', 'desconto_mercadona_5',
   'titulo', '5 € de desconto na Mercadona Beleza', 'loja_id', 'mercadona-guarda', 'valor_cents', 500, 'custo_cents', 500, 'minimo_cents', 3000,
   'descricao', 'Na Mercadona · Beleza e Higiene: 5 € de desconto numa compra de pelo menos 30 € em produtos. Entrega e taxas pagas à parte.'), 'marketing'),
 ('checkin_marco_desconto_continente_5', jsonb_build_object('dia', 16, 'tipo', 'desconto', 'ativo', false, 'chave', 'desconto_continente_5',
   'titulo', '5 € de desconto no Continente', 'loja_id', 'continente-guarda', 'valor_cents', 500, 'custo_cents', 500, 'minimo_cents', 4000,
   'descricao', 'No Continente: 5 € de desconto numa compra de pelo menos 40 € em produtos. Entrega e taxas pagas à parte.'), 'marketing'),
 ('checkin_marco_desconto_continente_7', jsonb_build_object('dia', 22, 'tipo', 'desconto', 'ativo', false, 'chave', 'desconto_continente_7',
   'titulo', '7 € de desconto no Continente', 'loja_id', 'continente-guarda', 'valor_cents', 700, 'custo_cents', 700, 'minimo_cents', 5500,
   'descricao', 'No Continente: 7 € de desconto numa compra de pelo menos 55 € em produtos. Entrega e taxas pagas à parte.'), 'marketing'),
 ('checkin_marco_desconto_continente_10', jsonb_build_object('dia', 25, 'tipo', 'desconto', 'ativo', false, 'chave', 'desconto_continente_10',
   'titulo', '10 € de desconto no Continente', 'loja_id', 'continente-guarda', 'valor_cents', 1000, 'custo_cents', 1000, 'minimo_cents', 7000,
   'descricao', 'No Continente: 10 € de desconto numa compra de pelo menos 70 € em produtos. Entrega e taxas pagas à parte.'), 'marketing')
on conflict (key) do nothing;
