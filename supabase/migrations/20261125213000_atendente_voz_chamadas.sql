-- =============================================================================
-- ATENDENTE DE VOZ DO TELEFONE DA BORA (missão atendente-voz-2026-11-25, bloco B4)
--
-- Porquê: quem liga para a Bora (937 501 673) passa a ser atendido 24h por um
-- assistente virtual (Zadarma → Asterisk → Pipecat na VPS → Claude). Tudo o que
-- acontece numa chamada fica guardado aqui e aparece no painel admin, ecrã
-- "Chamadas (atendente de voz)".
--
--   1. (sem cópia: nada de existente é alterado)
--   2. Definições (painel) na tabela própria voz_definicoes: ligar/desligar,
--      saudação, voz, motor, tetos. Não ficam em platform_settings porque a
--      trava do modo automático recusa escrita direta nessa tabela e a função
--      existente (admin_update_setting) só muda chaves que já existem.
--   3. chamadas_voz (uma linha por chamada) e chamadas_voz_falas (a transcrição,
--      fala a fala). RLS: só o admin lê e marca; escreve só o service_role (a
--      Edge Function voz-ferramentas).
--   4. voz_ferramentas_tokens: senha própria da Edge voz-ferramentas (só o
--      sha256; ativo=false cancela). A senha em claro fica só no .env da
--      central na VPS.
--   5. Bucket privado chamadas-voz (áudio, 90 dias; apaga a Edge, chamada pelo
--      cron diário voz-limpar-audios).
--   6. Funções da Edge (só service_role): identificar quem liga, pedidos
--      recentes, abrir/gravar fala/fechar chamada, gasto do dia, áudios velhos.
--   7. Funções do painel (só admin, auditadas).
--
-- Zona verde: nenhuma escrita em pedidos, carteiras, tokens ou dinheiro. Os
-- tetos são do gasto da API Claude do próprio atendente, não de clientes.
-- Idempotente.
-- =============================================================================

-- ─── 2. Definições ────────────────────────────────────────────────────────────
create table if not exists public.voz_definicoes (
  key          text primary key check (key like 'voz\_%'),
  value        jsonb not null,
  description  text,
  category     text not null default 'atendente_voz',
  updated_at   timestamptz not null default now(),
  updated_by   uuid
);
comment on table public.voz_definicoes is
  'Definições do atendente de voz do telefone (25/11/2026): ligar/desligar, saudação, voz, motor e tetos de gasto da IA. Muda-se no painel (admin_voz_definir); a Edge voz-ferramentas lê-as.';
alter table public.voz_definicoes enable row level security;
revoke all on public.voz_definicoes from anon;
-- Sem blocos DO: a trava do modo automático recusa DO numa migração com
-- "grant execute". Tabelas novas: as regras criam-se uma vez.
create policy voz_definicoes_admin_ler on public.voz_definicoes
  for select to authenticated using (public.is_admin());

insert into public.voz_definicoes (key, value, description, category)
values
  ('voz_atendente_ativo', 'false'::jsonb,
   'Atendente de voz do telefone da Bora (assistente virtual). Desligado = quem liga ouve uma mensagem curta a pedir para escrever para o e-mail de suporte. Só se liga depois das chamadas de teste (bloco B7).',
   'atendente_voz'),
  ('voz_saudacao', '"Olá, está a falar com o assistente virtual da Bora. A chamada é gravada para qualidade. Em que posso ajudar?"'::jsonb,
   'Primeira frase de cada chamada. Tem de dizer que é um assistente virtual e que a chamada é gravada (AI Act art. 50 e RGPD).',
   'atendente_voz'),
  ('voz_voz', '"pt-PT-RaquelNeural"'::jsonb,
   'Voz usada (edge-tts, sempre pt-PT): pt-PT-RaquelNeural (feminina) ou pt-PT-DuarteNeural (masculina).',
   'atendente_voz'),
  ('voz_motor', '"claude-opus-5-5"'::jsonb,
   'Cérebro do atendente (modelo Claude, pelo crédito da API dos robôs).',
   'atendente_voz'),
  ('voz_motor_reserva', '"claude-sonnet-5-5"'::jsonb,
   'Cérebro de reserva quando o teto do dia passa ou o principal falha.',
   'atendente_voz'),
  ('voz_opus_teto_chamada_eur', '0.60'::jsonb,
   'Gasto máximo de IA por chamada, em euros (custo da API Claude). Passou: o atendente despede-se e passa à equipa.',
   'atendente_voz'),
  ('voz_opus_teto_dia_eur', '5'::jsonb,
   'Gasto máximo de IA por dia (Lisboa), em euros. Passou: as chamadas seguintes usam o motor de reserva.',
   'atendente_voz'),
  ('voz_duracao_max_min', '15'::jsonb,
   'Duração máxima de uma chamada, em minutos.',
   'atendente_voz'),
  ('voz_email_suporte', '"suporte@boraguarda.com"'::jsonb,
   'E-mail que o atendente manda escrever quando passa o caso à equipa.',
   'atendente_voz'),
  ('voz_linhas_simultaneas', '1'::jsonb,
   'Quantas chamadas ao mesmo tempo (a VPS tem 1 CPU). A seguinte ouve "a linha está ocupada".',
   'atendente_voz')
