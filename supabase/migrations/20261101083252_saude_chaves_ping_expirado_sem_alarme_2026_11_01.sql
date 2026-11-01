-- 01/11/2026 (Claude.ai): o vigia das chaves mandou 24 alertas urgentes FALSOS ao Danilo às 07:06.
-- Causa: a ronda 574c9da5 foi enviada à mão às 22:30 de 31/10 e só foi verificada às 07:06,
-- depois de o pg_net apagar as respostas (pg_net.ttl = 6 horas). Sem resposta guardada, cada
-- ping virou 'sem_resposta' e gerou "FUNÇÃO NÃO RESPONDE". A ronda das 07:00 deu 45/45 ok.
-- Mudança: ping sem resposta guardada e com mais de 5 horas passa a 'expirado' (não deu para
-- verificar), que não alerta; o resumo conta os expirados à parte. O resto fica igual.
-- (Aplicada em produção a 01/11/2026 — versão 20261101083252; substituída logo a seguir pela
--  20261101083613. Espelho no repo escrito na missão zona-vermelha-2026-11-01, SQL lido de
--  schema_migrations.statements.)
create or replace function public._cron_saude_chaves_verificar()
 returns integer
 language plpgsql
 security definer
 set search_path to 'public'
as $function$
declare
  p record;
  v_status int;
  v_corpo text;
  v_tem boolean;
  v_res text;
  v_alertas int := 0;
  g record;
begin
  for p in
    select s.* from public.saude_chaves_pings s
    where s.verificado_em is null and s.criado_em < now() - interval '90 seconds'
    order by s.id
  loop
    v_tem := false; v_status := null; v_corpo := null;
    select true, h.status_code, left(coalesce(h.content::text, h.error_msg, ''), 300)
      into v_tem, v_status, v_corpo
      from net._http_response h where h.id = p.request_id;

    if not coalesce(v_tem, false) then
      if p.criado_em > now() - interval '15 minutes' then
        continue;
      end if;
      -- O pg_net só guarda as respostas 6 horas: depois disso a falta de resposta não prova nada.
      if p.criado_em < now() - interval '5 hours' then
        v_res := 'expirado';
      else
        v_res := 'sem_resposta';
      end if;
    elsif v_status in (401, 403) then
      v_res := 'chave_recusada';
    elsif v_status is null or v_status >= 500 then
      v_res := 'erro_5xx';
    elsif p.espera_pong and not (v_status = 200 and coalesce(v_corpo, '') like '%"pong"%') then
      v_res := 'sem_pong';
    else
      v_res := 'ok';
    end if;

    update public.saude_chaves_pings
       set status_code = v_status, corpo = v_corpo, verificado_em = now(), resultado = v_res
     where id = p.id;
  end loop;

  for g in
    select s.ronda, s.funcao,
           string_agg(s.modo || '=' || coalesce(s.status_code::text, 'sem resposta'), ', ' order by s.modo) as detalhe,
           bool_or(s.resultado = 'chave_recusada') as recusada,
           min(s.status_code) filter (where s.resultado <> 'ok') as codigo
      from public.saude_chaves_pings s
     where s.verificado_em is not null and s.resultado not in ('ok', 'expirado') and not s.alertado
     group by s.ronda, s.funcao
  loop
    perform public.notify_admin_urgent_push(
      case when g.recusada then 'chave_recusada' else 'funcao_sem_resposta' end,
      case when g.recusada
           then format(E'🔑 CHAVE RECUSADA · %s · %s\nO servidor deixou de conseguir chamar esta função (%s). Avisos, pagamentos ou pedidos podem estar a falhar calados.', g.funcao, coalesce(g.codigo::text, '?'), g.detalhe)
           else format(E'⚠️ FUNÇÃO NÃO RESPONDE · %s · %s\nO vigia das chaves chamou e a resposta não foi a esperada (%s).', g.funcao, coalesce(g.codigo::text, 'sem resposta'), g.detalhe)
      end,
      'edge_function', g.funcao,
      jsonb_build_object('ronda', g.ronda, 'funcao', g.funcao, 'detalhe', g.detalhe),
      '/admin/system-health');
    insert into public.e2e_log (fluxo, passo, estado, detalhe, device)
    values ('saude-chaves', g.funcao, 'erro', format('ronda %s: %s', g.ronda, g.detalhe), 'pg_cron');
    update public.saude_chaves_pings set alertado = true
     where ronda = g.ronda and funcao = g.funcao and resultado not in ('ok', 'expirado');
    v_alertas := v_alertas + 1;
  end loop;

  insert into public.e2e_log (fluxo, passo, estado, detalhe, device)
  select 'saude-chaves', 'ronda verificada',
         case when count(*) filter (where resultado not in ('ok', 'expirado')) > 0 then 'erro'
              when count(*) filter (where resultado = 'expirado') > 0 then 'aviso'
              else 'ok' end,
         format('ronda %s: %s ok, %s com problema, %s por verificar (respostas já apagadas pelo pg_net)',
                ronda,
                count(*) filter (where resultado = 'ok'),
                count(*) filter (where resultado not in ('ok', 'expirado')),
                count(*) filter (where resultado = 'expirado')),
         'pg_cron'
    from public.saude_chaves_pings
   where verificado_em > now() - interval '2 minutes'
   group by ronda;

  return v_alertas;
end;
$function$;
