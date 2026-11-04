-- Missão checkin-escada-premios-2026-11-04, bloco C (antiabuso, decisão do conselho; Danilo 04/11 09:58
-- "Vai, pode fazer."): um prémio do check-in levantado por pessoa a cada N dias (defeito 30).
-- Dentro do intervalo o cliente continua a fazer check-in e a ganhar tokens; o prémio conquistado fica
-- GUARDADO (não se perde) e o calendário mostra "próximo prémio disponível a DD/MM".
-- Não mexe em tokens, preços nem comissões. 0 ou nulo = sem intervalo.

insert into public.platform_settings (key, value)
values ('checkin_premio_intervalo_dias', '30'::jsonb)
on conflict (key) do nothing;

-- Quando o cliente pode levantar o próximo prémio (nulo = já pode).
create or replace function public._checkin_premio_proximo_em(p_uid uuid)
 returns timestamptz language sql stable security definer set search_path to 'public'
as $function$
  select case when coalesce(d.dias, 0) <= 0 then null
              else (select max(v.emitido_em) from public.checkin_premios_vales v
                     where v.user_id = p_uid and v.origem = 'checkin' and v.estado <> 'anulado')
                   + make_interval(days => d.dias) end
    from (select least(greatest(coalesce((public._checkin_marco_cfg('checkin_premio_intervalo_dias', '30'::jsonb) #>> '{}')::int, 30), 0), 365) as dias) d;
$function$;
revoke all on function public._checkin_premio_proximo_em(uuid) from public, anon, authenticated;

create or replace function public._checkin_premio_bloqueado(p_uid uuid)
 returns boolean language sql stable security definer set search_path to 'public'
as $function$
  select coalesce(public._checkin_premio_proximo_em(p_uid) > now(), false);
$function$;
revoke all on function public._checkin_premio_bloqueado(uuid) from public, anon, authenticated;

-- Levantar: dentro do intervalo não emite e NÃO apaga o prémio guardado.
CREATE OR REPLACE FUNCTION public._checkin_escada_levantar(p_uid uuid, p_marco jsonb, p_inicio date, p_reinicio date, p_motivo text)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_vale uuid;
BEGIN
  IF public._checkin_premio_bloqueado(p_uid) THEN
    RETURN NULL;
  END IF;
  v_vale := public._checkin_vale_emitir(p_uid, p_marco, p_inicio, 'checkin', NULL, p_motivo);
  UPDATE public.checkin_escada
     SET guardado_chave = NULL, guardado_dia = NULL, guardado_titulo = NULL, guardado_tipo = NULL,
         guardado_marco = NULL, guardado_ciclo_inicio = NULL, guardado_em = NULL, garantido_ate = NULL,
         decisao = 'pendente',
         reinicio_data = CASE WHEN v_vale IS NULL THEN reinicio_data
                              ELSE GREATEST(COALESCE(reinicio_data, p_reinicio), p_reinicio) END,
         levantados = levantados + CASE WHEN v_vale IS NULL THEN 0 ELSE 1 END,
         ultimo_vale_id = COALESCE(v_vale, ultimo_vale_id),
         ultimo_levantado_em = CASE WHEN v_vale IS NULL THEN ultimo_levantado_em ELSE now() END,
         atualizado_em = now()
   WHERE user_id = p_uid;
  RETURN v_vale;
END;
$function$;

-- Chegou a um degrau: no último só levanta sozinho se puder; senão guarda (como os outros degraus).
CREATE OR REPLACE FUNCTION public._checkin_escada_chegou(p_uid uuid, p_marco jsonb, p_inicio date, p_data date)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_row      public.checkin_escada%ROWTYPE;
  v_dia      integer := (p_marco ->> 'dia')::int;
  v_validade integer := LEAST(GREATEST(COALESCE((public._checkin_marco_cfg('checkin_marco_validade_dias', '30'::jsonb) #>> '{}')::int, 30), 1), 365);
  v_ultimo   integer;
BEGIN
  SELECT max((x ->> 'dia')::int) INTO v_ultimo FROM jsonb_array_elements(public._checkin_escada_degraus()) x;
  INSERT INTO public.checkin_escada (user_id) VALUES (p_uid) ON CONFLICT (user_id) DO NOTHING;
  SELECT * INTO v_row FROM public.checkin_escada WHERE user_id = p_uid FOR UPDATE;

  IF v_row.guardado_chave IS NOT NULL
     AND (v_row.garantido_ate IS NULL OR v_row.garantido_ate > now())
     AND v_row.guardado_dia > v_dia THEN
    RETURN NULL;
  END IF;

  IF v_dia >= COALESCE(v_ultimo, v_dia) AND NOT public._checkin_premio_bloqueado(p_uid) THEN
    RETURN public._checkin_escada_levantar(p_uid, p_marco, p_inicio, p_data, 'escada:ultimo');
  END IF;

  UPDATE public.checkin_escada
     SET guardado_chave = p_marco ->> 'chave', guardado_dia = v_dia,
         guardado_titulo = COALESCE(p_marco ->> 'titulo', 'Prémio do check-in'),
         guardado_tipo = p_marco ->> 'tipo', guardado_marco = p_marco,
         guardado_ciclo_inicio = p_inicio, guardado_em = now(),
         garantido_ate = now() + make_interval(days => v_validade),
         decisao = 'pendente', atualizado_em = now()
   WHERE user_id = p_uid;
  RETURN NULL;
END;
$function$;

-- O cliente carrega em "Levantar": dentro do intervalo diz quando pode.
CREATE OR REPLACE FUNCTION public.client_checkin_escada_levantar()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_uid  uuid := auth.uid();
  v_hoje date := (now() AT TIME ZONE 'Europe/Lisbon')::date;
  v_row  public.checkin_escada%ROWTYPE;
  v_ult  date;
  v_vale uuid;
  v_json jsonb;
  v_prox timestamptz;
BEGIN
  IF v_uid IS NULL THEN
    RETURN jsonb_build_object('ok', false, 'reason', 'sem_sessao');
  END IF;
  PERFORM pg_advisory_xact_lock(hashtext('checkin_escada:' || v_uid::text));
  SELECT * INTO v_row FROM public.checkin_escada WHERE user_id = v_uid FOR UPDATE;
  IF NOT FOUND OR v_row.guardado_chave IS NULL THEN
    RETURN jsonb_build_object('ok', false, 'reason', 'sem_premio');
  END IF;
  IF v_row.garantido_ate IS NOT NULL AND v_row.garantido_ate <= now() THEN
    RETURN jsonb_build_object('ok', false, 'reason', 'expirado');
  END IF;
  v_prox := public._checkin_premio_proximo_em(v_uid);
  IF v_prox IS NOT NULL AND v_prox > now() THEN
    RETURN jsonb_build_object('ok', false, 'reason', 'intervalo', 'proximo_premio_em', v_prox,
                              'estado', public._checkin_estado_marcos(v_uid));
  END IF;
  -- recomeça a seguir ao último check-in feito: se já o fez hoje, amanhã é o Dia 1;
  -- se ainda não, o check-in de hoje já conta como Dia 1
  SELECT max(c.checkin_date) INTO v_ult FROM public.daily_checkins c
   WHERE c.user_id = v_uid AND c.checkin_date <= v_hoje;
  v_vale := public._checkin_escada_levantar(v_uid, v_row.guardado_marco, v_row.guardado_ciclo_inicio,
                                            COALESCE(v_ult, v_hoje), 'escada:levantar');
  IF v_vale IS NULL THEN
    RETURN jsonb_build_object('ok', false, 'reason', 'ja_levantado', 'estado', public._checkin_estado_marcos(v_uid));
  END IF;
  SELECT public._checkin_vale_json(x) INTO v_json FROM public.checkin_premios_vales x WHERE x.id = v_vale;
  RETURN jsonb_build_object('ok', true, 'vale', v_json, 'estado', public._checkin_estado_marcos(v_uid));
END;
$function$;

-- O estado do calendário passa a dizer quando é o próximo prémio (escada.proximo_premio_em).
DO $patch$
DECLARE
  v_def text := pg_get_functiondef('public._checkin_estado_marcos(uuid)'::regprocedure);
  v_novo text;
BEGIN
  IF position('proximo_premio_em' in v_def) > 0 THEN
    RETURN;
  END IF;
  v_novo := replace(v_def, '''ultimo_vale_id'', v_er.ultimo_vale_id)',
                    '''ultimo_vale_id'', v_er.ultimo_vale_id,' || chr(10) ||
                    '      ''proximo_premio_em'', CASE WHEN p_uid IS NOT NULL THEN public._checkin_premio_proximo_em(p_uid) END,' || chr(10) ||
                    '      ''intervalo_dias'', LEAST(GREATEST(COALESCE((public._checkin_marco_cfg(''checkin_premio_intervalo_dias'', ''30''::jsonb) #>> ''{}'')::int, 30), 0), 365))');
  IF v_novo = v_def THEN
    RAISE EXCEPTION 'ancora_nao_encontrada em _checkin_estado_marcos';
  END IF;
  EXECUTE v_novo;
END
$patch$;
