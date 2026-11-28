-- Missão lupa-sugestoes-17-11 (bloco 2) — prova DEPOIS de aplicar 20261117140100_pesquisa_dono.sql.
-- Compara a pesquisa_produtos nova (SECURITY DEFINER, regras à mão) com pesquisa_produtos_antiga
-- (a de antes de 17/11, que corre com as regras de leitura RLS) para 4 pessoas, produto a produto.
-- "Igual" = o mesmo conjunto de produtos e a mesma sequência de nome+nota (produtos empatados com o
-- mesmo nome e a mesma nota podem trocar de lugar entre si — já acontecia na antiga).
-- ESPERADO: em cada pessoa, "iguais" = "pesquisas" e "A3" = 0 para anon e normal.
-- Cada bloco desfaz tudo (RAISE no fim). Correr um bloco por pessoa se o MCP der tempo esgotado.
do $$
declare
  x_qs text[] := array['leite','frango','caes','coca cola','papel higenico','caneta','caderno',
                       'vitamina c','porta chaves','iogrute grego','detergnte roupa','chocolat'];
  x_cont text; x_lojas text[]; x_ctx text; x_sub text; x_role text; x_q text; x_l text;
  a_set text; a_nom text; n_set text; n_nom text; x_a3 int;
  x_n int; x_eq int; x_a3t int; x_ma numeric; x_mn numeric; x_t0 timestamptz; x_out text := ''; x_dif text;
begin
  select id into x_cont from public.restaurants where name ilike 'continente%' order by id limit 1;
  x_lojas := array['*', x_cont, 'a3-guarda'];
  foreach x_ctx in array array['anon','normal','dono_a3','admin'] loop
    x_sub := case x_ctx when 'anon' then '' when 'normal' then 'a5305b27-24c9-4498-8fff-d6a3c31249c6'
                        when 'dono_a3' then '0420ab5b-7f14-4cf3-aa81-7c5125699801'
                        else 'c9fccf85-03ee-4efc-83bf-613f211a78ff' end;
    x_role := case when x_ctx = 'anon' then 'anon' else 'authenticated' end;
    perform set_config('request.jwt.claim.sub', x_sub, true);
    perform set_config('request.jwt.claims', json_build_object('sub', nullif(x_sub, ''), 'role', x_role)::text, true);
    perform set_config('role', x_role, true);
    x_n := 0; x_eq := 0; x_a3t := 0; x_ma := 0; x_mn := 0; x_dif := '';
    foreach x_q in array x_qs loop
      foreach x_l in array x_lojas loop
        x_n := x_n + 1;
        x_t0 := clock_timestamp();
        select string_agg(r.id || '/' || r.match_kind || '/' || round(r.score::numeric, 3), ',' order by r.id),
               string_agg(r.name || '/' || round(r.score::numeric, 4), ',' order by r.o)
          into a_set, a_nom
          from public.pesquisa_produtos_antiga(x_q, nullif(x_l, '*'), 50)
               with ordinality r(id, name, category, category_root, price, photo_url, restaurant_id, match_kind, score, o);
        x_ma := x_ma + extract(epoch from clock_timestamp() - x_t0) * 1000;
        x_t0 := clock_timestamp();
        select string_agg(r.id || '/' || r.match_kind || '/' || round(r.score::numeric, 3), ',' order by r.id),
               string_agg(r.name || '/' || round(r.score::numeric, 4), ',' order by r.o),
               count(*) filter (where r.restaurant_id = 'a3-guarda')
          into n_set, n_nom, x_a3
          from public.pesquisa_produtos(x_q, nullif(x_l, '*'), 50)
               with ordinality r(id, name, category, category_root, price, photo_url, restaurant_id, match_kind, score, o);
        x_mn := x_mn + extract(epoch from clock_timestamp() - x_t0) * 1000;
        if x_l <> 'a3-guarda' then x_a3t := x_a3t + coalesce(x_a3, 0); end if;
        if a_set is not distinct from n_set and a_nom is not distinct from n_nom then x_eq := x_eq + 1;
        elsif length(x_dif) < 300 then x_dif := x_dif || format(' [%s@%s]', x_q, x_l); end if;
      end loop;
    end loop;
    x_out := x_out || format(' | %s: pesquisas %s iguais %s A3-fora-da-loja-A3 %s ms antiga %s ms nova %s%s',
                             x_ctx, x_n, x_eq, x_a3t, round(x_ma), round(x_mn), x_dif);
  end loop;
  perform set_config('role', 'none', true);
  raise exception 'RESULT%', x_out;
end $$;
