-- =============================================================================
-- Serviço "Imprimir documentos" e "Personalizados" — missão a3-guarda-16-11, parte 2
-- (ponto 5 da caixa 114; Bloco 2 da caixa 111). Motor genérico: serve qualquer loja que
-- imprima, ligado loja a loja (impressao_lojas.ligado). Primeira loja: a3-guarda.
--
-- Esqueleto copiado do envio de receita das farmácias (pedidos_prescricao, 11/11):
--  - ficheiros num bucket PRIVADO (impressoes), cada cliente na sua pasta, links assinados;
--  - a loja lê só os ficheiros dos pedidos dela (impressao_pode_ler_ficheiro);
--  - avisos pelo sininho + notify-partner (toque persistente) / notify-client;
--  - limpeza dos ficheiros 30 dias depois de concluído (Edge impressoes-limpeza, pg_cron).
--  - DINHEIRO: como na receita, numa loja ESCONDIDA (so_lista_permissao) o pedido é de TESTE
--    (is_demo = true, nada é cobrado). Numa loja aberta ao público o pedido real ainda NÃO está
--    ligado à cobrança: recusa com IMPRESSAO_REAL_POR_LIGAR. Ligar a cobrança é Lista Vermelha.
--
-- Preço: tabela da loja (impressao_precos, em cêntimos, preço de BALCÃO, editável pela loja no
-- painel do parceiro e por nós no admin). Valores provisórios da caixa 111, marcados
-- provisorio = true até a A3 mandar os dela. O cliente vê o mesmo esquema de preço da loja:
-- artigo = balcão × fator_cliente (1,15 na A3, igual ao catálogo; NÃO editável no painel) e a
-- taxa de serviço e a de entrega vêm da função oficial pricing_calculate (nada de fórmula nova).
-- =============================================================================

-- 1. Lojas com o serviço -------------------------------------------------------
create table if not exists public.impressao_lojas (
  restaurant_id text primary key references public.restaurants(id) on delete cascade,
  ligado boolean not null default false,
  personalizados_ligado boolean not null default false,
  fator_cliente numeric not null default 1.15 check (fator_cliente between 1 and 2),
  permite_levantar boolean not null default true,
  permite_entrega boolean not null default true,
  max_ficheiros int not null default 10 check (max_ficheiros between 1 and 30),
  max_paginas int not null default 500 check (max_paginas between 1 and 5000),
  atualizado_em timestamptz not null default now(),
  atualizado_por uuid
);

-- 2. Tabela de preços por loja (cêntimos, preço de balcão) ----------------------
create table if not exists public.impressao_precos (
  restaurant_id text not null references public.restaurants(id) on delete cascade,
  chave text not null check (chave in (
    'a4_pb_face', 'a4_cor_face', 'a3_fator_pct',
    'papel_cartolina_folha', 'papel_fotografico_folha',
    'acab_agrafar', 'acab_argolas', 'acab_plastificar_a4', 'acab_plastificar_a3')),
  valor int not null check (valor >= 0),
  provisorio boolean not null default true,
  atualizado_em timestamptz not null default now(),
  atualizado_por uuid,
  primary key (restaurant_id, chave)
);

-- 3. Pedidos --------------------------------------------------------------------
create table if not exists public.pedidos_impressao (
  id uuid primary key default gen_random_uuid(),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  restaurant_id text not null references public.restaurants(id),
  user_id uuid not null references auth.users(id),
  tipo text not null check (tipo in ('impressao', 'personalizado')),
  estado text not null default 'enviado' check (estado in (
    'enviado', 'orcamentado', 'aceite', 'pronto', 'entregue', 'recusado', 'cancelado', 'expirado')),
  -- impressão
  ficheiros jsonb not null default '[]'::jsonb, -- [{path, nome, paginas, tipo}]
  tamanho text check (tamanho in ('A4', 'A3')),
  cor boolean,
  frente_verso boolean,
  papel text check (papel in ('normal', 'cartolina', 'fotografico')),
  copias int check (copias between 1 and 500),
  intervalo text, -- null = todas; ex.: "1-3, 5"
  paginas int, -- páginas a imprimir por cópia (somadas todos os ficheiros)
  folhas int, -- folhas por cópia
  acabamento text check (acabamento in ('nenhum', 'agrafar', 'argolas', 'plastificar')),
  -- personalizado
  product_id text references public.products(id),
  texto_personalizado text,
  foto_path text,
  -- entrega
  modo text not null default 'levantar' check (modo in ('levantar', 'entrega')),
  morada text, lat double precision, lng double precision,
  nota text,
  -- dinheiro (cêntimos). preco_provisorio = calculado com a tabela provisória
  artigo_balcao_cents int,
  artigo_cents int,
  taxa_servico_cents int,
  taxa_entrega_cents int,
  total_cents int,
  preco_provisorio boolean not null default false,
  metodo_pagamento text check (metodo_pagamento in ('card', 'mbway', 'cash')),
  is_demo boolean not null default false,
  codigo_levantamento text,
  -- resposta da loja
  motivo_recusa text,
  respondido_por uuid, respondido_em timestamptz,
  pronto_em timestamptz, entregue_em timestamptz,
  cancelado_por uuid, cancelado_em timestamptz,
  dados_apagados_em timestamptz,
  -- impressão sem ficheiros não existe (menos depois da limpeza RGPD, que os apaga)
  constraint impressao_tem_ficheiros
    check (tipo <> 'impressao' or dados_apagados_em is not null or jsonb_array_length(ficheiros) > 0)
);
create index if not exists pedidos_impressao_loja_idx on public.pedidos_impressao (restaurant_id, created_at desc);
create index if not exists pedidos_impressao_user_idx on public.pedidos_impressao (user_id, created_at desc);
create index if not exists pedidos_impressao_estado_idx on public.pedidos_impressao (estado);

