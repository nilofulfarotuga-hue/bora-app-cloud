-- Missão livro-comum-2026-10-23 (Bloco 5h): funil do caça-clientes no painel e máximo por dia configurável.
-- Nada de dinheiro: só contagens, um interruptor de quantidade de emails e a marca "à espera do Danilo".

-- 1) marca "à espera do Danilo" (o carteiro liga-a quando há rascunho de preço/reunião; o "manda" desliga-a)
alter table public.prospects_presenca add column if not exists espera_danilo boolean not null default false;

-- 2) máximo de emails novos por dia útil (era 5 escrito na função)
insert into public.platform_settings (key, value, description, category)
values ('caca_clientes_max_dia', '5'::jsonb, 'Caça-clientes: máximo de emails novos por dia útil (0 a 20)', 'caca_clientes')
on conflict (key) do nothing;

-- 3) carteiro_fila lê o máximo das definições (igual ao anterior em tudo o resto)
create or replace function public.carteiro_fila(p_chave text, p_forcar boolean default false)
returns jsonb
language plpgsql
security definer
set search_path to 'public', 'vault'
as $function$
declare v_on boolean; v_hoje integer; v_resto integer; v_local timestamp := now() at time zone 'Europe/Lisbon';
        v_janela boolean; v_novas jsonb; v_seg jsonb; v_agora jsonb; v_max integer;
