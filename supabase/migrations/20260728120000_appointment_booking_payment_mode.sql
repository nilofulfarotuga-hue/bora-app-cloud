-- BLOCO B (2026-07-28) — modo de cobrança da marcação por parceiro.
--
-- ⚠️ 🔴 ZONA VERMELHA — ALTERA O VALOR COBRADO AO CLIENTE.
-- Esta migration NÃO foi aplicada. Aguarda o "vai" do Danilo.
-- (Validation Gate do CLAUDE.md: "Migrations/UPDATE que alterem valores
--  cobrados a clientes" = a única travagem que resta.)
--
-- O QUE MUDA
-- ----------
-- `client_book_appointment` gravava SEMPRE
-- `deposit_cents = platform_settings.appointment_deposit_cents` (300).
-- Passa a respeitar `service_providers.booking_payment_mode`:
--   • 'deposit' (default, todos os outros parceiros) → 300, exactamente como hoje;
--   • 'full'    (Barbearia Ouro e Prata)            → `provider_services.price_cents`.
--
-- O QUE **NÃO** MUDA
-- ------------------
--   • `platform_settings.appointment_deposit_cents` (300) — intocado;
--   • o split `appointment_deposit_bora_cut_cents` / `_partner_cut_cents` —
--     intocado; continua a valer para o modo `deposit`;
--   • a Edge `create-appointment-payment-intent` — já cobra `appt.deposit_cents`,
--     não precisa de alteração nenhuma;
--   • `service_price_cents` continua a ser o preço do serviço nos dois modos.
--
-- DEPENDÊNCIA DE RELEASE: o ecrã do cliente (booking_flow_screen) já mostra
-- "Pagas agora €X — valor total do serviço" quando o parceiro está em `full`.
-- Enquanto esta migration não for aplicada, o texto diz €15 e o Stripe cobra
-- €3. Aplicar ao mesmo tempo que a build entra no ar.

CREATE OR REPLACE FUNCTION public.client_book_appointment(
  p_service_id text,
  p_staff_id text,
  p_scheduled_at timestamp with time zone,
  p_client_notes text DEFAULT NULL::text
)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_uid uuid := auth.uid(); v_svc record; v_deposit int; v_max_days int;
  v_appt_id uuid; v_name text; v_phone text;
BEGIN
  IF v_uid IS NULL THEN RAISE EXCEPTION 'auth_required'; END IF;
  -- +sp.booking_payment_mode: é o único acrescento ao SELECT original.
  SELECT ps.duration_minutes, ps.price_cents, sp.id AS prov_id,
         COALESCE(sp.booking_payment_mode, 'deposit') AS pay_mode
    INTO v_svc
    FROM provider_services ps
    JOIN service_providers sp ON sp.id = ps.provider_id
    WHERE ps.id = p_service_id AND ps.is_active AND sp.approval_status='approved';
  IF v_svc IS NULL THEN RAISE EXCEPTION 'service_not_found'; END IF;
  IF NOT EXISTS (SELECT 1 FROM staff_members WHERE id=p_staff_id AND provider_id=v_svc.prov_id AND is_active) THEN
    RAISE EXCEPTION 'staff_not_found';
  END IF;

  SELECT COALESCE((value::text)::int,300) INTO v_deposit FROM platform_settings WHERE key='appointment_deposit_cents';
  v_deposit := COALESCE(v_deposit,300);
  -- ▼ ÚNICA alteração de valor cobrado nesta migration.
  IF v_svc.pay_mode = 'full' THEN
    v_deposit := v_svc.price_cents;
  END IF;
  -- Guarda-costas: o Stripe rejeita abaixo de 0,50 EUR e um preço a zero
  -- criaria uma marcação impagável.
  IF v_deposit IS NULL OR v_deposit < 50 THEN
    RAISE EXCEPTION 'invalid_deposit_amount';
  END IF;

  SELECT COALESCE((value::text)::int,30) INTO v_max_days FROM platform_settings WHERE key='appointment_max_advance_days';
  v_max_days := COALESCE(v_max_days,30);
  IF p_scheduled_at <= now() THEN RAISE EXCEPTION 'slot_in_past'; END IF;
  IF p_scheduled_at > now() + (v_max_days || ' days')::interval THEN RAISE EXCEPTION 'too_far_in_advance'; END IF;
  IF EXISTS (
    SELECT 1 FROM appointments a
    WHERE a.staff_id = p_staff_id
      AND a.status IN ('pending_payment','confirmed','completed','blocked')
      AND tstzrange(a.scheduled_at, a.scheduled_at + (a.duration_minutes||' minutes')::interval,'[)')
          && tstzrange(p_scheduled_at, p_scheduled_at + (v_svc.duration_minutes||' minutes')::interval,'[)')
  ) THEN RAISE EXCEPTION 'slot_taken'; END IF;
  SELECT COALESCE(name,''), COALESCE(phone,'') INTO v_name, v_phone FROM users WHERE id=v_uid;
  INSERT INTO appointments(provider_id, staff_id, service_id, client_user_id, client_name, client_phone,
                           scheduled_at, duration_minutes, service_price_cents, deposit_cents, deposit_status,
                           status, client_notes)
  VALUES (v_svc.prov_id, p_staff_id, p_service_id, v_uid, v_name, v_phone,
          p_scheduled_at, v_svc.duration_minutes, v_svc.price_cents, v_deposit, 'pending',
          'pending_payment', p_client_notes)
  RETURNING id INTO v_appt_id;
  RETURN jsonb_build_object('appointment_id', v_appt_id, 'deposit_cents', v_deposit,
                            'service_price_cents', v_svc.price_cents,
                            'payment_mode', v_svc.pay_mode);
END $function$;
