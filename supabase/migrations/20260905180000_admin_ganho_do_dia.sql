-- ============================================================================
-- PAINEL ADMIN — O GANHO DE UM DIA, POR PESSOA, SOMANDO TODOS OS PAPEIS
-- 2026-09-05 (sessao fila-ganho-05-09)
--
-- O QUE FALTAVA
-- O painel ja sabia mostrar o acerto SEMANAL por pessoa (`admin_acerto_unifi-
-- cado`, que le a vista semanal). O que nao existia era o DIA: o Danilo nao
-- conseguia abrir o painel e ver quanto e que uma pessoa fez hoje somando
-- entregas, corridas, limpeza e lavagem. As tabelas de acerto so tem grao
-- semanal, por isso a semana nunca respondia a pergunta do dia.
--
-- O QUE ISTO FAZ, E O QUE NAO FAZ
-- Isto SOMA colunas que ja existem e mostra-as agrupadas por dia e por pessoa.
-- Nao ha aqui formula nova nenhuma: nenhum valor cobrado a cliente ou devido a
-- prestador e lido de outro sitio, alterado, arredondado de outra maneira ou
-- escrito. Sao duas coisas de leitura: uma vista e uma funcao de admin.
--
-- NOTA HONESTA QUE FICA REGISTADA (para o Danilo decidir depois)
-- A funcao que o proprio prestador usa no telemovel para ver o dia dele e
-- `meu_ganho_ao_vivo`, e essa e fixa ao utilizador autenticado — um admin nao
-- a pode usar para ver a vida de outra pessoa. Por isso o grao diario tem de
-- existir aqui tambem. Ficam portanto duas somas do mesmo dia, uma para quem
-- trabalha e outra para o painel; se um dia a regra de uma mudar, a outra tem
-- de mudar no mesmo movimento. O passo seguinte (fora do que foi pedido hoje)
-- e a do prestador passar a ler esta vista, ficando uma so.
-- ============================================================================

-- ── 1. A vista: uma linha por pessoa, por dia, por papel ───────────────────
CREATE OR REPLACE VIEW public.v_ganho_diario_por_pessoa AS
WITH linhas AS (
  -- ENTREGAS E FAVORES do estafeta. Mesma origem e mesmo filtro do extrato
  -- que ele ve no telemovel: o lancamento de ganho do proprio estafeta.
  SELECT (l.user_id)::uuid                                        AS user_id,
         (l.created_at AT TIME ZONE 'Europe/Lisbon')::date        AS dia,
         'driver'::text                                           AS papel,
         round(l.amount * 100)::bigint                            AS cents,
         1                                                        AS trabalhos
  FROM public.ledger_entries l
  WHERE l.user_type = 'driver'
    AND l.type = 'earning'
    AND l.user_id IS NOT NULL
    AND l.user_id ~ '^[0-9a-fA-F-]{36}$'

  UNION ALL

  -- CORRIDAS TVDE. O `driver_id` tanto pode ser o utilizador como a linha do
  -- estafeta — a mesma tolerancia que o extrato ja faz.
  SELECT COALESCE(d.user_id, r.driver_id)                         AS user_id,
         (r.updated_at AT TIME ZONE 'Europe/Lisbon')::date        AS dia,
         'driver'::text,
         COALESCE(r.driver_earn_cents, 0)::bigint,
         1
  FROM public.tvde_rides r
  LEFT JOIN public.drivers d ON d.id = r.driver_id
  WHERE r.status = 'finalizada'
    AND r.driver_id IS NOT NULL

  UNION ALL

  -- LIMPEZA
  SELECT c.user_id,
         (b.completed_at AT TIME ZONE 'Europe/Lisbon')::date,
         'cleaner'::text,
         COALESCE(b.cleaner_earnings_cents, 0)::bigint,
         1
  FROM public.cleaning_bookings b
  JOIN public.cleaners c ON c.id = b.cleaner_id
  WHERE b.status = 'completed'
    AND b.completed_at IS NOT NULL
    AND COALESCE(b.is_test_order, false) = false

  UNION ALL

  -- LAVAGEM DE CARROS
  SELECT w.user_id,
         (b.completed_at AT TIME ZONE 'Europe/Lisbon')::date,
         'washer'::text,
         COALESCE(b.washer_earnings_cents, 0)::bigint,
         1
  FROM public.carwash_bookings b
  JOIN public.washers w ON w.id = b.washer_id
  WHERE b.status = 'completed'
    AND b.completed_at IS NOT NULL
)
SELECT user_id,
       dia,
       papel,
       sum(cents)::bigint    AS cents,
       sum(trabalhos)::int   AS trabalhos