begin
  perform public._caca_chave_ok(p_chave);
  select coalesce((value #>> '{}')::boolean, false) into v_on from public.platform_settings where key = 'caca_clientes_enabled';
  if not coalesce(v_on, false) then return jsonb_build_object('ligado', false, 'novas', '[]'::jsonb, 'seguimentos', '[]'::jsonb); end if;
  select least(20, greatest(0, coalesce((value #>> '{}')::integer, 5))) into v_max from public.platform_settings where key = 'caca_clientes_max_dia';
  v_max := coalesce(v_max, 5);
  v_janela := p_forcar or (extract(isodow from v_local) between 1 and 5 and v_local::time between time '09:30' and time '11:30');
  with f as (update public.prospect_propostas r set estado = 'sem_resposta', atualizado_em = now()
              from public.prospects_presenca p
             where p.id = r.prospect_id and r.estado = 'enviada' and r.seguimentos >= 2 and p.proximo_seguimento_em <= now()
             returning r.prospect_id)
  update public.prospects_presenca p set estado = 'sem_resposta', proximo_seguimento_em = null, atualizado_em = now() from f where p.id = f.prospect_id;
  select count(*) into v_hoje from public.prospect_propostas
   where canal = 'email' and enviado_em is not null and (enviado_em at time zone 'Europe/Lisbon')::date = v_local::date and destinatario not ilike 'boraappbora@%';
  v_resto := greatest(0, v_max - v_hoje);
  select coalesce(jsonb_agg(x), '[]'::jsonb) into v_agora from (
    select jsonb_build_object('proposta_id', r.id, 'prospect_id', p.id, 'nome', p.nome, 'para', p.email, 'assunto', r.assunto, 'texto', r.texto) x
      from public.prospect_propostas r join public.prospects_presenca p on p.id = r.prospect_id
     where r.estado = 'pronta' and r.canal = 'email' and r.enviar_agora and p.email_verificado and coalesce(p.email,'') <> ''
       and p.estado not in ('recusou','recusado','cliente','descartado','pausado') order by r.id limit 5) q;
  if v_janela then
    select coalesce(jsonb_agg(x), '[]'::jsonb) into v_novas from (
      select jsonb_build_object('proposta_id', r.id, 'prospect_id', p.id, 'nome', p.nome, 'para', p.email, 'assunto', r.assunto, 'texto', r.texto) x
        from public.prospect_propostas r join public.prospects_presenca p on p.id = r.prospect_id
       where r.estado = 'pronta' and r.canal = 'email' and not r.enviar_agora and p.email_verificado and coalesce(p.email,'') <> ''
         and p.estado not in ('recusou','recusado','cliente','descartado','pausado')
       order by p.pontuacao desc nulls last, r.id limit v_resto) q;
    select coalesce(jsonb_agg(x), '[]'::jsonb) into v_seg from (
      select jsonb_build_object('proposta_id', r.id, 'prospect_id', p.id, 'nome', p.nome, 'para', r.destinatario, 'assunto', r.assunto,
                                'texto', r.texto, 'thread_id', r.gmail_thread_id, 'rfc_message_id', r.rfc_message_id, 'numero', r.seguimentos + 1) x
        from public.prospect_propostas r join public.prospects_presenca p on p.id = r.prospect_id
       where r.estado = 'enviada' and r.canal = 'email' and r.seguimentos < 2 and p.proximo_seguimento_em <= now()
         and p.estado = 'enviada' order by p.proximo_seguimento_em limit 15) q;
  end if;
  return jsonb_build_object('ligado', true, 'janela', v_janela, 'enviadas_hoje', v_hoje, 'max_dia', v_max,
                            'novas', coalesce(v_agora, '[]'::jsonb) || coalesce(v_novas, '[]'::jsonb), 'seguimentos', coalesce(v_seg, '[]'::jsonb));
end $function$;

-- 4) carteiro_marcar ganha dois eventos: espera_danilo (rascunho à espera) e danilo_mandou (saiu com o manda)
create or replace function public.carteiro_marcar(p_chave text, p_proposta bigint, p_evento text, p_dados jsonb default '{}'::jsonb)
returns jsonb
language plpgsql
security definer
set search_path to 'public', 'vault'
as $function$
declare r public.prospect_propostas;
begin
  perform public._caca_chave_ok(p_chave);
  select * into r from public.prospect_propostas where id = p_proposta for update;
  if r.id is null then raise exception 'proposta_inexistente'; end if;
  if p_evento = 'enviada' then
    update public.prospect_propostas set estado = 'enviada', enviado_em = now(), enviar_agora = false, seguimentos = 0,
           destinatario = coalesce(p_dados->>'para', destinatario), gmail_message_id = p_dados->>'message_id',
           gmail_thread_id = p_dados->>'thread_id', rfc_message_id = p_dados->>'rfc_message_id', atualizado_em = now() where id = r.id;
    update public.prospects_presenca set estado = 'enviada', ultimo_contacto_em = now(), proximo_seguimento_em = now() + interval '3 days', atualizado_em = now()
     where id = r.prospect_id;
  elsif p_evento = 'seguimento' then
    update public.prospect_propostas set seguimentos = seguimentos + 1, atualizado_em = now() where id = r.id;
    update public.prospects_presenca set ultimo_contacto_em = now(),
           proximo_seguimento_em = now() + case when r.seguimentos = 0 then interval '4 days' else interval '7 days' end, atualizado_em = now()
     where id = r.prospect_id;
  elsif p_evento in ('respondeu','recusou','espera_danilo') then
    update public.prospect_propostas set estado = case when p_evento = 'espera_danilo' then 'respondeu' else p_evento end, atualizado_em = now() where id = r.id;
    update public.prospects_presenca set estado = case when p_evento = 'espera_danilo' then 'respondeu' else p_evento end,
           espera_danilo = (p_evento = 'espera_danilo'),
           resposta = left(p_dados->>'resposta', 4000), proximo_seguimento_em = null, atualizado_em = now()
     where id = r.prospect_id;
  elsif p_evento = 'danilo_mandou' then
    update public.prospects_presenca set espera_danilo = false, ultimo_contacto_em = now(),
           notas = coalesce(notas || ' | ', '') || 'manda do Danilo ' || to_char(now() at time zone 'Europe/Lisbon', 'DD/MM HH24:MI'), atualizado_em = now()
     where id = r.prospect_id;
  elsif p_evento = 'bounce' then
    update public.prospect_propostas set estado = 'email_invalido', atualizado_em = now() where id = r.id;
    update public.prospects_presenca set estado = 'email_invalido', email_verificado = false, proximo_seguimento_em = null,
           notas = coalesce(notas || ' | ', '') || 'bounce ' || to_char(now(), 'DD/MM') || ': ' || coalesce(email, ''), atualizado_em = now()
     where id = r.prospect_id;
  else raise exception 'evento_desconhecido';
  end if;
  return jsonb_build_object('ok', true, 'proposta', r.id, 'evento', p_evento);
end $function$;

-- 5) resumo do painel: funil completo + máximo por dia
create or replace function public.admin_caca_resumo()
returns jsonb
language sql
stable security definer
set search_path to 'public'
as $function$
  select case when public.is_admin() then jsonb_build_object(
    'ligado', coalesce((select (value #>> '{}')::boolean from public.platform_settings where key = 'caca_clientes_enabled'), false),
    'max_dia', coalesce((select (value #>> '{}')::integer from public.platform_settings where key = 'caca_clientes_max_dia'), 5),
    'encontrados', (select count(*) from public.prospects_presenca),
    'ativos', (select count(*) from public.prospects_presenca where estado not in ('descartado')),
    'com_email', (select count(*) from public.prospects_presenca where email_verificado),
    'prontas', (select count(*) from public.prospect_propostas where estado = 'pronta'),
    'enviados', (select count(*) from public.prospect_propostas where enviado_em is not null and destinatario not ilike 'boraappbora@%'),
    'enviados_hoje', (select count(*) from public.prospect_propostas where enviado_em is not null and destinatario not ilike 'boraappbora@%'
                        and (enviado_em at time zone 'Europe/Lisbon')::date = (now() at time zone 'Europe/Lisbon')::date),
    'respostas', (select count(*) from public.prospects_presenca where estado in ('respondeu','recusou')),
    'espera_danilo', (select count(*) from public.prospects_presenca where espera_danilo),
    'fechados', (select count(*) from public.prospects_presenca where estado = 'cliente'),
    'concelhos', (select coalesce(jsonb_agg(distinct concelho), '[]'::jsonb) from public.prospects_presenca where concelho is not null)
  ) end;
$function$;

-- 6) o painel muda o máximo por dia (só admin)
create or replace function public.admin_caca_max_dia(p_max integer)
returns integer
language plpgsql
security definer
set search_path to 'public'
as $function$
declare v integer := least(20, greatest(0, coalesce(p_max, 5)));
begin
  if not public.is_admin() then raise exception 'so_admin'; end if;
  insert into public.platform_settings (key, value, description, category, updated_at, updated_by)
  values ('caca_clientes_max_dia', to_jsonb(v), 'Caça-clientes: máximo de emails novos por dia útil (0 a 20)', 'caca_clientes', now(), auth.uid())
  on conflict (key) do update set value = excluded.value, updated_at = now(), updated_by = auth.uid();
  return v;
end $function$;

revoke all on function public.admin_caca_max_dia(integer) from public, anon;
grant execute on function public.admin_caca_max_dia(integer) to authenticated;
