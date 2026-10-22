-- REVERSÃO da migração 20261021195814_encomendas_mesmo_acesso_do_bora_motorista (N2, 21/10/2026).
-- Só se o Danilo escolher "encomendas abertas a todos" (opção b). NÃO correr sem essa ordem.
-- Volta a pôr o portão só nos passageiros (como ficou o A1): md5 2273e348/3ab9d0e5/590b1229 -> e864711/b3623e1b/ae675690.
DO $rev$
DECLARE
  v_nova   constant text := E'  PERFORM public._tvde_exige_acesso(v_uid);\n';
  v_antiga constant text := E'  IF v_ride_kind = ''passageiros'' THEN PERFORM public._tvde_exige_acesso(v_uid); END IF;\n';
  f record;
  v_def text;
  v_md5 text;
BEGIN
  FOR f IN
    SELECT * FROM (VALUES
      ('tvde_request_ride',       '2273e348a4983024cf90b66b3b7917e9', 'e864711391be540dfbe8085efdd05e61'),
      ('tvde_schedule_ride',      '3ab9d0e5083ca09f50a978909f150cb4', 'b3623e1b87a1432b830e417b2a10a48e'),
      ('tvde_schedule_roundtrip', '590b12297e0aba6982dfffea97dbbc73', 'ae675690c6b358e51a876250363264aa')
    ) AS t(nome, md5_agora, md5_volta)
  LOOP
    SELECT pg_get_functiondef(p.oid), md5(p.prosrc) INTO v_def, v_md5
      FROM pg_proc p WHERE p.pronamespace = 'public'::regnamespace AND p.proname = f.nome;
    IF v_md5 IS DISTINCT FROM f.md5_agora THEN
      RAISE EXCEPTION '% mudou (md5 % <> %) — nada revertido', f.nome, v_md5, f.md5_agora;
    END IF;
    EXECUTE replace(v_def, v_nova, v_antiga);
    SELECT md5(p.prosrc) INTO v_md5 FROM pg_proc p WHERE p.pronamespace = 'public'::regnamespace AND p.proname = f.nome;
    IF v_md5 IS DISTINCT FROM f.md5_volta THEN
      RAISE EXCEPTION '%: md5 depois da reversão % <> %', f.nome, v_md5, f.md5_volta;
    END IF;
  END LOOP;
END
$rev$;
