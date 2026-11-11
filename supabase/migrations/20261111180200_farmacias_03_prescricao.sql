-- =============================================================================
-- farmacias-2026-11-11 · 03 · Pedido com receita / pedido especial na farmácia
-- Fluxo: cliente envia → farmácia aceita (valor) / recusa (motivo) → cliente confirma e escolhe pagamento.
-- Loja escondida (so_lista_permissao) = DEMONSTRAÇÃO: confirmar não cria pedido, não cobra e não chama estafeta.
-- Dados de saúde (fotos, códigos) em bucket privado; nunca vão para logs, Telegram ou e2e_log.
-- Depende de 01 e 02.
-- =============================================================================

create table if not exists public.pedidos_prescricao (
  id uuid primary key default gen_random_uuid(),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  restaurant_id text not null references public.restaurants(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  tipo text not null check (tipo in ('receita', 'pedido_livre')),
  estado text not null default 'enviado'
    check (estado in ('enviado','aceite','aceite_parcial','recusado','expirado','cancelado','confirmado','entregue')),
  -- cliente
  receita_foto_path text,
  receita_numero text,
  receita_codigo_acesso text,
  receita_codigo_opcao text,
  descricao text check (descricao is null or length(descricao) <= 1000),
  pedido_foto_path text,
  morada text,
  lat double precision,
  lng double precision,
  nota text check (nota is null or length(nota) <= 500),
  assinatura_path text,
  consentimento_versao text,
  consentimento_texto text,
  consentimento_em timestamptz,
  -- farmácia
  valor_medicamentos_cents integer check (valor_medicamentos_cents is null or valor_medicamentos_cents between 0 and 100000),
  itens_disponiveis text,
  tempo_preparacao_min integer check (tempo_preparacao_min is null or tempo_preparacao_min between 0 and 240),
  motivo_recusa text check (motivo_recusa is null or motivo_recusa in ('sem_stock','receita_invalida','outro')),
  motivo_texto text,
  volta_a_ter text,
  respondido_por uuid,
  respondido_em timestamptz,
  lembrete_enviado_em timestamptz,
  expira_em timestamptz,
  -- confirmação
  taxa_servico_cents integer,
  total_cents integer,
  metodo_pagamento text check (metodo_pagamento is null or metodo_pagamento in ('card','mbway','cash')),
  so_disponiveis boolean,
  confirmado_em timestamptz,
  codigo_levantamento text,
  codigo_entrega text,
  order_id text,
  is_demo boolean not null default false,
  cancelado_por uuid,
  cancelado_em timestamptz,
  entregue_em timestamptz,
  dados_apagados_em timestamptz
);
create index if not exists pedidos_prescricao_loja_idx on public.pedidos_prescricao (restaurant_id, created_at desc);
create index if not exists pedidos_prescricao_user_idx on public.pedidos_prescricao (user_id, created_at desc);
create index if not exists pedidos_prescricao_vigiar_idx on public.pedidos_prescricao (estado, expira_em) where estado = 'enviado';

create or replace function public._pedidos_prescricao_updated_at()
returns trigger language plpgsql set search_path = public, pg_temp as $$
begin new.updated_at := now(); return new; end $$;
drop trigger if exists trg_pedidos_prescricao_updated_at on public.pedidos_prescricao;
create trigger trg_pedidos_prescricao_updated_at before update on public.pedidos_prescricao
  for each row execute function public._pedidos_prescricao_updated_at();

alter table public.pedidos_prescricao enable row level security;
revoke all on public.pedidos_prescricao from public, anon;
grant select on public.pedidos_prescricao to authenticated;  -- escrita só pelas RPCs

drop policy if exists pedidos_prescricao_ver on public.pedidos_prescricao;
create policy pedidos_prescricao_ver on public.pedidos_prescricao
  for select to authenticated
  using (
    user_id = auth.uid()
    or public.is_admin()
    or exists (select 1 from public.restaurants r
                where r.id = pedidos_prescricao.restaurant_id
                  and (r.user_id = auth.uid() or r.user_ = auth.uid()))
  );

-- Tempo real: a resposta da farmácia aparece no telemóvel do cliente em segundos.
do $$ begin
  if exists (select 1 from pg_publication where pubname = 'supabase_realtime')
     and not exists (select 1 from pg_publication_tables
                      where pubname = 'supabase_realtime' and schemaname = 'public' and tablename = 'pedidos_prescricao') then
    alter publication supabase_realtime add table public.pedidos_prescricao;
  end if;
end $$;

-- ---- Storage privado ----------------------------------------------------------------
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('prescricoes', 'prescricoes', false, 10485760, array['image/jpeg','image/png','image/webp','image/heic','application/pdf'])
on conflict (id) do update set public = false;

-- Quem pode LER um ficheiro: o dono da pasta (cliente), a farmácia de um pedido que o use, o admin.
create or replace function public.prescricao_pode_ler_ficheiro(p_nome text)
returns boolean
language sql stable security definer
set search_path = public, pg_temp
as $$
  select auth.uid() is not null and (
    split_part(p_nome, '/', 1) = auth.uid()::text
    or public.is_admin()
    or exists (
      select 1 from public.pedidos_prescricao pp
        join public.restaurants r on r.id = pp.restaurant_id
       where (r.user_id = auth.uid() or r.user_ = auth.uid())
         and p_nome in (pp.receita_foto_path, pp.pedido_foto_path, pp.assinatura_path)
    )
  );
$$;
revoke all on function public.prescricao_pode_ler_ficheiro(text) from public, anon;
grant execute on function public.prescricao_pode_ler_ficheiro(text) to authenticated;

drop policy if exists prescricoes_ler on storage.objects;
create policy prescricoes_ler on storage.objects for select to authenticated
  using (bucket_id = 'prescricoes' and public.prescricao_pode_ler_ficheiro(name));
drop policy if exists prescricoes_inserir_propria_pasta on storage.objects;
create policy prescricoes_inserir_propria_pasta on storage.objects for insert to authenticated
  with check (bucket_id = 'prescricoes' and split_part(name, '/', 1) = auth.uid()::text);

-- ---- Ajudas -----------------------------------------------------------------------------
create or replace function public._setting_int(p_key text, p_defeito integer)
returns integer language sql stable security definer set search_path = public, pg_temp as $$
  select coalesce((select (value #>> '{}')::integer from public.platform_settings where key = p_key), p_defeito);
$$;
create or replace function public._setting_num(p_key text, p_defeito numeric)
returns numeric language sql stable security definer set search_path = public, pg_temp as $$
  select coalesce((select (value #>> '{}')::numeric from public.platform_settings where key = p_key), p_defeito);
$$;
create or replace function public._setting_txt(p_key text, p_defeito text)
returns text language sql stable security definer set search_path = public, pg_temp as $$
  select coalesce((select value #>> '{}' from public.platform_settings where key = p_key), p_defeito);
$$;
revoke all on function public._setting_int(text, integer), public._setting_num(text, numeric), public._setting_txt(text, text) from public, anon, authenticated;

-- A receita e os botões da farmácia estão visíveis para o utilizador atual?
create or replace function public.farmacia_botoes_visiveis(p_restaurant_id text)
returns boolean
language sql stable security definer
set search_path = public, pg_temp
as $$
  select coalesce((
    select r.category = 'pharmacy'
       and public.loja_visivel_para_mim(r.id)
       and (
         r.pharmacy_prescription_mode = 'publico'
         or (r.pharmacy_prescription_mode = 'so_lista' and auth.uid() is not null and (
               public.is_admin() or r.user_id = auth.uid() or r.user_ = auth.uid()
               or exists (select 1 from public.loja_lista_permissao l where l.restaurant_id = r.id and l.user_id = auth.uid())))
       )
      from public.restaurants r where r.id = p_restaurant_id
  ), false);
$$;
revoke all on function public.farmacia_botoes_visiveis(text) from public;
grant execute on function public.farmacia_botoes_visiveis(text) to anon, authenticated;

create or replace function public.farmacia_consentimento(p_restaurant_id text)
returns jsonb
language plpgsql stable security definer
set search_path = public, pg_temp
as $$
declare v_nome text;
begin
  if not public.farmacia_botoes_visiveis(p_restaurant_id) then
    raise exception 'FARMACIA_INDISPONIVEL: Este serviço ainda não está disponível nesta farmácia.' using errcode = 'P0001';
  end if;
  select name into v_nome from public.restaurants where id = p_restaurant_id;
  return jsonb_build_object(
    'versao', public._setting_txt('pharmacy_prescription_consent_version', 'v1-2026-11-11'),
    'texto', replace(public._setting_txt('pharmacy_prescription_consent_text',
       'Autorizo o estafeta da Bora a levantar os meus medicamentos em meu nome na {farmacia}. A farmácia valida a receita e é responsável pela dispensa.'),
       '{farmacia}', coalesce(v_nome, 'farmácia')),
    'taxa_servico_cents', public._setting_int('errand_fee_normal_cents', 600),
    'minutos_resposta', public._setting_int('pharmacy_prescription_response_minutes', 15)
  );
end $$;
revoke all on function public.farmacia_consentimento(text) from public, anon;
grant execute on function public.farmacia_consentimento(text) to authenticated;

-- Avisos (sininho + push). Nunca leva códigos nem fotos da receita no texto.
create or replace function public._prescricao_avisar(p_id uuid, p_para text, p_tipo text, p_titulo text, p_corpo text)
returns void
language plpgsql security definer
set search_path = public, pg_temp
as $$
declare
  v record; v_dono uuid; v_url text; v_key text;
begin
  select pp.user_id, pp.restaurant_id into v from public.pedidos_prescricao pp where pp.id = p_id;
  if not found then return; end if;
  select coalesce(r.user_id, r.user_) into v_dono from public.restaurants r where r.id = v.restaurant_id;
  begin
    perform public._push_in_app_notification(case when p_para = 'cliente' then v.user_id else v_dono end,
                                             p_tipo, p_titulo, p_corpo, p_id::text);
  exception when others then raise notice 'prescricao sininho: %', sqlerrm;
  end;
  select decrypted_secret into v_url from vault.decrypted_secrets where name = 'project_url';
  select decrypted_secret into v_key from vault.decrypted_secrets where name = 'service_role_key';
  if v_url is null or v_key is null then return; end if;
  begin
    if p_para = 'cliente' then
      perform net.http_post(url := v_url || '/functions/v1/notify-client',
        headers := jsonb_build_object('Authorization', 'Bearer ' || v_key, 'Content-Type', 'application/json'),
        body := jsonb_build_object('clientId', v.user_id, 'orderId', p_id::text, 'type', p_tipo,
                                   'status', p_tipo, 'title', p_titulo, 'body', p_corpo));
    else
      perform net.http_post(url := v_url || '/functions/v1/notify-partner',
        headers := jsonb_build_object('Authorization', 'Bearer ' || v_key, 'Content-Type', 'application/json'),
        body := jsonb_build_object('restaurantId', v.restaurant_id, 'orderId', p_id::text, 'kind', p_tipo,
                                   'customTitle', p_titulo, 'customBody', p_corpo, 'items', p_corpo));
    end if;
  exception when others then raise notice 'prescricao push: %', sqlerrm;
  end;
end $$;
revoke all on function public._prescricao_avisar(uuid, text, text, text, text) from public, anon, authenticated;

-- ---- Cliente: enviar ------------------------------------------------------------------------
create or replace function public.prescricao_criar(
  p_restaurant_id text, p_tipo text,
  p_receita_foto_path text default null, p_receita_numero text default null,
  p_receita_codigo_acesso text default null, p_receita_codigo_opcao text default null,
  p_descricao text default null, p_pedido_foto_path text default null,
  p_morada text default null, p_lat double precision default null, p_lng double precision default null,
  p_nota text default null, p_assinatura_path text default null, p_consentimento_versao text default null)
returns uuid
language plpgsql security definer
set search_path = public, pg_temp
as $$
declare
  v_uid uuid := auth.uid();
  v_loja record;
  v_min integer := public._setting_int('pharmacy_prescription_response_minutes', 15);
  v_versao text := public._setting_txt('pharmacy_prescription_consent_version', 'v1-2026-11-11');
  v_cons jsonb;
  v_id uuid;
  v_pasta text;
begin
  if v_uid is null then
    raise exception 'SEM_SESSAO: Tem de entrar na sua conta.' using errcode = '42501';
  end if;
  if not public.farmacia_botoes_visiveis(p_restaurant_id) then
    raise exception 'FARMACIA_INDISPONIVEL: Este serviço ainda não está disponível nesta farmácia.' using errcode = 'P0001';
  end if;
  select id, name, so_lista_permissao into v_loja from public.restaurants where id = p_restaurant_id;
  if p_tipo not in ('receita', 'pedido_livre') then
    raise exception 'TIPO_INVALIDO: Tipo de pedido desconhecido.' using errcode = 'P0001';
  end if;
  v_pasta := v_uid::text || '/';
  if coalesce(p_receita_foto_path, v_pasta) not like v_pasta || '%'
     or coalesce(p_pedido_foto_path, v_pasta) not like v_pasta || '%'
     or coalesce(p_assinatura_path, v_pasta) not like v_pasta || '%' then
    raise exception 'FICHEIRO_INVALIDO: A imagem não é sua. Tire a foto outra vez.' using errcode = '42501';
  end if;
  if p_tipo = 'receita' then
    if nullif(btrim(coalesce(p_receita_foto_path, '')), '') is null
       and (nullif(btrim(coalesce(p_receita_numero, '')), '') is null
            or nullif(btrim(coalesce(p_receita_codigo_acesso, '')), '') is null) then
      raise exception 'FALTA_RECEITA: Falta a foto da receita ou o número com o código de acesso.' using errcode = 'P0001';
    end if;
    if nullif(btrim(coalesce(p_assinatura_path, '')), '') is null then
      raise exception 'FALTA_ASSINATURA: Falta a sua assinatura na autorização.' using errcode = 'P0001';
    end if;
    if coalesce(p_consentimento_versao, '') <> v_versao then
      raise exception 'AUTORIZACAO_DESATUALIZADA: O texto da autorização mudou. Volte a ler e assine outra vez.' using errcode = 'P0001';
    end if;
  else
    if nullif(btrim(coalesce(p_descricao, '')), '') is null then
      raise exception 'FALTA_DESCRICAO: Escreva o que procura.' using errcode = 'P0001';
    end if;
  end if;
  if nullif(btrim(coalesce(p_morada, '')), '') is null then
    raise exception 'FALTA_MORADA: Falta a morada de entrega.' using errcode = 'P0001';
  end if;
  -- Não deixar encher a farmácia: no máximo 3 pedidos à espera por cliente e loja.
  if (select count(*) from public.pedidos_prescricao
       where user_id = v_uid and restaurant_id = p_restaurant_id and estado = 'enviado') >= 3 then
    raise exception 'DEMASIADOS_PEDIDOS: Já tem pedidos à espera nesta farmácia. Aguarde a resposta.' using errcode = 'P0001';
  end if;

  v_cons := public.farmacia_consentimento(p_restaurant_id);
  insert into public.pedidos_prescricao (
    restaurant_id, user_id, tipo, receita_foto_path, receita_numero, receita_codigo_acesso, receita_codigo_opcao,
    descricao, pedido_foto_path, morada, lat, lng, nota, assinatura_path,
    consentimento_versao, consentimento_texto, consentimento_em, expira_em, is_demo, taxa_servico_cents)
  values (
    p_restaurant_id, v_uid, p_tipo,
    nullif(btrim(coalesce(p_receita_foto_path, '')), ''), nullif(btrim(coalesce(p_receita_numero, '')), ''),
    nullif(btrim(coalesce(p_receita_codigo_acesso, '')), ''), nullif(btrim(coalesce(p_receita_codigo_opcao, '')), ''),
    nullif(btrim(coalesce(p_descricao, '')), ''), nullif(btrim(coalesce(p_pedido_foto_path, '')), ''),
    btrim(p_morada), p_lat, p_lng, nullif(btrim(coalesce(p_nota, '')), ''),
    nullif(btrim(coalesce(p_assinatura_path, '')), ''),
    case when p_tipo = 'receita' then v_versao end,
    case when p_tipo = 'receita' then v_cons->>'texto' end,
    case when p_tipo = 'receita' then now() end,
    now() + make_interval(mins => 2 * v_min),
    coalesce(v_loja.so_lista_permissao, false),
    (v_cons->>'taxa_servico_cents')::integer)
  returning id into v_id;

  perform public._prescricao_avisar(v_id, 'loja', 'prescricao_nova',
    case when p_tipo = 'receita' then 'Nova receita para aviar' else 'Pedido especial de um cliente' end,
    'Toque para ver e responder: tem ou não tem.');
  return v_id;
end $$;
revoke all on function public.prescricao_criar(text, text, text, text, text, text, text, text, text, double precision, double precision, text, text, text) from public, anon;
grant execute on function public.prescricao_criar(text, text, text, text, text, text, text, text, text, double precision, double precision, text, text, text) to authenticated;

-- ---- Farmácia: responder ------------------------------------------------------------------
create or replace function public.prescricao_responder(
  p_id uuid, p_aceita boolean, p_valor_cents integer default null, p_parcial boolean default false,
  p_itens_disponiveis text default null, p_tempo_preparacao_min integer default null,
  p_motivo text default null, p_motivo_texto text default null, p_volta_a_ter text default null)
returns void
language plpgsql security definer
set search_path = public, pg_temp
as $$
declare
  v_uid uuid := auth.uid();
  v record;
begin
  select pp.*, r.user_id as dono1, r.user_ as dono2 into v
    from public.pedidos_prescricao pp join public.restaurants r on r.id = pp.restaurant_id
   where pp.id = p_id for update of pp;
  if not found then
    raise exception 'NAO_ENCONTRADO: Pedido não encontrado.' using errcode = 'P0002';
  end if;
  if v_uid is null or not (v_uid = v.dono1 or v_uid = v.dono2 or public.is_admin()) then
    raise exception 'SEM_PERMISSAO: Só a farmácia deste pedido pode responder.' using errcode = '42501';
  end if;
  if v.estado <> 'enviado' then
    raise exception 'JA_RESPONDIDO: Este pedido já não está à espera de resposta.' using errcode = 'P0001';
  end if;
  if p_aceita then
    if p_valor_cents is null or p_valor_cents <= 0 then
      raise exception 'FALTA_VALOR: Escreva o valor total a pagar pelo cliente.' using errcode = 'P0001';
    end if;
    if coalesce(p_parcial, false) and nullif(btrim(coalesce(p_itens_disponiveis, '')), '') is null then
      raise exception 'FALTA_ITENS: Diga quais medicamentos tem.' using errcode = 'P0001';
    end if;
    update public.pedidos_prescricao set
      estado = case when coalesce(p_parcial, false) then 'aceite_parcial' else 'aceite' end,
      valor_medicamentos_cents = p_valor_cents,
      itens_disponiveis = nullif(btrim(coalesce(p_itens_disponiveis, '')), ''),
      tempo_preparacao_min = p_tempo_preparacao_min,
      respondido_por = v_uid, respondido_em = now()
    where id = p_id;
    perform public._prescricao_avisar(p_id, 'cliente', 'prescricao_resposta',
      case when coalesce(p_parcial, false) then 'A farmácia tem parte do seu pedido' else 'A farmácia tem o seu pedido' end,
      'Veja o valor e confirme na app.');
  else
    if p_motivo is null or p_motivo not in ('sem_stock', 'receita_invalida', 'outro') then
      raise exception 'FALTA_MOTIVO: Escolha o motivo.' using errcode = 'P0001';
    end if;
    update public.pedidos_prescricao set
      estado = 'recusado', motivo_recusa = p_motivo,
      motivo_texto = nullif(btrim(coalesce(p_motivo_texto, '')), ''),
      volta_a_ter = nullif(btrim(coalesce(p_volta_a_ter, '')), ''),
      respondido_por = v_uid, respondido_em = now()
    where id = p_id;
    perform public._prescricao_avisar(p_id, 'cliente', 'prescricao_resposta',
      'A farmácia não tem o seu pedido', 'Não foi cobrado nada. Veja o motivo na app.');
  end if;
end $$;
revoke all on function public.prescricao_responder(uuid, boolean, integer, boolean, text, integer, text, text, text) from public, anon;
grant execute on function public.prescricao_responder(uuid, boolean, integer, boolean, text, integer, text, text, text) to authenticated;

-- ---- Cliente: confirmar / cancelar ----------------------------------------------------------
create or replace function public._prescricao_codigo(p_tam integer)
returns text language sql volatile set search_path = public, pg_temp as $$
  select string_agg(substr('ABCDEFGHJKLMNPQRSTUVWXYZ23456789', 1 + floor(random() * 32)::int, 1), '')
    from generate_series(1, p_tam);
$$;
revoke all on function public._prescricao_codigo(integer) from public, anon, authenticated;

create or replace function public.prescricao_confirmar(p_id uuid, p_metodo text, p_so_disponiveis boolean default true)
returns jsonb
language plpgsql security definer
set search_path = public, pg_temp
as $$
declare
  v_uid uuid := auth.uid();
  v record;
  v_taxa integer;
  v_total integer;
  v_lev text := public._prescricao_codigo(6);
  v_ent text := lpad((floor(random() * 10000))::int::text, 4, '0');
begin
  select pp.*, r.so_lista_permissao as escondida into v
    from public.pedidos_prescricao pp join public.restaurants r on r.id = pp.restaurant_id
   where pp.id = p_id for update of pp;
  if not found or v.user_id is distinct from v_uid then
    raise exception 'NAO_ENCONTRADO: Pedido não encontrado.' using errcode = 'P0002';
  end if;
  if v.estado not in ('aceite', 'aceite_parcial') then
    raise exception 'NAO_CONFIRMAVEL: Este pedido já não pode ser confirmado.' using errcode = 'P0001';
  end if;
  if p_metodo not in ('card', 'mbway', 'cash') then
    raise exception 'METODO_INVALIDO: Escolha cartão, MB Way ou dinheiro.' using errcode = 'P0001';
  end if;
  v_taxa := coalesce(v.taxa_servico_cents, public._setting_int('errand_fee_normal_cents', 600));
  v_total := v.valor_medicamentos_cents + v_taxa;

  if not coalesce(v.escondida, false) then
    -- Loja aberta ao público: o pedido real (estafeta + cobrança) ainda não está ligado.
    -- Ver LEIA-ME_PUBLICAR.md (definição pharmacy_prescription_real_orders_enabled).
    raise exception 'RECEITA_REAL_POR_LIGAR: A entrega de receitas ainda não está disponível. Pode levantar na farmácia.' using errcode = 'P0001';
  end if;

  update public.pedidos_prescricao set
    estado = 'confirmado', metodo_pagamento = p_metodo, so_disponiveis = coalesce(p_so_disponiveis, true),
    taxa_servico_cents = v_taxa, total_cents = v_total, confirmado_em = now(),
    codigo_levantamento = v_lev, codigo_entrega = v_ent, is_demo = true
  where id = p_id;
  perform public._prescricao_avisar(p_id, 'loja', 'prescricao_confirmada',
    'O cliente confirmou o pedido', 'Pode preparar. Código de levantamento ' || v_lev || '.');
  return jsonb_build_object('estado', 'confirmado', 'is_demo', true, 'total_cents', v_total,
                            'taxa_servico_cents', v_taxa, 'codigo_levantamento', v_lev, 'codigo_entrega', v_ent);
end $$;
revoke all on function public.prescricao_confirmar(uuid, text, boolean) from public, anon;
grant execute on function public.prescricao_confirmar(uuid, text, boolean) to authenticated;

create or replace function public.prescricao_cancelar(p_id uuid)
returns void
language plpgsql security definer
set search_path = public, pg_temp
as $$
declare v record;
begin
  select * into v from public.pedidos_prescricao where id = p_id for update;
  if not found or v.user_id is distinct from auth.uid() then
    raise exception 'NAO_ENCONTRADO: Pedido não encontrado.' using errcode = 'P0002';
  end if;
  if v.estado not in ('enviado', 'aceite', 'aceite_parcial') then
    raise exception 'NAO_CANCELAVEL: Este pedido já não pode ser cancelado.' using errcode = 'P0001';
  end if;
  update public.pedidos_prescricao set estado = 'cancelado', cancelado_por = auth.uid(), cancelado_em = now() where id = p_id;
  perform public._prescricao_avisar(p_id, 'loja', 'prescricao_confirmada', 'O cliente cancelou o pedido', 'Já não precisa de preparar.');
end $$;
revoke all on function public.prescricao_cancelar(uuid) from public, anon;
grant execute on function public.prescricao_cancelar(uuid) to authenticated;

-- ---- Vigia (cada minuto): lembrete aos X min, expira aos 2X ------------------------------------
create or replace function public.prescricao_vigiar()
returns integer
language plpgsql security definer
set search_path = public, pg_temp
as $$
declare
  v_min integer := public._setting_int('pharmacy_prescription_response_minutes', 15);
  r record; n integer := 0;
begin
  for r in select id from public.pedidos_prescricao
            where estado = 'enviado' and lembrete_enviado_em is null
              and created_at <= now() - make_interval(mins => v_min) and expira_em > now()
  loop
    update public.pedidos_prescricao set lembrete_enviado_em = now() where id = r.id;
    perform public._prescricao_avisar(r.id, 'loja', 'prescricao_lembrete', 'Receita à espera de resposta',
      'Um cliente está à espera. Responda se tem ou não tem.');
    n := n + 1;
  end loop;
  for r in select id from public.pedidos_prescricao where estado = 'enviado' and expira_em <= now()
  loop
    update public.pedidos_prescricao set estado = 'expirado' where id = r.id and estado = 'enviado';
    perform public._prescricao_avisar(r.id, 'cliente', 'prescricao_expirada', 'A farmácia não respondeu a tempo',
      'Não foi cobrado nada. Pode enviar outra vez.');
    n := n + 1;
  end loop;
  return n;
end $$;
revoke all on function public.prescricao_vigiar() from public, anon, authenticated;

-- ---- Admin (painel PT-BR) ---------------------------------------------------------------------
create or replace function public.admin_prescricoes_listar(p_estado text default null, p_restaurant_id text default null, p_limite integer default 200)
returns setof jsonb
language plpgsql stable security definer
set search_path = public, pg_temp
as $$
begin
  if not public.is_admin() then
    raise exception 'Somente admin.' using errcode = '42501';
  end if;
  return query
  select jsonb_build_object(
    'id', pp.id, 'created_at', pp.created_at, 'restaurant_id', pp.restaurant_id, 'loja', r.name,
    'cliente_email', u.email, 'cliente_nome', coalesce(u.raw_user_meta_data->>'name', u.raw_user_meta_data->>'full_name'),
    'tipo', pp.tipo, 'estado', pp.estado,
    'respondido_por_email', ru.email, 'respondido_em', pp.respondido_em,
    'valor_medicamentos_cents', pp.valor_medicamentos_cents, 'taxa_servico_cents', pp.taxa_servico_cents,
    'total_cents', pp.total_cents, 'metodo_pagamento', pp.metodo_pagamento, 'is_demo', pp.is_demo,
    'motivo_recusa', pp.motivo_recusa, 'expira_em', pp.expira_em, 'confirmado_em', pp.confirmado_em,
    'tem_foto', (pp.receita_foto_path is not null or pp.pedido_foto_path is not null),
    'tem_codigos', (pp.receita_numero is not null),
    'dados_apagados_em', pp.dados_apagados_em)
  from public.pedidos_prescricao pp
  join public.restaurants r on r.id = pp.restaurant_id
  left join auth.users u on u.id = pp.user_id
  left join auth.users ru on ru.id = pp.respondido_por
  where (p_estado is null or pp.estado = p_estado)
    and (p_restaurant_id is null or pp.restaurant_id = p_restaurant_id)
  order by pp.created_at desc
  limit greatest(1, least(coalesce(p_limite, 200), 1000));
end $$;
revoke all on function public.admin_prescricoes_listar(text, text, integer) from public, anon;
grant execute on function public.admin_prescricoes_listar(text, text, integer) to authenticated;

create or replace function public.admin_prescricao_forcar(p_id uuid, p_estado text, p_motivo text)
returns void
language plpgsql security definer
set search_path = public, pg_temp
as $$
declare v_antes text;
begin
  if not public.is_admin() then
    raise exception 'Somente admin.' using errcode = '42501';
  end if;
  if nullif(btrim(coalesce(p_motivo, '')), '') is null then
    raise exception 'Motivo obrigatório.' using errcode = 'P0001';
  end if;
  if p_estado not in ('enviado','aceite','aceite_parcial','recusado','expirado','cancelado','confirmado','entregue') then
    raise exception 'Estado inválido.' using errcode = 'P0001';
  end if;
  select estado into v_antes from public.pedidos_prescricao where id = p_id for update;
  if not found then raise exception 'Pedido não encontrado.' using errcode = 'P0002'; end if;
  update public.pedidos_prescricao set estado = p_estado,
    cancelado_por = case when p_estado = 'cancelado' then auth.uid() else cancelado_por end,
    cancelado_em = case when p_estado = 'cancelado' then now() else cancelado_em end,
    entregue_em = case when p_estado = 'entregue' then now() else entregue_em end,
    expira_em = case when p_estado = 'enviado' then now() + make_interval(mins => 2 * public._setting_int('pharmacy_prescription_response_minutes', 15)) else expira_em end
  where id = p_id;
  begin
    insert into public.admin_audit_log (admin_id, action, entity_type, entity_id_text, details)
    values (auth.uid(), 'prescricao_forcar', 'pedido_prescricao', p_id::text,
            jsonb_build_object('de', v_antes, 'para', p_estado, 'motivo', p_motivo));
  exception when others then raise notice 'admin_audit_log: %', sqlerrm;
  end;
  if p_estado in ('cancelado', 'recusado', 'expirado', 'entregue', 'confirmado') then
    perform public._prescricao_avisar(p_id, 'cliente', 'prescricao_resposta', 'O seu pedido à farmácia mudou',
      'Abra a app para ver o estado.');
  end if;
end $$;
revoke all on function public.admin_prescricao_forcar(uuid, text, text) from public, anon;
grant execute on function public.admin_prescricao_forcar(uuid, text, text) to authenticated;

create or replace function public.admin_farmacias_listar()
returns setof jsonb
language plpgsql stable security definer
set search_path = public, pg_temp
as $$
begin
  if not public.is_admin() then
    raise exception 'Somente admin.' using errcode = '42501';
  end if;
  return query
  select jsonb_build_object(
    'id', r.id, 'name', r.name, 'approval_status', r.approval_status, 'is_active_admin', r.is_active_admin,
    'coming_soon', r.coming_soon, 'so_lista_permissao', r.so_lista_permissao,
    'pharmacy_prescription_mode', r.pharmacy_prescription_mode,
    'partner_extra_commission_pct', r.partner_extra_commission_pct,
    'partner_extra_commission_starts_at', r.partner_extra_commission_starts_at,
    'aberta_ao_publico_em', r.aberta_ao_publico_em,
    'dono_email', (select email from auth.users where id = coalesce(r.user_id, r.user_)),
    'produtos', (select count(*) from public.products p where p.restaurant_id = r.id),
    'produtos_provisorios', (select count(*) from public.products p where p.restaurant_id = r.id and p.preco_provisorio),
    'lista', (select coalesce(jsonb_agg(u.email order by u.email), '[]'::jsonb)
                from public.loja_lista_permissao l join auth.users u on u.id = l.user_id where l.restaurant_id = r.id),
    'pedidos_receita', (select count(*) from public.pedidos_prescricao pp where pp.restaurant_id = r.id))
  from public.restaurants r
  where r.category = 'pharmacy'
  order by r.so_lista_permissao desc, r.name;
end $$;
revoke all on function public.admin_farmacias_listar() from public, anon;
grant execute on function public.admin_farmacias_listar() to authenticated;

create or replace function public.admin_farmacia_definir(p_restaurant_id text, p_modo text default null, p_so_lista boolean default null,
                                                          p_extra_pct numeric default null, p_extra_inicio timestamptz default null)
returns void
language plpgsql security definer
set search_path = public, pg_temp
as $$
begin
  if not public.is_admin() then
    raise exception 'Somente admin.' using errcode = '42501';
  end if;
  if p_modo is not null and p_modo not in ('desligado', 'so_lista', 'publico') then
    raise exception 'Modo inválido.' using errcode = 'P0001';
  end if;
  update public.restaurants set
    pharmacy_prescription_mode = coalesce(p_modo, pharmacy_prescription_mode),
    so_lista_permissao = coalesce(p_so_lista, so_lista_permissao),
    partner_extra_commission_pct = coalesce(p_extra_pct, partner_extra_commission_pct),
    partner_extra_commission_starts_at = coalesce(p_extra_inicio, partner_extra_commission_starts_at)
  where id = p_restaurant_id and category = 'pharmacy';
  if not found then raise exception 'Farmácia não encontrada.' using errcode = 'P0002'; end if;
  begin
    insert into public.admin_audit_log (admin_id, action, entity_type, entity_id_text, details)
    values (auth.uid(), 'farmacia_definir', 'restaurant', p_restaurant_id,
            jsonb_build_object('modo', p_modo, 'so_lista', p_so_lista, 'extra_pct', p_extra_pct, 'extra_inicio', p_extra_inicio));
  exception when others then raise notice 'admin_audit_log: %', sqlerrm;
  end;
end $$;
revoke all on function public.admin_farmacia_definir(text, text, boolean, numeric, timestamptz) from public, anon;
grant execute on function public.admin_farmacia_definir(text, text, boolean, numeric, timestamptz) to authenticated;

create or replace function public.admin_loja_lista_permissao_listar(p_restaurant_id text)
returns setof text
language plpgsql stable security definer
set search_path = public, pg_temp
as $$
begin
  if not public.is_admin() then raise exception 'Somente admin.' using errcode = '42501'; end if;
  return query select u.email::text from public.loja_lista_permissao l join auth.users u on u.id = l.user_id
                where l.restaurant_id = p_restaurant_id order by 1;
end $$;
revoke all on function public.admin_loja_lista_permissao_listar(text) from public, anon;
grant execute on function public.admin_loja_lista_permissao_listar(text) to authenticated;

-- Substitui a lista pelos emails dados; devolve os emails que não correspondem a nenhuma conta.
create or replace function public.admin_loja_lista_permissao_definir(p_restaurant_id text, p_emails text[])
returns setof text
language plpgsql security definer
set search_path = public, pg_temp
as $$
begin
  if not public.is_admin() then raise exception 'Somente admin.' using errcode = '42501'; end if;
  if not exists (select 1 from public.restaurants where id = p_restaurant_id) then
    raise exception 'Loja não encontrada.' using errcode = 'P0002';
  end if;
  delete from public.loja_lista_permissao l
   where l.restaurant_id = p_restaurant_id
     and l.user_id not in (select u.id from auth.users u where lower(u.email) = any (select lower(btrim(e)) from unnest(p_emails) e));
  insert into public.loja_lista_permissao (restaurant_id, user_id, motivo, criado_por)
  select p_restaurant_id, u.id, 'painel admin', auth.uid()
    from auth.users u where lower(u.email) = any (select lower(btrim(e)) from unnest(p_emails) e)
  on conflict do nothing;
  begin
    insert into public.admin_audit_log (admin_id, action, entity_type, entity_id_text, details)
    values (auth.uid(), 'loja_lista_permissao', 'restaurant', p_restaurant_id, jsonb_build_object('emails', p_emails));
  exception when others then raise notice 'admin_audit_log: %', sqlerrm;
  end;
  return query select e from unnest(p_emails) e
                where nullif(btrim(e), '') is not null
                  and not exists (select 1 from auth.users u where lower(u.email) = lower(btrim(e)));
end $$;
revoke all on function public.admin_loja_lista_permissao_definir(text, text[]) from public, anon;
grant execute on function public.admin_loja_lista_permissao_definir(text, text[]) to authenticated;

-- Abrir ao público: tira a lista de permissão e começa a contar os meses sem comissão.
-- Não força a conformidade (nome legal, NIF, IBAN, autocertificação): se faltar, o gatilho recusa e diz o quê.
create or replace function public.admin_farmacia_abrir(p_restaurant_id text)
returns void
language plpgsql security definer
set search_path = public, pg_temp
as $$
declare v_meses integer := public._setting_int('pharmacy_extra_commission_months', 3);
begin
  if not public.is_admin() then raise exception 'Somente admin.' using errcode = '42501'; end if;
  update public.restaurants set
    so_lista_permissao = false,
    coming_soon = false,
    aberta_ao_publico_em = coalesce(aberta_ao_publico_em, now()),
    partner_extra_commission_starts_at = coalesce(partner_extra_commission_starts_at,
      case when partner_extra_commission_pct is not null then now() + make_interval(months => v_meses) end)
  where id = p_restaurant_id and category = 'pharmacy';
  if not found then raise exception 'Farmácia não encontrada.' using errcode = 'P0002'; end if;
  begin
    insert into public.admin_audit_log (admin_id, action, entity_type, entity_id_text, details)
    values (auth.uid(), 'farmacia_abrir', 'restaurant', p_restaurant_id, jsonb_build_object('meses_sem_comissao', v_meses));
  exception when others then raise notice 'admin_audit_log: %', sqlerrm;
  end;
end $$;
revoke all on function public.admin_farmacia_abrir(text) from public, anon;
grant execute on function public.admin_farmacia_abrir(text) to authenticated;