on conflict (key) do nothing;

-- ─── 3. Tabelas ───────────────────────────────────────────────────────────────
create table if not exists public.chamadas_voz (
  id                      uuid primary key default gen_random_uuid(),
  criado_em               timestamptz not null default now(),
  inicio                  timestamptz not null default now(),
  fim                     timestamptz,
  duracao_s               integer,
  telefone                text,
  user_id                 uuid,
  papel                   text not null default 'desconhecido'
                          check (papel in ('cliente','estafeta','parceiro','desconhecido')),
  nome_identificado       text,
  linha                   text not null default 'zadarma',
  sip_call_id             text unique,
  motor                   text,
  custo_usd               numeric(10,4) not null default 0,
  tokens_entrada          integer not null default 0,
  tokens_saida            integer not null default 0,
  estado                  text not null default 'a_decorrer'
                          check (estado in ('a_decorrer','resolvido','escalado','perdida','ocupado','erro')),
  etiquetas               text[] not null default '{}',
  resumo                  text,
  gravacao_consentida     boolean not null default true,
  audio_path              text,
  primeira_palavra_ms     integer,
  teste                   boolean not null default false,
  revisto_em              timestamptz,
  revisto_por             uuid,
  nota_admin              text
);
comment on table public.chamadas_voz is
  'Atendente de voz (25/11/2026): uma linha por chamada para o telefone da Bora — quem ligou, cliente/estafeta/parceiro reconhecido pelo número, duração, custo da IA, estado (resolvido/escalado), etiquetas, resumo de 3 linhas e caminho do áudio (bucket chamadas-voz, 90 dias).';
create index if not exists chamadas_voz_inicio_idx on public.chamadas_voz (inicio desc);
create index if not exists chamadas_voz_estado_idx on public.chamadas_voz (estado, inicio desc);

create table if not exists public.chamadas_voz_falas (
  id                bigint generated always as identity primary key,
  chamada_id        uuid not null references public.chamadas_voz(id) on delete cascade,
  criado_em         timestamptz not null default now(),
  quem              text not null check (quem in ('cliente','atendente','sistema','ferramenta')),
  texto             text not null check (length(texto) between 1 and 8000),
  ms_desde_inicio   integer
);
comment on table public.chamadas_voz_falas is
  'Transcrição de cada chamada do atendente de voz, fala a fala (cliente, atendente, sistema, ferramenta).';
create index if not exists chamadas_voz_falas_chamada_idx on public.chamadas_voz_falas (chamada_id, id);

alter table public.chamadas_voz enable row level security;
alter table public.chamadas_voz_falas enable row level security;

create policy chamadas_voz_admin_ler on public.chamadas_voz
  for select to authenticated using (public.is_admin());
create policy chamadas_voz_admin_marcar on public.chamadas_voz
  for update to authenticated using (public.is_admin()) with check (public.is_admin());
create policy chamadas_voz_falas_admin_ler on public.chamadas_voz_falas
  for select to authenticated using (public.is_admin());

revoke all on public.chamadas_voz, public.chamadas_voz_falas from anon;

