-- Texto aplicado em produção a 15/11/2026 (versão 20261115185158, pela Claude.ai, por carregador com sha256
-- 651b4965cd98e481daabe4b1ab6987af1d3adbcfd858ed2967088137f0acf46b); igual a docs/propostas/fechar-tudo-15-11/reservas_insert_e_delete_FINAL.sql.

-- FINAL do Juiz da Claude.ai (15/11 ~19:20). Reservas: recusa INSERT e DELETE de cliente/anon nao-admin,
-- trg_00 passa a proteger id, people e reserved_for (sem excecao do PI: as Edges v27/v18 escrevem como servidor).
-- Aplicar so depois de create-reservation-payment-intent v27 e create-mbway-reservation-payment-intent v18 no ar.
begin;
create or replace function public._reservas_cliente_insert_protegido()
 returns trigger language plpgsql set search_path to 'public'
as $function$
begin
  if current_user in ('authenticated','anon') and not coalesce(public.is_admin(), false) then
    raise exception 'reserva_campo_protegido: as reservas so se criam pelas funcoes do servidor (create-reservation-payment-intent)'
      using errcode = '42501';
  end if;
  return new;
end
$function$;
revoke all on function public._reservas_cliente_insert_protegido() from public, anon, authenticated;
drop trigger if exists trg_00_reservas_insert_protegido on public.reservations;
create trigger trg_00_reservas_insert_protegido before insert on public.reservations
  for each row execute function public._reservas_cliente_insert_protegido();

create or replace function public._reservas_cliente_campos_protegidos()
 returns trigger language plpgsql set search_path to 'public'
as $function$
begin
  if current_user in ('authenticated','anon') and not coalesce(public.is_admin(), false) then
    if new.id is distinct from old.id
    or new.status is distinct from old.status
    or new.people is distinct from old.people
    or new.reserved_for is distinct from old.reserved_for
    or new.prepayment_cents is distinct from old.prepayment_cents
    or new.prepayment_pi is distinct from old.prepayment_pi
    or new.stripe_account is distinct from old.stripe_account
    or new.restaurant_id is distinct from old.restaurant_id
    or new.client_user_id is distinct from old.client_user_id
    or new.decided_at is distinct from old.decided_at
    or new.arrived_at is distinct from old.arrived_at
    or new.cancelled_at is distinct from old.cancelled_at
    or new.cancel_reason is distinct from old.cancel_reason
    or new.seated_at is distinct from old.seated_at
    or new.finished_at is distinct from old.finished_at
    or new.is_walk_in is distinct from old.is_walk_in
    or new.floor_plan_id is distinct from old.floor_plan_id
    or new.reminder_24h_sent_at is distinct from old.reminder_24h_sent_at
    or new.reminder_2h_sent_at is distinct from old.reminder_2h_sent_at
    or new.confirmation_sent_at is distinct from old.confirmation_sent_at
    or new.created_at is distinct from old.created_at
    then
      raise exception 'reserva_campo_protegido: este campo so muda pelas funcoes do servidor (ex.: client_cancel_reservation)'
        using errcode = '42501';
    end if;
  end if;
  return new;
end
$function$;
revoke all on function public._reservas_cliente_campos_protegidos() from public, anon, authenticated;

revoke delete, truncate on public.reservations from anon, authenticated;
commit;
