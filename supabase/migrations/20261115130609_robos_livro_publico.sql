-- Texto aplicado em produção a 15/11/2026 (schema_migrations.statements, versão 20261115130609); antes estava no repo como 20261115120000_robos_livro_publico.sql
-- Conferido a 15/11/2026: o SQL que corre é igual ao gravado no servidor; só comentários e espaços diferem.

-- A3 (missão manha-15-11, 15/11/2026) — o livro comum que os robôs podem ler, por LISTA FECHADA.
-- POR APLICAR: escrito no repo, não aplicado em produção.
--
-- O QUE FAZ: cria public.robos_livro_publico(p_pagina), só de leitura, que devolve do livro
-- (public.claude_ai_memoria) apenas as páginas de uma lista fechada E, mesmo dessas, esconde
-- qualquer página cujo texto traga margens, markup, comissões, lucro, nomes de tabelas ou funções
-- (palavras_com_sublinhado, public.x), chaves, emails, senhas escritas, ou o nome/identidade do
-- dono. Se alguém escrever uma coisa destas numa página da lista, a página deixa de sair (fecha,
-- não deixa escapar). Só a chamam os robôs do servidor (sessão service_role); para mais ninguém.
--
-- PROVA FEITA ANTES DE ESCREVER (SELECT em produção, 15/11/2026 ~09:30, só leitura):
--   * colunas de claude_ai_memoria: pagina (PK), titulo, conteudo, origem, atualizado_em; RLS ligada.
--   * 680 páginas no livro. Com o filtro de termos desta função, 669 ficam escondidas e só 11
--     passariam — e nenhuma dessas 11 é útil a um cliente (notas técnicas, o Jai, uma loja, séries).
--   * as páginas candidatas óbvias TODAS têm termos proibidos (4 de 4): regras-do-danilo,
--     livro-areas-tokens-cliente, livro-areas-robo-suporte, tokens-metade-do-saldo-2026-10-14
--     (têm o nome do dono, margens ou nomes internos). A página business-rules não existe com
--     esse nome. Por isso NENHUMA página que já existe entra na lista.
--   * a lista fechada é feita de duas páginas NOVAS, escritas de propósito para o público:
--       ajuda-publica-clientes, ajuda-publica-estafetas-parceiros
--     hoje existem 0 (SELECT: da_lista_existentes = 0), portanto 0 com termos proibidos.
--     O texto delas é o de docs/ajuda/*.md; entram pelo ficheiro
--     docs/propostas/manha-15-11/A3b-livro-paginas-publicas.sql (não é migração: é conteúdo).
--   * prova local (PGlite, Postgres 17): com as duas páginas criadas pelo A3b a função devolve as
--     2, com 0 termos proibidos; uma página da lista com o nome do dono escrito sai escondida; uma
--     página fora da lista nunca sai; sem sessão de servidor a chamada é recusada.
--
-- Para pôr outra página na lista: nova migração, depois de ler a página e provar por SELECT
-- que não traz nenhum destes termos.

create or replace function public._robos_livro_lista()
 returns text[]
 language sql
 immutable
 set search_path to 'public'
as $function$
  select array['ajuda-publica-clientes', 'ajuda-publica-estafetas-parceiros']::text[];
$function$;

-- true = o texto traz coisa que os robôs nunca podem dizer.
create or replace function public._robos_texto_interno(p_texto text)
 returns boolean
 language sql
 immutable
 set search_path to 'public'
as $function$
  select coalesce(p_texto, '') ~* '(markup|ocult|lucro|margem|margens|comiss|danilo|fulfaro|\mdono\M|\mdona\M|propriet|sk_live|sk_test|service_role|anon.?key|eyJ[A-Za-z0-9_-]{10}|password|api.?key|secret|segredo|(senha|palavra-passe)\s*[:=])'
      or coalesce(p_texto, '') ~ '([A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}|\mpublic\.[a-z_]+|\m[a-z]+_[a-z0-9_]+\M)';
$function$;

create or replace function public.robos_livro_publico(p_pagina text default null)
 returns table(pagina text, titulo text, conteudo text, atualizado_em timestamptz)
 language plpgsql
 stable
 security definer
 set search_path to 'public', 'pg_temp'
as $function$
begin
  -- Guarda: dentro de SECURITY DEFINER o current_user é sempre o dono da função, por isso
  -- olha-se para o papel do JWT (pedidos pela API) e para session_user (ligação direta).
  if coalesce(auth.jwt() ->> 'role', '') <> 'service_role'
     and session_user not in ('postgres', 'supabase_admin') then
    raise exception 'robos_livro_publico: só para os robôs do servidor' using errcode = '42501';
  end if;

  return query
    select m.pagina, m.titulo, m.conteudo, m.atualizado_em
      from public.claude_ai_memoria m
     where m.pagina = any (public._robos_livro_lista())
       and (p_pagina is null or m.pagina = p_pagina)
       and not public._robos_texto_interno(m.titulo || E'\n' || m.conteudo)
     order by m.pagina;
end;
$function$;

revoke all on function public._robos_livro_lista() from public, anon, authenticated;
revoke all on function public._robos_texto_interno(text) from public, anon, authenticated;
revoke all on function public.robos_livro_publico(text) from public, anon, authenticated;
grant execute on function public.robos_livro_publico(text) to service_role;

comment on function public.robos_livro_publico(text) is
  'Livro comum para os robôs (suporte e Amigo Bora): só as páginas da lista fechada _robos_livro_lista e só se o texto não tiver termos internos (_robos_texto_interno). Só service_role. Missão manha-15-11 A3.';
