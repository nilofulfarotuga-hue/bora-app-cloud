-- ============================================================================
-- Missão estafeta-web-2026-09-16 · BLOCO 2 — pedido nunca mais preso num
-- estafeta que não responde (padrão Uber Eats / Glovo, sem inventar).
--
--  1. Estafeta escolhido antes de o pedido estar pronto (preassigned_driver_id,
--     ou o caminho antigo de deixar assigned_driver_id posto em preparing):
--     quando a loja marca pronto, o pedido vai PRIMEIRO a esse estafeta como
--     OFERTA NORMAL (current_driver_offer_id = user_id dele, tempo e som
--     normais). Se estiver desligado / sem sinal / sem notificações, a
--     pré-atribuição limpa-se sozinha e o pedido segue para o dispatch normal,
--     com aviso ao admin (Telegram + push).
--  2. Se não aceitar no tempo da oferta, a rotação normal do
--     bora_dispatch_maintenance (passo 7) limpa a oferta e o motor segue.
--  3. Rede de segurança: nenhum pedido fica em callingDriver com estafeta
--     atribuído sem aceitar mais de dispatch_preassign_release_seconds (180) —
--     o bora_dispatch_maintenance liberta, avisa o admin e chama o motor.
--  4. admin_reassign_order: em pedido ainda não pronto passa a PRÉ-ATRIBUIR
--     (não mexe em assigned_driver_id); em pedido pronto mantém o comportamento
--     de 16/09 e avisa o estafeta pela Edge notify-driver-assigned (bloco 4).
--  5. ops_reassign_order: aceita pré-atribuição a estafeta ligado (antes
--     recusava pedido ainda não pronto).
--  6. admin_release_order_driver / ops_release_order_driver: "Mandar para
--     todos" — tira o estafeta e devolve o pedido ao dispatch, com registo.
--  7. driver_heartbeat(p_platform): grava de onde o estafeta usa a Bora.
--  8. expire_stale_driver_presence: quem fica desligado por falta de sinal
--     recebe "Ficaste desligado. Abre a Bora para voltares a receber pedidos."
--
-- Não mexe em preços, tempo global de oferta, claim nem rotação do motor.
-- Backups das versões anteriores em public.bkp_fn_dispatch_20260916.
-- ============================================================================

-- ---------------------------------------------------------------------------
-- 0. Colunas de plataforma no estafeta (painel: "como usa a Bora")
-- ---------------------------------------------------------------------------
alter table public.drivers
  add column if not exists last_platform    text,
  add column if not exists last_platform_at timestamptz;

comment on column public.drivers.last_platform is
  'Última plataforma vista no heartbeat: android_app, ios_app, web_ios, web_android, web_desktop.';

-- ---------------------------------------------------------------------------
-- 1. Auxiliares internos (só chamáveis por funções SECURITY DEFINER)
-- ---------------------------------------------------------------------------
create or replace function public._service_role_key()
returns text
language sql
stable
security definer
set search_path to 'public', 'vault'
as $$
  select coalesce(
    nullif(current_setting('app.settings.service_role_key', true), ''),
    (select s.decrypted_secret from vault.decrypted_secrets s where s.name = 'service_role_key' limit 1));
$$;
revoke all on function public._service_role_key() from public;
revoke all on function public._service_role_key() from anon;
revoke all on function public._service_role_key() from authenticated;

-- Aviso ao estafeta por push (Edge notify-driver-assigned, data-only, todos os
-- aparelhos dele incluindo web). Best-effort: nunca rebenta a transação.
create or replace function public._notify_driver_assigned_http(
  p_driver text, p_order_id text, p_type text, p_title text, p_body text)
returns void
language plpgsql
security definer
set search_path to 'public'
as $$
begin
  perform net.http_post(
    url     := 'https://ojykpzwqrtusfeakzrna.supabase.co/functions/v1/notify-driver-assigned',
    headers := jsonb_build_object(
      'Content-Type', 'application/json',
      'Authorization', 'Bearer ' || coalesce(public._service_role_key(), '')),
    body    := jsonb_build_object(
      'driverId', p_driver, 'orderId', p_order_id, 'type', p_type,
      'title', p_title, 'body', p_body));
exception when others then
  raise warning '_notify_driver_assigned_http(%,%): %', p_type, p_order_id, sqlerrm;
end;
$$;
revoke all on function public._notify_driver_assigned_http(text, text, text, text, text) from public;
revoke all on function public._notify_driver_assigned_http(text, text, text, text, text) from anon;
revoke all on function public._notify_driver_assigned_http(text, text, text, text, text) from authenticated;

-- Oferta normal ao estafeta (mesmo pedido que fn_notify_driver_on_offer faz;
-- aqui chamado explicitamente porque um trigger BEFORE que muda
-- current_driver_offer_id não faz disparar o AFTER ... OF current_driver_offer_id).
create or replace function public._notify_driver_offer_http(
  p_order_id text, p_driver text, p_vendor text, p_total numeric)
