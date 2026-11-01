-- 01/11/2026 (Claude.ai por MCP): alarme falso das 07:06 — 24 avisos "FUNÇÃO NÃO RESPONDE" no Telegram.
-- Causa provada: uma ronda manual do vigia às 22:30 de 31/10 só foi verificada às 07:06 (o verificador só corria às 07:06/07:20);
-- o pg_net apaga as respostas ao fim de 6 horas (pg_net.ttl = 6 hours), por isso o verificador não achou resposta nenhuma
-- e deu "sem resposta" a todas — quando os registos das funções mostram 200 em todas às 22:30:38.
-- Correção: (1) resposta já apagada pelo pg_net (ping com mais de 5 h) = 'expirado', sem aviso;
-- (2) UM aviso por ronda com a lista das funções, nunca um por função; (3) verificador de hora a hora (:06).
-- (Aplicada em produção a 01/11/2026 — versão 20261101083613. Espelho no repo escrito na missão
--  zona-vermelha-2026-11-01, SQL lido de schema_migrations.statements.)

CREATE OR REPLACE FUNCTION public._cron_saude_chaves_verificar()
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
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
      -- O pg_net apaga as respostas ao fim de 6 horas. Ping com mais de 5 h sem resposta guardada
      -- = verificado tarde demais (resposta apagada), NÃO função calada: marca 'expirado' e não avisa.
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

  -- UM aviso por ronda, com a lista das funções (antes: um aviso por função = 24 mensagens seguidas).
  for g in
    select s.ronda,
           count(distinct s.funcao) as n_funcoes,
           string_agg(distinct s.funcao, ', ' order by s.funcao) as funcoes,
           bool_or(s.resultado = 'chave_recusada') as recusada,
           string_agg(s.funcao || ' ' || s.modo || '=' || coalesce(s.status_code::text, 'sem resposta'), '; ') as detalhe
      from public.saude_chaves_pings s
     where s.verificado_em is not null and s.resultado not in ('ok', 'expirado') and not s.alertado
     group by s.ronda
  loop
    perform public.notify_admin_urgent_push(
      case when g.recusada then 'chave_recusada' else 'funcao_sem_resposta' end,
      case when g.recusada
           then format(E'🔑 CHAVE RECUSADA em %s função(ões)\nO servidor deixou de conseguir chamar: %s. Avisos, pagamentos ou pedidos podem estar a falhar calados.', g.n_funcoes, g.funcoes)
           else format(E'⚠️ %s FUNÇÃO(ÕES) SEM RESPOSTA CERTA\nO vigia das chaves chamou e não veio a resposta esperada de: %s.', g.n_funcoes, g.funcoes)
      end,
      'edge_function', g.ronda::text,
      jsonb_build_object('ronda', g.ronda, 'funcoes', g.funcoes, 'detalhe', left(g.detalhe, 3000)),
      '/admin/system-health');
    insert into public.e2e_log (fluxo, passo, estado, detalhe, device)
    values ('saude-chaves', 'aviso enviado', 'erro', format('ronda %s: %s', g.ronda, left(g.detalhe, 1500)), 'pg_cron');
    update public.saude_chaves_pings set alertado = true
     where ronda = g.ronda and verificado_em is not null and resultado not in ('ok', 'expirado');
    v_alertas := v_alertas + 1;
  end loop;

  insert into public.e2e_log (fluxo, passo, estado, detalhe, device)
  select 'saude-chaves', 'ronda verificada',
         case when count(*) filter (where resultado not in ('ok', 'expirado')) = 0 then 'ok' else 'erro' end,
         format('ronda %s: %s ok, %s com problema, %s verificados tarde demais (resposta já apagada, sem aviso)', ronda,
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

-- Verificador passa a correr de hora a hora (minuto 6): qualquer ronda extra/manual é verificada
-- muito antes de o pg_net apagar as respostas (6 h). Sem nada por verificar, não escreve nada.
select cron.alter_job(117, schedule := '6 * * * *');
