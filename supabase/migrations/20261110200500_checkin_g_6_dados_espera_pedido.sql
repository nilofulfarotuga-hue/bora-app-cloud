-- Missão fechar-tudo-2026-11-10, Bloco G — parte 6 de 6: R2 nos prémios que já existem.
-- Antes de 10/11 só o serviço do dia 30 esperava por um pedido pago; os produtos saíam logo.
-- Agora TODO o prémio espera. Quem já levantou não perde: o vale continua dele e passa a
-- "Falta 1 pedido para desbloquear", com prazo nunca menor do que o que já tinha; desbloqueia
-- sozinho quando comprar (checkin_premios_manutencao, de hora a hora).
-- Os prémios ainda só guardados na escada (checkin_escada) não mudam: quando a pessoa
-- carregar "Quero este" o vale nasce já à espera (parte 2).
-- Cópias de segurança antes de mexer (nunca se apaga nada).

CREATE TABLE IF NOT EXISTS public.bkp_checkin_premios_vales_20261110 AS
  SELECT * FROM public.checkin_premios_vales;
CREATE TABLE IF NOT EXISTS public.bkp_checkin_escada_20261110 AS
  SELECT * FROM public.checkin_escada;
ALTER TABLE public.bkp_checkin_premios_vales_20261110 ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.bkp_checkin_escada_20261110 ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.bkp_checkin_premios_vales_20261110 FROM PUBLIC, anon, authenticated;
REVOKE ALL ON public.bkp_checkin_escada_20261110 FROM PUBLIC, anon, authenticated;

DO $$
DECLARE
  v_n integer := 0;
BEGIN
  IF public._checkin_cfg_bool('checkin_marco_exige_pedido_pago', true) THEN
    UPDATE public.checkin_premios_vales v
       SET estado = 'a_espera_pedido',
           esperar_ate = GREATEST(COALESCE(v.valido_ate, now()),
                                  now() + make_interval(days => LEAST(GREATEST(
                                    public._checkin_cfg_int('checkin_marco_espera_pedido_dias', 30), 1), 365))),
           motivo = COALESCE(v.motivo || ' | ', '') || 'R2 10/11: espera 1 pedido pago',
           atualizado_em = now()
     WHERE v.origem = 'checkin'
       AND v.estado = 'por_usar'
       AND v.pedido_id IS NULL
       AND NOT public._checkin_teve_pedido_pago(v.user_id, public._checkin_cfg_int('checkin_marco_pedido_pago_dias', 30));
    GET DIAGNOSTICS v_n = ROW_COUNT;
  END IF;
  INSERT INTO public.e2e_log (fluxo, passo, estado, detalhe, device)
  VALUES ('fechar-tudo-2026-11-10', 'G-migracao-R2', 'ok',
          'Vales por usar sem pedido pago passaram a esperar pelo pedido: ' || v_n
          || ' (backup bkp_checkin_premios_vales_20261110 e bkp_checkin_escada_20261110).', 'servidor');
END;
$$;
