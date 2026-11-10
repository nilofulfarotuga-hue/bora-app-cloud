-- Missão fechar-tudo-2026-11-10, Bloco G (check-in a fundo) — parte 1 de 6.
-- Definições novas (cada regra com o seu interruptor e uma linha de explicação),
-- tabelas do perdão (R5) e das preferências do lembrete (R8), e leitores de definições.
-- Ordem de aplicação: 200000 → 200100 → 200200 → 200300 → 200400 → 200500.
-- Prova local em PGlite: docs/propostas/fechar-tudo-2026-11-10/G_prova_pglite.mjs.

-- 1) Definições (só se ainda não existirem: nunca por cima do que o Danilo já mudou)
INSERT INTO public.platform_settings (key, value, description, category, updated_at) VALUES
  ('checkin_pedido_conta_tvde', 'false'::jsonb,
   'R2: uma corrida TVDE conta como "pedido pago" para desbloquear prémios. Desligado enquanto o Bora Motorista estiver fechado.',
   'marketing', now()),
  ('checkin_quero_este_recomeca_semana', 'false'::jsonb,
   'R3: ao carregar "Quero este", além da escada dos prémios, também a semana de tokens (5,5,10,10,15,15,40) volta ao Dia 1. Desligado: a semana segue o seu ciclo.',
   'marketing', now()),
  ('checkin_sugestao_ativa', 'true'::jsonb,
   'R4: o prémio guardado é sempre o mais valioso a que a pessoa já chegou; entre iguais, o da loja onde ela mais pediu.',
   'marketing', now()),
  ('checkin_perdao_ativo', 'true'::jsonb,
   'R5: perdoa sozinho 1 dia falhado por mês (gelo no calendário), só a quem tem 1 pedido pago nos últimos 30 dias.',
   'marketing', now()),
  ('checkin_perdao_por_mes', '1'::jsonb,
   'R5: quantos dias falhados se perdoam por mês a cada pessoa.',
   'marketing', now()),
  ('checkin_premios_tecto_custo_ativo', 'true'::jsonb,
   'R6: teto de custo mensal dos prémios. Passando o teto, o prémio fica guardado para o mês seguinte.',
   'marketing', now()),
  ('checkin_premios_tecto_custo_cents', '10000'::jsonb,
   'R6: teto do custo dos prémios por mês, em cêntimos (o que a Bora paga às lojas). Valor de partida 100 € — POR CONFIRMAR pelo Danilo.',
   'marketing', now()),
  ('checkin_premios_tecto_aviso_pct', '80'::jsonb,
   'R6: aviso no painel quando o custo do mês chega a esta percentagem do teto.',
   'marketing', now()),
  ('checkin_lembrete_hora_habitual', 'true'::jsonb,
   'R8: um lembrete por dia, à hora a que a pessoa costuma fazer o check-in. Desligado: voltam os lembretes das 11h e 20h só a quem fez ontem.',
   'marketing', now()),
  ('checkin_lembrete_max_falhas', '3'::jsonb,
   'R8: o lembrete pára depois de a pessoa falhar este número de dias seguidos (1 = a regra de 18/10: só a quem fez ontem).',
   'marketing', now())
ON CONFLICT (key) DO NOTHING;

-- Texto da escada com a regra nova (R3), só se ainda for o texto de 29/10.
UPDATE public.platform_settings
   SET value = to_jsonb('Em cada sequência levas UM prémio: o mais valioso a que chegares. «Quero este» leva o prémio e a escada dos prémios volta ao dia 1 (os tokens de cada dia continuam). «Continuar» troca por um prémio maior.'::text),
       updated_at = now()
 WHERE key = 'checkin_escada_texto'
   AND value = to_jsonb('Em cada sequência levas UM prémio: o mais alto a que chegares. Se levantares, a sequência volta ao dia 1. Se continuares, trocas por um prémio maior.'::text);

-- 2) Leitores de definições que nunca rebentam com um valor mal escrito no painel
CREATE OR REPLACE FUNCTION public._checkin_cfg_bool(p_key text, p_defeito boolean)
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  SELECT CASE lower(COALESCE(public._checkin_marco_cfg(p_key, 'null'::jsonb) #>> '{}', ''))
           WHEN 'true' THEN true
           WHEN 'false' THEN false
           ELSE p_defeito
         END
$function$;

CREATE OR REPLACE FUNCTION public._checkin_cfg_int(p_key text, p_defeito integer)
 RETURNS integer
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  SELECT CASE WHEN (x #>> '{}') ~ '^-?[0-9]{1,9}$' THEN (x #>> '{}')::integer ELSE p_defeito END
    FROM (SELECT public._checkin_marco_cfg(p_key, 'null'::jsonb) AS x) s
$function$;

-- 3) R5: dias falhados que ficaram perdoados (um por linha)
CREATE TABLE IF NOT EXISTS public.checkin_perdoes (
  id          bigserial PRIMARY KEY,
  user_id     uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  dia         date NOT NULL,          -- o dia falhado que ficou perdoado
  mes         date NOT NULL,          -- 1.º dia do mês desse dia (conta o limite por mês)
  aplicado_em timestamptz NOT NULL DEFAULT now(),
  visto_em    timestamptz,            -- a app já mostrou "Usámos o teu perdão deste mês"
  CONSTRAINT checkin_perdoes_um_por_dia UNIQUE (user_id, dia)
);
CREATE INDEX IF NOT EXISTS checkin_perdoes_user_mes ON public.checkin_perdoes (user_id, mes);
ALTER TABLE public.checkin_perdoes ENABLE ROW LEVEL SECURITY;
-- Sem políticas: só as funções do servidor leem e escrevem.
REVOKE ALL ON public.checkin_perdoes FROM PUBLIC, anon, authenticated;
REVOKE ALL ON SEQUENCE public.checkin_perdoes_id_seq FROM PUBLIC, anon, authenticated;

-- 4) R8: preferência do lembrete por pessoa (botão "desligar o lembrete" na app)
CREATE TABLE IF NOT EXISTS public.checkin_lembrete_prefs (
  user_id       uuid PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
  desligado     boolean NOT NULL DEFAULT false,
  atualizado_em timestamptz NOT NULL DEFAULT now()
);
ALTER TABLE public.checkin_lembrete_prefs ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.checkin_lembrete_prefs FROM PUBLIC, anon, authenticated;

-- 5) R8: o lembrete único do dia regista-se com o turno 'habitual'
ALTER TABLE public.checkin_lembretes_envios DROP CONSTRAINT IF EXISTS checkin_lembretes_envios_turno_check;
ALTER TABLE public.checkin_lembretes_envios
  ADD CONSTRAINT checkin_lembretes_envios_turno_check CHECK (turno = ANY (ARRAY['manha'::text, 'noite'::text, 'habitual'::text]));

REVOKE ALL ON FUNCTION public._checkin_cfg_bool(text, boolean) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public._checkin_cfg_int(text, integer) FROM PUBLIC, anon, authenticated;
