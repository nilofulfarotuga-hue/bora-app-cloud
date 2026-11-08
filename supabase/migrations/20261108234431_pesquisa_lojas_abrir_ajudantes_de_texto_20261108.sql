-- M10 (08/11/2026): a pesquisa dentro das lojas (search_products, SECURITY INVOKER, aberta a anon e
-- authenticated) chama assistant_tokens, assistant_singular e f_unaccent, que estavam fechadas a esses papeis
-- (42501 -> "Sem resultados" na app). Sao funcoes IMMUTABLE so de texto (nao leem tabelas).
-- Motivo do GRANT a anon: a pesquisa funciona antes do login (convidado).
grant execute on function public.assistant_tokens(text) to anon, authenticated;
grant execute on function public.assistant_singular(text) to anon, authenticated;
grant execute on function public.f_unaccent(text) to anon, authenticated;