returns void
language plpgsql
security definer
set search_path to 'public'
as $$
begin
  perform net.http_post(
    url     := 'https://ojykpzwqrtusfeakzrna.supabase.co/functions/v1/notify-driver',
    headers := jsonb_build_object(
      'Content-Type', 'application/json',
      'Authorization', 'Bearer ' || public._dispatch_jwt()),
    body    := jsonb_build_object(
      'driverId', p_driver, 'orderId', p_order_id,
      'vendorName', coalesce(p_vendor, 'Pedido'), 'total', coalesce(p_total, 0)));
exception when others then
  raise warning '_notify_driver_offer_http(%): %', p_order_id, sqlerrm;
end;
$$;
revoke all on function public._notify_driver_offer_http(text, text, text, numeric) from public;
revoke all on function public._notify_driver_offer_http(text, text, text, numeric) from anon;
revoke all on function public._notify_driver_offer_http(text, text, text, numeric) from authenticated;

-- Aviso ao admin quando uma pré-atribuição é libertada (Telegram + push admin
-- pelo notify_admin_urgent_push que já existe) + registo em admin_audit_log.
create or replace function public._preassign_released_alert(
  p_order_id text, p_estafeta text, p_motivo text, p_contexto text)
returns void
language plpgsql
security definer
set search_path to 'public'
as $$
declare
  v_ref text := upper(substr(replace(p_order_id, '-', ''), 1, 6));
  v_msg text;
begin
  v_msg := 'Bora: pedido ' || v_ref || ' estava reservado para ' || coalesce(p_estafeta, '?')
        || ' mas foi libertado (' || p_motivo || '; ' || p_contexto || '). Segue para todos os estafetas.';
  begin
    insert into public.admin_audit_log (action, entity_type, entity_id_text, admin_email, details)
    values ('preassign_released', 'order', p_order_id, 'sistema',
            jsonb_build_object('estafeta', p_estafeta, 'motivo', p_motivo, 'contexto', p_contexto));
  exception when others then
    raise warning '_preassign_released_alert audit: %', sqlerrm;
  end;
  begin
    perform public.notify_admin_urgent_push(
      'preassign_released', v_msg, 'order', p_order_id,
      jsonb_build_object('estafeta', p_estafeta, 'motivo', p_motivo, 'contexto', p_contexto),
      '/admin/orders/' || p_order_id);
  exception when others then
    raise warning '_preassign_released_alert push: %', sqlerrm;
  end;
  begin
    perform public._telegram_admin(v_msg);
  exception when others then
    raise warning '_preassign_released_alert telegram: %', sqlerrm;
  end;
end;
$$;
revoke all on function public._preassign_released_alert(text, text, text, text) from public;
revoke all on function public._preassign_released_alert(text, text, text, text) from anon;
revoke all on function public._preassign_released_alert(text, text, text, text) from authenticated;

-- Estafeta "vai receber"? (ligado, sinal < 90 s, notificações registadas)
create or replace function public._driver_reachability(p_driver text)
returns table (
  driver_id uuid, user_id uuid, name text, approval_status text, is_banned boolean,
  online_agora boolean, tem_notificacoes boolean, last_heartbeat_at timestamptz, last_platform text)
language sql
stable
security definer
set search_path to 'public'
as $$
  select d.id, d.user_id, d.name, d.approval_status, coalesce(d.is_banned, false),
         coalesce(d.is_online, false)
           and d.last_heartbeat_at is not null
           and d.last_heartbeat_at > now() - interval '90 seconds',
         d.fcm_token is not null
           or exists (select 1 from public.driver_push_tokens t
                       where t.user_id::text = coalesce(d.user_id, d.id)::text and t.active)
           or exists (select 1 from public.provider_push_tokens t
                       where t.user_id::text = coalesce(d.user_id, d.id)::text
                         and t.role = 'driver' and t.active),
         d.last_heartbeat_at, d.last_platform
  from public.drivers d
  where d.user_id::text = p_driver or d.id::text = p_driver
  limit 1;
$$;
revoke all on function public._driver_reachability(text) from public;
revoke all on function public._driver_reachability(text) from anon;

-- ---------------------------------------------------------------------------
-- 2. Pré-atribuição vira oferta normal quando o pedido fica pronto
-- ---------------------------------------------------------------------------
create or replace function public._preassign_to_offer()
returns trigger
language plpgsql
security definer
set search_path to 'public'
as $$
declare
  v_d       record;
  v_uid     text;
  v_timeout int;
  v_motivo  text;
