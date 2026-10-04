-- 2026-10-04 — Pacote ida-e-volta PAGO sem corrida de ida: reparo no servidor + rede de segurança.
--
-- Cicatriz (04/10/2026, cliente Priscila, Safari do iPhone): pagou 9,60 EUR do pacote por
-- cartão (vale 77d33304, pi_3UMqwGGlT3R2jCYp1MOTHCM1) e a ida nunca nasceu. Na web o cartão
-- sai da página; a app criava a ida DEPOIS do pagamento, na página que já tinha morrido.
-- O vale ficou com outbound_ride_id NULL, nenhum motorista foi chamado, nenhum aviso saiu.
--
-- O que muda aqui (a app passa a criar a ida ANTES de abrir o cartão — ver
-- lib/screens/client/tvde/tvde_request_ride_screen.dart):
--   1. tvde_create_roundtrip_credit: um vale que já existe mas está SEM ida deixa de ser beco
--      sem saída — a mesma função liga-lhe a ida pendente (dada pela app ou achada sozinha).
--      O caminho de vale novo fica igual, byte a byte na lógica.
--   2. Índice único por payment_intent_id: pagar/voltar duas vezes nunca dá dois vales.
--   3. tvde_roundtrip_sweep_orfaos + cron de 1 min: vale pago há mais de 2 min sem ida ->
--      liga a ida pendente se houver; senão avisa já (Telegram + push admin). Rasto no e2e_log.
--   4. Painel: admin_tvde_pagos_sem_corrida (lista) e admin_tvde_roundtrip_reparar (botão).
--
-- Reverter: a definição anterior da função está em bkp_fn_tvde_roundtrip_20261004;
--   select cron.unschedule('tvde-roundtrip-orfaos');

create table if not exists public.bkp_fn_tvde_roundtrip_20261004 (
  guardado_em timestamptz not null default now(),
  proname text not null,
  definicao text not null
);
alter table public.bkp_fn_tvde_roundtrip_20261004 enable row level security;

insert into public.bkp_fn_tvde_roundtrip_20261004 (proname, definicao)
select 'tvde_create_roundtrip_credit', pg_get_functiondef('public.tvde_create_roundtrip_credit(uuid,uuid,integer,text)'::regprocedure)
where not exists (select 1 from public.bkp_fn_tvde_roundtrip_20261004 where proname = 'tvde_create_roundtrip_credit');

alter table public.tvde_roundtrip_credits
  add column if not exists orphan_alert_at timestamptz;

create unique index if not exists tvde_roundtrip_credits_pi_unico
  on public.tvde_roundtrip_credits (payment_intent_id)
  where payment_intent_id is not null;

CREATE OR REPLACE FUNCTION public.tvde_create_roundtrip_credit(p_client_id uuid, p_outbound_ride_id uuid, p_paid_cents integer, p_payment_intent_id text)
 RETURNS tvde_roundtrip_credits
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_hours INT;
  v_credit public.tvde_roundtrip_credits;
  v_ride_id UUID := p_outbound_ride_id;
  v_auto BOOLEAN := false;
  v_reparo BOOLEAN := false;
  v_client UUID := p_client_id;
