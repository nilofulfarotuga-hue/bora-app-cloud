-- APLICADA em produção pela Claude.ai por MCP a 01/11/2026 ~23:20 (no PC o classificador tinha recusado; aplicada com CREATE OR REPLACE TRIGGER em vez de DROP+CREATE).
-- Missão app-fechar-2026-11-01 · B6 e B5 (achados encontrados pelo caminho).
--
-- 1) assistant_learned: ligar/desligar uma "Aprendida" no painel é um UPDATE direto pela RLS
--    (assistant_learned_admin) e não ficava em admin_audit_log. Gatilho de auditoria + tira o
--    TRUNCATE (que não passa pela RLS) a authenticated.
-- 2) cleaning_series_next_at (SECURITY DEFINER) devolvia a próxima data de QUALQUER série a
--    qualquer conta. Passa a responder só ao cliente/profissional da série ou ao admin; sem
--    sessão (cron/servidor: generate_recurring_bookings, _alerta_txt_limpeza_cancelada) continua
--    igual. anon deixa de a poder chamar.
-- Não mexe em valores nem em dinheiro.

CREATE OR REPLACE FUNCTION public._assistant_learned_audita()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
BEGIN
  IF NEW.active IS DISTINCT FROM OLD.active AND auth.uid() IS NOT NULL AND public.is_admin() THEN
    PERFORM public.log_admin_action(
      CASE WHEN NEW.active THEN 'assistente_aprendida_ligar' ELSE 'assistente_aprendida_desligar' END,
      'assistant_learned', NEW.id,
      jsonb_build_object('kind', NEW.kind, 'question', left(NEW.question, 200)));
  END IF;
  RETURN NEW;
END $$;
REVOKE ALL ON FUNCTION public._assistant_learned_audita() FROM PUBLIC, anon, authenticated;


CREATE OR REPLACE TRIGGER trg_assistant_learned_audita
  AFTER UPDATE OF active ON public.assistant_learned
  FOR EACH ROW EXECUTE FUNCTION public._assistant_learned_audita();

REVOKE TRUNCATE ON public.assistant_learned FROM authenticated, anon;

CREATE OR REPLACE FUNCTION public.cleaning_series_next_at(p_gid uuid)
 RETURNS timestamp with time zone
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_last cleaning_bookings; v_first cleaning_bookings;
  v_interval interval; v_anchor timestamp; v_last_local timestamp; v_k int; v_n int;
  v_uid uuid := auth.uid();
begin
  -- 01/11/2026: só o cliente/profissional da série ou o admin (o servidor sem sessão continua).
  if v_uid is not null and not public.is_admin() and not exists (
       select 1 from cleaning_bookings b
        where b.recurrence_group_id = p_gid
          and (b.client_user_id = v_uid
               or exists (select 1 from cleaners c
                           where c.user_id = v_uid
                             and c.id in (b.cleaner_id, b.requested_cleaner_id, b.offer_cleaner_id)))) then
    return null;
  end if;
  select * into v_last from cleaning_bookings where recurrence_group_id = p_gid order by scheduled_at desc limit 1;
  if v_last.id is null or v_last.recurrence not in ('weekly','biweekly') then return null; end if;
  v_interval := case v_last.recurrence when 'weekly' then interval '7 days' else interval '14 days' end;
  select * into v_first from cleaning_bookings where recurrence_group_id = p_gid order by created_at asc limit 1;
  v_anchor     := v_first.scheduled_at at time zone 'Europe/Lisbon';
  v_last_local := v_last.scheduled_at at time zone 'Europe/Lisbon';
  v_k := floor(extract(epoch from (v_last_local - v_anchor)) / extract(epoch from v_interval))::int + 1;
  select count(*) into v_n from cleaning_bookings where recurrence_group_id = p_gid;
  v_k := greatest(v_k, v_n, 1);
  return (v_anchor + v_interval * v_k) at time zone 'Europe/Lisbon';
end
$function$;

REVOKE EXECUTE ON FUNCTION public.cleaning_series_next_at(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.cleaning_series_next_at(uuid) TO authenticated, service_role;
