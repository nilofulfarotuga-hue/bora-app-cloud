-- 01/11/2026 (missão seguranca-05, bloco 4) — guarda de colunas sensíveis nas tabelas dos prestadores.
--
-- PORQUÊ: a política washers_update_own (UPDATE, {authenticated}, user_id = auth.uid() OR is_admin())
-- não limita colunas: o lavador podia, com um PATCH direto em /rest/v1/washers, pôr-se
-- approval_status='approved', tirar o próprio ban, mudar o IBAN para onde lhe pagamos, subir a nota.
-- O mesmo buraco existe nas gémeas (PADRAO_BORA.md §2, regra dos gémeos — "o que se arranja num
-- papel arranja-se em todos"):
--   drivers.drivers_update_own        — o with_check só impede sair de pending/approved; um pending
--                                       pode pôr-se 'approved' com is_banned=false (passa no check)
--   service_providers.sp_update       — user_id = auth.uid() OR is_admin(), sem guarda de colunas
--   cleaners / casa_profissionais     — hoje só têm política SELECT (sem UPDATE direto); a guarda
--                                       entra na mesma, para o dia em que alguém abrir o UPDATE
--
-- COMO: gatilho BEFORE UPDATE `a00_colunas_guarda` (nome com a00 para correr antes dos outros) que,
-- quando quem escreve é o papel da app (current_user = authenticated ou anon) e NÃO é admin
-- (public.is_admin()), repõe as colunas sensíveis ao valor de OLD em silêncio e regista a tentativa em
-- e2e_log (fluxo 'prestador-colunas-guarda'). As políticas RLS já limitam o UPDATE ao próprio
-- (user_id = auth.uid()) ou ao admin, por isso "app-role e não-admin" = "o próprio".
--
-- QUEM NÃO É AFETADO (de propósito):
--   • RPCs SECURITY DEFINER (driver_register_or_update, washer_apply, cleaner_set_profile,
--     provider_update_legal_fields, admin_update_washer, _carwash_complete, casa_*): correm como
--     o dono (postgres), current_user ≠ authenticated → o gatilho deixa passar. É por aí que a app
--     escreve NIF/IBAN/mbway (lib/ confirmado 01/11: nenhum UPDATE direto dessas colunas).
--   • service_role, cron, MCP, Edge Functions com chave secreta: idem.
--   • Painel admin com sessão de admin: is_admin() = true → passa.
--   • Colunas que o PRÓPRIO controla de propósito e por isso NÃO entram na guarda:
--     is_online (regra do Danilo: só o botão desliga), lat/lng, fcm_token, photo_url, docs,
--     priority_until (o estafeta compra prioridade em ganhos_screen.dart), is_active de
--     washers/cleaners (o próprio liga/desliga por RPC), business_hours/gallery/social dos parceiros.
--
-- Idempotente: CREATE OR REPLACE da função; DROP TRIGGER IF EXISTS antes de cada CREATE TRIGGER.

create or replace function public._prestador_colunas_guarda()
returns trigger
language plpgsql
as $fn$
declare
  v_old     jsonb := to_jsonb(OLD);
  v_new     jsonb := to_jsonb(NEW);
  v_mudadas text[] := '{}';
  c         text;
begin
  -- Só escrita direta pelo papel da app. Funções definer (postgres), service_role, cron e MCP passam.
  if current_user not in ('authenticated', 'anon') then
    return NEW;
  end if;
  if public.is_admin() then
    return NEW;
  end if;

  foreach c in array tg_argv loop
    if (v_new -> c) is distinct from (v_old -> c) then
      v_mudadas := array_append(v_mudadas, c);
    end if;
  end loop;

  if cardinality(v_mudadas) = 0 then
    return NEW;
  end if;

  -- Repõe as colunas sensíveis ao valor antigo; o resto do UPDATE segue.
  NEW := jsonb_populate_record(NEW, (select jsonb_object_agg(k, v_old -> k) from unnest(v_mudadas) k));

  begin
    insert into public.e2e_log (fluxo, passo, estado, detalhe, device)
    values ('prestador-colunas-guarda', tg_table_name, 'bloqueado',
            format('user %s tentou mudar %s em %s (reposto ao valor antigo)',
                   coalesce(auth.uid()::text, 'sem-sessao'), array_to_string(v_mudadas, ', '), tg_table_name),
            'trigger');
  exception when others then
    null; -- o registo é melhor-esforço
  end;

  return NEW;
end
$fn$;

comment on function public._prestador_colunas_guarda() is
  '01/11/2026 seguranca-05: BEFORE UPDATE nas tabelas dos prestadores; quando quem escreve é o papel da app e não é admin, repõe as colunas passadas como argumentos ao valor de OLD.';

-- ── washers ─────────────────────────────────────────────────────────────────────────────────
drop trigger if exists a00_colunas_guarda on public.washers;
create trigger a00_colunas_guarda
  before update on public.washers
  for each row execute function public._prestador_colunas_guarda(
    'id', 'user_id',
    'approval_status', 'approved_at', 'approved_by', 'rejection_reason',
    'is_banned', 'ban_reason', 'banned_at',
    'rating_avg', 'ratings_count', 'washes_done', 'flagged_low_rating',
    'nif', 'iban', 'mbway_phone');

-- ── drivers ─────────────────────────────────────────────────────────────────────────────────
drop trigger if exists a00_colunas_guarda on public.drivers;
create trigger a00_colunas_guarda
  before update on public.drivers
  for each row execute function public._prestador_colunas_guarda(
    'id', 'user_id',
    'approval_status', 'approved_at', 'approved_by', 'rejection_reason', 'reviewed_at',
    'is_banned', 'banned_at', 'banned_by', 'banned_until', 'ban_reason_code', 'ban_reason',
    'deleted_at', 'deleted_by', 'deletion_reason',
    'last_forced_logout_at', 'last_forced_logout_by',
    'nif', 'iban', 'mbway_phone', 'payment_method',
    'token_balance', 'debt_cents', 'blocked_for_debt',
    'avg_rating', 'ratings_count',
    'stripe_account_id', 'stripe_account_status', 'stripe_charges_enabled', 'stripe_payouts_enabled',
    'stripe_requirements', 'stripe_onboarded_at',
    'tvde_operator_id');

-- ── cleaners ────────────────────────────────────────────────────────────────────────────────
drop trigger if exists a00_colunas_guarda on public.cleaners;
create trigger a00_colunas_guarda
  before update on public.cleaners
  for each row execute function public._prestador_colunas_guarda(
    'id', 'user_id',
    'approval_status', 'approved_at', 'approved_by', 'rejection_reason',
    'rating_avg', 'ratings_count', 'cleanings_done', 'flagged_low_rating',
    'nif', 'iban', 'mbway_phone',
    'stripe_account_id', 'stripe_account_status', 'stripe_charges_enabled', 'stripe_payouts_enabled',
    'stripe_requirements', 'stripe_onboarded_at');

-- ── service_providers (barbearias/serviços) ─────────────────────────────────────────────────
drop trigger if exists a00_colunas_guarda on public.service_providers;
create trigger a00_colunas_guarda
  before update on public.service_providers
  for each row execute function public._prestador_colunas_guarda(
    'id', 'user_id',
    'approval_status', 'approved_at', 'approved_by', 'rejection_reason',
    'is_active_admin',
    'avg_rating', 'ratings_count',
    'nif', 'iban', 'mbway_phone',
    'stripe_account_id', 'stripe_account_status', 'stripe_charges_enabled', 'stripe_payouts_enabled',
    'stripe_requirements', 'stripe_onboarded_at');

-- ── casa_profissionais (Casa & Manutenção) ──────────────────────────────────────────────────
-- is_active aqui é do ADMIN (casa_05_admin: suspended/banned → is_active=false); sem_comissao_ate é comissão.
drop trigger if exists a00_colunas_guarda on public.casa_profissionais;
create trigger a00_colunas_guarda
  before update on public.casa_profissionais
  for each row execute function public._prestador_colunas_guarda(
    'id', 'user_id',
    'approval_status', 'approved_at', 'approved_by', 'rejection_reason',
    'is_active', 'sem_comissao_ate',
    'rating_avg', 'ratings_count', 'jobs_done',
    'nif', 'iban');

-- PROVA (correr depois de aplicar):
--   select tgrelid::regclass as tabela, tgname from pg_trigger
--     where tgname = 'a00_colunas_guarda' and not tgisinternal order by 1;
--   -- esperado: 5 linhas (casa_profissionais, cleaners, drivers, service_providers, washers)
--
--   -- Teste funcional (numa transação, SEM commit — rollback no fim):
--   begin;
--   select set_config('request.jwt.claims', json_build_object('sub', w.user_id, 'role', 'authenticated')::text, true)
--     from public.washers w where w.approval_status = 'pending' limit 1;   -- um lavador pendente real
--   set local role authenticated;
--   update public.washers set approval_status = 'approved', is_banned = false, iban = 'PT50000000000000000000000'
--     where user_id = (current_setting('request.jwt.claims', true)::json ->> 'sub')::uuid
--     returning approval_status, iban;
--   -- esperado: approval_status continua 'pending' e o iban continua o antigo (o UPDATE "passa" mas sem efeito)
--   reset role;
--   select fluxo, passo, estado, detalhe from public.e2e_log where fluxo = 'prestador-colunas-guarda' order by id desc limit 1;
--   -- esperado: 1 linha 'bloqueado' a dizer "tentou mudar approval_status, is_banned, iban em washers"
--   rollback;
--
--   -- Caminho da app continua a funcionar (RPC definer): o mesmo lavador chama provider_update_legal_fields
--   -- com um IBAN novo e o IBAN muda (current_user = postgres dentro da RPC → o gatilho não interfere).
