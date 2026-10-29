-- ════════════════════════════════════════════════════════════════════════════
-- PROPOSTA (NÃO APLICADA) — C6 modo ocupado: o despacho soma o tempo ao chamar o estafeta
-- Missão geral 28/10 · item 6 do plano do Danilo (adendo 5, 29/10/2026)
-- ════════════════════════════════════════════════════════════════════════════
--
-- ZONA PROTEGIDA (dispatch): a regra de QUANDO se chama o estafeta nos pedidos de parceiro
-- (migração 20261004193649: aceite + preparação − 8 min) não se altera na missão. Este
-- ficheiro só PROPÕE. Um revisor independente decide antes de se aplicar. Nada de dinheiro.
--
-- DEPENDE de: supabase/migrations/20261029200600_c6_modo_ocupado.sql já aplicada
-- (traz orders.ready_at_promised e partner_busy_extra_minutes()).
--
-- ANTES DE APLICAR, o revisor deve:
--   1. comparar a função VIVA com a do repo (o repo pode estar atrás do ar):
--        select pg_get_functiondef('public.partner_auto_dispatch_ready_orders()'::regprocedure);
--        select pg_get_functiondef('public._orders_set_accepted_at()'::regprocedure);
--      e confirmar que o corpo de baixo só difere no que está marcado "C6";
--   2. correr a prova em transação desfeita (fim deste ficheiro): tem de acabar em
--      "PROVA OK" e a transação é sempre desfeita (ROLLBACK), por isso não deixa rasto.
--
-- O QUE MUDA (e só com o interruptor partner_busy_mode_enabled ligado, porque sem ele
-- partner_busy_extra_minutes() devolve 0 e ninguém põe ready_at_promised):
--   A. orders.busy_extra_applied — o extra do modo ocupado, "fotografado" no momento em
--      que a loja aceita. Fotografar (e não ler ao vivo) evita atrasar pedidos que a loja
--      já aceitou antes de ligar o modo, ou apressar os que aceitou ocupada.
--   B. _partner_chamada_due_at(...) — a conta "a que horas chamar" passa a uma função só
--      (a mesma CASE de hoje + os dois acrescentos C6). Sem ready_at_promised e com
--      busy_extra_applied = 0 dá EXATAMENTE a hora de hoje (a prova compara numa grelha).
--   C. partner_auto_dispatch_ready_orders() usa a função B no WHERE. Resto igual.
--   D. _orders_set_accepted_at() fotografa busy_extra_applied ao aceitar (trigger já
--      existente; falhar a leitura nunca trava o aceitar: cai para 0).
--
-- REGRA NOVA (por esta ordem):
--   • com scheduled_for (agendado / encomenda de festa):
--       chama em scheduled_for − 30 (como hoje). Se a loja prometeu "fica pronto às HH:MM"
--       mais tarde que isso, chama em MAX(scheduled_for − 30, ready_at_promised − 8);
--   • sem data marcada, com "fica pronto às HH:MM":
--       chama em ready_at_promised − dispatch_antecedencia_minutos (8);
--   • sem data marcada e com tempo de preparação:
--       chama em accepted_at + max(0, prep − 8) + busy_extra_applied;
--   • sem preparação nem promessa:
--       chama em accepted_at + partner_auto_dispatch_after_minutes (5) + busy_extra_applied.
--   O parceiro pode sempre carregar "Chamar estafeta já". Pedido já em callingDriver não
--   é recalculado (o botão "fica pronto às" só aparece em pedidos em preparação).
--
-- COMO DESFAZER: restaurar das cópias (passo 0):
--   do $$ begin
--     execute (select definicao from public.bkp_fn_partner_auto_dispatch_ready_orders_20261029 limit 1);
--     execute (select definicao from public.bkp_fn__orders_set_accepted_at_20261029 limit 1);
--   end $$;
--   (a coluna e a função auxiliar podem ficar: sem uso, não fazem nada.)
-- ════════════════════════════════════════════════════════════════════════════

-- ── 0) BACKUP das duas funções (bkp_fn_<nome>_20261029) ─────────────────────
create table if not exists public.bkp_fn_partner_auto_dispatch_ready_orders_20261029 as
  select now() as guardado_em,
         'partner_auto_dispatch_ready_orders()'::text as funcao,
         pg_get_functiondef('public.partner_auto_dispatch_ready_orders()'::regprocedure) as definicao;
create table if not exists public.bkp_fn__orders_set_accepted_at_20261029 as
  select now() as guardado_em,
         '_orders_set_accepted_at()'::text as funcao,
         pg_get_functiondef('public._orders_set_accepted_at()'::regprocedure) as definicao;
