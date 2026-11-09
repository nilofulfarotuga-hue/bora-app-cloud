-- =============================================================================
-- PROVA EM ROLLBACK · M10 item 2.5 · chamada de reforço (migração 20261109010134)
-- GERADO por gerar_prova_chamada_reforco.mjs (não editar à mão: editar o modelo
-- prova_chamada_reforco.modelo.sql e voltar a gerar).
--
-- Corre TUDO num único DO que acaba em RAISE EXCEPTION 'PROVA_OK ...': a exceção
-- desfaz tudo (funções, tabelas, definições, linhas de teste). Garantias:
--   * os gatilhos da migração são criados em CLONES temporários de orders,
--     tvde_rides e tvde_ride_events (CREATE TEMP TABLE ... LIKE, sem gatilho
--     nenhum — nem tr_notify_driver_on_offer nem tr_notify_tvde_driver_on_offer,
--     os únicos que chamam pg_net numa oferta). Nenhum UPDATE em public.orders,
--     public.tvde_rides nem public.drivers;
--   * as funções novas só LEEM public.orders/drivers; escritas reais só em
--     ofertas_prestador_log, platform_settings, chamada_reforco_consentimento e
--     tvde_ride_events (nenhuma destas tabelas tem gatilho com pg_net — o passo
--     12 confere) e tudo é desfeito no fim;
--   * a varredura dispatch_fases_sweep (relança o motor por pg_net) só é chamada
--     DESLIGADA; admin_forcar_chamada só nos caminhos que respondem antes de
--     escrever (desligado / pedido entregue);
--   * o cron da migração NÃO entra (bloco [CRON-INICIO..FIM] retirado).
-- =============================================================================
do $prova$
declare
  v_mig  text := $mig_m10_20261109$-- =============================================================================
-- 20261109050000 · M10 (08-09/11/2026) item 2.5 — CHAMADA AO ESTAFETA
-- Chamada de reforço (regra do Danilo de 10/10) posta POR CIMA do que está no ar.
--
-- PORQUÊ ESTA MIGRAÇÃO E NÃO AS TRÊS DE 10/10
-- As migrações 20261010063000, 20261010070000 e 20261010073000 estão no repo mas
-- NUNCA foram aplicadas. Aplicá-las hoje como estão faria três estragos:
--   1. a 070000 trocava dispatch_candidatos_entrega pelo corpo de 10/10 e
--      apagava o modo demonstração de 27/10 (pedido demo só ao estafeta demo);
--   2. o registo de ofertas tem desde 31/10 a regra "categoria só limpeza,
--      lavagem, casa": cada oferta de entrega/Favor/TVDE falhava calada e as
--      fases nunca andavam (o reforço chamaria o Valdemir sem parar);
--   3. o gatilho que adia o cancelamento comparava o tipo enumerado
--      cancellation_initiator com '' (COALESCE(..., '')): isso dá ERRO e, como
--      está fora do bloco de exceção, partia TODA a mudança de estado de pedido.
--   A 073000 (limpeza, duas voltas) fica de FORA: não é estafeta, a função no ar
--   (_cleaning_next_offer) tem três correções depois de 10/10 (portão "só chama
--   se pago" 19/10, papel desligado 14/10, ganho da profissional 30/10) e há
--   outro ajudante na limpeza esta noite.
--
-- O QUE FAZ (regra do Danilo de 10/10, página livro-areas-chamada-estafeta-rotacao)
--   Entregas e Favores: chama os estafetas ONLINE por rotação (N voltas); se
--   ninguém aceitar, CHAMADA DE REFORÇO a um estafeta DESLIGADO que ligou no
--   telemóvel "Aceito chamadas de reforço quando estou desligado", pela ordem
--   da prioridade (Valdemir primeiro: user_id e355fde0-b634-48ba-bce1-e2a4466c4cc2,
--   drivers.id e1d81564-91f6-40b4-bf1e-f2710e44c368), um de cada vez; depois
--   volta aos online; só no fim o pedido pode ser cancelado ("não há estafeta").
--   TVDE: antes de a corrida ficar "sem motorista", o mesmo reforço (só
--   corridas da app; nunca reservas nem balcão).
--   Limites desenhados a 10/10 e mantidos (o Danilo confirma): consentimento de
--   cada um; só entre 08:00 e 23:00 de Lisboa; no máximo 3 reforços por pessoa
--   por dia; uma vez por pessoa por pedido; recusar nunca penaliza.
--
-- MUDANÇAS FACE AO DESENHO DE 10/10 (revisão de 09/11)
--   a) O reforço SÓ ACRESCENTA: nunca cancela mais cedo do que hoje. Esgotadas
--      as fases, o motor continua a rodar pelos online como sempre e quem
--      cancela é o tempo de sempre (bora_dispatch_maintenance). A 10/10
--      cancelava logo no fim das fases (com 1 estafeta online seriam ~5 min em
--      vez dos 20 de hoje).
--   b) Pedido de demonstração nunca faz reforço; pedido normal nunca chama o
--      estafeta demo.
--   c) Botão do painel "Forçar chamada" (admin_forcar_chamada): oferece já o
--      pedido ao próximo do reforço. Só com o interruptor ligado.
--   d) Gatilhos com WHEN: só acordam quando há oferta ou cancelamento.
--
-- INTERRUPTORES (nascem DESLIGADOS; a sessão principal / o Danilo decide):
--   dispatch_forcado_ligado = false  (entregas e Favores, e o botão do painel)
--   tvde_forcado_ligado     = false  (TVDE)
--   Desligado = despacho IGUAL ao de hoje: dispatch_candidatos_entrega devolve
--   exatamente a lista de sempre (cópia letra a letra do corpo do ar), nenhum
--   cancelamento é adiado, a varredura nova não faz nada, o TVDE fecha "sem
--   motorista" como hoje.
--   SEMPRE LIGADO (só observação, é o "ver a rotação" do painel): o registo de
--   cada oferta em ofertas_prestador_log (quem, quando, online ou não, se o
--   toque saiu, como acabou). Só escreve nesse registo; um erro nele nunca
--   parte o despacho (vai para notification_failures).
--
-- GUARDA: se dispatch_candidatos_entrega, admin_ofertas_log ou a regra da
-- categoria mudaram no ar depois de 09/11, a migração PÁRA com erro claro em vez
-- de apagar correções. Reaplicar é seguro (idempotente).
-- Prova em rollback: docs/propostas/m10-2026-11-09/prova_chamada_reforco.sql
-- =============================================================================

-- Revisão M10 (P1): não ficar à espera de bloqueios com auth.users e o registo de ofertas presos;
-- se uma transação longa estiver em orders, a migração desiste ao fim de 5 s (tudo ou nada).
SELECT set_config('lock_timeout', '5000', true);

-- 0) Guarda: só se aplica por cima do que foi revisto a 09/11.
DO $guarda$
DECLARE
  v_def text;
  v_chk text;
BEGIN
  v_def := pg_get_functiondef('public.dispatch_candidatos_entrega(text)'::regprocedure);
  IF md5(v_def) <> 'ebf3e6fc8165e1decce39ad7ce6c6ab6'
     AND position('m10-reforco-20261109' in v_def) = 0 THEN
    RAISE EXCEPTION 'M10 reforço: dispatch_candidatos_entrega mudou no ar depois de 09/11 (md5 %). Rever a migração antes de aplicar.', md5(v_def);
  END IF;
  v_def := pg_get_functiondef('public.admin_ofertas_log(text,integer,integer)'::regprocedure);
  IF md5(v_def) <> 'b8d6c187e0a420b04c44c1bbaa174995'
     AND position('m10-reforco-20261109' in v_def) = 0 THEN
    RAISE EXCEPTION 'M10 reforço: admin_ofertas_log mudou no ar depois de 09/11 (md5 %). Rever a migração antes de aplicar.', md5(v_def);
  END IF;
  SELECT pg_get_constraintdef(c.oid) INTO v_chk
    FROM pg_constraint c
   WHERE c.conrelid = 'public.ofertas_prestador_log'::regclass
     AND c.conname = 'ofertas_prestador_log_categoria_check';
  IF v_chk IS DISTINCT FROM 'CHECK ((categoria = ANY (ARRAY[''limpeza''::text, ''lavagem''::text, ''casa''::text])))'
     AND position('entrega' in COALESCE(v_chk, '')) = 0 THEN
    RAISE EXCEPTION 'M10 reforço: a regra da categoria do registo de ofertas mudou (%). Rever a migração.', v_chk;
  END IF;
END $guarda$;

-- 1) Cópia das definições que esta migração substitui (só servidor lê).
CREATE TABLE IF NOT EXISTS public.bkp_fn_reforco_20261109 (
  nome        text PRIMARY KEY,
  definicao   text NOT NULL,
  guardado_em timestamptz NOT NULL DEFAULT now()
);
ALTER TABLE public.bkp_fn_reforco_20261109 ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.bkp_fn_reforco_20261109 FROM PUBLIC, anon, authenticated;

-- 2) Definições. Os interruptores nascem DESLIGADOS. Não mexe em nenhuma que já exista.
INSERT INTO public.platform_settings (key, value, category, description) VALUES
  ('dispatch_forcado_ligado', 'false', 'dispatch',
   'Chamada de reforço (entregas e Favores): se nenhum estafeta online aceitar, chamar quem está desligado MAS consentiu, um de cada vez. Também liga o botão "Forçar chamada" do painel.'),
  ('dispatch_voltas_online_antes_forcado', '2', 'dispatch',
   'Voltas completas aos estafetas online antes da chamada de reforço.'),
  ('dispatch_forcado_tentativas', '2', 'dispatch',
   'Quantos estafetas desligados (que consentiram) se chamam, um de cada vez, antes de voltar aos online.'),
  ('dispatch_forcado_prioridade', '["e355fde0-b634-48ba-bce1-e2a4466c4cc2"]', 'dispatch',
   'Ordem fixa de quem é chamado no reforço (user_id). Os restantes vêm a seguir, do visto mais recentemente.'),
  ('dispatch_forcado_visto_horas', '168', 'dispatch',
   'Só entra no reforço quem tem aparelho registado e abriu a app nas últimas N horas.'),
  ('dispatch_forcado_horario_inicio', '"08:00"', 'dispatch',
   'Hora de Lisboa a partir da qual se pode fazer a chamada de reforço.'),
  ('dispatch_forcado_horario_fim', '"23:00"', 'dispatch',
   'Hora de Lisboa a partir da qual já não se faz a chamada de reforço.'),
  ('dispatch_forcado_max_por_dia', '3', 'dispatch',
   'Máximo de chamadas de reforço por pessoa por dia (recusar nunca penaliza).'),
  ('dispatch_voltas_online_depois_forcado', '1', 'dispatch',
   'Depois do reforço, voltas aos online antes de o pedido poder ser cancelado por tempo (nunca antes do tempo normal).'),
  ('dispatch_cancelar_so_no_fim', 'true', 'dispatch',
   'O cancelamento automático por tempo espera que as fases acabem (só vale com a chamada de reforço ligada).'),
  ('dispatch_cancelar_limite_absoluto_segundos', '3600', 'dispatch',
   'Limite absoluto: passado este tempo a procurar, o pedido pode ser cancelado mesmo a meio das fases.'),
  ('tvde_forcado_ligado', 'false', 'tvde',
   'Chamada de reforço (TVDE): antes de "sem motorista", chamar motoristas desligados que consentiram, um de cada vez. Só corridas da app (nunca reservas nem balcão).'),
  ('tvde_forcado_tentativas', '2', 'tvde',
   'TVDE: quantos motoristas desligados (que consentiram) se chamam antes de "sem motorista".'),
  ('tvde_forcado_prioridade', '["e355fde0-b634-48ba-bce1-e2a4466c4cc2"]', 'tvde',
   'TVDE: ordem fixa de quem é chamado no reforço (user_id).')
ON CONFLICT (key) DO NOTHING;

-- 3) Consentimento de cada profissional (só a própria pessoa liga/desliga; nasce desligado).
CREATE TABLE IF NOT EXISTS public.chamada_reforco_consentimento (
  user_id       uuid PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
  ligado        boolean NOT NULL DEFAULT false,
  atualizado_em timestamptz NOT NULL DEFAULT now()
);
ALTER TABLE public.chamada_reforco_consentimento ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS reforco_ver_o_meu ON public.chamada_reforco_consentimento;
CREATE POLICY reforco_ver_o_meu ON public.chamada_reforco_consentimento
  FOR SELECT TO authenticated USING (user_id = auth.uid() OR public.is_admin());