-- Produtos personalizáveis (canecas, t-shirts…): pedem foto + texto e vão a orçamento.
alter table public.products add column if not exists personalizavel boolean not null default false;

-- 4. RLS -----------------------------------------------------------------------
alter table public.impressao_lojas enable row level security;
alter table public.impressao_precos enable row level security;
alter table public.pedidos_impressao enable row level security;
revoke all on public.impressao_lojas, public.impressao_precos, public.pedidos_impressao from public, anon, authenticated;
grant select on public.impressao_lojas, public.impressao_precos to authenticated;
grant select on public.pedidos_impressao to authenticated;
grant all on public.impressao_lojas, public.impressao_precos, public.pedidos_impressao to service_role;

drop policy if exists impressao_lojas_ler on public.impressao_lojas;
create policy impressao_lojas_ler on public.impressao_lojas for select to authenticated
  using (not (restaurant_id = any(coalesce((select public.lojas_escondidas_para_mim()), '{}'::text[]))));
drop policy if exists impressao_precos_ler on public.impressao_precos;
create policy impressao_precos_ler on public.impressao_precos for select to authenticated
  using (not (restaurant_id = any(coalesce((select public.lojas_escondidas_para_mim()), '{}'::text[]))));
drop policy if exists pedidos_impressao_ler on public.pedidos_impressao;
create policy pedidos_impressao_ler on public.pedidos_impressao for select to authenticated
  using (user_id = auth.uid() or public.is_admin()
         or exists (select 1 from public.restaurants r where r.id = restaurant_id
                     and (r.user_id = auth.uid() or r.user_ = auth.uid())));

-- 5. Bucket privado ------------------------------------------------------------
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('impressoes', 'impressoes', false, 26214400, array['application/pdf', 'image/jpeg', 'image/png'])
on conflict (id) do update set public = false, file_size_limit = excluded.file_size_limit,
  allowed_mime_types = excluded.allowed_mime_types;

create or replace function public.impressao_pode_ler_ficheiro(p_nome text)
returns boolean language sql stable security definer set search_path to 'public', 'pg_temp' as $$
  select auth.uid() is not null and (
    split_part(p_nome, '/', 1) = auth.uid()::text
    or public.is_admin()
    or exists (
      select 1 from public.pedidos_impressao pi
        join public.restaurants r on r.id = pi.restaurant_id
       where (r.user_id = auth.uid() or r.user_ = auth.uid())
         and (p_nome = pi.foto_path or exists (select 1 from jsonb_array_elements(pi.ficheiros) f where f->>'path' = p_nome))
    )
  );
$$;
revoke all on function public.impressao_pode_ler_ficheiro(text) from public, anon;
grant execute on function public.impressao_pode_ler_ficheiro(text) to authenticated;

drop policy if exists impressoes_inserir_propria_pasta on storage.objects;
create policy impressoes_inserir_propria_pasta on storage.objects for insert to authenticated
  with check (bucket_id = 'impressoes' and split_part(name, '/', 1) = auth.uid()::text);
drop policy if exists impressoes_ler on storage.objects;
create policy impressoes_ler on storage.objects for select to authenticated
  using (bucket_id = 'impressoes' and public.impressao_pode_ler_ficheiro(name));

-- 6. Preço -------------------------------------------------------------------
-- Conta o preço de balcão de uma impressão a partir da tabela da loja. Devolve cêntimos.
create or replace function public._impressao_preco_balcao(
  p_restaurant_id text, p_tamanho text, p_cor boolean, p_frente_verso boolean, p_papel text,
  p_copias int, p_paginas int, p_acabamento text)
returns jsonb language plpgsql stable security definer set search_path to 'public', 'pg_temp' as $$
declare
  v jsonb; v_prov boolean;
  v_folhas int; v_face int; v_a3 int; v_imp bigint; v_papel bigint := 0; v_acab bigint := 0; v_total bigint;
  v_falta text;
