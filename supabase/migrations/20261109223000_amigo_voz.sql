-- =============================================================================
-- O AMIGO — VOZ DO SERVIDOR (missão missao-pendencias-2026-11-09, bloco I)
--
-- Porquê: o Amigo fala com a voz do aparelho (flutter_tts / speechSynthesis). O
-- Safari do iPhone nem sempre tem voz pt-PT e o Amigo fica mudo (só legenda).
-- Nesse caso a app pede o áudio à Edge Function amigo-voz, que o gera na Google
-- Cloud Text-to-Speech (SEMPRE pt-PT, voz feminina Standard por defeito) e
-- guarda-o numa cache privada para as frases repetidas não gastarem caracteres.
--
--   1. Cópia das definições amigo_voz* ANTES de mexer (nada é apagado).
--   2. Quatro definições novas (painel /admin/assistente, separador Amigo Bora):
--        amigo_voz_servidor_ativo       false  (liga-se depois de pôr a chave)
--        amigo_voz_teto_dia             20000  caracteres gerados por dia
--        amigo_voz_teto_utilizador_dia  3000   caracteres gerados por cliente/dia
--        amigo_voz_nome                 "pt-PT-Standard-E"
--      Porquê 20000/dia: 20000 × 31 dias = 620 000/mês, 15,5 % do grátis
--      Standard (4 milhões/mês) e ainda dentro do grátis das vozes WaveNet/
--      Neural2 (1 milhão/mês) se um dia se trocar de voz. São ~130 frases novas
--      de 150 caracteres por dia; as repetidas (saudação, deixas) saem da cache
--      e não contam. O máximo aceite pelo painel é 133000/dia (4 M ÷ 30).
--   3. amigo_voz_consumo — por dia (Lisboa): pedidos e caracteres pedidos,
--      servidos da cache, gerados na Google, recusados (teto, limite, sem chave)
--      e erros. amigo_voz_uso_utilizador — caracteres gerados por cliente/dia
--      (o limite simples por cliente). RLS: só o admin lê; escreve só o
--      service_role (a Edge), pelas funções do ponto 5.
--   4. Bucket privado amigo-voz (cache dos MP3; só o service_role lá chega).
--   5. Funções da Edge (só service_role): amigo_voz_reservar, amigo_voz_contar.
--   6. Painel (só admin, auditado): admin_amigo_voz_overview,
--      admin_amigo_voz_definir (com log_admin_action).
--
-- Zona verde: nenhuma escrita em pedidos nem em dinheiro. Idempotente.
-- Funções novas fechadas a anon (e as da Edge também a authenticated).
-- =============================================================================

-- ─── 1. Cópia antes de mexer ──────────────────────────────────────────────────
create table if not exists public.bkp_platform_settings_amigo_voz_20261109 as
  select * from public.platform_settings where key like 'amigo\_voz%';

-- ─── 2. Definições ────────────────────────────────────────────────────────────
insert into public.platform_settings (key, value, description, category)
values
  ('amigo_voz_servidor_ativo', 'false'::jsonb,
   'Voz do servidor do Amigo (Google Cloud Text-to-Speech, pt-PT). Só é usada quando o aparelho não tem voz de Portugal (ex.: Safari do iPhone). Desligada = o Amigo fala por legenda nesses aparelhos, como antes. Ligar só depois de pôr o segredo GOOGLE_TTS_API_KEY na Edge amigo-voz.',
   'assistente'),
  ('amigo_voz_teto_dia', '20000'::jsonb,
   'Máximo de caracteres por dia enviados à Google para a voz do Amigo (as frases da cache não contam). Grátis por mês: 4 milhões nas vozes Standard, 1 milhão nas WaveNet/Neural2. Passou o teto: o Amigo volta à legenda até ao dia seguinte.',
   'assistente'),
  ('amigo_voz_teto_utilizador_dia', '3000'::jsonb,
   'Máximo de caracteres por cliente e por dia gerados na Google para a voz do Amigo (impede que uma só pessoa gaste o teto do dia).',
   'assistente'),
  ('amigo_voz_nome', '"pt-PT-Standard-E"'::jsonb,
   'Voz da Google usada pelo Amigo. Sempre pt-PT (nunca do Brasil). Padrão: pt-PT-Standard-E, feminina, a do maior grátis (4 milhões de caracteres/mês). Vozes pt-PT na lista da Google a 09/11/2026: Standard-E (feminina), Standard-F (masculina), Wavenet-E (feminina), Wavenet-F (masculina).',
   'assistente')
