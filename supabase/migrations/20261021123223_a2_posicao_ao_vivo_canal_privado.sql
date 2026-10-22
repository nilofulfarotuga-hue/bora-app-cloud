-- A2 · CARRO A DESLIZAR — canal PRIVADO do Supabase Realtime por corrida (missão
-- fechar-pendencias-2026-10-20). Não toca no despacho nem em nada de dinheiro.
--
-- O motorista atribuído emite a posição de poucos em poucos segundos no canal "tvde_pos:<id da
-- corrida>" (broadcast, private: true); o cliente da corrida ouve e anima o carro entre posições.
-- Realtime Authorization (doc oficial supabase.com/docs/guides/realtime/authorization): as
-- políticas em realtime.messages decidem quem entra no canal privado.
--   * ouvir  (SELECT): o cliente E o motorista da corrida, só enquanto a corrida está atribuída /
--     a caminho / chegou / em andamento;
--   * emitir (INSERT): só o motorista atribuído, nas mesmas fases.
-- Anónimos: nenhuma política → não entram. Nada de posição de motoristas a quem não é da corrida.
-- Sem canal (rede, política), a app continua com o que já tinha (driver_locations + poll).

CREATE OR REPLACE FUNCTION public.tvde_pos_ao_vivo_pode(p_topico text, p_emitir boolean)
RETURNS boolean
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_uid uuid := auth.uid();
  v_id  uuid;
BEGIN
  IF v_uid IS NULL OR p_topico IS NULL
     OR p_topico !~ '^tvde_pos:[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$' THEN
    RETURN false;
  END IF;
  v_id := substr(p_topico, 10)::uuid;   -- 'tvde_pos:' tem 9 caracteres
  RETURN EXISTS (
    SELECT 1 FROM public.tvde_rides r
     WHERE r.id = v_id
       AND r.status IN ('motorista_atribuido', 'motorista_a_caminho', 'motorista_chegou', 'em_andamento')
       AND r.driver_id IS NOT NULL
       AND (r.driver_id = v_uid OR (NOT COALESCE(p_emitir, true) AND r.client_id = v_uid)));
END;
$function$;

REVOKE ALL ON FUNCTION public.tvde_pos_ao_vivo_pode(text, boolean) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.tvde_pos_ao_vivo_pode(text, boolean) TO authenticated;

DROP POLICY IF EXISTS tvde_pos_ao_vivo_ouvir ON realtime.messages;
CREATE POLICY tvde_pos_ao_vivo_ouvir ON realtime.messages
  FOR SELECT TO authenticated
  USING (realtime.messages.extension = 'broadcast'
         AND public.tvde_pos_ao_vivo_pode((SELECT realtime.topic()), false));

DROP POLICY IF EXISTS tvde_pos_ao_vivo_emitir ON realtime.messages;
CREATE POLICY tvde_pos_ao_vivo_emitir ON realtime.messages
  FOR INSERT TO authenticated
  WITH CHECK (realtime.messages.extension = 'broadcast'
              AND public.tvde_pos_ao_vivo_pode((SELECT realtime.topic()), true));

-- Interruptor (painel) e cadência. Ligado: só tem efeito com a app nova; desligado = a app nem
-- abre o canal e fica tudo como hoje (driver_locations + poll).
INSERT INTO public.platform_settings (key, value, description, category) VALUES
  ('tvde_pos_ao_vivo_enabled', 'true'::jsonb,
   'Carro a deslizar: o motorista emite a posição num canal privado da corrida (Supabase Realtime) e o cliente anima o carro sobre a rota. Desligado = só o caminho antigo (driver_locations + poll).',
   'tvde'),
  ('tvde_pos_ao_vivo_intervalo_s', '2'::jsonb,
   'Carro a deslizar: de quantos em quantos segundos o motorista emite a posição no canal da corrida (1 a 10).',
   'tvde')
ON CONFLICT (key) DO NOTHING;
