-- ============================================================================
-- DEMO — Barbearia Nobre (Guarda). Idempotente e reversível.
-- Login: barbearia.nobre@bora.app / BarbeariaNobre2026!
-- is_online=false até testes; approval_status='approved'.
-- Rollback: ver fim do ficheiro.
-- ============================================================================
DO $$
DECLARE
  v_uid uuid;
  v_provider_id text;
  v_tiago text;
  v_andre text;
BEGIN
  -- 1) user auth
  SELECT id INTO v_uid FROM auth.users WHERE email='barbearia.nobre@bora.app';
  IF v_uid IS NULL THEN
    v_uid := gen_random_uuid();
    INSERT INTO auth.users (
      instance_id, id, aud, role, email, encrypted_password,
      email_confirmed_at, created_at, updated_at,
      raw_app_meta_data, raw_user_meta_data,
      confirmation_token, recovery_token, email_change_token_new, email_change
    ) VALUES (
      '00000000-0000-0000-0000-000000000000', v_uid, 'authenticated', 'authenticated',
      'barbearia.nobre@bora.app', crypt('BarbeariaNobre2026!', gen_salt('bf')),
      now(), now(), now(),
      '{"provider":"email","providers":["email"]}'::jsonb,
      jsonb_build_object('bora_role','partner','name','Barbearia Nobre'),
      '', '', '', ''
    );
    INSERT INTO auth.identities (
      id, user_id, identity_data, provider, provider_id,
      last_sign_in_at, created_at, updated_at
    ) VALUES (
      gen_random_uuid(), v_uid,
      jsonb_build_object('sub', v_uid::text, 'email', 'barbearia.nobre@bora.app'),
      'email', v_uid::text, now(), now(), now()
    );
  END IF;

  -- espelho defensivo em public.users (não crítico ao fluxo)
  BEGIN
    INSERT INTO public.users (id, email, name)
    VALUES (v_uid, 'barbearia.nobre@bora.app', 'Barbearia Nobre')
    ON CONFLICT (id) DO NOTHING;
  EXCEPTION WHEN OTHERS THEN NULL; END;

  -- 2) service_provider
  SELECT id INTO v_provider_id FROM service_providers WHERE user_id = v_uid AND name='Barbearia Nobre' LIMIT 1;
  IF v_provider_id IS NULL THEN
    v_provider_id := (gen_random_uuid())::text;
    INSERT INTO service_providers (id, user_id, name, category, description, address, lat, lng, phone,
                                   is_online, is_active_admin, approval_status, approved_at)
    VALUES (v_provider_id, v_uid, 'Barbearia Nobre', 'barbershop',
      'O teu estilo, à tua hora. Cortes modernos e barba impecável no coração da Guarda.',
      'Rua Francisco de Passos, 6300-700 Guarda', 40.5370, -7.2680, '',
      false, true, 'approved', now());
  END IF;

  -- 3) staff (2) + availability Seg-Sáb
  IF NOT EXISTS (SELECT 1 FROM staff_members WHERE provider_id=v_provider_id) THEN
    v_tiago := (gen_random_uuid())::text;
    v_andre := (gen_random_uuid())::text;
    INSERT INTO staff_members (id, provider_id, name, bio, specialties, sort_order) VALUES
      (v_tiago, v_provider_id, 'Tiago', 'Especialista em degradê e barba', ARRAY['Degradê','Barba','Sobrancelha'], 0),
      (v_andre, v_provider_id, 'André', 'Cortes clássicos e modernos', ARRAY['Corte Clássico','Corte Infantil','Coloração'], 1);

    INSERT INTO staff_availability (staff_id, day_of_week, start_time, end_time, is_working)
    SELECT s.id, t.dow, t.st, t.en, true
    FROM (VALUES (v_tiago),(v_andre)) AS s(id)
    CROSS JOIN (VALUES
      (1,'09:00'::time,'19:00'::time),
      (2,'09:00'::time,'19:00'::time),
      (3,'09:00'::time,'19:00'::time),
      (4,'09:00'::time,'19:00'::time),
      (5,'09:00'::time,'19:00'::time),
      (6,'09:00'::time,'17:00'::time)
    ) AS t(dow, st, en);
  END IF;

  -- 4) services (6)
  IF NOT EXISTS (SELECT 1 FROM provider_services WHERE provider_id=v_provider_id) THEN
    INSERT INTO provider_services (provider_id, name, duration_minutes, price_cents, sort_order) VALUES
      (v_provider_id, 'Corte de Cabelo', 30, 1200, 0),
      (v_provider_id, 'Barba',           20,  800, 1),
      (v_provider_id, 'Corte + Barba',   45, 1800, 2),
      (v_provider_id, 'Corte Infantil',  20,  800, 3),
      (v_provider_id, 'Degradê',         40, 1400, 4),
      (v_provider_id, 'Sobrancelha',     10,  500, 5);
  END IF;
END $$;

-- ROLLBACK (manual):
-- DELETE FROM service_providers WHERE name='Barbearia Nobre';  -- CASCADE remove staff/services/availability
-- DELETE FROM auth.identities WHERE user_id=(SELECT id FROM auth.users WHERE email='barbearia.nobre@bora.app');
-- DELETE FROM auth.users WHERE email='barbearia.nobre@bora.app';
