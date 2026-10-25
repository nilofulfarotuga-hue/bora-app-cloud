-- Missão livro-comum-2026-10-23 (Bloco 3a): o caderno de correções aprende nos dois sentidos.
-- livro_aprender acrescenta UMA linha ao fim da página erros-aprendidos do livro
-- (public.claude_ai_memoria), com a data de Lisboa: "- DD/MM (quem): errei → regra".
-- Nunca sobrescreve: só concatena. Fechada a anon e authenticated; só service_role
-- (Hermes, scripts da VPS) e o dono das funções (MCP do Claude Code / Claude.ai).

create or replace function public.livro_aprender(p_quem text, p_errei text, p_regra text)
returns text
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_quem  text := lower(btrim(coalesce(p_quem, '')));
  v_errei text := regexp_replace(btrim(coalesce(p_errei, '')), '\s+', ' ', 'g');
  v_regra text := regexp_replace(btrim(coalesce(p_regra, '')), '\s+', ' ', 'g');
  v_linha text;
begin
  if v_quem not in ('claude-ai', 'claude-code', 'hermes', 'chatgpt', 'opencode', 'codex') then
    raise exception 'livro_aprender: quem tem de ser claude-ai, claude-code, hermes, chatgpt, opencode ou codex';
  end if;
  if length(v_errei) < 3 or length(v_regra) < 3 then
    raise exception 'livro_aprender: errei e regra são obrigatórios';
  end if;
  if length(v_errei) > 400 or length(v_regra) > 400 then
    raise exception 'livro_aprender: máximo 400 caracteres em cada parte';
  end if;
  if (v_errei || ' ' || v_regra) ~ '(sk_live_|sk_test_|sb_secret_|eyJhbGciOi|ghp_[A-Za-z0-9]{20}|AIza[0-9A-Za-z_-]{30}|PRIVATE KEY)' then
    raise exception 'livro_aprender: parece um segredo; não se grava';
  end if;

  v_linha := '- ' || to_char(now() at time zone 'Europe/Lisbon', 'DD/MM') || ' (' || v_quem || '): '
             || v_errei || ' → ' || v_regra;

  update public.claude_ai_memoria
     set conteudo = rtrim(conteudo, E'\n') || E'\n' || v_linha || E'\n',
         atualizado_em = now()
   where pagina = 'erros-aprendidos';
  if not found then
    raise exception 'livro_aprender: a página erros-aprendidos não existe';
  end if;
  return v_linha;
end;
$$;

revoke all on function public.livro_aprender(text, text, text) from public;
revoke all on function public.livro_aprender(text, text, text) from anon, authenticated;
grant execute on function public.livro_aprender(text, text, text) to service_role;

comment on function public.livro_aprender(text, text, text) is
  'Acrescenta uma correção do Danilo ao fim de erros-aprendidos (livro). Só acrescenta. Missão livro-comum-2026-10-23.';
