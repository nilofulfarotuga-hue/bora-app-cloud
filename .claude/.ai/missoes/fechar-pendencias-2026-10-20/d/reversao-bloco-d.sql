-- REVERSÃO do Bloco D (marcos do check-in), migrações 20261021045300 .. 20261021050727.
-- NÃO correr sem ordem do Danilo. Desliga primeiro, depois desfaz (sem apagar dados de clientes:
-- os vales ficam guardados numa cópia antes de a tabela sair).
--
-- Passo 0 (basta para parar tudo, sem apagar nada): desligar.
--   select public.admin_update_setting('checkin_marco_ativo', 'false'::jsonb);
--   update public.support_skills set active = false where skill_name = 'CHECKIN_MARCOS_PREMIOS';
--
-- Passo 1 (desfazer de vez):
BEGIN;
SELECT cron.unschedule('checkin-premios-manutencao');

-- lembretes: repor a versão de 18/10 (md5 do corpo antigo: abfeca53817be18e7655e03ad745e0fd);
-- o texto antigo está em supabase_migrations.schema_migrations, versão 20261018170119.

DROP TRIGGER IF EXISTS trg_checkin_premio_limpeza_cancelada ON public.cleaning_bookings;
DROP TRIGGER IF EXISTS trg_checkin_premio_lavagem_cancelada ON public.carwash_bookings;
DROP TRIGGER IF EXISTS trg_checkin_premio_no_pedido ON public.orders;
DROP TRIGGER IF EXISTS trg_checkin_premio_pedido_cancelado ON public.orders;
DROP TRIGGER IF EXISTS trg_checkin_marcos_apos_checkin ON public.daily_checkins;

DROP FUNCTION IF EXISTS public.client_checkin_premio_marcar_limpeza(uuid, timestamptz, text, text, text, double precision, double precision, text);
DROP FUNCTION IF EXISTS public.client_checkin_premio_marcar_lavagem(uuid, text, text, text, timestamptz, text, text, text, double precision, double precision, text, text, text);
DROP FUNCTION IF EXISTS public._checkin_premio_marcacao_cancelada();
DROP FUNCTION IF EXISTS public._checkin_premio_no_pedido();
DROP FUNCTION IF EXISTS public._checkin_premio_pedido_cancelado();
DROP FUNCTION IF EXISTS public.admin_checkin_premios_pagar_loja(uuid[], text);
DROP FUNCTION IF EXISTS public.admin_checkin_premio_marcar_usado(uuid, text);
DROP FUNCTION IF EXISTS public.admin_checkin_premio_dar(uuid, text, text);
DROP FUNCTION IF EXISTS public.admin_checkin_premio_anular(uuid, text);
DROP FUNCTION IF EXISTS public.admin_checkin_premios_resumo();
DROP FUNCTION IF EXISTS public.admin_checkin_premios_lista(text, text, integer);
DROP FUNCTION IF EXISTS public.checkin_premios_manutencao();
DROP FUNCTION IF EXISTS public.client_checkin_premio_escolher(uuid, text);
DROP FUNCTION IF EXISTS public.client_checkin_premio_libertar(uuid);
DROP FUNCTION IF EXISTS public.client_checkin_premio_reservar(uuid);
DROP FUNCTION IF EXISTS public.client_checkin_premio_visto(uuid[]);
DROP FUNCTION IF EXISTS public.client_checkin_premios();
DROP FUNCTION IF EXISTS public._checkin_vale_json(public.checkin_premios_vales);
DROP FUNCTION IF EXISTS public._checkin_marcos_apos_checkin();
DROP FUNCTION IF EXISTS public._checkin_vale_emitir(uuid, jsonb, date, text, uuid, text);
DROP FUNCTION IF EXISTS public._checkin_vale_ativar(uuid, boolean);
DROP FUNCTION IF EXISTS public._checkin_vale_avisar(uuid, text);
DROP FUNCTION IF EXISTS public._checkin_teve_pedido_pago(uuid, integer);
-- _checkin_estado_marcos é usada pelos lembretes: só sai depois de repor os lembretes antigos.
DROP FUNCTION IF EXISTS public._checkin_estado_marcos(uuid);
DROP FUNCTION IF EXISTS public._checkin_sequencia(uuid, date);
DROP FUNCTION IF EXISTS public._checkin_marcos_config();
DROP FUNCTION IF EXISTS public._checkin_marco_cfg(text, jsonb);

-- forma de pagamento 'premio': só se volta à lista antiga se não houver marcações 'premio'
-- (se houver, primeiro decidir o que fazer com elas).
-- ALTER TABLE public.cleaning_bookings DROP CONSTRAINT cleaning_bookings_payment_method_check;
-- ALTER TABLE public.cleaning_bookings ADD CONSTRAINT cleaning_bookings_payment_method_check
--   CHECK (payment_method = ANY (ARRAY['card','mbway','cash']));
-- (o mesmo para carwash_bookings)

DROP POLICY IF EXISTS products_premio_checkin_oculto_anon ON public.products;
DROP POLICY IF EXISTS products_premio_checkin_oculto ON public.products;
-- os 2 artigos-prémio a 0 EUR: tirar do catálogo SEM apagar (ficam escondidos)
UPDATE public.products SET is_available = false, removal_reason = 'bloco D revertido'
 WHERE id IN ('premio-checkin-salgados', 'premio-checkin-acai');

UPDATE public.support_skills SET active = false WHERE skill_name = 'CHECKIN_MARCOS_PREMIOS';

-- cópia dos vales antes de a tabela sair (regra: nunca apagar dados de produção sem backup)
CREATE TABLE IF NOT EXISTS public.bkp_checkin_premios_vales_20261021 AS TABLE public.checkin_premios_vales;
ALTER TABLE public.bkp_checkin_premios_vales_20261021 ENABLE ROW LEVEL SECURITY;
DROP TABLE IF EXISTS public.checkin_premios_vales;

DELETE FROM public.platform_settings WHERE key LIKE 'checkin\_marco\_%';
COMMIT;
