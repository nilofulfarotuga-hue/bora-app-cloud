-- ============================================================================
-- ENTREGAS PASSA A SER TRABALHO PRÓPRIO
--
-- ── A decisão, e porquê ────────────────────────────────────────────────────
-- Entregas estava colada ao papel de motorista: a caixa só oferecia "só
-- passageiros" ou "passageiros mais entregas", nunca "só entregas". Duas
-- coisas estavam mal com isso.
--
-- A primeira é de escolha: quem quer ligar e desligar as entregas por si, como
-- liga a limpeza, não podia.
--
-- A segunda é maior e é a que decide: **um estafeta de bicicleta ou mota não é
-- um motorista de TVDE**. O TVDE em Portugal exige certificado do IMT
-- (DL 45/2018); levar comida não exige nada disso. Hoje quem só quer entregar
-- tem de se inscrever como motorista, o que é errado de facto e de direito.
-- A base já sabia disto sem ninguém reparar: `drivers.vehicle_type` distingue
-- `carro_passageiros` de `motorcycle`.
--
-- Por isso `delivery` passa a ser papel de primeira, em `user_roles`, ao lado
-- de driver, cleaner e washer. Tudo o que já se construiu — os papéis, as
-- preferências, os tokens de aviso, a caixa do ecrã — passa a servi-lo sem
-- código novo.
--
-- ── UMA verdade, não duas ──────────────────────────────────────────────────
-- `drivers.work_mode` continua a existir porque a app e o admin já o lêem.
-- Mas deixa de ser escrito à mão: passa a ser PROJECÇÃO da preferência, mantida
-- por gatilho. Ter os dois editáveis era o erro dos gémeos outra vez — dois
-- sítios a guardar a mesma verdade, um actualizado e o outro não. Aqui só há
-- um sítio onde se escreve: `preferencias_papel`.
--
-- Nada disto mexe em preços, comissões, tokens de fidelidade nem no motor de
-- dispatch. Mexe em QUEM é chamado, que é escolha da própria pessoa.
-- ============================================================================

-- ── 1. `delivery` entra nas listas ─────────────────────────────────────────
ALTER TABLE public.user_roles DROP CONSTRAINT IF EXISTS user_roles_role_check;
ALTER TABLE public.user_roles ADD CONSTRAINT user_roles_role_check
  CHECK (role IN ('client', 'driver', 'delivery', 'partner', 'cleaner',
                  'washer', 'admin'));

ALTER TABLE public.preferencias_papel DROP CONSTRAINT IF EXISTS preferencias_papel_papel_check;
ALTER TABLE public.preferencias_papel ADD CONSTRAINT preferencias_papel_papel_check
  CHECK (papel IN ('driver', 'delivery', 'cleaner', 'washer'));

ALTER TABLE public.provider_push_tokens DROP CONSTRAINT IF EXISTS provider_push_tokens_role_check;
ALTER TABLE public.provider_push_tokens ADD CONSTRAINT provider_push_tokens_role_check
  CHECK (role IN ('cleaner', 'washer', 'delivery'));


-- ── 2. Quem já faz entregas passa a ter o papel ────────────────────────────
-- Ninguém perde nada e ninguém ganha trabalho novo: quem já era motorista
-- continua a poder entregar, agora com interruptor próprio.
INSERT INTO public.user_roles (user_id, role)
SELECT d.user_id, 'delivery'
FROM public.drivers d
WHERE d.user_id IS NOT NULL
ON CONFLICT DO NOTHING;

-- E a preferência nasce do estado ACTUAL, para o comportamento não mudar
-- debaixo dos pés de ninguém: quem estava em 'everything' fica com as entregas
-- ligadas; quem estava em 'rides_only' fica com elas desligadas.
INSERT INTO public.preferencias_papel (user_id, papel, aceita)
SELECT d.user_id, 'delivery', (d.work_mode = 'everything')
FROM public.drivers d
WHERE d.user_id IS NOT NULL
ON CONFLICT (user_id, papel) DO NOTHING;


-- ── 3. `work_mode` passa a ser projecção, não fonte ────────────────────────
CREATE OR REPLACE FUNCTION public.projectar_work_mode()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $function$
BEGIN
  -- Só as entregas mexem no work_mode. O interruptor das corridas é lido
  -- directamente da preferência por quem envia os avisos de TVDE.
  IF NEW.papel = 'delivery' THEN
    UPDATE public.drivers
       SET work_mode = CASE WHEN NEW.aceita THEN 'everything' ELSE 'rides_only' END
     WHERE user_id = NEW.user_id
       AND work_mode IS DISTINCT FROM
           (CASE WHEN NEW.aceita THEN 'everything' ELSE 'rides_only' END);
  END IF;
  RETURN NEW;
END;
$function$;

DROP TRIGGER IF EXISTS trg_projectar_work_mode ON public.preferencias_papel;
CREATE TRIGGER trg_projectar_work_mode
  AFTER INSERT OR UPDATE OF aceita ON public.preferencias_papel
  FOR EACH ROW EXECUTE FUNCTION public.projectar_work_mode();

COMMENT ON FUNCTION public.projectar_work_mode() IS
  'drivers.work_mode e PROJECCAO de preferencias_papel(delivery). Nao escrever '
  'work_mode a mao — a fonte unica e a preferencia.';


-- ── 4. A caixa passa a mostrar quatro ──────────────────────────────────────
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
    AND ur.role IN ('driver', 'delivery', 'cleaner', 'washer')
  -- Ordem em que se lê no ecrã, não alfabética: primeiro o que dá mais
  -- trabalho por semana.
  ORDER BY CASE ur.role
             WHEN 'driver'   THEN 1
             WHEN 'delivery' THEN 2
             WHEN 'cleaner'  THEN 3
             WHEN 'washer'   THEN 4
             ELSE 9
           END;
$function$;

REVOKE ALL ON FUNCTION public.meus_papeis_e_preferencias() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.meus_papeis_e_preferencias() TO authenticated;