on conflict (key) do nothing;

-- ─── 3. Consumo ───────────────────────────────────────────────────────────────
create table if not exists public.amigo_voz_consumo (
  dia                  date primary key,
  pedidos              integer not null default 0,
  caracteres_pedidos   bigint  not null default 0,
  pedidos_cache        integer not null default 0,
  caracteres_cache     bigint  not null default 0,
  pedidos_gerados      integer not null default 0,
  caracteres_gerados   bigint  not null default 0,
  pedidos_recusados    integer not null default 0,
  caracteres_recusados bigint  not null default 0,
  erros                integer not null default 0,
  atualizado_em        timestamptz not null default now()
);
comment on table public.amigo_voz_consumo is
  'Voz do servidor do Amigo (09/11/2026): consumo por dia de Lisboa — pedidos, caracteres servidos da cache, gerados na Google (contam para o grátis), recusados (teto, limite por cliente, sem chave) e erros. Só contagens, sem texto.';

create table if not exists public.amigo_voz_uso_utilizador (
  dia                date not null,
  user_id            uuid not null references auth.users(id) on delete cascade,
  pedidos            integer not null default 0,
  caracteres_gerados integer not null default 0,
  primary key (dia, user_id)
);
comment on table public.amigo_voz_uso_utilizador is
  'Voz do servidor do Amigo: caracteres gerados na Google por cliente e por dia (limite amigo_voz_teto_utilizador_dia). Só contagens.';
create index if not exists amigo_voz_uso_utilizador_user_idx
  on public.amigo_voz_uso_utilizador (user_id, dia desc);

alter table public.amigo_voz_consumo enable row level security;
alter table public.amigo_voz_uso_utilizador enable row level security;

do $$
begin
  if not exists (select 1 from pg_policies where schemaname = 'public'
                  and tablename = 'amigo_voz_consumo' and policyname = 'amigo_voz_consumo_admin_le') then
    create policy amigo_voz_consumo_admin_le on public.amigo_voz_consumo
      for select to authenticated
      using (coalesce((select public.is_admin()), false));
  end if;
  if not exists (select 1 from pg_policies where schemaname = 'public'
                  and tablename = 'amigo_voz_uso_utilizador' and policyname = 'amigo_voz_uso_admin_le') then
    create policy amigo_voz_uso_admin_le on public.amigo_voz_uso_utilizador
      for select to authenticated
      using (coalesce((select public.is_admin()), false));
  end if;
end $$;

revoke all on public.amigo_voz_consumo from public, anon, authenticated;
revoke all on public.amigo_voz_uso_utilizador from public, anon, authenticated;
grant select on public.amigo_voz_consumo to authenticated;          -- a política deixa só o admin
grant select on public.amigo_voz_uso_utilizador to authenticated;   -- idem
grant all on public.amigo_voz_consumo to service_role;
grant all on public.amigo_voz_uso_utilizador to service_role;
revoke all on public.bkp_platform_settings_amigo_voz_20261109 from public, anon, authenticated;

-- ─── 4. Cache privada dos MP3 ─────────────────────────────────────────────────
-- Sem políticas em storage.objects para este bucket: só o service_role (a Edge) lê e grava.
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('amigo-voz', 'amigo-voz', false, 1048576, array['audio/mpeg'])
on conflict (id) do nothing;

