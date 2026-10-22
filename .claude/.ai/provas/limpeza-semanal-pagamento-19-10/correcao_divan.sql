-- Correção de dados da série semanal do Divan — corrida a 19/10/2026 ~08:41 UTC pelo MCP.
-- Autorização do Danilo (19/10/2026): "autorizo arrumar as limpezas semanais" + "Pode".
-- NÃO é migração (só dados). Cópia antes: public.bkp_cleaning_bookings_divan_20261019.

create table if not exists public.bkp_cleaning_bookings_divan_20261019 as
  select now() as bkp_em, b.* from public.cleaning_bookings b
  where b.id in ('df044ec2-f6b2-4ec9-93d8-b0394b332e25','e7cc0ba4-2bca-4c5f-a062-138152e04677');
alter table public.bkp_cleaning_bookings_divan_20261019 enable row level security;
revoke all on public.bkp_cleaning_bookings_divan_20261019 from anon, authenticated;

-- A de 26/10 08:45 (cópia errada do reagendamento de 17/10) volta ao dia da série.
update public.cleaning_bookings
set scheduled_at = ('2026-10-24 13:30'::timestamp AT TIME ZONE 'Europe/Lisbon'),
    status = 'scheduled', cleaner_id = null, accepted_at = null,
    offer_cleaner_id = null, offer_expires_at = null, offered_cleaner_ids = '{}',
    requested_cleaner_id = '8b4c0aa9-ca16-4bc1-b88f-a071a8468dd9',
    reminder_24h_sent_at = null, reminder_2h_sent_at = null
where id = 'df044ec2-f6b2-4ec9-93d8-b0394b332e25' and status = 'accepted' and payment_status = 'unpaid';

-- Aviso à profissional (igual ao que o admin_reschedule_cleaning faz).
select public._cleaning_notify_user(
  (select user_id from cleaners where id='8b4c0aa9-ca16-4bc1-b88f-a071a8468dd9'),
  'cleaning_rescheduled', 'Limpeza reagendada',
  'A limpeza de segunda 26/10 às 08:45 voltou ao dia habitual do cliente: sábado 24/10 às 13:30. Vais receber o pedido para a aceitar assim que o pagamento entrar.',
  'df044ec2-f6b2-4ec9-93d8-b0394b332e25');

-- Pedidos MB Way (a de hoje primeiro; o estado da de hoje NÃO se mexe).
select public.cleaning_request_payment('e7cc0ba4-2bca-4c5f-a062-138152e04677');
select public.cleaning_request_payment('df044ec2-f6b2-4ec9-93d8-b0394b332e25');

-- Aviso ao cliente.
select public._cleaning_notify_user('fee289f5-d74a-49ff-8c4a-a6eed22d9006', 'cleaning_rescheduled',
  'Pagamento MB Way da limpeza',
  'Enviámos-te 2 pedidos MB Way de 32,40 €: a limpeza de hoje (19/10) e a próxima, que voltou ao teu dia habitual — sábado 24/10 às 13:30. Aprova-os no telemóvel para confirmarmos a profissional.',
  'df044ec2-f6b2-4ec9-93d8-b0394b332e25');