begin
  perform set_config('bora.caminho_oficial', 'preassign_to_offer', true);

  -- Caminho antigo: estafeta deixado em assigned_driver_id antes de pronto.
  -- Passa a pré-atribuição — senão o motor nunca chamava ninguém (16/09).
  if new.assigned_driver_id is not null then
    new.preassigned_driver_id := coalesce(new.preassigned_driver_id, new.assigned_driver_id);
    new.preassigned_at        := coalesce(new.preassigned_at, now());
    new.preassigned_by        := coalesce(new.preassigned_by, 'assigned_driver_id_antes_de_pronto');
    new.assigned_driver_id    := null;
    new.driver_id             := null;
  end if;

  if new.preassigned_driver_id is null or coalesce(new.service_type, '') = 'takeaway' then
    return new;
  end if;

  select * into v_d from public._driver_reachability(new.preassigned_driver_id);
  v_uid := coalesce(v_d.user_id, v_d.driver_id)::text;

  if v_d.driver_id is null then
    v_motivo := 'estafeta não encontrado';
  elsif v_d.approval_status <> 'approved' or v_d.is_banned then
    v_motivo := 'estafeta não aprovado ou banido';
  elsif not v_d.online_agora then
    v_motivo := 'desligado ou sem sinal há mais de 90 s';
  elsif not v_d.tem_notificacoes then
    v_motivo := 'sem notificações registadas';
  end if;

  if v_motivo is not null then
    perform public._preassign_released_alert(
      new.id::text, coalesce(v_d.name, new.preassigned_driver_id), v_motivo, 'ao ficar pronto');
    new.preassigned_driver_id := null;
    return new;  -- segue para o dispatch normal (trg_dispatch_on_calling_driver)
  end if;

  select coalesce((value #>> '{}')::int, 60) into v_timeout
    from public.platform_settings where key = 'dispatch_offer_timeout_seconds';
  v_timeout := coalesce(v_timeout, 60);

  new.current_driver_offer_id := v_uid;
  new.driver_offer_expires_at := now() + make_interval(secs => v_timeout);
  new.dispatch_last_tick_at   := now();

  perform public._notify_driver_offer_http(new.id::text, v_uid, new.vendor_name, new.price);
  raise log '[preassign_to_offer] order=% oferta primeiro a % (expira %)', new.id, v_uid, new.driver_offer_expires_at;
  return new;
end;
$$;

create or replace trigger trg_zy_preassign_to_offer
  before update of status on public.orders
  for each row
  when (new.status = 'callingDriver' and old.status is distinct from 'callingDriver')
  execute function public._preassign_to_offer();

-- ---------------------------------------------------------------------------
-- 3. Trigger de arranque do motor: não chama o motor por cima de uma oferta
--    viva (a oferta ao escolhido tem de correr o seu tempo); a rotação do
--    maintenance trata do resto. O resto é igual à versão anterior.
-- ---------------------------------------------------------------------------
create or replace function public.fn_dispatch_on_calling_driver()
returns trigger
language plpgsql
security definer
set search_path to 'public'
as $$
declare
  v_jwt text;
begin
  if new.status = 'callingDriver'
    and (old.status is distinct from 'callingDriver')
    and new.assigned_driver_id is null
    and (new.current_driver_offer_id is null
         or new.driver_offer_expires_at is null
         or new.driver_offer_expires_at <= now())
  then
    v_jwt := public._dispatch_jwt();
    perform net.http_post(
      url := 'https://ojykpzwqrtusfeakzrna.supabase.co/functions/v1/dispatch-engine',
      headers := jsonb_build_object(
        'Content-Type', 'application/json',
        'Authorization', 'Bearer ' || v_jwt
      ),
      body := jsonb_build_object('orderId', new.id::text)
    );
  end if;
  return new;
end;
$$;

-- ---------------------------------------------------------------------------
-- 4. Rede de segurança no bora_dispatch_maintenance (passo 0, novo).
--    Passos 1-8 copiados tal e qual da versão anterior (v2).
-- ---------------------------------------------------------------------------
create or replace function public.bora_dispatch_maintenance()
returns void
language plpgsql
security definer
set search_path to 'public'
as $$
DECLARE
  v_order             record;
  v_cancelled_count   int := 0;
  v_ttl_max_count     int := 0;
  v_ttl_safety_count  int := 0;
  v_released_count    int := 0;
  v_drivers_online    int;
  v_jwt               text := public._dispatch_jwt();
  v_max_total_s       int;
  v_safety_s          int;
  v_release_s         int;
BEGIN
  PERFORM set_config('bora.caminho_oficial', 'bora_dispatch_maintenance', true);

  SELECT (value::text)::int INTO v_max_total_s
    FROM public.platform_settings WHERE key = 'dispatch_max_total_seconds_with_drivers_online';
  v_max_total_s := COALESCE(v_max_total_s, 1200);

  SELECT (value::text)::int INTO v_safety_s
    FROM public.platform_settings WHERE key = 'dispatch_auto_cancel_safety_seconds';
  v_safety_s := COALESCE(v_safety_s, 1800);

  SELECT (value::text)::int INTO v_release_s
    FROM public.platform_settings WHERE key = 'dispatch_preassign_release_seconds';
  v_release_s := COALESCE(v_release_s, 180);

  SELECT count(*) INTO v_drivers_online
    FROM public.drivers
    WHERE is_online = true
      AND last_heartbeat_at > NOW() - INTERVAL '90 seconds';

  -- 0) REDE DE SEGURANÇA (novo, 16/09): pedido pronto com estafeta atribuído
  --    que não aceitou em v_release_s → liberta, avisa o admin, chama o motor.
  FOR v_order IN
    SELECT o.id, o.assigned_driver_id, d.name AS driver_name,
           EXTRACT(EPOCH FROM (NOW() - COALESCE(o.driver_assigned_at, o.status_updated_at, o.dispatch_calling_since)))::int AS espera_s
      FROM public.orders o
      LEFT JOIN public.drivers d
        ON d.user_id::text = o.assigned_driver_id OR d.id::text = o.assigned_driver_id
     WHERE o.status = 'callingDriver'
       AND o.assigned_driver_id IS NOT NULL
       AND COALESCE(o.driver_assigned_at, o.status_updated_at, o.dispatch_calling_since, NOW())
           < NOW() - make_interval(secs => v_release_s)
  LOOP
    UPDATE public.orders
       SET assigned_driver_id      = NULL,
           driver_id               = NULL,
           current_driver_offer_id = NULL,
           driver_offer_expires_at = NULL,
           preassigned_driver_id   = NULL,
           dispatch_last_tick_at   = NOW()
     WHERE id = v_order.id AND status = 'callingDriver';
    PERFORM public._preassign_released_alert(
      v_order.id::text,
      COALESCE(v_order.driver_name, v_order.assigned_driver_id),
      'atribuído há ' || v_order.espera_s || ' s sem aceitar (limite ' || v_release_s || ' s)',
      'rede de segurança');
    PERFORM public.invoke_dispatch_engine(v_order.id::text);
    v_released_count := v_released_count + 1;
  END LOOP;
  IF v_released_count > 0 THEN
    RAISE NOTICE '[dispatch_maintenance] libertou % pedido(s) preso(s) em estafeta sem aceitar', v_released_count;
  END IF;

  -- 1) Pagamentos abandonados (inalterado da v1)
  WITH abandoned AS (
    UPDATE public.orders
       SET status         = 'cancelled',
           payment_status = 'failed',
           cancel_reason  = 'payment_abandoned'
     WHERE status = 'created' AND payment_status = 'pending'
       AND payment_method IN ('card', 'mbway')
       AND created_at < NOW() - INTERVAL '10 minutes'
    RETURNING id
  )
  SELECT count(*) INTO v_cancelled_count FROM abandoned;
  IF v_cancelled_count > 0 THEN
    RAISE NOTICE '[dispatch_maintenance] auto-cancelled % abandoned payment(s)', v_cancelled_count;
  END IF;

  -- 2) Backfill defensivo: callingDriver sem âncora TTL (pedidos pré-migration)
  UPDATE public.orders
     SET dispatch_calling_since = NOW()
   WHERE status = 'callingDriver' AND dispatch_calling_since IS NULL;

  -- 3) Acumulação do tempo de tentativa COM drivers online (inalterado da v1)
  IF v_drivers_online > 0 THEN
    UPDATE public.orders
       SET dispatch_online_attempt_seconds =
             COALESCE(dispatch_online_attempt_seconds, 0)
             + LEAST(
                 EXTRACT(EPOCH FROM (NOW() - COALESCE(dispatch_last_tick_at, NOW())))::int,
                 180
               ),
           dispatch_last_tick_at = NOW()
     WHERE status = 'callingDriver'
       AND assigned_driver_id IS NULL;
  ELSE
    UPDATE public.orders
       SET dispatch_last_tick_at = NOW()
     WHERE status = 'callingDriver'
       AND assigned_driver_id IS NULL;
  END IF;

  -- 4) Limpeza de extensões de parceiro expiradas (inalterado da v1)
  UPDATE public.orders
     SET dispatch_partner_decision_at = NULL,
         dispatch_extended_until      = NULL
   WHERE status = 'callingDriver'
     AND assigned_driver_id IS NULL
     AND dispatch_extended_until IS NOT NULL
     AND dispatch_extended_until < NOW();

  -- 5) TTL 1: máximo de tentativa ativa com drivers online
  IF v_drivers_online > 0 THEN
    FOR v_order IN
      SELECT id FROM public.orders
       WHERE status = 'callingDriver'
         AND assigned_driver_id IS NULL
         AND COALESCE(dispatch_online_attempt_seconds, 0) >= v_max_total_s
    LOOP
      IF public.dispatch_cancel_expired_order(v_order.id, 'dispatch_max_total_with_drivers_exceeded') THEN
        v_ttl_max_count := v_ttl_max_count + 1;
      END IF;
    END LOOP;
    IF v_ttl_max_count > 0 THEN
      RAISE NOTICE '[dispatch_maintenance] TTL max_total auto-cancel % order(s) (>=%s s)',
        v_ttl_max_count, v_max_total_s;
    END IF;
  END IF;

  -- 6) TTL 2: safety absoluto, COM OU SEM drivers online
  FOR v_order IN
    SELECT id FROM public.orders
     WHERE status = 'callingDriver'
       AND assigned_driver_id IS NULL
       AND dispatch_calling_since IS NOT NULL
       AND dispatch_calling_since < NOW() - make_interval(secs => v_safety_s)
  LOOP
    IF public.dispatch_cancel_expired_order(v_order.id, 'dispatch_safety_timeout') THEN
      v_ttl_safety_count := v_ttl_safety_count + 1;
    END IF;
  END LOOP;
  IF v_ttl_safety_count > 0 THEN
    RAISE NOTICE '[dispatch_maintenance] TTL safety auto-cancel % order(s) (>=%s s em callingDriver)',
      v_ttl_safety_count, v_safety_s;
  END IF;

  -- 7) Rotação de ofertas expiradas (inalterado da v1)
  UPDATE public.orders
     SET tried_driver_ids        = array_append(
                                     COALESCE(tried_driver_ids, '{}'::text[]),
                                     current_driver_offer_id
                                   ),
         current_driver_offer_id = NULL,
         driver_offer_expires_at = NULL
   WHERE status = 'callingDriver'
     AND assigned_driver_id IS NULL
     AND current_driver_offer_id IS NOT NULL
     AND driver_offer_expires_at IS NOT NULL
     AND driver_offer_expires_at < NOW();

  -- 8) Reinvocação do engine: só pedidos dentro dos TTLs E sem cadeia de retry ativa
  FOR v_order IN
    SELECT id FROM public.orders
     WHERE status = 'callingDriver'
       AND assigned_driver_id IS NULL
       AND current_driver_offer_id IS NULL
       AND (dispatch_extended_until IS NULL OR dispatch_extended_until > NOW())
       AND (dispatch_calling_since IS NULL
            OR dispatch_calling_since > NOW() - make_interval(secs => v_safety_s))
       AND COALESCE(dispatch_online_attempt_seconds, 0) < v_max_total_s
       AND (dispatch_next_retry_at IS NULL
            OR dispatch_next_retry_at < NOW() - INTERVAL '60 seconds')
  LOOP
    PERFORM net.http_post(
      url     := 'https://ojykpzwqrtusfeakzrna.supabase.co/functions/v1/dispatch-engine',
      headers := jsonb_build_object(
        'Content-Type', 'application/json',
        'Authorization', 'Bearer ' || v_jwt
      ),
      body    := jsonb_build_object('orderId', v_order.id::text)
    );
  END LOOP;
