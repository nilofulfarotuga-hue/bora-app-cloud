-- 2026-10-21 · super-missão fechar-pendencias-2026-10-20 · BLOCO A1 (2/3)
-- As 3 RPCs que criam corridas do cliente ganham o parâmetro opcional
-- p_ride_kind (por omissão NULL = "não disse" -> declarado pela app no caminho
-- da Edge tvde-payment, senão 'passageiros'). NADA mais muda nelas.
--
-- Como: o texto novo NÃO é escrito à mão. Este bloco lê a definição que está
-- NO AR, confirma o md5 de 20/10 (ESTADO-0), faz 4-5 trocas por âncora (cada
-- âncora tem de aparecer exactamente o nº de vezes esperado, senão aborta e
-- nada muda), apaga a assinatura antiga e cria a nova (assim não nasce uma
-- sobrecarga: a chamada antiga, sem p_ride_kind, cai na MESMA função pelo
-- valor por omissão), repõe as permissões e no fim prova que o corpo novo,
-- com as trocas desfeitas, tem o md5 de antes — byte a byte.
--
-- As trocas, em cada uma das 3 funções:
--   a) assinatura: + p_ride_kind text DEFAULT NULL::text (último parâmetro);
--   b) DECLARE: + v_ride_kind;
--   c) o portão: "PERFORM public._tvde_exige_acesso(v_uid);" passa a
--      "v_ride_kind := public._tvde_ride_kind_resolver(v_uid, p_ride_kind);
--       IF v_ride_kind = 'passageiros' THEN PERFORM public._tvde_exige_acesso(v_uid); END IF;"
--      (passageiros: o mesmo portão de sempre; encomendas: o interruptor
--      tvde_encomendas_enabled, decisão do Danilo de 19/10 — as encomendas não
--      pedem o acesso do Bora Motorista);
--   d) INSERT: + coluna ride_kind = v_ride_kind (só nas que inserem).
--      tvde_schedule_roundtrip não insere a ida: passa v_ride_kind à
--      tvde_schedule_ride; a volta herda pelo gatilho trg_tvde_ride_kind_da_volta.

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

do $mig$
declare
  c_gate_old constant text := E'  PERFORM public._tvde_exige_acesso(v_uid);\n';
  c_gate_new constant text := E'  v_ride_kind := public._tvde_ride_kind_resolver(v_uid, p_ride_kind);\n'
                           || E'  IF v_ride_kind = ''passageiros'' THEN PERFORM public._tvde_exige_acesso(v_uid); END IF;\n';
  r record;
  v_oid oid; v_def text; v_new text; v_src text; v_back text; v_acl_old text[]; v_acl_new text[];
  v_md5_old text; v_sig_new text;
  v_body_pairs text[][];
  i int;
