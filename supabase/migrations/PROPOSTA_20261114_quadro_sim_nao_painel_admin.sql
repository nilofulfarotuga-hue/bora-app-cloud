-- PROPOSTA (NÃO APLICADA) — missão sistema-conteudo-14-11, bloco 5.5 ("Quadro Sim/Não" no ecrã
-- "Caixa de guardados" do painel admin, rota /admin/caixa-guardados).
-- A tranca da sessão do PC recusou apply_migration e qualquer DDL ("migration é publicar:
-- publica o Claude.ai"). Quem aplica: o Claude.ai, pelo MCP (apply_migration), tudo de uma vez.
-- Depois de aplicar, renomear para <versão>_quadro_sim_nao_painel_admin.sql com a versão registada.
--
-- O despacho NÃO muda: o painel grava origem 'evento' (aceite pelo despacho_origem_check) e põe
-- "(painel admin)" no fim do título e da tarefa (ordem do maestro, 14/11).
--
-- Lido a 14/11/2026 (pg_constraint / pg_policies), o que hoje a base recusa ao Quadro:
--   1. caixa_guardados_estado_check não tem 'aprovado' → o Sim da caixa falha (23514).
--   2. radar_videos só tem policy SELECT para o admin → o painel não consegue mudar o veredito.
--      Em vez de abrir UPDATE à tabela, uma função com guarda faz as duas coisas de uma vez
--      (cria a tarefa no despacho E marca o vídeo), como o opcoes_danilo.py faz na VPS.
--
-- Só alarga uma lista de valores e cria uma função de admin. Nenhuma linha existente muda.

-- 1) estado 'aprovado' na caixa de guardados (Sim no Quadro: estado 'aprovado', decisao 'sim (painel)')
alter table public.caixa_guardados drop constraint if exists caixa_guardados_estado_check;
alter table public.caixa_guardados add constraint caixa_guardados_estado_check
  check (estado = any (array['guardado'::text, 'analisado'::text, 'em-curso'::text, 'feito'::text,
                             'rejeitado'::text, 'precisa-danilo'::text, 'aprovado'::text]));

-- 2) Sim/Não numa opção do radar (radar_videos com veredito 'pendente')
--    Sim → tarefa no despacho (origem 'evento', para 'emerson') + veredito 'despachado' (o mesmo que a VPS usa).
--    Não → veredito 'rejeitado-danilo'.
create or replace function public.admin_quadro_radar_decidir(p_youtube_id text, p_sim boolean)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v public.radar_videos%rowtype;
  v_despacho bigint;
  v_veredito text;
  v_tema text;
begin
  -- Só o admin com sessão na app. Nada de current_user aqui: dentro de SECURITY DEFINER é sempre o dono.
  if not public.is_admin() then
    raise exception 'so_admin' using errcode = '42501';
  end if;

  select * into v from public.radar_videos where youtube_id = p_youtube_id for update;
  if not found then
    raise exception 'video_nao_encontrado';
  end if;
  if v.veredito is distinct from 'pendente' then
    raise exception 'ja_decidido: %', coalesce(v.veredito, '(vazio)');
  end if;

  v_tema := coalesce(nullif(trim(v.tema), ''), v.titulo, p_youtube_id);

  if p_sim then
    insert into public.despacho (origem, para, tipo, titulo, tarefa, prioridade, estado)
    values ('evento', 'emerson', 'tarefa',
            left('radar: ' || v_tema, 184) || ' (painel admin)',
            'Opção do radar aprovada pelo Danilo no Quadro Sim/Não.' || E'\n'
              || 'Vídeo: ' || coalesce(v.titulo, '') || E'\n'
              || 'Link: ' || coalesce(v.link, '') || E'\n'
              || 'Resumo: ' || coalesce(v.transcricao_resumida, '') || E'\n'
              || 'Ideias: ' || coalesce(v.ideias::text, '') || E'\n'
              || '(painel admin)',
            90, 'aberta')
    returning id into v_despacho;
    v_veredito := 'despachado';
  else
    v_veredito := 'rejeitado-danilo';
  end if;

  update public.radar_videos
     set veredito = v_veredito,
         revisto_em = now(),
         atualizado_em = now(),
         acao = '[painel ' || to_char(now() at time zone 'Europe/Lisbon', 'DD/MM HH24:MI')
                || case when p_sim then ': sim, despacho #' || v_despacho else ': não' end
                || '] ' || coalesce(v.acao, '')
   where youtube_id = p_youtube_id;

  perform public.log_admin_action(
    case when p_sim then 'quadro_radar_sim' else 'quadro_radar_nao' end,
    'radar_video', p_youtube_id,
    jsonb_build_object('veredito', v_veredito, 'despacho_id', v_despacho));

  return jsonb_build_object('youtube_id', p_youtube_id, 'veredito', v_veredito, 'despacho_id', v_despacho);
end;
$$;

revoke all on function public.admin_quadro_radar_decidir(text, boolean) from public;
revoke all on function public.admin_quadro_radar_decidir(text, boolean) from anon;
grant execute on function public.admin_quadro_radar_decidir(text, boolean) to authenticated, service_role;

-- Prova depois de aplicar (só leitura):
--   select pg_get_constraintdef(oid) from pg_constraint where conname = 'caixa_guardados_estado_check';
--   select has_function_privilege('anon', 'public.admin_quadro_radar_decidir(text, boolean)', 'EXECUTE');  -- false
--   select has_function_privilege('authenticated', 'public.admin_quadro_radar_decidir(text, boolean)', 'EXECUTE');  -- true
--   select prosecdef, proconfig from pg_proc where proname = 'admin_quadro_radar_decidir';  -- t, {search_path=public}
-- Guarda: chamada por um autenticado que não é admin tem de dar 'so_admin' (prova em transação
-- que acaba em erro, sem deixar linhas).
