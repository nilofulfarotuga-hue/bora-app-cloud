-- Missão fechar-app-15-11, Bloco 3c (14/11/2026) — POR APLICAR (aplica a Claude.ai).
--
-- A app passou a pedir os produtos de uma loja por cursor, na ordem de sempre:
-- sort_order crescente (vazios no fim), depois id. Sem este índice cada página
-- ordena a loja inteira (Continente: 19 808 linhas, 59 ms e 5 MB em disco por
-- página, medido a 14/11). Com ele o servidor lê as linhas já pela ordem.
--
-- A app funciona sem o índice (custa o mesmo que hoje); o índice só a torna
-- mais leve. Não muda dados, preços nem regras. Tabela com cerca de 45 mil
-- linhas: a criação demora menos de um segundo.

create index if not exists idx_products_loja_ordem_disponiveis
  on public.products (restaurant_id, sort_order, id)
  where is_available = true;
