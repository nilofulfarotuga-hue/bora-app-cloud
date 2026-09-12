-- 1) Add missing columns to drivers
ALTER TABLE public.drivers
  ADD COLUMN IF NOT EXISTS vehicle_doc_url TEXT,
  ADD COLUMN IF NOT EXISTS address TEXT,
  ADD COLUMN IF NOT EXISTS submitted_at TIMESTAMPTZ,
  ADD COLUMN IF NOT EXISTS reviewed_at TIMESTAMPTZ;

-- 2) Replace RPC to accept new params: p_mbway_phone, p_address, p_vehicle_doc_url
CREATE OR REPLACE FUNCTION public.driver_register_or_update(
  p_name TEXT,
  p_phone TEXT,
  p_vehicle_type TEXT,
  p_license_plate TEXT DEFAULT NULL,
  p_document_type TEXT DEFAULT NULL,
  p_document_number TEXT DEFAULT NULL,
  p_document_photo_url TEXT DEFAULT NULL,
  p_vehicle_photo_url TEXT DEFAULT NULL,
  p_registration_selfie_url TEXT DEFAULT NULL,
  p_iban TEXT DEFAULT NULL,
  p_nif TEXT DEFAULT NULL,
  p_mbway_phone TEXT DEFAULT NULL,
  p_address TEXT DEFAULT NULL,
  p_vehicle_doc_url TEXT DEFAULT NULL
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_user_id UUID := auth.uid();
  v_driver_id UUID;
BEGIN
  IF v_user_id IS NULL THEN
    RETURN jsonb_build_object('success', false, 'reason', 'unauthorized');
  END IF;

  INSERT INTO public.drivers (
    user_id, name, phone, vehicle_type, license_plate,
    document_type, document_number, document_photo_url,
    vehicle_photo_url, registration_selfie_url, iban, nif,
    mbway_phone, address, vehicle_doc_url,
    approval_status, submitted_at, created_at, updated_at
  ) VALUES (
    v_user_id, p_name, p_phone, p_vehicle_type, p_license_plate,
    p_document_type, p_document_number, p_document_photo_url,
    p_vehicle_photo_url, p_registration_selfie_url, p_iban, p_nif,
    p_mbway_phone, p_address, p_vehicle_doc_url,
    'pending', now(), now(), now()
  )
  ON CONFLICT (user_id) DO UPDATE SET
    name = EXCLUDED.name,
    phone = EXCLUDED.phone,
    vehicle_type = EXCLUDED.vehicle_type,
    license_plate = COALESCE(EXCLUDED.license_plate, drivers.license_plate),
    document_type = COALESCE(EXCLUDED.document_type, drivers.document_type),
    document_number = COALESCE(EXCLUDED.document_number, drivers.document_number),
    document_photo_url = COALESCE(EXCLUDED.document_photo_url, drivers.document_photo_url),
    vehicle_photo_url = COALESCE(EXCLUDED.vehicle_photo_url, drivers.vehicle_photo_url),
    registration_selfie_url = COALESCE(EXCLUDED.registration_selfie_url, drivers.registration_selfie_url),
    iban = COALESCE(EXCLUDED.iban, drivers.iban),
    nif = COALESCE(EXCLUDED.nif, drivers.nif),
    mbway_phone = COALESCE(EXCLUDED.mbway_phone, drivers.mbway_phone),
    address = COALESCE(EXCLUDED.address, drivers.address),
    vehicle_doc_url = COALESCE(EXCLUDED.vehicle_doc_url, drivers.vehicle_doc_url),
    updated_at = now()
  RETURNING id INTO v_driver_id;

  RETURN jsonb_build_object('success', true, 'driver_id', v_driver_id);
EXCEPTION WHEN OTHERS THEN
  RETURN jsonb_build_object('success', false, 'reason', SQLERRM);
END;
$function$;
