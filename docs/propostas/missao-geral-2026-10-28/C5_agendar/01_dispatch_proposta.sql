-- ============================================================================
-- C5 · PROPOSTA 01 — DESPACHO: a hora de chamar o estafeta conta a partir da hora agendada
-- Item 5 do adendo 5 do Danilo (29/10/2026). NÃO APLICADA.
--
-- ⚠️ ZONA DE DESPACHO. Mexe na função partner_auto_dispatch_ready_orders (o cron que passa os pedidos de
--    parceiro de "preparing" a "callingDriver"). Revisor independente OBRIGATÓRIO antes de aplicar e antes
--    de ligar o interruptor. Nada disto muda com o interruptor `scheduled_orders_enabled` DESLIGADO
--    (prova na PARTE 3, caso a caso).
--
-- A REGRA DO DANILO (literal): "a regra atual (aceite + preparação − 8 min, migração 20261004193649) passa a
-- contar a partir da hora agendada; estafeta chamado na hora certa".
--
-- COMO LI A REGRA (decisão a confirmar pelo revisor/Danilo — está num único sítio, na função auxiliar):
--   • A hora marcada (orders.scheduled_for = início da janela de 30 min) é a hora a que o pedido deve estar
--     PRONTO NA LOJA. Hoje o "pronto" é aceite + preparação; nos agendados passa a ser a hora marcada
--     ("o aceite passa a contar a partir da hora agendada").
--   • O estafeta é chamado 8 min antes de o pedido estar pronto (dispatch_antecedencia_minutos, igual a hoje):
--         chamar_em = MAIOR( hora_marcada − viagem ,  aceite + preparação )  −  8 min
--     O MAIOR protege o caso de a loja aceitar tarde: nunca se chama antes de o pedido poder estar pronto.
--   • `dispatch_agendado_viagem_minutos` (novo, 0 por defeito) é o botão único para o caso de o Danilo querer
--     que a janela seja a hora de CHEGADA ao cliente: pôr 10, 15... e o pedido fica pronto mais cedo.
--     Com 0, a janela de 30 min escolhida cobre a recolha e a entrega (a entrega cai dentro dos 30 min).
--   • Sem tempo de preparação definido (prep_time_minutes nulo) mantém-se a regra de hoje para agendados:
--     hora marcada − 30 min (dispatch_antecedencia_agendado_minutos).
--   • Lojas de FESTAS ficam fora (têm a sua regra, hora marcada − 30 min), e tudo o que não tem hora marcada
--     fica byte a byte como hoje.
--
-- ANTES DE APLICAR (ler a definição VIVA — a do repo é a de 04/10 e pode estar atrás da produção):
--   select md5(pg_get_functiondef('public.partner_auto_dispatch_ready_orders()'::regprocedure));
--   select pg_get_functiondef('public.partner_auto_dispatch_ready_orders()'::regprocedure);
--   -- tem de bater (a menos de espaços) com a da migração 20261004193649 (FOR ... LOOP com CASE scheduled_for/
--   -- prep_time_minutes). Se a viva for outra, parar e rever a PARTE 2 contra ela.
--   select jobname, schedule, command from cron.job where command ilike '%partner_auto_dispatch%';
--   -- confirmar que o cron existe e a cada quanto corre (a chamada acontece no minuto do cron, não ao segundo).
--
-- COMO USAR ESTE FICHEIRO
--   PARTE 3 (prova)  : correr SOZINHA primeiro. Cria a função auxiliar numa transação que ela própria desfaz
--                      (DO + RAISE) e devolve a tabela de casos. Nada fica gravado.
--   PARTE 1 + PARTE 2: só depois do SIM do revisor. Backup + definição nova. Aplicar com o "vai" do Danilo.
--   REVERSÃO         : PARTE 4.
-- ============================================================================


-- ============================================================================
-- PARTE 1 — Backup (bkp_fn_<nome>_20261029) e a definição nova da regra
-- ============================================================================
CREATE TABLE IF NOT EXISTS public.bkp_fn_partner_auto_dispatch_ready_orders_20261029 AS
  SELECT now() AS guardado_em,
         pg_get_functiondef('public.partner_auto_dispatch_ready_orders()'::regprocedure) AS def;
ALTER TABLE public.bkp_fn_partner_auto_dispatch_ready_orders_20261029 ENABLE ROW LEVEL SECURITY;  -- sem política: ninguém lê pela API

