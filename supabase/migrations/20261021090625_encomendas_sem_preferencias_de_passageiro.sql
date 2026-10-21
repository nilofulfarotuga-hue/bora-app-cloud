-- 2026-10-21 · super-missão fechar-pendencias-2026-10-20 · BLOCO A1 (4/4)
-- Uma ENCOMENDA não herda as preferências de PASSAGEIRO do cliente
-- (tvde_client_prefs: fala português, mobilidade reduzida, cão-guia, cadeira de
-- rodas, carrinho de bebé). Sem isto o estafeta via "cliente em cadeira de
-- rodas" numa caixa. Só PALAVRAS/INFORMAÇÃO: nenhum preço, nenhum despacho
-- (tvde_offer_to_next não lê estas colunas para escolher). Passageiros: igual.
-- Troca por âncora sobre a definição no ar (md5 conferido), aditiva.

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

do $m4$
declare v_def text;
begin
  if (select md5(prosrc) from pg_proc where oid = 'public.fn_tvde_rides_prefs()'::regprocedure)
     <> 'e0a687d63ff66a9cdae823659726c112' then
    raise exception 'A1 fn_tvde_rides_prefs mudou no ar — nada foi mudado';
  end if;
  insert into public.bkp_fn_encomendas_20261021 (nome, assinatura, definicao, prosrc_md5, acl, copiado_em)
  select p.proname::text, pg_get_function_identity_arguments(p.oid), pg_get_functiondef(p.oid), md5(p.prosrc),
         p.proacl::text, now()
    from pg_proc p where p.oid = 'public.fn_tvde_rides_prefs()'::regprocedure
     and not exists (select 1 from public.bkp_fn_encomendas_20261021 b where b.nome = 'fn_tvde_rides_prefs');
  v_def := pg_get_functiondef('public.fn_tvde_rides_prefs()'::regprocedure);
  v_def := pg_temp._a1_troca(v_def,
    E'begin\n  select * into p from public.tvde_client_prefs where client_id = new.client_id;',
    E'begin\n  -- 21/10/2026 (A1): uma encomenda não leva as preferências de passageiro.\n'
    || E'  if new.ride_kind = ''encomendas'' then return new; end if;\n'
    || E'  select * into p from public.tvde_client_prefs where client_id = new.client_id;', 1, 'prefs');
  execute v_def;
end $m4$;
