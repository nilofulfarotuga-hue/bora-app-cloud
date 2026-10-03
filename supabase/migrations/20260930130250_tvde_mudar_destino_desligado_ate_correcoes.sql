-- 30/09: revisão adversarial encontrou falhas no caminho do pagamento. Interruptor
-- DESLIGADO até as correções estarem provadas (o servidor recusa com dest_change_disabled).
-- Aplicada no ar pela sessão Claude Code (schema_migrations: tvde_mudar_destino_desligado_ate_correcoes).
UPDATE public.platform_settings SET value = 'false'::jsonb, updated_at = now()
 WHERE key = 'tvde_dest_change_enabled';
