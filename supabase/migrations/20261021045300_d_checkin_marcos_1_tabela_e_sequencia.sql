-- Bloco D · fechar-pendencias-2026-10-20 — marcos do check-in (Bora Todo Dia).
-- Parte 1/4 (tabela, definicoes e sequencia). Base: tabela dos vales, sequencia continua, emissao no check-in, leitura do cliente,
-- manutencao horaria e funcoes do painel. Nao mexe nos tokens do check-in (Dia1..Dia7
-- continuam como estao) nem em nenhuma funcao de cobranca.
-- Marcos por sequencia continua: 7 (os tokens do Dia 7, so se mostra), 10, 15 e 30.
-- Falhou um dia -> volta a 1. Depois do dia 30 o ciclo recomeca no 1.

-- 1) Tabela dos vales ---------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.checkin_premios_vales (
  id             uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id        uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  marco          smallint NOT NULL CHECK (marco BETWEEN 1 AND 365),
  marco_chave    text NOT NULL,
  tipo           text NOT NULL CHECK (tipo IN ('produto','servico')),
  ciclo_inicio   date,
  estado         text NOT NULL DEFAULT 'por_usar'
                 CHECK (estado IN ('por_usar','reservado','usado','expirado','anulado','guardado','a_espera_pedido')),
  titulo         text NOT NULL,
  loja_id        text,
  produto_id     text,
  quantidade     integer NOT NULL DEFAULT 1 CHECK (quantidade > 0),
  opcoes         text[] NOT NULL DEFAULT '{}'::text[],
  opcao          text,
  valor_cents    integer NOT NULL DEFAULT 0 CHECK (valor_cents >= 0),
  custo_cents    integer NOT NULL DEFAULT 0 CHECK (custo_cents >= 0),
  emitido_em     timestamptz NOT NULL DEFAULT now(),
  ativado_em     timestamptz,
  valido_ate     timestamptz,
  ativar_em      date,
  esperar_ate    timestamptz,
  reservado_ate  timestamptz,
  usado_em       timestamptz,
  pedido_id      text,
  marcacao_tipo  text CHECK (marcacao_tipo IS NULL OR marcacao_tipo IN ('limpeza','lavagem')),
  marcacao_id    uuid,
  pago_loja_em   timestamptz,
  pago_loja_por  uuid,
  pago_loja_nota text,
  anulado_em     timestamptz,
  anulado_por    uuid,
  motivo         text,
  origem         text NOT NULL DEFAULT 'checkin' CHECK (origem IN ('checkin','admin')),
  criado_por     uuid,
  visto_em       timestamptz,
  atualizado_em  timestamptz NOT NULL DEFAULT now()
);

COMMENT ON TABLE public.checkin_premios_vales IS
  'Vales dos marcos do check-in (10/15/30 dias seguidos). Um por marco por ciclo. Escrita so por funcoes do servidor.';
COMMENT ON COLUMN public.checkin_premios_vales.valor_cents IS 'Quanto o cliente pagaria pelo produto/servico do vale.';
COMMENT ON COLUMN public.checkin_premios_vales.custo_cents IS 'Quanto a Bora paga a loja (preco de balcao, venda normal) ou ao prestador (ganho normal).';

CREATE UNIQUE INDEX IF NOT EXISTS checkin_premios_vales_um_por_ciclo
  ON public.checkin_premios_vales (user_id, marco_chave, ciclo_inicio) WHERE origem = 'checkin';
CREATE INDEX IF NOT EXISTS checkin_premios_vales_user_estado ON public.checkin_premios_vales (user_id, estado);
CREATE INDEX IF NOT EXISTS checkin_premios_vales_estado ON public.checkin_premios_vales (estado, valido_ate);
CREATE INDEX IF NOT EXISTS checkin_premios_vales_pedido ON public.checkin_premios_vales (pedido_id) WHERE pedido_id IS NOT NULL;
CREATE INDEX IF NOT EXISTS checkin_premios_vales_marcacao ON public.checkin_premios_vales (marcacao_id) WHERE marcacao_id IS NOT NULL;

ALTER TABLE public.checkin_premios_vales ENABLE ROW LEVEL SECURITY;

CREATE POLICY checkin_premios_vales_ler_proprio ON public.checkin_premios_vales
  FOR SELECT TO authenticated
  USING (user_id = auth.uid() OR public.is_admin());