-- ─── 4. Senha da Edge voz-ferramentas ─────────────────────────────────────────
create table if not exists public.voz_ferramentas_tokens (
  hash        text primary key,
  nome        text not null,
  ativo       boolean not null default true,
  criado_em   timestamptz not null default now(),
  ultimo_uso  timestamptz
);
comment on table public.voz_ferramentas_tokens is
  'Senha própria da Edge voz-ferramentas (só o sha256). ativo=false cancela. A senha em claro vive só no .env da central na VPS.';
alter table public.voz_ferramentas_tokens enable row level security;
revoke all on public.voz_ferramentas_tokens from anon, authenticated;

-- A senha cria-a quem instala a central na VPS (voz/atendente/LEIA-ME.md):
-- gera-a lá (openssl rand -hex 32), grava só o sha256 aqui e o texto no .env
-- da central. A trava do modo automático recusa ler o cofre (vault).

-- ─── 5. Bucket privado do áudio ───────────────────────────────────────────────
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('chamadas-voz', 'chamadas-voz', false, 52428800,
        array['audio/wav','audio/x-wav','audio/mpeg','audio/ogg','audio/opus'])
on conflict (id) do nothing;

create policy chamadas_voz_audio_admin_ler on storage.objects
  for select to authenticated
  using (bucket_id = 'chamadas-voz' and public.is_admin());

-- ─── 6. Funções da Edge (só service_role) ─────────────────────────────────────
-- Os últimos 9 dígitos do número (Portugal): "+351 937 501 673" → 937501673.
create or replace function public.voz_tel9(p_tel text)
returns text language sql immutable as $$
  select right(regexp_replace(coalesce(p_tel, ''), '\D', '', 'g'), 9)
$$;

-- Quem liga? Procura o número em parceiros, estafetas e clientes (por esta ordem).
-- O número NÃO prova a identidade: o atendente confirma nome + um dado do pedido.
create or replace function public.voz_identificar(p_tel text)
returns jsonb language plpgsql stable security definer set search_path = public as $$
declare
  v9 text := public.voz_tel9(p_tel);
  r record;
begin
  if length(v9) < 9 then
    return jsonb_build_object('papel', 'desconhecido');
  end if;
  select id, user_id, name, is_partner, coming_soon into r from public.restaurants
   where public.voz_tel9(phone) = v9 or public.voz_tel9(alert_call_phone) = v9
   order by is_partner desc nulls last limit 1;
  if found then
    return jsonb_build_object('papel', 'parceiro', 'user_id', r.user_id,
      'nome', r.name, 'loja_id', r.id, 'parceiro', coalesce(r.is_partner, false));
  end if;
  select id, user_id, name into r from public.drivers
   where public.voz_tel9(phone) = v9 and deleted_at is null limit 1;
  if found then
    return jsonb_build_object('papel', 'estafeta', 'user_id', r.user_id,
      'nome', split_part(coalesce(r.name, ''), ' ', 1), 'estafeta_id', r.id);
  end if;
  select id, name into r from public.users where public.voz_tel9(phone) = v9 limit 1;
  if found then
    return jsonb_build_object('papel', 'cliente', 'user_id', r.id,
      'nome', split_part(coalesce(r.name, ''), ' ', 1));
  end if;
  return jsonb_build_object('papel', 'desconhecido');
end $$;

-- Pedidos dos últimos 14 dias de quem liga (pelo número do pedido ou pela conta).
-- Só o que o próprio cliente pode ouvir: sem moradas completas nem dados de outros.
create or replace function public.voz_pedidos_recentes(p_tel text, p_user_id uuid default null)
returns jsonb language sql stable security definer set search_path = public as $$
  select coalesce(jsonb_agg(x order by x->>'criado_em' desc), '[]'::jsonb) from (
    select jsonb_build_object(
      'pedido', left(o.id::text, 8),
      'criado_em', to_char(o.created_at at time zone 'Europe/Lisbon', 'DD/MM HH24:MI'),
      'estado', o.status,
      'tipo', o.service_type,
      'loja', r.name,
      'total_eur', coalesce(o.customer_total, o.total),
      'tem_estafeta', o.assigned_driver_id is not null,
      'estafeta_nome', (select split_part(coalesce(d.name, ''), ' ', 1) from public.drivers d
                         where d.user_id::text = o.assigned_driver_id or d.id::text = o.assigned_driver_id limit 1),
      'nome_no_pedido', split_part(coalesce(o.customer_name, ''), ' ', 1)
    ) x
    from public.orders o
    left join public.restaurants r on r.id = o.restaurant_id
    where o.created_at > now() - interval '14 days'
      and (public.voz_tel9(o.client_phone) = public.voz_tel9(p_tel)
           or (p_user_id is not null and o.user_id = p_user_id))
    order by o.created_at desc
    limit 5
  ) t
