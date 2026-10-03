-- Caca-clientes (03/10/2026): contacto verificado, carteiro com seguimentos, painel admin.
-- Nao toca em dinheiro. Tabelas: prospects_presenca, prospect_propostas, platform_settings (so a chave caca_clientes_enabled).

alter table public.prospects_presenca
  add column if not exists email_verificado boolean not null default false,
  add column if not exists email_fonte text,
  add column if not exists canal_preferido text,
  add column if not exists livro_reclamacoes_ok boolean,
  add column if not exists gancho text,
  add column if not exists ultimo_contacto_em timestamptz,
  add column if not exists proximo_seguimento_em timestamptz,
  add column if not exists resposta text,
  add column if not exists cliente_tipo text;

alter table public.prospects_presenca drop constraint if exists prospects_presenca_cliente_tipo_check;
alter table public.prospects_presenca add constraint prospects_presenca_cliente_tipo_check
  check (cliente_tipo is null or cliente_tipo in ('site','parceiro-bora','funcionario-digital','os-dois'));
alter table public.prospects_presenca drop constraint if exists prospects_presenca_estado_check;
alter table public.prospects_presenca add constraint prospects_presenca_estado_check
  check (estado in ('novo','amostra_pronta','proposta_rascunho','aprovado_danilo','enviado','cliente','recusado','descartado',
                    'pronta','enviada','respondeu','recusou','sem_resposta','email_invalido','pausado'));

alter table public.prospect_propostas
  add column if not exists destinatario text,
  add column if not exists gmail_message_id text,
  add column if not exists gmail_thread_id text,
  add column if not exists rfc_message_id text,
  add column if not exists enviado_em timestamptz,
  add column if not exists seguimentos smallint not null default 0,
  add column if not exists enviar_agora boolean not null default false,
  add column if not exists atualizado_em timestamptz not null default now();
alter table public.prospect_propostas drop constraint if exists prospect_propostas_canal_check;
alter table public.prospect_propostas add constraint prospect_propostas_canal_check
  check (canal in ('email','whatsapp','presencial','instagram','facebook'));
alter table public.prospect_propostas drop constraint if exists prospect_propostas_estado_check;
alter table public.prospect_propostas add constraint prospect_propostas_estado_check
  check (estado in ('rascunho','aprovado_danilo','enviado','pronta','enviada','respondeu','recusou','sem_resposta','email_invalido','pausada'));

insert into public.platform_settings (key, value, description, category)
values ('caca_clientes_enabled', 'false'::jsonb, 'Carteiro do caca-clientes: envia emails de prospecao em nome da Bora (max 5 novos por dia util). Interruptor geral.', 'robos')
on conflict (key) do nothing;

create or replace function public._caca_chave_ok(p_chave text) returns void
language plpgsql security definer set search_path = public, vault as $$
declare v_ok text;
begin
  select decrypted_secret into v_ok from vault.decrypted_secrets where name = 'prospects_presenca_key';
  if v_ok is null or p_chave is null or p_chave <> v_ok then raise exception 'chave_invalida'; end if;
end $$;
revoke all on function public._caca_chave_ok(text) from public, anon, authenticated;

-- cacador de contactos: so escreve os campos de contacto; nunca rebaixa um email ja verificado.
create or replace function public.prospect_contacto_registar(p_chave text, p_id bigint, p_linha jsonb)
returns jsonb
language plpgsql security definer set search_path = public, vault as $$
declare r public.prospects_presenca;
begin
  perform public._caca_chave_ok(p_chave);
  update public.prospects_presenca p set
    email = coalesce(nullif(p_linha->>'email',''), p.email),
    email_verificado = case when p_linha ? 'email_verificado' then (p_linha->>'email_verificado')::boolean else p.email_verificado end,
    email_fonte = coalesce(nullif(p_linha->>'email_fonte',''), p.email_fonte),
    canal_preferido = coalesce(nullif(p_linha->>'canal_preferido',''), p.canal_preferido),
    livro_reclamacoes_ok = case when p_linha ? 'livro_reclamacoes_ok' then (p_linha->>'livro_reclamacoes_ok')::boolean else p.livro_reclamacoes_ok end,
    gancho = coalesce(nullif(p_linha->>'gancho',''), p.gancho),
    instagram = coalesce(nullif(p_linha->>'instagram',''), p.instagram),
    facebook = coalesce(nullif(p_linha->>'facebook',''), p.facebook),
    website = coalesce(nullif(p_linha->>'website',''), p.website),
    concelho = coalesce(nullif(p_linha->>'concelho',''), p.concelho),
    cliente_tipo = coalesce(nullif(p_linha->>'cliente_tipo',''), p.cliente_tipo),
    pontuacao = coalesce(nullif(p_linha->>'pontuacao','')::smallint, p.pontuacao),
    notas = coalesce(nullif(p_linha->>'notas',''), p.notas),
    atualizado_em = now()
  where p.id = p_id returning * into r;
  if r.id is null then raise exception 'prospect_inexistente'; end if;
  return jsonb_build_object('id', r.id, 'email', r.email, 'email_verificado', r.email_verificado, 'canal_preferido', r.canal_preferido);
