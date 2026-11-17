-- Missão servidor-busca-leve-2026-11-17 — provas do B1 em produção. CORRE A CLAUDE.AI, por partes,
-- na ordem de docs/propostas/busca-leve-2026-11-17/APLICAR.md. Cada parte diz o resultado esperado.
-- Lista das 311 pesquisas (12 fixas da ordem + 299 tiradas dos nomes dos produtos, com e sem
-- acento, plural, erros de escrita, duas palavras e começos de palavra): consultas_teste.txt.

-- =============================================================================================
-- PARTE 0 — ANTES da 20261117100100: cópia da função de hoje, para comparar.
-- =============================================================================================
do $$
declare d text;
begin
  perform extensions.similarity('a', 'b');
  d := pg_get_functiondef('public.pesquisa_produtos(text,text,integer,vector)'::regprocedure);
  d := replace(d, 'FUNCTION public.pesquisa_produtos(', 'FUNCTION public.pesquisa_produtos_antiga(');
  execute d;
end $$;
revoke all on function public.pesquisa_produtos_antiga(text, text, integer, vector) from public;
grant execute on function public.pesquisa_produtos_antiga(text, text, integer, vector) to anon, authenticated;
-- (o grant a anon/authenticated é só para a PARTE 2 correr com "set role anon"; a função sai na PARTE 3)

-- =============================================================================================
-- PARTE 1 — DEPOIS da 20261117100000 e do enchimento (APLICAR.md passos 1-2). Esperado: tudo 0 / true.
-- =============================================================================================
-- 1a) bora_ns/bora_nr dão EXATAMENTE a expressão antiga em todos os produtos
select count(*) filter (where public.bora_ns(p.name) is distinct from (' ' || btrim(regexp_replace(regexp_replace(regexp_replace(regexp_replace(regexp_replace(regexp_replace(regexp_replace(regexp_replace(regexp_replace(regexp_replace(' ' || regexp_replace(regexp_replace(lower(extensions.unaccent('extensions.unaccent'::regdictionary, coalesce(p.name, ''))), '[^a-z0-9]+', ' ', 'g'), ' ', '  ', 'g') || ' ', ' (de|da|do|das|dos|em|e|a|o|os|as|para|p|ao|aos|na|no|nas|nos|c|um|uma|ou|pra) ', ' ', 'g'), ' ([a-z][a-z0-9]*)oes ', ' \1ao ', 'g'), ' ([a-z][a-z0-9]*)aes ', ' \1ao ', 'g'), ' ([a-z][a-z0-9]*)ais ', ' \1al ', 'g'), ' ([a-z][a-z0-9]*)eis ', ' \1el ', 'g'), ' ([a-z][a-z0-9]*)ois ', ' \1ol ', 'g'), ' ([a-z][a-z0-9]+)ns ', ' \1m ', 'g'), ' ([a-z][a-z0-9]+[rz])es ', ' \1 ', 'g'), ' ([a-z][a-z0-9]+[^s ])s ', ' \1 ', 'g'), ' +', ' ', 'g')) || ' ')) as ns_nome_diferentes,
       count(*) filter (where public.bora_ns(p.category) is distinct from (' ' || btrim(regexp_replace(regexp_replace(regexp_replace(regexp_replace(regexp_replace(regexp_replace(regexp_replace(regexp_replace(regexp_replace(regexp_replace(' ' || regexp_replace(regexp_replace(lower(extensions.unaccent('extensions.unaccent'::regdictionary, coalesce(p.category, ''))), '[^a-z0-9]+', ' ', 'g'), ' ', '  ', 'g') || ' ', ' (de|da|do|das|dos|em|e|a|o|os|as|para|p|ao|aos|na|no|nas|nos|c|um|uma|ou|pra) ', ' ', 'g'), ' ([a-z][a-z0-9]*)oes ', ' \1ao ', 'g'), ' ([a-z][a-z0-9]*)aes ', ' \1ao ', 'g'), ' ([a-z][a-z0-9]*)ais ', ' \1al ', 'g'), ' ([a-z][a-z0-9]*)eis ', ' \1el ', 'g'), ' ([a-z][a-z0-9]*)ois ', ' \1ol ', 'g'), ' ([a-z][a-z0-9]+)ns ', ' \1m ', 'g'), ' ([a-z][a-z0-9]+[rz])es ', ' \1 ', 'g'), ' ([a-z][a-z0-9]+[^s ])s ', ' \1 ', 'g'), ' +', ' ', 'g')) || ' ')) as ns_categoria_diferentes,
       count(*) filter (where public.bora_nr(p.name) is distinct from (' ' || regexp_replace(lower(extensions.unaccent('extensions.unaccent'::regdictionary, coalesce(p.name, ''))), '[^a-z0-9]+', ' ', 'g') || ' ')) as nr_diferentes,
       count(*) as produtos
  from public.products p;

