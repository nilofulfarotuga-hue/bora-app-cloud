-- F1 (missao-geral-2026-10-28, Bloco 3): a data da autocertificação (DAC7) do PARCEIRO deixa de ser
-- carimbada outra vez cada vez que ele grava os dados fiscais.
--
-- O que estava mal (provider_update_legal_fields, ramo 'partner', definição viva lida a 28/10):
--  1. A app obriga a ter a caixa da autocertificação marcada para gravar, por isso manda sempre
--     p_self_certify = true. O servidor punha dsa_self_certified_at = now() em TODAS as lojas do dono
--     (WHERE r.user_id = v_uid OR r.user_ = v_uid), mesmo sem nada ter mudado.
--  2. Um dono com DUAS lojas nem conseguia gravar: UPDATE ... RETURNING ... INTO com mais de uma linha
--     dá erro no PL/pgSQL ("query returned more than one row").
--
-- Agora, em cada loja do dono:
--  - a data só é carimbada quando o parceiro marca a autocertificação E (a loja ainda não a tinha OU
--    um dos dados fiscais DESSA loja muda agora: nome legal, NIF, morada, IBAN, data de nascimento);
--  - se nada mudou, a data e a versão antigas ficam;
--  - os dados continuam a ser gravados em todas as lojas do dono (igual a antes);
--  - a resposta ('missing', 'self_certified_at') vem da loja mais antiga do dono, como o
--    parceiro_dados_fiscais() sem loja escolhida.
-- Os outros papéis (estafeta, limpeza, lavagem, serviços) ficam EXATAMENTE como estavam.
-- Não toca em dinheiro. Aplicar na JANELA 2.

-- 0. Cópia da definição de antes
create table if not exists public.bkp_fn_provider_update_legal_fields_20261028 as
  select now() as guardado_em,
         'public.provider_update_legal_fields(text,text,text,text,text,date,boolean)'::text as assinatura,
         pg_get_functiondef('public.provider_update_legal_fields(text,text,text,text,text,date,boolean)'::regprocedure) as definicao;
alter table public.bkp_fn_provider_update_legal_fields_20261028 enable row level security;

-- 1. Função nova (mesma assinatura)
create or replace function public.provider_update_legal_fields(
  p_role text,
  p_legal_name text default null::text,
  p_nif text default null::text,
  p_address text default null::text,
  p_iban text default null::text,
  p_birth_date date default null::date,
  p_self_certify boolean default false)
 returns jsonb
 language plpgsql
 security definer
 set search_path to 'public'
as $function$
DECLARE
  v_uid uuid := auth.uid();
  v_nif text := NULLIF(regexp_replace(COALESCE(p_nif, ''), '[^0-9]', '', 'g'), '');
  v_iban text := NULLIF(upper(regexp_replace(COALESCE(p_iban, ''), '\s', '', 'g')), '');
  v_nome text := NULLIF(btrim(COALESCE(p_legal_name, '')), '');
  v_morada text := NULLIF(btrim(COALESCE(p_address, '')), '');
  v_row jsonb;
  v_cert timestamptz;