FROM linhas
WHERE user_id IS NOT NULL
GROUP BY user_id, dia, papel;

REVOKE ALL ON public.v_ganho_diario_por_pessoa FROM PUBLIC, anon, authenticated;


-- ── 2. A funcao que o painel chama ─────────────────────────────────────────
-- Devolve o dia pedido (por defeito hoje, hora de Lisboa), a lista de pessoas
-- que trabalharam nesse dia com o detalhe por papel, e o total do dia.
CREATE OR REPLACE FUNCTION public.admin_ganho_do_dia(p_dia date DEFAULT NULL)
RETURNS jsonb
LANGUAGE plpgsql
STABLE SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE v_dia date; v_out jsonb;
BEGIN
  IF NOT public.is_admin() THEN RAISE EXCEPTION 'admin_required'; END IF;

  v_dia := COALESCE(p_dia, (now() AT TIME ZONE 'Europe/Lisbon')::date);

  WITH pessoa AS (
    SELECT v.user_id,
           sum(v.cents)::bigint  AS total_cents,
           sum(v.trabalhos)::int AS trabalhos_total,
           jsonb_agg(jsonb_build_object(
             'papel', v.papel,
             'titulo', CASE v.papel
                         WHEN 'driver'  THEN 'Entregas e corridas'
                         WHEN 'cleaner' THEN 'Limpeza'
                         WHEN 'washer'  THEN 'Lavagem de carros'
                         ELSE v.papel END,
             'cents', v.cents,
             'trabalhos', v.trabalhos) ORDER BY v.cents DESC) AS por_papel
    FROM public.v_ganho_diario_por_pessoa v
    WHERE v.dia = v_dia
    GROUP BY v.user_id
  )
  SELECT jsonb_build_object(
    'ok', true,
    'dia', v_dia,
    'total_cents', COALESCE((SELECT sum(total_cents) FROM pessoa), 0),
    'pessoas', COALESCE((SELECT count(*) FROM pessoa), 0),
    'itens', COALESCE((
      SELECT jsonb_agg(jsonb_build_object(
        'user_id', p.user_id,
        -- O nome que o Danilo le, nunca o uuid. Vem do papel mais completo
        -- que a pessoa tenha, igual ao que o acerto semanal ja faz.
        'nome', COALESCE(
          (SELECT d.name FROM drivers  d WHERE d.user_id = p.user_id LIMIT 1),
          (SELECT c.name FROM cleaners c WHERE c.user_id = p.user_id LIMIT 1),
          (SELECT w.name FROM washers  w WHERE w.user_id = p.user_id LIMIT 1),
          (SELECT u.email FROM auth.users u WHERE u.id = p.user_id),
          '(sem nome)'),
        'email', COALESCE((SELECT u.email FROM auth.users u WHERE u.id = p.user_id), ''),
        'telefone', COALESCE(
          (SELECT d.phone FROM drivers  d WHERE d.user_id = p.user_id LIMIT 1),
          (SELECT c.phone FROM cleaners c WHERE c.user_id = p.user_id LIMIT 1),
          (SELECT w.phone FROM washers  w WHERE w.user_id = p.user_id LIMIT 1), ''),
        'total_cents', p.total_cents,
        'trabalhos_total', p.trabalhos_total,
        'por_papel', p.por_papel)
        ORDER BY p.total_cents DESC)
      FROM pessoa p), '[]'::jsonb)
  ) INTO v_out;

  RETURN v_out;
END $function$;

REVOKE ALL ON FUNCTION public.admin_ganho_do_dia(date) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.admin_ganho_do_dia(date) TO authenticated;