begin
  select jsonb_object_agg(chave, valor), bool_or(provisorio) into v, v_prov
    from public.impressao_precos where restaurant_id = p_restaurant_id;
  if v is null then raise exception 'SEM_TABELA: Esta loja ainda não tem tabela de preços de impressão.' using errcode = 'P0001'; end if;
  select string_agg(k, ', ') into v_falta
    from unnest(array['a4_pb_face','a4_cor_face','a3_fator_pct','papel_cartolina_folha','papel_fotografico_folha',
                      'acab_agrafar','acab_argolas','acab_plastificar_a4','acab_plastificar_a3']) k
   where not (v ? k);
  if v_falta is not null then
    raise exception 'TABELA_INCOMPLETA: Falta na tabela de preços: %', v_falta using errcode = 'P0001';
  end if;
  if p_paginas is null or p_paginas < 1 then raise exception 'SEM_PAGINAS: Não há páginas para imprimir.' using errcode = 'P0001'; end if;
  if p_copias is null or p_copias < 1 then raise exception 'COPIAS: Escolha pelo menos 1 cópia.' using errcode = 'P0001'; end if;

  v_folhas := case when coalesce(p_frente_verso, false) then ceil(p_paginas / 2.0)::int else p_paginas end;
  v_face := case when coalesce(p_cor, false) then (v->>'a4_cor_face')::int else (v->>'a4_pb_face')::int end;
  v_a3 := case when p_tamanho = 'A3' then (v->>'a3_fator_pct')::int else 100 end;
  v_imp := round(p_paginas::numeric * v_face * v_a3 / 100.0) * p_copias;
  if p_papel = 'cartolina' then v_papel := v_folhas::bigint * (v->>'papel_cartolina_folha')::int * p_copias;
  elsif p_papel = 'fotografico' then v_papel := v_folhas::bigint * (v->>'papel_fotografico_folha')::int * p_copias;
  end if;
  v_acab := case coalesce(p_acabamento, 'nenhum')
    when 'agrafar' then (v->>'acab_agrafar')::int * p_copias
    when 'argolas' then (v->>'acab_argolas')::int * p_copias
    when 'plastificar' then v_folhas::bigint * p_copias *
      (case when p_tamanho = 'A3' then (v->>'acab_plastificar_a3')::int else (v->>'acab_plastificar_a4')::int end)
    else 0 end;
  v_total := v_imp + v_papel + v_acab;
  return jsonb_build_object('folhas', v_folhas, 'impressao_cents', v_imp, 'papel_cents', v_papel,
                            'acabamento_cents', v_acab, 'balcao_cents', v_total, 'provisorio', coalesce(v_prov, false));
end $$;
revoke all on function public._impressao_preco_balcao(text, text, boolean, boolean, text, int, int, text) from public, anon, authenticated;

-- Taxas ao cliente pela função oficial (pricing_calculate). Devolve cêntimos.
create or replace function public._impressao_taxas(p_restaurant_id text, p_artigo_cents int, p_modo text, p_lat double precision, p_lng double precision)
returns jsonb language plpgsql stable security definer set search_path to 'public', 'pg_temp' as $$
declare r record; v_km numeric := 0; v_pc record;
begin
  select lat, lng into r from public.restaurants where id = p_restaurant_id;
  if p_modo = 'entrega' then
    if p_lat is null or p_lng is null then raise exception 'SEM_MORADA: Indique a morada de entrega.' using errcode = 'P0001'; end if;
    v_km := round(public._haversine_km(r.lat::double precision, r.lng::double precision, p_lat, p_lng)::numeric, 2);
  end if;
  select * into v_pc from public.pricing_calculate('restaurant', p_artigo_cents / 100.0, v_km, true, false, false, 0);
  return jsonb_build_object(
    'distancia_km', v_km,
    'taxa_servico_cents', round(v_pc.service_fee * 100)::int,
    'taxa_entrega_cents', case when p_modo = 'entrega' then round(v_pc.delivery_fee * 100)::int else 0 end);
end $$;
revoke all on function public._impressao_taxas(text, int, text, double precision, double precision) from public, anon, authenticated;

-- O cliente vê o preço ANTES de pagar.
create or replace function public.impressao_cotar(p_restaurant_id text, p_opcoes jsonb)
returns jsonb language plpgsql stable security definer set search_path to 'public', 'pg_temp' as $$
declare v_loja public.impressao_lojas; v_b jsonb; v_art int; v_t jsonb;
begin
  if p_restaurant_id = any(public.lojas_escondidas_para_mim()) then
    raise exception 'NAO_ENCONTRADO: Loja não encontrada.' using errcode = 'P0002';
  end if;
  select * into v_loja from public.impressao_lojas where restaurant_id = p_restaurant_id and ligado;
  if not found then raise exception 'SERVICO_DESLIGADO: Esta loja não tem o serviço de impressão.' using errcode = 'P0001'; end if;
  v_b := public._impressao_preco_balcao(p_restaurant_id, p_opcoes->>'tamanho', (p_opcoes->>'cor')::boolean,
           (p_opcoes->>'frente_verso')::boolean, p_opcoes->>'papel', (p_opcoes->>'copias')::int,
           (p_opcoes->>'paginas')::int, p_opcoes->>'acabamento');
  v_art := round((v_b->>'balcao_cents')::int * v_loja.fator_cliente)::int;
  v_t := public._impressao_taxas(p_restaurant_id, v_art, coalesce(p_opcoes->>'modo', 'levantar'),
           (p_opcoes->>'lat')::double precision, (p_opcoes->>'lng')::double precision);
  return v_b || v_t || jsonb_build_object('artigo_cents', v_art,
    'total_cents', v_art + (v_t->>'taxa_servico_cents')::int + (v_t->>'taxa_entrega_cents')::int);
