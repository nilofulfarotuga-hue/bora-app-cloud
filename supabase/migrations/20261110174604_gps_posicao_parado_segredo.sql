-- Bloco B (GPS do estafeta parado), missão fechar-tudo-2026-11-10 (Claude Code, 10/11/2026).
-- Ordem do Danilo: "GPS, tem que fazer" (10/11 16:43) e "vai" de 09/11.
--
-- O DEFEITO (provado a 10/11 ~17:50 por SELECT): o Valdemir estava online com o batimento de agora e a
-- última posição em driver_locations com 4 h 23 min. Com a app em segundo plano, o serviço de fundo
-- (flutter_foreground_task) bate pelo segredo (driver_heartbeat_segredo), mas a posição de reserva ia
-- pela RPC autenticada driver_update_location com o token de sessão guardado — que dura 1 hora. Depois
-- disso: 401, o serviço larga o token e a posição pára até o estafeta voltar a abrir a app. Por isso a
-- janela de frescura das entregas (dispatch_gps_fresh_seconds_entregas) está em 172800 s desde 04/10.
--
-- O CONSERTO: driver_posicao_segredo — a mesma prova de identidade do batimento (segredo do próprio
-- estafeta, 32+ caracteres, tabela driver_heartbeat_segredos) e a mesma escrita de sempre: chama a RPC
-- oficial driver_update_location em nome do estafeta (mesmas validações de coordenadas e as mesmas
-- tabelas). Não abre caminho novo de escrita. Só aceita estafeta ligado (online).
-- Colunas novas em driver_locations (só informação para o painel e para a tarefa que aperta a janela):
--   fonte          'servico_fundo' quando a posição chegou pelo serviço de fundo;
--   app_build      número da versão da app que a mandou;
--   permissao_gps  'always' / 'whileInUse' / … (o Android só dá posição em fundo com 'always').
-- A janela dispatch_gps_fresh_seconds_entregas NÃO muda aqui (fica 172800 até haver prova; ver
-- docs/propostas/fechar-tudo-2026-11-10/B_apertar_janela_gps.sql).

alter table public.driver_locations add column if not exists fonte text;
alter table public.driver_locations add column if not exists app_build integer;
alter table public.driver_locations add column if not exists permissao_gps text;
alter table public.driver_locations add column if not exists fonte_em timestamptz;

create or replace function public.driver_posicao_segredo(
  p_driver_id text,
  p_segredo text,
  p_latitude numeric,
  p_longitude numeric,
  p_heading numeric default null,
  p_speed_kmh numeric default null,
  p_app_build integer default null,
  p_permissao text default null
)
returns jsonb
language plpgsql
security definer
set search_path to 'public'
as $function$
declare
  v_id     uuid;
  v_uid    uuid;
  v_ok     boolean;
  v_online boolean;
begin
  begin
    v_id := trim(p_driver_id)::uuid;
  exception when others then
    return jsonb_build_object('ok', false, 'error', 'forbidden');
  end;
  if p_segredo is null or length(p_segredo) < 32 then
    return jsonb_build_object('ok', false, 'error', 'forbidden');
  end if;

  select d.user_id, (s.segredo = p_segredo), d.is_online
    into v_uid, v_ok, v_online
    from public.driver_heartbeat_segredos s
    join public.drivers d on d.user_id = s.user_id
   where d.user_id = v_id or d.id = v_id
   limit 1;
  if not coalesce(v_ok, false) or v_uid is null then
    return jsonb_build_object('ok', false, 'error', 'forbidden');
  end if;
  if not coalesce(v_online, false) then
    return jsonb_build_object('ok', false, 'error', 'offline');
  end if;

  -- A RPC oficial lê o estafeta de auth.uid(): a identidade aqui vem do segredo (só nesta transação).
  perform set_config('request.jwt.claim.sub', v_uid::text, true);
  perform public.driver_update_location(p_latitude, p_longitude, p_heading, p_speed_kmh, true);

  update public.driver_locations
     set fonte = 'servico_fundo',
         fonte_em = now(),
         app_build = coalesce(p_app_build, app_build),
         permissao_gps = coalesce(left(p_permissao, 20), permissao_gps)
   where driver_id = v_uid;

  return jsonb_build_object('ok', true, 'em', now());
end;
$function$;

comment on function public.driver_posicao_segredo(text, text, numeric, numeric, numeric, numeric, integer, text) is
  'GPS do estafeta parado (10/11/2026): posição do serviço de fundo com o segredo do batimento; passa por driver_update_location. Aberta a anon porque o serviço de fundo corre sem sessão (o token dura 1 h); só aceita quem tem o segredo e está online.';

-- Nasce fechada; abre-se a anon e authenticated com motivo (serviço de fundo sem sessão, prova por segredo).
revoke all on function public.driver_posicao_segredo(text, text, numeric, numeric, numeric, numeric, integer, text) from public;
grant execute on function public.driver_posicao_segredo(text, text, numeric, numeric, numeric, numeric, integer, text) to anon, authenticated, service_role;
