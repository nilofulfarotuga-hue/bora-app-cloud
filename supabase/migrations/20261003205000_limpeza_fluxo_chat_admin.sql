-- 2026-10-03 — Limpeza: fluxo da limpadora, chat da Bora e fecho sem SQL à mão.
--
-- Casos reais: a Mayra (03/10) não percebeu "A caminho → Iniciar → Concluir"
-- e o início não ficou gravado; ontem o cliente não confirmou e o Danilo
-- fechou à mão (horas redondas escritas na base); a Bora não conseguia
-- escrever no chat da limpeza.
--
-- 1. _cleaning_transition aceita vários estados de partida (lista separada
--    por vírgulas), é idempotente (repetir o mesmo passo não dá erro) e
--    preenche as horas dos passos saltados. Assim "Iniciar" funciona mesmo
--    sem "A caminho", e "Concluir" mesmo sem "Iniciar" (como Uber/Helpling:
--    o prestador nunca fica preso por ter saltado um botão).
--    Deixa de notificar o cliente — quem notifica são os wrappers, com o
--    texto certo. Antes o cliente recebia DUAS notificações por passo.
-- 2. Chat: sender_role passa a aceitar 'admin'; nova RPC
--    admin_send_cleaning_message; o push de uma mensagem da Bora vai para o
--    cliente e para a limpadora.
-- 3. Lembrete ao cliente para confirmar a limpeza, 2 h depois de terminada
--    (a confirmação automática das 24 h mantém-se).
-- 4. Limpeza presa em curso: além do aviso ao admin, a limpadora recebe
--    "Já terminaste?".
-- 5. admin_set_cleaning_status: o admin avança o estado (a caminho / em
--    curso / terminada) com motivo e auditoria. NÃO mexe em dinheiro — o
--    pagamento continua a ser libertado só pela confirmação (cliente ou
--    automática), como já estava.

create or replace function public._cleaning_transition(p_booking_id uuid, p_from text, p_to text, p_ts_col text)
returns jsonb
language plpgsql
security definer
set search_path to 'public'
as $function$
declare
  v_me cleaners; v_b cleaning_bookings;
  v_from text[] := string_to_array(replace(p_from, ' ', ''), ',');
begin
  v_me := public._cleaning_current_cleaner();
  select * into v_b from cleaning_bookings where id = p_booking_id for update;
  if v_b.id is null or v_b.cleaner_id is distinct from v_me.id then
    raise exception 'booking_not_yours';
  end if;
  -- Idempotente: segundo toque / nova tentativa depois de falha de rede.
  if v_b.status = p_to then
    return to_jsonb(v_b);
  end if;
  if not (v_b.status = any(v_from)) then
    raise exception 'invalid_transition_from_%', v_b.status;
  end if;
  execute format('update cleaning_bookings set status = $1, %I = now() where id = $2', p_ts_col)
  using p_to, p_booking_id;
  -- Passos saltados ficam com hora (nunca ficam vazios). Em update separado:
  -- no mesmo SET o Postgres recusa atribuir started_at duas vezes.
  update cleaning_bookings set
    on_the_way_at = case when p_to in ('in_progress','done') then coalesce(on_the_way_at, now()) else on_the_way_at end,
    started_at    = case when p_to = 'done' then coalesce(started_at, now()) else started_at end
  where id = p_booking_id;
  return (select to_jsonb(b) from cleaning_bookings b where b.id = p_booking_id);
end $function$;

create or replace function public.cleaning_mark_on_the_way(p_booking_id uuid)
returns jsonb language plpgsql security definer set search_path to 'public' as $function$
declare v jsonb; v_antes text;
begin
  select status into v_antes from cleaning_bookings where id = p_booking_id;
  v := public._cleaning_transition(p_booking_id, 'accepted', 'on_the_way', 'on_the_way_at');
  if v_antes is distinct from 'on_the_way' then
    perform public._cleaning_notify_user((v ->> 'client_user_id')::uuid, 'cleaning_on_the_way',
      'A caminho 🚗', 'A tua profissional está a caminho.', p_booking_id::text);
  end if;
  return v;
end $function$;

create or replace function public.cleaning_mark_started(p_booking_id uuid)
returns jsonb language plpgsql security definer set search_path to 'public' as $function$
declare v jsonb; v_antes text;
begin
  select status into v_antes from cleaning_bookings where id = p_booking_id;
  v := public._cleaning_transition(p_booking_id, 'accepted,on_the_way', 'in_progress', 'started_at');
  if v_antes is distinct from 'in_progress' then
    perform public._cleaning_notify_user((v ->> 'client_user_id')::uuid, 'cleaning_started',
      'Limpeza iniciada 🧽', 'A tua limpeza começou.', p_booking_id::text);
  end if;
  return v;