end $$;
revoke all on function public.impressao_cotar(text, jsonb) from public, anon;
grant execute on function public.impressao_cotar(text, jsonb) to authenticated;

-- 7. Avisos (igual a _prescricao_avisar) -----------------------------------------
create or replace function public._impressao_avisar(p_id uuid, p_para text, p_tipo text, p_titulo text, p_corpo text)
returns void language plpgsql security definer set search_path to 'public', 'pg_temp' as $$
declare v record; v_dono uuid; v_url text; v_key text;
begin
  select pi.user_id, pi.restaurant_id into v from public.pedidos_impressao pi where pi.id = p_id;
  if not found then return; end if;
  select coalesce(r.user_id, r.user_) into v_dono from public.restaurants r where r.id = v.restaurant_id;
  begin
    perform public._push_in_app_notification(case when p_para = 'cliente' then v.user_id else v_dono end,
                                             p_tipo, p_titulo, p_corpo, p_id::text);
  exception when others then raise notice 'impressao sininho: %', sqlerrm;
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
  exception when others then raise notice 'impressao push: %', sqlerrm;
  end;
end $$;
revoke all on function public._impressao_avisar(uuid, text, text, text, text) from public, anon, authenticated;

-- 8. Cliente -------------------------------------------------------------------
create or replace function public.impressao_criar(p_restaurant_id text, p_dados jsonb)
returns jsonb language plpgsql security definer set search_path to 'public', 'pg_temp' as $$
declare
  v_uid uuid := auth.uid(); v_loja public.impressao_lojas; v_escondida boolean; v_tipo text := coalesce(p_dados->>'tipo', 'impressao');
  v_modo text := coalesce(p_dados->>'modo', 'levantar'); v_metodo text := p_dados->>'metodo';
  v_fich jsonb := coalesce(p_dados->'ficheiros', '[]'::jsonb); f jsonb; v_q jsonb; v_id uuid; v_cod text;
  v_prod record;