-- 1b) o texto da expressão de bora_ns está, letra a letra, dentro da função de hoje
select position('('' '' || btrim(regexp_replace(regexp_replace(regexp_replace(regexp_replace(regexp_replace(regexp_replace(regexp_replace(regexp_replace(regexp_replace(regexp_replace('' '' || regexp_replace(regexp_replace(lower(extensions.unaccent(''extensions.unaccent''::regdictionary, coalesce(c.name, ''''))), ''[^a-z0-9]+'', '' '', ''g''), '' '', ''  '', ''g'') || '' '', '' (de|da|do|das|dos|em|e|a|o|os|as|para|p|ao|aos|na|no|nas|nos|c|um|uma|ou|pra) '', '' '', ''g''), '' ([a-z][a-z0-9]*)oes '', '' \1ao '', ''g''), '' ([a-z][a-z0-9]*)aes '', '' \1ao '', ''g''), '' ([a-z][a-z0-9]*)ais '', '' \1al '', ''g''), '' ([a-z][a-z0-9]*)eis '', '' \1el '', ''g''), '' ([a-z][a-z0-9]*)ois '', '' \1ol '', ''g''), '' ([a-z][a-z0-9]+)ns '', '' \1m '', ''g''), '' ([a-z][a-z0-9]+[rz])es '', '' \1 '', ''g''), '' ([a-z][a-z0-9]+[^s ])s '', '' \1 '', ''g''), '' +'', '' '', ''g'')) || '' '')' in pg_get_functiondef('public.pesquisa_produtos_antiga(text,text,integer,vector)'::regprocedure)) > 0 as ns_igual_ao_texto_antigo,
       position('('' '' || regexp_replace(lower(extensions.unaccent(''extensions.unaccent''::regdictionary, coalesce(c.name, ''''))), ''[^a-z0-9]+'', '' '', ''g'') || '' '')' in pg_get_functiondef('public.pesquisa_produtos_antiga(text,text,integer,vector)'::regprocedure)) > 0 as nr_igual_ao_texto_antigo;

-- 1c) a tabela está completa e em dia
select (select count(*) from public.products) as produtos,
       (select count(*) from public.produtos_busca_ns) as linhas,
       (select count(*) from public.products p left join public.produtos_busca_ns b on b.product_id = p.id
         where b.product_id is null or b.nome is distinct from p.name or b.categoria is distinct from p.category
            or b.restaurant_id is distinct from p.restaurant_id) as em_falta_ou_desatualizadas;

-- 1d) secções: iguais às que saem dos produtos disponíveis (0 nas duas colunas)
with certo as (select distinct p.restaurant_id, p.category_root, p.id like 'premio-checkin-%' as premio
                 from public.products p where p.is_available and p.category_root is not null)
select (select count(*) from certo c where not exists (select 1 from public.seccoes_disponiveis s
          where s.restaurant_id = c.restaurant_id and s.category_root = c.category_root and s.premio = c.premio)) as em_falta,
       (select count(*) from public.seccoes_disponiveis s where not exists (select 1 from certo c
          where s.restaurant_id = c.restaurant_id and s.category_root = c.category_root and s.premio = c.premio)) as a_mais;