END;
$$;

-- ---------------------------------------------------------------------------
-- 5. admin_reassign_order — pré-atribui se ainda não pronto; avisa pela Edge
--    notify-driver-assigned (bloco 4). Mantém o resto da migração de 16/09.
-- ---------------------------------------------------------------------------
create or replace function public.admin_reassign_order(p_order_id text, p_new_driver text, p_motivo text default ''::text)
returns jsonb
language plpgsql
security definer
set search_path to 'public'
as $$
DECLARE
  v_o     record;
  v_d     record;
  v_new   text;
  v_ref   text;
  v_admin record;
BEGIN
  SELECT * INTO v_admin FROM public._admin_op_guard();
  PERFORM set_config('bora.caminho_oficial', 'admin_reassign_order', true);

  SELECT id, status, assigned_driver_id, preassigned_driver_id, service_type, vendor_name
    INTO v_o FROM orders WHERE id = p_order_id FOR UPDATE;
  IF v_o.id IS NULL THEN RETURN jsonb_build_object('ok', false, 'error', 'pedido_nao_encontrado'); END IF;
  IF v_o.status IN ('delivered','cancelled','rejected') THEN
    RETURN jsonb_build_object('ok', false, 'error', 'pedido_ja_terminal', 'status', v_o.status);
  END IF;
  IF COALESCE(v_o.service_type, '') = 'takeaway' THEN
    RETURN jsonb_build_object('ok', false, 'error', 'takeaway_sem_estafeta');
  END IF;

  SELECT d.id, d.user_id, d.name, d.approval_status INTO v_d
  FROM drivers d
  WHERE d.id::text = p_new_driver OR d.user_id::text = p_new_driver
  LIMIT 1;
  IF v_d.id IS NULL THEN RETURN jsonb_build_object('ok', false, 'error', 'estafeta_nao_encontrado'); END IF;
  IF v_d.approval_status <> 'approved' THEN
    RETURN jsonb_build_object('ok', false, 'error', 'estafeta_nao_aprovado');
  END IF;

  v_new := COALESCE(v_d.user_id, v_d.id)::text;   -- user_id manda
  v_ref := upper(substr(replace(p_order_id, '-', ''), 1, 6));

  -- Pedido AINDA NÃO PRONTO → pré-atribuição (vira oferta quando a loja marcar pronto)
  IF v_o.status NOT IN ('callingDriver', 'driverAccepted', 'pickedUp', 'onTheWay') THEN
    UPDATE orders
       SET preassigned_driver_id = v_new,
           preassigned_at        = now(),
           preassigned_by        = 'admin:' || COALESCE(v_admin.admin_email, v_admin.admin_id::text)
     WHERE id = p_order_id;

    PERFORM public.log_admin_action('order_preassigned', 'order', p_order_id,
      jsonb_build_object('de', v_o.preassigned_driver_id, 'para', v_new,
                         'estafeta', v_d.name, 'motivo', NULLIF(p_motivo,''), 'status', v_o.status));
    INSERT INTO admin_audit_log (admin_id, admin_email, action, entity_type, entity_id_text, details)
    VALUES (v_admin.admin_id, v_admin.admin_email, 'order_preassigned', 'order', p_order_id,
            jsonb_build_object('de', v_o.preassigned_driver_id, 'para', v_new,
                               'estafeta', v_d.name, 'motivo', NULLIF(p_motivo,''), 'status', v_o.status));

    PERFORM public._notify_driver_assigned_http(
      v_new, p_order_id, 'order_preassigned',
      '📦 Pedido reservado para ti',
      'O pedido ' || v_ref || COALESCE(' (' || v_o.vendor_name || ')', '') ||
      ' fica para ti. Recebes a oferta assim que a loja o marcar pronto — mantém-te ligado.');

    RETURN jsonb_build_object('ok', true, 'estafeta', v_d.name, 'novo_driver', v_new,
                              'pre_atribuicao', true, 'status', v_o.status);
  END IF;

  -- Pedido PRONTO ou em curso → atribuição directa (comportamento de 16/09)
  UPDATE orders
  SET assigned_driver_id = v_new,
      driver_id = COALESCE(v_d.user_id, v_d.id),
      current_driver_offer_id = NULL,
      driver_offer_expires_at = NULL,
      preassigned_driver_id = NULL,
      status = CASE WHEN status IN ('callingDriver') THEN 'driverAccepted' ELSE status END
  WHERE id = p_order_id;

  PERFORM public.log_admin_action('order_reassigned', 'order', p_order_id,
    jsonb_build_object('de', v_o.assigned_driver_id, 'para', v_new,
                       'estafeta', v_d.name, 'motivo', NULLIF(p_motivo,'')));
  INSERT INTO admin_audit_log (admin_id, admin_email, action, entity_type, entity_id_text, details)
  VALUES (v_admin.admin_id, v_admin.admin_email, 'order_reassigned', 'order', p_order_id,
          jsonb_build_object('de', v_o.assigned_driver_id, 'para', v_new,
                             'estafeta', v_d.name, 'motivo', NULLIF(p_motivo,''), 'status_antes', v_o.status));

  PERFORM public._notify_driver_assigned_http(
    v_new, p_order_id, 'order_reassigned',
    '📦 Pedido atribuído a ti',
    'O suporte atribuiu-te o pedido ' || v_ref || COALESCE(' (' || v_o.vendor_name || ')', '') ||
    '. Abre para ver os detalhes.');

  RETURN jsonb_build_object('ok', true, 'estafeta', v_d.name, 'novo_driver', v_new, 'pre_atribuicao', false);
