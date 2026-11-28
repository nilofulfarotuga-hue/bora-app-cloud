-- Aplicada em produção pela Claude.ai por MCP a 28/11/2026 16:03 (autorizado pelo Danilo às 16:02).
-- O recalculo completo das sugestoes da lupa leva ~90 s e pôs o servidor a 60,8% às 15:53 (vigia-servidor).
-- Antes corria de hora a hora.
-- 1) cron: só de madrugada (03h-05h59 Lisboa), 1 vez por dia, ou se nunca correu.
create or replace function public.lupa_sugestoes_cron()
 returns void
 language plpgsql
 security definer
 set search_path to 'public', 'pg_temp'
as $function$
declare
  v_e    public.lupa_sugestoes_estado;
  v_hora integer := extract(hour from (now() at time zone 'Europe/Lisbon'))::integer;
begin
  select * into v_e from public.lupa_sugestoes_estado where id = 1;
  if v_e.id is null or v_e.ultimo_recalculo is null then
    perform public.lupa_sugestoes_recalcular(false);
  elsif v_hora between 3 and 5
        and (v_e.pendente or v_e.ultimo_recalculo < now() - interval '20 hours') then
    perform public.lupa_sugestoes_recalcular(false);
  end if;
end
$function$;

comment on function public.lupa_sugestoes_cron() is
  'Recalculo completo das sugestoes da lupa (~90 s): só de madrugada 03h-05h59 Lisboa, 1 vez por dia ou se pendente. Mudado a 28/11/2026 depois do alerta servidor_carregado das 15:57.';

-- 2) trigger das lojas: deixa de fazer o recalculo de 90 s na hora ao esconder uma loja (prendia o painel).
--    A lupa_sugestoes() já filtra lojas escondidas na leitura (lojas_escondidas_para_mim); o resto
--    fica marcado como pendente para a volta da madrugada. Loja desativada continua a sair logo.
create or replace function public.lupa_sugestoes_loja_mudou()
 returns trigger
 language plpgsql
 security definer
 set search_path to 'public', 'pg_temp'
as $function$
begin
  if new.approval_status is distinct from 'approved' or not coalesce(new.is_active_admin, true) then
    delete from public.lupa_sugestoes s
     where (s.restaurant_id = new.id or s.loja_origem = new.id) and not s.escondida;
  end if;
  update public.lupa_sugestoes_estado set pendente = true where id = 1;
  return null;
end
$function$;
