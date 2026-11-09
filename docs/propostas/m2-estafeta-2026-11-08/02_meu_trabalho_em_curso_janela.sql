-- PROPOSTA · missão m2-estafeta-conta-fila-2026-11-08 · 2/3
-- Aplicar em produção: Claude.ai. Depois: supabase/migrations/20261108200100_m2_trabalho_em_curso_janela.sql.
--
-- A faixa "Limpeza a decorrer — aceite — a caminho" ficou presa a 08/11 (18:20) no telemóvel do
-- Danilo. Causa provada por SELECT: meu_trabalho_em_curso devolvia QUALQUER marcação aceite, sem olhar
-- à data — a limpeza ae42a171 (accepted, marcada para 14/11 14:00) aparecia como "a caminho" dias
-- antes, e a faixa tapava o interruptor Online.
--
-- Agora:
--  · "a decorrer" = em curso (on_the_way/picked_up/in_progress/delivering) OU aceite com a hora
--    marcada até daqui a 3 h (scheduled_at <= now() + 3 h) e não mais velha do que ontem
--    (hoje-1 .. hoje+1 pela hora de Lisboa, para não ressuscitar marcações esquecidas);
--  · a resposta leva scheduled_at (a app já o lê);
--  · aceite para mais tarde vem em 'proxima' (sem 'tem'), para um cartão pequeno — nunca na faixa.
-- A app (lib/services/trabalho_em_curso.dart) já aplica a mesma janela de 3 h ao ler a hora
-- marcada da própria marcação; isto põe o servidor a dizer o mesmo.

create or replace function public.meu_trabalho_em_curso()
returns jsonb
language plpgsql
stable
security definer
set search_path to 'public', 'pg_temp'
as $$
declare
  v_uid uuid := auth.uid();
  v_id uuid;
  r record;
  v_hoje date := (now() at time zone 'Europe/Lisbon')::date;
  v_prox jsonb := null;
begin
  if v_uid is null then raise exception 'not_authenticated' using errcode = '42501'; end if;

  -- LAVAGEM primeiro: é a que prende a pessoa por mais tempo (leva o carro).
  select w.id into v_id from washers w where w.user_id = v_uid;
  if v_id is not null then
    select b.id, b.status, b.address_street, b.address_city, b.washer_earnings_cents, b.scheduled_at
      into r
      from carwash_bookings b
     where b.washer_id = v_id
       and (b.status in ('on_the_way','picked_up','in_progress','delivering')
            or (b.status = 'accepted'
                and b.scheduled_at <= now() + interval '3 hours'
                and (b.scheduled_at at time zone 'Europe/Lisbon')::date >= v_hoje - 1))
     order by b.scheduled_at
     limit 1;
    if found then
      return jsonb_build_object(
        'ok', true, 'tem', true, 'categoria', 'lavagem',
        'booking_id', r.id, 'estado', r.status, 'scheduled_at', r.scheduled_at,
        'morada', trim(both ', ' from coalesce(r.address_street,'') || ', ' || coalesce(r.address_city,'')),
        'ganho_cents', coalesce(r.washer_earnings_cents, 0));
    end if;
    select b.id, b.scheduled_at into r from carwash_bookings b
     where b.washer_id = v_id and b.status = 'accepted' and b.scheduled_at > now()
     order by b.scheduled_at limit 1;
    if found then
      v_prox := jsonb_build_object('categoria', 'lavagem', 'booking_id', r.id, 'scheduled_at', r.scheduled_at);
    end if;
  end if;

  select c.id into v_id from cleaners c where c.user_id = v_uid;
  if v_id is not null then
    select b.id, b.status, b.address_street, b.address_city, b.cleaner_earnings_cents, b.scheduled_at
      into r
      from cleaning_bookings b
     where b.cleaner_id = v_id
       and (b.status in ('on_the_way','in_progress')
            or (b.status = 'accepted'
                and b.scheduled_at <= now() + interval '3 hours'
                and (b.scheduled_at at time zone 'Europe/Lisbon')::date >= v_hoje - 1))
     order by b.scheduled_at
     limit 1;
    if found then
      return jsonb_build_object(
        'ok', true, 'tem', true, 'categoria', 'limpeza',
        'booking_id', r.id, 'estado', r.status, 'scheduled_at', r.scheduled_at,
        'morada', trim(both ', ' from coalesce(r.address_street,'') || ', ' || coalesce(r.address_city,'')),
        'ganho_cents', coalesce(r.cleaner_earnings_cents, 0));
    end if;
    if v_prox is null then
      select b.id, b.scheduled_at into r from cleaning_bookings b
       where b.cleaner_id = v_id and b.status = 'accepted' and b.scheduled_at > now()
       order by b.scheduled_at limit 1;
      if found then
        v_prox := jsonb_build_object('categoria', 'limpeza', 'booking_id', r.id, 'scheduled_at', r.scheduled_at);
      end if;
    end if;
  end if;

  return jsonb_build_object('ok', true, 'tem', false, 'proxima', v_prox);
end
$$;

-- (os grants da função já existem; create or replace mantém-nos)