end $$;
revoke all on function public.prospect_contacto_registar(text, bigint, jsonb) from public;
grant execute on function public.prospect_contacto_registar(text, bigint, jsonb) to anon, authenticated, service_role;

-- redator: 'pronta' so com email verificado (ou canal que nao seja email); senao fica rascunho.
create or replace function public.prospect_proposta_registar(p_chave text, p_prospect bigint, p_linha jsonb)
returns bigint
language plpgsql security definer set search_path = public, vault as $$
declare v_id bigint; v_canal text := coalesce(p_linha->>'canal','email'); v_estado text := 'rascunho'; p public.prospects_presenca;
begin
  perform public._caca_chave_ok(p_chave);
  select * into p from public.prospects_presenca where id = p_prospect;
  if p.id is null then raise exception 'prospect_inexistente'; end if;
  if p.estado in ('recusou','recusado','cliente','descartado') then raise exception 'prospect_fechado'; end if;
  if p_linha->>'estado' = 'pronta' and (v_canal <> 'email' or (p.email_verificado and coalesce(p.email,'') <> '')) then
    v_estado := 'pronta';
  end if;
  insert into public.prospect_propostas (prospect_id, canal, assunto, texto, preco_mes_eur, estado, destinatario)
  values (p_prospect, v_canal, p_linha->>'assunto', p_linha->>'texto',
          nullif(p_linha->>'preco_mes_eur','')::numeric, v_estado, case when v_canal = 'email' then p.email end)
  returning id into v_id;
  update public.prospects_presenca set estado = case when v_estado = 'pronta' then 'pronta' else 'proposta_rascunho' end, atualizado_em = now()
   where id = p_prospect and estado in ('novo','amostra_pronta','proposta_rascunho','email_invalido');
  return v_id;
end $$;

-- carteiro: fila do dia. Devolve nada se o interruptor estiver desligado (a nao ser em teste com p_forcar).
create or replace function public.carteiro_fila(p_chave text, p_forcar boolean default false)
returns jsonb
language plpgsql security definer set search_path = public, vault as $$
declare v_on boolean; v_hoje integer; v_resto integer; v_local timestamp := now() at time zone 'Europe/Lisbon';
        v_janela boolean; v_novas jsonb; v_seg jsonb; v_agora jsonb;