DROP POLICY IF EXISTS reforco_criar_o_meu ON public.chamada_reforco_consentimento;
CREATE POLICY reforco_criar_o_meu ON public.chamada_reforco_consentimento
  FOR INSERT TO authenticated WITH CHECK (user_id = auth.uid());
DROP POLICY IF EXISTS reforco_mudar_o_meu ON public.chamada_reforco_consentimento;
CREATE POLICY reforco_mudar_o_meu ON public.chamada_reforco_consentimento
  FOR UPDATE TO authenticated USING (user_id = auth.uid()) WITH CHECK (user_id = auth.uid());
REVOKE ALL ON public.chamada_reforco_consentimento FROM PUBLIC, anon, authenticated;
GRANT SELECT, INSERT, UPDATE ON public.chamada_reforco_consentimento TO authenticated;
GRANT ALL ON public.chamada_reforco_consentimento TO service_role;

CREATE OR REPLACE FUNCTION public._reforco_carimbo()
 RETURNS trigger LANGUAGE plpgsql SET search_path TO 'public' AS $function$
BEGIN
  NEW.atualizado_em := now();
  RETURN NEW;
END $function$;
DROP TRIGGER IF EXISTS trg_reforco_carimbo ON public.chamada_reforco_consentimento;
CREATE TRIGGER trg_reforco_carimbo BEFORE INSERT OR UPDATE ON public.chamada_reforco_consentimento
  FOR EACH ROW EXECUTE FUNCTION public._reforco_carimbo();

-- 4) Registo de ofertas: colunas e categorias novas (entrega, favor, tvde).
ALTER TABLE public.ofertas_prestador_log
  ALTER COLUMN booking_id DROP NOT NULL,
  ADD COLUMN IF NOT EXISTS pedido_ref     text,
  ADD COLUMN IF NOT EXISTS fase           text,
  ADD COLUMN IF NOT EXISTS estava_online  boolean,
  ADD COLUMN IF NOT EXISTS janela_s       integer,
  ADD COLUMN IF NOT EXISTS push_aparelhos integer,
  ADD COLUMN IF NOT EXISTS push_enviados  integer,
  ADD COLUMN IF NOT EXISTS push_em        timestamptz,
  ADD COLUMN IF NOT EXISTS push_detalhe   text;
ALTER TABLE public.ofertas_prestador_log DROP CONSTRAINT IF EXISTS ofertas_prestador_log_categoria_check;
ALTER TABLE public.ofertas_prestador_log ADD CONSTRAINT ofertas_prestador_log_categoria_check
  CHECK (categoria = ANY (ARRAY['limpeza'::text, 'lavagem'::text, 'casa'::text,
                                'entrega'::text, 'favor'::text, 'tvde'::text]));
CREATE INDEX IF NOT EXISTS ofertas_prestador_log_pedido_idx
  ON public.ofertas_prestador_log (pedido_ref, oferecida_em);
CREATE INDEX IF NOT EXISTS ofertas_prestador_log_abertas_idx
  ON public.ofertas_prestador_log (pedido_ref) WHERE desfecho IS NULL;
CREATE INDEX IF NOT EXISTS ofertas_prestador_log_user_dia_idx
  ON public.ofertas_prestador_log (user_id, oferecida_em) WHERE fase = 'forcado';

-- 5) Decisões puras (sem tabelas), provadas em rollback.
-- 5a) Dentro do horário do reforço? (a janela pode passar a meia-noite)
CREATE OR REPLACE FUNCTION public.dispatch_reforco_horario_ok(p_agora time, p_ini time, p_fim time)
 RETURNS boolean
 LANGUAGE sql
 IMMUTABLE
 SET search_path TO 'public'
AS $function$
  SELECT CASE
    WHEN p_agora IS NULL OR p_ini IS NULL OR p_fim IS NULL THEN false
    WHEN p_ini <= p_fim THEN p_agora >= p_ini AND p_agora < p_fim
    ELSE p_agora >= p_ini OR p_agora < p_fim
  END;
$function$;

-- 5b) Em que fase está o pedido.
--    p_online   : quem está online e elegível agora (user_id)
--    p_ofertas  : ofertas já feitas, por ordem: [{"user_id":..,"fase":"online1|forcado|online2"}]
--    p_forcados : quem pode receber a chamada de reforço agora, já por ordem
CREATE OR REPLACE FUNCTION public.dispatch_fase_decidir(
  p_online        uuid[],
  p_ofertas       jsonb,
  p_forcados      uuid[],
  p_ligado        boolean,
  p_voltas_antes  integer,
  p_tentativas    integer,
  p_voltas_depois integer
) RETURNS jsonb
 LANGUAGE plpgsql
 IMMUTABLE
 SET search_path TO 'public'
AS $function$
DECLARE
  v_ofertas  jsonb  := COALESCE(p_ofertas, '[]'::jsonb);
  v_online   uuid[] := array_remove(COALESCE(p_online, '{}'::uuid[]), NULL);
  v_feitos   uuid[];
  v_online2  boolean;
  v_u        uuid;
  v_n        integer;
  v_prox     uuid;
  v_falta    boolean;
BEGIN
  IF NOT COALESCE(p_ligado, false) THEN
    RETURN jsonb_build_object('fase', 'online1', 'motivo', 'chamada_de_reforco_desligada');
  END IF;

  SELECT array_remove(COALESCE(array_agg(DISTINCT (e->>'user_id')::uuid) FILTER (WHERE e->>'fase' = 'forcado'), '{}'::uuid[]), NULL),
         COALESCE(bool_or(e->>'fase' = 'online2'), false)
    INTO v_feitos, v_online2
    FROM jsonb_array_elements(v_ofertas) e;
  v_feitos  := COALESCE(v_feitos, '{}'::uuid[]);
  v_online2 := COALESCE(v_online2, false);

  -- Fase 1: N voltas completas aos online.
  IF cardinality(v_feitos) = 0 AND NOT v_online2 THEN
    v_falta := false;
    FOREACH v_u IN ARRAY v_online LOOP
      SELECT count(*) INTO v_n FROM jsonb_array_elements(v_ofertas) e
       WHERE e->>'fase' = 'online1' AND e->>'user_id' = v_u::text;
      IF v_n < GREATEST(COALESCE(p_voltas_antes, 1), 1) THEN v_falta := true; EXIT; END IF;
    END LOOP;
    IF v_falta THEN
      RETURN jsonb_build_object('fase', 'online1', 'forcados_feitos', 0);
    END IF;
  END IF;

  -- Fase 2: chamada de reforço, um de cada vez, uma vez por pessoa por pedido.
  IF NOT v_online2 AND cardinality(v_feitos) < GREATEST(COALESCE(p_tentativas, 0), 0) THEN
    SELECT f INTO v_prox
      FROM unnest(COALESCE(p_forcados, '{}'::uuid[])) WITH ORDINALITY t(f, i)
     WHERE f IS NOT NULL AND NOT (f = ANY(v_feitos)) AND NOT (f = ANY(v_online))
     ORDER BY i LIMIT 1;
    IF v_prox IS NOT NULL THEN
      RETURN jsonb_build_object('fase', 'forcado', 'user_id', v_prox, 'forcados_feitos', cardinality(v_feitos));
    END IF;
  END IF;

  -- Fase 3: online outra vez.
  v_falta := false;
  FOREACH v_u IN ARRAY v_online LOOP
    SELECT count(*) INTO v_n FROM jsonb_array_elements(v_ofertas) e
     WHERE e->>'fase' = 'online2' AND e->>'user_id' = v_u::text;
    IF v_n < GREATEST(COALESCE(p_voltas_depois, 0), 0) THEN v_falta := true; EXIT; END IF;
  END LOOP;
  IF v_falta THEN
    RETURN jsonb_build_object('fase', 'online2', 'forcados_feitos', cardinality(v_feitos));
  END IF;

  -- Fase 4: acabou o reforço (o pedido pode ser cancelado pelo tempo de sempre).
  RETURN jsonb_build_object('fase', 'esgotado', 'forcados_feitos', cardinality(v_feitos));
END;
$function$;

-- 6) Os candidatos ONLINE de sempre: cópia LETRA A LETRA do corpo que está no ar
--    (dispatch_candidatos_entrega de 27/10, com o modo demonstração; md5 ebf3e6fc…),
--    só com o nome trocado. Guardado antes em bkp_fn_reforco_20261109.
DO $copia$
DECLARE
  v_def text := pg_get_functiondef('public.dispatch_candidatos_entrega(text)'::regprocedure);
BEGIN
  IF position('m10-reforco-20261109' in v_def) = 0 THEN
    INSERT INTO public.bkp_fn_reforco_20261109 (nome, definicao)
    VALUES ('dispatch_candidatos_entrega', v_def)
    ON CONFLICT (nome) DO NOTHING;
    EXECUTE replace(v_def,
      'CREATE OR REPLACE FUNCTION public.dispatch_candidatos_entrega(',
      'CREATE OR REPLACE FUNCTION public._dispatch_candidatos_online(');
  END IF;
END $copia$;