BEGIN
  IF v_uid IS NULL THEN RAISE EXCEPTION 'unauthenticated' USING ERRCODE = '42501'; END IF;
  IF p_role NOT IN ('driver','partner','cleaner','washer','provider') THEN
    RAISE EXCEPTION 'invalid_role: %', p_role;
  END IF;
  IF v_nif IS NOT NULL AND v_nif !~ '^[0-9]{9}$' THEN RAISE EXCEPTION 'nif_invalido'; END IF;
  IF v_iban IS NOT NULL AND v_iban !~ '^PT[0-9]{23}$' THEN RAISE EXCEPTION 'iban_invalido'; END IF;
  IF p_birth_date IS NOT NULL AND p_birth_date > (current_date - interval '18 years') THEN
    RAISE EXCEPTION 'menor_de_idade';
  END IF;
  v_cert := CASE WHEN COALESCE(p_self_certify, false) THEN now() END;

  IF p_role = 'driver' THEN
    UPDATE public.drivers d SET
      legal_name = COALESCE(v_nome, d.legal_name), nif = COALESCE(v_nif, d.nif),
      address = COALESCE(v_morada, d.address), iban = COALESCE(v_iban, d.iban),
      birth_date = COALESCE(p_birth_date, d.birth_date),
      dsa_self_certified_at = COALESCE(v_cert, d.dsa_self_certified_at),
      dsa_self_cert_version = CASE WHEN v_cert IS NOT NULL THEN '2026-09-23' ELSE d.dsa_self_cert_version END
    WHERE d.user_id = v_uid OR d.id = v_uid
    RETURNING to_jsonb(d) INTO v_row;
  ELSIF p_role = 'partner' THEN
    -- F1 (28/10): carimbo só quando marca E (a loja ainda não tinha OU um dado fiscal dela muda).
    WITH alvo AS (
      SELECT x.id,
             (v_cert IS NOT NULL AND (
                  x.dsa_self_certified_at IS NULL
               OR (v_nome IS NOT NULL AND v_nome IS DISTINCT FROM NULLIF(btrim(COALESCE(x.legal_name, '')), ''))
               OR (v_nif IS NOT NULL AND v_nif IS DISTINCT FROM NULLIF(regexp_replace(COALESCE(x.nif, ''), '[^0-9]', '', 'g'), ''))
               OR (v_morada IS NOT NULL AND v_morada IS DISTINCT FROM NULLIF(btrim(COALESCE(x.address, '')), ''))
               OR (v_iban IS NOT NULL AND v_iban IS DISTINCT FROM NULLIF(upper(regexp_replace(COALESCE(x.iban, ''), '\s', '', 'g')), ''))
               OR (p_birth_date IS NOT NULL AND p_birth_date IS DISTINCT FROM x.birth_date))) AS carimbar
        FROM public.restaurants x
       WHERE x.user_id = v_uid OR x.user_ = v_uid),
    feito AS (
      UPDATE public.restaurants r SET
        legal_name = COALESCE(v_nome, r.legal_name), nif = COALESCE(v_nif, r.nif),
        address = COALESCE(v_morada, r.address), iban = COALESCE(v_iban, r.iban),
        birth_date = COALESCE(p_birth_date, r.birth_date),
        dsa_self_certified_at = CASE WHEN a.carimbar THEN v_cert ELSE r.dsa_self_certified_at END,
        dsa_self_cert_version = CASE WHEN a.carimbar THEN '2026-09-23' ELSE r.dsa_self_cert_version END
        FROM alvo a
       WHERE r.id = a.id
      RETURNING to_jsonb(r) AS j, r.created_at AS criada)
    SELECT f.j INTO v_row FROM feito f ORDER BY f.criada NULLS LAST LIMIT 1;
  ELSIF p_role = 'cleaner' THEN
    UPDATE public.cleaners c SET
      legal_name = COALESCE(v_nome, c.legal_name), nif = COALESCE(v_nif, c.nif),
      address = COALESCE(v_morada, c.address), iban = COALESCE(v_iban, c.iban),
      birth_date = COALESCE(p_birth_date, c.birth_date),
      dsa_self_certified_at = COALESCE(v_cert, c.dsa_self_certified_at),
      dsa_self_cert_version = CASE WHEN v_cert IS NOT NULL THEN '2026-09-23' ELSE c.dsa_self_cert_version END
    WHERE c.user_id = v_uid
    RETURNING to_jsonb(c) INTO v_row;
  ELSIF p_role = 'washer' THEN
    UPDATE public.washers w SET
      legal_name = COALESCE(v_nome, w.legal_name), nif = COALESCE(v_nif, w.nif),
      address = COALESCE(v_morada, w.address), iban = COALESCE(v_iban, w.iban),
      birth_date = COALESCE(p_birth_date, w.birth_date),
      dsa_self_certified_at = COALESCE(v_cert, w.dsa_self_certified_at),
      dsa_self_cert_version = CASE WHEN v_cert IS NOT NULL THEN '2026-09-23' ELSE w.dsa_self_cert_version END
    WHERE w.user_id = v_uid
    RETURNING to_jsonb(w) INTO v_row;
  ELSE
    UPDATE public.service_providers s SET
      legal_name = COALESCE(v_nome, s.legal_name), nif = COALESCE(v_nif, s.nif),
      address = COALESCE(v_morada, s.address), iban = COALESCE(v_iban, s.iban),
      birth_date = COALESCE(p_birth_date, s.birth_date),
      dsa_self_certified_at = COALESCE(v_cert, s.dsa_self_certified_at),
      dsa_self_cert_version = CASE WHEN v_cert IS NOT NULL THEN '2026-09-23' ELSE s.dsa_self_cert_version END
    WHERE s.user_id = v_uid
    RETURNING to_jsonb(s) INTO v_row;
  END IF;

  IF v_row IS NULL THEN
    RETURN jsonb_build_object('ok', false, 'role', p_role, 'error', 'registo_nao_encontrado',
                              'missing', to_jsonb(ARRAY['registo']));
  END IF;
  RETURN jsonb_build_object('ok', true, 'role', p_role,
                            'missing', to_jsonb(public._conformidade_em_falta(v_row)),
                            'self_certified_at', v_row->>'dsa_self_certified_at');
END;
$function$;

-- 2. Permissões iguais às de antes (chamada pela app com sessão; nunca anon)
revoke all on function public.provider_update_legal_fields(text,text,text,text,text,date,boolean) from public, anon;
grant execute on function public.provider_update_legal_fields(text,text,text,text,text,date,boolean) to authenticated, service_role;

-- PROVA ESPERADA (feita a 28/10 em transação desfeita, com a função nova criada como
-- _tmp_f1_provider_update_legal_fields e um dono de teste com DUAS lojas, a A com os dados iguais
-- aos enviados e a B com outra morada, as duas certificadas a 2026-01-01):
--   viva  (dono com 2 lojas)            -> erro "query returned more than one row" (nem grava)
--   nova, marcada, A sem mudança         -> A fica 2026-01-01 / versão antiga
--   nova, marcada, B com morada nova     -> B carimbada com a hora do pedido / versão 2026-09-23
--   nova, marcada outra vez, nada muda   -> A e B não mudam a data
--   nova, loja nunca certificada         -> carimbada (primeira autocertificação)
--   nova, NÃO marcada, NIF muda          -> data antiga fica (não carimba nem apaga)
-- Depois de aplicar, conferir:
--   select pg_get_functiondef('public.provider_update_legal_fields(text,text,text,text,text,date,boolean)'::regprocedure) ~ 'carimbar';  -- true
--   select count(*) from public.bkp_fn_provider_update_legal_fields_20261028;  -- 1
