-- Trava no servidor: prestador NAO aprovado nao fica online (ordem do Danilo 01/11/2026 19:56, ponto 12:
-- "Eles nao podem ficar online sem estar aprovado").
--
-- Antes: a app escrevia drivers.is_online=true por UPDATE direto (DriverStore.updateDriverOnlineStatus) e
-- nada no servidor conferia approval_status; drivers.is_online ate nasce TRUE por defeito. O despacho ja so
-- chama aprovados (dispatch_candidatos_entrega), mas o candidato via-se "online" e aparecia online no painel.
--
-- Agora (drivers e service_providers, as duas tabelas com is_online; cleaners/washers/casa_profissionais nao
-- tem is_online e as ofertas ja exigem approval_status='approved'):
--   • INSERT ou UPDATE com is_online=true e conta nao aprovada / banida / apagada → is_online fica false.
--   • Tentativa EXPLICITA de ligar (UPDATE OF is_online, false → true) sem aprovacao → erro claro para a app:
--       CONTA_NAO_APROVADA / CONTA_BLOQUEADA (padrao dos erros TVDE_BLOQUEADO / DOCUMENTO_EXPIRADO).
--   • RPC prestador_pode_ficar_online() para a app perguntar ANTES de ligar o botao (ok, codigo, mensagem).
--   • Quem estava online sem aprovacao fica offline agora (com backup bkp_drivers_online_20261101).

create or replace function public.fn_prestador_online_so_aprovado()
returns trigger language plpgsql security definer set search_path to 'public' as $f$
declare
  v_aprovado boolean := coalesce(NEW.approval_status, '') = 'approved';
  v_bloqueado boolean := false;
  v_apagado boolean := false;
  v_tentativa boolean;
  v_codigo text;
  v_msg text;
begin
  if not coalesce(NEW.is_online, false) then return NEW; end if;

  if TG_TABLE_NAME = 'drivers' then
    v_bloqueado := coalesce((to_jsonb(NEW) ->> 'is_banned')::boolean, false);
    v_apagado := (to_jsonb(NEW) ->> 'deleted_at') is not null;
  elsif TG_TABLE_NAME = 'service_providers' then
    v_bloqueado := not coalesce((to_jsonb(NEW) ->> 'is_active_admin')::boolean, true);
  end if;

  if v_aprovado and not v_bloqueado and not v_apagado then return NEW; end if;

  -- Tentativa explicita de ligar o botao (so o is_online mudou, de false para true).
  v_tentativa := TG_OP = 'UPDATE'
    and not coalesce(OLD.is_online, false)
    and NEW.approval_status is not distinct from OLD.approval_status
    and (TG_TABLE_NAME <> 'drivers' or (to_jsonb(NEW) ->> 'is_banned') is not distinct from (to_jsonb(OLD) ->> 'is_banned'))
    and (TG_TABLE_NAME <> 'service_providers' or (to_jsonb(NEW) ->> 'is_active_admin') is not distinct from (to_jsonb(OLD) ->> 'is_active_admin'));

  if v_tentativa then
    if v_bloqueado then
      v_codigo := 'CONTA_BLOQUEADA';
      v_msg := 'A tua conta está bloqueada. Fala com o suporte da Bora.';
    elsif v_apagado then
      v_codigo := 'CONTA_APAGADA';
      v_msg := 'Esta conta já não está ativa.';
    elsif coalesce(NEW.approval_status, '') = 'rejected' then
      v_codigo := 'CONTA_RECUSADA';
      v_msg := 'A tua candidatura não foi aprovada. Fala com o suporte da Bora.';
    else
      v_codigo := 'CONTA_NAO_APROVADA';
      v_msg := 'A tua conta ainda não está aprovada. Quando for aprovada recebes um aviso e podes ficar online.';
    end if;
    begin
      insert into public.e2e_log (fluxo, passo, estado, detalhe, device)
      values ('online-so-aprovado', 'recusado', 'ok',
              TG_TABLE_NAME || ' u=' || coalesce(left(NEW.user_id::text, 8), '?') || ' ' || v_codigo, 'servidor');
    exception when others then null;
    end;
    raise exception '%: %', v_codigo, v_msg
      using hint = 'Envia os documentos em falta em "Falta enviar" e aguarda a aprovação.', errcode = 'P0001';
  end if;

  -- Caso contrario (INSERT, mudanca de estado, ou ja estava "online" sem direito): fica offline, sem erro.
  NEW.is_online := false;
  return NEW;
