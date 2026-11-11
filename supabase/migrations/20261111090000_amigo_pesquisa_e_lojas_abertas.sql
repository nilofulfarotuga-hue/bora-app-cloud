-- =============================================================================
-- AMIGO BORA — PESQUISA NA INTERNET, LOJAS ABERTAS E PARCEIRO PRIMEIRO
-- (missão fechar-tudo-2026-11-11, bloco 2 — Edge client-assistant v12)
--
-- Porquê (conversas de 10/11 com o Amigo): "quais restaurantes estão abertos?" → "não tenho a lista";
-- agenda da Guarda e tempo → "não sei, vou passar à equipa"; açaí → açaí congelado do Continente com o
-- Goola (parceiro, açaí) aberto até às 22h; "então eu quero" → "não consegui montar o carrinho".
--
--   1. Cópia das definições que se mexem ANTES de mexer (nada é apagado).
--   2. Duas definições novas (painel /admin/assistente, separador Amigo Bora):
--        assistant_web_search_enabled   true  pesquisa na internet do Amigo (web_search da Anthropic)
--        assistant_web_search_max_uses  3     máximo de pesquisas por mensagem (o painel aceita 1 a 5)
--      Cada pesquisa custa ~0,01 USD (10 USD por 1000) do crédito dos robôs, mais os tokens.
--   3. A conversa livre do Amigo passa para o claude-sonnet-5-5: assistant_amigo_model e
--      claude_robos → edge-amigo → modelo (só essa chave; o resto de claude_robos fica igual).
--      O caminho de reserva não muda (sem crédito / erro → Gemini, como antes).
--   4. ia_gastos.pesquisas_web — quantas pesquisas fez cada chamada (o custo delas já entra no
--      custo_usd, que o porteiro ia_claude_pode desconta do crédito como o resto).
--   5. assistant_lojas_abertas(p_tipo) — quem está aberto AGORA (is_partner_open de cada loja visível
--      ao assistente, hora de Lisboa), parceiros primeiro. Só leitura; só o servidor (Edge).
--   6. assistant_produtos_parceiro_aberto(p_query, p_limite) — produtos de PARCEIROS abertos agora cujo
--      nome, secção ou descrição tem o que se procura ("açaí" → os bowls do Goola). Preço = o do parceiro
--      (o mesmo que a assistant_search_products mostra para parceiros). Só leitura; só o servidor.
--   7. Painel (só admin, auditado): admin_amigo_pesquisa_overview (pesquisas de hoje e do mês, de
--      ia_gastos) e admin_amigo_pesquisa_definir (interruptor e máximo 1 a 5, com log_admin_action).
--
-- Zona verde: nenhuma escrita em pedidos, carteiras, preços ou dinheiro de clientes/parceiros.
-- Idempotente. Funções novas fechadas a anon.
-- =============================================================================

-- ─── 1. Cópia antes de mexer ──────────────────────────────────────────────────
create table if not exists public.bkp_platform_settings_amigo_20261111 as
  select * from public.platform_settings
   where key in ('assistant_amigo_model', 'claude_robos', 'assistant_web_search_enabled', 'assistant_web_search_max_uses');
revoke all on public.bkp_platform_settings_amigo_20261111 from public, anon, authenticated;

-- ─── 2. Definições novas ──────────────────────────────────────────────────────
insert into public.platform_settings (key, value, description, category)
values
  ('assistant_web_search_enabled', 'true'::jsonb,
   'Pesquisa na internet do Amigo Bora (ferramenta web_search da API do Claude): o tempo, a agenda e os eventos da Guarda, notícias e a farmácia de serviço. Nunca para produtos, preços ou lojas da Bora. Cada pesquisa custa ~0,01 USD do crédito dos robôs (fica em ia_gastos.pesquisas_web). Desligada: o Amigo diz que não sabe, como antes.',
   'assistente'),
  ('assistant_web_search_max_uses', '3'::jsonb,
   'Máximo de pesquisas na internet por mensagem do cliente (1 a 5). Padrão 3.',
   'assistente')
on conflict (key) do nothing;

-- ─── 3. Conversa livre do Amigo no Sonnet ─────────────────────────────────────
update public.platform_settings
   set value = '"claude-sonnet-5-5"'::jsonb, updated_at = now()
 where key = 'assistant_amigo_model'
   and value is distinct from '"claude-sonnet-5-5"'::jsonb;

