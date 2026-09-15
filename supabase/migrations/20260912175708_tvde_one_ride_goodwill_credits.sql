create table if not exists public.tvde_promo_credits (
  id uuid primary key default gen_random_uuid(),
  client_id uuid not null,
  amount_cents integer not null check (amount_cents > 0),
  reason text,
  source_key text not null unique,
  created_at timestamptz not null default now(),
  expires_at timestamptz,
  used_at timestamptz,
  used_ride_id uuid references public.tvde_rides(id) on delete set null
);

alter table public.tvde_promo_credits enable row level security;

drop policy if exists tvde_promo_credits_select_own on public.tvde_promo_credits;
create policy tvde_promo_credits_select_own
on public.tvde_promo_credits
for select
to authenticated
using ((select auth.uid()) = client_id);

alter table public.tvde_rides
  add column if not exists promo_credit_id uuid references public.tvde_promo_credits(id) on delete set null,
  add column if not exists promo_credit_applied_cents integer not null default 0;

create or replace function public.fn_tvde_apply_promo_credit()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_credit public.tvde_promo_credits%rowtype;
  v_discount integer;
begin
  if new.client_id is null or coalesce(new.est_fare_cents, 0) <= 0 then
    return new;
  end if;

  select * into v_credit
  from public.tvde_promo_credits
  where client_id = new.client_id
    and used_at is null
    and (expires_at is null or expires_at > now())
  order by created_at asc
  for update skip locked
  limit 1;

  if not found then
    return new;
  end if;

  v_discount := least(v_credit.amount_cents, new.est_fare_cents);
  if v_discount <= 0 then
    return new;
  end if;

  new.est_fare_cents := new.est_fare_cents - v_discount;
  new.bora_cut_cents := coalesce(new.bora_cut_cents, 0) - v_discount;
  new.promo_credit_id := v_credit.id;
  new.promo_credit_applied_cents := v_discount;

  update public.tvde_promo_credits
  set used_at = now(), used_ride_id = new.id
  where id = v_credit.id;

  return new;
end;
$$;

drop trigger if exists trg_tvde_apply_promo_credit on public.tvde_rides;
create trigger trg_tvde_apply_promo_credit
before insert on public.tvde_rides
for each row
execute function public.fn_tvde_apply_promo_credit();

create or replace function public.fn_tvde_restore_promo_credit_on_cancel()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if new.status in ('cancelada_cliente','cancelada_motorista','no_show')
     and old.status is distinct from new.status
     and new.promo_credit_id is not null then
    update public.tvde_promo_credits
    set used_at = null, used_ride_id = null
    where id = new.promo_credit_id
      and used_ride_id = new.id;
  end if;
  return new;
end;
$$;

drop trigger if exists trg_tvde_restore_promo_credit_on_cancel on public.tvde_rides;
create trigger trg_tvde_restore_promo_credit_on_cancel
after update of status on public.tvde_rides
for each row
execute function public.fn_tvde_restore_promo_credit_on_cancel();