$$;

create or replace function public.voz_chamada_abrir(
  p_telefone text, p_sip_call_id text, p_motor text, p_teste boolean default false)
returns jsonb language plpgsql security definer set search_path = public as $$
declare
  v_id uuid;
  v_quem jsonb := public.voz_identificar(p_telefone);
begin
  insert into public.chamadas_voz (telefone, sip_call_id, motor, teste, papel, user_id, nome_identificado)
  values (p_telefone, nullif(p_sip_call_id, ''), p_motor, coalesce(p_teste, false),
          coalesce(v_quem->>'papel', 'desconhecido'),
          nullif(v_quem->>'user_id', '')::uuid, v_quem->>'nome')
  on conflict (sip_call_id) do update set motor = excluded.motor
  returning id into v_id;
  return jsonb_build_object('chamada_id', v_id, 'quem', v_quem);
end $$;

create or replace function public.voz_fala_gravar(
  p_chamada_id uuid, p_quem text, p_texto text, p_ms integer default null)
returns bigint language sql security definer set search_path = public as $$
  insert into public.chamadas_voz_falas (chamada_id, quem, texto, ms_desde_inicio)
  values (p_chamada_id, p_quem, left(p_texto, 8000), p_ms)
  returning id
$$;

create or replace function public.voz_chamada_fechar(
  p_chamada_id uuid, p_estado text, p_resumo text, p_etiquetas text[],
  p_custo_usd numeric, p_tokens_entrada integer, p_tokens_saida integer,
  p_audio_path text, p_primeira_palavra_ms integer, p_gravacao_consentida boolean)
returns jsonb language plpgsql security definer set search_path = public as $$
declare
  c public.chamadas_voz;
  v_rotulo text;
begin
  update public.chamadas_voz set
    fim = now(),
    duracao_s = greatest(0, extract(epoch from (now() - inicio))::int),
    estado = coalesce(nullif(p_estado, ''), 'resolvido'),
    resumo = p_resumo,
    etiquetas = coalesce(p_etiquetas, '{}'),
    custo_usd = coalesce(p_custo_usd, 0),
    tokens_entrada = coalesce(p_tokens_entrada, 0),
    tokens_saida = coalesce(p_tokens_saida, 0),
    audio_path = case when coalesce(p_gravacao_consentida, true) then p_audio_path else null end,
    primeira_palavra_ms = p_primeira_palavra_ms,
    gravacao_consentida = coalesce(p_gravacao_consentida, true)
  where id = p_chamada_id
  returning * into c;
  if not found then
    return jsonb_build_object('ok', false, 'erro', 'chamada nao existe');
  end if;

  v_rotulo := case c.papel when 'parceiro' then 'Parceiro' when 'estafeta' then 'Estafeta'
                           when 'cliente' then 'Cliente' else 'Número desconhecido' end;
  if c.teste then
    -- Chamadas de teste: aviso no painel, sem push no telemóvel.
    insert into public.admin_notifications (event_type, severity, entity_type, entity_id, summary, payload, deep_link)
    values ('chamada_voz', 'low', 'chamada_voz', c.id::text,
            '[TESTE] Chamada · ' || v_rotulo || ' · ' || coalesce(left(c.resumo, 140), 'sem resumo'),
            jsonb_build_object('chamada_id', c.id, 'estado', c.estado, 'teste', true),
            '/admin/chamadas/' || c.id::text);
  else
    begin
      perform public.notify_admin_urgent_push(
        'chamada_voz',
        case when c.estado = 'escalado' then '📞 CHAMADA PARA A EQUIPA · ' else '📞 Chamada · ' end
          || v_rotulo || coalesce(' ' || c.nome_identificado, '') || E'\n' || left(coalesce(c.resumo, ''), 160),
        'chamada_voz', c.id::text,
        jsonb_build_object('chamada_id', c.id, 'estado', c.estado, 'push_ref', 'chamada:' || c.id::text),
        '/admin/chamadas/' || c.id::text);
    exception when others then
      raise notice 'voz_chamada_fechar aviso falhou: %', sqlerrm;
    end;
  end if;
  return jsonb_build_object('ok', true, 'chamada_id', c.id, 'duracao_s', c.duracao_s, 'estado', c.estado);
