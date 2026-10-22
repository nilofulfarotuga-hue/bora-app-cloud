-- 21/10/2026 · fechar-pendencias, agente-encomendas-n2 (Tarefa 3).
-- Encomendas com a MESMA regra de acesso do Bora Motorista ("cópia EXATA do TVDE, só trocam as
-- palavras" — Danilo, relayado pelo orquestrador 21/10): quem tem acesso ao Bora Motorista
-- (users.tvde_access) pede corridas e encomendas; quem não tem, não pede nenhuma das duas.
-- Nas 3 RPCs de pedir, o portão volta a ser o de 20/10, igual para os dois tipos:
--   IF v_ride_kind = 'passageiros' THEN PERFORM public._tvde_exige_acesso(v_uid); END IF;
--   ->  PERFORM public._tvde_exige_acesso(v_uid);
-- Nenhum preço, ganho, comissão, despacho ou permissão muda. Só esta linha, nas 3 funções.
-- Corpo novo sem as linhas do tipo (declaração, resolvedor, coluna do INSERT) = corpo de 20/10
-- byte a byte (2a60a458 / 9ab25a91 / 15c6d850). Aborta sem mexer em nada se o ar tiver mudado.
DO $mig$
DECLARE
  v_antiga constant text := E'  IF v_ride_kind = ''passageiros'' THEN PERFORM public._tvde_exige_acesso(v_uid); END IF;\n';
  v_nova   constant text := E'  PERFORM public._tvde_exige_acesso(v_uid);\n';
  f record;
  v_def text;
  v_md5 text;
  v_acl text;
  v_n int;
BEGIN
  FOR f IN
    SELECT * FROM (VALUES
      ('tvde_request_ride',       'e864711391be540dfbe8085efdd05e61', '2273e348a4983024cf90b66b3b7917e9'),
      ('tvde_schedule_ride',      'b3623e1b87a1432b830e417b2a10a48e', '3ab9d0e5083ca09f50a978909f150cb4'),
      ('tvde_schedule_roundtrip', 'ae675690c6b358e51a876250363264aa', '590b12297e0aba6982dfffea97dbbc73')
    ) AS t(nome, md5_antes, md5_depois)
  LOOP
    SELECT count(*) INTO v_n FROM pg_proc p
     WHERE p.pronamespace = 'public'::regnamespace AND p.proname = f.nome;
    IF v_n <> 1 THEN
      RAISE EXCEPTION '%: % assinaturas (esperava 1) — nada aplicado', f.nome, v_n;
    END IF;
    SELECT pg_get_functiondef(p.oid), md5(p.prosrc), p.proacl::text INTO v_def, v_md5, v_acl
      FROM pg_proc p WHERE p.pronamespace = 'public'::regnamespace AND p.proname = f.nome;
    IF v_md5 IS DISTINCT FROM f.md5_antes THEN
      RAISE EXCEPTION '% mudou no ar (md5 % <> %) — nada aplicado', f.nome, v_md5, f.md5_antes;
    END IF;
    IF (length(v_def) - length(replace(v_def, v_antiga, ''))) <> length(v_antiga) THEN
      RAISE EXCEPTION '%: a linha do portão não aparece exactamente 1 vez — nada aplicado', f.nome;
    END IF;
    EXECUTE replace(v_def, v_antiga, v_nova);
    SELECT md5(p.prosrc) INTO v_md5 FROM pg_proc p
     WHERE p.pronamespace = 'public'::regnamespace AND p.proname = f.nome;
    IF v_md5 IS DISTINCT FROM f.md5_depois THEN
      RAISE EXCEPTION '%: md5 depois % <> % — nada aplicado', f.nome, v_md5, f.md5_depois;
    END IF;
    IF (SELECT p.proacl::text FROM pg_proc p
         WHERE p.pronamespace = 'public'::regnamespace AND p.proname = f.nome) IS DISTINCT FROM v_acl THEN
      RAISE EXCEPTION '%: permissões mudaram — nada aplicado', f.nome;
    END IF;
  END LOOP;
END
$mig$;
