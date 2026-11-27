-- 27/11/2026 — Atendente de voz: procurar lojas por nomes PARECIDOS (pedido do Danilo depois da chamada das 11:42:
-- "eu falei Josmin, mesmo que esteja errado, ela tinha que procurar alguma coisa parecida").
-- O reconhecimento de voz escreve os nomes como soam ("Josemim", "Jovem", "Jasmim" para "Jyosmi Sushi").
-- A procura antiga era ilike '%nome%' e não achava nada. Agora junta três medidas e devolve as 5 melhores:
--   1. parecença de letras (pg_trgm) do nome inteiro;
--   2. parecença de palavra (word_similarity);
--   3. esqueleto pelo som: sem acentos, y=i, z=s, k=c, sem h, sem vogais (menos a 1.ª letra), sem letras
--      dobradas ("jyosmi" e "josemim" dão os dois "jsm"), comparado por distância de edição (fuzzystrmatch).
-- Só leitura, só para o servidor (voz-cerebro chama com a chave de serviço).

create extension if not exists fuzzystrmatch with schema extensions;

create or replace function public.voz_esqueleto(p text)
returns text language sql immutable set search_path = public, extensions as $$
  with base as (
    select translate(
             replace(replace(replace(replace(replace(replace(
               regexp_replace(lower(extensions.unaccent(coalesce(p, ''))), '[^a-z]', '', 'g'),
             'ph', 'f'), 'qu', 'c'), 'ch', 'x'), 'lh', 'l'), 'nh', 'n'), 'h', ''),
           'yzkw', 'iscv') as s
  )
  select regexp_replace(left(s, 1) || regexp_replace(substr(s, 2), '[aeiou]', '', 'g'), '(.)\1+', '\1', 'g')
    from base;
$$;

create or replace function public.voz_procurar_loja(p_nome text)
returns table (nome text, tipo text, parceira boolean, disponivel_na_app boolean, horario jsonb, parecenca numeric)
language plpgsql stable security definer set search_path = public, extensions as $$
declare
  q text := lower(extensions.unaccent(trim(coalesce(p_nome, ''))));
begin
  if length(q) < 2 then return; end if;
  return query
  with palavras_q as (
    select public.voz_esqueleto(w) as sk from regexp_split_to_table(q, '\s+') w where length(w) >= 3
  ),
  lojas as (
    select r.name, r.category, r.is_partner, r.coming_soon, r.approval_status, r.business_hours,
           lower(extensions.unaccent(r.name)) as n
      from public.restaurants r
     where r.name !~* '(demo|teste)'
  ),
  pontos as (
    select l.*,
           greatest(
             extensions.similarity(l.n, q),
             extensions.word_similarity(q, l.n),
             coalesce((
               select max(1 - extensions.levenshtein(public.voz_esqueleto(w), pq.sk)::numeric
                            / greatest(length(public.voz_esqueleto(w)), length(pq.sk), 1))
                 from regexp_split_to_table(l.n, '\s+') w, palavras_q pq
                where length(w) >= 3 and length(pq.sk) >= 2
             ), 0)
           )::numeric as p
      from lojas l
  ),
  com_topo as (select pontos.*, max(pontos.p) over () as topo from pontos)
  select pt.name::text, pt.category::text, coalesce(pt.is_partner, false),
         (pt.approval_status = 'approved' and not coalesce(pt.coming_soon, false)),
         to_jsonb(pt.business_hours), round(pt.p, 2)
    from com_topo pt
   where (pt.p >= greatest(0.45, pt.topo - 0.3)) or pt.n like '%' || q || '%'
   order by pt.p desc
   limit 5;
end $$;

revoke all on function public.voz_esqueleto(text) from public, anon, authenticated;
revoke all on function public.voz_procurar_loja(text) from public, anon, authenticated;
grant execute on function public.voz_esqueleto(text), public.voz_procurar_loja(text) to service_role;
