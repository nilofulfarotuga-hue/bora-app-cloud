-- 31/10/2026 — ordem do Danilo no chat da Claude.ai (19:53, "eu autorizo de 1 a 8"):
-- (7) limpeza sem mínimo de antecedência para marcar (decisão dele de julho: "sem mínimo"; o servidor tinha 12 h,
--     e foi isso que pôs ao Divan uma limpeza para domingo 05:23 em vez de hoje).
-- (8) o cliente cancela sem taxa nos primeiros 5 minutos depois de marcar (como a Uber).
-- Só mexe nestas duas regras da limpeza; nenhum outro valor muda.

update public.platform_settings
   set value = '0'::jsonb, updated_at = now(), updated_by = 'c9fccf85-03ee-4efc-83bf-613f211a78ff'
 where key = 'cleaning_min_lead_hours';

insert into public.platform_settings (key, value, description, category, updated_at, updated_by, is_secret)
values ('cleaning_cancel_grace_minutes', '5'::jsonb,
        'Minutos depois de marcar em que o cliente cancela a limpeza sem taxa (como a Uber). Decisão do Danilo 31/10/2026.',
        'cleaning', now(), 'c9fccf85-03ee-4efc-83bf-613f211a78ff', false)
on conflict (key) do update set value = excluded.value, description = excluded.description, updated_at = now(), updated_by = excluded.updated_by;

DO $mig$
DECLARE
  d text := pg_get_functiondef('public.cancel_cleaning_booking(uuid,text,boolean)'::regprocedure);
  n text;
BEGIN
  n := replace(d,
    'IF v_hours >= v_free THEN v_fee := 0;',
    'IF v_hours >= v_free OR now() - v_b.created_at <= make_interval(mins => public._cleaning_setting_int(''cleaning_cancel_grace_minutes'', 5)) THEN v_fee := 0;');
  IF n = d THEN
    RAISE EXCEPTION 'regra da taxa nao encontrada em cancel_cleaning_booking; nada foi mudado';
  END IF;
  EXECUTE n;
END
$mig$;

insert into public.admin_audit_log (admin_id, admin_email, action, entity_type, entity_id_text, details)
values
 ('c9fccf85-03ee-4efc-83bf-613f211a78ff', 'nilofulfarotuga@gmail.com', 'platform_setting_update', 'platform_settings', 'cleaning_min_lead_hours',
  jsonb_build_object('antes', 12, 'depois', 0, 'por', 'claude-ai', 'ordem', 'Danilo chat 31/10/2026 19:53 "autorizo de 1 a 8"')),
 ('c9fccf85-03ee-4efc-83bf-613f211a78ff', 'nilofulfarotuga@gmail.com', 'platform_setting_update', 'platform_settings', 'cleaning_cancel_grace_minutes',
  jsonb_build_object('antes', null, 'depois', 5, 'por', 'claude-ai', 'ordem', 'Danilo chat 31/10/2026 19:53 "autorizo de 1 a 8"'));