end $$;

-- Gasto de IA do atendente hoje (dia de Lisboa), em USD.
create or replace function public.voz_gasto_hoje_usd()
returns numeric language sql stable security definer set search_path = public as $$
  select coalesce(sum(custo_usd), 0) from public.chamadas_voz
   where (inicio at time zone 'Europe/Lisbon')::date = (now() at time zone 'Europe/Lisbon')::date
$$;

-- Áudios com mais de 90 dias (a Edge apaga-os no Storage e limpa o caminho).
create or replace function public.voz_audios_expirados(p_limite integer default 200)
returns table (id uuid, audio_path text) language sql stable security definer set search_path = public as $$
  select id, audio_path from public.chamadas_voz
   where audio_path is not null and inicio < now() - interval '90 days'
   order by inicio limit greatest(1, least(coalesce(p_limite, 200), 1000))
$$;

create or replace function public.voz_audio_apagado(p_chamada_id uuid)
returns void language sql security definer set search_path = public as $$
  update public.chamadas_voz set audio_path = null where id = p_chamada_id
$$;

revoke all on function public.voz_identificar(text) from public, anon, authenticated;
revoke all on function public.voz_pedidos_recentes(text, uuid) from public, anon, authenticated;
revoke all on function public.voz_chamada_abrir(text, text, text, boolean) from public, anon, authenticated;
revoke all on function public.voz_fala_gravar(uuid, text, text, integer) from public, anon, authenticated;
revoke all on function public.voz_chamada_fechar(uuid, text, text, text[], numeric, integer, integer, text, integer, boolean) from public, anon, authenticated;
revoke all on function public.voz_gasto_hoje_usd() from public, anon, authenticated;
revoke all on function public.voz_audios_expirados(integer) from public, anon, authenticated;
revoke all on function public.voz_audio_apagado(uuid) from public, anon, authenticated;
grant execute on function public.voz_identificar(text), public.voz_pedidos_recentes(text, uuid),
  public.voz_chamada_abrir(text, text, text, boolean), public.voz_fala_gravar(uuid, text, text, integer),
  public.voz_chamada_fechar(uuid, text, text, text[], numeric, integer, integer, text, integer, boolean),
  public.voz_gasto_hoje_usd(), public.voz_audios_expirados(integer), public.voz_audio_apagado(uuid)
  to service_role;

-- ─── 7. Painel (só admin) ─────────────────────────────────────────────────────
create or replace function public.admin_chamadas_voz(
  p_estado text default null, p_limite integer default 100, p_incluir_teste boolean default true)
returns table (
  id uuid, inicio timestamptz, duracao_s integer, telefone text, papel text, nome_identificado text,
  estado text, etiquetas text[], resumo text, custo_usd numeric, motor text, tem_audio boolean,
  teste boolean, revisto_em timestamptz, falas integer)
language plpgsql stable security definer set search_path = public as $$
begin
  if not public.is_admin() then raise exception 'so admin' using errcode = '42501'; end if;
  return query
  select c.id, c.inicio, c.duracao_s, c.telefone, c.papel, c.nome_identificado, c.estado, c.etiquetas,
         c.resumo, c.custo_usd, c.motor, c.audio_path is not null, c.teste, c.revisto_em,
         (select count(*)::int from public.chamadas_voz_falas f where f.chamada_id = c.id)
    from public.chamadas_voz c
   where (p_estado is null or p_estado = '' or c.estado = p_estado)
     and (coalesce(p_incluir_teste, true) or not c.teste)
   order by c.inicio desc
   limit greatest(1, least(coalesce(p_limite, 100), 1000));
end $$;