begin
  if v_uid is null then raise exception 'SEM_SESSAO: Tem de entrar na sua conta.' using errcode = '42501'; end if;
  if p_restaurant_id = any(public.lojas_escondidas_para_mim()) then
    raise exception 'NAO_ENCONTRADO: Loja não encontrada.' using errcode = 'P0002';
  end if;
  select * into v_loja from public.impressao_lojas where restaurant_id = p_restaurant_id and ligado;
  if not found then raise exception 'SERVICO_DESLIGADO: Esta loja não tem o serviço de impressão.' using errcode = 'P0001'; end if;
  select so_lista_permissao into v_escondida from public.restaurants where id = p_restaurant_id;
  if not coalesce(v_escondida, false) then
    -- Loja aberta ao público: a cobrança real ainda não está ligada (Lista Vermelha).
    raise exception 'IMPRESSAO_REAL_POR_LIGAR: Os pedidos de impressão pela app ainda não estão disponíveis nesta loja.' using errcode = 'P0001';
  end if;
  if v_modo = 'levantar' and not v_loja.permite_levantar then raise exception 'MODO: Esta loja não tem levantamento.' using errcode = 'P0001'; end if;
  if v_modo = 'entrega' and not v_loja.permite_entrega then raise exception 'MODO: Esta loja não faz entregas de impressões.' using errcode = 'P0001'; end if;
  if v_metodo is not null and v_metodo not in ('card', 'mbway', 'cash') then
    raise exception 'METODO_INVALIDO: Escolha cartão, MB Way ou dinheiro.' using errcode = 'P0001';
  end if;
  v_cod := public._prescricao_codigo(6);

  if v_tipo = 'impressao' then
    if jsonb_typeof(v_fich) <> 'array' or jsonb_array_length(v_fich) = 0 then
      raise exception 'SEM_FICHEIROS: Escolha pelo menos um ficheiro.' using errcode = 'P0001';
    end if;
    if jsonb_array_length(v_fich) > v_loja.max_ficheiros then
      raise exception 'FICHEIROS: No máximo % ficheiros por pedido.', v_loja.max_ficheiros using errcode = 'P0001';
    end if;
    for f in select * from jsonb_array_elements(v_fich) loop
      if split_part(f->>'path', '/', 1) <> v_uid::text then
        raise exception 'FICHEIRO_INVALIDO: Ficheiro inválido.' using errcode = 'P0001';
      end if;
    end loop;
    if v_metodo is null then raise exception 'METODO_INVALIDO: Escolha cartão, MB Way ou dinheiro.' using errcode = 'P0001'; end if;
    if (p_dados->>'paginas')::int > v_loja.max_paginas then
      raise exception 'PAGINAS: No máximo % páginas por pedido. Para mais, peça orçamento.', v_loja.max_paginas using errcode = 'P0001';
    end if;
    -- o preço calcula-se aqui, no servidor (nunca o que a app mandar)
    v_q := public.impressao_cotar(p_restaurant_id, p_dados);
    insert into public.pedidos_impressao (restaurant_id, user_id, tipo, ficheiros, tamanho, cor, frente_verso, papel,
      copias, intervalo, paginas, folhas, acabamento, modo, morada, lat, lng, nota,
      artigo_balcao_cents, artigo_cents, taxa_servico_cents, taxa_entrega_cents, total_cents, preco_provisorio,
      metodo_pagamento, is_demo, codigo_levantamento)
    values (p_restaurant_id, v_uid, 'impressao', v_fich, coalesce(p_dados->>'tamanho', 'A4'), coalesce((p_dados->>'cor')::boolean, false),
      coalesce((p_dados->>'frente_verso')::boolean, false), coalesce(p_dados->>'papel', 'normal'), (p_dados->>'copias')::int,
      nullif(trim(p_dados->>'intervalo'), ''), (p_dados->>'paginas')::int, (v_q->>'folhas')::int, coalesce(p_dados->>'acabamento', 'nenhum'),
      v_modo, nullif(trim(p_dados->>'morada'), ''), (p_dados->>'lat')::double precision, (p_dados->>'lng')::double precision,
      left(nullif(trim(p_dados->>'nota'), ''), 500),
      (v_q->>'balcao_cents')::int, (v_q->>'artigo_cents')::int, (v_q->>'taxa_servico_cents')::int, (v_q->>'taxa_entrega_cents')::int,
      (v_q->>'total_cents')::int, coalesce((v_q->>'provisorio')::boolean, false), v_metodo, true, v_cod)
    returning id into v_id;
    perform public._impressao_avisar(v_id, 'loja', 'impressao_nova', 'Novo pedido de impressão',
      (p_dados->>'paginas') || ' pág. × ' || (p_dados->>'copias') || ' cópia(s) · ' ||
      case when v_modo = 'entrega' then 'entrega' else 'levantar na loja' end);
  else
    if not v_loja.personalizados_ligado then raise exception 'SERVICO_DESLIGADO: Esta loja não tem personalizados.' using errcode = 'P0001'; end if;
    select id, name, personalizavel, restaurant_id into v_prod from public.products where id = p_dados->>'product_id';
    if not found or v_prod.restaurant_id <> p_restaurant_id or not v_prod.personalizavel then
      raise exception 'PRODUTO: Este produto não é personalizável.' using errcode = 'P0001';
    end if;
    if nullif(p_dados->>'foto_path', '') is not null and split_part(p_dados->>'foto_path', '/', 1) <> v_uid::text then
      raise exception 'FICHEIRO_INVALIDO: Ficheiro inválido.' using errcode = 'P0001';
    end if;
    insert into public.pedidos_impressao (restaurant_id, user_id, tipo, product_id, texto_personalizado, foto_path,
      copias, modo, morada, lat, lng, nota, is_demo, codigo_levantamento)
    values (p_restaurant_id, v_uid, 'personalizado', v_prod.id, left(nullif(trim(p_dados->>'texto'), ''), 300),
      nullif(p_dados->>'foto_path', ''), greatest(1, coalesce((p_dados->>'copias')::int, 1)), v_modo,
      nullif(trim(p_dados->>'morada'), ''), (p_dados->>'lat')::double precision, (p_dados->>'lng')::double precision,
      left(nullif(trim(p_dados->>'nota'), ''), 500), true, v_cod)
    returning id into v_id;
    perform public._impressao_avisar(v_id, 'loja', 'personalizado_novo', 'Pedido de personalizado',
      v_prod.name || ' — mande o preço e a prova ao cliente.');
  end if;
  return jsonb_build_object('id', v_id, 'is_demo', true, 'codigo_levantamento', v_cod) || coalesce(v_q, '{}'::jsonb);
end $$;
revoke all on function public.impressao_criar(text, jsonb) from public, anon;
grant execute on function public.impressao_criar(text, jsonb) to authenticated;