END $$;

-- ---------------------------------------------------------------------------
-- 6. ops_reassign_order — caminho dos agentes; aceita pré-atribuição a
--    estafeta ligado (pedido ainda não pronto deixa de ser recusa).
-- ---------------------------------------------------------------------------
create or replace function public.ops_reassign_order(p_order_id text, p_new_driver text, p_motivo text, p_agente text, p_forcar boolean default false)
returns jsonb
language plpgsql
security definer
set search_path to 'public'
as $$
DECLARE
  v_o record;
  v_d record;
  v_pronto boolean;
  v_claims_antes text;
  v_res jsonb;
  c_admin_uid constant text := 'c9fccf85-03ee-4efc-83bf-613f211a78ff';
BEGIN
  IF coalesce(btrim(p_agente), '') = '' OR coalesce(btrim(p_motivo), '') = '' THEN
    RETURN jsonb_build_object('ok', false, 'error', 'agente_e_motivo_obrigatorios');
  END IF;
  PERFORM set_config('bora.caminho_oficial', 'ops_reassign_order', true);

  SELECT id, status, assigned_driver_id, service_type INTO v_o FROM orders WHERE id = p_order_id;
  IF v_o.id IS NULL THEN
    RETURN jsonb_build_object('ok', false, 'error', 'pedido_nao_encontrado');
  END IF;
  IF v_o.status IN ('delivered', 'cancelled', 'rejected') THEN
    RETURN jsonb_build_object('ok', false, 'error', 'pedido_ja_terminal', 'status', v_o.status);
  END IF;
  IF COALESCE(v_o.service_type, '') = 'takeaway' THEN
    RETURN jsonb_build_object('ok', false, 'error', 'takeaway_sem_estafeta');
  END IF;

  SELECT * INTO v_d FROM public._driver_reachability(p_new_driver);
  IF v_d.driver_id IS NULL THEN
    RETURN jsonb_build_object('ok', false, 'error', 'estafeta_nao_encontrado');
  END IF;
  IF v_d.is_banned THEN
    RETURN jsonb_build_object('ok', false, 'error', 'estafeta_banido', 'estafeta', v_d.name);
  END IF;

  v_pronto := v_o.status IN ('callingDriver', 'driverAccepted', 'pickedUp', 'onTheWay');

  IF NOT p_forcar AND (NOT v_d.online_agora OR NOT v_d.tem_notificacoes) THEN
    RETURN jsonb_build_object(
      'ok', false,
      'error', 'estafeta_nao_vai_receber',
      'estafeta', v_d.name,
      'online_agora', v_d.online_agora,
      'tem_notificacoes', v_d.tem_notificacoes,
      'ultimo_sinal', v_d.last_heartbeat_at,
      'plataforma', v_d.last_platform,
      'status_pedido', v_o.status,
      'o_que_fazer', 'Não atribuas por outro caminho. Diz ao Danilo o motivo em palavras simples. Só repetir com p_forcar => true se o Danilo mandar expressamente depois de saber o motivo.');
  END IF;

  v_claims_antes := current_setting('request.jwt.claims', true);
  PERFORM set_config('request.jwt.claims',
    json_build_object('sub', c_admin_uid, 'role', 'authenticated',
                      'email', 'nilofulfarotuga@gmail.com',
                      'app_metadata', json_build_object('role', 'admin'))::text, true);
  BEGIN
    v_res := public.admin_reassign_order(p_order_id, p_new_driver,
                                         left('[agente ' || p_agente || '] ' || p_motivo, 500));
  EXCEPTION WHEN OTHERS THEN
    PERFORM set_config('request.jwt.claims', coalesce(v_claims_antes, ''), true);
    RAISE;
  END;
  PERFORM set_config('request.jwt.claims', coalesce(v_claims_antes, ''), true);

  INSERT INTO admin_audit_log (action, entity_type, entity_id_text, admin_email, details)
  VALUES ('order_reassigned_by_agent', 'order', p_order_id, 'agente:' || p_agente,
          jsonb_build_object('agente', p_agente, 'motivo', p_motivo,
                             'de', v_o.assigned_driver_id,
                             'para', coalesce(v_d.user_id, v_d.driver_id), 'estafeta', v_d.name,
                             'forcado', p_forcar, 'online_agora', v_d.online_agora,
                             'tem_notificacoes', v_d.tem_notificacoes, 'status_pedido', v_o.status,
                             'pre_atribuicao', NOT v_pronto,
                             'resultado', v_res));

  RETURN coalesce(v_res, '{}'::jsonb)
         || jsonb_build_object('agente', p_agente, 'forcado', p_forcar,
                               'online_agora', v_d.online_agora, 'tem_notificacoes', v_d.tem_notificacoes,
                               'pre_atribuicao', NOT v_pronto);