create or replace function public.admin_chamada_voz(p_id uuid)
returns jsonb language plpgsql stable security definer set search_path = public as $$
declare v jsonb;
begin
  if not public.is_admin() then raise exception 'so admin' using errcode = '42501'; end if;
  select to_jsonb(c) || jsonb_build_object('falas', coalesce((
           select jsonb_agg(jsonb_build_object('quem', f.quem, 'texto', f.texto,
                  'ms', f.ms_desde_inicio, 'criado_em', f.criado_em) order by f.id)
             from public.chamadas_voz_falas f where f.chamada_id = c.id), '[]'::jsonb))
    into v from public.chamadas_voz c where c.id = p_id;
  return v;
end $$;

create or replace function public.admin_chamada_voz_marcar(p_id uuid, p_estado text, p_nota text default null)
returns jsonb language plpgsql security definer set search_path = public as $$
begin
  if not public.is_admin() then raise exception 'so admin' using errcode = '42501'; end if;
  if p_estado not in ('resolvido','escalado') then raise exception 'estado invalido'; end if;
  update public.chamadas_voz set estado = p_estado, nota_admin = coalesce(p_nota, nota_admin),
         revisto_em = now(), revisto_por = auth.uid()
   where id = p_id;
  perform public.log_admin_action('chamada_voz_marcar'::text, 'chamada_voz'::text, p_id::text,
    jsonb_build_object('estado', p_estado, 'nota', p_nota));
  return jsonb_build_object('ok', true);
end $$;

-- Definições do atendente (só as chaves voz_*, com validação simples).
create or replace function public.admin_voz_definir(p_key text, p_value jsonb)
returns jsonb language plpgsql security definer set search_path = public as $$
declare v_antes jsonb;
begin
  if not public.is_admin() then raise exception 'so admin' using errcode = '42501'; end if;
  if p_key not in ('voz_atendente_ativo','voz_saudacao','voz_voz','voz_motor','voz_motor_reserva',
                   'voz_opus_teto_chamada_eur','voz_opus_teto_dia_eur','voz_duracao_max_min',
                   'voz_email_suporte','voz_linhas_simultaneas') then
    raise exception 'definicao nao permitida: %', p_key;
  end if;
  if p_key = 'voz_atendente_ativo' and jsonb_typeof(p_value) <> 'boolean' then raise exception 'tem de ser verdadeiro/falso'; end if;
  if p_key in ('voz_opus_teto_chamada_eur','voz_opus_teto_dia_eur','voz_duracao_max_min','voz_linhas_simultaneas')
     and (jsonb_typeof(p_value) <> 'number' or (p_value)::text::numeric <= 0 or (p_value)::text::numeric > 100) then
    raise exception 'numero entre 0 e 100';
  end if;
  if p_key = 'voz_saudacao' and (jsonb_typeof(p_value) <> 'string'
     or p_value #>> '{}' not ilike '%assistente virtual%' or p_value #>> '{}' not ilike '%gravad%') then
    raise exception 'a saudacao tem de dizer "assistente virtual" e que a chamada e gravada (lei)';
  end if;
  if p_key = 'voz_voz' and p_value #>> '{}' not in ('pt-PT-RaquelNeural','pt-PT-DuarteNeural') then
    raise exception 'voz tem de ser pt-PT (RaquelNeural ou DuarteNeural)';
  end if;
  select value into v_antes from public.voz_definicoes where key = p_key;
  update public.voz_definicoes set value = p_value, updated_at = now(), updated_by = auth.uid() where key = p_key;
  perform public.log_admin_action('voz_definir'::text, 'voz_definicoes'::text, p_key,
    jsonb_build_object('antes', v_antes, 'depois', p_value));
  return jsonb_build_object('ok', true, 'key', p_key, 'value', p_value);
end $$;

revoke all on function public.admin_chamadas_voz(text, integer, boolean) from public, anon;
revoke all on function public.admin_chamada_voz(uuid) from public, anon;
revoke all on function public.admin_chamada_voz_marcar(uuid, text, text) from public, anon;
revoke all on function public.admin_voz_definir(text, jsonb) from public, anon;
grant execute on function public.admin_chamadas_voz(text, integer, boolean), public.admin_chamada_voz(uuid),
  public.admin_chamada_voz_marcar(uuid, text, text), public.admin_voz_definir(text, jsonb) to authenticated;

-- Tempo real da lista no painel.
-- (tabela nova: entra uma vez na publicação; a trava recusa DO com EXECUTE)
alter publication supabase_realtime add table public.chamadas_voz;