REVOKE ALL ON TABLE public.checkin_premios_vales FROM PUBLIC, anon, authenticated;
GRANT SELECT ON TABLE public.checkin_premios_vales TO authenticated;

-- 2) Definicoes (prefixo checkin_marco_) ------------------------------------------
CREATE OR REPLACE FUNCTION public._checkin_marco_cfg(p_key text, p_defeito jsonb)
RETURNS jsonb
LANGUAGE sql
STABLE SECURITY DEFINER
SET search_path TO 'public'
AS $function$
  SELECT COALESCE((SELECT s.value FROM public.platform_settings s WHERE s.key = p_key), p_defeito)
$function$;

-- Lista dos marcos, ordenada pelo dia. Cada definicao checkin_marco_<chave> e um objeto
-- {"chave","ativo","dia","tipo"(tokens|produto|servico),"titulo","descricao",...}.
-- Sem definicoes gravadas, valem os valores do Danilo de 20/10/2026.
CREATE OR REPLACE FUNCTION public._checkin_marcos_config()
RETURNS jsonb
LANGUAGE plpgsql
STABLE SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v jsonb;
BEGIN
  SELECT jsonb_agg(x.value || jsonb_build_object('chave', COALESCE(x.value ->> 'chave', substr(x.key, 15)))
                   ORDER BY (x.value ->> 'dia')::int)
    INTO v
    FROM public.platform_settings x
   WHERE x.key LIKE 'checkin\_marco\_%'
     AND jsonb_typeof(x.value) = 'object'
     AND x.value ? 'dia' AND x.value ? 'tipo'
     AND (x.value ->> 'dia') ~ '^[0-9]{1,3}$'
     AND (x.value ->> 'tipo') IN ('tokens','produto','servico');
  IF v IS NOT NULL THEN
    RETURN v;
  END IF;
  RETURN jsonb_build_array(
    jsonb_build_object('chave','semana','ativo',true,'dia',7,'tipo','tokens',
      'titulo','os tokens do Dia 7','descricao','Ao 7.º dia seguido ganhas os tokens do Dia 7.'),
    jsonb_build_object('chave','salgados','ativo',true,'dia',10,'tipo','produto',
      'titulo','2 salgados da Keli','descricao','Na Sabores do Brasil: 2 salgados grandes, coxinha ou esfirra à escolha. Pagas só a entrega e as taxas.',
      'loja_id','sabores-brasil-guarda','produto_id','premio-checkin-salgados','quantidade',1,
      'valor_cents',630,'custo_cents',540),
    jsonb_build_object('chave','acai','ativo',true,'dia',15,'tipo','produto',
      'titulo','um açaí do Goola','descricao','No Goola Açaí: um Goola Bowl com 3 acompanhamentos à escolha. Pagas só a entrega e as taxas.',
      'loja_id','goola-acai-guarda','produto_id','premio-checkin-acai','quantidade',1,
      'valor_cents',922,'custo_cents',790),
    jsonb_build_object('chave','mes','ativo',true,'dia',30,'tipo','servico',
      'titulo','2 horas de limpeza ou uma lavagem exterior do carro',
      'descricao','Escolhes: 2 horas de limpeza em casa ou uma lavagem do carro só por fora.',
      'opcoes',jsonb_build_array('limpeza','lavagem'),'limpeza_horas',2)
  );
END;
$function$;

-- 3) Sequencia continua -------------------------------------------------------------
-- Dias seguidos de check-in que acabam no ultimo check-in ate p_ate (inclusive).
CREATE OR REPLACE FUNCTION public._checkin_sequencia(p_uid uuid, p_ate date)
RETURNS TABLE (dias integer, inicio date, ultima date)
LANGUAGE sql
STABLE SECURITY DEFINER
SET search_path TO 'public'
AS $function$
  WITH d AS (
    SELECT c.checkin_date
      FROM public.daily_checkins c
     WHERE c.user_id = p_uid AND c.checkin_date <= p_ate
     ORDER BY c.checkin_date DESC
     LIMIT 800
  ), g AS (
    SELECT d.checkin_date,
           d.checkin_date + (row_number() OVER (ORDER BY d.checkin_date DESC))::int AS grupo
      FROM d
  ), primeiro AS (
    SELECT g.grupo FROM g ORDER BY g.checkin_date DESC LIMIT 1
  )
  SELECT count(*)::int, min(g.checkin_date), max(g.checkin_date)
    FROM g
   WHERE g.grupo = (SELECT p.grupo FROM primeiro p)