END $$;

-- ---------------------------------------------------------------------------
-- 7. "Mandar para todos": tira o estafeta e devolve o pedido ao dispatch.
-- ---------------------------------------------------------------------------
create or replace function public.admin_release_order_driver(p_order_id text, p_motivo text default ''::text)
returns jsonb
language plpgsql
security definer
set search_path to 'public'
as $$
DECLARE
  v_o     record;
  v_admin record;
  v_antes text;
  v_ref   text;
BEGIN
  SELECT * INTO v_admin FROM public._admin_op_guard();
  PERFORM set_config('bora.caminho_oficial', 'admin_release_order_driver', true);

  SELECT id, status, assigned_driver_id, preassigned_driver_id, vendor_name
    INTO v_o FROM orders WHERE id = p_order_id FOR UPDATE;
  IF v_o.id IS NULL THEN RETURN jsonb_build_object('ok', false, 'error', 'pedido_nao_encontrado'); END IF;
  IF v_o.status IN ('delivered','cancelled','rejected') THEN
    RETURN jsonb_build_object('ok', false, 'error', 'pedido_ja_terminal', 'status', v_o.status);
  END IF;
  IF v_o.status IN ('pickedUp','onTheWay') THEN
    RETURN jsonb_build_object('ok', false, 'error', 'estafeta_ja_tem_a_encomenda', 'status', v_o.status);
  END IF;

  v_antes := COALESCE(v_o.assigned_driver_id, v_o.preassigned_driver_id);
  v_ref   := upper(substr(replace(p_order_id, '-', ''), 1, 6));

  IF v_o.status IN ('callingDriver', 'driverAccepted') THEN
    UPDATE orders
       SET assigned_driver_id      = NULL,
           driver_id               = NULL,
           current_driver_offer_id = NULL,
           driver_offer_expires_at = NULL,
           preassigned_driver_id   = NULL,
           status                  = 'callingDriver'
     WHERE id = p_order_id;
  ELSE
    UPDATE orders SET preassigned_driver_id = NULL, preassigned_at = NULL, preassigned_by = NULL
     WHERE id = p_order_id;
  END IF;

  PERFORM public.log_admin_action('order_driver_released', 'order', p_order_id,
    jsonb_build_object('de', v_antes, 'motivo', NULLIF(p_motivo,''), 'status_antes', v_o.status));
  INSERT INTO admin_audit_log (admin_id, admin_email, action, entity_type, entity_id_text, details)
  VALUES (v_admin.admin_id, v_admin.admin_email, 'order_driver_released', 'order', p_order_id,
          jsonb_build_object('de', v_antes, 'motivo', NULLIF(p_motivo,''), 'status_antes', v_o.status));

  IF v_antes IS NOT NULL THEN
    PERFORM public._notify_driver_assigned_http(
      v_antes, p_order_id, 'order_unassigned',
      'Pedido ' || v_ref || ' retirado',
      'O suporte devolveu o pedido ' || v_ref || ' à fila geral. Não precisas de fazer nada.');
  END IF;

  -- driverAccepted → callingDriver já dispara o motor pelo trigger de status;
  -- em callingDriver o status não muda, por isso chama-se aqui.
  IF v_o.status = 'callingDriver' THEN
    PERFORM public.invoke_dispatch_engine(p_order_id);
  END IF;

  RETURN jsonb_build_object('ok', true, 'de', v_antes, 'status_antes', v_o.status);
