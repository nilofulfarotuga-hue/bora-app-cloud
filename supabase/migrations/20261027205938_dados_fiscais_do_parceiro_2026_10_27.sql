-- Dados fiscais do PARCEIRO depois do registo (DAC7, Lei n.º 36/2023).
-- Missão boom-burger-2026-10-27, adendo 3, passo F3 (Claude Code, 27/10/2026).
-- O portão trg_conformidade_abrir_loja_parceira não deixa abrir uma loja parceira sem nome legal, NIF, morada,
-- IBAN PT, data de nascimento (só pessoa singular) e autocertificação. Até hoje só o registo novo os pedia.
--  1. parceiro_dados_fiscais(loja): o dono (a sua loja) ou o admin (qualquer loja) lê os dados e o que falta
--     ('em_falta', a mesma lista do portão). O parceiro grava pelo provider_update_legal_fields('partner', ...).
--  2. admin_parceiro_atualizar_dados_fiscais(...): o admin corrige os dados de uma loja, incluindo a data e a
--     versão da autocertificação recebida por escrito. Fica no admin_audit_log só QUE campos mudaram (sem valores).

create or replace function public.parceiro_dados_fiscais(p_restaurant_id text default null)
 returns jsonb
 language plpgsql
 stable security definer
 set search_path to 'public'
as $function$
declare
  v_uid uuid := auth.uid();
  r public.restaurants;
begin
  if v_uid is null then raise exception 'unauthenticated' using errcode = '42501'; end if;
  if p_restaurant_id is null then
    select x.* into r from public.restaurants x
     where (x.user_id = v_uid or x.user_ = v_uid) and coalesce(x.is_partner, false)
     order by x.created_at limit 1;
  else
    select x.* into r from public.restaurants x where x.id::text = p_restaurant_id;
  end if;
  if r.id is null then raise exception 'loja_nao_encontrada'; end if;
  if not public.is_admin() and r.user_id is distinct from v_uid and r.user_ is distinct from v_uid then
    raise exception 'sem_permissao' using errcode = '42501';
  end if;
  return jsonb_build_object(
    'restaurant_id', r.id, 'loja', r.name, 'legal_name', r.legal_name, 'nif', r.nif, 'address', r.address,
    'iban', r.iban, 'birth_date', r.birth_date,
    'dsa_self_certified_at', r.dsa_self_certified_at, 'dsa_self_cert_version', r.dsa_self_cert_version,
    'empresa', regexp_replace(coalesce(r.nif, ''), '[^0-9]', '', 'g') ~ '^[5679][0-9]{8}$',
    'em_falta', to_jsonb(public._conformidade_em_falta(to_jsonb(r))));
end
$function$;

create or replace function public.admin_parceiro_atualizar_dados_fiscais(
  p_restaurant_id text,
  p_legal_name text default null,
  p_nif text default null,
  p_address text default null,
  p_iban text default null,
  p_birth_date date default null,
  p_autocertificado_em timestamptz default null,
  p_autocert_versao text default null,
  p_motivo text default null)
 returns jsonb
 language plpgsql
 security definer
 set search_path to 'public'
as $function$
declare
  v_nif    text := nullif(regexp_replace(coalesce(p_nif, ''), '[^0-9]', '', 'g'), '');
  v_iban   text := nullif(upper(regexp_replace(coalesce(p_iban, ''), '\s', '', 'g')), '');
  v_nome   text := nullif(btrim(coalesce(p_legal_name, '')), '');
  v_morada text := nullif(btrim(coalesce(p_address, '')), '');
  v_row    jsonb;
  v_campos text[];
begin
  if not public.is_admin() then raise exception 'admin_required' using errcode = '42501'; end if;
  if v_nif is not null and v_nif !~ '^[0-9]{9}$' then raise exception 'nif_invalido'; end if;
  if v_iban is not null and v_iban !~ '^PT[0-9]{23}$' then raise exception 'iban_invalido'; end if;
  if p_birth_date is not null and p_birth_date > (current_date - interval '18 years') then
    raise exception 'menor_de_idade';
  end if;
  if p_autocertificado_em is not null and p_autocertificado_em > now() + interval '1 day' then
    raise exception 'autocertificacao_no_futuro';
  end if;
  v_campos := array_remove(array[
    case when v_nome is not null then 'nome' end, case when v_nif is not null then 'nif' end,
    case when v_morada is not null then 'morada' end, case when v_iban is not null then 'iban' end,
    case when p_birth_date is not null then 'data_nascimento' end,
    case when p_autocertificado_em is not null then 'autocertificacao' end], null);

  update public.restaurants r set
    legal_name = coalesce(v_nome, r.legal_name), nif = coalesce(v_nif, r.nif),
    address = coalesce(v_morada, r.address), iban = coalesce(v_iban, r.iban),
    birth_date = coalesce(p_birth_date, r.birth_date),
    dsa_self_certified_at = coalesce(p_autocertificado_em, r.dsa_self_certified_at),
    dsa_self_cert_version = case when p_autocertificado_em is not null
                                 then coalesce(nullif(btrim(coalesce(p_autocert_versao, '')), ''), '2026-09-23')
                                 else r.dsa_self_cert_version end
   where r.id::text = p_restaurant_id
  returning to_jsonb(r) into v_row;
  if v_row is null then raise exception 'loja_nao_encontrada'; end if;

  perform public.log_admin_action('parceiro_dados_fiscais'::text, 'restaurant'::text, p_restaurant_id::text,
    jsonb_build_object('campos', to_jsonb(v_campos), 'motivo', nullif(btrim(coalesce(p_motivo, '')), '')));
  return jsonb_build_object('ok', true, 'campos', to_jsonb(v_campos),
                            'em_falta', to_jsonb(public._conformidade_em_falta(v_row)));
end
$function$;

revoke all on function public.parceiro_dados_fiscais(text) from public, anon;
revoke all on function public.admin_parceiro_atualizar_dados_fiscais(text, text, text, text, text, date, timestamptz, text, text) from public, anon;
grant execute on function public.parceiro_dados_fiscais(text) to authenticated;
grant execute on function public.admin_parceiro_atualizar_dados_fiscais(text, text, text, text, text, date, timestamptz, text, text) to authenticated;