update public.platform_settings
   set value = jsonb_set(value, '{edge-amigo,modelo}', '"claude-sonnet-5-5"'::jsonb, false), updated_at = now()
 where key = 'claude_robos'
   and jsonb_typeof(value -> 'edge-amigo') = 'object'
   and (value #>> '{edge-amigo,modelo}') is distinct from 'claude-sonnet-5-5';

-- ─── 4. Contagem das pesquisas no livro de gastos ─────────────────────────────
alter table public.ia_gastos add column if not exists pesquisas_web integer not null default 0;
comment on column public.ia_gastos.pesquisas_web is
  'Pesquisas na internet (web_search da API do Claude) feitas nesta chamada. O custo delas (~0,01 USD cada) já está em custo_usd. 11/11/2026.';

-- ─── 5. Lojas abertas agora ───────────────────────────────────────────────────
create or replace function public.assistant_lojas_abertas(p_tipo text default null)
returns jsonb
language plpgsql
stable
set search_path = public
as $$
declare
  v_tipo text := lower(coalesce(nullif(trim(p_tipo), ''), 'todas'));
  v jsonb;
begin
  select coalesce(jsonb_agg(x.j order by x.parceiro desc, x.nome), '[]'::jsonb) into v
    from (
      select coalesce(l.is_partner, false) as parceiro,
             l.name as nome,
             jsonb_build_object(
               'id', l.id,
               'nome', l.name,
               'parceiro', coalesce(l.is_partner, false),
               'categoria', l.category,
               'servico', l.service_type,
               'cozinha', nullif(r.cuisine_type, ''),
               'morada', r.address,
               'lat', l.lat,
               'lng', l.lng,
               'fecha_em_minutos', (o.st ->> 'closes_in_minutes')::int
             ) as j
        from public.assistant_lojas l
        join public.restaurants r on r.id = l.id
        cross join lateral (select public.is_partner_open(l.id) as st) o
       where coalesce((o.st ->> 'is_open')::boolean, false)
         and (v_tipo = 'todas'
              or (v_tipo = 'restaurantes' and l.service_type = 'restaurant')
              or (v_tipo = 'mercados' and l.category = 'supermarket')
              or (v_tipo = 'farmacias' and l.category = 'pharmacy')
              or (v_tipo = 'lojas' and l.category = 'store'))
    ) x;
  return v;
end;
$$;

comment on function public.assistant_lojas_abertas(text) is
  'Amigo Bora (11/11/2026): lojas visíveis ao assistente abertas AGORA (is_partner_open, hora de Lisboa), parceiros primeiro. p_tipo: todas | restaurantes | mercados | farmacias | lojas. Só leitura; chamada pela Edge client-assistant.';

-- ─── 6. Produtos de parceiros abertos agora ───────────────────────────────────
create or replace function public.assistant_produtos_parceiro_aberto(p_query text, p_limite integer default 6)
returns jsonb
language plpgsql
stable
set search_path = public, extensions
as $$
declare
  v_q      text := lower(public.f_unaccent(coalesce(p_query, '')));
  v_tokens text[];
  v        jsonb;
begin
  v_q := btrim(regexp_replace(regexp_replace(v_q, '[^a-z0-9 ]', ' ', 'g'), '\s+', ' ', 'g'));
  -- palavras com 3+ letras, sem as que não dizem o que é ("com", "para", "quero"…)
  v_tokens := array(
    select t from unnest(string_to_array(v_q, ' ')) t
     where length(t) >= 3
       and t not in ('com', 'sem', 'para', 'uma', 'uns', 'umas', 'dos', 'das', 'que', 'mais', 'menos',
                     'quero', 'queria', 'algo', 'alguma', 'algum', 'pra', 'por', 'favor'));
  if cardinality(v_tokens) = 0 then
    return '[]'::jsonb;
  end if;

  with abertas as (
    select l.id, l.name, (o.st ->> 'closes_in_minutes')::int as fecha
      from public.assistant_lojas l
      cross join lateral (select public.is_partner_open(l.id) as st) o
     where coalesce(l.is_partner, false)
       and coalesce((o.st ->> 'is_open')::boolean, false)
  ),
  bons as (
    select p.id, p.name, p.price, p.unit, p.category, p.taxonomy_section, p.category_root,
           a.id as loja_id, a.name as loja, a.fecha,
           row_number() over (partition by a.id order by p.price asc, p.name) as rn
      from abertas a
      join public.products p on p.restaurant_id = a.id
     where coalesce(p.is_available, true)
       and p.price > 0
       and (select bool_and(
                    lower(public.f_unaccent(coalesce(p.name, '') || ' ' || coalesce(p.category, '') || ' ' || coalesce(p.description, '')))
                      ~ ('\m' || t || '(s|es)?\M'))
              from unnest(v_tokens) t)
  )
  select coalesce(jsonb_agg(jsonb_build_object(
           'product_id', b.id,
           'nome', b.name,
           'loja', b.loja,
           'restaurant_id', b.loja_id,
           'preco', b.price,
           'unidade', b.unit,
           'parceiro', true,
           'aberta', true,
           'fecha_em_minutos', b.fecha,
           'maior_18', public.produto_e_maior_18(b.name, b.category, b.taxonomy_section, b.category_root)
         ) order by b.loja, b.price), '[]'::jsonb)
    into v
    from (select * from bons where rn <= 3 order by loja, price
          limit greatest(1, least(coalesce(p_limite, 6), 20))) b;
  return v;
end;
$$;

comment on function public.assistant_produtos_parceiro_aberto(text, integer) is
  'Amigo Bora (11/11/2026): produtos de PARCEIROS abertos agora cujo nome, secção ou descrição tem as palavras procuradas (ex.: "açaí" → bowls do Goola). Até 3 por loja. Preço = o do parceiro (como a assistant_search_products mostra). Só leitura; chamada pela Edge client-assistant.';

revoke all on function public.assistant_lojas_abertas(text) from public, anon, authenticated;
revoke all on function public.assistant_produtos_parceiro_aberto(text, integer) from public, anon, authenticated;
grant execute on function public.assistant_lojas_abertas(text) to service_role;
grant execute on function public.assistant_produtos_parceiro_aberto(text, integer) to service_role;

-- ─── 7. Painel admin ──────────────────────────────────────────────────────────
-- Pesquisas de hoje e do mês (dia de Lisboa), lidas de ia_gastos, e as duas definições.
create or replace function public.admin_amigo_pesquisa_overview()
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_hoje       date := (now() at time zone 'Europe/Lisbon')::date;
  v_mes        date := date_trunc('month', (now() at time zone 'Europe/Lisbon'))::date;
  v_hoje_desde timestamptz := (v_hoje::timestamp at time zone 'Europe/Lisbon');
  v_mes_desde  timestamptz := (v_mes::timestamp at time zone 'Europe/Lisbon');
  v_hoje_j     jsonb;
  v_mes_j      jsonb;
begin
  if not coalesce(public.is_admin(), false) then
    raise exception 'admin_required';
  end if;

  select jsonb_build_object(
           'pesquisas', coalesce(sum(g.pesquisas_web), 0),
           'chamadas', count(*),
           'usd', round(coalesce(sum(g.pesquisas_web), 0) * 0.01, 2))
    into v_hoje_j
    from public.ia_gastos g
   where g.pesquisas_web > 0 and g.quando >= v_hoje_desde;

  select jsonb_build_object(
           'pesquisas', coalesce(sum(g.pesquisas_web), 0),
           'chamadas', count(*),
           'usd', round(coalesce(sum(g.pesquisas_web), 0) * 0.01, 2))
    into v_mes_j
    from public.ia_gastos g
   where g.pesquisas_web > 0 and g.quando >= v_mes_desde;

  return jsonb_build_object(
    'hoje', v_hoje_j,
    'mes', v_mes_j,
    'dia', to_char(v_hoje, 'YYYY-MM-DD'),
    'mes_inicio', to_char(v_mes, 'YYYY-MM-DD'),
    'usd_por_pesquisa', 0.01,
    'definicoes', jsonb_build_object(
       'assistant_web_search_enabled',
         coalesce((select value = 'true'::jsonb from public.platform_settings where key = 'assistant_web_search_enabled'), false),
       'assistant_web_search_max_uses',
         (select value from public.platform_settings where key = 'assistant_web_search_max_uses'))
  );
end;
$$;

-- Liga/desliga a pesquisa e muda o máximo por mensagem (1 a 5). Só o que vier preenchido. Fica na auditoria.
create or replace function public.admin_amigo_pesquisa_definir(
  p_ativo boolean default null,
  p_max_usos integer default null
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
  v_quem   uuid := auth.uid();
begin
  if not coalesce(public.is_admin(), false) then
    raise exception 'admin_required';
  end if;
  if p_ativo is null and p_max_usos is null then
    raise exception 'nada_para_mudar';
  end if;
  if p_max_usos is not null and (p_max_usos < 1 or p_max_usos > 5) then
    raise exception 'max_usos_invalido: entre 1 e 5';
  end if;

  select jsonb_object_agg(key, value) into v_antes
    from public.platform_settings
   where key in ('assistant_web_search_enabled', 'assistant_web_search_max_uses');

  if p_ativo is not null then
    insert into public.platform_settings (key, value, description, category, updated_at, updated_by)
    values ('assistant_web_search_enabled', to_jsonb(p_ativo),
            'Pesquisa na internet do Amigo Bora (criada pelo painel).', 'assistente', now(), v_quem)
    on conflict (key) do update
      set value = excluded.value, updated_at = now(), updated_by = v_quem;
  end if;
  if p_max_usos is not null then
    insert into public.platform_settings (key, value, description, category, updated_at, updated_by)
    values ('assistant_web_search_max_uses', to_jsonb(p_max_usos),
            'Máximo de pesquisas na internet por mensagem (criada pelo painel).', 'assistente', now(), v_quem)
    on conflict (key) do update
      set value = excluded.value, updated_at = now(), updated_by = v_quem;
  end if;

  select jsonb_object_agg(key, value) into v_depois
    from public.platform_settings
   where key in ('assistant_web_search_enabled', 'assistant_web_search_max_uses');

  perform public.log_admin_action('amigo_pesquisa_definir'::text, 'platform_setting'::text, 'assistant_web_search'::text,
                                  jsonb_build_object('antes', v_antes, 'depois', v_depois));
  return v_depois;
end;
$$;

revoke all on function public.admin_amigo_pesquisa_overview() from public, anon;
revoke all on function public.admin_amigo_pesquisa_definir(boolean, integer) from public, anon;
grant execute on function public.admin_amigo_pesquisa_overview() to authenticated;
grant execute on function public.admin_amigo_pesquisa_definir(boolean, integer) to authenticated;