END $$;

create or replace function public.ops_release_order_driver(p_order_id text, p_motivo text, p_agente text)
returns jsonb
language plpgsql
security definer
set search_path to 'public'
as $$
DECLARE
  v_claims_antes text;
  v_res jsonb;
  c_admin_uid constant text := 'c9fccf85-03ee-4efc-83bf-613f211a78ff';
BEGIN
  IF coalesce(btrim(p_agente), '') = '' OR coalesce(btrim(p_motivo), '') = '' THEN
    RETURN jsonb_build_object('ok', false, 'error', 'agente_e_motivo_obrigatorios');
  END IF;
  PERFORM set_config('bora.caminho_oficial', 'ops_release_order_driver', true);
  v_claims_antes := current_setting('request.jwt.claims', true);
  PERFORM set_config('request.jwt.claims',
    json_build_object('sub', c_admin_uid, 'role', 'authenticated',
                      'email', 'nilofulfarotuga@gmail.com',
                      'app_metadata', json_build_object('role', 'admin'))::text, true);
  BEGIN
    v_res := public.admin_release_order_driver(p_order_id, left('[agente ' || p_agente || '] ' || p_motivo, 500));
  EXCEPTION WHEN OTHERS THEN
    PERFORM set_config('request.jwt.claims', coalesce(v_claims_antes, ''), true);
    RAISE;
  END;
  PERFORM set_config('request.jwt.claims', coalesce(v_claims_antes, ''), true);

  INSERT INTO admin_audit_log (action, entity_type, entity_id_text, admin_email, details)
  VALUES ('order_driver_released_by_agent', 'order', p_order_id, 'agente:' || p_agente,
          jsonb_build_object('agente', p_agente, 'motivo', p_motivo, 'resultado', v_res));
  RETURN coalesce(v_res, '{}'::jsonb) || jsonb_build_object('agente', p_agente);