-- Personalizado: o cliente aceita o orçamento da loja.
create or replace function public.impressao_confirmar_orcamento(p_id uuid, p_metodo text)
returns jsonb language plpgsql security definer set search_path to 'public', 'pg_temp' as $$
declare v public.pedidos_impressao; v_t jsonb;
begin
  select * into v from public.pedidos_impressao where id = p_id for update;
  if not found or v.user_id is distinct from auth.uid() then raise exception 'NAO_ENCONTRADO: Pedido não encontrado.' using errcode = 'P0002'; end if;
  if v.estado <> 'orcamentado' then raise exception 'NAO_CONFIRMAVEL: Este pedido já não pode ser confirmado.' using errcode = 'P0001'; end if;
  if p_metodo not in ('card', 'mbway', 'cash') then raise exception 'METODO_INVALIDO: Escolha cartão, MB Way ou dinheiro.' using errcode = 'P0001'; end if;
  v_t := public._impressao_taxas(v.restaurant_id, v.artigo_cents, v.modo, v.lat, v.lng);
  update public.pedidos_impressao set estado = 'aceite', metodo_pagamento = p_metodo,
    taxa_servico_cents = (v_t->>'taxa_servico_cents')::int, taxa_entrega_cents = (v_t->>'taxa_entrega_cents')::int,
    total_cents = v.artigo_cents + (v_t->>'taxa_servico_cents')::int + (v_t->>'taxa_entrega_cents')::int, updated_at = now()
  where id = p_id returning * into v;
  perform public._impressao_avisar(p_id, 'loja', 'personalizado_confirmado', 'O cliente aceitou o orçamento', 'Pode produzir.');
  return jsonb_build_object('estado', v.estado, 'total_cents', v.total_cents, 'is_demo', v.is_demo);
end $$;
revoke all on function public.impressao_confirmar_orcamento(uuid, text) from public, anon;
grant execute on function public.impressao_confirmar_orcamento(uuid, text) to authenticated;

create or replace function public.impressao_cancelar(p_id uuid)
returns void language plpgsql security definer set search_path to 'public', 'pg_temp' as $$
declare v public.pedidos_impressao;
begin
  select * into v from public.pedidos_impressao where id = p_id for update;
  if not found or v.user_id is distinct from auth.uid() then raise exception 'NAO_ENCONTRADO: Pedido não encontrado.' using errcode = 'P0002'; end if;
  if v.estado not in ('enviado', 'orcamentado') then
    raise exception 'NAO_CANCELAVEL: A loja já começou o seu pedido. Fale com a loja.' using errcode = 'P0001';
  end if;
  update public.pedidos_impressao set estado = 'cancelado', cancelado_por = auth.uid(), cancelado_em = now(), updated_at = now() where id = p_id;
  perform public._impressao_avisar(p_id, 'loja', 'impressao_cancelada', 'Pedido cancelado pelo cliente', 'Não precisa de fazer nada.');
end $$;
revoke all on function public.impressao_cancelar(uuid) from public, anon;
grant execute on function public.impressao_cancelar(uuid) to authenticated;

-- 9. Loja (dono) e admin ----------------------------------------------------------
create or replace function public._impressao_e_dono(p_restaurant_id text)
returns boolean language sql stable security definer set search_path to 'public', 'pg_temp' as $$
  select public.is_admin() or exists (select 1 from public.restaurants r where r.id = p_restaurant_id
                                       and (r.user_id = auth.uid() or r.user_ = auth.uid()));
$$;
revoke all on function public._impressao_e_dono(text) from public, anon;
grant execute on function public._impressao_e_dono(text) to authenticated;

