-- Missão servidor-nao-travar-2026-11-16, bloco B4.1.
-- pesquisa_produtos: a junção às categorias normalizadas (catn) usava
-- "is not distinct from", que não usa hash e fazia ~1,25 M comparações.
-- Passa a igualdade simples sobre coalesce(category, ''), com o catn já
-- agrupado pelo mesmo coalesce. Provado a 16/11 na cópia pesquisa_produtos_teste:
-- resultados iguais em 8 buscas (vinho branco 1l, leite, frango, chocolate fundue,
-- batata, papel higenico, coca cola 1,5l, pizza), 15-25% mais rápido.
-- Só troca estas duas linhas; mantém o SET pg_trgm.word_similarity_threshold = 0.45.
do $mig$
declare
  d text;
  n text;
begin
  -- carrega o pg_trgm nesta sessão: sem isto o SET pg_trgm.word_similarity_threshold
  -- da função dá "permission denied to set parameter" (parâmetro ainda desconhecido).
  perform extensions.similarity('a', 'b');
  d := pg_get_functiondef('public.pesquisa_produtos(text,text,integer,vector)'::regprocedure);
  n := replace(d,
    'from (select distinct cand.category from cand) k',
    'from (select distinct coalesce(cand.category, '''') as category from cand) k');
  n := replace(n,
    'left join catn kn on kn.category is not distinct from c.category',
    'left join catn kn on kn.category = coalesce(c.category, '''')');
  if n = d then
    if position('left join catn kn on kn.category = coalesce(c.category, '''')' in d) > 0 then
      raise notice 'pesquisa_produtos já tinha a troca; nada a fazer';
    else
      raise exception 'pesquisa_produtos: texto esperado não encontrado, nada mudado';
    end if;
  else
    if position('word_similarity_threshold' in n) = 0 then
      raise exception 'pesquisa_produtos: perdeu o SET do limiar, nada mudado';
    end if;
    execute n;
  end if;
end
$mig$;

-- A cópia de ensaio de 16/11 deixa de ser precisa.
drop function if exists public.pesquisa_produtos_teste(text, text, integer, vector);
