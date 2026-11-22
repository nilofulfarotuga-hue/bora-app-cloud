-- Stubs mínimos para a prova local da porta do Hermes (B4). Nomes de teste de propósito: a prova é do
-- MECANISMO (classificar, travar, autorizar), não dos nomes reais das tabelas de produção.
create schema cron; create schema auth; create schema vault;
create role anon nologin; create role authenticated nologin; create role service_role nologin;
create table cron.job (jobid bigserial primary key, jobname text, schedule text, command text, active boolean default true);
create table cron.job_run_details (runid bigserial primary key, jobid bigint, status text, return_message text, start_time timestamptz default now());
create function cron.schedule(n text, s text, c text) returns bigint language plpgsql as $$
declare v bigint; begin delete from cron.job where jobname = n; insert into cron.job(jobname, schedule, command) values (n, s, c) returning jobid into v; return v; end $$;
create function cron.unschedule(j bigint) returns boolean language sql as $$ delete from cron.job where jobid = j returning true $$;
create table vault.decrypted_secrets (name text, decrypted_secret text);
create function auth.uid() returns uuid language sql stable as $$ select null::uuid $$;
create function public.is_admin() returns boolean language sql stable as $$ select coalesce(current_setting('app.admin', true), '') = '1' $$;

create table public.platform_settings (key text primary key, value jsonb, description text, category text, updated_at timestamptz default now(), updated_by uuid, is_secret boolean default false);
create table public.admin_audit_log (id uuid primary key default gen_random_uuid(), admin_id uuid, admin_email text, action text, entity_type text, entity_id uuid, entity_id_text text, details jsonb, created_at timestamptz default now());
create table public.despacho (id bigint generated always as identity primary key, origem text, para text, tipo text, titulo text, tarefa text, prioridade int, estado text default 'aberta', resultado text, prova text, terminada_em timestamptz);
create table public.licoes_robos (id bigint generated always as identity primary key, robo text not null, errou text, regra text not null, origem text, vezes int default 1, ativa boolean default true);
create table public.agentes_estado (agente text primary key, ligado boolean, nota text);
insert into public.agentes_estado values ('critico', false, 'ARQUIVADO 22/11/2026: substituto=fiscal. Fundido.'), ('torre', true, null);

-- o canal de alertas, em stub: guarda o que mandaria ao Danilo
create table public.avisos_teste (id bigserial primary key, tipo text, texto text, ref text, link text);
create function public.notify_admin_urgent_push(p_event_type text, p_summary text, p_entity_type text, p_entity_id text, p_payload jsonb, p_deep_link text)
returns uuid language plpgsql security definer as $$
begin insert into public.avisos_teste (tipo, texto, ref, link) values (p_event_type, p_summary, p_entity_id, p_deep_link); return gen_random_uuid(); end $$;

-- tabelas de teste, uma por classe
create table public.clientes_teste (id int primary key, nome text, nota text);                      -- livre
create table public.carteiras_teste (id int primary key, saldo_cents int);                          -- valor (pelo nome)
create table public.produtos_teste (id int primary key, nome text, preco numeric, disponivel boolean); -- livre, com coluna de valor
create table public.orders (id text primary key, status text);                                      -- operação
create table public.bkp_clientes_20261101 (id int, nome text);                                      -- cópia: controlo
create table public.avisos_push_tokens (id int primary key, fcm_token text);                        -- segredo (pelo nome)
create table public.parceiros_teste (id int primary key, nome text, iban text, nif text);           -- livre, com colunas reservadas
create table public.registos_teste (id int primary key, texto text);                                -- livre, mas o gatilho mexe em valores
insert into public.clientes_teste values (1, 'Ana', null), (2, 'Rui', null);
insert into public.carteiras_teste values (1, 500);
insert into public.produtos_teste values (1, 'Arroz', 1.29, true);
insert into public.orders values ('P1', 'delivered'), ('P2', 'delivered');
insert into public.avisos_push_tokens values (1, 'segredo-fcm');
insert into public.parceiros_teste values (1, 'Loja A', 'PT50-IBAN-SECRETO', '123456789');
insert into public.platform_settings (key, value, category, is_secret) values
  ('sentinela_minutos_loja', '8', 'sentinela', false), ('comissao_parceiro_pct', '10', 'precos', false), ('chave_api_externa', '"abc-segredo"', 'chaves', true);

create function public.trg_registos_paga() returns trigger language plpgsql as $$
begin update public.carteiras_teste set saldo_cents = saldo_cents + 1 where id = 1; return new; end $$;
create trigger registos_paga after insert on public.registos_teste for each row execute function public.trg_registos_paga();

-- funções de teste, uma por classe
create function public.pagar_parceiro_teste(p int) returns int language sql as $$ select p $$;                                         -- valor (pelo nome)
create function public.ajusta_escondido_teste() returns void language sql as $$ update public.carteiras_teste set saldo_cents = saldo_cents $$;  -- valor (mexe na tabela)
create function public.chama_ajuste_teste() returns void language plpgsql as $$ begin perform public.ajusta_escondido_teste(); end $$;  -- valor (contágio)
create function public.marcar_visto_teste(p int) returns void language sql as $$ update public.clientes_teste set nota = 'visto' where id = p $$;  -- livre
create function public.ler_total_teste() returns bigint language sql stable as $$ select sum(saldo_cents) from public.carteiras_teste $$;   -- livre (só lê)
create function public.le_cofre_teste() returns text language sql as $$ select decrypted_secret from vault.decrypted_secrets limit 1 $$;    -- segredo
create function public.ops_reassign_order(p_order_id text, p_new_driver text, p_motivo text, p_agente text, p_forcar boolean default false) returns jsonb language sql as $$ select '{"ok":true}'::jsonb $$;  -- operação
create function public.fecha_pedido_teste(p text) returns void language sql as $$ update public.orders set status = 'delivered' where id = p $$;  -- mexe em pedidos fora das ops_*