INSERT INTO public.platform_settings (key, value, description, category) VALUES
  ('dispatch_agendado_viagem_minutos', '0'::jsonb,
   'Pedidos agendados: minutos a tirar à hora marcada para saber quando o pedido deve estar PRONTO (0 = a hora marcada é a hora de recolha).',
   'dispatch')
ON CONFLICT (key) DO NOTHING;


-- ============================================================================
-- PARTE 2 — A função auxiliar (pura) e o cron com a regra nova
-- ============================================================================

-- A regra num só sítio. Pura (sem tabelas): por isso a prova da PARTE 3 é exata.
CREATE OR REPLACE FUNCTION public._partner_dispatch_chamar_em(
  p_scheduled_for  timestamptz,   -- orders.scheduled_for
  p_prep_min       integer,       -- orders.prep_time_minutes
  p_ref_aceite     timestamptz,   -- COALESCE(accepted_at, status_updated_at)
  p_min_sem_prep   integer,       -- partner_auto_dispatch_after_minutes (5)
  p_ant            integer,       -- dispatch_antecedencia_minutos (8)
  p_ant_agendado   integer,       -- dispatch_antecedencia_agendado_minutos (30)
  p_regra_nova     boolean,       -- interruptor ligado E a loja não é de festas
  p_viagem         integer        -- dispatch_agendado_viagem_minutos (0)
) RETURNS timestamptz
 LANGUAGE sql
 IMMUTABLE
AS $function$
  SELECT CASE
    -- Agendado, regra nova: pronto à hora marcada (ou quando der, se a loja aceitou tarde); chama 8 min antes.
    WHEN p_scheduled_for IS NOT NULL AND p_regra_nova AND p_prep_min IS NOT NULL THEN
      GREATEST(
        GREATEST(p_scheduled_for - make_interval(mins => p_viagem),
                 p_ref_aceite + make_interval(mins => p_prep_min))
          - make_interval(mins => p_ant),
        p_ref_aceite)
    -- Agendado, regra de hoje (festas, interruptor desligado, ou sem tempo de preparação).
    WHEN p_scheduled_for IS NOT NULL THEN
      p_scheduled_for - make_interval(mins => p_ant_agendado)
    -- Imediato com tempo de preparação: igual a hoje.
    WHEN p_prep_min IS NOT NULL THEN
      p_ref_aceite + make_interval(mins => GREATEST(0, p_prep_min - p_ant))
    -- Imediato sem tempo de preparação: igual a hoje.
    ELSE
      p_ref_aceite + make_interval(mins => p_min_sem_prep)
  END
$function$;

REVOKE ALL ON FUNCTION public._partner_dispatch_chamar_em(timestamptz, integer, timestamptz, integer, integer, integer, boolean, integer)
  FROM PUBLIC, anon, authenticated;

