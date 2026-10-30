-- Gorjetas (missão gorjetas-taxa-2026-10-30, Bloco A): interruptor da gorjeta do carrinho no
-- mesmo pagamento da compra. Começa DESLIGADO: o líder só o liga depois de as Edge Functions do
-- pagamento (patches em docs/propostas/gorjetas-taxa-2026-10-30/) estarem no ar e provadas.
-- Mesma categoria e as mesmas marcas das chaves tips_enabled e tip_max_cents (não é segredo:
-- get_setting devolve-a a qualquer pessoa, como as outras chaves de gorjeta). O painel admin grava-a
-- por admin_update_setting (que só aceita chaves que já existem).
INSERT INTO public.platform_settings (key, value, category, description, is_secret) VALUES
  ('tips_checkout_junto_pagamento', 'false'::jsonb, 'tips',
   'Gorjeta do carrinho cobrada no MESMO pagamento da compra (cartão e MB Way), inteira para o estafeta. false = como antes (cobrada à parte depois de o pedido existir).',
   false)
ON CONFLICT (key) DO NOTHING;
