-- Robô do Jai: o aviso "TESTE robô do Jai — ignora" (prova da instalação) não conta para a quota de 1 aviso por 20 h
-- nem para as 3 emergências por 24 h. Sem isto, a prova da instalação trava o primeiro aviso real durante 20 h.
-- Só muda as duas contagens; o resto da função fica igual à 20261123071500_jai_robo_portas.sql.
create or replace function public.jai_robo_aviso_urgente(p_chave text, p_texto text, p_emergencia boolean default false)
returns uuid
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v_id uuid;
  v_teste boolean := coalesce(p_texto, '') like 'TESTE robô do Jai%';
begin
  if not public._jai_robo_chave_ok(p_chave) then
    raise exception 'jai_robo: chave invalida' using errcode = '28000';
  end if;
  if p_texto is null or length(btrim(p_texto)) = 0 or length(p_texto) > 400 then
    raise exception 'jai_robo: texto vazio ou maior que 400';
  end if;
  if not v_teste and not coalesce(p_emergencia, false) and exists (
       select 1 from public.jai_robo_avisos where criado_em > now() - interval '20 hours' and not teste) then
    return null;
  end if;
  if not v_teste and coalesce(p_emergencia, false) and (
       select count(*) from public.jai_robo_avisos where criado_em > now() - interval '24 hours' and not teste) >= 3 then
    return null;
  end if;
  -- o próprio teste: no máximo 1 por hora (correr o lançador duas vezes seguidas não manda dois)
  if v_teste and exists (select 1 from public.jai_robo_avisos where teste and criado_em > now() - interval '1 hour') then
    return null;
  end if;
  v_id := public.notify_admin_urgent_push(
    'jai_robo',
    'Robô do Jai' || E'\n' || btrim(p_texto),
    'jai_robo',
    'jai-robo',
    jsonb_build_object('origem', 'robo-jai', 'push_ref', 'jai-robo'),
    '/admin'
  );
  insert into public.jai_robo_avisos (texto, teste, emergencia, admin_event)
  values (btrim(p_texto), v_teste, coalesce(p_emergencia, false), v_id);
  return v_id;
end;
$$;
revoke all on function public.jai_robo_aviso_urgente(text, text, boolean) from public;
grant execute on function public.jai_robo_aviso_urgente(text, text, boolean) to anon, authenticated;
