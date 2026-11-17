-- Teste de lojas_escondidas_para_mim() — missão a3-guarda-16-11, parte 2 (ponto 2 da caixa 114).
-- Prova a correção 20261117000300_lojas_escondidas_dono_vazio.sql (loja escondida SEM dono).
--
-- Corre numa transação que se desfaz (begin … rollback): não muda nada na base.
-- Usa as lojas escondidas reais: a3-guarda (sem dono) e as duas farmácias (com dono).
-- Cada caso simula uma sessão (request.jwt.claims) e diz se a loja fica escondida.
-- Resultado: uma linha por caso, com ok = true/false. Tudo true = passa.
--
-- Sem a correção, o caso "cliente com sessão fora da lista" dá ok=false na a3-guarda
-- (a loja aparece). Com a correção, todos ok=true.

begin;

create temp table _caso (caso text, loja text, escondida boolean, esperado boolean) on commit drop;

do $$
declare
  v_dono_se uuid := (select user_id from public.restaurants where id = 'farmacia-se-guarda');
  v_dono_tx uuid := (select user_id from public.restaurants where id = 'farmacia-teixeira-guarda');
  v_lista_a3 uuid := (select l.user_id from public.loja_lista_permissao l
                       join auth.users u on u.id = l.user_id
                      where l.restaurant_id = 'a3-guarda'
                        and coalesce(u.raw_app_meta_data->>'role', '') <> 'admin'
                        and u.email not in ('nilofulfarotuga@gmail.com', 'nilofulfaro@gmail.com')
                      limit 1);
  v_admin uuid := (select id from auth.users where email = 'nilofulfarotuga@gmail.com');
  v_estranho uuid := gen_random_uuid(); -- cliente com sessão, fora de todas as listas
  -- a conta da lista da A3 (do Danilo) também está na lista das farmácias: vê as que a incluem
  v_farm_lista text[] := array(select restaurant_id from public.loja_lista_permissao
                                where user_id = v_lista_a3 and restaurant_id like 'farmacia-%');
  v_farm_fora text[] := array(select id from public.restaurants
                               where so_lista_permissao and id like 'farmacia-%' and id <> all(v_farm_lista));
  v_loja text;
  v_esc text[];
  r record;
begin
  for r in
    select * from (values
      ('anónimo (sem sessão)',            null::uuid, array['a3-guarda','farmacia-se-guarda','farmacia-teixeira-guarda'], array[]::text[]),
      ('cliente com sessão fora da lista', v_estranho, array['a3-guarda','farmacia-se-guarda','farmacia-teixeira-guarda'], array[]::text[]),
      ('dono da Farmácia da Sé',           v_dono_se,  array['a3-guarda','farmacia-teixeira-guarda'],                    array['farmacia-se-guarda']),
      ('dono da Farmácia Teixeira',        v_dono_tx,  array['a3-guarda','farmacia-se-guarda'],                          array['farmacia-teixeira-guarda']),
      ('conta na lista da A3 (não admin)', v_lista_a3, v_farm_fora,                                                      array['a3-guarda'] || v_farm_lista),
      ('admin',                            v_admin,    array[]::text[],                                                   array['a3-guarda','farmacia-se-guarda','farmacia-teixeira-guarda'])
    ) as t(caso, uid, escondidas, visiveis)
  loop
    if r.uid is null and r.caso <> 'anónimo (sem sessão)' then
      insert into _caso values (r.caso, '(sem conta para simular)', null, null);
      continue;
    end if;
    perform set_config('request.jwt.claims',
      case when r.uid is null then '' else json_build_object('sub', r.uid, 'role', 'authenticated')::text end, true);
    perform set_config('request.jwt.claim.sub', coalesce(r.uid::text, ''), true);
    v_esc := public.lojas_escondidas_para_mim();
    foreach v_loja in array r.escondidas loop
      insert into _caso values (r.caso, v_loja, v_loja = any(v_esc), true);
    end loop;
    foreach v_loja in array r.visiveis loop
      insert into _caso values (r.caso, v_loja, v_loja = any(v_esc), false);
    end loop;
  end loop;
  perform set_config('request.jwt.claims', '', true);
  perform set_config('request.jwt.claim.sub', '', true);
end $$;

select caso, loja, escondida, esperado, escondida is not distinct from esperado as ok
  from _caso order by caso, loja;

rollback;
