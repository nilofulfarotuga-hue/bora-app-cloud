with x as (
  select p.name,
         ' ' || array_to_string(public.assistant_tokens(p.name), ' ') || ' ' as oficial,
         (' ' || btrim(regexp_replace(regexp_replace(regexp_replace(regexp_replace(regexp_replace(regexp_replace(regexp_replace(regexp_replace(regexp_replace(regexp_replace(' ' || regexp_replace(regexp_replace(lower(extensions.unaccent('extensions.unaccent'::regdictionary, coalesce(p.name, ''))), '[^a-z0-9]+', ' ', 'g'), ' ', '  ', 'g') || ' ', ' (de|da|do|das|dos|em|e|a|o|os|as|para|p|ao|aos|na|no|nas|nos|c|um|uma|ou|pra) ', ' ', 'g'), ' ([a-z][a-z0-9]*)oes ', ' \1ao ', 'g'), ' ([a-z][a-z0-9]*)aes ', ' \1ao ', 'g'), ' ([a-z][a-z0-9]*)ais ', ' \1al ', 'g'), ' ([a-z][a-z0-9]*)eis ', ' \1el ', 'g'), ' ([a-z][a-z0-9]*)ois ', ' \1ol ', 'g'), ' ([a-z][a-z0-9]+)ns ', ' \1m ', 'g'), ' ([a-z][a-z0-9]+[rz])es ', ' \1 ', 'g'), ' ([a-z][a-z0-9]+[^s ])s ', ' \1 ', 'g'), ' +', ' ', 'g')) || ' ') as rapido
    from public.products p
)
select count(*) as total,
       count(*) filter (where oficial <> rapido) as diferentes,
       (select string_agg(name || ' => [' || oficial || '] / [' || rapido || ']', ' || ') from (select * from x where oficial <> rapido limit 8) z) as exemplos
  from x;