-- p_acao: 'aceitar' | 'recusar' | 'orcamentar' (personalizado, com p_valor_cents) | 'pronto' | 'entregue'
create or replace function public.impressao_loja_responder(p_id uuid, p_acao text, p_valor_cents int default null, p_motivo text default null, p_codigo text default null)
returns jsonb language plpgsql security definer set search_path to 'public', 'pg_temp' as $$
declare v public.pedidos_impressao; v_novo text; v_fator numeric;
begin
  select * into v from public.pedidos_impressao where id = p_id for update;
  if not found or not public._impressao_e_dono(v.restaurant_id) then
    raise exception 'NAO_ENCONTRADO: Pedido não encontrado.' using errcode = 'P0002';
  end if;
  if p_acao = 'aceitar' and v.estado = 'enviado' and v.tipo = 'impressao' then
    v_novo := 'aceite';
  elsif p_acao = 'orcamentar' and v.estado = 'enviado' and v.tipo = 'personalizado' then
    if p_valor_cents is null or p_valor_cents <= 0 then raise exception 'VALOR: Indique o preço.' using errcode = 'P0001'; end if;
    select fator_cliente into v_fator from public.impressao_lojas where restaurant_id = v.restaurant_id;
    update public.pedidos_impressao set artigo_balcao_cents = p_valor_cents,
      artigo_cents = round(p_valor_cents * coalesce(v_fator, 1))::int where id = p_id;
    v_novo := 'orcamentado';
  elsif p_acao = 'recusar' and v.estado in ('enviado', 'orcamentado', 'aceite') then
    v_novo := 'recusado';
  elsif p_acao = 'pronto' and v.estado = 'aceite' then
    v_novo := 'pronto';
  elsif p_acao = 'entregue' and v.estado = 'pronto' then
    if v.modo = 'levantar' and coalesce(p_codigo, '') <> coalesce(v.codigo_levantamento, '') then
      raise exception 'CODIGO: O código de levantamento não confere.' using errcode = 'P0001';
    end if;
    v_novo := 'entregue';
  else
    raise exception 'ESTADO: Não é possível fazer isso a este pedido agora.' using errcode = 'P0001';
  end if;
  update public.pedidos_impressao set estado = v_novo, updated_at = now(),
    respondido_por = coalesce(respondido_por, auth.uid()), respondido_em = coalesce(respondido_em, now()),
    motivo_recusa = case when v_novo = 'recusado' then left(nullif(trim(p_motivo), ''), 300) else motivo_recusa end,
    pronto_em = case when v_novo = 'pronto' then now() else pronto_em end,
    entregue_em = case when v_novo = 'entregue' then now() else entregue_em end
  where id = p_id;
  if v_novo = 'aceite' then
    perform public._impressao_avisar(p_id, 'cliente', 'impressao_aceite', 'A loja aceitou o seu pedido', 'Já está a ser preparado.');
  elsif v_novo = 'orcamentado' then
    perform public._impressao_avisar(p_id, 'cliente', 'personalizado_orcamento', 'Tem o preço do seu personalizado', 'Abra o pedido para ver e confirmar.');
  elsif v_novo = 'recusado' then
    perform public._impressao_avisar(p_id, 'cliente', 'impressao_recusada', 'A loja não pode fazer o pedido', coalesce(nullif(trim(p_motivo), ''), 'Fale com a loja para saber mais.'));
  elsif v_novo = 'pronto' then
    perform public._impressao_avisar(p_id, 'cliente', 'impressao_pronta',
      case when v.modo = 'entrega' then 'O seu pedido está pronto' else 'Pode levantar o seu pedido' end,
      case when v.modo = 'entrega' then 'Vai seguir para a sua morada.' else 'Mostre o código ' || v.codigo_levantamento || ' na loja.' end);
  end if;
  return jsonb_build_object('estado', v_novo);
end $$;
revoke all on function public.impressao_loja_responder(uuid, text, int, text, text) from public, anon;
grant execute on function public.impressao_loja_responder(uuid, text, int, text, text) to authenticated;

