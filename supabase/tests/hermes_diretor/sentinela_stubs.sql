-- Esqueleto mínimo para provar o vigia (B3) no PGlite. Colunas e tipos copiados da produção (confirmados por SELECT em 22/11/2026).
create role anon nologin; create role authenticated nologin; create role service_role nologin;
create schema cron; create schema auth;
grant usage on schema public to anon, authenticated, service_role;
create schema vault;
create table cron.job (jobid serial primary key, jobname text, schedule text, command text);
create table cron.job_run_details (runid bigserial primary key, jobid bigint, status text, return_message text, start_time timestamptz);
create function cron.schedule(n text, s text, c text) returns bigint language plpgsql as $$
declare v bigint; begin
  delete from cron.job where jobname = n;
  insert into cron.job(jobname,schedule,command) values (n,s,c) returning jobid into v; return v; end $$;
create function cron.unschedule(n text) returns boolean language plpgsql as $$
begin
  if not exists (select 1 from cron.job where jobname = n) then raise exception 'could not find valid entry for job %', n; end if;
  delete from cron.job where jobname = n; return true; end $$;

create function public.is_admin() returns boolean language sql stable as $$ select coalesce(current_setting('app.admin', true), '') = '1' $$;

create table public.platform_settings (key text primary key, value jsonb, description text, category text, updated_at timestamptz default now(), updated_by uuid, is_secret boolean);

create table public.despacho (
  id bigint generated always as identity primary key,
  origem text not null check (origem = any (array['danilo-telegram','claude-ai','relogio','evento','agente'])),
  para text not null default 'emerson',
  tipo text not null default 'tarefa' check (tipo = any (array['tarefa','campanha','pergunta','ordem-fixa'])),
  titulo text not null, tarefa text not null,
  prioridade integer not null default 50,
  estado text not null default 'aberta' check (estado = any (array['aberta','executando','feita','falhou','a-espera-do-danilo','a-espera-do-pc','cancelada'])),
  subtarefas jsonb not null default '[]'::jsonb, resultado text, prova text, conversa_id text, custo_estimado numeric,
  created_at timestamptz not null default now(), iniciada_em timestamptz, terminada_em timestamptz, atualizada_em timestamptz not null default now());
create table public.licoes_robos (id bigint generated always as identity primary key, robo text, errou text, regra text);
create table public.agentes_estado (id serial primary key, nome text);

create table public.orders (id text primary key, restaurant_id text, order_type text,
  status text not null check (status = any (array['created','preparing','readyForPickup','callingDriver','driverAccepted','pickedUp','onTheWay','delivered','rejected','cancelled'])),
  created_at timestamptz default now(), status_updated_at timestamptz default now(), accepted_at timestamptz, dispatch_calling_since timestamptz,
  assigned_driver_id text, scheduled_for timestamptz, is_test_order boolean default false);
create table public.tvde_rides (id uuid primary key default gen_random_uuid(), status text, created_at timestamptz default now(), no_driver_since timestamptz);
create table public.cleaning_bookings (id uuid primary key default gen_random_uuid(), status text, cleaner_id uuid, is_test_order boolean default false, created_at timestamptz default now());
create table public.carwash_bookings (id uuid primary key default gen_random_uuid(), status text, washer_id uuid, is_test_order boolean default false, created_at timestamptz default now());
create table public.appointments (id uuid primary key default gen_random_uuid(), status text, awaiting_since timestamptz, is_test boolean default false);
create table public.reservations (id uuid primary key default gen_random_uuid(), created_at timestamptz default now(), status text default 'pending', reserved_for timestamptz);
create table public.encomendas_telefone (order_id text, criado_em timestamptz default now(), libertado_em timestamptz, cancelado_em timestamptz);
create table public.payment_drafts_alertados (draft_id uuid, alertado_em timestamptz, tentativa_em timestamptz, avisado_em timestamptz);
create table public.payment_reconciliation_findings (id uuid primary key default gen_random_uuid(), run_at timestamptz default now(), kind text, severity text, entity_type text, entity_id text, pi_id text, amount_cents integer, details jsonb, resolved_at timestamptz);
create table public.order_lifecycle_errors (id bigserial primary key, order_id text, component text, error_message text, occurred_at timestamptz default now(), context jsonb);
create table public.debug_crash_logs (id uuid primary key default gen_random_uuid(), created_at timestamptz default now(), screen text, error_message text);
create table public.ia_gastos (id bigserial primary key, quando timestamptz default now(), robo text, ok boolean, erro text);
create table public.robot_runs (id uuid primary key default gen_random_uuid(), started_at timestamptz default now(), status text, error text);
create table public.vigia_servidor_registos (id bigserial primary key, criado_em timestamptz default now(), alertou boolean, motivo text);
create table public.support_chatbot_sessions (id uuid primary key default gen_random_uuid(), escalated_pending boolean, admin_assumiu_em timestamptz, ultima_msg_em timestamptz);
create table public.support_chatbot_messages (id uuid primary key default gen_random_uuid(), session_id uuid, role text, content text, created_at timestamptz default now());
create table public.support_tickets (id uuid primary key default gen_random_uuid(), satisfaction integer, created_at timestamptz default now(), updated_at timestamptz);
create table public.assistant_conversations (id uuid primary key default gen_random_uuid(), status text check (status = any (array['open','closed','handoff'])), last_message_at timestamptz, equipa_assumiu_por uuid);
create table public.assistant_chat_messages (id uuid primary key default gen_random_uuid(), conversation_id uuid, role text, content text, created_at timestamptz default now());
create table public.whatsapp_contacts (numero text primary key, ultima_msg_em timestamptz, ultima_resposta_bot_em timestamptz, bot_pausado boolean, assumido_por_danilo boolean);
create table public.whatsapp_messages (id bigserial primary key, numero text, direcao text, texto text, transcricao text, created_at timestamptz default now());
create table public.carrinhos_abandonados (user_id uuid, n_itens integer, atualizado_em timestamptz, convertido_em timestamptz);
