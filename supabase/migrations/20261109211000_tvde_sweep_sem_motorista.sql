-- 20261109211000_tvde_sweep_sem_motorista.sql
--
-- ZONA DE DESPACHO (TVDE). Missão pendencias-2026-11-09, bloco H.
--
-- O defeito (erro fora do scope n.º 4 da M10, e2e_log 7333/7345 "P4"):
-- com a chamada de reforço TVDE ligada (platform_settings.tvde_forcado_ligado = true), o
-- gatilho BEFORE UPDATE _aa_tvde_chamada_de_reforco apanha o "solicitada -> sem_motorista" e
-- devolve a corrida a 'solicitada' com uma oferta de reforço. Mas quem fez o UPDATE grava
-- logo a seguir o evento 'sem_motorista' em tvde_ride_events, e a corrida CONTINUA:
--   (a) tvde_dispatch_sweep, ramo "procura esgotada" (6 min): grava com IF FOUND, e o
--       UPDATE conta como feito mesmo quando o gatilho o desviou;
--   (b) tvde_offer_to_next, ramo "sem candidatos há mais de 120 s" (chamada pelo próprio
--       tvde_dispatch_sweep): grava sem verificar nada. É o caminho mais comum à noite.
--
-- A correção (mudança mínima, só o registo): o evento 'sem_motorista' só se grava se a
-- corrida ficou mesmo em 'sem_motorista'. Nenhum UPDATE muda, nenhuma oferta muda: quem
-- recebe a corrida é o mesmo antes e depois. Com o reforço desligado (como está hoje) o
-- comportamento é igual ao de hoje, linha a linha.
--
-- Como (patch por âncora, como em 20260930122000): lê-se a definição que está no ar,
-- confere-se o md5 do corpo (prosrc) contra o lido em produção a 09/11/2026, troca-se só a
-- âncora e recria-se. Corpo já corrigido -> não faz nada (idempotente). md5 diferente ->
-- ABORTA (alguém mudou a função entretanto: refazer a proposta, não aplicar às cegas).
-- Depois de recriar, prova-se que o corpo novo, com a troca desfeita, é o de antes (md5).
--
-- Prova: PGlite com as definições de produção (md5 iguais) e pg_net falso,
-- .claude/.ai/missoes/pendencias-2026-11-09/H-tvde-sweep/ (prova_sweep.mjs + saida).

SET LOCAL lock_timeout = '5s';

DO $mig_h$
DECLARE
  v_marca  constant text := '2026-11-09 (H)';
  v_nota   constant text := replace(
$n$      -- 2026-11-09 (H): com a chamada de reforço TVDE ligada, o gatilho _aa_tvde_chamada_de_reforco
      -- pode devolver a corrida a 'solicitada' com uma oferta de reforço: a corrida continua e não
      -- se regista 'sem_motorista'. Só muda este registo; quem recebe a corrida fica igual.
$n$, E'\r', '');
  -- (a) tvde_dispatch_sweep
  v_sw_md5 constant text := '737fc041f940142d92877a7eea4e45e8';
  v_sw_anc constant text := replace(
$a$      IF FOUND THEN
        INSERT INTO public.tvde_ride_events(ride_id, status, actor, meta)
          VALUES (r.id, 'sem_motorista', 'system',$a$, E'\r', '');
  v_sw_nov constant text := v_nota || replace(
$a$      IF FOUND AND EXISTS (SELECT 1 FROM public.tvde_rides x
                            WHERE x.id = r.id AND x.status = 'sem_motorista') THEN
        INSERT INTO public.tvde_ride_events(ride_id, status, actor, meta)
          VALUES (r.id, 'sem_motorista', 'system',$a$, E'\r', '');
  -- (b) tvde_offer_to_next
  v_on_md5 constant text := '2c6fb898cf7bc5141351ec45b81cf655';
  v_on_anc constant text := replace(
$b$      INSERT INTO public.tvde_ride_events(ride_id,status,actor)
        VALUES (p_ride_id,'sem_motorista','system');
      RETURN false;$b$, E'\r', '');
  v_on_nov constant text := v_nota || replace(
$b$      IF EXISTS (SELECT 1 FROM public.tvde_rides x
                  WHERE x.id = p_ride_id AND x.status = 'sem_motorista') THEN
        INSERT INTO public.tvde_ride_events(ride_id,status,actor)
          VALUES (p_ride_id,'sem_motorista','system');
      END IF;
      RETURN false;$b$, E'\r', '');

  v_fn   regprocedure;
  v_md5  text;
  v_anc  text;
  v_nov  text;
  v_src  text;
  v_def  text;
  v_n    int;
BEGIN
  FOR i IN 1..2 LOOP
    IF i = 1 THEN
      v_fn := 'public.tvde_dispatch_sweep()'::regprocedure;
      v_md5 := v_sw_md5; v_anc := v_sw_anc; v_nov := v_sw_nov;
    ELSE
      v_fn := 'public.tvde_offer_to_next(uuid)'::regprocedure;
      v_md5 := v_on_md5; v_anc := v_on_anc; v_nov := v_on_nov;
    END IF;

    SELECT p.prosrc INTO v_src FROM pg_proc p WHERE p.oid = v_fn;

    IF position(v_marca IN v_src) > 0 THEN
      RAISE NOTICE '[H] % já tem a correção (%): nada a fazer', v_fn, v_marca;
      CONTINUE;
    END IF;

    IF md5(v_src) <> v_md5 THEN
      RAISE EXCEPTION '[H] % mudou desde 09/11 (md5 do corpo % <> %): não aplico às cegas',
        v_fn, md5(v_src), v_md5;
    END IF;

    v_n := (length(v_src) - length(replace(v_src, v_anc, ''))) / length(v_anc);
    IF v_n <> 1 THEN
      RAISE EXCEPTION '[H] % : âncora encontrada % vezes (esperado 1)', v_fn, v_n;
    END IF;

    v_def := pg_get_functiondef(v_fn);
    IF (length(v_def) - length(replace(v_def, v_anc, ''))) / length(v_anc) <> 1 THEN
      RAISE EXCEPTION '[H] % : âncora fora do sítio na definição completa', v_fn;
    END IF;
    EXECUTE replace(v_def, v_anc, v_nov);

    -- Prova: o corpo novo, com a troca desfeita, é byte a byte o de antes.
    SELECT p.prosrc INTO v_src FROM pg_proc p WHERE p.oid = v_fn;
    IF md5(replace(v_src, v_nov, v_anc)) <> v_md5 OR position(v_marca IN v_src) = 0 THEN
      RAISE EXCEPTION '[H] % : o corpo novo não é o antigo + a troca', v_fn;
    END IF;
    RAISE NOTICE '[H] % corrigida: md5 do corpo % -> %', v_fn, v_md5, md5(v_src);
  END LOOP;
END
$mig_h$;

-- Desfazer (se for preciso): o mesmo DO com as trocas ao contrário, ou seja
--   replace(pg_get_functiondef(f), <v_*_nov>, <v_*_anc>) e EXECUTE, conferindo no fim
--   md5(prosrc) = 737fc041f940142d92877a7eea4e45e8 (tvde_dispatch_sweep) e
--   2c6fb898cf7bc5141351ec45b81cf655 (tvde_offer_to_next).
