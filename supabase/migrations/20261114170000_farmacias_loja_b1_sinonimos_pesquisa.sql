-- Missão farmacias-loja-2026-11-14 · bloco 4 (lupa dentro da loja da farmácia).
--
-- O que muda: só DADOS em public.pesquisa_sinonimos (5 linhas, todas as lojas,
-- origem 'manual', o mesmo mecanismo da semente de 09/11 em
-- 20261109070000_pesquisa_inteligente.sql). Nenhuma função muda; o filtro das
-- lojas escondidas (lojas_escondidas_para_mim / políticas RESTRICTIVE) fica
-- igual, porque search_products e pesquisa_produtos são SECURITY INVOKER.
--
-- Porquê (provado a 14/11 na Farmácia da Sé, 867 produtos, search_products
-- com p_restaurant_id = 'farmacia-se-guarda'):
--   * "protector solar" (grafia antiga) não apanhava a frase-sinónimo
--     "protetor solar" → só restos 'parcial' e "Vibrocil ActilongProtect" em
--     1.º lugar. Com estas linhas fica igual a "protetor solar".
--   * "protetor solar" deixava de fora 8 protetores PIZ BUIN escritos "FPS".
--     Com o alvo "fps" passam de 35 para 43 produtos certos.
--   * "escova de dentes" só achava um elixir (BEXIDENT); as escovas estão
--     abreviadas no catálogo ("ELGYDIUM ... ESC DENT ..."). Com o alvo
--     "esc dent" acha as 4 escovas.
-- O gatilho trg_pesquisa_sinonimos_normalizar calcula chave/alvo_chave
-- (assistant_tokens): "escova de dentes" → "escova dente" (igual para
-- "escova dentes", "escovas de dentes"); "protector solar" → "protector solar".
--
-- Idempotente (uq_pesquisa_sinonimos + on conflict do nothing). Sem dinheiro.
-- Desfazer: delete from public.pesquisa_sinonimos where origem = 'manual'
--   and (chave, alvo_chave) in (('protector solar','spf'),('protector solar','solar'),
--   ('protector solar','fps'),('protetor solar','fps'),('escova dente','esc dent'));

insert into public.pesquisa_sinonimos (termo, alvo, origem)
select v.termo, v.alvo, 'manual'
  from (values
    ('protector solar', 'spf'),
    ('protector solar', 'solar'),
    ('protector solar', 'fps'),
    ('protetor solar',  'fps'),
    ('escova de dentes', 'esc dent')
  ) as v(termo, alvo)
on conflict do nothing;

-- Prova (correr depois de aplicar; esperado na Farmácia da Sé):
--   select t, count(*) filter (where r.match_kind <> 'parcial') as certos
--     from (values ('protetor solar'),('protector solar'),('escova de dentes')) v(t)
--     cross join lateral public.pesquisa_produtos(t, 'farmacia-se-guarda', 200) r
--    group by t;
--   → protetor solar 43 · protector solar 43 · escova de dentes 4
--   (antes: 35 · 9 [8 'significado' + Vibrocil 'parecido'] · 0)