-- A loja (ou o admin) muda a sua tabela de preços. Deixa de ser provisória.
create or replace function public.impressao_precos_definir(p_restaurant_id text, p_precos jsonb)
returns void language plpgsql security definer set search_path to 'public', 'pg_temp' as $$
declare k text; val jsonb;
begin
  if not public._impressao_e_dono(p_restaurant_id) then raise exception 'SEM_PERMISSAO: Sem permissão.' using errcode = '42501'; end if;
  for k, val in select * from jsonb_each(coalesce(p_precos, '{}'::jsonb)) loop
    if (val #>> '{}')::int < 0 then raise exception 'VALOR: Os preços não podem ser negativos.' using errcode = 'P0001'; end if;
    insert into public.impressao_precos (restaurant_id, chave, valor, provisorio, atualizado_em, atualizado_por)
    values (p_restaurant_id, k, (val #>> '{}')::int, false, now(), auth.uid())
    on conflict (restaurant_id, chave) do update set valor = excluded.valor, provisorio = false,
      atualizado_em = now(), atualizado_por = auth.uid();
  end loop;
  begin
    insert into public.admin_audit_log (admin_id, action, entity_type, entity_id_text, details)
    values (auth.uid(), 'impressao_precos_definir', 'restaurant', p_restaurant_id, p_precos);
  exception when others then raise notice 'admin_audit_log: %', sqlerrm;
  end;
end $$;
revoke all on function public.impressao_precos_definir(text, jsonb) from public, anon;
grant execute on function public.impressao_precos_definir(text, jsonb) to authenticated;

-- Admin: ligar/desligar por loja (o fator_cliente NÃO muda aqui: é dinheiro).
create or replace function public.admin_impressao_loja_definir(p_restaurant_id text, p_ligado boolean, p_personalizados boolean default null,
  p_permite_levantar boolean default null, p_permite_entrega boolean default null)
returns void language plpgsql security definer set search_path to 'public', 'pg_temp' as $$
begin
  if not public.is_admin() then raise exception 'Somente admin.' using errcode = '42501'; end if;
  insert into public.impressao_lojas (restaurant_id, ligado, personalizados_ligado, atualizado_em, atualizado_por)
  values (p_restaurant_id, p_ligado, coalesce(p_personalizados, false), now(), auth.uid())
  on conflict (restaurant_id) do update set ligado = p_ligado,
    personalizados_ligado = coalesce(p_personalizados, impressao_lojas.personalizados_ligado),
    permite_levantar = coalesce(p_permite_levantar, impressao_lojas.permite_levantar),
    permite_entrega = coalesce(p_permite_entrega, impressao_lojas.permite_entrega),
    atualizado_em = now(), atualizado_por = auth.uid();
  begin
    insert into public.admin_audit_log (admin_id, action, entity_type, entity_id_text, details)
    values (auth.uid(), 'impressao_loja_definir', 'restaurant', p_restaurant_id,
            jsonb_build_object('ligado', p_ligado, 'personalizados', p_personalizados));
  exception when others then raise notice 'admin_audit_log: %', sqlerrm;
  end;
end $$;
revoke all on function public.admin_impressao_loja_definir(text, boolean, boolean, boolean, boolean) from public, anon;
grant execute on function public.admin_impressao_loja_definir(text, boolean, boolean, boolean, boolean) to authenticated;

create or replace function public.admin_impressao_listar(p_estado text default null, p_restaurant_id text default null, p_limite int default 200)
returns setof public.pedidos_impressao language plpgsql stable security definer set search_path to 'public', 'pg_temp' as $$
begin
  if not public.is_admin() then raise exception 'Somente admin.' using errcode = '42501'; end if;
  return query select * from public.pedidos_impressao
   where (p_estado is null or estado = p_estado) and (p_restaurant_id is null or restaurant_id = p_restaurant_id)
   order by created_at desc limit greatest(1, least(coalesce(p_limite, 200), 1000));
end $$;
revoke all on function public.admin_impressao_listar(text, text, int) from public, anon;
grant execute on function public.admin_impressao_listar(text, text, int) to authenticated;

-- 10. Limpeza RGPD: ficheiros apagados 30 dias depois de concluído ----------------
create or replace function public.impressao_para_limpar(p_limite int default 200)
returns table(id uuid, caminhos text[]) language sql stable security definer set search_path to 'public', 'pg_temp' as $$
  select pi.id,
         array_remove(array(select f->>'path' from jsonb_array_elements(pi.ficheiros) f) || pi.foto_path, null)
    from public.pedidos_impressao pi
   where pi.dados_apagados_em is null
     and pi.estado in ('entregue', 'recusado', 'cancelado', 'expirado')
     and coalesce(pi.entregue_em, pi.cancelado_em, pi.respondido_em, pi.updated_at) <= now() - interval '30 days'
   limit greatest(1, least(coalesce(p_limite, 200), 1000));
$$;
revoke all on function public.impressao_para_limpar(int) from public, anon, authenticated;
grant execute on function public.impressao_para_limpar(int) to service_role;

create or replace function public.impressao_marcar_dados_apagados(p_ids uuid[])
returns int language plpgsql security definer set search_path to 'public', 'pg_temp' as $$
declare n int;
begin
  update public.pedidos_impressao set dados_apagados_em = now(), ficheiros = '[]'::jsonb, foto_path = null,
    texto_personalizado = null, morada = null, lat = null, lng = null
   where id = any(p_ids) and dados_apagados_em is null;
  get diagnostics n = row_count;
  return n;
end $$;
revoke all on function public.impressao_marcar_dados_apagados(uuid[]) from public, anon, authenticated;
grant execute on function public.impressao_marcar_dados_apagados(uuid[]) to service_role;

select cron.schedule('impressoes-limpeza', '50 3 * * *', $c$
  select net.http_post(
    url := (select decrypted_secret from vault.decrypted_secrets where name = 'project_url') || '/functions/v1/impressoes-limpeza',
    headers := jsonb_build_object('Authorization', 'Bearer ' || (select decrypted_secret from vault.decrypted_secrets where name = 'service_role_key'),
                                  'Content-Type', 'application/json'),
    body := '{}'::jsonb, timeout_milliseconds := 120000);
$c$);

-- 11. A3 Guarda: serviço ligado (loja escondida = só pedidos de teste) e tabela provisória ----
insert into public.impressao_lojas (restaurant_id, ligado, personalizados_ligado)
values ('a3-guarda', true, true) on conflict (restaurant_id) do nothing;
insert into public.impressao_precos (restaurant_id, chave, valor, provisorio) values
  ('a3-guarda', 'a4_pb_face', 10, true),
  ('a3-guarda', 'a4_cor_face', 50, true),
  ('a3-guarda', 'a3_fator_pct', 200, true),
  ('a3-guarda', 'papel_cartolina_folha', 20, true),
  ('a3-guarda', 'papel_fotografico_folha', 80, true),
  ('a3-guarda', 'acab_agrafar', 20, true),
  ('a3-guarda', 'acab_argolas', 250, true),
  ('a3-guarda', 'acab_plastificar_a4', 150, true),
  ('a3-guarda', 'acab_plastificar_a3', 250, true)
on conflict (restaurant_id, chave) do nothing;
