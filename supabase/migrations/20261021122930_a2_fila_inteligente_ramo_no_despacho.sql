-- A2 · FILA INTELIGENTE — o ramo na tvde_offer_to_next (ZONA PROTEGIDA DE DESPACHO).
-- Missão fechar-pendencias-2026-10-20. Corre DEPOIS de A2_01 (fila_inteligente_base).
--
-- Mudança mínima, por âncora (memória patch-de-funcao-protegida-por-ancora):
--   * 1 linha no DECLARE  (v_fila_ia BOOLEAN)
--   * 1 bloco logo a seguir à guarda dispatch_hold_reason:
--       IF interruptor ligado THEN v_fila_ia := _tvde_fila_oferecer(...);
--                                 IF v_fila_ia IS NOT NULL THEN RETURN v_fila_ia; END IF;
--       END IF;
-- Com o interruptor DESLIGADO o bloco não faz nada e a função corre o caminho de sempre: o resto
-- do corpo fica BYTE A BYTE igual ao que estava no ar (provado aqui dentro: o corpo novo sem as
-- duas inserções tem o md5 de antes; se não tiver, a migração inteira volta atrás).
-- A tvde_dispatch_sweep NÃO muda (o varrimento já chama a tvde_offer_to_next quando a oferta
-- expira ou não há candidato — é aí que a fila passa ao seguinte). Também se prova o md5 dela.

DO $patch$
DECLARE
  c_md5_src_offer constant text := '40dd523a5b9c6dc9dbbbb5848abfef4f';  -- prosrc no ar a 20-21/10
  c_md5_src_sweep constant text := '6218c0a368cb0d3601e165fa2cfb4d8d';
  c_ancora_decl   constant text := E'  v_fila   BOOLEAN := false;\n';
  c_ancora_corpo  constant text := E'  IF v_ride.dispatch_hold_reason IS NOT NULL THEN RETURN false; END IF;\n';
  c_novo_decl     constant text := E'  v_fila_ia BOOLEAN;  -- 2026-10-21 (A2) fila inteligente\n';
  c_novo_corpo    constant text := $blk$
  -- 2026-10-21 (A2) FILA INTELIGENTE, atrás do interruptor tvde_fila_inteligente_enabled.
  -- Desligado: nada disto corre e segue o caminho de sempre, linha a linha. Ligado: a lista
  -- calculada uma vez manda; NULL = não se aplica (balcão) ou lista esgotada -> caminho de sempre.
  IF COALESCE((public.get_setting('tvde_fila_inteligente_enabled') #>> '{}')::boolean, false) THEN
    v_fila_ia := public._tvde_fila_oferecer(p_ride_id);
    IF v_fila_ia IS NOT NULL THEN RETURN v_fila_ia; END IF;
  END IF;
$blk$;
  v_oid      oid := 'public.tvde_offer_to_next(uuid)'::regprocedure;
  v_src      text;
  v_def      text;
  v_acl      text;
  v_novo     text;
  v_src_novo text;
  v_n        int;
BEGIN
  SELECT p.prosrc, pg_get_functiondef(p.oid), p.proacl::text INTO v_src, v_def, v_acl
    FROM pg_proc p WHERE p.oid = v_oid;
  IF md5(v_src) <> c_md5_src_offer THEN
    RAISE EXCEPTION 'A2: tvde_offer_to_next mudou no ar (md5 % <> %) — parar e reler', md5(v_src), c_md5_src_offer;
  END IF;
  IF (SELECT md5(p.prosrc) FROM pg_proc p WHERE p.oid = 'public.tvde_dispatch_sweep()'::regprocedure)
     <> c_md5_src_sweep THEN
    RAISE EXCEPTION 'A2: tvde_dispatch_sweep mudou no ar — parar e reler';
  END IF;

  v_n := (length(v_def) - length(replace(v_def, c_ancora_decl, ''))) / length(c_ancora_decl);
  IF v_n <> 1 THEN RAISE EXCEPTION 'A2: âncora do DECLARE aparece % vezes (esperado 1)', v_n; END IF;
  v_n := (length(v_def) - length(replace(v_def, c_ancora_corpo, ''))) / length(c_ancora_corpo);
  IF v_n <> 1 THEN RAISE EXCEPTION 'A2: âncora do corpo aparece % vezes (esperado 1)', v_n; END IF;
  IF position('v_fila_ia' in v_def) > 0 THEN RAISE EXCEPTION 'A2: ramo já lá está'; END IF;

  v_novo := replace(v_def, c_ancora_decl, c_ancora_decl || c_novo_decl);
  v_novo := replace(v_novo, c_ancora_corpo, c_ancora_corpo || c_novo_corpo);
  EXECUTE v_novo;

  -- Prova byte a byte: o corpo novo, sem as duas inserções, é o de antes.
  SELECT p.prosrc INTO v_src_novo FROM pg_proc p WHERE p.oid = v_oid;
  IF md5(replace(replace(v_src_novo, c_novo_decl, ''), c_novo_corpo, '')) <> c_md5_src_offer THEN
    RAISE EXCEPTION 'A2: corpo sem o ramo NÃO é igual ao de antes — nada aplicado';
  END IF;
  IF length(v_src_novo) <> length(v_src) + length(c_novo_decl) + length(c_novo_corpo) THEN
    RAISE EXCEPTION 'A2: tamanho inesperado (% vs %)', length(v_src_novo),
      length(v_src) + length(c_novo_decl) + length(c_novo_corpo);
  END IF;
  -- Cabeçalho (SECURITY DEFINER, search_path, tipo de retorno) e permissões iguais.
  IF (SELECT p.proacl::text FROM pg_proc p WHERE p.oid = v_oid) IS DISTINCT FROM v_acl
     OR NOT (SELECT p.prosecdef FROM pg_proc p WHERE p.oid = v_oid)
     OR (SELECT p.proconfig::text FROM pg_proc p WHERE p.oid = v_oid) IS DISTINCT FROM '{search_path=public}' THEN
    RAISE EXCEPTION 'A2: cabeçalho ou permissões mudaram';
  END IF;
  IF (SELECT md5(p.prosrc) FROM pg_proc p WHERE p.oid = 'public.tvde_dispatch_sweep()'::regprocedure)
     <> c_md5_src_sweep THEN
    RAISE EXCEPTION 'A2: tvde_dispatch_sweep mexida — não devia';
  END IF;
  RAISE NOTICE 'A2 ramo aplicado: offer md5_src % -> %, sweep % (igual)', md5(v_src), md5(v_src_novo), c_md5_src_sweep;
END
$patch$;