-- ─── 5. Funções da Edge (só service_role) ─────────────────────────────────────
-- Leitura tolerante dos valores jsonb (número ou texto; true/"true").
create or replace function public._amigo_voz_num(p jsonb)
returns bigint
language sql
immutable
set search_path = public
as $$
  select case
    when p is null then null
    when jsonb_typeof(p) = 'number' then round((p #>> '{}')::numeric)::bigint
    when jsonb_typeof(p) = 'string' and (p #>> '{}') ~ '^\s*[0-9]+(\.[0-9]+)?\s*$'
      then round(trim(p #>> '{}')::numeric)::bigint
    else null
  end
$$;

create or replace function public._amigo_voz_bool(p jsonb)
returns boolean
language sql
immutable
set search_path = public
as $$
  select case
    when p is null then null
    when jsonb_typeof(p) = 'boolean' then (p #>> '{}')::boolean
    when jsonb_typeof(p) = 'string' then lower(trim(p #>> '{}')) in ('true', '1', 'sim')
    else null
  end
$$;

-- Antes de pedir à Google: confirma o interruptor, o teto do dia e o limite do
-- cliente, e reserva os caracteres (tudo na mesma linha bloqueada: dois pedidos
-- ao mesmo tempo não passam o teto). Devolve {ok, motivo?}.
create or replace function public.amigo_voz_reservar(p_user_id uuid, p_caracteres integer)
returns jsonb
language plpgsql
volatile
security definer
set search_path = public
as $$
declare
  v_dia     date := (now() at time zone 'Europe/Lisbon')::date;
  v_ativo   boolean;
  v_teto    bigint;
  v_teto_u  bigint;
  v_gerados bigint;
  v_user    bigint;
  v_motivo  text;
begin
  if p_user_id is null or coalesce(p_caracteres, 0) <= 0 then
    return jsonb_build_object('ok', false, 'motivo', 'invalido');
  end if;

  select coalesce(public._amigo_voz_bool(value), false) into v_ativo
    from public.platform_settings where key = 'amigo_voz_servidor_ativo';
  select public._amigo_voz_num(value) into v_teto
    from public.platform_settings where key = 'amigo_voz_teto_dia';
  select public._amigo_voz_num(value) into v_teto_u
    from public.platform_settings where key = 'amigo_voz_teto_utilizador_dia';
  v_ativo  := coalesce(v_ativo, false);
  v_teto   := greatest(coalesce(v_teto, 20000), 0);
  v_teto_u := greatest(coalesce(v_teto_u, 3000), 0);

  insert into public.amigo_voz_consumo (dia) values (v_dia) on conflict (dia) do nothing;
  select caracteres_gerados into v_gerados
    from public.amigo_voz_consumo where dia = v_dia for update;

  if not v_ativo then
    v_motivo := 'desligado';
  elsif v_gerados + p_caracteres > v_teto then
    v_motivo := 'teto';
  else
    select caracteres_gerados into v_user
      from public.amigo_voz_uso_utilizador where dia = v_dia and user_id = p_user_id;
    if coalesce(v_user, 0) + p_caracteres > v_teto_u then
      v_motivo := 'limite_utilizador';
    end if;
  end if;

  if v_motivo is not null then
    update public.amigo_voz_consumo
       set pedidos = pedidos + 1,
           caracteres_pedidos = caracteres_pedidos + p_caracteres,
           pedidos_recusados = pedidos_recusados + 1,
           caracteres_recusados = caracteres_recusados + p_caracteres,
           atualizado_em = now()
     where dia = v_dia;
    return jsonb_build_object('ok', false, 'motivo', v_motivo, 'teto', v_teto, 'gerados', v_gerados);
  end if;

  update public.amigo_voz_consumo
     set pedidos = pedidos + 1,
         caracteres_pedidos = caracteres_pedidos + p_caracteres,
         pedidos_gerados = pedidos_gerados + 1,
         caracteres_gerados = caracteres_gerados + p_caracteres,
         atualizado_em = now()
   where dia = v_dia;
  insert into public.amigo_voz_uso_utilizador (dia, user_id, pedidos, caracteres_gerados)
  values (v_dia, p_user_id, 1, p_caracteres)
  on conflict (dia, user_id) do update
     set pedidos = public.amigo_voz_uso_utilizador.pedidos + 1,
         caracteres_gerados = public.amigo_voz_uso_utilizador.caracteres_gerados + excluded.caracteres_gerados;
  return jsonb_build_object('ok', true, 'teto', v_teto, 'gerados', v_gerados + p_caracteres);
end;
$$;

-- Conta o que não passou pela reserva: 'cache' (servido da cache, não gasta),
-- 'erro' (a Google falhou depois de reservar: devolve os caracteres) e
-- 'sem_chave' (falta o segredo GOOGLE_TTS_API_KEY: conta como recusado).
create or replace function public.amigo_voz_contar(p_user_id uuid, p_caracteres integer, p_tipo text)
returns void
language plpgsql
volatile
security definer
set search_path = public
as $$
declare
  v_dia date := (now() at time zone 'Europe/Lisbon')::date;
  v_n   integer := greatest(coalesce(p_caracteres, 0), 0);
begin
  if p_tipo is null or p_tipo not in ('cache', 'erro', 'sem_chave') then
    raise exception 'tipo_invalido: %', p_tipo;
  end if;
  insert into public.amigo_voz_consumo (dia) values (v_dia) on conflict (dia) do nothing;

  if p_tipo = 'cache' then
    update public.amigo_voz_consumo
       set pedidos = pedidos + 1,
           caracteres_pedidos = caracteres_pedidos + v_n,
           pedidos_cache = pedidos_cache + 1,
           caracteres_cache = caracteres_cache + v_n,
           atualizado_em = now()
     where dia = v_dia;
  elsif p_tipo = 'erro' then
    update public.amigo_voz_consumo
       set erros = erros + 1,
           pedidos_gerados = greatest(pedidos_gerados - 1, 0),
           caracteres_gerados = greatest(caracteres_gerados - v_n, 0),
           atualizado_em = now()
     where dia = v_dia;
    if p_user_id is not null then
      update public.amigo_voz_uso_utilizador
         set caracteres_gerados = greatest(caracteres_gerados - v_n, 0)
       where dia = v_dia and user_id = p_user_id;
    end if;
  else
    update public.amigo_voz_consumo
       set pedidos = pedidos + 1,
           caracteres_pedidos = caracteres_pedidos + v_n,
           pedidos_recusados = pedidos_recusados + 1,
           caracteres_recusados = caracteres_recusados + v_n,
           atualizado_em = now()
     where dia = v_dia;
  end if;
end;
$$;

revoke all on function public._amigo_voz_num(jsonb) from public, anon;
revoke all on function public._amigo_voz_bool(jsonb) from public, anon;
grant execute on function public._amigo_voz_num(jsonb) to authenticated, service_role;
grant execute on function public._amigo_voz_bool(jsonb) to authenticated, service_role;
revoke all on function public.amigo_voz_reservar(uuid, integer) from public, anon, authenticated;
revoke all on function public.amigo_voz_contar(uuid, integer, text) from public, anon, authenticated;
grant execute on function public.amigo_voz_reservar(uuid, integer) to service_role;
grant execute on function public.amigo_voz_contar(uuid, integer, text) to service_role;

-- ─── 6. Painel admin ──────────────────────────────────────────────────────────
create or replace function public.admin_amigo_voz_overview(p_dias integer default 30)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_dias    integer := greatest(1, least(coalesce(p_dias, 30), 365));
  v_hoje    date := (now() at time zone 'Europe/Lisbon')::date;
  v_mes     date := date_trunc('month', (now() at time zone 'Europe/Lisbon'))::date;
  v_voz     text;
  v_gratis  bigint;
  v_teto    bigint;
  v_hoje_j  jsonb;
  v_mes_j   jsonb;
begin
  if not coalesce(public.is_admin(), false) then
    raise exception 'admin_required';
  end if;

  select coalesce(nullif(trim(value #>> '{}'), ''), 'pt-PT-Standard-E') into v_voz
    from public.platform_settings where key = 'amigo_voz_nome';
  v_voz := coalesce(v_voz, 'pt-PT-Standard-E');
  -- grátis por mês da Google: Standard 4 milhões; WaveNet/Neural2 e outras 1 milhão
  v_gratis := case when v_voz ilike '%standard%' then 4000000 else 1000000 end;
  select public._amigo_voz_num(value) into v_teto
    from public.platform_settings where key = 'amigo_voz_teto_dia';

  select jsonb_build_object(
           'pedidos', coalesce(sum(pedidos), 0),
           'caracteres_pedidos', coalesce(sum(caracteres_pedidos), 0),
           'pedidos_cache', coalesce(sum(pedidos_cache), 0),
           'caracteres_cache', coalesce(sum(caracteres_cache), 0),
           'pedidos_gerados', coalesce(sum(pedidos_gerados), 0),
           'caracteres_gerados', coalesce(sum(caracteres_gerados), 0),
           'pedidos_recusados', coalesce(sum(pedidos_recusados), 0),
           'caracteres_recusados', coalesce(sum(caracteres_recusados), 0),
           'erros', coalesce(sum(erros), 0))
    into v_hoje_j
    from public.amigo_voz_consumo where dia = v_hoje;

  select jsonb_build_object(
           'pedidos', coalesce(sum(pedidos), 0),
           'caracteres_pedidos', coalesce(sum(caracteres_pedidos), 0),
           'pedidos_cache', coalesce(sum(pedidos_cache), 0),
           'caracteres_cache', coalesce(sum(caracteres_cache), 0),
           'pedidos_gerados', coalesce(sum(pedidos_gerados), 0),
           'caracteres_gerados', coalesce(sum(caracteres_gerados), 0),
           'pedidos_recusados', coalesce(sum(pedidos_recusados), 0),
           'caracteres_recusados', coalesce(sum(caracteres_recusados), 0),
           'erros', coalesce(sum(erros), 0))
    into v_mes_j
    from public.amigo_voz_consumo where dia >= v_mes and dia <= v_hoje;

  return jsonb_build_object(
    'hoje', v_hoje_j,
    'mes', v_mes_j,
    'dia', to_char(v_hoje, 'YYYY-MM-DD'),
    'mes_inicio', to_char(v_mes, 'YYYY-MM-DD'),
    'gratis_mes', v_gratis,
    'pct_gratis_mes', round(100.0 * (v_mes_j ->> 'caracteres_gerados')::numeric / v_gratis, 2),
    'pct_teto_hoje', case when coalesce(v_teto, 0) <= 0 then null
                          else round(100.0 * (v_hoje_j ->> 'caracteres_gerados')::numeric / v_teto, 1) end,
    'clientes_hoje', (select count(*) from public.amigo_voz_uso_utilizador where dia = v_hoje),
    'por_dia', coalesce((select jsonb_agg(jsonb_build_object(
                           'dia', to_char(dia, 'YYYY-MM-DD'),
                           'gerados', caracteres_gerados,
                           'cache', caracteres_cache,
                           'recusados', caracteres_recusados,
                           'erros', erros) order by dia)
                           from public.amigo_voz_consumo
                          where dia > v_hoje - v_dias), '[]'::jsonb),
    'definicoes', jsonb_build_object(
       'amigo_voz_servidor_ativo', coalesce((select public._amigo_voz_bool(value) from public.platform_settings where key = 'amigo_voz_servidor_ativo'), false),
       'amigo_voz_teto_dia', v_teto,
       'amigo_voz_teto_utilizador_dia', (select public._amigo_voz_num(value) from public.platform_settings where key = 'amigo_voz_teto_utilizador_dia'),
       'amigo_voz_nome', v_voz)
  );
end;
$$;

-- Muda o interruptor, os tetos e a voz (só o que vier preenchido). Fica na auditoria.
create or replace function public.admin_amigo_voz_definir(
  p_ativo boolean default null,
  p_teto_dia integer default null,
  p_teto_utilizador_dia integer default null,
  p_voz text default null
)
returns jsonb
language plpgsql
volatile
security definer
set search_path = public
as $$
declare
  v_antes  jsonb;
  v_depois jsonb;
  v_mudar  jsonb;
  v_k      text;
  v_v      jsonb;
  v_quem   uuid := auth.uid();
begin
  if not coalesce(public.is_admin(), false) then
    raise exception 'admin_required';
  end if;
  if p_ativo is null and p_teto_dia is null and p_teto_utilizador_dia is null and p_voz is null then
    raise exception 'nada_para_mudar';
  end if;
  if p_teto_dia is not null and (p_teto_dia < 0 or p_teto_dia > 133000) then
    raise exception 'teto_dia_invalido: entre 0 e 133000 (4 milhões ÷ 30)';
  end if;
  if p_teto_utilizador_dia is not null and (p_teto_utilizador_dia < 0 or p_teto_utilizador_dia > 20000) then
    raise exception 'teto_utilizador_dia_invalido: entre 0 e 20000';
  end if;
  if p_voz is not null and p_voz !~ '^pt-PT-[A-Za-z0-9]+-[A-Z]$' then
    raise exception 'voz_invalida: só vozes pt-PT (ex.: pt-PT-Standard-E)';
  end if;

  select jsonb_object_agg(key, value) into v_antes
    from public.platform_settings
   where key in ('amigo_voz_servidor_ativo', 'amigo_voz_teto_dia', 'amigo_voz_teto_utilizador_dia', 'amigo_voz_nome');

  v_mudar := jsonb_strip_nulls(jsonb_build_object(
    'amigo_voz_servidor_ativo', to_jsonb(p_ativo),
    'amigo_voz_teto_dia', to_jsonb(p_teto_dia),
    'amigo_voz_teto_utilizador_dia', to_jsonb(p_teto_utilizador_dia),
    'amigo_voz_nome', to_jsonb(p_voz)));
  for v_k, v_v in select key, value from jsonb_each(v_mudar) loop
    update public.platform_settings
       set value = v_v, updated_at = now(), updated_by = v_quem
     where key = v_k;
    if not found then
      insert into public.platform_settings (key, value, description, category, updated_at, updated_by)
      values (v_k, v_v, 'Voz do servidor do Amigo (criada pelo painel).', 'assistente', now(), v_quem);
    end if;
  end loop;

  select jsonb_object_agg(key, value) into v_depois
    from public.platform_settings
   where key in ('amigo_voz_servidor_ativo', 'amigo_voz_teto_dia', 'amigo_voz_teto_utilizador_dia', 'amigo_voz_nome');

  perform public.log_admin_action('amigo_voz_definir'::text, 'platform_setting'::text, 'amigo_voz'::text,
                                  jsonb_build_object('antes', v_antes, 'depois', v_depois));
  return v_depois;
end;
$$;

revoke all on function public.admin_amigo_voz_overview(integer) from public, anon;
revoke all on function public.admin_amigo_voz_definir(boolean, integer, integer, text) from public, anon;
grant execute on function public.admin_amigo_voz_overview(integer) to authenticated;
grant execute on function public.admin_amigo_voz_definir(boolean, integer, integer, text) to authenticated;
