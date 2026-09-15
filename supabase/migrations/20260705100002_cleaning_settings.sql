-- ============================================================================
-- LIMPEZA — platform_settings (categoria 'cleaning') + ratings subject_type
-- Valores decididos pelo Danilo (2026-07-05). Editáveis no admin via
-- admin_update_setting existente (guard + audit).
-- ============================================================================

INSERT INTO public.platform_settings (key, value, description, category) VALUES
  ('cleaning_enabled',                'true'::jsonb,  'Categoria Limpeza ativa na app', 'cleaning'),
  ('cleaning_stripe_enabled',         'false'::jsonb, 'Pagamento cartao/MBWay na Limpeza (ativar so apos deploy da Edge Fn cleaning-checkout)', 'cleaning'),
  ('cleaning_bora_pct',               '15'::jsonb,    'Percentagem Bora no split (profissional recebe o resto)', 'cleaning'),
  ('cleaning_price_t0_t1_cents',      '3500'::jsonb,  'Preco fixo T0/T1 standard (~3h)', 'cleaning'),
  ('cleaning_price_t2_cents',         '4500'::jsonb,  'Preco fixo T2 standard (~4h)', 'cleaning'),
  ('cleaning_price_t3_cents',         '5500'::jsonb,  'Preco fixo T3 standard (~5h)', 'cleaning'),
  ('cleaning_price_t4plus_cents',     '7000'::jsonb,  'Preco fixo T4+ standard (~6h)', 'cleaning'),
  ('cleaning_deep_pct',               '40'::jsonb,    'Limpeza profunda: acrescimo % sobre standard', 'cleaning'),
  ('cleaning_postworks_pct',          '60'::jsonb,    'Pos-obras/mudanca: acrescimo % sobre standard', 'cleaning'),
  ('cleaning_hourly_cents',           '1200'::jsonb,  'Preco por hora (alternativa)', 'cleaning'),
  ('cleaning_min_hours',              '2'::jsonb,     'Minimo de horas no modo por hora', 'cleaning'),
  ('cleaning_products_fee_cents',     '300'::jsonb,   'Taxa produtos da profissional (100% para ela)', 'cleaning'),
  ('cleaning_recurring_discount_pct', '10'::jsonb,    'Desconto recorrencia (semanal/quinzenal)', 'cleaning'),
  ('cleaning_min_lead_hours',         '12'::jsonb,    'Antecedencia minima de agendamento (horas)', 'cleaning'),
  ('cleaning_cancel_free_hours',      '24'::jsonb,    'Cancelamento cliente gratis acima destas horas', 'cleaning'),
  ('cleaning_cancel_half_hours',      '2'::jsonb,     'Entre free e isto: 50%; abaixo disto: 100%', 'cleaning'),
  ('cleaning_offer_timeout_min',      '30'::jsonb,    'Timeout da oferta a profissional (rotation)', 'cleaning'),
  ('cleaning_auto_confirm_hours',     '24'::jsonb,    'Auto-confirmacao apos profissional marcar concluida', 'cleaning'),
  ('cleaning_reminder_24h_enabled',   'true'::jsonb,  'Lembrete push 24h antes', 'cleaning'),
  ('cleaning_reminder_2h_enabled',    'true'::jsonb,  'Lembrete push 2h antes', 'cleaning'),
  ('cleaning_late_cancel_limit',      '3'::jsonb,     'Cancelamentos <24h da profissional em 30d ate suspensao', 'cleaning'),
  ('cleaning_durations_min',          '{"t0_t1":180,"t2":240,"t3":300,"t4plus":360}'::jsonb, 'Duracao estimada por tamanho (minutos)', 'cleaning')
ON CONFLICT (key) DO NOTHING;

-- ratings: aceitar avaliacoes da vertical limpeza (dois lados)
ALTER TABLE public.ratings DROP CONSTRAINT IF EXISTS ratings_subject_type_check;
ALTER TABLE public.ratings ADD CONSTRAINT ratings_subject_type_check
  CHECK (subject_type = ANY (ARRAY['partner'::text, 'driver'::text, 'app'::text,
                                   'tvde_passenger'::text, 'cleaner'::text, 'cleaning_client'::text]));
