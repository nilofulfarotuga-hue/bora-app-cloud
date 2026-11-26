-- =============================================================================
-- E-MAIL NOVO EM suporte@boraguarda.com = AVISO NO TELEMÓVEL DO ADMIN
-- (missão atendente-voz-2026-11-25, bloco B6)
--
-- O atendente de voz e o robô do suporte mandam escrever para suporte@boraguarda.com
-- (support_settings.support_email passou para este endereço a 25/11, cópia em
-- bkp_support_settings_20261125). Cada e-mail que ENTRA na caixa "suporte" passa a
-- gerar um aviso com push (notify_admin_urgent_push) que abre /admin/agentes-email.
-- E-mails de teste (assunto começado por "TESTE") só ficam no painel, sem push.
-- Zona verde: nada de dinheiro, pedidos ou RLS de tabelas protegidas.
-- =============================================================================

create or replace function public._agentes_email_suporte_aviso()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  if new.direcao is distinct from 'entrada' or new.agente is distinct from 'suporte' then
    return new;
  end if;
  if coalesce(new.assunto, '') ilike 'TESTE%' then
    insert into public.admin_notifications (event_type, severity, entity_type, entity_id, summary, payload, deep_link)
    values ('email_suporte', 'low', 'agentes_email', new.id::text,
            '[TESTE] E-mail em suporte@ · ' || left(coalesce(new.assunto, ''), 120),
            jsonb_build_object('email_id', new.id, 'teste', true), '/admin/agentes-email');
    return new;
  end if;
  begin
    perform public.notify_admin_urgent_push(
      'email_suporte',
      '✉️ E-mail em suporte@ · ' || left(coalesce(new.de, 'sem remetente'), 60) || E'\n' || left(coalesce(new.assunto, ''), 140),
      'agentes_email', new.id::text,
      jsonb_build_object('email_id', new.id, 'push_ref', 'email:' || new.id::text),
      '/admin/agentes-email');
  exception when others then
    raise notice '_agentes_email_suporte_aviso falhou: %', sqlerrm;
  end;
  return new;
end $$;

revoke all on function public._agentes_email_suporte_aviso() from public, anon, authenticated;

create trigger agentes_email_suporte_aviso
  after insert on public.agentes_email
  for each row execute function public._agentes_email_suporte_aviso();