-- 7) Quem pode receber a chamada de reforço agora, já por ordem.
--    Desligado (fora dos online), aprovado, não banido nem apagado, consentiu,
--    aceita entregas, aparelho que acorda (app, não só navegador), visto nas
--    últimas N horas, livre, dentro do horário e abaixo do máximo diário.
--    Pedido demo nunca; o estafeta demo nunca entra num pedido normal.
CREATE OR REPLACE FUNCTION public._dispatch_forcados_entrega(p_order_id text)
 RETURNS TABLE(driver_id uuid, user_id uuid, lat double precision, lng double precision, vehicle_type text,
               dist_km double precision, mesma_loja boolean, ordem integer, visto_em timestamptz)
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  o          record;
  v_horas    int   := COALESCE((public.get_setting('dispatch_forcado_visto_horas') #>> '{}')::int, 168);
  v_max_dia  int   := COALESCE((public.get_setting('dispatch_forcado_max_por_dia') #>> '{}')::int, 3);
  v_ini      time  := COALESCE((public.get_setting('dispatch_forcado_horario_inicio') #>> '{}')::time, '08:00');
  v_fim      time  := COALESCE((public.get_setting('dispatch_forcado_horario_fim') #>> '{}')::time, '23:00');
  v_prio     jsonb := public.get_setting('dispatch_forcado_prioridade');
  v_dia0     timestamptz := date_trunc('day', now() AT TIME ZONE 'Europe/Lisbon') AT TIME ZONE 'Europe/Lisbon';
  v_req_car  boolean;
  v_favor    boolean;
  v_demo_uid uuid;
BEGIN
  IF NOT public.dispatch_reforco_horario_ok((now() AT TIME ZONE 'Europe/Lisbon')::time, v_ini, v_fim) THEN
    RETURN;
  END IF;

  SELECT x.id, x.service_type, x.requires_car, x.pickup_lat, x.pickup_lng, x.restaurant_id
    INTO o FROM public.orders x WHERE x.id = p_order_id;
  IF NOT FOUND THEN RETURN; END IF;
  IF public._e_pedido_demo_loja(o.id) THEN RETURN; END IF;
  v_demo_uid := public._modo_demo_estafeta();
  v_req_car  := COALESCE(o.requires_car, false) OR o.service_type = 'carryGroceries';
  v_favor    := o.service_type = 'errand';
  IF v_prio IS NULL OR jsonb_typeof(v_prio) <> 'array' THEN v_prio := '[]'::jsonb; END IF;

  RETURN QUERY
  WITH online AS (
    SELECT COALESCE(c.user_id, c.driver_id) AS uid FROM public._dispatch_candidatos_online(p_order_id) c
  ), base AS (
    SELECT d.id AS d_id, COALESCE(d.user_id, d.id) AS d_uid, d.lat AS d_lat, d.lng AS d_lng, d.vehicle_type AS d_veh,
           ARRAY[d.id::text, COALESCE(d.user_id, d.id)::text] AS chaves,
           GREATEST(COALESCE(d.last_heartbeat_at, '-infinity'::timestamptz),
                    COALESCE((SELECT max(t.last_used_at) FROM public.driver_push_tokens t
                               WHERE t.user_id = COALESCE(d.user_id, d.id) AND t.active),
                             '-infinity'::timestamptz)) AS visto
      FROM public.drivers d
      JOIN public.chamada_reforco_consentimento cons
        ON cons.user_id = COALESCE(d.user_id, d.id) AND cons.ligado
     WHERE d.approval_status = 'approved'
       AND (COALESCE(d.is_banned, false) = false
            OR (d.banned_until IS NOT NULL AND d.banned_until <= now()))
       AND d.deleted_at IS NULL
       AND (v_demo_uid IS NULL OR COALESCE(d.user_id, d.id) IS DISTINCT FROM v_demo_uid)
       AND (d.work_mode IS NULL OR d.work_mode <> 'rides_only')
       AND (NOT v_req_car OR d.vehicle_type IN ('car', 'carro_passageiros'))
       AND public.aceita_papel(COALESCE(d.user_id, d.id), 'delivery')
       AND NOT EXISTS (SELECT 1 FROM online x WHERE x.uid = COALESCE(d.user_id, d.id))
       AND (COALESCE(d.fcm_token, '') <> ''
            OR EXISTS (SELECT 1 FROM public.driver_push_tokens t
                        WHERE t.user_id = COALESCE(d.user_id, d.id) AND t.active
                          AND COALESCE(t.platform, '') NOT ILIKE 'web%'))
       AND NOT EXISTS (SELECT 1 FROM public.tvde_rides r
                        WHERE r.driver_id = d.user_id
                          AND r.status IN ('motorista_atribuido','motorista_a_caminho','motorista_chegou','em_andamento'))
       AND (SELECT count(*) FROM public.ofertas_prestador_log l
             WHERE l.user_id = COALESCE(d.user_id, d.id) AND l.fase = 'forcado'
               AND l.oferecida_em >= v_dia0) < v_max_dia
  ), carga AS (
    SELECT b.*,
           (SELECT count(*) FROM public.orders a
             WHERE a.assigned_driver_id = ANY(b.chaves)
               AND a.status IN ('driverAccepted','pickedUp','onTheWay')) AS ativos,
           EXISTS (SELECT 1 FROM public.orders a
             WHERE a.assigned_driver_id = ANY(b.chaves)
               AND a.status IN ('driverAccepted','pickedUp','onTheWay')
               AND a.service_type = 'errand') AS tem_favor,
           EXISTS (SELECT 1 FROM public.orders a
             WHERE a.id <> o.id
               AND a.status = 'callingDriver'
               AND a.current_driver_offer_id = ANY(b.chaves)
               AND a.driver_offer_expires_at > now()) AS oferta_ocupada,
           (SELECT e.ord::int FROM jsonb_array_elements_text(v_prio) WITH ORDINALITY e(val, ord)
             WHERE e.val = b.d_uid::text OR e.val = b.d_id::text
             ORDER BY e.ord LIMIT 1) AS prio
      FROM base b
     WHERE b.visto > now() - make_interval(hours => v_horas)
  )
  SELECT c.d_id, c.d_uid, c.d_lat, c.d_lng, c.d_veh,
         CASE WHEN o.pickup_lat IS NULL OR o.pickup_lng IS NULL OR c.d_lat IS NULL OR c.d_lng IS NULL THEN NULL
              ELSE 6371 * 2 * asin(sqrt(
                     power(sin(radians(o.pickup_lat::double precision - c.d_lat) / 2), 2)
                   + cos(radians(c.d_lat)) * cos(radians(o.pickup_lat::double precision))
                     * power(sin(radians(o.pickup_lng::double precision - c.d_lng) / 2), 2)))
         END,
         false,
         COALESCE(c.prio, 1000000),
         c.visto
    FROM carga c
   WHERE NOT c.oferta_ocupada
     AND c.ativos < 3
     AND NOT c.tem_favor
     AND (NOT v_favor OR c.ativos = 0)
   ORDER BY COALESCE(c.prio, 1000000), c.visto DESC;
END;
$function$;

-- 8) A fase de um pedido real (junta as entradas e chama a decisão pura).
--    Interruptor desligado: responde logo "online1" sem ler nada.
CREATE OR REPLACE FUNCTION public.dispatch_fase_entrega(p_order_id text)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_online   uuid[];
  v_ofertas  jsonb;
  v_forcados uuid[];
  v_dec      jsonb;
  v_ext      timestamptz;
BEGIN
  IF NOT COALESCE((public.get_setting('dispatch_forcado_ligado') #>> '{}')::boolean, false) THEN
    RETURN jsonb_build_object('fase', 'online1', 'motivo', 'chamada_de_reforco_desligada');
  END IF;

  SELECT COALESCE(array_agg(COALESCE(c.user_id, c.driver_id)), '{}'::uuid[])
    INTO v_online FROM public._dispatch_candidatos_online(p_order_id) c;
  SELECT COALESCE(jsonb_agg(jsonb_build_object('user_id', l.user_id, 'fase', l.fase) ORDER BY l.oferecida_em), '[]'::jsonb)
    INTO v_ofertas
    FROM public.ofertas_prestador_log l
   WHERE l.pedido_ref = p_order_id AND l.categoria IN ('entrega', 'favor')
     AND l.fase IN ('online1', 'forcado', 'online2');
  SELECT COALESCE(array_agg(f.user_id ORDER BY f.ordem, f.visto_em DESC), '{}'::uuid[])
    INTO v_forcados FROM public._dispatch_forcados_entrega(p_order_id) f;

  v_dec := public.dispatch_fase_decidir(
    v_online, v_ofertas, v_forcados, true,
    COALESCE((public.get_setting('dispatch_voltas_online_antes_forcado') #>> '{}')::int, 2),
    COALESCE((public.get_setting('dispatch_forcado_tentativas') #>> '{}')::int, 2),
    COALESCE((public.get_setting('dispatch_voltas_online_depois_forcado') #>> '{}')::int, 1));

  -- O parceiro pediu mais tempo ("Continuar"): enquanto durar, não está esgotado.
  SELECT x.dispatch_extended_until INTO v_ext FROM public.orders x WHERE x.id = p_order_id;
  IF v_dec->>'fase' = 'esgotado' AND v_ext IS NOT NULL AND v_ext > now() THEN
    v_dec := v_dec || jsonb_build_object('fase', 'online2', 'motivo', 'prolongado_pelo_parceiro');
  END IF;

  RETURN v_dec || jsonb_build_object(
    'online_n', cardinality(v_online),
    'ofertas_n', jsonb_array_length(v_ofertas),
    'forcados_disponiveis_n', cardinality(v_forcados));
END;
$function$;

-- 9) O que o motor (Edge dispatch-engine) lê. m10-reforco-20261109
--    forcado            → só o próximo estafeta do reforço;
--    tudo o resto       → os online de sempre (o reforço só acrescenta).
CREATE OR REPLACE FUNCTION public.dispatch_candidatos_entrega(p_order_id text)
 RETURNS TABLE(driver_id uuid, user_id uuid, lat double precision, lng double precision, vehicle_type text, dist_km double precision, mesma_loja boolean)
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  -- m10-reforco-20261109: fases da chamada de reforço por cima do corpo de 27/10
  v_fase jsonb;
  v_f    record;
  v_tem  boolean := false;
BEGIN
  -- Revisão M10 (P3): um erro no cálculo da fase (definição mal escrita, função em falta) NUNCA
  -- pára o despacho: avisa e segue com a lista online de sempre.
  BEGIN
    v_fase := public.dispatch_fase_entrega(p_order_id);
    IF v_fase->>'fase' = 'forcado' THEN
      SELECT f.driver_id, f.user_id, f.lat, f.lng, f.vehicle_type, f.dist_km, f.mesma_loja
        INTO v_f
        FROM public._dispatch_forcados_entrega(p_order_id) f
       WHERE f.user_id = (v_fase->>'user_id')::uuid
       LIMIT 1;
      v_tem := FOUND;
    END IF;
  EXCEPTION WHEN OTHERS THEN
    RAISE WARNING 'dispatch_candidatos_entrega: fase do reforço falhou (%), segue a lista online', SQLERRM;
    v_fase := NULL;
    v_tem := false;
  END;
  IF v_fase->>'fase' = 'forcado' THEN
    IF v_tem THEN
      driver_id := v_f.driver_id; user_id := v_f.user_id; lat := v_f.lat; lng := v_f.lng;
      vehicle_type := v_f.vehicle_type; dist_km := v_f.dist_km; mesma_loja := v_f.mesma_loja;
      RETURN NEXT;
    END IF;
    RETURN;
  END IF;
  RETURN QUERY SELECT * FROM public._dispatch_candidatos_online(p_order_id);
END;
$function$;

-- 10) Registo de ofertas de entregas e Favores (SÓ escreve no registo).
--     Marca a fase (online1 / forcado / online2); o botão do painel marca
--     'forcado' por bora.oferta_fase.
CREATE OR REPLACE FUNCTION public._registar_oferta_entrega()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_mudou    boolean;
  v_desfecho text;
  v_d        record;
  v_janela   integer;
  v_online   boolean;
  v_fase     jsonb;
  v_label    text;
BEGIN
  v_mudou := NEW.current_driver_offer_id IS DISTINCT FROM OLD.current_driver_offer_id
          OR NEW.driver_offer_expires_at IS DISTINCT FROM OLD.driver_offer_expires_at;

  -- Fechar a oferta que acabou.
  IF OLD.current_driver_offer_id IS NOT NULL
     AND (v_mudou OR NEW.status IS DISTINCT FROM OLD.status
          OR NEW.assigned_driver_id IS DISTINCT FROM OLD.assigned_driver_id) THEN
    v_desfecho := CASE
      WHEN NEW.assigned_driver_id IS NOT NULL
           AND (NEW.assigned_driver_id = OLD.current_driver_offer_id
                OR EXISTS (SELECT 1 FROM public.drivers d
                            WHERE (d.user_id::text = OLD.current_driver_offer_id OR d.id::text = OLD.current_driver_offer_id)
                              AND NEW.assigned_driver_id IN (d.id::text, COALESCE(d.user_id, d.id)::text)))
        THEN 'aceite'
      WHEN NEW.status = 'cancelled' THEN 'pedido_cancelado'
      WHEN NEW.status IS DISTINCT FROM 'callingDriver' THEN 'pedido_mudou'
      WHEN OLD.driver_offer_expires_at IS NOT NULL
           AND OLD.driver_offer_expires_at > now() + interval '2 seconds' THEN 'recusou'
      ELSE 'expirou' END;
    UPDATE public.ofertas_prestador_log
       SET desfecho = v_desfecho, fechada_em = now()
     WHERE pedido_ref = NEW.id AND categoria IN ('entrega', 'favor') AND desfecho IS NULL;
  END IF;

  -- Abrir a oferta nova.
  IF v_mudou AND NEW.current_driver_offer_id IS NOT NULL AND NEW.driver_offer_expires_at IS NOT NULL
     AND NEW.status = 'callingDriver' AND NEW.assigned_driver_id IS NULL THEN
    SELECT d.id, COALESCE(d.user_id, d.id) AS uid, d.name, d.is_online, d.last_heartbeat_at, d.fcm_token
      INTO v_d
      FROM public.drivers d
     WHERE d.user_id::text = NEW.current_driver_offer_id OR d.id::text = NEW.current_driver_offer_id
     LIMIT 1;
    v_janela := GREATEST(1, EXTRACT(EPOCH FROM (NEW.driver_offer_expires_at - now()))::int);
    v_online := COALESCE(v_d.is_online, false) AND v_d.last_heartbeat_at > now() - interval '90 seconds';

    v_label := NULLIF(current_setting('bora.oferta_fase', true), '');
    IF v_label IS NULL THEN
      -- A fase em que o pedido estava quando esta oferta foi escolhida.
      v_fase  := public.dispatch_fase_entrega(NEW.id);
      v_label := v_fase->>'fase';
      IF v_label = 'forcado' AND (v_fase->>'user_id') IS DISTINCT FROM v_d.uid::text THEN
        v_label := CASE WHEN COALESCE((v_fase->>'forcados_feitos')::int, 0) > 0 THEN 'online2' ELSE 'online1' END;
      ELSIF v_label = 'esgotado' THEN
        v_label := 'online2';
      END IF;
    END IF;

    INSERT INTO public.ofertas_prestador_log
      (categoria, booking_id, pedido_ref, prestador_id, user_id, nome, tem_aparelho,
       janela_min, janela_s, fase, estava_online)
    VALUES
      (CASE WHEN NEW.service_type = 'errand' THEN 'favor' ELSE 'entrega' END,
       CASE WHEN NEW.id ~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$' THEN NEW.id::uuid END,
       NEW.id, v_d.id, v_d.uid, v_d.name,
       COALESCE(v_d.fcm_token, '') <> ''
         OR EXISTS (SELECT 1 FROM public.driver_push_tokens t WHERE t.user_id = v_d.uid AND t.active),
       CEIL(v_janela / 60.0)::int, v_janela, v_label, v_online);
  END IF;
  RETURN NULL;
EXCEPTION WHEN OTHERS THEN
  -- O registo nunca pode partir o despacho; mas fica rasto.
  BEGIN
    INSERT INTO public.notification_failures (kind, source, erro)
    VALUES ('registo_oferta', '_registar_oferta_entrega', left(NEW.id || ': ' || SQLERRM, 500));
  EXCEPTION WHEN OTHERS THEN
    RAISE WARNING '[_registar_oferta_entrega] % (registo da falha também falhou: %)', NEW.id, SQLERRM;
  END;
  RETURN NULL;
END;
$function$;

DROP TRIGGER IF EXISTS trg_registar_oferta_entrega ON pg_temp._orders_clone;
CREATE TRIGGER trg_registar_oferta_entrega
  AFTER UPDATE OF current_driver_offer_id, driver_offer_expires_at, status, assigned_driver_id
  ON pg_temp._orders_clone
  FOR EACH ROW
  WHEN (OLD.current_driver_offer_id IS NOT NULL OR NEW.current_driver_offer_id IS NOT NULL)
  EXECUTE FUNCTION public._registar_oferta_entrega();

-- 11) "Nunca antes": o cancelamento automático por TEMPO espera o fim das fases
--     (só com o reforço ligado e "cancelar só no fim"). Corre antes dos outros
--     gatilhos BEFORE de estado (nome "_aa"); devolver NULL salta a mudança —
--     dispatch_cancel_expired_order vê 0 linhas e devolve false, sem avisos nem
--     devoluções. CORRIGIDO face a 10/10: o tipo enumerado compara-se como texto.
CREATE OR REPLACE FUNCTION public._dispatch_nao_cancelar_cedo()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_lim  integer;
  v_fase text;
BEGIN
  IF NEW.status = 'cancelled' AND OLD.status = 'callingDriver'
     AND NEW.cancellation_initiator::text IS NOT DISTINCT FROM 'system'
     AND NEW.cancel_reason IN ('dispatch_safety_timeout', 'dispatch_max_total_with_drivers_exceeded') THEN
    BEGIN
      IF COALESCE((public.get_setting('dispatch_cancelar_so_no_fim') #>> '{}')::boolean, false)
         AND COALESCE((public.get_setting('dispatch_forcado_ligado') #>> '{}')::boolean, false) THEN
        v_lim := COALESCE((public.get_setting('dispatch_cancelar_limite_absoluto_segundos') #>> '{}')::int, 3600);
        IF OLD.dispatch_calling_since IS NULL
           OR now() - OLD.dispatch_calling_since < make_interval(secs => v_lim) THEN
          v_fase := public.dispatch_fase_entrega(OLD.id)->>'fase';
          IF v_fase IS DISTINCT FROM 'esgotado' THEN
            RAISE NOTICE '[despacho] cancelamento por tempo adiado: pedido % ainda na fase %', OLD.id, v_fase;
            RETURN NULL;
          END IF;
        END IF;
      END IF;
    EXCEPTION WHEN OTHERS THEN
      -- Na dúvida, deixa seguir o cancelamento de sempre.
      RAISE WARNING '[_dispatch_nao_cancelar_cedo] %: %', OLD.id, SQLERRM;
    END;
  END IF;
  RETURN NEW;
END;
$function$;

DROP TRIGGER IF EXISTS _aa_dispatch_nao_cancelar_cedo ON pg_temp._orders_clone;
CREATE TRIGGER _aa_dispatch_nao_cancelar_cedo
  BEFORE UPDATE OF status ON pg_temp._orders_clone
  FOR EACH ROW
  WHEN (NEW.status = 'cancelled' AND OLD.status = 'callingDriver')
  EXECUTE FUNCTION public._dispatch_nao_cancelar_cedo();

-- 12) Varredura (cron 15 s): passado o tempo normal e ainda a meio das fases, o
--     motor deixa de se relançar sozinho; esta varredura relança-o. NÃO cancela
--     (quem cancela é o tempo de sempre, quando as fases acabam).
CREATE OR REPLACE FUNCTION public.dispatch_fases_sweep()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  r          record;
  v_fase     jsonb;
  v_safety   integer;
  v_max      integer;
  v_relancar integer := 0;
BEGIN
  IF NOT COALESCE((public.get_setting('dispatch_forcado_ligado') #>> '{}')::boolean, false)
     OR NOT COALESCE((public.get_setting('dispatch_cancelar_so_no_fim') #>> '{}')::boolean, false) THEN
    RETURN jsonb_build_object('ok', true, 'desligado', true);
  END IF;
  v_safety := COALESCE((public.get_setting('dispatch_auto_cancel_safety_seconds') #>> '{}')::int, 1800);
  v_max    := COALESCE((public.get_setting('dispatch_max_total_seconds_with_drivers_online') #>> '{}')::int, 1200);

  FOR r IN
    SELECT o.id
      FROM public.orders o
     WHERE o.status = 'callingDriver'
       AND o.assigned_driver_id IS NULL
       AND (o.current_driver_offer_id IS NULL OR o.driver_offer_expires_at IS NULL
            OR o.driver_offer_expires_at < now())
       AND ((o.dispatch_calling_since IS NOT NULL
             AND o.dispatch_calling_since < now() - make_interval(secs => v_safety))
            OR COALESCE(o.dispatch_online_attempt_seconds, 0) >= v_max)
       AND (o.dispatch_next_retry_at IS NULL OR o.dispatch_next_retry_at < now() - interval '20 seconds')
  LOOP
    BEGIN
      v_fase := public.dispatch_fase_entrega(r.id);
      IF v_fase->>'fase' <> 'esgotado' THEN
        PERFORM public.invoke_dispatch_engine(r.id::text);
        v_relancar := v_relancar + 1;
      END IF;
    EXCEPTION WHEN OTHERS THEN
      RAISE WARNING '[dispatch_fases_sweep] pedido %: %', r.id, SQLERRM;
    END;
  END LOOP;
  RETURN jsonb_build_object('ok', true, 'relancados', v_relancar);
END;
$function$;

-- 13) TVDE: antes de "sem motorista", chamada de reforço a um motorista
--     desligado que consentiu (mesmo horário e máximo diário das entregas).
--     Só corridas da app: reservas, balcão e corridas retidas fecham como hoje.
CREATE OR REPLACE FUNCTION public._tvde_forcados(p_ride_id uuid)
 RETURNS TABLE(user_id uuid, nome text, ordem integer, visto_em timestamptz)
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_horas   int   := COALESCE((public.get_setting('dispatch_forcado_visto_horas') #>> '{}')::int, 168);
  v_max_dia int   := COALESCE((public.get_setting('dispatch_forcado_max_por_dia') #>> '{}')::int, 3);
  v_ini     time  := COALESCE((public.get_setting('dispatch_forcado_horario_inicio') #>> '{}')::time, '08:00');
  v_fim     time  := COALESCE((public.get_setting('dispatch_forcado_horario_fim') #>> '{}')::time, '23:00');
  v_hb      int   := COALESCE((public.get_setting('tvde_heartbeat_window_seconds') #>> '{}')::int, 90);
  v_prio    jsonb := public.get_setting('tvde_forcado_prioridade');
  v_dia0    timestamptz := date_trunc('day', now() AT TIME ZONE 'Europe/Lisbon') AT TIME ZONE 'Europe/Lisbon';
BEGIN
  IF NOT public.dispatch_reforco_horario_ok((now() AT TIME ZONE 'Europe/Lisbon')::time, v_ini, v_fim) THEN
    RETURN;
  END IF;
  IF v_prio IS NULL OR jsonb_typeof(v_prio) <> 'array' THEN v_prio := '[]'::jsonb; END IF;

  RETURN QUERY
  SELECT d.user_id, d.name,
         COALESCE((SELECT e.ord::int FROM jsonb_array_elements_text(v_prio) WITH ORDINALITY e(val, ord)
                    WHERE e.val = d.user_id::text ORDER BY e.ord LIMIT 1), 1000000),
         GREATEST(COALESCE(d.last_heartbeat_at, '-infinity'::timestamptz),
                  COALESCE((SELECT max(t.last_used_at) FROM public.driver_push_tokens t
                             WHERE t.user_id = d.user_id AND t.active), '-infinity'::timestamptz)) AS visto
    FROM public.drivers d
    JOIN public.chamada_reforco_consentimento cons ON cons.user_id = d.user_id AND cons.ligado
   WHERE d.vehicle_type = 'carro_passageiros'
     AND d.approval_status = 'approved'
     AND d.user_id IS NOT NULL
     AND d.deleted_at IS NULL
     AND (COALESCE(d.is_banned, false) = false OR (d.banned_until IS NOT NULL AND d.banned_until <= now()))
     AND NOT (COALESCE(d.is_online, false) AND d.last_heartbeat_at > now() - make_interval(secs => v_hb))
     AND (COALESCE(d.fcm_token, '') <> ''
          OR EXISTS (SELECT 1 FROM public.driver_push_tokens t
                      WHERE t.user_id = d.user_id AND t.active AND COALESCE(t.platform, '') NOT ILIKE 'web%'))
     AND NOT EXISTS (SELECT 1 FROM public.tvde_rides r2
                      WHERE r2.driver_id = d.user_id
                        AND r2.status IN ('motorista_atribuido','motorista_a_caminho','motorista_chegou','em_andamento'))
     AND NOT EXISTS (SELECT 1 FROM public.orders o
                      WHERE o.assigned_driver_id IN (d.user_id::text, d.id::text)
                        AND o.status IN ('driverAccepted','pickedUp','onTheWay'))
     AND NOT public.tvde_driver_reservation_locked(d.user_id)
     AND public.tvde_driver_offer_allowed(d.user_id, p_ride_id)
     AND (SELECT count(*) FROM public.ofertas_prestador_log l
           WHERE l.user_id = d.user_id AND l.fase = 'forcado' AND l.oferecida_em >= v_dia0) < v_max_dia
     AND GREATEST(COALESCE(d.last_heartbeat_at, '-infinity'::timestamptz),
                  COALESCE((SELECT max(t.last_used_at) FROM public.driver_push_tokens t
                             WHERE t.user_id = d.user_id AND t.active), '-infinity'::timestamptz))
         > now() - make_interval(hours => v_horas)
   ORDER BY 3, 4 DESC;
END;
$function$;

CREATE OR REPLACE FUNCTION public._tvde_chamada_de_reforco()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_t      integer;
  v_feitos uuid[];
  v_prox   uuid;
  v_ttl    integer;
BEGIN
  IF NOT (OLD.status = 'solicitada' AND NEW.status = 'sem_motorista') THEN RETURN NEW; END IF;
  -- Reservas (têm devolução própria), balcão e corridas retidas: como hoje.
  IF NEW.reservation_status IS NOT NULL OR OLD.reservation_status IS NOT NULL
     OR COALESCE(NEW.source, 'app') = 'balcao' OR NEW.dispatch_hold_reason IS NOT NULL THEN
    RETURN NEW;
  END IF;
  BEGIN
    IF NOT COALESCE((public.get_setting('tvde_forcado_ligado') #>> '{}')::boolean, false) THEN RETURN NEW; END IF;
    v_t := COALESCE((public.get_setting('tvde_forcado_tentativas') #>> '{}')::int, 2);
    SELECT COALESCE(array_agg(DISTINCT l.user_id) FILTER (WHERE l.user_id IS NOT NULL), '{}'::uuid[]) INTO v_feitos
      FROM public.ofertas_prestador_log l
     WHERE l.categoria = 'tvde' AND l.booking_id = NEW.id AND l.fase = 'forcado';
    IF cardinality(v_feitos) >= v_t THEN RETURN NEW; END IF;
    SELECT f.user_id INTO v_prox FROM public._tvde_forcados(NEW.id) f
     WHERE NOT (f.user_id = ANY(v_feitos)) ORDER BY f.ordem, f.visto_em DESC LIMIT 1;
    IF v_prox IS NULL THEN RETURN NEW; END IF;
    v_ttl := COALESCE((public.get_setting('tvde_offer_ttl_seconds') #>> '{}')::int, 40);
    INSERT INTO public.tvde_ride_events (ride_id, status, actor, meta)
      VALUES (NEW.id, 'oferta', 'system',
              jsonb_build_object('driver_id', v_prox, 'expires_in_s', v_ttl, 'forcado', true,
                                 'motivo', 'chamada_de_reforco'));
  EXCEPTION WHEN OTHERS THEN
    RAISE WARNING '[_tvde_chamada_de_reforco] %: %', NEW.id, SQLERRM;
    RETURN NEW;
  END;
  -- Em vez de fechar "sem motorista", fica a procurar com a oferta de reforço.
  NEW.status := 'solicitada';
  NEW.cancel_reason := OLD.cancel_reason;
  NEW.current_offer_driver_id := v_prox;
  NEW.offer_expires_at := now() + make_interval(secs => v_ttl);
  NEW.no_driver_since := NULL;
  RETURN NEW;
END;
$function$;

DROP TRIGGER IF EXISTS _aa_tvde_chamada_de_reforco ON pg_temp._tvde_rides_clone;
CREATE TRIGGER _aa_tvde_chamada_de_reforco
  BEFORE UPDATE OF status ON pg_temp._tvde_rides_clone
  FOR EACH ROW
  WHEN (OLD.status = 'solicitada' AND NEW.status = 'sem_motorista')
  EXECUTE FUNCTION public._tvde_chamada_de_reforco();

-- Registo TVDE (SÓ escreve no registo); marca a oferta de reforço como 'forcado'.
CREATE OR REPLACE FUNCTION public._registar_oferta_tvde()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_d        record;
  v_online   boolean;
  v_janela   integer;
  v_desfecho text;
  v_reforco  boolean;
BEGIN
  IF OLD.current_offer_driver_id IS NOT NULL
     AND (NEW.current_offer_driver_id IS DISTINCT FROM OLD.current_offer_driver_id
          OR NEW.status IS DISTINCT FROM OLD.status) THEN
    v_desfecho := CASE
      WHEN NEW.driver_id IS NOT NULL AND NEW.driver_id = OLD.current_offer_driver_id THEN 'aceite'
      WHEN NEW.status LIKE 'cancelada%' THEN 'pedido_cancelado'
      WHEN NEW.status = 'sem_motorista' THEN 'sem_motorista'
      WHEN OLD.offer_expires_at IS NOT NULL AND OLD.offer_expires_at > now() + interval '2 seconds' THEN 'recusou'
      ELSE 'expirou' END;
    UPDATE public.ofertas_prestador_log
       SET desfecho = v_desfecho, fechada_em = now()
     WHERE booking_id = NEW.id AND categoria = 'tvde' AND desfecho IS NULL;
  END IF;

  IF NEW.current_offer_driver_id IS NOT NULL
     AND NEW.current_offer_driver_id IS DISTINCT FROM OLD.current_offer_driver_id
     AND NEW.status = 'solicitada' THEN
    SELECT d.id, d.user_id AS uid, d.name, d.is_online, d.last_heartbeat_at, d.fcm_token
      INTO v_d FROM public.drivers d WHERE d.user_id = NEW.current_offer_driver_id LIMIT 1;
    v_online := COALESCE(v_d.is_online, false) AND v_d.last_heartbeat_at > now() - interval '90 seconds';
    v_janela := CASE WHEN NEW.offer_expires_at IS NULL THEN NULL
                     ELSE GREATEST(1, EXTRACT(EPOCH FROM (NEW.offer_expires_at - now()))::int) END;
    v_reforco := EXISTS (SELECT 1 FROM public.tvde_ride_events e
                          WHERE e.ride_id = NEW.id AND e.status = 'oferta'
                            AND e.meta->>'driver_id' = NEW.current_offer_driver_id::text
                            AND COALESCE((e.meta->>'forcado')::boolean, false)
                            AND e.at > now() - interval '30 seconds');
    INSERT INTO public.ofertas_prestador_log
      (categoria, booking_id, pedido_ref, prestador_id, user_id, nome, tem_aparelho,
       janela_min, janela_s, fase, estava_online)
    VALUES
      ('tvde', NEW.id, NEW.id::text, v_d.id, NEW.current_offer_driver_id, v_d.name,
       COALESCE(v_d.fcm_token, '') <> ''
         OR EXISTS (SELECT 1 FROM public.driver_push_tokens t WHERE t.user_id = NEW.current_offer_driver_id AND t.active),
       COALESCE(CEIL(v_janela / 60.0)::int, 0), v_janela,
       CASE WHEN v_reforco THEN 'forcado' WHEN v_online THEN 'online' ELSE 'desligado' END,
       v_online);
  END IF;
  RETURN NULL;
EXCEPTION WHEN OTHERS THEN
  BEGIN
    INSERT INTO public.notification_failures (kind, source, erro)
    VALUES ('registo_oferta', '_registar_oferta_tvde', left(NEW.id::text || ': ' || SQLERRM, 500));
  EXCEPTION WHEN OTHERS THEN
    RAISE WARNING '[_registar_oferta_tvde] % (registo da falha também falhou: %)', NEW.id, SQLERRM;
  END;
  RETURN NULL;
END;
$function$;

DROP TRIGGER IF EXISTS trg_registar_oferta_tvde ON pg_temp._tvde_rides_clone;
CREATE TRIGGER trg_registar_oferta_tvde
  AFTER UPDATE OF current_offer_driver_id, status
  ON pg_temp._tvde_rides_clone
  FOR EACH ROW
  WHEN (OLD.current_offer_driver_id IS NOT NULL OR NEW.current_offer_driver_id IS NOT NULL)
  EXECUTE FUNCTION public._registar_oferta_tvde();

-- O "push_enviado/push_falhou" que o notify-tvde-driver já regista passa para a
-- linha da oferta (o painel mostra se o toque saiu).
CREATE OR REPLACE FUNCTION public._registar_toque_tvde()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
BEGIN
  IF NEW.status IN ('push_enviado', 'push_falhou')
     AND COALESCE(NEW.meta->>'kind', 'offer') = 'offer' THEN
    UPDATE public.ofertas_prestador_log
       SET push_enviados = CASE WHEN NEW.status = 'push_enviado' THEN 1 ELSE 0 END,
           push_em = NEW.at,
           push_detalhe = left(COALESCE(NEW.meta::text, ''), 500)
     WHERE booking_id = NEW.ride_id AND categoria = 'tvde' AND desfecho IS NULL
       AND (NEW.meta->>'driver_id' IS NULL OR user_id::text = NEW.meta->>'driver_id');
  END IF;
  RETURN NULL;
EXCEPTION WHEN OTHERS THEN
  RAISE WARNING '[_registar_toque_tvde] %: %', NEW.ride_id, SQLERRM;
  RETURN NULL;
END;
$function$;

DROP TRIGGER IF EXISTS trg_registar_toque_tvde ON pg_temp._tvde_ride_events_clone;
CREATE TRIGGER trg_registar_toque_tvde
  AFTER INSERT ON pg_temp._tvde_ride_events_clone
  FOR EACH ROW
  WHEN (NEW.status IN ('push_enviado', 'push_falhou'))
  EXECUTE FUNCTION public._registar_toque_tvde();

-- 14) Painel (PT-BR).
-- 14a) A rotação de um pedido/corrida: quem foi chamado, quando, como acabou.
CREATE OR REPLACE FUNCTION public.admin_ofertas_do_pedido(p_ref text)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE v_itens jsonb;
BEGIN
  IF NOT public.is_admin() THEN RAISE EXCEPTION 'admin_required'; END IF;
  SELECT COALESCE(jsonb_agg(jsonb_build_object(
           'categoria', l.categoria, 'nome', COALESCE(l.nome, '(sem nome)'),
           'user_id', l.user_id, 'fase', l.fase, 'estava_online', l.estava_online,
           'tem_aparelho', l.tem_aparelho, 'janela_s', COALESCE(l.janela_s, l.janela_min * 60),
           'oferecida_em', l.oferecida_em, 'fechada_em', l.fechada_em,
           'desfecho', COALESCE(l.desfecho, 'a decorrer'),
           'push_aparelhos', l.push_aparelhos, 'push_enviados', l.push_enviados,
           'push_em', l.push_em, 'push_detalhe', l.push_detalhe)
         ORDER BY l.oferecida_em), '[]'::jsonb)
    INTO v_itens
    FROM public.ofertas_prestador_log l
   WHERE l.pedido_ref = p_ref OR l.booking_id::text = p_ref;
  RETURN jsonb_build_object('ok', true, 'itens', v_itens);
END;
$function$;

-- 14b) Quem ligou o interruptor de reforço (e quantas vezes foi chamado hoje).
CREATE OR REPLACE FUNCTION public.admin_reforco_lista()
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE v jsonb; v_prio jsonb := public.get_setting('dispatch_forcado_prioridade');
BEGIN
  IF NOT public.is_admin() THEN RAISE EXCEPTION 'admin_required'; END IF;
  IF v_prio IS NULL OR jsonb_typeof(v_prio) <> 'array' THEN v_prio := '[]'::jsonb; END IF;
  SELECT COALESCE(jsonb_agg(jsonb_build_object(
           'user_id', d.user_id, 'nome', d.name, 'veiculo', d.vehicle_type,
           'consentiu', COALESCE(c.ligado, false), 'consentiu_em', c.atualizado_em,
           'online', d.is_online, 'visto_em', d.last_heartbeat_at,
           'ordem', (SELECT e.ord FROM jsonb_array_elements_text(v_prio) WITH ORDINALITY e(val, ord)
                      WHERE e.val = d.user_id::text LIMIT 1),
           'reforcos_hoje', (SELECT count(*) FROM public.ofertas_prestador_log l
                              WHERE l.user_id = d.user_id AND l.fase = 'forcado'
                                AND l.oferecida_em >= date_trunc('day', now() AT TIME ZONE 'Europe/Lisbon') AT TIME ZONE 'Europe/Lisbon'))
         ORDER BY COALESCE(c.ligado, false) DESC, d.name), '[]'::jsonb)
    INTO v
    FROM public.drivers d
    LEFT JOIN public.chamada_reforco_consentimento c ON c.user_id = d.user_id
   WHERE d.approval_status = 'approved' AND d.deleted_at IS NULL AND d.user_id IS NOT NULL;
  RETURN jsonb_build_object('ok', true, 'itens', v);
END;
$function$;

-- 14c) O registo geral do painel: corpo do ar (antes de 09/11) + colunas novas.
DO $bkp_log$
DECLARE v_def text := pg_get_functiondef('public.admin_ofertas_log(text,integer,integer)'::regprocedure);
BEGIN
  IF position('m10-reforco-20261109' in v_def) = 0 THEN
    INSERT INTO public.bkp_fn_reforco_20261109 (nome, definicao)
    VALUES ('admin_ofertas_log', v_def) ON CONFLICT (nome) DO NOTHING;
  END IF;
END $bkp_log$;

CREATE OR REPLACE FUNCTION public.admin_ofertas_log(p_categoria text DEFAULT NULL::text, p_dias integer DEFAULT 7, p_limite integer DEFAULT 200)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE v_out jsonb; v_resumo jsonb;
BEGIN
  -- m10-reforco-20261109: mais pedido_ref, fase, online, toque e reforço
  IF NOT public.is_admin() THEN RAISE EXCEPTION 'admin_required'; END IF;

  SELECT COALESCE(jsonb_agg(jsonb_build_object(
           'id', o.id, 'categoria', o.categoria, 'booking_id', o.booking_id,
           'pedido_ref', COALESCE(o.pedido_ref, o.booking_id::text),
           'nome', COALESCE(o.nome, '(sem nome)'),
           'tem_aparelho', o.tem_aparelho, 'janela_min', o.janela_min,
           'janela_s', COALESCE(o.janela_s, o.janela_min * 60),
           'fase', o.fase, 'estava_online', o.estava_online,
           'push_enviados', o.push_enviados, 'push_aparelhos', o.push_aparelhos, 'push_em', o.push_em,
           'oferecida_em', o.oferecida_em,
           'desfecho', COALESCE(o.desfecho, 'a decorrer'),
           'fechada_em', o.fechada_em) ORDER BY o.oferecida_em DESC), '[]'::jsonb)
    INTO v_out
    FROM (SELECT * FROM public.ofertas_prestador_log
           WHERE oferecida_em > now() - make_interval(days => GREATEST(COALESCE(p_dias,7),1))
             AND (p_categoria IS NULL OR categoria = p_categoria)
           ORDER BY oferecida_em DESC
           LIMIT GREATEST(COALESCE(p_limite,200),1)) o;

  SELECT jsonb_build_object(
      'total', count(*),
      'sem_aparelho', count(*) FILTER (WHERE NOT tem_aparelho),
      'expiraram', count(*) FILTER (WHERE desfecho = 'expirou'),
      'aceites', count(*) FILTER (WHERE desfecho = 'aceite'),
      'reforco', count(*) FILTER (WHERE fase = 'forcado'),
      'toque_falhou', count(*) FILTER (WHERE push_enviados = 0))
    INTO v_resumo
    FROM public.ofertas_prestador_log
   WHERE oferecida_em > now() - make_interval(days => GREATEST(COALESCE(p_dias,7),1))
     AND (p_categoria IS NULL OR categoria = p_categoria);

  RETURN jsonb_build_object('ok', true, 'resumo', v_resumo, 'itens', v_out);
END $function$;

-- 14d) Botão "Forçar chamada" (painel do pedido): oferece JÁ o pedido ao próximo
--      estafeta do reforço (Valdemir primeiro), com o mesmo prazo das ofertas
--      normais. Só com o interruptor ligado, só pedidos à procura de estafeta,
--      nunca por cima de uma oferta viva, nunca a quem já foi chamado em reforço
--      neste pedido. O toque sai pelo gatilho de sempre (tr_notify_driver_on_offer).
CREATE OR REPLACE FUNCTION public.admin_forcar_chamada(p_order_id text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  o        record;
  v_prox   record;
  v_feitos uuid[];
  v_ttl    integer;
  v_ate    timestamptz;
  v_n      integer;
  v_nome   text;
BEGIN
  IF NOT public.is_admin() THEN RAISE EXCEPTION 'admin_required' USING ERRCODE = '42501'; END IF;
  IF NOT COALESCE((public.get_setting('dispatch_forcado_ligado') #>> '{}')::boolean, false) THEN
    RETURN jsonb_build_object('ok', false, 'motivo', 'reforco_desligado');
  END IF;

  SELECT x.id, x.status, x.assigned_driver_id, x.current_driver_offer_id, x.driver_offer_expires_at
    INTO o FROM public.orders x WHERE x.id = p_order_id FOR UPDATE;
  IF NOT FOUND THEN
    RETURN jsonb_build_object('ok', false, 'motivo', 'pedido_nao_encontrado');
  END IF;
  IF o.status IS DISTINCT FROM 'callingDriver' OR o.assigned_driver_id IS NOT NULL THEN
    RETURN jsonb_build_object('ok', false, 'motivo', 'pedido_nao_esta_a_chamar', 'estado', o.status);
  END IF;
  IF o.current_driver_offer_id IS NOT NULL AND o.driver_offer_expires_at > now() THEN
    RETURN jsonb_build_object('ok', false, 'motivo', 'oferta_a_decorrer', 'ate', o.driver_offer_expires_at);
  END IF;

  SELECT COALESCE(array_agg(DISTINCT l.user_id) FILTER (WHERE l.user_id IS NOT NULL), '{}'::uuid[])
    INTO v_feitos
    FROM public.ofertas_prestador_log l
   WHERE l.pedido_ref = p_order_id AND l.categoria IN ('entrega', 'favor') AND l.fase = 'forcado';
  SELECT f.user_id, f.driver_id INTO v_prox
    FROM public._dispatch_forcados_entrega(p_order_id) f
   WHERE NOT (f.user_id = ANY(v_feitos))
   ORDER BY f.ordem, f.visto_em DESC
   LIMIT 1;
  IF NOT FOUND THEN
    RETURN jsonb_build_object('ok', false, 'motivo', 'ninguem_disponivel',
                              'ja_chamados', cardinality(v_feitos));
  END IF;

  v_ttl := GREATEST(COALESCE((public.get_setting('dispatch_offer_timeout_seconds') #>> '{}')::int, 60), 40);
  v_ate := now() + make_interval(secs => v_ttl);
  PERFORM set_config('bora.caminho_oficial', 'admin_forcar_chamada', true);
  PERFORM set_config('bora.oferta_fase', 'forcado', true);
  UPDATE public.orders
     SET current_driver_offer_id = v_prox.user_id::text,
         driver_offer_expires_at = v_ate
   WHERE id = p_order_id AND status = 'callingDriver' AND assigned_driver_id IS NULL
     AND (current_driver_offer_id IS NULL OR driver_offer_expires_at IS NULL OR driver_offer_expires_at <= now());
  GET DIAGNOSTICS v_n = ROW_COUNT;
  PERFORM set_config('bora.oferta_fase', '', true);
  IF v_n <> 1 THEN
    RETURN jsonb_build_object('ok', false, 'motivo', 'nao_deu_para_oferecer');
  END IF;

  SELECT d.name INTO v_nome FROM public.drivers d WHERE d.id = v_prox.driver_id;
  INSERT INTO public.admin_audit_log (admin_id, admin_email, action, entity_type, entity_id_text, details)
  VALUES (auth.uid(), (SELECT u.email FROM auth.users u WHERE u.id = auth.uid()),
          'forcar_chamada_reforco', 'order', p_order_id,
          jsonb_build_object('user_id', v_prox.user_id, 'nome', v_nome, 'expira_em', v_ate,
                             'origem', 'painel: quem foi chamado'));

  RETURN jsonb_build_object('ok', true, 'user_id', v_prox.user_id, 'nome', v_nome, 'expira_em', v_ate);
END;
$function$;

-- 15) Quem pode chamar o quê. Funções novas fechadas a anon; internas só o serviço.
REVOKE ALL ON FUNCTION public._reforco_carimbo() FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public._registar_oferta_entrega() FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public._registar_oferta_tvde() FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public._registar_toque_tvde() FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public._dispatch_nao_cancelar_cedo() FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public._tvde_chamada_de_reforco() FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.dispatch_reforco_horario_ok(time, time, time) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.dispatch_fase_decidir(uuid[], jsonb, uuid[], boolean, integer, integer, integer) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public._dispatch_candidatos_online(text) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public._dispatch_forcados_entrega(text) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.dispatch_fase_entrega(text) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.dispatch_candidatos_entrega(text) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.dispatch_fases_sweep() FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public._tvde_forcados(uuid) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.dispatch_reforco_horario_ok(time, time, time) TO service_role;
GRANT EXECUTE ON FUNCTION public.dispatch_fase_decidir(uuid[], jsonb, uuid[], boolean, integer, integer, integer) TO service_role;
GRANT EXECUTE ON FUNCTION public._dispatch_candidatos_online(text) TO service_role;
GRANT EXECUTE ON FUNCTION public._dispatch_forcados_entrega(text) TO service_role;
GRANT EXECUTE ON FUNCTION public.dispatch_fase_entrega(text) TO service_role;
GRANT EXECUTE ON FUNCTION public.dispatch_candidatos_entrega(text) TO service_role;
GRANT EXECUTE ON FUNCTION public.dispatch_fases_sweep() TO service_role;
-- Painel: só admins (a função confere is_admin()).
REVOKE ALL ON FUNCTION public.admin_ofertas_do_pedido(text) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.admin_reforco_lista() FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.admin_ofertas_log(text, integer, integer) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.admin_forcar_chamada(text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.admin_ofertas_do_pedido(text) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.admin_reforco_lista() TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.admin_ofertas_log(text, integer, integer) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.admin_forcar_chamada(text) TO authenticated, service_role;

-- 16) Varredura agendada (15 s). Com o interruptor desligado devolve logo
--     {"desligado":true} e não faz nada.
-- [cron retirado na prova]
$mig_m10_20261109$;
  v_r    text := '';
  v_txt  text;
  v_txt2 text;
  v_j    jsonb;
  v_n    int;
  v_md5_antes text;
  v_val  uuid := 'e355fde0-b634-48ba-bce1-e2a4466c4cc2';  -- Valdemir (user_id)
  v_admin uuid;
  v_ped  text;
  v_ride uuid;
  a  uuid := '00000000-0000-0000-0000-00000000000a';
  b  uuid := '00000000-0000-0000-0000-00000000000b';
  f1 uuid := '00000000-0000-0000-0000-0000000000f1';
  f2 uuid := '00000000-0000-0000-0000-0000000000f2';
  v_dec int := 0;
begin
  perform set_config('lock_timeout', '3000', true);
  v_r := 'md5_migracao_executada=' || md5(v_mig);

  -- ── 0) ANTES da migração ───────────────────────────────────────────────────
  -- 0a) defeito da 070000 de 10/10: tipo enumerado comparado com ''.
  begin
    perform coalesce(x.cancellation_initiator, '') from public.orders x limit 1;
    v_r := v_r || ' | 0a enum_vazio=passou(?)';
  exception when invalid_text_representation then
    v_r := v_r || ' | 0a defeito_10_10 COALESCE(cancellation_initiator,'''')=ERRO_22P02';
  end;
  -- 0b) o registo de ofertas de hoje recusa entregas (regra de 31/10).
  begin
    insert into public.ofertas_prestador_log (categoria, booking_id, prestador_id, tem_aparelho, janela_min)
    values ('entrega', gen_random_uuid(), gen_random_uuid(), true, 1);
    v_r := v_r || ' | 0b registo_aceitava_entrega(?)';
  exception when check_violation then
    v_r := v_r || ' | 0b registo_hoje_recusa_entrega=check_violation';
  end;
  -- 0c) candidatos de hoje para os 40 pedidos mais recentes (só leitura).
  create temp table _ids as select id from public.orders order by created_at desc limit 40;
  v_md5_antes := md5(pg_get_functiondef('public.dispatch_candidatos_entrega(text)'::regprocedure));
  create temp table _antes as
    select o.id as pedido, c.* from _ids o cross join lateral public.dispatch_candidatos_entrega(o.id) c;
  select count(*) into v_n from _antes;
  v_r := v_r || ' | 0c md5_candidatos_no_ar=' || v_md5_antes || ' linhas=' || v_n;

  -- Clones sem gatilhos, onde a migração da prova põe os gatilhos.
  create temp table _orders_clone (like public.orders including defaults);
  create temp table _tvde_rides_clone (like public.tvde_rides including defaults);
  create temp table _tvde_ride_events_clone (like public.tvde_ride_events including defaults);
  execute 'create function pg_temp.o(u uuid, f text) returns jsonb language sql immutable as '
       || '$x$ select jsonb_build_object(''user_id'', u, ''fase'', f) $x$';

  -- ── 1) Aplicar duas vezes (idempotente) ───────────────────────────────────
  execute v_mig;
  execute v_mig;
  v_r := v_r || ' | 1 migracao_2_vezes=ok';

  -- ── 2) Candidatos online = cópia letra a letra do corpo do ar ─────────────
  v_txt := md5(replace(pg_get_functiondef('public._dispatch_candidatos_online(text)'::regprocedure),
                       'public._dispatch_candidatos_online(', 'public.dispatch_candidatos_entrega('));
  if v_txt <> v_md5_antes then raise exception 'PROVA_FALHOU 2 copia diferente (%)', v_txt; end if;
  select md5(definicao) into v_txt from public.bkp_fn_reforco_20261109 where nome = 'dispatch_candidatos_entrega';
  if v_txt is distinct from v_md5_antes then raise exception 'PROVA_FALHOU 2 backup diferente'; end if;
  select string_agg(nome, ',' order by nome) into v_txt from public.bkp_fn_reforco_20261109;
  v_r := v_r || ' | 2 copia_online_md5=igual_ao_ar backup=' || v_txt;

  -- ── 3) Interruptores nascem desligados ────────────────────────────────────
  if coalesce((public.get_setting('dispatch_forcado_ligado') #>> '{}')::boolean, true)
     or coalesce((public.get_setting('tvde_forcado_ligado') #>> '{}')::boolean, true) then
    raise exception 'PROVA_FALHOU 3 interruptor ligado';
  end if;
  v_r := v_r || ' | 3 dispatch_forcado_ligado=false tvde_forcado_ligado=false';

  -- ── 4) Desligado: o motor recebe EXATAMENTE a lista de antes ───────────────
  select count(*) into v_n from (
    (select * from _antes
     except all
     select o.id, c.* from _ids o cross join lateral public.dispatch_candidatos_entrega(o.id) c)
    union all
    (select o.id, c.* from _ids o cross join lateral public.dispatch_candidatos_entrega(o.id) c
     except all
     select * from _antes)) d;
  if v_n <> 0 then raise exception 'PROVA_FALHOU 4 lista mudou (% diferencas)', v_n; end if;
  v_j := public.dispatch_fase_entrega((select id from _ids limit 1));
  v_txt := (v_j->>'fase') || '/' || (v_j->>'motivo');
  v_j := public.dispatch_fases_sweep();
  v_r := v_r || ' | 4 desligado: diferencas_na_lista=0 fase=' || v_txt || ' varredura=' || v_j::text;

  -- ── 5) Decisão pura (regra do Danilo) ─────────────────────────────────────
  -- a) desligado
  v_j := public.dispatch_fase_decidir(array[a,b], '[]', array[f1], false, 2, 2, 1);
  if v_j->>'fase' <> 'online1' then raise exception 'PROVA_FALHOU 5a %', v_j; end if; v_dec := v_dec + 1;
  -- b) dois online, ninguém chamado → online
  v_j := public.dispatch_fase_decidir(array[a,b], '[]', array[f1,f2], true, 2, 2, 1);
  if v_j->>'fase' <> 'online1' then raise exception 'PROVA_FALHOU 5b %', v_j; end if; v_dec := v_dec + 1;
  -- c) uma volta só → ainda online
  v_j := public.dispatch_fase_decidir(array[a,b], jsonb_build_array(pg_temp.o(a,'online1'), pg_temp.o(b,'online1')), array[f1,f2], true, 2, 2, 1);
  if v_j->>'fase' <> 'online1' then raise exception 'PROVA_FALHOU 5c %', v_j; end if; v_dec := v_dec + 1;
  -- d) duas voltas → reforço ao 1.º da lista (Valdemir no ar)
  v_j := public.dispatch_fase_decidir(array[a,b], jsonb_build_array(pg_temp.o(a,'online1'), pg_temp.o(b,'online1'), pg_temp.o(a,'online1'), pg_temp.o(b,'online1')), array[f1,f2], true, 2, 2, 1);
  if v_j->>'fase' <> 'forcado' or v_j->>'user_id' <> f1::text then raise exception 'PROVA_FALHOU 5d %', v_j; end if; v_dec := v_dec + 1;
  -- e) depois do 1.º → o 2.º (um de cada vez)
  v_j := public.dispatch_fase_decidir(array[a,b], jsonb_build_array(pg_temp.o(a,'online1'), pg_temp.o(b,'online1'), pg_temp.o(a,'online1'), pg_temp.o(b,'online1'), pg_temp.o(f1,'forcado')), array[f1,f2], true, 2, 2, 1);
  if v_j->>'fase' <> 'forcado' or v_j->>'user_id' <> f2::text then raise exception 'PROVA_FALHOU 5e %', v_j; end if; v_dec := v_dec + 1;
  -- f) depois dos dois → volta aos online
  v_j := public.dispatch_fase_decidir(array[a,b], jsonb_build_array(pg_temp.o(a,'online1'), pg_temp.o(b,'online1'), pg_temp.o(a,'online1'), pg_temp.o(b,'online1'), pg_temp.o(f1,'forcado'), pg_temp.o(f2,'forcado')), array[f1,f2], true, 2, 2, 1);
  if v_j->>'fase' <> 'online2' then raise exception 'PROVA_FALHOU 5f %', v_j; end if; v_dec := v_dec + 1;
  -- g) depois da volta final → esgotado (só então pode cancelar pelo tempo)
  v_j := public.dispatch_fase_decidir(array[a,b], jsonb_build_array(pg_temp.o(a,'online1'), pg_temp.o(b,'online1'), pg_temp.o(a,'online1'), pg_temp.o(b,'online1'), pg_temp.o(f1,'forcado'), pg_temp.o(f2,'forcado'), pg_temp.o(a,'online2'), pg_temp.o(b,'online2')), array[f1,f2], true, 2, 2, 1);
  if v_j->>'fase' <> 'esgotado' then raise exception 'PROVA_FALHOU 5g %', v_j; end if; v_dec := v_dec + 1;
  -- h) só um online: volta a ele (2 voltas) antes do reforço
  v_j := public.dispatch_fase_decidir(array[a], jsonb_build_array(pg_temp.o(a,'online1')), array[f1], true, 2, 2, 1);
  if v_j->>'fase' <> 'online1' then raise exception 'PROVA_FALHOU 5h %', v_j; end if; v_dec := v_dec + 1;
  -- i) ninguém online → reforço logo
  v_j := public.dispatch_fase_decidir('{}'::uuid[], '[]', array[f1], true, 2, 2, 1);
  if v_j->>'fase' <> 'forcado' or v_j->>'user_id' <> f1::text then raise exception 'PROVA_FALHOU 5i %', v_j; end if; v_dec := v_dec + 1;
  -- j) quem está na lista mas está online é saltado
  v_j := public.dispatch_fase_decidir(array[a], jsonb_build_array(pg_temp.o(a,'online1'), pg_temp.o(a,'online1')), array[a,f1], true, 2, 2, 1);
  if v_j->>'fase' <> 'forcado' or v_j->>'user_id' <> f1::text then raise exception 'PROVA_FALHOU 5j %', v_j; end if; v_dec := v_dec + 1;
  -- k) ninguém consentiu → volta aos online
  v_j := public.dispatch_fase_decidir(array[a], jsonb_build_array(pg_temp.o(a,'online1'), pg_temp.o(a,'online1')), '{}'::uuid[], true, 2, 2, 1);
  if v_j->>'fase' <> 'online2' then raise exception 'PROVA_FALHOU 5k %', v_j; end if; v_dec := v_dec + 1;
  -- l) linha do registo sem user_id não estraga a conta
  v_j := public.dispatch_fase_decidir('{}'::uuid[], jsonb_build_array(jsonb_build_object('fase','forcado'), pg_temp.o(f1,'forcado')), array[f1,f2], true, 2, 2, 1);
  if v_j->>'fase' <> 'forcado' or v_j->>'user_id' <> f2::text then raise exception 'PROVA_FALHOU 5l %', v_j; end if; v_dec := v_dec + 1;
  v_r := v_r || ' | 5 decisoes=' || v_dec || '/12';

  -- ── 6) Horário do reforço ─────────────────────────────────────────────────
  if not (public.dispatch_reforco_horario_ok('08:00', '08:00', '23:00')
          and not public.dispatch_reforco_horario_ok('07:59', '08:00', '23:00')
          and public.dispatch_reforco_horario_ok('22:59', '08:00', '23:00')
          and not public.dispatch_reforco_horario_ok('23:00', '08:00', '23:00')
          and public.dispatch_reforco_horario_ok('01:00', '22:00', '06:00')
          and not public.dispatch_reforco_horario_ok('12:00', '22:00', '06:00')) then
    raise exception 'PROVA_FALHOU 6 horario';
  end if;
  v_r := v_r || ' | 6 horario=ok';

  -- ── 7) Defeitos de 10/10 corrigidos ───────────────────────────────────────
  perform x.cancellation_initiator::text is not distinct from 'system' from public.orders x limit 1;
  insert into public.ofertas_prestador_log (categoria, pedido_ref, prestador_id, tem_aparelho, janela_min)
  values ('entrega', 'prova-m10', gen_random_uuid(), true, 1);
  v_r := v_r || ' | 7 enum_como_texto=ok registo_aceita_entrega=ok';

  -- ── 8) LIGADO só nesta transação; Valdemir consentiu; horário 00:00-23:59 ─
  update public.platform_settings set value = 'true' where key in ('dispatch_forcado_ligado', 'tvde_forcado_ligado');
  update public.platform_settings set value = '"00:00"' where key = 'dispatch_forcado_horario_inicio';
  update public.platform_settings set value = '"23:59"' where key = 'dispatch_forcado_horario_fim';
  insert into public.chamada_reforco_consentimento (user_id, ligado) values (v_val, true);
  select x.id into v_ped from public.orders x
   where x.status = 'delivered' and not coalesce(x.is_test_order, false) and x.service_type is distinct from 'errand'
   order by x.created_at desc limit 1;
  select string_agg(f.user_id::text || '#' || f.ordem, ',' order by f.ordem) into v_txt
    from public._dispatch_forcados_entrega(v_ped) f;
  select f.user_id::text into v_txt2 from public._dispatch_forcados_entrega(v_ped) f order by f.ordem, f.visto_em desc limit 1;
  if v_txt2 is distinct from v_val::text then raise exception 'PROVA_FALHOU 8 Valdemir nao e o 1.o (%)', v_txt; end if;
  select count(*) into v_n from public._dispatch_candidatos_online(v_ped);
  v_r := v_r || ' | 8 pedido_lido=' || left(v_ped, 8) || ' online_agora=' || v_n || ' lista_reforco=' || v_txt;

  -- ── 9) Gatilhos de entregas no CLONE (sem pg_net) ─────────────────────────
  insert into _orders_clone select * from public.orders where id = v_ped;
  update _orders_clone set status = 'callingDriver', assigned_driver_id = null, driver_id = null,
         current_driver_offer_id = null, driver_offer_expires_at = null, dispatch_calling_since = now(),
         cancellation_initiator = null, cancel_reason = null, dispatch_extended_until = null
   where id = v_ped;
  -- 9a) os online deste pedido já tiveram as 2 voltas (registo montado)
  insert into public.ofertas_prestador_log (categoria, pedido_ref, prestador_id, user_id, nome, tem_aparelho,
                                            janela_min, janela_s, fase, estava_online, desfecho, fechada_em)
  select 'entrega', v_ped, c.driver_id, coalesce(c.user_id, c.driver_id), 'prova', true, 1, 60, 'online1', true, 'expirou', now()
    from public._dispatch_candidatos_online(v_ped) c cross join generate_series(1, 2);
  v_j := public.dispatch_fase_entrega(v_ped);
  if v_j->>'fase' <> 'forcado' or v_j->>'user_id' <> v_val::text then raise exception 'PROVA_FALHOU 9a %', v_j; end if;
  -- 9b) o motor recebe SÓ o Valdemir
  select string_agg(coalesce(c.user_id, c.driver_id)::text, ',') into v_txt from public.dispatch_candidatos_entrega(v_ped) c;
  if v_txt is distinct from v_val::text then raise exception 'PROVA_FALHOU 9b motor recebe %', v_txt; end if;
  -- 9c) cancelamento por tempo a meio das fases → adiado (0 linhas mudadas)
  update _orders_clone set status = 'cancelled', cancellation_initiator = 'system', cancel_reason = 'dispatch_safety_timeout'
   where id = v_ped and status = 'callingDriver';
  get diagnostics v_n = row_count;
  if v_n <> 0 then raise exception 'PROVA_FALHOU 9c cancelou a meio das fases'; end if;
  -- 9d) oferta ao Valdemir → registo 'forcado', desligado
  update _orders_clone set current_driver_offer_id = v_val::text, driver_offer_expires_at = now() + interval '60 seconds'
   where id = v_ped;
  select l.fase || '/online=' || coalesce(l.estava_online::text, '?') || '/' || l.categoria || '/aparelho=' || l.tem_aparelho
    into v_txt from public.ofertas_prestador_log l
   where l.pedido_ref = v_ped and l.desfecho is null order by l.oferecida_em desc limit 1;
  if v_txt not like 'forcado/online=false/%' then raise exception 'PROVA_FALHOU 9d registo %', v_txt; end if;
  -- 9e) a oferta acaba → o registo fecha; fase seguinte
  update _orders_clone set current_driver_offer_id = null, driver_offer_expires_at = null where id = v_ped;
  select l.desfecho into v_txt2 from public.ofertas_prestador_log l
   where l.pedido_ref = v_ped and l.fase = 'forcado' order by l.oferecida_em desc limit 1;
  if v_txt2 is null then raise exception 'PROVA_FALHOU 9e registo nao fechou'; end if;
  v_j := public.dispatch_fase_entrega(v_ped);
  v_r := v_r || ' | 9 fase=forcado(Valdemir) motor_recebe=so_Valdemir cancelar_a_meio=adiado registo=' || v_txt
             || ' fechou=' || v_txt2 || ' depois=' || (v_j->>'fase');
  -- 9f) volta final aos online → esgotado
  insert into public.ofertas_prestador_log (categoria, pedido_ref, prestador_id, user_id, nome, tem_aparelho,
                                            janela_min, janela_s, fase, estava_online, desfecho, fechada_em)
  select 'entrega', v_ped, c.driver_id, coalesce(c.user_id, c.driver_id), 'prova', true, 1, 60, 'online2', true, 'expirou', now()
    from public._dispatch_candidatos_online(v_ped) c;
  v_j := public.dispatch_fase_entrega(v_ped);
  if v_j->>'fase' <> 'esgotado' then raise exception 'PROVA_FALHOU 9f %', v_j; end if;
  -- 9g) esgotado: o motor recebe os online de sempre (nunca menos do que hoje)
  select count(*) into v_n from (
    (select * from public.dispatch_candidatos_entrega(v_ped) except all select * from public._dispatch_candidatos_online(v_ped))
    union all
    (select * from public._dispatch_candidatos_online(v_ped) except all select * from public.dispatch_candidatos_entrega(v_ped))) d;
  if v_n <> 0 then raise exception 'PROVA_FALHOU 9g'; end if;
  -- 9h) agora o cancelamento por tempo passa (1 linha)
  update _orders_clone set status = 'cancelled', cancellation_initiator = 'system', cancel_reason = 'dispatch_safety_timeout'
   where id = v_ped and status = 'callingDriver';
  get diagnostics v_n = row_count;
  if v_n <> 1 then raise exception 'PROVA_FALHOU 9h nao cancelou no fim'; end if;
  v_r := v_r || ' | 9 esgotado: motor=online_de_sempre cancelar_no_fim=passa';

  -- ── 10) TVDE no CLONE ─────────────────────────────────────────────────────
  select r.id into v_ride from public.tvde_rides r order by r.created_at desc limit 1;
  insert into _tvde_rides_clone select * from public.tvde_rides where id = v_ride;
  update _tvde_rides_clone set status = 'solicitada', reservation_status = null, source = 'app',
         dispatch_hold_reason = null, driver_id = null, current_offer_driver_id = null,
         offer_expires_at = null, cancel_reason = null
   where id = v_ride;
  -- 10a) só o Valdemir consentiu, mas ele desligou o TVDE na app → fecha como hoje
  update _tvde_rides_clone set status = 'sem_motorista', current_offer_driver_id = null, offer_expires_at = null
   where id = v_ride;
  select c.status into v_txt from _tvde_rides_clone c where c.id = v_ride;
  if v_txt <> 'sem_motorista' then raise exception 'PROVA_FALHOU 10a Valdemir chamado no TVDE (%)', v_txt; end if;
  v_r := v_r || ' | 10a tvde_so_Valdemir(TVDE desligado na app dele)=' || v_txt;
  -- 10b) outro motorista TVDE elegível e desligado consente → fica à procura com oferta de reforço
  select d.user_id into v_admin from public.drivers d
   where d.vehicle_type = 'carro_passageiros' and d.approval_status = 'approved' and d.user_id is not null
     and d.deleted_at is null and coalesce(d.is_banned, false) = false and d.user_id <> v_val
     and public.aceita_papel(d.user_id, 'driver')
     and not (coalesce(d.is_online, false) and d.last_heartbeat_at > now() - make_interval(
              secs => coalesce((public.get_setting('tvde_heartbeat_window_seconds') #>> '{}')::int, 90)))
     and (coalesce(d.fcm_token, '') <> '' or exists (select 1 from public.driver_push_tokens t
          where t.user_id = d.user_id and t.active and coalesce(t.platform, '') not ilike 'web%'))
     and greatest(coalesce(d.last_heartbeat_at, '-infinity'), coalesce((select max(t.last_used_at)
          from public.driver_push_tokens t where t.user_id = d.user_id and t.active), '-infinity')) > now() - interval '168 hours'
     and not public.tvde_driver_reservation_locked(d.user_id)
     and public.tvde_driver_offer_allowed(d.user_id, v_ride)
     and not exists (select 1 from public.tvde_rides r2 where r2.driver_id = d.user_id
                      and r2.status in ('motorista_atribuido','motorista_a_caminho','motorista_chegou','em_andamento'))
   order by d.last_heartbeat_at desc nulls last limit 1;
  if v_admin is null then
    v_r := v_r || ' | 10b sem_motorista_tvde_elegivel_desligado_agora(nao_testado)';
  else
    insert into public.chamada_reforco_consentimento (user_id, ligado) values (v_admin, true)
      on conflict (user_id) do update set ligado = true;
    update _tvde_rides_clone set status = 'solicitada', cancel_reason = null where id = v_ride;
    update _tvde_rides_clone set status = 'sem_motorista', current_offer_driver_id = null, offer_expires_at = null
     where id = v_ride;
    select c.status || '/' || coalesce(c.current_offer_driver_id::text, '-') into v_txt from _tvde_rides_clone c where c.id = v_ride;
    select l.fase into v_txt2 from public.ofertas_prestador_log l
     where l.categoria = 'tvde' and l.booking_id = v_ride and l.desfecho is null order by l.oferecida_em desc limit 1;
    if v_txt <> 'solicitada/' || v_admin::text or v_txt2 is distinct from 'forcado' then
      raise exception 'PROVA_FALHOU 10b % %', v_txt, v_txt2;
    end if;
    v_r := v_r || ' | 10b tvde_outro_consentiu=solicitada+oferta_de_reforco registo=' || v_txt2;
  end if;
  v_admin := null;
  -- 10c) reserva fecha como hoje (sem reforço)
  update _tvde_rides_clone set reservation_status = 'agendada', current_offer_driver_id = null, offer_expires_at = null,
         status = 'solicitada'
   where id = v_ride;
  update _tvde_rides_clone set status = 'sem_motorista' where id = v_ride;
  select c.status into v_txt2 from _tvde_rides_clone c where c.id = v_ride;
  if v_txt2 <> 'sem_motorista' then raise exception 'PROVA_FALHOU 10c reserva %', v_txt2; end if;
  v_r := v_r || ' | 10c tvde_reserva=sem_motorista(como_hoje)';

  -- ── 11) Painel ────────────────────────────────────────────────────────────
  begin
    perform public.admin_reforco_lista();
    raise exception 'PROVA_FALHOU 11 sem admin passou';
  exception when others then
    if sqlerrm like 'PROVA_FALHOU%' then raise; end if;
    v_txt := sqlerrm;
  end;
  select u.id into v_admin from auth.users u where u.email = 'nilofulfarotuga@gmail.com' limit 1;
  perform set_config('request.jwt.claims', json_build_object('sub', v_admin, 'role', 'authenticated')::text, true);
  perform set_config('request.jwt.claim.sub', v_admin::text, true);
  v_j := public.admin_reforco_lista();
  select e->>'consentiu' || '#ordem=' || coalesce(e->>'ordem', '-') into v_txt2
    from jsonb_array_elements(v_j->'itens') e where e->>'user_id' = v_val::text;
  v_r := v_r || ' | 11 sem_admin=' || v_txt || ' lista_Valdemir_consentiu=' || coalesce(v_txt2, '?');
  v_j := public.admin_ofertas_do_pedido(v_ped);
  select string_agg(e->>'fase' || ':' || (e->>'desfecho'), ',') into v_txt
    from jsonb_array_elements(v_j->'itens') e where e->>'fase' = 'forcado';
  v_r := v_r || ' rotacao_do_pedido=' || jsonb_array_length(v_j->'itens') || '_linhas reforco=' || coalesce(v_txt, '-');
  v_j := public.admin_ofertas_log(null, 1, 20);
  v_r := v_r || ' log_resumo_tem_reforco=' || (v_j->'resumo' ? 'reforco');
  v_j := public.admin_forcar_chamada(v_ped);
  if v_j->>'motivo' is distinct from 'pedido_nao_esta_a_chamar' then raise exception 'PROVA_FALHOU 11 botao %', v_j; end if;
  v_txt := v_j->>'motivo';
  update public.platform_settings set value = 'false' where key = 'dispatch_forcado_ligado';
  v_j := public.admin_forcar_chamada(v_ped);
  if v_j->>'motivo' is distinct from 'reforco_desligado' then raise exception 'PROVA_FALHOU 11 botao desligado %', v_j; end if;
  v_r := v_r || ' botao_pedido_entregue=' || v_txt || ' botao_desligado=' || (v_j->>'motivo');
  perform set_config('request.jwt.claims', '', true);
  perform set_config('request.jwt.claim.sub', '', true);

  -- ── 12) Quem pode chamar; tabelas escritas sem pg_net; cron fora ──────────
  select count(*) into v_n from pg_proc p
   where p.pronamespace = 'public'::regnamespace
     and p.proname in ('dispatch_reforco_horario_ok','dispatch_fase_decidir','_dispatch_candidatos_online',
                       '_dispatch_forcados_entrega','dispatch_fase_entrega','dispatch_candidatos_entrega',
                       '_registar_oferta_entrega','_dispatch_nao_cancelar_cedo','dispatch_fases_sweep',
                       '_tvde_forcados','_tvde_chamada_de_reforco','_registar_oferta_tvde','_registar_toque_tvde',
                       '_reforco_carimbo','admin_ofertas_do_pedido','admin_reforco_lista','admin_ofertas_log',
                       'admin_forcar_chamada')
     and has_function_privilege('anon', p.oid, 'execute');
  if v_n <> 0 then raise exception 'PROVA_FALHOU 12 anon executa % funcoes', v_n; end if;
  select string_agg(p.proname, ',' order by p.proname) into v_txt from pg_proc p
   where p.pronamespace = 'public'::regnamespace
     and p.proname in ('dispatch_reforco_horario_ok','dispatch_fase_decidir','_dispatch_candidatos_online',
                       '_dispatch_forcados_entrega','dispatch_fase_entrega','dispatch_candidatos_entrega',
                       '_registar_oferta_entrega','_dispatch_nao_cancelar_cedo','dispatch_fases_sweep',
                       '_tvde_forcados','_tvde_chamada_de_reforco','_registar_oferta_tvde','_registar_toque_tvde',
                       '_reforco_carimbo','admin_ofertas_do_pedido','admin_reforco_lista','admin_ofertas_log',
                       'admin_forcar_chamada')
     and has_function_privilege('authenticated', p.oid, 'execute');
  if v_txt is distinct from 'admin_forcar_chamada,admin_ofertas_do_pedido,admin_ofertas_log,admin_reforco_lista' then
    raise exception 'PROVA_FALHOU 12 authenticated executa %', v_txt;
  end if;
  if has_table_privilege('anon', 'public.chamada_reforco_consentimento', 'select')
     or has_table_privilege('authenticated', 'public.bkp_fn_reforco_20261109', 'select') then
    raise exception 'PROVA_FALHOU 12 tabela aberta';
  end if;
  select count(*) into v_n
    from pg_trigger t join pg_proc p on p.oid = t.tgfoid
   where t.tgrelid in ('public.ofertas_prestador_log'::regclass, 'public.platform_settings'::regclass,
                       'public.chamada_reforco_consentimento'::regclass, 'public.tvde_ride_events'::regclass,
                       'public.bkp_fn_reforco_20261109'::regclass)
     and not t.tgisinternal
     and pg_get_functiondef(p.oid) ~* 'net\.http|http_post|notify-';
  if v_n <> 0 then raise exception 'PROVA_FALHOU 12 tabela escrita tem gatilho com pg_net'; end if;
  select count(*) into v_n from pg_trigger t
   where t.tgrelid in ('pg_temp._orders_clone'::regclass, 'pg_temp._tvde_rides_clone'::regclass,
                       'pg_temp._tvde_ride_events_clone'::regclass) and not t.tgisinternal;
  v_r := v_r || ' | 12 anon=0_funcoes authenticated=' || v_txt || ' tabelas_escritas_sem_pg_net=ok gatilhos_nos_clones=' || v_n
             || ' cron_na_prova=' || (select count(*) from cron.job where jobname = 'dispatch_fases_sweep');

  raise exception 'PROVA_OK %', v_r;
end $prova$;