begin
  perform public._caca_chave_ok(p_chave);
  select coalesce((value #>> '{}')::boolean, false) into v_on from public.platform_settings where key = 'caca_clientes_enabled';
  if not coalesce(v_on, false) then return jsonb_build_object('ligado', false, 'novas', '[]'::jsonb, 'seguimentos', '[]'::jsonb); end if;
  v_janela := p_forcar or (extract(isodow from v_local) between 1 and 5 and v_local::time between time '09:30' and time '11:30');
  -- quem ja levou os dois seguimentos e o prazo passou fica sem_resposta
  with f as (update public.prospect_propostas r set estado = 'sem_resposta', atualizado_em = now()
              from public.prospects_presenca p
             where p.id = r.prospect_id and r.estado = 'enviada' and r.seguimentos >= 2 and p.proximo_seguimento_em <= now()
             returning r.prospect_id)
  update public.prospects_presenca p set estado = 'sem_resposta', proximo_seguimento_em = null, atualizado_em = now() from f where p.id = f.prospect_id;
  select count(*) into v_hoje from public.prospect_propostas
   where canal = 'email' and enviado_em is not null and (enviado_em at time zone 'Europe/Lisbon')::date = v_local::date and destinatario not ilike 'boraappbora@%';
  v_resto := greatest(0, 5 - v_hoje);
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
  return jsonb_build_object('ligado', true, 'janela', v_janela, 'enviadas_hoje', v_hoje,
                            'novas', coalesce(v_agora, '[]'::jsonb) || coalesce(v_novas, '[]'::jsonb), 'seguimentos', coalesce(v_seg, '[]'::jsonb));
end $$;
revoke all on function public.carteiro_fila(text, boolean) from public;
grant execute on function public.carteiro_fila(text, boolean) to anon, authenticated, service_role;

create or replace function public.carteiro_threads(p_chave text)
returns jsonb
language plpgsql security definer set search_path = public, vault as $$
begin
  perform public._caca_chave_ok(p_chave);
  return coalesce((select jsonb_agg(jsonb_build_object('proposta_id', r.id, 'prospect_id', r.prospect_id, 'nome', p.nome, 'para', r.destinatario,
                    'thread_id', r.gmail_thread_id, 'assunto', r.assunto))
            from public.prospect_propostas r join public.prospects_presenca p on p.id = r.prospect_id
           where r.estado = 'enviada' and r.gmail_thread_id is not null), '[]'::jsonb);
end $$;
revoke all on function public.carteiro_threads(text) from public;
grant execute on function public.carteiro_threads(text) to anon, authenticated, service_role;

-- eventos: enviada | seguimento | respondeu | recusou | bounce
create or replace function public.carteiro_marcar(p_chave text, p_proposta bigint, p_evento text, p_dados jsonb default '{}'::jsonb)
returns jsonb
language plpgsql security definer set search_path = public, vault as $$
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
  elsif p_evento in ('respondeu','recusou') then
    update public.prospect_propostas set estado = p_evento, atualizado_em = now() where id = r.id;
    update public.prospects_presenca set estado = p_evento, resposta = left(p_dados->>'resposta', 4000), proximo_seguimento_em = null, atualizado_em = now()
     where id = r.prospect_id;
  elsif p_evento = 'bounce' then
    update public.prospect_propostas set estado = 'email_invalido', atualizado_em = now() where id = r.id;
    update public.prospects_presenca set estado = 'email_invalido', email_verificado = false, proximo_seguimento_em = null,
           notas = coalesce(notas || ' | ', '') || 'bounce ' || to_char(now(), 'DD/MM') || ': ' || coalesce(email, ''), atualizado_em = now()
     where id = r.prospect_id;
  else raise exception 'evento_desconhecido';
  end if;
  return jsonb_build_object('ok', true, 'proposta', r.id, 'evento', p_evento);
end $$;
revoke all on function public.carteiro_marcar(text, bigint, text, jsonb) from public;
grant execute on function public.carteiro_marcar(text, bigint, text, jsonb) to anon, authenticated, service_role;

create or replace function public.carteiro_resumo_dia(p_chave text)
returns jsonb
language plpgsql security definer set search_path = public, vault as $$
declare d date := (now() at time zone 'Europe/Lisbon')::date;
begin
  perform public._caca_chave_ok(p_chave);
  return jsonb_build_object(
    'enviados', (select count(*) from public.prospect_propostas where (enviado_em at time zone 'Europe/Lisbon')::date = d and destinatario not ilike 'boraappbora@%'),
    'seguimentos', (select count(*) from public.prospect_propostas r join public.prospects_presenca p on p.id = r.prospect_id
                     where r.seguimentos > 0 and (p.ultimo_contacto_em at time zone 'Europe/Lisbon')::date = d and (r.enviado_em at time zone 'Europe/Lisbon')::date < d),
    'respostas', (select count(*) from public.prospect_propostas where estado in ('respondeu','recusou') and (atualizado_em at time zone 'Europe/Lisbon')::date = d),
    'prontas', (select count(*) from public.prospect_propostas where estado = 'pronta'));
end $$;
revoke all on function public.carteiro_resumo_dia(text) from public;
grant execute on function public.carteiro_resumo_dia(text) to anon, authenticated, service_role;

-- ---------------------------------------------------------------- painel admin (PT-BR)
create or replace function public.admin_caca_lista(p_estado text default null, p_tipo text default null, p_concelho text default null,
                                                   p_pontos_min integer default 0, p_limite integer default 500)
returns setof jsonb
language sql stable security definer set search_path = public as $$
  select to_jsonb(p) || jsonb_build_object(
           'link', (select a.link_unico from public.prospect_amostras a where a.prospect_id = p.id order by a.criado_em desc limit 1),
           'proposta', (select to_jsonb(r) from public.prospect_propostas r where r.prospect_id = p.id order by r.id desc limit 1))
    from public.prospects_presenca p
   where public.is_admin() and (p_estado is null or p.estado = p_estado) and (p_tipo is null or p.cliente_tipo = p_tipo)
     and (p_concelho is null or p.concelho ilike p_concelho) and coalesce(p.pontuacao, 0) >= coalesce(p_pontos_min, 0)
   order by p.pontuacao desc nulls last, p.id
   limit greatest(1, least(coalesce(p_limite, 500), 5000));
$$;
revoke all on function public.admin_caca_lista(text, text, text, integer, integer) from public;
grant execute on function public.admin_caca_lista(text, text, text, integer, integer) to authenticated, service_role;

create or replace function public.admin_caca_resumo()
returns jsonb
language sql stable security definer set search_path = public as $$
  select case when public.is_admin() then jsonb_build_object(
    'ligado', coalesce((select (value #>> '{}')::boolean from public.platform_settings where key = 'caca_clientes_enabled'), false),
    'encontrados', (select count(*) from public.prospects_presenca),
    'ativos', (select count(*) from public.prospects_presenca where estado not in ('descartado')),
    'com_email', (select count(*) from public.prospects_presenca where email_verificado),
    'prontas', (select count(*) from public.prospect_propostas where estado = 'pronta'),
    'enviados', (select count(*) from public.prospect_propostas where enviado_em is not null and destinatario not ilike 'boraappbora@%'),
    'respostas', (select count(*) from public.prospects_presenca where estado in ('respondeu','recusou')),
    'fechados', (select count(*) from public.prospects_presenca where estado = 'cliente'),
    'concelhos', (select coalesce(jsonb_agg(distinct concelho), '[]'::jsonb) from public.prospects_presenca where concelho is not null)
  ) end;
$$;
revoke all on function public.admin_caca_resumo() from public;
grant execute on function public.admin_caca_resumo() to authenticated, service_role;

-- acoes: enviar_agora | pausar | retomar | recusou | cliente | editar | apagar
create or replace function public.admin_caca_acao(p_prospect bigint, p_acao text, p_assunto text default null, p_texto text default null)
returns jsonb
language plpgsql security definer set search_path = public as $$
declare p public.prospects_presenca; v_prop bigint;
begin
  if not public.is_admin() then raise exception 'so_admin'; end if;
  select * into p from public.prospects_presenca where id = p_prospect;
  if p.id is null then raise exception 'prospect_inexistente'; end if;
  select id into v_prop from public.prospect_propostas where prospect_id = p_prospect order by id desc limit 1;
  if p_acao = 'enviar_agora' then
    if not p.email_verificado or coalesce(p.email,'') = '' then raise exception 'sem_email_verificado'; end if;
    if v_prop is null then raise exception 'sem_proposta'; end if;
    update public.prospect_propostas set estado = 'pronta', enviar_agora = true, canal = 'email', destinatario = p.email, atualizado_em = now()
     where id = v_prop and estado in ('rascunho','pronta','pausada','aprovado_danilo');
    update public.prospects_presenca set estado = 'pronta', atualizado_em = now() where id = p_prospect;
  elsif p_acao = 'pausar' then
    update public.prospect_propostas set estado = 'pausada', enviar_agora = false, atualizado_em = now() where id = v_prop and estado in ('pronta','rascunho');
    update public.prospects_presenca set estado = 'pausado', proximo_seguimento_em = null, atualizado_em = now() where id = p_prospect;
  elsif p_acao = 'retomar' then
    update public.prospect_propostas set estado = 'pronta', atualizado_em = now() where id = v_prop and estado = 'pausada';
    update public.prospects_presenca set estado = 'pronta', atualizado_em = now() where id = p_prospect and estado = 'pausado';
  elsif p_acao = 'recusou' then
    update public.prospect_propostas set estado = 'recusou', enviar_agora = false, atualizado_em = now() where prospect_id = p_prospect and estado <> 'recusou';
    update public.prospects_presenca set estado = 'recusou', proximo_seguimento_em = null, atualizado_em = now() where id = p_prospect;
  elsif p_acao = 'cliente' then
    update public.prospects_presenca set estado = 'cliente', proximo_seguimento_em = null, atualizado_em = now() where id = p_prospect;
  elsif p_acao = 'editar' then
    if v_prop is null then raise exception 'sem_proposta'; end if;
    update public.prospect_propostas set assunto = coalesce(p_assunto, assunto), texto = coalesce(p_texto, texto), atualizado_em = now()
     where id = v_prop and estado in ('rascunho','pronta','pausada');
  elsif p_acao = 'apagar' then
    delete from public.prospects_presenca where id = p_prospect;
  else raise exception 'acao_desconhecida';
  end if;
  insert into public.admin_audit_log (admin_id, action, target_type, target_id, details)
  values (auth.uid(), 'caca_clientes_' || p_acao, 'prospect', p_prospect::text, jsonb_build_object('nome', p.nome));
  return jsonb_build_object('ok', true, 'acao', p_acao, 'prospect', p_prospect);
end $$;
revoke all on function public.admin_caca_acao(bigint, text, text, text) from public;
grant execute on function public.admin_caca_acao(bigint, text, text, text) to authenticated, service_role;

create or replace function public.admin_caca_interruptor(p_ligado boolean)
returns boolean
language plpgsql security definer set search_path = public as $$
begin
  if not public.is_admin() then raise exception 'so_admin'; end if;
  update public.platform_settings set value = to_jsonb(p_ligado), updated_at = now(), updated_by = auth.uid() where key = 'caca_clientes_enabled';
  return p_ligado;
end $$;
revoke all on function public.admin_caca_interruptor(boolean) from public;
grant execute on function public.admin_caca_interruptor(boolean) to authenticated, service_role;
