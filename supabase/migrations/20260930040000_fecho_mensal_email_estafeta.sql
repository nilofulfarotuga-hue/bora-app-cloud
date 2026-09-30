-- 30/09 (pedido do Danilo): o resumo do recibo verde do mês também vai por email a cada estafeta.
-- Aplicada por MCP a 30/09/2026. O envio está na Edge Function monthly-partner-statement v2
-- (mesmo cron do dia 1 às 09h; só a partir do mês de outubro de 2026).
create table if not exists public.driver_monthly_statement_log (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null,
  ano int not null,
  mes int not null,
  email_to text,
  email_status text,
  email_error text,
  sent_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (user_id, ano, mes)
);
alter table public.driver_monthly_statement_log enable row level security;
drop policy if exists admin_le_driver_monthly_statement_log on public.driver_monthly_statement_log;
create policy admin_le_driver_monthly_statement_log on public.driver_monthly_statement_log
  for select using (public.is_admin());

create or replace function public.driver_monthly_statement_email(p_user_id text)
returns text language sql stable security definer set search_path to 'public' as $$
  select coalesce(nullif(trim(d.email),''), u.email)
    from auth.users u left join public.drivers d on d.user_id = u.id
   where u.id::text = p_user_id limit 1;
$$;
revoke all on function public.driver_monthly_statement_email(text) from public, anon, authenticated;
