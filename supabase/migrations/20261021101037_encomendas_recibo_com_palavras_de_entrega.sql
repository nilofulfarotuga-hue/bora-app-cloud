-- 2026-10-21 · fechar-pendencias-2026-10-20 · BLOCO A1 · RONDA 1 do revisor (ponto 2)
-- Recibo/resumo do servidor (_tvde_recibo, usado pela app e pela Edge do e-mail):
-- numa ENCOMENDA o título, a razão e o aviso legal dizem "entrega" em vez de
-- "viagem". Só texto: os números (total, transporte, taxa, IVA, cálculo) saem
-- da MESMA expressão de sempre. Troca por âncora sobre a definição no ar (md5
-- conferido); passageiros recebem exactamente o mesmo objecto de antes.

create or replace function pg_temp._a1_troca(p_txt text, p_de text, p_para text, p_vezes int, p_onde text)
returns text language plpgsql as $f$
declare v_n int;
begin
  v_n := (length(p_txt) - length(replace(p_txt, p_de, ''))) / greatest(length(p_de), 1);
  if v_n <> p_vezes then
    raise exception 'A1 âncora % apareceu % vez(es), esperava % — nada foi mudado', p_onde, v_n, p_vezes;
  end if;
  return replace(p_txt, p_de, p_para);
end $f$;

do $m7$
declare v_def text; v_src text; v_back text;
  c_ini_old constant text := E'  return jsonb_build_object(\n    ''ride_id'', r.id,';
  c_ini_new constant text := E'  return (jsonb_build_object(\n    ''ride_id'', r.id,';
  c_fim_old constant text := E'pela Autoridade Tributária.'');\nend';
  c_fim_new constant text := E'pela Autoridade Tributária.''))\n'
    || E'    -- 21/10/2026 (A1 r1): numa encomenda as palavras são de entrega (os números não mudam).\n'
    || E'    || case when r.ride_kind = ''encomendas'' then jsonb_strip_nulls(jsonb_build_object(\n'
    || E'         ''titulo'', ''Resumo da entrega'',\n'
    || E'         ''razao'', case\n'
    || E'           when v_total = 0 then ''Entrega incluída num pacote ou assinatura já pago.''\n'
    || E'           when not v_bate then ''Entrega com ajuste de pacote ida-e-volta: a divisão entre estafeta e Bora está no teu extrato de pacote.''\n'
    || E'           end,\n'
    || E'         ''aviso_legal'', ''Resumo da entrega. Não é uma fatura: a fatura é emitida por software certificado pela Autoridade Tributária.''))\n'
    || E'       else ''{}''::jsonb end;\nend';
begin
  if (select md5(prosrc) from pg_proc where oid = 'public._tvde_recibo(uuid)'::regprocedure)
     <> 'a75fdb28685713f3a3ba70e8e9af2c68' then
    raise exception 'A1-r1 _tvde_recibo mudou no ar — nada foi mudado';
  end if;
  insert into public.bkp_fn_encomendas_20261021 (nome, assinatura, definicao, prosrc_md5, acl, copiado_em)
  select p.proname::text, pg_get_function_identity_arguments(p.oid), pg_get_functiondef(p.oid), md5(p.prosrc),
         p.proacl::text, now()
    from pg_proc p where p.oid = 'public._tvde_recibo(uuid)'::regprocedure
     and not exists (select 1 from public.bkp_fn_encomendas_20261021 b where b.nome = '_tvde_recibo');
  v_def := pg_get_functiondef('public._tvde_recibo(uuid)'::regprocedure);
  v_def := pg_temp._a1_troca(v_def, c_ini_old, c_ini_new, 1, 'recibo:inicio');
  v_def := pg_temp._a1_troca(v_def, c_fim_old, c_fim_new, 1, 'recibo:fim');
  execute v_def;
  select prosrc into v_src from pg_proc where oid = 'public._tvde_recibo(uuid)'::regprocedure;
  v_back := pg_temp._a1_troca(pg_temp._a1_troca(v_src, c_fim_new, c_fim_old, 1, 'desfaz:fim'), c_ini_new, c_ini_old, 1, 'desfaz:inicio');
  if md5(v_back) <> 'a75fdb28685713f3a3ba70e8e9af2c68' then
    raise exception 'A1-r1 _tvde_recibo sem a parte nova NÃO é o de antes (%)', md5(v_back);
  end if;
end $m7$;
