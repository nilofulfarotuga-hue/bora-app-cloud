-- ═══════════════════════════════════════════════════════════════════════════
-- FAVORES (errand) — Fase 1.C: platform_settings (todas editáveis no admin)
-- G4 (Danilo): SEM sistema de horário — apenas errand_available (kill-switch).
-- Disponibilidade real depende de haver estafeta online (dispatch já cuida).
-- value é JSONB (mesmo padrão de delivery_*); ON CONFLICT preserva valores já tocados.
-- ═══════════════════════════════════════════════════════════════════════════
INSERT INTO public.platform_settings (key, value, description, category) VALUES
  ('errand_available',                'true', 'Kill-switch geral dos Favores (disponibilidade depende de estafeta online)', 'errand'),
  ('errand_fee_normal_cents',         '600',  'Taxa cliente favor Normal (até 3h)',           'errand'),
  ('errand_fee_express_cents',        '1000', 'Taxa cliente favor Expresso (45-60min)',       'errand'),
  ('errand_driver_normal_cents',      '500',  'Ganho estafeta favor Normal',                  'errand'),
  ('errand_driver_express_cents',     '800',  'Ganho estafeta favor Expresso',                'errand'),
  ('errand_home_stop_fee_cents',      '200',  'Taxa cliente paragem em casa',                 'errand'),
  ('errand_home_stop_driver_cents',   '100',  'Ganho estafeta paragem em casa',               'errand'),
  ('errand_base_distance_km',         '4',    'Km incluídos antes de cobrar km extra',        'errand'),
  ('errand_per_km_cents',             '50',   'Taxa cliente €/km acima da base',              'errand'),
  ('errand_driver_per_km_cents',      '50',   'Ganho estafeta €/km acima da base (100%)',     'errand'),
  ('errand_max_advance_cents',        '4000', 'Máx adiantamento estafeta sem paragem em casa','errand'),
  ('errand_buffer_multiplier',        '1.2',  'Multiplicador buffer cartão (estimativa×1.2)', 'errand'),
  ('errand_sla_normal_minutes',       '180',  'SLA informativo favor Normal (minutos)',       'errand'),
  ('errand_sla_express_minutes',      '60',   'SLA informativo favor Expresso (minutos)',     'errand'),
  ('errand_description_max_chars',    '500',  'Máx caracteres da descrição do favor',         'errand'),
  ('errand_catalog_queue_enabled',    'true', 'Kill-switch da fila de catálogo automático',   'errand'),
  ('receipt_ocr_enabled',             'true', 'Kill-switch do OCR Gemini do talão',           'receipts'),
  ('receipt_divergence_alert_cents',  '100',  'Limite |digitado-OCR| em cents para alerta',   'receipts')
ON CONFLICT (key) DO NOTHING;