END $$;

revoke all on function public.ops_release_order_driver(text, text, text) from public;
revoke all on function public.ops_release_order_driver(text, text, text) from anon;
revoke all on function public.ops_release_order_driver(text, text, text) from authenticated;
grant execute on function public.ops_release_order_driver(text, text, text) to service_role;

-- ---------------------------------------------------------------------------
-- 8. Heartbeat com plataforma (sobrecarga; a versão sem argumentos continua)
-- ---------------------------------------------------------------------------
create or replace function public.driver_heartbeat(p_platform text)
returns jsonb
language plpgsql
security definer
set search_path to 'public'
as $$
DECLARE
  v_uid UUID;
  v_now TIMESTAMPTZ := now();
  v_plat text := lower(btrim(coalesce(p_platform, '')));
BEGIN
  v_uid := auth.uid();
  IF v_uid IS NULL THEN
    RAISE EXCEPTION 'unauthenticated' USING ERRCODE = '42501';
  END IF;
  IF v_plat NOT IN ('android_app','ios_app','web_ios','web_android','web_desktop') THEN
    v_plat := NULL;
  END IF;

  UPDATE public.drivers
     SET last_heartbeat_at = v_now,
         is_online = true,
         last_platform    = COALESCE(v_plat, last_platform),
         last_platform_at = CASE WHEN v_plat IS NULL THEN last_platform_at ELSE v_now END
   WHERE user_id = v_uid OR id = v_uid;

  RETURN jsonb_build_object('success', true, 'driver_id', v_uid, 'heartbeat_at', v_now, 'platform', v_plat);
END;
$$;
grant execute on function public.driver_heartbeat(text) to authenticated;

-- ---------------------------------------------------------------------------
-- 9. Quem cai por falta de sinal fica a saber (padrão Uber)
-- ---------------------------------------------------------------------------
create or replace function public.expire_stale_driver_presence()
returns integer
language plpgsql
security definer
set search_path to 'public'
as $$
DECLARE
  v_count integer;
  v_dl    integer;
  v_uid   text;
  v_uids  text[];
BEGIN
  WITH off AS (
    UPDATE public.drivers
       SET is_online = false
     WHERE is_online
       AND (last_heartbeat_at IS NULL
            OR last_heartbeat_at < now() - interval '90 seconds')
    RETURNING COALESCE(user_id, id)::text AS uid
  )
  SELECT count(*), array_agg(uid) INTO v_count, v_uids FROM off;

  UPDATE public.driver_locations
     SET is_online = false
   WHERE is_online
     AND last_updated < now() - interval '90 seconds';
  GET DIAGNOSTICS v_dl = ROW_COUNT;

  -- Aviso ao estafeta que caiu: sem isto ele acha que está a receber pedidos.
  IF v_uids IS NOT NULL THEN
    FOREACH v_uid IN ARRAY v_uids LOOP
      PERFORM public._notify_driver_assigned_http(
        v_uid, NULL, 'driver_offline',
        'Ficaste desligado',
        'Ficaste desligado. Abre a Bora para voltares a receber pedidos.');
    END LOOP;
  END IF;

  RETURN COALESCE(v_count, 0) + v_dl;
END;
$$;