end $function$;

create or replace function public.cleaning_mark_done(p_booking_id uuid)
returns jsonb language plpgsql security definer set search_path to 'public' as $function$
declare v jsonb; v_antes text;
begin
  select status into v_antes from cleaning_bookings where id = p_booking_id;
  v := public._cleaning_transition(p_booking_id, 'on_the_way,in_progress', 'done', 'done_at');
  if v_antes is distinct from 'done' then
    perform public._cleaning_notify_user((v ->> 'client_user_id')::uuid, 'cleaning_done',
      'Limpeza concluída ✅',
      'A profissional marcou a limpeza como concluída. Confirma na app para libertar o pagamento.',
      p_booking_id::text);
  end if;
  return v;
end $function$;

-- 2) Chat da Bora -----------------------------------------------------------
alter table public.cleaning_messages drop constraint if exists cleaning_messages_sender_role_check;
alter table public.cleaning_messages add constraint cleaning_messages_sender_role_check
  check (sender_role = any (array['client'::text, 'cleaner'::text, 'admin'::text]));

create or replace function public._cleaning_chat_push()
returns trigger language plpgsql security definer set search_path to 'public' as $function$
declare v_b cleaning_bookings; v_to uuid; v_limpadora uuid;
begin
  select * into v_b from cleaning_bookings where id = new.booking_id;
  if v_b.id is null then return new; end if;
  if v_b.cleaner_id is not null then
    select user_id into v_limpadora from cleaners where id = v_b.cleaner_id;
  end if;
  if new.sender_role = 'admin' then
    perform public._cleaning_notify_user(v_b.client_user_id, 'cleaning_chat',
      'Mensagem da Bora 💬', left(new.message, 96), new.booking_id::text);
    if v_limpadora is not null then
      perform public._cleaning_notify_user(v_limpadora, 'cleaning_chat',
        'Mensagem da Bora 💬', left(new.message, 96), new.booking_id::text);
    end if;
    return new;
  end if;
  if v_b.cleaner_id is null then return new; end if;
  if new.sender_role = 'client' then
    v_to := v_limpadora;
  else
    v_to := v_b.client_user_id;
  end if;
  perform public._cleaning_notify_user(
    v_to, 'cleaning_chat', 'Nova mensagem 💬',
    left(new.message, 96), new.booking_id::text);
  return new;
end $function$;

create or replace function public.admin_send_cleaning_message(p_booking_id uuid, p_message text)
returns jsonb language plpgsql security definer set search_path to 'public' as $function$
declare v_msg cleaning_messages;
begin
  perform public._admin_op_guard();
  if p_message is null or length(trim(p_message)) = 0 then
    raise exception 'mensagem_vazia';
  end if;
  if not exists (select 1 from cleaning_bookings where id = p_booking_id) then
    raise exception 'booking_not_found';
  end if;
  insert into cleaning_messages (booking_id, sender_role, message)
  values (p_booking_id, 'admin', left(trim(p_message), 2000))
  returning * into v_msg;
  perform public.log_admin_action('cleaning_chat_sent', 'cleaning_booking',
    p_booking_id::text, jsonb_build_object('message_id', v_msg.id));
  return to_jsonb(v_msg);
end $function$;
revoke all on function public.admin_send_cleaning_message(uuid, text) from public, anon;
grant execute on function public.admin_send_cleaning_message(uuid, text) to authenticated;

-- 3) Lembrete ao cliente -----------------------------------------------------
alter table public.cleaning_bookings add column if not exists client_confirm_reminded_at timestamptz;

create or replace function public._cleaning_cron_auto_confirm()
returns integer language plpgsql security definer set search_path to 'public' as $function$
declare
  v_hours int := public._cleaning_setting_int('cleaning_auto_confirm_hours', 24);
  v_lembrete int := public._cleaning_setting_int('cleaning_confirm_reminder_hours', 2);
  v_count int := 0; v_rec record;