-- 1e) gatilho, numa transação desfeita: produto de teste nasce, muda de nome e sai
begin;
insert into public.products (id, restaurant_id, name, category, price, is_available)
values ('teste-busca-leve-17-11', 'continente-guarda', 'Pães de Leite Teste', 'Padaria e Pastelaria', 1.00, true);
select ns = public.bora_ns('Pães de Leite Teste') as ns_certo_ao_nascer from public.produtos_busca_ns where product_id = 'teste-busca-leve-17-11';
update public.products set name = 'Pão Alentejano Teste' where id = 'teste-busca-leve-17-11';
select nome = 'Pão Alentejano Teste' and ns = public.bora_ns('Pão Alentejano Teste') as ns_certo_depois_de_mudar from public.produtos_busca_ns where product_id = 'teste-busca-leve-17-11';
rollback;
-- (se o insert falhar por outra coluna obrigatória/guarda do catálogo, ajustar só os valores do teste)

-- =============================================================================================
-- PARTE 2 — DEPOIS da 20261117100100. Esperado: diferentes = 0 (como postgres E como anon).
-- =============================================================================================
create temp table t_dif (papel text, q text, loja text);
do $$
declare q text; l text;
begin
  perform extensions.similarity('a', 'b');
  foreach q in array array['pa','co','car','pao','leite','agua','frango','coca cola','cerveja sagres','papel higenico','iogurte grego','detergente roupa','adult','ambientador','anos','atum','auchan','aveia','azul','bebé','bebida','black','bolachas','branca','bruto','cabelo','cacau','caderno','cães','caixa','caneta','cápsulas','caramelo','casa','castanho','cemporcento','chocolate','clássico','colgate','comida','compal','condicionador','delta','desodorizante','detergente','dexter','doce','doses','equilíbrio','facial','fatiado','feijão','fraldas','frutos','garrafa','gato','gatos','glúten','grande','hidratante','incontinência','infusão','integral','jogo','júnior','lactose','lego','limpeza','loiça','loréal','maçã','manteiga','meio','menino','mesa','mistura','molho','natural','néctar','normal','note','oréal','pantene','para','pastilhas','peso','porta','porto','power','preto','rosé','saquetas','seleção','soja','solar','spray','stick','suplemento','tamanho','unidades','vaca','vegetal','acucar','agua','alcool','algodao','amendoa','ananas','apagavel','bebe','caes','cafe','capsulas','champo','classico','coloracao','equilibrio','gluten','humida','incontinencia','infusao','lapis','limao','liquido','loica','maca','maquina','margao','mascara','nectar','nestle','oleo','oreal','pedacos','pessego','proteina','racao','rose','salmao','selecao','serum','setubal','águas','amêndoas','aveias','azeites','banhos','cacaus','cemporcentos','chocolates','cinzas','continentes','corpos','dexters','escuros','espumantes','frangos','freshs','gelatinas','infusãos','líquidos','mangas','manteigas','máquinas','máscaras','massas','meninos','peles','pesos','pêssegos','pingos','pretos','recargas','refrigerantes','reservas','roupas','sérums','solars','sprays','suaves','tomates','zeros','açúar','alentjano','ambietador','anaás','apagvel','azete','bacahau','batta','bebda','bolahas','bolcha','canta','choclate','clásico','colate','conjnto','danne','denes','equilbrio','escorido','fatado','fradas','freco','gelaina','glúen','legmi','líqido','mantiga','máqina','marão','misura','mylbel','penísula','penos','permaente','quejo','quita','tabete','toalitas','uniddes','açcúar','adluto','alenetjano','aziete','baatta','babrear','baclahau','bauinlha','caenla','daonne','emblaagem','fimabre','flaemngo','flroes','frnago','hedrade','laarnja','máuqina','myalbel','permnaente','preusnto','quiejo','qunita','rehceio','samlão','santiário','talbete','toahlitas','veremlho','veremlhos','auchan bio','azeite virgem','azul escuro','bebé menina','branco garrafa','branco tamanho','caneta apagável','cem porcento','cerveja com','com gás','continente equilíbrio','dão vinho','desodorizante spray','dolce gusto','equilíbrio emb','esferográfica apagável','frutos vermelhos','húmida para','iogurte líquido','lata para','lava tudo','leite com','máquina loiça','menina branco','para menina','para menino','pastilhas elásticas','porsi viva','porta chaves','produção própria','queijo flamengo','ração para','refrigerante com','reserva douro','sem glúten','top down','várias cores','vinho branco','vinho rosé','vinho tinto','acti','ant','cer','doc','fati','fran','fru','frut','loi','mang','molh','mor','myla','ori','par','ref','snac','veg','vinh']::text[] loop
    foreach l in array array[null, 'continente-guarda']::text[] loop
      continue when length(replace(public.bora_normalize(q), ' ', '')) < 3;  -- 2 letras: só secções
      if (select array_agg(r.id order by r.o) from public.pesquisa_produtos_antiga(q, l, 50) with ordinality r(id, n, c, cr, p, f, rid, k, s, o))
         is distinct from
         (select array_agg(r.id order by r.o) from public.pesquisa_produtos(q, l, 50) with ordinality r(id, n, c, cr, p, f, rid, k, s, o)) then
        insert into t_dif values (current_user, q, l);
      end if;
    end loop;
  end loop;
