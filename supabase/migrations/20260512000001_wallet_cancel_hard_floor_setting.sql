-- Hard floor wallet APENAS para cancelamento CASH after_pickup (até €40 negativo).
-- Ajustes/sacos continuam a usar wallet_hard_floor_cents (€20).
INSERT INTO public.platform_settings (key, value)
VALUES ('wallet_cancel_hard_floor_cents', '-4000'::jsonb)
ON CONFLICT (key) DO UPDATE SET value = EXCLUDED.value;

COMMENT ON TABLE public.platform_settings IS
'Settings runtime da plataforma. Hard floors wallet: wallet_hard_floor_cents=-2000 (ajustes/sacos), wallet_cancel_hard_floor_cents=-4000 (cancel CASH after_pickup, pior caso €40 limite CASH).';