-- A função do cron: igual à de 20261004193649, com a conta a sair da função auxiliar.
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
  v_viagem  integer;
  v_novo    boolean;
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

  -- C5 (29/10/2026): regra nova dos agendados só com o interruptor ligado.
  SELECT (value::text)::integer INTO v_viagem
    FROM public.platform_settings WHERE key = 'dispatch_agendado_viagem_minutos';
  v_viagem := GREATEST(COALESCE(v_viagem, 0), 0);
  SELECT COALESCE((value #>> '{}')::boolean, false) INTO v_novo
    FROM public.platform_settings WHERE key = 'scheduled_orders_enabled';
  v_novo := COALESCE(v_novo, false);

  FOR v_order IN
    SELECT o.id
      FROM public.orders o
     WHERE o.status = 'preparing'
       AND COALESCE(o.is_partner_store, false)
       AND o.service_type = 'restaurant'
       AND o.assigned_driver_id IS NULL
       AND o.driver_id IS NULL
       AND (COALESCE(o.payment_method, 'cash') = 'cash' OR o.payment_status = 'paid')
       AND now() >= public._partner_dispatch_chamar_em(
             o.scheduled_for,
             o.prep_time_minutes,
             COALESCE(o.accepted_at, o.status_updated_at),
             v_min, v_ant, v_ant_ag,
             v_novo AND NOT EXISTS (SELECT 1 FROM public.restaurants r
                                     WHERE r.id = o.restaurant_id AND r.category = 'festas'),
             v_viagem)
     ORDER BY COALESCE(o.accepted_at, o.status_updated_at)
     LIMIT 50
     FOR UPDATE OF o SKIP LOCKED
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
-- As permissões da função do cron mantêm-se (CREATE OR REPLACE não as muda).


-- ============================================================================
-- PARTE 3 — PROVA numa transação que se desfaz sozinha (DO + RAISE)
--   Correr o bloco abaixo SOZINHO (tirar o /* e o */), antes de aplicar as outras partes.
--   Termina SEMPRE com um erro "PROVA ...": isso é o rollback propositado, e o texto do erro é a tabela de
--   resultados. Não escreve em nenhuma tabela e não toca em nenhum pedido real.
--   Se a sessão ficar numa transação abortada, correr ROLLBACK;
-- ============================================================================
/*
BEGIN;

CREATE OR REPLACE FUNCTION public._partner_dispatch_chamar_em(
  p_scheduled_for timestamptz, p_prep_min integer, p_ref_aceite timestamptz, p_min_sem_prep integer,
  p_ant integer, p_ant_agendado integer, p_regra_nova boolean, p_viagem integer
) RETURNS timestamptz LANGUAGE sql IMMUTABLE AS $f$
  SELECT CASE
    WHEN p_scheduled_for IS NOT NULL AND p_regra_nova AND p_prep_min IS NOT NULL THEN
      GREATEST(GREATEST(p_scheduled_for - make_interval(mins => p_viagem),
                        p_ref_aceite + make_interval(mins => p_prep_min)) - make_interval(mins => p_ant), p_ref_aceite)
    WHEN p_scheduled_for IS NOT NULL THEN p_scheduled_for - make_interval(mins => p_ant_agendado)
    WHEN p_prep_min IS NOT NULL THEN p_ref_aceite + make_interval(mins => GREATEST(0, p_prep_min - p_ant))
    ELSE p_ref_aceite + make_interval(mins => p_min_sem_prep)
  END $f$;

DO $prova$
DECLARE
  ref    timestamptz := '2026-11-07 17:00+00';   -- hora de aceite
  sab    timestamptz := '2026-11-07 19:00+00';   -- hora marcada
  c      record;
  obtido timestamptz;
  txt    text := '';
  falhas int := 0;
  total  int := 0;
  hoje   timestamptz;       -- a regra de HOJE (20261004193649), escrita à parte para comparar
  s_ts   timestamptz;
  p_prep int;
  a_ref  timestamptz;
  n_igual int := 0;
  n_total int := 0;
BEGIN
  -- A) Casos escritos à mão (regra nova ligada, salvo indicação). Parâmetros do servidor: 5 / 8 / 30.
  FOR c IN
    SELECT * FROM (VALUES
      ('imediato, prep 20 (aceite+12)',                         NULL::timestamptz, 20,        ref,                                 true,   0, ref + interval '12 minutes'),
      ('imediato, sem prep (aceite+5)',                         NULL::timestamptz, NULL::int, ref,                                 true,   0, ref + interval '5 minutes'),
      ('agendado, interruptor DESLIGADO (−30)',                 sab,               20,        ref,                                 false,  0, sab - interval '30 minutes'),
      ('agendado, ligado, aceite cedo (pronto 19:00 → 18:52)',  sab,               20,        ref,                                 true,   0, sab - interval '8 minutes'),
      ('agendado, ligado, aceite TARDE 18:55 (pronto 19:15 → 19:07)', sab,         20,        '2026-11-07 18:55+00'::timestamptz,  true,   0, '2026-11-07 19:07+00'::timestamptz),
      ('agendado, ligado, sem prep (−30 como hoje)',            sab,               NULL::int, ref,                                 true,   0, sab - interval '30 minutes'),
      ('agendado, ligado, prep 5, aceite 19:00 (nunca antes do aceite)', sab,      5,         sab,                                 true,   0, sab),
      ('agendado, ligado, viagem 10 (pronto 18:50 → 18:42)',    sab,               20,        ref,                                 true,  10, sab - interval '18 minutes'),
      ('festas (regra nova desligada p/ a loja) agendado (−30)', sab,              20,        ref,                                 false,  0, sab - interval '30 minutes')
    ) AS t(nome, ag, pr, ac, novo, viagem, esperado)
  LOOP
    obtido := public._partner_dispatch_chamar_em(c.ag, c.pr, c.ac, 5, 8, 30, c.novo, c.viagem);
    total := total + 1;
    IF obtido IS NOT DISTINCT FROM c.esperado THEN
      txt := txt || 'OK    ' || c.nome || ' → ' || obtido::text || E'\n';
    ELSE
      falhas := falhas + 1;
      txt := txt || 'FALHA ' || c.nome || ' → obtido ' || COALESCE(obtido::text, 'NULL')
                 || ' esperado ' || c.esperado::text || E'\n';
    END IF;
  END LOOP;

  -- B) EQUIVALÊNCIA com a regra de hoje quando a regra nova está DESLIGADA: uma grelha de 36 combinações
  --    tem de dar exatamente o mesmo que o CASE da migração 20261004193649.
  FOR s_ts IN SELECT unnest(ARRAY[NULL::timestamptz, sab, ref + interval '1 day']) LOOP
    FOR p_prep IN SELECT unnest(ARRAY[NULL::int, 0, 5, 8, 20, 45]) LOOP
      FOR a_ref IN SELECT unnest(ARRAY[ref, ref + interval '3 hours']) LOOP
        hoje := CASE
                  WHEN s_ts IS NOT NULL THEN s_ts - make_interval(mins => 30)
                  WHEN p_prep IS NOT NULL THEN a_ref + make_interval(mins => GREATEST(0, p_prep - 8))
                  ELSE a_ref + make_interval(mins => 5)
                END;
        n_total := n_total + 1;
        IF public._partner_dispatch_chamar_em(s_ts, p_prep, a_ref, 5, 8, 30, false, 0) IS NOT DISTINCT FROM hoje THEN
          n_igual := n_igual + 1;
        ELSE
          falhas := falhas + 1;
          txt := txt || 'FALHA equivalência s=' || COALESCE(s_ts::text, 'NULL') || ' p=' || COALESCE(p_prep::text, 'NULL')
                     || ' a=' || a_ref::text || E'\n';
        END IF;
      END LOOP;
    END LOOP;
  END LOOP;
  txt := txt || 'Equivalência com a regra de hoje (interruptor desligado): ' || n_igual || '/' || n_total || E'\n';

  IF falhas = 0 THEN
    RAISE EXCEPTION 'PROVA OK — % casos à mão + % combinações. (rollback propositado)%', total, n_total, E'\n' || txt;
  ELSE
    RAISE EXCEPTION 'PROVA FALHOU — % falhas. (rollback propositado)%', falhas, E'\n' || txt;
  END IF;
END
$prova$;
ROLLBACK;
*/


-- ============================================================================
-- PARTE 4 — REVERSÃO (se alguma coisa correr mal depois de aplicar)
--   A definição antiga está em public.bkp_fn_partner_auto_dispatch_ready_orders_20261029.
-- ============================================================================
/*
DO $rev$
BEGIN
  EXECUTE (SELECT def FROM public.bkp_fn_partner_auto_dispatch_ready_orders_20261029 ORDER BY guardado_em LIMIT 1);
END
$rev$;
-- (a função auxiliar _partner_dispatch_chamar_em pode ficar: já ninguém a chama.)
-- Ou, mais simples e sem tocar na função: desligar o interruptor no painel (Pedidos agendados) — a regra nova
-- só corre com `scheduled_orders_enabled` = true.
*/

-- ============================================================================
-- NOTAS PARA O REVISOR (o que tentar derrubar)
--   1. Equivalência: com o interruptor desligado o resultado é idêntico ao de hoje (prova B, 36 combinações).
--   2. Festas: NOT EXISTS (restaurants.category = 'festas') — uma loja de festas com scheduled_for continua a −30.
--   3. Cartão: pedidos pagos por cartão só entram com payment_status = 'paid' (igual a hoje).
--   4. Um agendado aceite com muita antecedência fica em 'preparing' dias (já acontecia nas festas). Verificar
--      se algum vigia trata 'preparing' parado como erro (admin-check-orphan-orders, _cron_check_orphan_orders,
--      alertas de "pedido preso"): se sim, excluir scheduled_for > now() + 2 h desses vigias antes de ligar.
--   5. Cron: a cada quanto corre? Se for de 5 em 5 min, o estafeta pode ser chamado até 5 min depois do alvo;
--      subir dispatch_antecedencia_minutos (8) ou correr o cron ao minuto.
--   6. O estafeta chamado fora de horas (loja já fechada quando o pedido está pronto): a janela já cabe no
--      horário (scheduled_windows_for_store), mas a chamada pode cair depois do fecho se a preparação for longa.
-- ============================================================================