end
$f$;
revoke all on function public.fn_prestador_online_so_aprovado() from public, anon, authenticated;

create or replace trigger trg_online_so_aprovado
  before insert or update of is_online, approval_status, is_banned, deleted_at on public.drivers
  for each row execute function public.fn_prestador_online_so_aprovado();

create or replace trigger trg_online_so_aprovado
  before insert or update of is_online, approval_status, is_active_admin on public.service_providers
  for each row execute function public.fn_prestador_online_so_aprovado();

-- ── RPC para a app perguntar antes de ligar o botao ───────────────────────────────
create or replace function public.prestador_pode_ficar_online()
returns jsonb language plpgsql security definer set search_path to 'public' as $f$
declare
  v_uid uuid := auth.uid();
  d record;
  v_tvde jsonb;
begin
  if v_uid is null then raise exception 'sem_sessao' using errcode = '42501'; end if;
  select approval_status, is_banned, deleted_at, vehicle_type into d
    from public.drivers where user_id = v_uid or id = v_uid
   order by (user_id = v_uid) desc, created_at desc limit 1;
  if not found then
    return jsonb_build_object('ok', false, 'codigo', 'SEM_CONTA', 'mensagem', 'Não encontrámos a tua conta de prestador.');
  end if;
  if d.deleted_at is not null then
    return jsonb_build_object('ok', false, 'codigo', 'CONTA_APAGADA', 'mensagem', 'Esta conta já não está ativa.');
  end if;
  if coalesce(d.is_banned, false) then
    return jsonb_build_object('ok', false, 'codigo', 'CONTA_BLOQUEADA', 'mensagem', 'A tua conta está bloqueada. Fala com o suporte da Bora.');
  end if;
  if coalesce(d.approval_status, '') = 'rejected' then
    return jsonb_build_object('ok', false, 'codigo', 'CONTA_RECUSADA', 'mensagem', 'A tua candidatura não foi aprovada. Fala com o suporte da Bora.');
  end if;
  if coalesce(d.approval_status, '') <> 'approved' then
    return jsonb_build_object('ok', false, 'codigo', 'CONTA_NAO_APROVADA',
      'mensagem', 'A tua conta ainda não está aprovada. Quando for aprovada recebes um aviso e podes ficar online.',
      'faltas', to_jsonb(public._robo_documentos_faltas(v_uid)));
  end if;
  if d.vehicle_type = 'carro_passageiros' then
    v_tvde := public.tvde_driver_pode_ficar_online();
    if not coalesce((v_tvde ->> 'ok')::boolean, true) then
      return jsonb_build_object('ok', false, 'codigo', 'TVDE_BLOQUEADO',
        'mensagem', 'Não podes ficar online: ' || coalesce((select string_agg(e ->> 'rotulo', '; ') from jsonb_array_elements(v_tvde -> 'motivos') e), ''),
        'motivos', v_tvde -> 'motivos');
    end if;
  end if;
  return jsonb_build_object('ok', true, 'codigo', 'OK', 'mensagem', null);
end
$f$;
revoke all on function public.prestador_pode_ficar_online() from public, anon;
grant execute on function public.prestador_pode_ficar_online() to authenticated;

-- ── Correcao de agora: quem esta online sem aprovacao passa a offline (com backup) ──
create table if not exists public.bkp_drivers_online_20261101 as
  select now() as bkp_em, id, user_id, name, vehicle_type, approval_status, is_banned, deleted_at, is_online, last_heartbeat_at
    from public.drivers
   where is_online = true
     and (coalesce(approval_status, '') <> 'approved' or coalesce(is_banned, false) or deleted_at is not null);
revoke all on table public.bkp_drivers_online_20261101 from public, anon, authenticated;

-- Aplicado em producao a 01/11/2026 20:20 UTC: o backup ficou com 0 linhas (ninguem estava online sem
-- aprovacao nesse momento), por isso nao houve UPDATE a fazer. Se um dia for preciso repetir:
--   update public.drivers set is_online = false where id in (select id from public.bkp_drivers_online_20261101);
--   update public.driver_locations dl set is_online = false from public.bkp_drivers_online_20261101 b
--    where dl.is_online and (dl.driver_id = b.id or dl.driver_id = b.user_id);