BEGIN
  v_hours := COALESCE((public.get_setting('tvde_roundtrip_validity_hours') #>> '{}')::int, 6);

  SELECT * INTO v_credit FROM public.tvde_roundtrip_credits
    WHERE payment_intent_id = p_payment_intent_id LIMIT 1
    FOR UPDATE;
  IF FOUND THEN
    -- 2026-10-04 (caso Priscila): o vale existe mas ficou SEM ida. Antes devolvia-se
    -- logo e a ida nunca mais se ligava. Agora repara-se aqui, e só aqui. Vale com
    -- ida, usado, anulado, expirado, marcado ou com volta já pedida fica como está.
    IF v_credit.outbound_ride_id IS NOT NULL
       OR v_credit.status <> 'ativo'
       OR v_credit.return_ride_id IS NOT NULL
       OR v_credit.scheduled_return_ride_id IS NOT NULL
       OR v_credit.outbound_scheduled_at IS NOT NULL
       OR now() > v_credit.expires_at THEN
      RETURN v_credit;
    END IF;
    v_reparo := true;
    v_client := v_credit.client_id;
    -- O id que a app manda só vale se for mesmo uma ida pendente deste cliente.
    IF v_ride_id IS NOT NULL AND NOT EXISTS (
         SELECT 1 FROM public.tvde_rides r
          WHERE r.id = v_ride_id
            AND r.client_id = v_client
            AND r.status = 'solicitada'
            AND r.roundtrip_credit_id IS NULL
            AND r.driver_id IS NULL
            AND COALESCE(r.is_return_leg, false) = false
            AND COALESCE(r.payment_status,'') <> 'succeeded'
            AND COALESCE(r.payment_method,'cash') IN ('card','mbway')) THEN
      v_ride_id := NULL;
    END IF;
  END IF;

  -- NOVO: sem id vindo do app, procurar a ida pendente deste cliente.
  IF v_ride_id IS NULL THEN
    SELECT r.id INTO v_ride_id
      FROM public.tvde_rides r
     WHERE r.client_id = v_client
       AND r.status = 'solicitada'
       AND r.roundtrip_credit_id IS NULL
       AND r.driver_id IS NULL
       AND COALESCE(r.payment_status,'') <> 'succeeded'
       AND COALESCE(r.payment_method,'cash') IN ('card','mbway')
       AND r.created_at > now() - interval '45 minutes'
     ORDER BY r.created_at DESC
     LIMIT 1;
    v_auto := v_ride_id IS NOT NULL;
  END IF;

  IF v_reparo THEN
    IF v_ride_id IS NULL THEN
      RETURN v_credit;  -- continua sem ida; a rede de segurança avisa
    END IF;
    UPDATE public.tvde_roundtrip_credits
       SET outbound_ride_id = v_ride_id
     WHERE id = v_credit.id
    RETURNING * INTO v_credit;
  ELSE
    BEGIN
      INSERT INTO public.tvde_roundtrip_credits
        (client_id, outbound_ride_id, paid_cents, payment_intent_id, expires_at)
      VALUES
        (p_client_id, v_ride_id, p_paid_cents, p_payment_intent_id, now() + make_interval(hours => v_hours))
      RETURNING * INTO v_credit;
    EXCEPTION WHEN unique_violation THEN
      -- webhook e app chegaram ao mesmo tempo: fica o vale que já nasceu.
      SELECT * INTO v_credit FROM public.tvde_roundtrip_credits
        WHERE payment_intent_id = p_payment_intent_id LIMIT 1;
      RETURN v_credit;
    END;
  END IF;

  IF v_ride_id IS NOT NULL THEN
    -- `payment_status` entra aqui. O pacote esta pago, logo esta perna esta
    -- paga — e e isto que dispara o despacho via tr_tvde_dispatch_on_paid.
    UPDATE public.tvde_rides r
       SET roundtrip_credit_id = v_credit.id,
           payment_status = 'succeeded',
           -- 2026-09-21: ganho da IDA reescrito para a regra do pacote, para a
           -- oferta mostrar ao motorista o mesmo que tvde_finish_ride lhe paga.
           driver_earn_cents = COALESCE((public.get_setting('tvde_roundtrip_outbound_driver_cents') #>> '{}')::int,
                                        (public.get_setting('tvde_driver_base_cents') #>> '{}')::int)
             + GREATEST(0, CEIL(COALESCE(r.est_distance_km, 0)
                 - (public.get_setting('tvde_base_distance_km') #>> '{}')::int))::int
               * (public.get_setting('tvde_driver_per_km_cents') #>> '{}')::int,
           updated_at = now()
     WHERE r.id = v_ride_id;

    IF v_auto OR v_reparo THEN
      INSERT INTO public.tvde_ride_events (ride_id, status, actor, meta)
      VALUES (v_ride_id, 'solicitada', 'system',
        jsonb_build_object('vale_ligado_automaticamente', v_auto,
                           'vale_orfao_reparado', v_reparo,
                           'motivo', CASE WHEN v_reparo THEN 'vale pago estava sem ida'
                                          ELSE 'app nao enviou outbound_ride_id' END,
                           'credit_id', v_credit.id,
                           'payment_intent_id', p_payment_intent_id));
    END IF;
  END IF;

  RETURN v_credit;
END; $function$;

-- Rede de segurança (pg_cron, 1 min): vale pago há mais de 2 min sem corrida de ida.
create or replace function public.tvde_roundtrip_sweep_orfaos()
 returns integer
 language plpgsql
 security definer
 set search_path to 'public'
as $function$
declare
  c record;
  v_out uuid;
  v_n integer := 0;
  v_nome text;
  v_tel text;
  v_rota text;
  v_resumo text;
begin
  for c in
    select k.* from public.tvde_roundtrip_credits k
     where k.status = 'ativo'
       and k.payment_intent_id is not null
       and k.outbound_ride_id is null
       and k.return_ride_id is null
       and k.scheduled_return_ride_id is null
       and k.outbound_scheduled_at is null
       and k.orphan_alert_at is null
       and k.created_at < now() - interval '2 minutes'
       and k.created_at > now() - interval '24 hours'
     order by k.created_at
     limit 20
  loop
    v_out := null;
    begin
      select (public.tvde_create_roundtrip_credit(c.client_id, null, c.paid_cents, c.payment_intent_id)).outbound_ride_id
        into v_out;
    exception when others then
      raise notice 'tvde_roundtrip_sweep_orfaos: reparo falhou em % (%)', c.id, sqlerrm;
    end;

    if v_out is not null then
      insert into public.e2e_log (fluxo, passo, estado, detalhe, device, run_id)
      values ('tvde-pago-sem-corrida', 'vale-' || left(c.id::text, 8), 'corrigido',
              'vale ' || c.id || ' pago (' || c.payment_intent_id || ') estava sem ida; ligado a corrida '
                || v_out || ' e despacho arrancado', 'pg_cron', 'rede-seguranca-tvde');
      v_n := v_n + 1;
      continue;
    end if;

    -- Sem ida pendente para ligar: o Danilo tem de saber JÁ.
    update public.tvde_roundtrip_credits set orphan_alert_at = now() where id = c.id;

    begin
      select u.name, u.phone into v_nome, v_tel from public.users u where u.id = c.client_id;
    exception when others then v_nome := null; v_tel := null;
    end;
    select coalesce(r.origin_label, '?') || ' -> ' || coalesce(r.dest_label, '?')
           || ' (' || r.status || coalesce(', ' || r.cancel_reason, '') || ')'
      into v_rota
      from public.tvde_rides r
     where r.client_id = c.client_id
       and r.created_at > c.created_at - interval '60 minutes'
     order by r.created_at desc limit 1;

    v_resumo := '🚨 PAGOU E NAO TEM CORRIDA · '
      || coalesce(nullif(v_nome, ''), 'cliente')
      || coalesce(' (' || nullif(v_tel, '') || ')', '')
      || E'\n' || 'Pacote ida-e-volta ' || to_char(coalesce(c.paid_cents, 0) / 100.0, 'FM999990.00') || ' EUR pago ha '
      || greatest(1, round(extract(epoch from (now() - c.created_at)) / 60))::int || ' min, sem corrida de ida.'
      || coalesce(' Ultima rota: ' || v_rota || '.', ' Sem rota registada.')
      || ' Liga ao cliente ou abre Pagos sem corrida no painel. #' || left(c.id::text, 8);

    insert into public.e2e_log (fluxo, passo, estado, detalhe, device, run_id)
    values ('tvde-pago-sem-corrida', 'vale-' || left(c.id::text, 8), 'aviso',
            'vale ' || c.id || ' pago (' || c.payment_intent_id || ') sem ida e sem corrida pendente para ligar; admin avisado',
            'pg_cron', 'rede-seguranca-tvde');

    if not public.is_demo_user(c.client_id) then
      begin
        perform public.notify_admin_urgent_push(
          'tvde_pago_sem_corrida', v_resumo, 'tvde_roundtrip_credit', c.id::text,
          jsonb_build_object('credit_id', c.id, 'client_id', c.client_id, 'client_name', v_nome,
            'client_phone', v_tel, 'paid_cents', c.paid_cents,
            'payment_intent_id', c.payment_intent_id, 'ultima_rota', v_rota),
          '/admin/tvde/pagos-sem-corrida');
      exception when others then
        raise notice 'tvde_roundtrip_sweep_orfaos: aviso falhou em % (%)', c.id, sqlerrm;
      end;
    end if;
    v_n := v_n + 1;
  end loop;
  return v_n;
end;
$function$;

revoke all on function public.tvde_roundtrip_sweep_orfaos() from public, anon, authenticated;

-- Painel admin: "Pagos sem corrida criada".
create or replace function public.admin_tvde_pagos_sem_corrida(p_dias integer default 30)
 returns table(credit_id uuid, created_at timestamptz, status text, paid_cents integer,
               payment_intent_id text, client_id uuid, cliente_nome text, cliente_contacto text,
               return_ride_id uuid, alertado_em timestamptz, ida_pendente_id uuid, ultima_rota text)
 language plpgsql
 stable security definer
 set search_path to 'public'
as $function$
begin
  if not public.is_admin() then raise exception 'apenas admin'; end if;
  return query
  select k.id, k.created_at, k.status, k.paid_cents, k.payment_intent_id, k.client_id,
         u.name::text, coalesce(u.phone, u.email)::text, k.return_ride_id, k.orphan_alert_at,
         (select r.id from public.tvde_rides r
           where r.client_id = k.client_id and r.status = 'solicitada'
             and r.roundtrip_credit_id is null and r.driver_id is null
             and coalesce(r.payment_status,'') <> 'succeeded'
             and coalesce(r.payment_method,'cash') in ('card','mbway')
             and r.created_at > now() - interval '45 minutes'
           order by r.created_at desc limit 1),
         (select coalesce(r.origin_label, '?') || ' -> ' || coalesce(r.dest_label, '?')
                 || ' (' || r.status || coalesce(', ' || r.cancel_reason, '') || ')'
            from public.tvde_rides r
           where r.client_id = k.client_id
             and r.created_at > k.created_at - interval '60 minutes'
             and r.created_at < k.created_at + interval '60 minutes'
           order by r.created_at desc limit 1)
    from public.tvde_roundtrip_credits k
    left join public.users u on u.id = k.client_id
   where k.payment_intent_id is not null
     and k.outbound_ride_id is null
     and k.outbound_scheduled_at is null
     and k.created_at > now() - make_interval(days => coalesce(p_dias, 30))
   order by k.created_at desc;
end;
$function$;

revoke all on function public.admin_tvde_pagos_sem_corrida(integer) from public, anon;
grant execute on function public.admin_tvde_pagos_sem_corrida(integer) to authenticated;

-- Botão "Ligar à ida pendente": o mesmo reparo, pedido pelo admin.
create or replace function public.admin_tvde_roundtrip_reparar(p_credit_id uuid)
 returns jsonb
 language plpgsql
 security definer
 set search_path to 'public'
as $function$
declare
  k public.tvde_roundtrip_credits;
  v public.tvde_roundtrip_credits;
begin
  if not public.is_admin() then raise exception 'apenas admin'; end if;
  select * into k from public.tvde_roundtrip_credits where id = p_credit_id;
  if not found then return jsonb_build_object('ok', false, 'motivo', 'vale_nao_encontrado'); end if;
  if k.outbound_ride_id is not null then
    return jsonb_build_object('ok', true, 'outbound_ride_id', k.outbound_ride_id, 'ja_estava', true);
  end if;
  if k.payment_intent_id is null then
    return jsonb_build_object('ok', false, 'motivo', 'vale_sem_pagamento_online');
  end if;
  v := public.tvde_create_roundtrip_credit(k.client_id, null, k.paid_cents, k.payment_intent_id);
  if v.outbound_ride_id is null then
    return jsonb_build_object('ok', false, 'motivo',
      case when v.status <> 'ativo' then 'vale_' || v.status else 'sem_ida_pendente' end);
  end if;
  return jsonb_build_object('ok', true, 'outbound_ride_id', v.outbound_ride_id);
end;
$function$;

revoke all on function public.admin_tvde_roundtrip_reparar(uuid) from public, anon;
grant execute on function public.admin_tvde_roundtrip_reparar(uuid) to authenticated;

select cron.unschedule('tvde-roundtrip-orfaos')
 where exists (select 1 from cron.job where jobname = 'tvde-roundtrip-orfaos');
select cron.schedule('tvde-roundtrip-orfaos', '* * * * *',
                     $$select public.tvde_roundtrip_sweep_orfaos();$$);