alter table public.bkp_fn_partner_auto_dispatch_ready_orders_20261029 enable row level security;
alter table public.bkp_fn__orders_set_accepted_at_20261029 enable row level security;

-- ── A) Coluna: o extra do modo ocupado fotografado ao aceitar ───────────────
alter table public.orders
  add column if not exists busy_extra_applied integer not null default 0;
comment on column public.orders.busy_extra_applied is
  'C6 modo ocupado: minutos do modo ocupado da loja no instante em que aceitou o pedido (0 se nao estava ocupada ou o interruptor estava desligado). O despacho soma-os a preparacao.';

-- ── B) A conta "a que horas chamar o estafeta", numa função só ──────────────
-- p_base = COALESCE(accepted_at, status_updated_at).
-- STABLE e não IMMUTABLE: soma intervalos a timestamptz.
create or replace function public._partner_chamada_due_at(
  p_base               timestamptz,
  p_scheduled_for      timestamptz,
  p_ready_at_promised  timestamptz,
  p_prep_time_minutes  integer,
  p_busy_extra         integer,
  p_min                integer,
  p_ant                integer,
  p_ant_ag             integer
) returns timestamptz
language sql
stable
set search_path to ''
as $fn$
  select case
    when p_scheduled_for is not null then
      greatest(
        p_scheduled_for - make_interval(mins => p_ant_ag),
        coalesce(p_ready_at_promised - make_interval(mins => p_ant), '-infinity'::timestamptz))
    when p_ready_at_promised is not null then
      p_ready_at_promised - make_interval(mins => p_ant)
    when p_prep_time_minutes is not null then
      p_base + make_interval(mins => greatest(0, p_prep_time_minutes - p_ant)
                                      + greatest(coalesce(p_busy_extra, 0), 0))
    else
      p_base + make_interval(mins => p_min + greatest(coalesce(p_busy_extra, 0), 0))
  end;
$fn$;
revoke all on function public._partner_chamada_due_at(timestamptz, timestamptz, timestamptz, integer, integer, integer, integer, integer)
  from public, anon, authenticated;
grant execute on function public._partner_chamada_due_at(timestamptz, timestamptz, timestamptz, integer, integer, integer, integer, integer)
  to service_role;

-- ── C) O cron: igual ao de 20261004193649, só o WHERE chama a função B ──────
CREATE OR REPLACE FUNCTION public.partner_auto_dispatch_ready_orders()
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
DECLARE
  v_min     integer;
  v_ant     integer;
  v_ant_ag  integer;
  v_order   record;
BEGIN
  SELECT (value::text)::integer INTO v_min
    FROM public.platform_settings
   WHERE key = 'partner_auto_dispatch_after_minutes';
  v_min := COALESCE(v_min, 5);
  IF v_min <= 0 THEN RETURN; END IF;   -- interruptor: 0 desliga a chamada automática

  SELECT (value::text)::integer INTO v_ant
    FROM public.platform_settings WHERE key = 'dispatch_antecedencia_minutos';
  v_ant := GREATEST(COALESCE(v_ant, 8), 0);
  SELECT (value::text)::integer INTO v_ant_ag
    FROM public.platform_settings WHERE key = 'dispatch_antecedencia_agendado_minutos';
  v_ant_ag := GREATEST(COALESCE(v_ant_ag, 30), 0);

  FOR v_order IN
    SELECT id
      FROM public.orders
     WHERE status = 'preparing'
       AND COALESCE(is_partner_store, false)
       AND service_type = 'restaurant'
       AND assigned_driver_id IS NULL
       AND driver_id IS NULL
       AND (COALESCE(payment_method, 'cash') = 'cash' OR payment_status = 'paid')
       -- C6: a mesma conta de antes, agora numa função (+ ready_at_promised + busy_extra_applied).
       AND now() >= public._partner_chamada_due_at(
             COALESCE(accepted_at, status_updated_at),
             scheduled_for,
             ready_at_promised,
             prep_time_minutes,
             busy_extra_applied,
             v_min, v_ant, v_ant_ag)
     ORDER BY COALESCE(accepted_at, status_updated_at)
     LIMIT 50
     FOR UPDATE SKIP LOCKED
  LOOP
    BEGIN
      PERFORM set_config('app.order_transition_source',
                         'partner_auto_dispatch_ready_orders', true);
      UPDATE public.orders SET status = 'callingDriver'
       WHERE id = v_order.id AND status = 'preparing';
    EXCEPTION WHEN OTHERS THEN
      INSERT INTO public.order_lifecycle_errors(
        order_id, component, error_message
      ) VALUES (
        v_order.id, 'partner_auto_dispatch_ready_orders', SQLERRM
      );
    END;
  END LOOP;
END;
$function$;

