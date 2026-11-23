-- missao radar-fila-2026-11-23 (B1): portas com chave para o radar_crescimento.py (PC) tratar a radar_fila.
-- O PC so tem a chave anon + RADAR_VIDEOS_KEY; a radar_fila tem RLS sem politicas, por isso tudo passa
-- por funcoes SECURITY DEFINER que conferem a chave no vault (igual a radar_videos_registar).
-- Escrita pelo Claude Code; a aplicacao em producao e da Claude.ai (a tranca recusa migracoes ao executor).
-- Ate ser aplicada, o script grava o resumo pela radar_videos_registar antiga e guarda origem +
-- transcricao em dados/fila_pendentes.jsonl, que despeja sozinho na primeira corrida depois disto.

alter table public.radar_fila add column if not exists pegado_em timestamptz;

create or replace function public._radar_chave_ok(p_chave text) returns boolean
language plpgsql stable security definer set search_path to 'public','vault' as $$
declare v_ok text;
begin
  select decrypted_secret into v_ok from vault.decrypted_secrets where name = 'radar_videos_key';
  return v_ok is not null and p_chave is not null and p_chave = v_ok;
end $$;
revoke all on function public._radar_chave_ok(text) from public, anon, authenticated;

-- radar_videos_registar passa a gravar origem ('pesquisa'|'historico'|'inicio') e a transcricao completa (ate 60 000)
create or replace function public.radar_videos_registar(p_chave text, p_linha jsonb)
 returns text language plpgsql security definer set search_path to 'public','vault' as $function$
declare v_ok text;
begin
  select decrypted_secret into v_ok from vault.decrypted_secrets where name = 'radar_videos_key';
  if v_ok is null or p_chave is null or p_chave <> v_ok then raise exception 'chave_invalida'; end if;
  insert into public.radar_videos (youtube_id, titulo, canal, visualizacoes, publicado_em, duracao_s, link, lingua, tema, pesquisa, tem_transcricao, transcricao_resumida, ideias, nota_utilidade, motor_resumo, origem, transcricao)
  values (p_linha->>'youtube_id', coalesce(p_linha->>'titulo','(sem título)'), p_linha->>'canal', nullif(p_linha->>'visualizacoes','')::bigint, nullif(p_linha->>'publicado_em','')::date,
          nullif(p_linha->>'duracao_s','')::integer, coalesce(p_linha->>'link', 'https://www.youtube.com/watch?v=' || (p_linha->>'youtube_id')), p_linha->>'lingua', p_linha->>'tema', p_linha->>'pesquisa',
          coalesce((p_linha->>'tem_transcricao')::boolean, false), p_linha->>'transcricao_resumida', p_linha->'ideias', nullif(p_linha->>'nota_utilidade','')::smallint, p_linha->>'motor_resumo',
          case when p_linha->>'origem' in ('historico','inicio','pesquisa') then p_linha->>'origem' else 'pesquisa' end,
          left(nullif(p_linha->>'transcricao',''), 60000))
  on conflict (youtube_id) do update
     set visualizacoes = excluded.visualizacoes, transcricao_resumida = coalesce(excluded.transcricao_resumida, radar_videos.transcricao_resumida),
         ideias = coalesce(excluded.ideias, radar_videos.ideias), nota_utilidade = coalesce(excluded.nota_utilidade, radar_videos.nota_utilidade),
         motor_resumo = coalesce(excluded.motor_resumo, radar_videos.motor_resumo), tema = coalesce(excluded.tema, radar_videos.tema),
         tem_transcricao = excluded.tem_transcricao or radar_videos.tem_transcricao,
         -- o historico/inicio do Danilo vale mais do que uma pesquisa: nunca desce para 'pesquisa'
         origem = case when excluded.origem in ('historico','inicio') then excluded.origem else radar_videos.origem end,
         pesquisa = case when excluded.origem in ('historico','inicio') then excluded.pesquisa else radar_videos.pesquisa end,
         transcricao = coalesce(excluded.transcricao, radar_videos.transcricao),
         atualizado_em = now();
  return p_linha->>'youtube_id';
end $function$;

-- pega um lote da fila (prioridade desc, criado_em) e marca 'a_processar'; os presos ha mais de 3 h voltam a 'novo'
create or replace function public.radar_fila_pegar(p_chave text, p_lote integer default 40)
 returns setof jsonb language plpgsql security definer set search_path to 'public','vault' as $$
begin
  if not public._radar_chave_ok(p_chave) then raise exception 'chave_invalida'; end if;
  update public.radar_fila set estado = 'novo', pegado_em = null
   where estado = 'a_processar' and coalesce(pegado_em, criado_em) < now() - interval '3 hours';
  return query
  with lote as (
    select youtube_id from public.radar_fila where estado = 'novo'
     order by prioridade desc, criado_em limit greatest(1, least(coalesce(p_lote, 40), 200))
     for update skip locked)
  update public.radar_fila f set estado = 'a_processar', pegado_em = now(), erro = null
    from lote where f.youtube_id = lote.youtube_id
  returning jsonb_build_object('youtube_id', f.youtube_id, 'titulo', f.titulo, 'canal', f.canal, 'origem', f.origem,
                               'visto_em', f.visto_em, 'prioridade', f.prioridade);
end $$;

create or replace function public.radar_fila_fechar(p_chave text, p_youtube_id text, p_estado text, p_erro text default null)
 returns text language plpgsql security definer set search_path to 'public','vault' as $$
begin
  if not public._radar_chave_ok(p_chave) then raise exception 'chave_invalida'; end if;
  if p_estado not in ('feito','sem_legenda','erro','ignorado','novo') then raise exception 'estado_invalido: %', p_estado; end if;
  update public.radar_fila set estado = p_estado, erro = left(p_erro, 500), processado_em = now()
   where youtube_id = p_youtube_id;
  return p_estado;
end $$;

-- para uma recolha que nao tenha o MCP do Supabase (ex.: script) meter videos na fila
create or replace function public.radar_fila_meter(p_chave text, p_linhas jsonb)
 returns jsonb language plpgsql security definer set search_path to 'public','vault' as $$
declare v_novos int; v_total int;
begin
  if not public._radar_chave_ok(p_chave) then raise exception 'chave_invalida'; end if;
  v_total := jsonb_array_length(coalesce(p_linhas, '[]'::jsonb));
  with ins as (
    insert into public.radar_fila (youtube_id, titulo, canal, origem, visto_em, prioridade)
    select l->>'youtube_id', l->>'titulo', l->>'canal', l->>'origem', l->>'visto_em',
           case when l->>'origem' = 'historico' then 8 else 5 end
      from jsonb_array_elements(coalesce(p_linhas, '[]'::jsonb)) l
     where (l->>'youtube_id') ~ '^[A-Za-z0-9_-]{11}$' and l->>'origem' in ('historico','inicio')
    on conflict (youtube_id) do nothing
    returning 1)
  select count(*) into v_novos from ins;
  return jsonb_build_object('recebidos', v_total, 'novos', v_novos);
end $$;

revoke all on function public.radar_fila_pegar(text, integer) from public;
revoke all on function public.radar_fila_fechar(text, text, text, text) from public;
revoke all on function public.radar_fila_meter(text, jsonb) from public;
grant execute on function public.radar_fila_pegar(text, integer) to anon, authenticated;
grant execute on function public.radar_fila_fechar(text, text, text, text) to anon, authenticated;
grant execute on function public.radar_fila_meter(text, jsonb) to anon, authenticated;