begin
  for r in
    select * from (values
      ('tvde_request_ride',
       'double precision, double precision, text, double precision, double precision, text, numeric, text, integer',
       '2a60a458a08fdca190c1c6875a7cc45d',
       E'p_tokens_to_apply integer DEFAULT 0)\n RETURNS ',
       E'p_tokens_to_apply integer DEFAULT 0, p_ride_kind text DEFAULT NULL::text)\n RETURNS ',
       'double precision, double precision, text, double precision, double precision, text, numeric, text, integer, text'),
      ('tvde_schedule_ride',
       'double precision, double precision, text, double precision, double precision, text, numeric, timestamp with time zone, text, text',
       '9ab25a911968650cf1f83fda6207c3b9',
       E'p_note text DEFAULT NULL::text)\n RETURNS ',
       E'p_note text DEFAULT NULL::text, p_ride_kind text DEFAULT NULL::text)\n RETURNS ',
       'double precision, double precision, text, double precision, double precision, text, numeric, timestamp with time zone, text, text, text'),
      ('tvde_schedule_roundtrip',
       'double precision, double precision, text, double precision, double precision, text, numeric, timestamp with time zone, timestamp with time zone, text, text',
       '15c6d850789b1272ad78702c1d80fe40',
       E'p_note text DEFAULT NULL::text)\n RETURNS ',
       E'p_note text DEFAULT NULL::text, p_ride_kind text DEFAULT NULL::text)\n RETURNS ',
       'double precision, double precision, text, double precision, double precision, text, numeric, timestamp with time zone, timestamp with time zone, text, text, text')
    ) as t(nome, sig_old, md5_old, hdr_old, hdr_new, sig_new)
  loop
    v_oid := to_regprocedure(format('public.%s(%s)', r.nome, r.sig_old));
    if v_oid is null then raise exception 'A1 % (%) não existe — nada foi mudado', r.nome, r.sig_old; end if;
    select md5(prosrc), proacl::text[] into v_md5_old, v_acl_old from pg_proc where oid = v_oid;
    if v_md5_old <> r.md5_old then
      raise exception 'A1 % mudou no ar desde 20/10 (md5 % <> %) — nada foi mudado', r.nome, v_md5_old, r.md5_old;
    end if;
    v_def := pg_get_functiondef(v_oid);

    -- trocas do corpo (de, para, vezes)
    if r.nome = 'tvde_request_ride' then
      v_body_pairs := array[
        array[E'  v_km_declarado NUMERIC;\nBEGIN', E'  v_km_declarado NUMERIC;\n  v_ride_kind TEXT;\nBEGIN', '1'],
        array[c_gate_old, c_gate_new, '1'],
        array[E'    tokens_applied_count, tokens_applied_value_cents)\n  VALUES (v_uid,',
              E'    tokens_applied_count, tokens_applied_value_cents, ride_kind)\n  VALUES (v_uid,', '1'],
        array[E'    v_tokens_discount_cents)\n  RETURNING * INTO v_ride;',
              E'    v_tokens_discount_cents, v_ride_kind)\n  RETURNING * INTO v_ride;', '1']];
    elsif r.nome = 'tvde_schedule_ride' then
      v_body_pairs := array[
        array[E'  v_fixed_driver int;\nBEGIN', E'  v_fixed_driver int;\n  v_ride_kind text;\nBEGIN', '1'],
        array[c_gate_old, c_gate_new, '1'],
        array[E'    payment_method, status, scheduled_at, reservation_status, customer_note, payment_status)\n  VALUES (v_uid,',
              E'    payment_method, status, scheduled_at, reservation_status, customer_note, payment_status, ride_kind)\n  VALUES (v_uid,', '1'],
        array[E'    p_note, CASE WHEN v_online THEN ''pendente'' ELSE NULL END)\n  RETURNING * INTO v_ride;',
              E'    p_note, CASE WHEN v_online THEN ''pendente'' ELSE NULL END, v_ride_kind)\n  RETURNING * INTO v_ride;', '1']];
    else
      v_body_pairs := array[
        array[E'  v_ret_earn int;\nBEGIN', E'  v_ret_earn int;\n  v_ride_kind text;\nBEGIN', '1'],
        array[c_gate_old, c_gate_new, '1'],
        array[E'    p_est_distance_km, p_outbound_at, p_payment_method, p_note);',
              E'    p_est_distance_km, p_outbound_at, p_payment_method, p_note, v_ride_kind);', '1']];
    end if;

    v_new := pg_temp._a1_troca(v_def, r.hdr_old, r.hdr_new, 1, r.nome || ':assinatura');
    for i in 1 .. array_length(v_body_pairs, 1) loop
      v_new := pg_temp._a1_troca(v_new, v_body_pairs[i][1], v_body_pairs[i][2], v_body_pairs[i][3]::int, r.nome || ':troca' || i);
    end loop;

    execute format('DROP FUNCTION public.%I(%s)', r.nome, r.sig_old);
    execute v_new;

    v_sig_new := format('public.%I(%s)', r.nome, r.sig_new);
    execute format('REVOKE ALL ON FUNCTION %s FROM PUBLIC, anon', v_sig_new);
    execute format('GRANT EXECUTE ON FUNCTION %s TO authenticated, service_role', v_sig_new);

    v_oid := to_regprocedure(v_sig_new);
    if v_oid is null then raise exception 'A1 % nova não ficou criada', r.nome; end if;
    if (select count(*) from pg_proc p join pg_namespace n on n.oid = p.pronamespace
         where n.nspname = 'public' and p.proname = r.nome) <> 1 then
      raise exception 'A1 % ficou com mais de uma assinatura (sobrecarga)', r.nome;
    end if;
    select prosrc, proacl::text[] into v_src, v_acl_new from pg_proc where oid = v_oid;
    if (select array_agg(x order by x) from unnest(v_acl_new) x)
       is distinct from (select array_agg(x order by x) from unnest(v_acl_old) x) then
      raise exception 'A1 % permissões diferentes: antes % depois %', r.nome, v_acl_old, v_acl_new;
    end if;
    if (select pg_get_userbyid(proowner) from pg_proc where oid = v_oid) <> 'postgres' then
      execute format('ALTER FUNCTION %s OWNER TO postgres', v_sig_new);
    end if;

    -- prova byte a byte: desfaz as trocas do corpo e compara o md5
    v_back := v_src;
    for i in reverse array_length(v_body_pairs, 1) .. 1 loop
      v_back := pg_temp._a1_troca(v_back, v_body_pairs[i][2], v_body_pairs[i][1], v_body_pairs[i][3]::int, r.nome || ':desfaz' || i);
    end loop;
    if md5(v_back) <> r.md5_old then
      raise exception 'A1 % corpo novo sem as trocas NÃO é igual ao antigo (md5 % <> %)', r.nome, md5(v_back), r.md5_old;
    end if;
    raise notice 'A1 % ok: md5 antes % · md5 novo % · desfeito %', r.nome, r.md5_old, md5(v_src), md5(v_back);
  end loop;
end $mig$;

-- O PostgREST relê as assinaturas já (a chamada antiga continua a funcionar entretanto: os nomes dos parâmetros são os mesmos).
notify pgrst, 'reload schema';
