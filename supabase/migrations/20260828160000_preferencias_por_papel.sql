-- ============================================================================
-- O QUE EU QUERO RECEBER HOJE — um interruptor por papel
--
-- A caixa "O que queres aceitar?" no ecrã do motorista era um rádio de duas
-- opções fixas: só corridas, ou corridas mais entregas. Quem acumula quatro
-- papéis via duas linhas e não tinha onde ligar a limpeza nem a lavagem.
--
-- Aqui fica a preferência do próprio, que é coisa diferente de duas que já
-- existem e que não se devem confundir:
--   * `cleaners.is_active` / `washers.is_active` — bandeira do ADMIN, diz se a
--     pessoa está aprovada e activa na plataforma. Não é dela para mexer.
--   * `drivers.is_online` — está a trabalhar agora ou não, para todos os
--     papéis de condução ao mesmo tempo.
-- Esta tabela responde a outra pergunta: estando online, o que e' que quero
-- que me chegue hoje. Falta de linha significa SIM — quem nunca mexeu recebe
-- tudo o que os seus papéis permitem, que é o comportamento de sempre.
-- ============================================================================

CREATE TABLE IF NOT EXISTS public.preferencias_papel (
  user_id    uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  papel      text NOT NULL CHECK (papel IN ('driver', 'cleaner', 'washer')),
  aceita     boolean NOT NULL DEFAULT true,
  updated_at timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (user_id, papel)
);

ALTER TABLE public.preferencias_papel ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS preferencias_proprias ON public.preferencias_papel;
CREATE POLICY preferencias_proprias ON public.preferencias_papel
  FOR ALL USING (auth.uid() = user_id) WITH CHECK (auth.uid() = user_id);

DROP POLICY IF EXISTS service_role_todas_preferencias ON public.preferencias_papel;
CREATE POLICY service_role_todas_preferencias ON public.preferencias_papel
  FOR ALL USING (auth.role() = 'service_role');

COMMENT ON TABLE public.preferencias_papel IS
  'O que a pessoa quer receber hoje, por papel. Sem linha = sim. Nao confundir '
  'com is_active (bandeira do admin) nem com is_online (esta a trabalhar).';


-- ── Ler: os papéis da pessoa, cada um com o seu interruptor ────────────────
-- Uma leitura só serve a caixa inteira do ecrã. Devolve SEMPRE todos os papéis
-- de trabalho que a pessoa tem, mesmo os que nunca foram mexidos — senão a
-- caixa aparecia com menos linhas do que a pessoa tem papéis.
CREATE OR REPLACE FUNCTION public.meus_papeis_e_preferencias()
RETURNS TABLE (papel text, aceita boolean)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $function$
  SELECT ur.role AS papel,
         COALESCE(p.aceita, true) AS aceita
  FROM public.user_roles ur
  LEFT JOIN public.preferencias_papel p
         ON p.user_id = ur.user_id AND p.papel = ur.role
  WHERE ur.user_id = auth.uid()
    AND ur.role IN ('driver', 'cleaner', 'washer')
  ORDER BY ur.role;
$function$;

REVOKE ALL ON FUNCTION public.meus_papeis_e_preferencias() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.meus_papeis_e_preferencias() TO authenticated;


-- ── Escrever: ligar ou desligar um papel ───────────────────────────────────
-- Só deixa mexer em papel que a pessoa TEM. Sem isto, alguém podia gravar
-- preferências de papéis que nunca lhe foram atribuídos e a caixa passava a
-- mostrar linhas a mais.
CREATE OR REPLACE FUNCTION public.definir_preferencia_papel(
  p_papel  text,
  p_aceita boolean
)
RETURNS boolean
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_user_id uuid := auth.uid();
BEGIN
  IF v_user_id IS NULL THEN
    RAISE EXCEPTION 'UNAUTHENTICATED';
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM public.user_roles
    WHERE user_id = v_user_id AND role = p_papel
  ) THEN
    RAISE EXCEPTION 'PAPEL_NAO_ATRIBUIDO: %', p_papel;
  END IF;

  INSERT INTO public.preferencias_papel (user_id, papel, aceita)
  VALUES (v_user_id, p_papel, p_aceita)
  ON CONFLICT (user_id, papel) DO UPDATE
    SET aceita = EXCLUDED.aceita, updated_at = now();

  RETURN p_aceita;
END;
$function$;

REVOKE ALL ON FUNCTION public.definir_preferencia_papel(text, boolean) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.definir_preferencia_papel(text, boolean) TO authenticated;


-- ── Para quem envia: esta pessoa quer receber deste papel? ─────────────────
-- Usada pelas Edge Functions notify-cleaner e notify-washer. Sem linha = sim.
CREATE OR REPLACE FUNCTION public.aceita_papel(p_user_id uuid, p_papel text)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $function$
  SELECT COALESCE(
    (SELECT p.aceita FROM public.preferencias_papel p
      WHERE p.user_id = p_user_id AND p.papel = p_papel),
    true
  );
$function$;

REVOKE ALL ON FUNCTION public.aceita_papel(uuid, text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.aceita_papel(uuid, text) TO service_role;

COMMENT ON FUNCTION public.aceita_papel(uuid, text) IS
  'Esta pessoa quer receber pedidos deste papel? Sem preferencia gravada = sim.';
