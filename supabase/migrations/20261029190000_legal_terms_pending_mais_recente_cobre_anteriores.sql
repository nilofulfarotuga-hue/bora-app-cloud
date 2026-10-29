-- 2026-10-29 — legal_terms_pending: aceitar a versão mais recente cobre as anteriores.
--
-- Antes: devolvia a versão mais recente POR ACEITAR (ORDER BY effective_date DESC LIMIT 1 com um
-- NOT EXISTS por versão). Quem aceitava a de 2026-11-01 via logo a de 2026-10-01 por aceitar
-- (auditoria no emulador, 29/10, passo 7.9-so-reportar).
-- Agora: devolve a versão mais recente do público, e só se o utilizador não tiver aceitado essa
-- nem nenhuma com effective_date igual ou posterior. Mesma assinatura, mesma forma do JSON (a linha
-- inteira de legal_terms_versions), mesmos grants (create or replace mantém a ACL).
-- Backup da função antiga: public.bkp_fn_legal_terms_pending_20261029 (RLS ligada, fechada a anon).

create table if not exists public.bkp_fn_legal_terms_pending_20261029 as
  select now() as guardado_em,
         p.proname::text as nome,
         pg_get_function_identity_arguments(p.oid) as args,
         md5(pg_get_functiondef(p.oid)) as md5,
         pg_get_functiondef(p.oid) as definicao
    from pg_proc p
    join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'public' and p.proname = 'legal_terms_pending';
alter table public.bkp_fn_legal_terms_pending_20261029 enable row level security;
revoke all on public.bkp_fn_legal_terms_pending_20261029 from anon, authenticated;

create or replace function public.legal_terms_pending(p_audience text)
 returns jsonb
 language sql
 stable security definer
 set search_path to 'public'
as $function$
  with ultima as (
    select v.*
      from public.legal_terms_versions v
     where v.audience = p_audience
     order by v.effective_date desc, v.created_at desc
     limit 1
  )
  select to_jsonb(u)
    from ultima u
   where auth.uid() is not null
     and not exists (
       select 1
         from public.legal_terms_acceptances a
         join public.legal_terms_versions va
           on va.audience = a.audience and va.version = a.version
        where a.user_id = auth.uid()
          and a.audience = u.audience
          and va.effective_date >= u.effective_date
     );
$function$;
