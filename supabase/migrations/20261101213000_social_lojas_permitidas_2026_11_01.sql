-- Robô das redes (VPS) publicava lojas "em breve" nas stories (ordem do Danilo 01/11/2026 19:56:
-- "Robô da Story está publicando lojas em breve. Conserta isso."). O robô vive na VPS; o patch dos
-- scripts está em docs/propostas/stories-em-breve-2026-11-01.md. Aqui fica a REGRA ÚNICA do lado
-- do banco: uma RPC de leitura que devolve só as lojas que podem aparecer numa peça de divulgação.
--
-- Pode sair: coming_soon = false · is_active_admin = true · approval_status = 'approved' ·
-- não é demo · (restaurants) tem pelo menos 1 produto disponível.
-- Aberta a anon DE PROPÓSITO (CLAUDE.md §5): o robô da VPS usa a chave anónima; devolve só id,
-- nome, categoria, tipo, is_partner e a contagem de produtos — nada que não seja público na app.

create or replace function public.social_lojas_permitidas()
returns table (
  id text,
  nome text,
  tipo text,
  categoria text,
  is_partner boolean,
  produtos_disponiveis bigint
)
language sql
stable
security definer
set search_path = public
as $$
  select r.id::text,
         r.name,
         'restaurant'::text,
         r.category::text,
         coalesce(r.is_partner, false),
         (select count(*) from public.products p
           where p.restaurant_id = r.id and coalesce(p.is_available, true))
    from public.restaurants r
   where coalesce(r.coming_soon, false) = false
     and coalesce(r.is_active_admin, true) = true
     and r.approval_status = 'approved'
     and r.id::text not like 'demo-%'
     and r.name not ilike '%demo%'
     and exists (select 1 from public.products p
                  where p.restaurant_id = r.id and coalesce(p.is_available, true))
  union all
  select s.id::text,
         s.name,
         'service_provider'::text,
         null::text,
         true,
         0::bigint
    from public.service_providers s
   where coalesce(s.coming_soon, false) = false
     and coalesce(s.is_active_admin, true) = true
     and s.approval_status = 'approved'
     and s.name not ilike '%demo%'
  order by 3, 2;
$$;

comment on function public.social_lojas_permitidas() is
  'Lojas que podem aparecer em stories/posts do robô das redes: abertas, ativas, aprovadas, sem coming_soon, não demo, com produtos disponíveis. Leitura só; aberta a anon porque o robô da VPS usa a chave anónima (01/11/2026).';

revoke all on function public.social_lojas_permitidas() from public;
grant execute on function public.social_lojas_permitidas() to anon, authenticated, service_role;
