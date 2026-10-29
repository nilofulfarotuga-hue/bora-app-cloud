-- F3 (missao-geral-2026-10-28, Bloco 3): os Termos do Parceiro (versão 2026-10-28) só se pedem a
-- donos de lojas de COMIDA ou MERCADO que já estão APROVADAS.
--
-- O que estava (definições vivas lidas a 28/10):
--   legal_terms_pending('parceiro') devolvia a versão a QUALQUER conta com sessão que ainda não a
--   aceitou — também a donos de serviços (barbearias, beleza) e a lojas ainda por aprovar.
--   admin_parceiros_termos() listava todas as lojas parceiras aprovadas, também as de beleza.
-- Agora:
--   _categoria_com_termos_parceiro(category, extra_categories): true para restaurant, sobremesa,
--     festas e supermarket (na categoria principal ou nas extra). Igual à lista da app
--     (lib/widgets/terms_gate.dart, kCategoriasComTermosDoParceiro).
--   _termos_parceiro_aplicam(uid): o utilizador é dono (user_id ou user_) de pelo menos uma loja
--     is_partner, approval_status = 'approved' e com categoria de comida/mercado.
--   legal_terms_pending: para o público 'parceiro' só devolve a versão quando _termos_parceiro_aplicam.
--     Cliente e estafeta: exatamente igual.
--   admin_parceiros_termos: a lista do painel passa a ter só as mesmas lojas.
-- Os serviços (service_providers e lojas de beleza) ficam sem termos até haver texto próprio para
-- eles (público novo em legal_terms_versions) — só reportado, nada criado aqui.
-- Não toca em dinheiro. Aplicar na JANELA 2.

-- 0. Cópias das definições de antes
create table if not exists public.bkp_fn_legal_terms_pending_20261028 as
  select now() as guardado_em,
         'public.legal_terms_pending(text)'::text as assinatura,
         pg_get_functiondef('public.legal_terms_pending(text)'::regprocedure) as definicao;
alter table public.bkp_fn_legal_terms_pending_20261028 enable row level security;

create table if not exists public.bkp_fn_admin_parceiros_termos_20261028 as
  select now() as guardado_em,
         'public.admin_parceiros_termos()'::text as assinatura,
         pg_get_functiondef('public.admin_parceiros_termos()'::regprocedure) as definicao;
alter table public.bkp_fn_admin_parceiros_termos_20261028 enable row level security;

-- 1. Quem vende comida ou mercado
create or replace function public._categoria_com_termos_parceiro(p_category text, p_extra text[])
 returns boolean
 language sql
 immutable
as $function$
  SELECT COALESCE(p_category, '') = ANY (ARRAY['restaurant','sobremesa','festas','supermarket'])
      OR COALESCE(p_extra, '{}'::text[]) && ARRAY['restaurant','sobremesa','festas','supermarket'];
$function$;
revoke all on function public._categoria_com_termos_parceiro(text, text[]) from public, anon, authenticated;

-- 2. Este utilizador tem de aceitar os termos do parceiro?
create or replace function public._termos_parceiro_aplicam(p_uid uuid)
 returns boolean
 language sql
 stable
 security definer
 set search_path to 'public'
as $function$
  SELECT p_uid IS NOT NULL AND EXISTS (
    SELECT 1 FROM public.restaurants r
     WHERE (r.user_id = p_uid OR r.user_ = p_uid)
       AND COALESCE(r.is_partner, false)
       AND r.approval_status = 'approved'
       AND public._categoria_com_termos_parceiro(r.category, r.extra_categories));
$function$;
revoke all on function public._termos_parceiro_aplicam(uuid) from public, anon, authenticated;

-- 3. legal_terms_pending (mesma assinatura; cliente e estafeta iguais)
create or replace function public.legal_terms_pending(p_audience text)
 returns jsonb
 language sql
 stable security definer
 set search_path to 'public'
as $function$
  SELECT to_jsonb(v) FROM public.legal_terms_versions v
   WHERE v.audience = p_audience AND auth.uid() IS NOT NULL
     AND (p_audience <> 'parceiro' OR public._termos_parceiro_aplicam(auth.uid()))
     AND NOT EXISTS (SELECT 1 FROM public.legal_terms_acceptances a
                      WHERE a.user_id = auth.uid() AND a.audience = v.audience AND a.version = v.version)
   ORDER BY v.effective_date DESC, v.created_at DESC
   LIMIT 1;
$function$;
revoke all on function public.legal_terms_pending(text) from public, anon;
grant execute on function public.legal_terms_pending(text) to authenticated, service_role;

-- 4. admin_parceiros_termos (mesma assinatura e colunas; só o filtro da categoria é novo)
create or replace function public.admin_parceiros_termos()
 returns table (restaurant_id text, loja text, user_id uuid, email text, versao_atual text,
                versao_aceite text, aceite_em timestamptz, via text, nota text)
 language plpgsql
 stable security definer
 set search_path to 'public'
as $function$
begin
  if not public.is_admin() then raise exception 'admin_required' using errcode = '42501'; end if;
  return query
  with v as (
    select t.version from public.legal_terms_versions t
     where t.audience = 'parceiro' order by t.effective_date desc, t.created_at desc limit 1)
  select r.id::text, r.name, coalesce(r.user_id, r.user_), u.email::text, (select v.version from v),
         a.version, a.accepted_at, a.platform, a.nota
    from public.restaurants r
    left join auth.users u on u.id = coalesce(r.user_id, r.user_)
    left join lateral (
      select x.version, x.accepted_at, x.platform, x.nota from public.legal_terms_acceptances x
       where x.user_id = coalesce(r.user_id, r.user_) and x.audience = 'parceiro'
       order by x.accepted_at desc limit 1) a on true
   where coalesce(r.is_partner, false) and r.approval_status = 'approved'
     and public._categoria_com_termos_parceiro(r.category, r.extra_categories)
   order by r.name;
end
$function$;
revoke all on function public.admin_parceiros_termos() from public, anon;
grant execute on function public.admin_parceiros_termos() to authenticated, service_role;

-- PROVA ESPERADA (feita a 28/10 em transação desfeita, com as funções novas criadas com o prefixo
-- _tmp_f3_ e comparadas com a legal_terms_pending viva, cada dono com a sua sessão simulada):
--   dono de restaurante parceiro aprovado          viva: versão 2026-10-28   nova: versão 2026-10-28
--   dono de loja de beleza parceira aprovada       viva: versão 2026-10-28   nova: null
--   dono de serviços (service_providers)           viva: versão 2026-10-28   nova: null
--   o mesmo restaurante posto 'pending'            viva: versão 2026-10-28   nova: null
--   cliente / estafeta                             viva e nova iguais
--   admin_parceiros_termos: 6 lojas -> 5 (sai a de beleza)
-- Depois de aplicar, conferir:
--   select count(*) from public.admin_parceiros_termos();   -- (como admin) 5
--   select has_function_privilege('authenticated', 'public._termos_parceiro_aplicam(uuid)', 'execute');  -- false
