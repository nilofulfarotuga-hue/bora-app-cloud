-- ============================================================================
-- CANDIDATURA DE LAVADOR — a porta que nunca existiu
--
-- Estado a 2026-08-28: a Lavagem Auto estava no ar, com motor, rotacao, avisos
-- e painel de admin — e **ninguem no mundo se podia inscrever como lavador**.
-- Nao havia ecra de candidatura nem funcao na base. As tres linhas de `washers`
-- que existem foram todas metidas a mao.
--
-- E o buraco tinha um irmao silencioso: a tabela `cleaners` tem o gatilho
-- `trg_grant_role_cleaners` que da o papel a quem se inscreve; a `washers`
-- **nao tinha gatilho nenhum**. Prova disso: dos tres lavadores, o "Lava & Leva"
-- nao tem `washer` em `user_roles`. E a regra dos gemeos outra vez — o papel
-- vive em quatro sitios (PADRAO_BORA §2.1) e um deles ficou por preencher.
--
-- Nada aqui toca em precos, comissoes, tokens nem no motor de despacho.
-- ============================================================================

-- ── 1. Onde vivem os documentos do lavador ─────────────────────────────────
-- Balde privado, com as MESMAS quatro politicas do `cleaner-documents`, que
-- estao provadas desde Julho. Copiadas a letra: a pessoa le e escreve dentro da
-- sua propria pasta, e o admin le tudo pelo claim do JWT — nunca consultando
-- `auth.users`, que e proibida ao papel `authenticated`.
INSERT INTO storage.buckets (id, name, public)
VALUES ('washer-documents', 'washer-documents', false)
ON CONFLICT (id) DO NOTHING;

DROP POLICY IF EXISTS washers_upload_own_docs ON storage.objects;
CREATE POLICY washers_upload_own_docs ON storage.objects
  FOR INSERT TO authenticated
  WITH CHECK (bucket_id = 'washer-documents'
              AND (storage.foldername(name))[1] = (auth.uid())::text);

DROP POLICY IF EXISTS washers_read_own_docs ON storage.objects;
CREATE POLICY washers_read_own_docs ON storage.objects
  FOR SELECT TO authenticated
  USING (bucket_id = 'washer-documents'
         AND (storage.foldername(name))[1] = (auth.uid())::text);

DROP POLICY IF EXISTS washers_update_own_docs ON storage.objects;
CREATE POLICY washers_update_own_docs ON storage.objects
  FOR UPDATE TO authenticated
  USING (bucket_id = 'washer-documents'
         AND (storage.foldername(name))[1] = (auth.uid())::text);

DROP POLICY IF EXISTS admin_read_all_washer_docs ON storage.objects;
CREATE POLICY admin_read_all_washer_docs ON storage.objects
  FOR SELECT TO authenticated
  USING (bucket_id = 'washer-documents'
         AND ((auth.jwt() -> 'app_metadata') ->> 'role') = 'admin');


-- ── 2. Inscrever-se como lavador passa a dar o papel ───────────────────────
DROP TRIGGER IF EXISTS trg_grant_role_washers ON public.washers;
CREATE TRIGGER trg_grant_role_washers
  AFTER INSERT ON public.washers
  FOR EACH ROW EXECUTE FUNCTION public._grant_role_from_profile('washer');

-- E quem ja la estava sem papel passa a te-lo. Sem isto, o interruptor do
-- prestador nao mostra a lavagem a quem ja a faz.
INSERT INTO public.user_roles (user_id, role)
SELECT w.user_id, 'washer' FROM public.washers w WHERE w.user_id IS NOT NULL
ON CONFLICT DO NOTHING;