$function$;

-- Estado dos marcos de uma pessoa, hoje (Lisboa).
CREATE OR REPLACE FUNCTION public._checkin_estado_marcos(p_uid uuid)
RETURNS jsonb
LANGUAGE plpgsql
STABLE SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_hoje     date := (now() AT TIME ZONE 'Europe/Lisbon')::date;
  v_ciclo    integer := LEAST(GREATEST(COALESCE((public._checkin_marco_cfg('checkin_marco_ciclo_dias', '30'::jsonb) #>> '{}')::int, 30), 1), 365);
  v_ativo    boolean := COALESCE((public._checkin_marco_cfg('checkin_marco_ativo', 'false'::jsonb) #>> '{}')::boolean, false);
  v_cfg      jsonb := public._checkin_marcos_config();
  v_premios  integer[] := public._checkin_premios();
  v_seq      record;
  v_dias     integer := 0;
  v_dia      integer := 0;
  v_feito    boolean := false;
  v_marcos   jsonb := '[]'::jsonb;
  v_prox     jsonb := NULL;
  v_primeiro jsonb := NULL;
  m          jsonb;
  v_falta    integer;
BEGIN
  IF p_uid IS NOT NULL THEN
    SELECT * INTO v_seq FROM public._checkin_sequencia(p_uid, v_hoje);
    IF v_seq.ultima IS NOT NULL AND v_seq.ultima >= v_hoje - 1 THEN
      v_dias  := COALESCE(v_seq.dias, 0);
      v_feito := v_seq.ultima = v_hoje;
    END IF;
  END IF;
  IF v_dias > 0 THEN
    v_dia := ((v_dias - 1) % v_ciclo) + 1;
  END IF;

  FOR m IN SELECT x FROM jsonb_array_elements(COALESCE(v_cfg, '[]'::jsonb)) x LOOP
    CONTINUE WHEN NOT COALESCE((m ->> 'ativo')::boolean, true);
    CONTINUE WHEN (m ->> 'dia')::int > v_ciclo;
    v_falta := GREATEST((m ->> 'dia')::int - v_dia, 0);
    v_marcos := v_marcos || jsonb_build_array(jsonb_build_object(
      'chave', m ->> 'chave', 'dia', (m ->> 'dia')::int, 'tipo', m ->> 'tipo',
      'titulo', m ->> 'titulo', 'descricao', m ->> 'descricao',
      'tokens', CASE WHEN m ->> 'tipo' = 'tokens' THEN v_premios[7] END,
      'atingido', v_dia >= (m ->> 'dia')::int,
      'faltam', v_falta));
    IF v_primeiro IS NULL THEN
      v_primeiro := m;
    END IF;
    IF v_prox IS NULL AND (m ->> 'dia')::int > v_dia THEN
      v_prox := jsonb_build_object('chave', m ->> 'chave', 'dia', (m ->> 'dia')::int,
                                   'titulo', m ->> 'titulo', 'faltam', v_falta);
    END IF;
  END LOOP;
  IF v_prox IS NULL AND v_primeiro IS NOT NULL THEN
    -- passou o ultimo marco do ciclo: o proximo e o primeiro do ciclo seguinte
    v_prox := jsonb_build_object('chave', v_primeiro ->> 'chave', 'dia', (v_primeiro ->> 'dia')::int,
                                 'titulo', v_primeiro ->> 'titulo',
                                 'faltam', (v_ciclo - v_dia) + (v_primeiro ->> 'dia')::int);
  END IF;

  RETURN jsonb_build_object(
    'marcos_ativos', v_ativo,
    'ciclo_dias', v_ciclo,
    'dias_seguidos', v_dias,
    'dia_marco', v_dia,
    'hoje_feito', v_feito,
    'marcos', v_marcos,
    'proximo', v_prox
  );
END;
$function$;

-- Permissoes: fechado a quem nao tem sessao
REVOKE ALL ON FUNCTION public._checkin_marco_cfg(text, jsonb) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public._checkin_marcos_config() FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public._checkin_sequencia(uuid, date) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public._checkin_estado_marcos(uuid) FROM PUBLIC, anon, authenticated;