begin
  for v_rec in
    select id, client_user_id from cleaning_bookings
     where status = 'done' and client_confirm_reminded_at is null
       and done_at < now() - make_interval(hours => v_lembrete)
       and done_at >= now() - make_interval(hours => v_hours)
  loop
    perform public._cleaning_notify_user(v_rec.client_user_id, 'cleaning_done',
      'Correu bem a limpeza?',
      'Confirma na app que a limpeza ficou feita. Se não disseres nada, confirmamos automaticamente.',
      v_rec.id::text);
    update cleaning_bookings set client_confirm_reminded_at = now() where id = v_rec.id;
  end loop;

  for v_rec in
    select id from cleaning_bookings
     where status = 'done' and done_at < now() - make_interval(hours => v_hours)
  loop
    perform public._cleaning_complete(v_rec.id, true);
    v_count := v_count + 1;
  end loop;
  return v_count;
end $function$;

-- 4) Limpeza presa em curso: perguntar também à limpadora ---------------------
create or replace function public._cleaning_cron_stuck_in_progress()
returns integer language plpgsql security definer set search_path to 'public' as $function$
declare
  v_hours int := public._cleaning_setting_int('cleaning_stuck_alert_hours', 6);
  v_count int := 0;
  v_rec record;
  v_limpadora uuid;
begin
  for v_rec in
    select id, status, scheduled_at, total_cents, payment_method, cleaner_id
      from cleaning_bookings
     where status in ('on_the_way', 'in_progress')
       and scheduled_at < now() - make_interval(hours => v_hours)
       and stuck_alerted_at is null
  loop
    perform public._cleaning_notify_admin(
      'Limpeza presa em ' || v_rec.status,
      'Booking ' || left(v_rec.id::text, 8) || ' agendada para ' ||
      to_char(v_rec.scheduled_at at time zone 'Europe/Lisbon', 'DD/MM HH24:MI') ||
      ' continua ' || v_rec.status || ' (' || v_rec.payment_method || ', EUR ' ||
      to_char(v_rec.total_cents / 100.0, 'FM999990.00') ||
      '). No painel: Limpezas → abrir a reserva → "Marcar como terminada".');
    select user_id into v_limpadora from cleaners where id = v_rec.cleaner_id;
    if v_limpadora is not null then
      perform public._cleaning_notify_user(v_limpadora, 'cleaning_stuck',
        'Já terminaste a limpeza?',
        'Carrega em "Concluir limpeza" na app para o cliente confirmar e receberes.',
        v_rec.id::text);
    end if;
    update cleaning_bookings set stuck_alerted_at = now() where id = v_rec.id;
    v_count := v_count + 1;
  end loop;
  return v_count;
end $function$;

-- 5) Admin avança o estado (sem dinheiro) -------------------------------------
create or replace function public.admin_set_cleaning_status(p_booking_id uuid, p_to text, p_reason text)
returns jsonb language plpgsql security definer set search_path to 'public' as $function$
declare v_b cleaning_bookings; v_ordem text[] := array['accepted','on_the_way','in_progress','done'];
begin
  perform public._admin_op_guard();
  if p_to not in ('on_the_way', 'in_progress', 'done') then
    raise exception 'estado_invalido: %', p_to;
  end if;
  if p_reason is null or length(trim(p_reason)) < 3 then
    raise exception 'motivo_obrigatorio';
  end if;
  select * into v_b from cleaning_bookings where id = p_booking_id for update;
  if v_b.id is null then raise exception 'booking_not_found'; end if;
  if v_b.cleaner_id is null then raise exception 'sem_limpadora'; end if;
  if v_b.status = p_to then return to_jsonb(v_b); end if;
  if coalesce(array_position(v_ordem, v_b.status), 99) >= array_position(v_ordem, p_to) then
    raise exception 'so_avanca: de % para % nao e permitido', v_b.status, p_to;
  end if;
  update cleaning_bookings set
    status = p_to,
    on_the_way_at = coalesce(on_the_way_at, now()),
    started_at = case when p_to in ('in_progress','done') then coalesce(started_at, now()) else started_at end,
    done_at = case when p_to = 'done' then coalesce(done_at, now()) else done_at end
  where id = p_booking_id;
  perform public.log_admin_action('cleaning_status_set', 'cleaning_booking', p_booking_id::text,
    jsonb_build_object('de', v_b.status, 'para', p_to, 'motivo', p_reason));
  if p_to = 'done' then
    perform public._cleaning_notify_user(v_b.client_user_id, 'cleaning_done',
      'Limpeza concluída ✅',
      'A limpeza foi marcada como concluída. Confirma na app que ficou tudo bem.',
      p_booking_id::text);
  end if;
  return (select to_jsonb(b) from cleaning_bookings b where b.id = p_booking_id);
end $function$;
revoke all on function public.admin_set_cleaning_status(uuid, text, text) from public, anon;
grant execute on function public.admin_set_cleaning_status(uuid, text, text) to authenticated;