-- ── D) O trigger de aceitar: fotografa o extra do modo ocupado ──────────────
-- Igual a 20261004193649 + o bloco C6. Corre como quem aceita (o parceiro): por isso
-- partner_busy_extra_minutes() tem EXECUTE para authenticated.
CREATE OR REPLACE FUNCTION public._orders_set_accepted_at()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO 'public', 'pg_temp'
AS $function$
BEGIN
  IF NEW.status = 'preparing'
     AND NEW.accepted_at IS NULL
     AND (TG_OP = 'INSERT' OR OLD.status IS DISTINCT FROM 'preparing') THEN
    NEW.accepted_at := now();
    -- C6 modo ocupado: fotografa os minutos extra da loja (0 se desligado). Nunca trava o aceitar.
    IF COALESCE(NEW.is_partner_store, false) AND NEW.restaurant_id IS NOT NULL THEN
      BEGIN
        NEW.busy_extra_applied := COALESCE(public.partner_busy_extra_minutes(NEW.restaurant_id), 0);
      EXCEPTION WHEN OTHERS THEN
        NEW.busy_extra_applied := 0;
      END;
    END IF;
  END IF;
  RETURN NEW;
END;
$function$;

-- ════════════════════════════════════════════════════════════════════════════
-- PARTE 2 — PROVA EM TRANSAÇÃO DESFEITA (corre depois da PARTE 1; não deixa rasto)
-- ════════════════════════════════════════════════════════════════════════════
-- Ensaio sem rasto nenhum (PARTE 1 + PARTE 2 de uma vez): escrever BEGIN; antes de tudo e
-- ROLLBACK; no fim. DDL em Postgres desfaz-se com a transação.
-- A prova acaba com NOTICE "PROVA C6 DESPACHO OK" ou com EXCEPTION a dizer o que falhou.
-- Os pedaços que escrevem dados correm dentro de um sub-bloco que se desfaz sempre
-- (RAISE 'PROVA_DESFEITA'), e o pedido de teste vive numa tabela temporária: nenhum pedido
-- real é criado nem tocado, por isso ninguém real recebe uma oferta.

-- 2.1) A conta nova = a conta de hoje (sem promessa e sem modo ocupado), numa grelha.
do $prova$
declare
  v_base  constant timestamptz := '2026-10-29 12:00:00+00';
  v_sched timestamptz;
  v_prep  integer;
  v_velho timestamptz;
  v_novo  timestamptz;
  v_casos integer := 0;
  v_dif   integer := 0;
begin
  foreach v_sched in array array[null, '2026-10-30 19:00:00+00'::timestamptz, '2026-10-29 12:20:00+00'::timestamptz] loop
    foreach v_prep in array array[null, 0, 5, 8, 15, 30, 120] loop
      -- a CASE de 20261004193649, com v_min = 5, v_ant = 8, v_ant_ag = 30
      v_velho := case
        when v_sched is not null then v_sched - make_interval(mins => 30)
        when v_prep  is not null then v_base + make_interval(mins => greatest(0, v_prep - 8))
        else v_base + make_interval(mins => 5)
      end;
      v_novo := public._partner_chamada_due_at(v_base, v_sched, null, v_prep, 0, 5, 8, 30);
      v_casos := v_casos + 1;
      if v_novo is distinct from v_velho then
        v_dif := v_dif + 1;
        raise warning 'DIFERE: sched=% prep=% velho=% novo=%', v_sched, v_prep, v_velho, v_novo;
      end if;
    end loop;
  end loop;
  if v_dif > 0 then
    raise exception 'PROVA C6 FALHOU: % de % casos diferem da regra de hoje', v_dif, v_casos;
  end if;
  raise notice '2.1 OK: % casos iguais a regra de hoje', v_casos;
end $prova$;

-- 2.2) A regra nova, valores exatos (minutos depois de v_base).
do $prova$
declare
  v_base constant timestamptz := '2026-10-29 12:00:00+00';
