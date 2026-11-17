-- Missão lupa-sugestoes-17-11 — provas DEPOIS de aplicar 20261117140000_lupa_sugestoes.sql.
-- Correr pelo MCP execute_sql, um bloco de cada vez. Cada bloco termina em RAISE EXCEPTION
-- 'RESULT ...': tudo o que fez é desfeito e o resultado vem na mensagem do erro.
-- Contas: anon (sem login); normal a5305b27 (cliente sem lista); dono da A3 0420ab5b;
-- admin c9fccf85.
--
-- ESPERADO: "FALHAS 0" em todos os blocos.

-- 1. Visibilidade: a A3 (e qualquer loja escondida) nunca aparece a quem não a vê.
do $$
declare
  x_ctx text; x_sub text; x_role text; x_q text; x_n int; x_falhas int := 0; x_out text := '';
  x_esc text[]; x_vistas int; x_a3 int; x_tot int := 0;
begin
  foreach x_ctx in array array['anon','normal','dono_a3','admin'] loop
    x_sub := case x_ctx when 'anon' then '' when 'normal' then 'a5305b27-24c9-4498-8fff-d6a3c31249c6'
                        when 'dono_a3' then '0420ab5b-7f14-4cf3-aa81-7c5125699801'
                        else 'c9fccf85-03ee-4efc-83bf-613f211a78ff' end;
    x_role := case when x_ctx = 'anon' then 'anon' else 'authenticated' end;
    perform set_config('request.jwt.claim.sub', x_sub, true);
    perform set_config('request.jwt.claims', json_build_object('sub', nullif(x_sub, ''), 'role', x_role)::text, true);
    perform set_config('role', x_role, true);
    x_esc := coalesce(public.lojas_escondidas_para_mim(), '{}'::text[]);
    x_vistas := 0;
    -- todas as letras e pares mais comuns, lupa geral e lupa de cada loja escondida
    foreach x_q in array array['a','b','c','d','e','f','g','h','i','j','l','m','n','o','p','q','r','s','t','u','v','x','z',
                               'ca','co','ag','ar','pa','pe','ch','ma','ba','le','ta','ga'] loop
      select count(*), count(*) filter (where s.restaurant_id = any (x_esc))
        into x_n, x_a3
        from public.lupa_sugestoes(x_q, null) s;
      x_tot := x_tot + x_n;
      if x_n > 8 then x_falhas := x_falhas + 1; x_out := x_out || format(' [%s geral "%s" devolveu %s > 8]', x_ctx, x_q, x_n); end if;
      if x_a3 > 0 then x_falhas := x_falhas + 1; x_out := x_out || format(' [%s geral "%s": %s de loja escondida]', x_ctx, x_q, x_a3); end if;
      -- a lupa da A3: só quem a vê recebe sugestões
      select count(*) into x_n from public.lupa_sugestoes(x_q, 'a3-guarda');
      x_vistas := x_vistas + x_n;
    end loop;
    if 'a3-guarda' = any (x_esc) and x_vistas > 0 then
      x_falhas := x_falhas + 1; x_out := x_out || format(' [%s viu %s sugestões da lupa da A3]', x_ctx, x_vistas);
    end if;
    if not ('a3-guarda' = any (x_esc)) and x_vistas = 0 then
      x_falhas := x_falhas + 1; x_out := x_out || format(' [%s devia ver a lupa da A3 e não viu nada]', x_ctx);
    end if;
    x_out := x_out || format(' | %s: escondidas=%s lupa A3=%s', x_ctx, array_length(x_esc, 1), x_vistas);
    perform set_config('role', 'none', true);
  end loop;
  -- prémios do check-in nunca entram na tabela
  select count(*) into x_n from public.lupa_sugestoes s where s.ref like 'premio-checkin-%';
  if x_n > 0 then x_falhas := x_falhas + 1; x_out := x_out || format(' [%s prémios na tabela]', x_n); end if;
  raise exception 'RESULT FALHAS % (sugestões lidas %)%', x_falhas, x_tot, x_out;
end $$;

-- 2. Velocidade e índice: 1 letra em menos de 10 ms, a ler o índice por prefixo.
do $$
declare l text; x_plano text := ''; x_t0 timestamptz; x_ms numeric; x_max numeric := 0; x_q text; x_falhas int := 0;
begin
  perform set_config('request.jwt.claims', '{"role":"anon"}', true);
  perform set_config('role', 'anon', true);
  foreach x_q in array array['a','c','p','ag','ca','le'] loop
    x_t0 := clock_timestamp();
    perform * from public.lupa_sugestoes(x_q, null);
    x_ms := extract(epoch from clock_timestamp() - x_t0) * 1000;
    x_max := greatest(x_max, x_ms);
  end loop;
  perform set_config('role', 'none', true);
  for l in explain (costs off)
      select s.texto from public.lupa_sugestoes s
       where s.restaurant_id is null and s.texto_normalizado ~>=~ 'a' and s.texto_normalizado ~<~ 'a{'
  loop x_plano := x_plano || ' / ' || l; end loop;
  if x_max >= 10 then x_falhas := x_falhas + 1; end if;
  if x_plano not like '%lupa_sugestoes_prefixo%' then x_falhas := x_falhas + 1; end if;
  raise exception 'RESULT FALHAS % | pior tempo % ms | plano:%', x_falhas, round(x_max, 2), x_plano;
end $$;

-- 3. Interruptor: desligado = nada; ligado = volta.
do $$
declare a int; b int; c int;
begin
  select count(*) into a from public.lupa_sugestoes('a', null);
  update public.platform_settings set value = 'false'::jsonb where key = 'lupa_sugestoes_enabled';
  select count(*) into b from public.lupa_sugestoes('a', null);
  update public.platform_settings set value = 'true'::jsonb where key = 'lupa_sugestoes_enabled';
  select count(*) into c from public.lupa_sugestoes('a', null);
  raise exception 'RESULT FALHAS % | ligado % · desligado % · ligado outra vez %',
    (case when a > 0 and b = 0 and c = a then 0 else 1 end), a, b, c;
end $$;

-- 4. Gatilho: loja desaprovada sai logo; "Esconder sugestão" não volta com o recálculo.
do $$
declare x_loja text; a int; b int; x_id bigint; x_texto text; c boolean;
begin
  select s.ref into x_loja from public.lupa_sugestoes s where s.tipo = 'loja' and s.ref <> 'a3-guarda' order by s.id limit 1;
  select count(*) into a from public.lupa_sugestoes s where s.restaurant_id = x_loja or s.loja_origem = x_loja;
  update public.restaurants set approval_status = 'pending' where id = x_loja;
  select count(*) into b from public.lupa_sugestoes s where s.restaurant_id = x_loja or s.loja_origem = x_loja;
  -- esconder uma palavra geral e recalcular à força
  select s.id, s.texto into x_id, x_texto from public.lupa_sugestoes s where s.tipo = 'palavra' and s.restaurant_id is null order by s.peso desc limit 1;
  update public.lupa_sugestoes set escondida = true where id = x_id;
  perform public.lupa_sugestoes_recalcular(true);
  select s.escondida into c from public.lupa_sugestoes s where s.id = x_id;
  raise exception 'RESULT FALHAS % | loja % linhas antes % depois de desaprovar % | "%" escondida depois do recálculo: %',
    (case when a > 0 and b = 0 and c then 0 else 1 end), x_loja, a, b, x_texto, c;
end $$;