end $$;
select count(*) as diferentes_postgres, string_agg(q || '@' || coalesce(l, '*'), ', ') from t_dif t(papel, q, l);

-- o mesmo como quem usa a app sem login (as regras de leitura das tabelas novas entram em jogo)
set role anon;
select count(*) as diferentes_anon, string_agg(x.q || '@' || coalesce(y.l0, '*'), ', ') as quais
  from unnest(array['pa','co','car','pao','leite','agua','frango','coca cola','cerveja sagres','papel higenico','iogurte grego','detergente roupa']::text[]) as x(q)
  cross join lateral unnest(array[null, 'continente-guarda']::text[]) as y(l0)
 where length(replace(public.bora_normalize(x.q), ' ', '')) >= 3
   and (select array_agg(r.id order by r.o) from public.pesquisa_produtos_antiga(x.q, y.l0, 50) with ordinality r(id, n, c, cr, p, f, rid, k, s, o))
       is distinct from
       (select array_agg(r.id order by r.o) from public.pesquisa_produtos(x.q, y.l0, 50) with ordinality r(id, n, c, cr, p, f, rid, k, s, o));
reset role;

-- secções como anon: as de seccoes_disponiveis = as de products (0 e 0)
set role anon;
select (select count(*) from (select distinct category_root from public.products where is_available and category_root is not null
          except select distinct category_root from public.seccoes_disponiveis) z) as so_em_products,
       (select count(*) from (select distinct category_root from public.seccoes_disponiveis
          except select distinct category_root from public.products where is_available and category_root is not null) z) as so_em_seccoes;
reset role;

-- DEPOIS: tempo de cada pesquisa da lista fixa, como a app a chama (search_products), 3 vezes, mediana
create temp table t_tempo (q text, loja text, ms numeric);
do $$
declare q text; l text; i int; t0 timestamptz;
begin
  foreach q in array array['pa','co','car','pao','leite','agua','frango','coca cola','cerveja sagres','papel higenico','iogurte grego','detergente roupa']::text[] loop
    foreach l in array array[null, 'continente-guarda']::text[] loop
      for i in 1..3 loop
        t0 := clock_timestamp();
        perform count(*) from public.search_products(q, l, 50);
        insert into t_tempo values (q, coalesce(l, '*'), round((extract(epoch from clock_timestamp() - t0) * 1000)::numeric, 1));
      end loop;
    end loop;
  end loop;
end $$;
select q, loja, percentile_cont(0.5) within group (order by ms) as mediana_ms from t_tempo group by q, loja order by loja, q;

-- =============================================================================================
-- PARTE 3 — no fim, com a PARTE 2 a 0: apagar a cópia.
-- =============================================================================================
drop function if exists public.pesquisa_produtos_antiga(text, text, integer, vector);