begin
  -- prep 15 − 8 = 7, + modo ocupado 20 = 27 min
  if public._partner_chamada_due_at(v_base, null, null, 15, 20, 5, 8, 30) <> v_base + interval '27 minutes' then
    raise exception 'PROVA C6 FALHOU: prep 15 + ocupado 20 devia dar +27 min'; end if;
  -- prep 5 (< 8): max(0, −3) = 0, + ocupado 10 = 10 min
  if public._partner_chamada_due_at(v_base, null, null, 5, 10, 5, 8, 30) <> v_base + interval '10 minutes' then
    raise exception 'PROVA C6 FALHOU: prep 5 + ocupado 10 devia dar +10 min'; end if;
  -- sem prep: 5 + ocupado 10 = 15 min
  if public._partner_chamada_due_at(v_base, null, null, null, 10, 5, 8, 30) <> v_base + interval '15 minutes' then
    raise exception 'PROVA C6 FALHOU: sem prep + ocupado 10 devia dar +15 min'; end if;
  -- fica pronto às base+40: chama em base+32 (o modo ocupado NÃO se soma à hora prometida)
  if public._partner_chamada_due_at(v_base, null, v_base + interval '40 minutes', 15, 30, 5, 8, 30) <> v_base + interval '32 minutes' then
    raise exception 'PROVA C6 FALHOU: pronto às +40 devia dar +32 min'; end if;
  -- agendado +300, promessa +320: o mais tarde dos dois (+312), nunca antes de +270
  if public._partner_chamada_due_at(v_base, v_base + interval '300 minutes', v_base + interval '320 minutes', 15, 0, 5, 8, 30) <> v_base + interval '312 minutes' then
    raise exception 'PROVA C6 FALHOU: agendado +300 e promessa +320 devia dar +312 min'; end if;
  -- agendado +300, promessa +100 (cedo demais): mantém scheduled − 30 = +270
  if public._partner_chamada_due_at(v_base, v_base + interval '300 minutes', v_base + interval '100 minutes', 15, 0, 5, 8, 30) <> v_base + interval '270 minutes' then
    raise exception 'PROVA C6 FALHOU: agendado +300 e promessa +100 devia dar +270 min'; end if;
  -- modo ocupado negativo ou nulo nunca adianta
  if public._partner_chamada_due_at(v_base, null, null, 15, -50, 5, 8, 30) <> v_base + interval '7 minutes' then
    raise exception 'PROVA C6 FALHOU: extra negativo devia contar 0'; end if;
  if public._partner_chamada_due_at(v_base, null, null, 15, null, 5, 8, 30) <> v_base + interval '7 minutes' then
    raise exception 'PROVA C6 FALHOU: extra nulo devia contar 0'; end if;
  raise notice '2.2 OK: regra nova com valores exatos';
end $prova$;

-- 2.3) O trigger de aceitar fotografa o extra (tabela temporária com as colunas que ele lê).
do $prova$
declare
  v_rest text;
  v_extra integer;
begin
  select id into v_rest from public.restaurants limit 1;
  if v_rest is null then
    raise notice '2.3 SALTADO: nao ha restaurantes na base';
    return;
  end if;
  begin
    create temp table t_pedido(
      id serial, status text, accepted_at timestamptz, is_partner_store boolean,
      restaurant_id text, busy_extra_applied integer not null default 0
    ) on commit drop;
    create trigger t_aceitar before insert or update of status on t_pedido
      for each row execute function public._orders_set_accepted_at();

    -- interruptor LIGADO e loja ocupada +20 por 1 hora
    update public.platform_settings set value = 'true'::jsonb where key = 'partner_busy_mode_enabled';
    update public.restaurants set busy_extra_minutes = 20, busy_until = now() + interval '1 hour' where id = v_rest;
    insert into t_pedido(status, is_partner_store, restaurant_id) values ('preparing', true, v_rest);
    select busy_extra_applied into v_extra from t_pedido order by id desc limit 1;
    if v_extra <> 20 then
      raise exception 'PROVA C6 FALHOU: com o modo ligado devia fotografar 20, deu %', v_extra; end if;

    -- interruptor DESLIGADO: fotografa 0 (nada muda)
    update public.platform_settings set value = 'false'::jsonb where key = 'partner_busy_mode_enabled';
    insert into t_pedido(status, is_partner_store, restaurant_id) values ('preparing', true, v_rest);
    select busy_extra_applied into v_extra from t_pedido order by id desc limit 1;
    if v_extra <> 0 then
      raise exception 'PROVA C6 FALHOU: com o modo desligado devia fotografar 0, deu %', v_extra; end if;

    -- loja que não é parceira: não fotografa
    update public.platform_settings set value = 'true'::jsonb where key = 'partner_busy_mode_enabled';
    insert into t_pedido(status, is_partner_store, restaurant_id) values ('preparing', false, v_rest);
    select busy_extra_applied into v_extra from t_pedido order by id desc limit 1;
    if v_extra <> 0 then
      raise exception 'PROVA C6 FALHOU: loja nao parceira devia ficar 0, deu %', v_extra; end if;

    raise notice '2.3 OK: o aceitar fotografa 20 / 0 / 0';
    raise exception 'PROVA_DESFEITA';
  exception when others then
    if sqlerrm <> 'PROVA_DESFEITA' then raise; end if;
  end;
end $prova$;

do $$ begin raise notice 'PROVA C6 DESPACHO OK'; end $$;
