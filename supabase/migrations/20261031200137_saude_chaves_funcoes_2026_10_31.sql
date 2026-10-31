-- 31/10/2026 — vigia diário das chaves (missão chaves-varredura-2026-10-31, bloco D; autorizado pelo Danilo
-- 31/10 12:19 e no chat da Claude.ai 31/10 19:53, item 3). Parte 2: as funções, fechadas a anon/authenticated.
-- 07:00 UTC chama cada Edge Function que o servidor usa com {"ping":true} (legada em Bearer; chave nova em
-- apikey+Bearer). 07:06 e 07:20 lê as respostas: 401/403 = CHAVE RECUSADA (notify_admin_urgent_push + e2e_log).
-- Mudanças da Claude.ai à versão da sessão do PC: (a) as 3 da zona vermelha (finalize-order-from-intent, refund,
-- dispatch-engine) só com a chave LEGADA até as correções delas (docs/propostas/chaves-2026-10-31) estarem
-- publicadas, senão havia um alerta urgente todos os dias; (b) sem limpeza automática de linhas antigas por agora
-- (a tabela cresce ~45 linhas por dia).

create or replace function public._saude_chaves_lista()
returns table (funcao text, espera_pong boolean, corpo jsonb)
language sql
immutable
set search_path to 'public'
as $$
  select f.funcao, f.espera_pong, coalesce(f.corpo, '{"ping":true}'::jsonb)
  from (values
    ('notify-client', true, null::jsonb),
    ('notify-driver', true, null),
    ('notify-partner', true, null),
    ('notify-admin-urgent', true, null),
    ('notify-tvde-client', true, null),
    ('notify-tvde-driver', true, null),
    ('notify-cleaner', true, null),
    ('notify-washer', true, null),
    ('notify-service-provider', true, null),
    ('notify-chat-message', true, null),
    ('notify-driver-assigned', true, null),
    ('notify-partner-low-rating', true, null),
    ('ocr-receipt', true, null),
    ('settlement-receipt', true, null),
    ('push-clientes-alvo', true, null),
    ('payments-reconciler', true, null),
    ('tvde-payment', true, null),
    ('decidir', true, null),
    ('support-password-reset', true, null),
    ('weekly-closeout-digest', true, null),
    ('monthly-partner-statement', true, null),
    ('finalize-order-from-intent', false, null),
    ('refund', false, null),
    ('dispatch-engine', false, '{"ping":true,"orderId":"00000000-0000-0000-0000-000000000000"}'::jsonb)
  ) as f(funcao, espera_pong, corpo);
$$;

create or replace function public._cron_saude_chaves_funcoes()
returns uuid
language plpgsql
security definer
set search_path to 'public', 'vault'
as $$
declare
  v_ronda uuid := gen_random_uuid();
  v_url text;
  v_legada text;
  v_nova text;
  v_id bigint;
  v_n int := 0;
  r record;
begin
  select decrypted_secret into v_url from vault.decrypted_secrets where name = 'project_url' limit 1;
  v_legada := nullif(public._service_role_key(), '');
  select decrypted_secret into v_nova from vault.decrypted_secrets where name = 'sb_secret_backend' limit 1;
  if v_url is null then
    insert into public.e2e_log (fluxo, passo, estado, detalhe, device)
    values ('saude-chaves', 'ronda', 'erro', 'sem project_url no cofre: vigia das chaves não correu', 'pg_cron');
    return null;
  end if;

  for r in select * from public._saude_chaves_lista() loop
    if v_legada is not null then
      v_id := net.http_post(
        url := v_url || '/functions/v1/' || r.funcao,
        body := r.corpo,
        headers := jsonb_build_object('Content-Type', 'application/json', 'Authorization', 'Bearer ' || v_legada),
        timeout_milliseconds := 20000);
      insert into public.saude_chaves_pings (ronda, funcao, modo, espera_pong, request_id)
      values (v_ronda, r.funcao, 'legada_bearer', r.espera_pong, v_id);
      v_n := v_n + 1;
    end if;
    -- As 3 da zona vermelha ainda não aceitam a chave nova: só a legada, até as correções serem publicadas.
    if v_nova is not null and r.funcao not in ('finalize-order-from-intent', 'refund', 'dispatch-engine') then
      v_id := net.http_post(
        url := v_url || '/functions/v1/' || r.funcao,
        body := r.corpo,
        headers := jsonb_build_object('Content-Type', 'application/json', 'apikey', v_nova, 'Authorization', 'Bearer ' || v_nova),
        timeout_milliseconds := 20000);
      insert into public.saude_chaves_pings (ronda, funcao, modo, espera_pong, request_id)
      values (v_ronda, r.funcao, 'nova_apikey', r.espera_pong, v_id);
      v_n := v_n + 1;
    end if;
  end loop;

  insert into public.e2e_log (fluxo, passo, estado, detalhe, device)
  values ('saude-chaves', 'ronda enviada', 'info',
          format('ronda %s: %s chamadas (legada=%s, nova=%s)', v_ronda, v_n, v_legada is not null, v_nova is not null),
          'pg_cron');
  return v_ronda;
end;
$$;

create or replace function public._cron_saude_chaves_verificar()
returns int
language plpgsql
security definer
set search_path to 'public'
as $$
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
      v_res := 'sem_resposta';
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
     where s.verificado_em is not null and s.resultado <> 'ok' and not s.alertado
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
     where ronda = g.ronda and funcao = g.funcao and resultado <> 'ok';
    v_alertas := v_alertas + 1;
  end loop;

  insert into public.e2e_log (fluxo, passo, estado, detalhe, device)
  select 'saude-chaves', 'ronda verificada',
         case when count(*) filter (where resultado <> 'ok') = 0 then 'ok' else 'erro' end,
         format('ronda %s: %s ok, %s com problema', ronda, count(*) filter (where resultado = 'ok'), count(*) filter (where resultado <> 'ok')),
         'pg_cron'
    from public.saude_chaves_pings
   where verificado_em > now() - interval '2 minutes'
   group by ronda;

  return v_alertas;
end;
$$;

revoke all on function public._cron_saude_chaves_funcoes() from public, anon, authenticated;
revoke all on function public._cron_saude_chaves_verificar() from public, anon, authenticated;
revoke all on function public._saude_chaves_lista() from public, anon, authenticated;