-- ── 3. A candidatura em si ─────────────────────────────────────────────────
-- Molde do `cleaner_apply`, com uma diferenca de tabela: `washers` nao tem
-- coluna `equipment` (o material fica dentro de `docs`), e tem colunas de
-- banimento que esta funcao NUNCA toca — recandidatar-se nao desbane ninguem.
CREATE OR REPLACE FUNCTION public.washer_apply(
  p_name text,
  p_phone text,
  p_email text,
  p_nif text,
  p_bio text DEFAULT '',
  p_photo_url text DEFAULT '',
  p_base_address text DEFAULT '',
  p_base_lat double precision DEFAULT NULL,
  p_base_lng double precision DEFAULT NULL,
  p_service_radius_km numeric DEFAULT 10,
  p_docs jsonb DEFAULT '{}'::jsonb
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE v_uid uuid := auth.uid(); v_existing washers; v_id uuid;
BEGIN
  IF v_uid IS NULL THEN RAISE EXCEPTION 'not_authenticated' USING ERRCODE = '42501'; END IF;
  IF length(trim(COALESCE(p_name,''))) < 3 THEN RAISE EXCEPTION 'name_required'; END IF;
  IF length(trim(COALESCE(p_phone,''))) < 9 THEN RAISE EXCEPTION 'phone_required'; END IF;

  SELECT * INTO v_existing FROM washers WHERE user_id = v_uid;

  IF v_existing.id IS NOT NULL THEN
    -- Quem foi banido nao se recandidata por esta porta: e decisao de admin.
    IF v_existing.is_banned THEN RAISE EXCEPTION 'washer_banned'; END IF;
    IF v_existing.approval_status IN ('pending','approved') THEN
      RAISE EXCEPTION 'application_already_exists';
    END IF;
    UPDATE washers
    SET name = p_name, phone = p_phone, email = COALESCE(p_email,''),
        nif = COALESCE(p_nif,''), bio = COALESCE(p_bio,''),
        photo_url = COALESCE(p_photo_url,''),
        base_address = COALESCE(p_base_address,''),
        base_lat = p_base_lat, base_lng = p_base_lng,
        service_radius_km = COALESCE(p_service_radius_km, 10),
        docs = COALESCE(p_docs,'{}'::jsonb),
        approval_status = 'pending', rejection_reason = NULL
    WHERE id = v_existing.id
    RETURNING id INTO v_id;
  ELSE
    INSERT INTO washers (user_id, name, phone, email, nif, bio, photo_url,
                         base_address, base_lat, base_lng, service_radius_km, docs)
    VALUES (v_uid, p_name, p_phone, COALESCE(p_email,''), COALESCE(p_nif,''),
            COALESCE(p_bio,''), COALESCE(p_photo_url,''), COALESCE(p_base_address,''),
            p_base_lat, p_base_lng, COALESCE(p_service_radius_km, 10),
            COALESCE(p_docs,'{}'::jsonb))
    RETURNING id INTO v_id;
  END IF;

  PERFORM public._carwash_notify_admin('Nova candidatura de lavador',
    p_name || ' candidatou-se. Rever documentos no painel.');

  RETURN (SELECT to_jsonb(w) FROM washers w WHERE w.id = v_id);
END $function$;

-- REVOKE de PUBLIC **e de anon**: o Supabase tem privilegios por omissao que
-- dao EXECUTE a `anon` a toda a funcao nova em `public`, e esse GRANT explicito
-- sobrevive a um `REVOKE FROM PUBLIC`. O `cleaner_apply` nao tem `anon` na ACL;
-- este passa a nao ter tambem.
REVOKE ALL ON FUNCTION public.washer_apply(text,text,text,text,text,text,text,
  double precision,double precision,numeric,jsonb) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.washer_apply(text,text,text,text,text,text,text,
  double precision,double precision,numeric,jsonb) TO authenticated;


-- ── 4. O resumo de papeis passa a saber que a lavagem existe ───────────────
-- Servia para o convite cruzado estafeta<->limpeza. Agora serve os quatro, e e
-- o que enche a porta "Quero trabalhar no Bora": diz o que a pessoa ja e, o que
-- tem em analise, e o que ainda pode ser — sem lhe pedir os dados outra vez.
CREATE OR REPLACE FUNCTION public.my_roles_summary()
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_uid uuid := auth.uid();
  v_has_driver boolean; v_driver_status text;
  v_dn text; v_dp text; v_de text; v_dnif text; v_dphoto text;
  v_has_cleaner boolean; v_cleaner_status text;
  v_cn text; v_cp text; v_ce text; v_cnif text; v_cphoto text;
  v_has_washer boolean; v_washer_status text;
  v_wn text; v_wp text; v_we text; v_wnif text; v_wphoto text;
BEGIN
  IF v_uid IS NULL THEN
    RAISE EXCEPTION 'not_authenticated' USING ERRCODE = '42501';
  END IF;

  SELECT true, approval_status, name, phone, email, nif, photo_url
    INTO v_has_driver, v_driver_status, v_dn, v_dp, v_de, v_dnif, v_dphoto
    FROM drivers WHERE user_id = v_uid LIMIT 1;

  SELECT true, approval_status, name, phone, email, nif, photo_url
    INTO v_has_cleaner, v_cleaner_status, v_cn, v_cp, v_ce, v_cnif, v_cphoto
    FROM cleaners WHERE user_id = v_uid LIMIT 1;

  SELECT true, approval_status, name, phone, email, nif, photo_url
    INTO v_has_washer, v_washer_status, v_wn, v_wp, v_we, v_wnif, v_wphoto
    FROM washers WHERE user_id = v_uid LIMIT 1;

  RETURN jsonb_build_object(
    'has_driver',     COALESCE(v_has_driver, false),
    'driver_status',  v_driver_status,
    'has_cleaner',    COALESCE(v_has_cleaner, false),
    'cleaner_status', v_cleaner_status,
    'has_washer',     COALESCE(v_has_washer, false),
    'washer_status',  v_washer_status,
    'driver_profile', CASE WHEN v_has_driver THEN jsonb_build_object(
        'name', v_dn, 'phone', v_dp, 'email', v_de, 'nif', v_dnif, 'photo_url', v_dphoto) ELSE NULL END,
    'cleaner_profile', CASE WHEN v_has_cleaner THEN jsonb_build_object(
        'name', v_cn, 'phone', v_cp, 'email', v_ce, 'nif', v_cnif, 'photo_url', v_cphoto) ELSE NULL END,
    'washer_profile', CASE WHEN v_has_washer THEN jsonb_build_object(
        'name', v_wn, 'phone', v_wp, 'email', v_we, 'nif', v_wnif, 'photo_url', v_wphoto) ELSE NULL END
  );
END $function$;
