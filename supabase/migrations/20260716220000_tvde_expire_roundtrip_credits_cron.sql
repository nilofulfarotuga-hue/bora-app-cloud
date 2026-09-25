-- ═══════════════════════════════════════════════════════════════════════════
-- TVDE — cron que expira vales ida-e-volta vencidos (tvde_roundtrip_credits)
-- ═══════════════════════════════════════════════════════════════════════════
-- Pendência antiga: o vale-volta (pacote 8 EUR, tvde_roundtrip_validity_hours=6) só
-- expirava LAZY — dentro de tvde_request_return_ride, e só se o cliente tentasse usá-lo
-- depois do prazo. Um vale nunca usado ficava para sempre com status='ativo' mesmo depois
-- de vencido, distorcendo admin_tvde_roundtrips() e qualquer métrica de uso.
--
-- Não é reembolso — é só fechar o status (mesma transição que já acontecia lazy). Não
-- mexe em Stripe/pricing, não cria nem move dinheiro novo; análogo a
-- auto_close_no_show_reservations()/_appointment_cron_auto_no_show() já em produção.
-- ═══════════════════════════════════════════════════════════════════════════

CREATE OR REPLACE FUNCTION public.tvde_expire_roundtrip_credits()
RETURNS integer
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE v_count integer;
BEGIN
  WITH expired AS (
    UPDATE public.tvde_roundtrip_credits
       SET status = 'expirado'
     WHERE status = 'ativo'
       AND now() > expires_at
    RETURNING 1
  )
  SELECT count(*) INTO v_count FROM expired;
  RETURN v_count;
END;
$function$;

REVOKE ALL ON FUNCTION public.tvde_expire_roundtrip_credits() FROM public, anon, authenticated;

SELECT cron.schedule(
  'tvde_expire_roundtrip_credits',
  '*/10 * * * *',
  $cron$SELECT public.tvde_expire_roundtrip_credits();$cron$
) WHERE NOT EXISTS (SELECT 1 FROM cron.job WHERE jobname = 'tvde_expire_roundtrip_credits');
