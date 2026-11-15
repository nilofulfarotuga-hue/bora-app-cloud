-- 15/11/2026 Claude.ai, autorizado pelo Danilo 16:06 ("Pode trancar"): a regra reservations_client_owner (ALL)
-- deixava o cliente mudar por escrita direta o estado, o pre-pagamento, as horas de chegada/sentado/fim etc.
-- Agora a escrita DIRETA do cliente (papel authenticated/anon, fora das funcoes do servidor) so muda campos
-- inofensivos (nome, telefone, pessoas, hora, notas, pedidos especiais, ocasiao, tipo de evento).
-- Funcoes do servidor (SECURITY DEFINER, dono postgres) e Edges (service_role) continuam iguais.
create or replace function public._reservas_cliente_campos_protegidos()
returns trigger
language plpgsql
security invoker
set search_path to 'public'
as $fn$
begin
  if current_user in ('authenticated', 'anon') and not coalesce(public.is_admin(), false) then
    if new.status               is distinct from old.status
    or new.prepayment_cents     is distinct from old.prepayment_cents
    or new.prepayment_pi        is distinct from old.prepayment_pi
    or new.stripe_account       is distinct from old.stripe_account
    or new.restaurant_id        is distinct from old.restaurant_id
    or new.client_user_id       is distinct from old.client_user_id
    or new.decided_at           is distinct from old.decided_at
    or new.arrived_at           is distinct from old.arrived_at
    or new.cancelled_at         is distinct from old.cancelled_at
    or new.cancel_reason        is distinct from old.cancel_reason
    or new.seated_at            is distinct from old.seated_at
    or new.finished_at          is distinct from old.finished_at
    or new.is_walk_in           is distinct from old.is_walk_in
    or new.floor_plan_id        is distinct from old.floor_plan_id
    or new.reminder_24h_sent_at is distinct from old.reminder_24h_sent_at
    or new.reminder_2h_sent_at  is distinct from old.reminder_2h_sent_at
    or new.confirmation_sent_at is distinct from old.confirmation_sent_at
    or new.created_at           is distinct from old.created_at
    then
      raise exception 'reserva_campo_protegido: este campo so muda pelas funcoes do servidor (ex.: client_cancel_reservation)'
        using errcode = '42501';
    end if;
  end if;
  return new;
end
$fn$;

revoke all on function public._reservas_cliente_campos_protegidos() from public, anon, authenticated;

create trigger trg_00_reservas_campos_protegidos
  before update on public.reservations
  for each row execute function public._reservas_cliente_campos_protegidos();
