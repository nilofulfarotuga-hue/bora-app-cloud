-- Assistente de Negocio: as rotinas marcam "lembrete/avaliacao enviados" por funcao propria
-- (regra da casa: nada de UPDATE directo em appointments). So mexe em marcacoes do assistente.
create or replace function public.assistente_aviso_enviado(p_appointment_id uuid, p_tipo text)
returns boolean
language plpgsql security definer set search_path to 'public'
as $$
declare v_n int;
begin
  if p_tipo = 'lembrete' then
    update appointments set assistant_reminder_sent_at = now()
     where id = p_appointment_id and assistant_tenant_id is not null and assistant_reminder_sent_at is null;
  elsif p_tipo = 'avaliacao' then
    update appointments set assistant_review_sent_at = now()
     where id = p_appointment_id and assistant_tenant_id is not null and assistant_review_sent_at is null;
  else
    raise exception 'tipo_invalido';
  end if;
  get diagnostics v_n = row_count;
  return v_n > 0;
end $$;
revoke all on function public.assistente_aviso_enviado(uuid, text) from public, anon, authenticated;
grant execute on function public.assistente_aviso_enviado(uuid, text) to service_role;
