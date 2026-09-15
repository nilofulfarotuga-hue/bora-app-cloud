-- ============================================================================
-- Serviços / Barbearias — platform_settings (value = JSONB)
-- Idempotente: ON CONFLICT DO NOTHING (não sobrescreve valores já ajustados).
-- ============================================================================
INSERT INTO public.platform_settings (key, value, category, description) VALUES
  ('appointment_booking_fee_cents',         to_jsonb(50),   'appointments', 'Taxa Bora por marcação concluída (cents). €0,50'),
  ('appointment_deposit_cents',             to_jsonb(300),  'appointments', 'Sinal obrigatório no momento da marcação (cents). €3,00'),
  ('appointment_cancel_window_hours',       to_jsonb(24),   'appointments', 'Horas antes de scheduled_at em que o cliente cancela com reembolso total do sinal'),
  ('appointment_deposit_bora_cut_cents',    to_jsonb(50),   'appointments', 'Do sinal retido (no-show/late-cancel): parte Bora (cents). €0,50'),
  ('appointment_deposit_partner_cut_cents', to_jsonb(250),  'appointments', 'Do sinal retido (no-show/late-cancel): parte parceiro (cents). €2,50'),
  ('appointment_reminder_24h_enabled',      to_jsonb(true), 'appointments', 'Ativar lembrete 24h antes da marcação'),
  ('appointment_reminder_2h_enabled',       to_jsonb(true), 'appointments', 'Ativar lembrete 2h antes da marcação'),
  ('appointment_max_advance_days',          to_jsonb(30),   'appointments', 'Máximo de dias de antecedência para marcar'),
  ('appointment_min_advance_minutes',       to_jsonb(30),   'appointments', 'Mínimo de minutos de antecedência para um slot ser oferecido'),
  ('appointment_no_show_grace_minutes',     to_jsonb(30),   'appointments', 'Minutos após scheduled_at até a marcação confirmada virar no_show pelo cron')
ON CONFLICT (key) DO NOTHING;
