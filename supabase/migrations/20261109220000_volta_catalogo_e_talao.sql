-- 20261109220000_volta_catalogo_e_talao.sql
-- Missão volta-deposito-kfc-2026-11-09 — PARTE 1 de 3 (sem dinheiro).
--   Ordem do Danilo (09/11/2026 20:08): "sempre quando houver qualquer bebida de lata ou garrafa que
--   tenha Volta, tem que cobrar mais os 10 cêntimos do cliente (...) Esse negócio do talão, tudo."
--   e (19:36) "Eu autorizo" para corrigir o catálogo e o talão do KFC.
--
-- Esta parte só prepara: colunas, definições, o classificador do Volta, o robô do talão (menus,
-- caixas, linhas de depósito) e as funções do painel. NÃO cobra nada a ninguém: a cobrança está na
-- PARTE 2 (proposta de dinheiro, .claude/.ai/missoes/volta-deposito-kfc-2026-11-09/) e a marcação do
-- catálogo na PARTE 3 (passo-3-marcar-catalogo.sql), que só corre depois da PARTE 2.
-- Tudo aditivo; nada se apaga.

-- ── 0. Cópia das definições que esta parte remenda ──────────────────────────────────────────────
create table if not exists public.bkp_fn_volta_20261109 (
  nome       text primary key,
  definicao  text not null,
  criado_em  timestamptz not null default now()
);
alter table public.bkp_fn_volta_20261109 enable row level security;
revoke all on public.bkp_fn_volta_20261109 from anon, authenticated;

insert into public.bkp_fn_volta_20261109 (nome, definicao)
select p.proname || '(' || pg_get_function_identity_arguments(p.oid) || ')', pg_get_functiondef(p.oid)
  from pg_proc p join pg_namespace n on n.oid = p.pronamespace
 where n.nspname = 'public'
   and p.proname in ('_talao_casar_itens', '_talao_e_acompanhamento', 'catalog_price_update_from_receipt', '_recibo_pedido')
on conflict (nome) do nothing;

-- ── 1. Colunas (aditivas) ───────────────────────────────────────────────────────────────────────
alter table public.products             add column if not exists deposit_units  integer not null default 0;
alter table public.products             add column if not exists deposit_review boolean not null default false;
alter table public.products             add column if not exists deposit_origem text;
alter table public.product_option_items add column if not exists deposit_units  integer not null default 0;
alter table public.product_option_items add column if not exists deposit_review boolean not null default false;
alter table public.product_option_items add column if not exists deposit_origem text;
alter table public.product_variants     add column if not exists deposit_units  integer;  -- null = igual ao produto

alter table public.orders add column if not exists deposit_units              integer not null default 0;
alter table public.orders add column if not exists deposit_cents              integer not null default 0;
alter table public.orders add column if not exists deposit_ajuste_cents       integer not null default 0;
alter table public.orders add column if not exists deposit_from_receipt_cents integer;
alter table public.orders add column if not exists deposit_talao_em           timestamptz;

do $c$ begin
  if not exists (select 1 from pg_constraint where conname = 'products_deposit_units_chk') then
    alter table public.products add constraint products_deposit_units_chk check (deposit_units between 0 and 48);
  end if;
  if not exists (select 1 from pg_constraint where conname = 'poi_deposit_units_chk') then
    alter table public.product_option_items add constraint poi_deposit_units_chk check (deposit_units between 0 and 48);
  end if;
  if not exists (select 1 from pg_constraint where conname = 'orders_deposit_chk') then
    alter table public.orders add constraint orders_deposit_chk check (deposit_units >= 0 and deposit_cents >= 0);
  end if;
end $c$;

comment on column public.products.deposit_units is 'Volta: embalagens com depósito (lata/garrafa de plástico até 3 L) por unidade vendida. 0 = sem depósito. Pack de 6 = 6.';
comment on column public.products.deposit_review is 'Volta: caso duvidoso ou talão com depósito a mais — lista "rever" do painel.';
comment on column public.products.deposit_origem is 'Volta: quem marcou (regra, talao, admin).';
comment on column public.orders.deposit_cents is 'Volta: depósito cobrado na criação do pedido (cêntimos). Fora do subtotal.';
comment on column public.orders.deposit_ajuste_cents is 'Volta: acertos depois da criação (produto em falta, talão com mais/menos depósito). Cêntimos com sinal.';
comment on column public.orders.deposit_from_receipt_cents is 'Volta: soma das linhas de depósito lidas no talão (DEPOSITO, VALOR DE DEPOSITO, VASILHAME…).';

-- ── 2. Definições (o painel muda-as em Configurações) ───────────────────────────────────────────
insert into public.platform_settings (key, value)
values ('volta_deposit_cents', to_jsonb(10)), ('volta_deposit_enabled', to_jsonb(true))
on conflict (key) do nothing;

-- ── 3. Funções auxiliares do Volta ──────────────────────────────────────────────────────────────
create or replace function public.volta_deposito_ativo()
returns boolean language sql stable security definer set search_path to 'public' as $$
  select coalesce((select (value #>> '{}')::boolean from public.platform_settings
                    where key = 'volta_deposit_enabled'), false)
$$;

create or replace function public.volta_deposito_cents_unidade()
returns integer language sql stable security definer set search_path to 'public' as $$
  select least(100, greatest(0, coalesce((select (value #>> '{}')::numeric from public.platform_settings
                                           where key = 'volta_deposit_cents'), 10)))::int
$$;

-- Embalagens com depósito de cada linha (produto + opções escolhidas) × quantidade, pelo CATÁLOGO.
-- Devolve o total e os itens com deposit_units / deposit_cents por linha.
create or replace function public.volta_deposito_itens(p_items jsonb)
returns table(units integer, items jsonb)
language plpgsql stable security definer set search_path to 'public' as $$
declare
  v_item  jsonb;
  v_out   jsonb := '[]'::jsonb;
  v_tot   integer := 0;
  v_qty   integer;
  v_prod  integer;
  v_opt   integer;
  v_u     integer;
  v_unit  integer := public.volta_deposito_cents_unidade();
begin
  if jsonb_typeof(p_items) is distinct from 'array' then
    return query select 0, coalesce(p_items, '[]'::jsonb);
    return;
  end if;
  for v_item in select * from jsonb_array_elements(p_items) loop
    v_qty := greatest(0, coalesce(round((v_item->>'quantity')::numeric)::int, 1));
    v_prod := null;
    select coalesce(p.deposit_units, 0) into v_prod from public.products p where p.id = v_item->>'productId';
    v_prod := coalesce(v_prod, 0);
    v_opt := 0;
    if jsonb_typeof(v_item->'selected_options') = 'array' then
      select coalesce(sum(m.u), 0)::int into v_opt
        from (select coalesce(min(poi.deposit_units) filter (where poi.is_available), 0) as u
                from (select g.value->>'group' as group_name, it.item_name
                        from jsonb_array_elements(v_item->'selected_options') g
                        cross join lateral jsonb_array_elements_text(
                          case when jsonb_typeof(g.value->'items') = 'array' then g.value->'items' else '[]'::jsonb end
                        ) it(item_name)) s
                left join public.product_option_groups pog
                  on pog.product_id = v_item->>'productId' and pog.name = s.group_name
                left join public.product_option_items poi
                  on poi.group_id = pog.id and poi.name = s.item_name
               group by s.group_name, s.item_name) m;
    end if;
    v_u := (v_prod + coalesce(v_opt, 0)) * v_qty;
    v_tot := v_tot + v_u;
    v_out := v_out || jsonb_build_array(v_item || jsonb_build_object('deposit_units', v_u, 'deposit_cents', v_u * v_unit));
  end loop;
  return query select v_tot, v_out;
end $$;

-- Classificador do Volta (regras escritas, iguais para a marcação do catálogo e o fecho do talão).
-- estado: marcar | duvidoso | excluido | nao_bebida ; units = embalagens por unidade vendida.
-- Fonte das regras: lei do Volta (DECO/Governo, desde 10/04/2026) — entram águas, sumos e néctares,
-- refrigerantes (incl. chá/café/infusões), energéticas, isotónicas, cerveja, sidra, sangria e misturas
-- alcoólicas em plástico/aço/alumínio até 3 L; ficam fora vidro, vinho, espirituosas, lácteos > 25 %,
-- cartão, bag-in-box e garrafões > 3 L. "Duvidoso" = 0 e vai para a lista "rever" do painel.
create or replace function public.volta_classificar(p_nome text, p_categoria text default null, p_loja text default null)
returns jsonb language plpgsql stable set search_path to 'public', 'extensions' as $$
declare
  n       text := ' ' || public._talao_norm(coalesce(p_nome, '')) || ' ';
  c       text := ' ' || public._talao_norm(coalesce(p_categoria, '')) || ' ';
  l       text := lower(coalesce(p_loja, ''));
  raw     text := replace(lower(extensions.unaccent(coalesce(p_nome, ''))), ',', '.');
  m       text[];
  v_ml    numeric;
  v_un    integer := 1;
  v_lata  boolean; v_pet boolean; v_garrafa boolean;
  v_tipo  text;
  v_merc  boolean := l ~ '(continente|intermarche|auchan|pingodoce|pingo-doce|lidl|mercadona|wells|leroy|kiwoko|zippy|worten|naturhouse|action)';
  v_catb  boolean := c ~ ' (bebida|bebidas|refrigerante|refrigerantes|agua|aguas|cerveja|cervejas|sumo|sumos|garrafeira|alcool|sidras|energeticas) ';
begin
  v_tipo := case
    when n ~ ' (cerveja|cervejas|sagres|super bock|superbock|heineken|estrella|mahou|carlsberg|coral|sidra|somersby|sangria|radler|shandy|panache|cocktail|mojito|daiquiri|breezer|breezeo) ' then 'alcool'
    when n ~ ' (sumo|sumos|nectar|nectares|compal|frisumo|um bongo|smoothie|innocent|agua de coco|coco) ' then 'sumo'
    when n ~ ' (agua|aguas|luso|vitalis|caramulo|monchique|fastio|pedras|frize|vimeiro|penacova|carvalhelhos) ' then 'agua'
    when n ~ ' (refrigerante|refrigerantes|cola|colas|coca|pepsi|fanta|sprite|7up|7 up|seven up|ice tea|iced tea|icetea|nestea|lipton|fuze|limonada|laranjada|gasosa|lima limao|tonica|tonic|ginger|schweppes|sumol|guarana|kas|trina|brisa|energetica|energeticas|energetico|energeticos|energy|red bull|redbull|monster|burn|rodeo|rockstar|celsius|prime|isotonica|isotonico|gatorade|aquarius|powerade|vitaminwater|vit hit|kombucha|cha frio|tisana|tisanas|aloe vera|mountain dew|dr pepper|tango|cha|tonica|fever tree|royal bliss) ' then 'refrigerante'
    when c ~ ' (bebida|bebidas|refrigerante|refrigerantes|agua|aguas|cerveja|cervejas|sumo|sumos) '
         and n ~ ' (lata|latas|garrafa|pet|[0-9]+ ?cl|[0-9]+ ?ml) ' then 'refrigerante'
    else null end;
  if v_tipo is null then
    m := regexp_match(n, ' (vinho|vinhos|espumante|champanhe|champagne|moscatel|porto|whisky|whiskey|vodka|gin|rum|licor|aguardente|brandy|tequila|conhaque|cognac|armagnac|cachaca|vermute|martini|aperitivo|espirituosa) ');
    if m is not null and (v_catb or not v_merc) then
      return jsonb_build_object('units', 0, 'estado', 'excluido', 'motivo', 'excluido_' || m[1]);
    end if;
    return jsonb_build_object('units', 0, 'estado', 'nao_bebida', 'motivo', 'nao_e_bebida');
  end if;
  -- nos mercados só conta o que está na secção de bebidas ("Fita Cola", "Pensos à prova de Água"…)
  if v_merc and not v_catb then
    return jsonb_build_object('units', 0, 'estado', 'nao_bebida', 'motivo', 'mercado_fora_da_seccao_de_bebidas');
  end if;
  -- vendido ao peso (gramas) e sem volume = não é bebida pronta (pós, saquetas, barras)
  if raw ~ '[0-9] ?(g|gr|grs|kg)([^a-z]|$)' and raw !~ '[0-9] ?(cl|ml|lt|lts|l|litro|litros)([^a-z]|$)' then
    return jsonb_build_object('units', 0, 'estado', 'nao_bebida', 'motivo', 'vendido_ao_peso');
  end if;

  -- fora do Volta: vidro, vinho, espirituosas, lácteos, cartão, bag-in-box, garrafões, copos de serviço
  m := regexp_match(n, ' (vidro|vidrio|glass|fever tree|royal bliss|long neck|vinho|vinhos|espumante|champanhe|champagne|moscatel|whisky|whiskey|vodka|gin|rum|licor|aguardente|brandy|tequila|tequilla|conhaque|cognac|armagnac|cachaca|vermute|martini|aperitivo|espirituosa|leite|iogurte|iogurtes|kefir|lacteo|lactea|lacteos|achocolatado|batido|milkshake|latte|cappuccino|bag in box|garrafao|copo|copos|caneca|chavena|xarope|concentrado|capsula|capsulas|saqueta|saquetas|vegetal|aveia|soja|amendoa|tetra|pacote|pacotes|brik|brick|cartao|gelo|ucal|vinagre|jarro|filtro|guache|tinta) ');
  -- a própria loja escreve "(SDR)" no nome: é embalagem com depósito (nunca no Burger King)
  if n ~ ' sdr ' and l !~ 'burger ?king|burgerking' and (m is null or m[1] in ('concentrado', 'xarope')) then
    m := regexp_match(raw, '([0-9]{1,2}) ?x ?[0-9]');
    return jsonb_build_object('units', case when m is not null and (m[1])::int between 2 and 48 then (m[1])::int else 1 end,
                              'estado', 'marcar', 'motivo', 'loja_marca_sdr');
  end if;
  if m is not null then
    return jsonb_build_object('units', 0, 'estado', 'excluido', 'motivo', 'excluido_' || replace(m[1], ' ', '_'));
  end if;
  if l ~ 'burger ?king|burgerking' then
    return jsonb_build_object('units', 0, 'estado', 'excluido', 'motivo', 'copos_burger_king');
  end if;

  -- volume (até 3 L) e packs
  m := regexp_match(raw, '([0-9]+(\.[0-9]+)?) ?(cl|ml|lt|lts|l|litro|litros)([^a-z]|$)');
  if m is not null then
    v_ml := (m[1])::numeric * case m[3] when 'cl' then 10 when 'ml' then 1 else 1000 end;
    if v_ml > 3000 then
      return jsonb_build_object('units', 0, 'estado', 'excluido', 'motivo', 'mais_de_3_litros');
    end if;
  end if;
  m := regexp_match(raw, '([0-9]{1,2}) ?x ?[0-9]');
  if m is null then
    m := regexp_match(raw, 'pack ?(de )?([0-9]{1,2})');
    if m is not null then m := array[m[2]]; end if;
  end if;
  if m is null then m := regexp_match(raw, '([0-9]{1,2}) ?(latas|garrafas|unidades|unid|un)([^a-z]|$)'); end if;
  if m is not null and (m[1])::int between 2 and 48 then v_un := (m[1])::int; end if;

  if v_tipo = 'refrigerante' and n ~ ' cha ' and n !~ ' (ice tea|iced tea|icetea|cha frio|lipton|nestea|fuze) ' and v_ml is null then
    return jsonb_build_object('units', 0, 'estado', 'nao_bebida', 'motivo', 'cha_seco_sem_volume');
  end if;

  v_lata    := n ~ ' (lata|latas|can|cans) ';
  v_pet     := n ~ ' (pet|plastico) ';
  v_garrafa := n ~ ' (garrafa|garrafas|gfa|grf) ';

  if l ~ 'mcdonald' and not (v_tipo = 'agua' and (v_garrafa or v_ml is not null)) then
    return jsonb_build_object('units', 0, 'estado', 'excluido', 'motivo', 'copos_mcdonalds');
  end if;

  if v_lata or v_pet then
    return jsonb_build_object('units', v_un, 'estado', 'marcar', 'motivo', case when v_lata then 'lata' else 'pet' end);
  end if;
  -- garrafa pequena (menos de 33 cl) sem lata/PET/SDR: nesta loja costuma ser vidro (revisão com fotos 09/11)
  if v_ml is not null and v_ml < 330 and n !~ ' (red bull|redbull|monster|burn|rodeo|rockstar) ' then
    return jsonb_build_object('units', 0, 'estado', 'duvidoso', 'motivo', 'garrafa_pequena_pode_ser_vidro', 'units_se_marcar', v_un);
  end if;
  -- marcas que só existem em lata (energéticas)
  if n ~ ' (red bull|redbull|monster|burn|rodeo|rockstar) ' then
    return jsonb_build_object('units', v_un, 'estado', 'marcar', 'motivo', 'marca_so_em_lata');
  end if;
  if v_tipo = 'alcool' then
    return jsonb_build_object('units', 0, 'estado', 'duvidoso', 'motivo', 'alcool_sem_lata_pode_ser_vidro', 'units_se_marcar', v_un);
  end if;
  if v_tipo = 'sumo' then
    if (v_garrafa or n ~ ' innocent ') and coalesce(v_ml, 0) >= 500 then
      return jsonb_build_object('units', v_un, 'estado', 'marcar', 'motivo', 'sumo_garrafa_grande_pet');
    end if;
    return jsonb_build_object('units', 0, 'estado', 'duvidoso', 'motivo', 'sumo_pode_ser_cartao_ou_vidro', 'units_se_marcar', v_un);
  end if;
  if v_tipo = 'agua' then
    if n ~ ' (pedras|frize) ' and coalesce(v_ml, 1000) <= 330 then
      return jsonb_build_object('units', 0, 'estado', 'duvidoso', 'motivo', 'agua_com_gas_pequena_pode_ser_vidro', 'units_se_marcar', v_un);
    end if;
    if v_ml is not null or v_garrafa then
      return jsonb_build_object('units', v_un, 'estado', 'marcar', 'motivo', 'agua_garrafa');
    end if;
    return jsonb_build_object('units', 0, 'estado', 'duvidoso', 'motivo', 'agua_sem_embalagem', 'units_se_marcar', v_un);
  end if;
  -- chás frios pequenos (até 25 cl) costumam ser de pacote
  if v_ml is not null and v_ml <= 250 and n ~ ' (ice tea|iced tea|icetea|nestea|tisana|tisanas) ' then
    return jsonb_build_object('units', 0, 'estado', 'duvidoso', 'motivo', 'cha_frio_pequeno_pode_ser_pacote', 'units_se_marcar', v_un);
  end if;
  if v_ml is not null or v_garrafa then
    return jsonb_build_object('units', v_un, 'estado', 'marcar', 'motivo', 'refrigerante_lata_ou_pet');
  end if;
  return jsonb_build_object('units', 0, 'estado', 'duvidoso', 'motivo', 'refrigerante_sem_embalagem', 'units_se_marcar', v_un);
end $$;

revoke all on function public.volta_deposito_itens(jsonb) from public, anon;
revoke all on function public.volta_classificar(text, text, text) from public, anon;
revoke all on function public.volta_deposito_ativo() from public, anon;
revoke all on function public.volta_deposito_cents_unidade() from public, anon;
grant execute on function public.volta_deposito_ativo() to authenticated, service_role;
grant execute on function public.volta_deposito_cents_unidade() to authenticated, service_role;
grant execute on function public.volta_classificar(text, text, text) to authenticated, service_role;
grant execute on function public.volta_deposito_itens(jsonb) to service_role;

-- ── 4. Robô do talão ────────────────────────────────────────────────────────────────────────────
create or replace function public._talao_e_deposito(p text)
returns boolean language sql stable set search_path to 'public', 'extensions' as $$
  select public._talao_norm(p) ~ '(^| )(deposito|depositos|vasilhame|vasilhames)( |$)'
      or public._talao_norm(p) ~ '^(sdr|volta|dep|dep emb)( |$)'
$$;

create or replace function public._talao_e_saco(p text)
returns boolean language sql stable set search_path to 'public', 'extensions' as $$
  select public._talao_norm(p) ~ '(^| )(saco|sacos)( |$)'
$$;

-- bebidas do KFC vêm com "V " à frente ("V LIPTON IT MANGA LA", "V PEPSI LATA")
create or replace function public._talao_e_acompanhamento(p text)
returns boolean language sql stable set search_path to 'public', 'extensions' as $$
  select public._talao_norm(p) ~ '^(v )?(batatas?|patatas?|fries|cola|coca|pepsi|fanta|sprite|7 ?up|ice ?tea|nestea|lipton|sumo|agua|bebida|refrigerante|cerveja|sagres|super ?bock|cafe|salada|sobremesa|gelado|sundae|aros|onion|red ?bull|sumol|compal)( |$)'
$$;

-- Casar os artigos do pedido com as linhas do talão.
-- 09/11/2026: (1) menu com cabeçalho a 0,00 ("MENU KENTUCKY BBQ 0,00") = um produto; o preço é a soma de
-- TODAS as sublinhas até ao próximo artigo (sanduíche + batata + bebida); (2) caixa cujo preço vem
-- partido ("BOX 6 HOTWINGS 0,55" + "6 HOT WINGS 5,65" = 6,20); (3) linhas de depósito e de saco nunca
-- entram no preço de um produto; (4) separadores "-----" ignoram-se.
create or replace function public._talao_casar_itens(p_items jsonb, p_lines jsonb)
 returns jsonb
 language plpgsql
 stable
 set search_path to 'public', 'extensions'
as $function$
declare
  v_n         int := coalesce(jsonb_array_length(p_lines), 0);
  v_usadas    int[] := '{}';
  v_out       jsonb := '[]'::jsonb;
  v_item      jsonb;
  v_idx       int := -1;
  v_nome      text;
  v_nome_menu text;
  v_menu      boolean;
  v_header    boolean;
  v_best      int;
  v_bsim      numeric;
  v_sim       numeric;
  v_line      jsonb;
  j           int;
  v_base      int;
  v_extra     int;
  v_ln        text;
  v_up        int;
  v_priced    int;
  v_comp      int;
  v_ref       int;
  v_iqty      numeric;
  v_outros    text[];
  v_app_mod   numeric;
  v_app_outro numeric;
  v_grupo     jsonb;
begin
  for v_item in select * from jsonb_array_elements(coalesce(p_items, '[]'::jsonb)) loop
    v_idx := v_idx + 1;
    v_iqty := coalesce((v_item->>'quantity')::numeric, 1);
    v_nome_menu := public._talao_norm(v_item->>'name');
    v_menu := v_nome_menu ~ '(^| )menu( |$)';
    v_nome := btrim(regexp_replace(v_nome_menu, '(^| )menu( |$)', ' ', 'g'));
    v_ref := round(coalesce((v_item->>'basePrice')::numeric, 0) * 100)::int;
    -- os outros artigos (não-menus) do pedido: um menu não engole um artigo que venha a seguir
    select coalesce(array_agg(public._talao_norm(t.x->>'name')), '{}') into v_outros
      from jsonb_array_elements(p_items) with ordinality as t(x, ord)
     where t.ord - 1 <> v_idx and public._talao_norm(t.x->>'name') !~ '(^| )menu( |$)';
    v_best := null; v_bsim := 0; v_header := false;

    -- (1) menu com cabeçalho a 0,00
    if v_menu then
      for j in 0 .. v_n - 1 loop
        v_line := p_lines->j;
        continue when j = any (v_usadas);
        continue when coalesce((v_line->>'unit_price_cents')::int, 0) <> 0;
        continue when coalesce((v_line->>'qty')::numeric, 1) <> v_iqty;
        v_ln := public._talao_norm(v_line->>'name');
        continue when v_ln !~ '(^| )menu( |$)';
        v_sim := greatest(extensions.similarity(v_nome_menu, v_ln),
                          extensions.word_similarity(v_ln, v_nome_menu),
                          extensions.similarity(replace(v_nome_menu, ' ', ''), replace(v_ln, ' ', '')));
        if v_sim > v_bsim then v_bsim := v_sim; v_best := j; end if;
      end loop;
      if v_best is not null and v_bsim >= 0.5 then
        v_header := true;
      else
        v_best := null; v_bsim := 0;
      end if;
    end if;

    -- (2) sem cabeçalho: a linha com preço mais parecida
    if not v_header then
      for j in 0 .. v_n - 1 loop
        v_line := p_lines->j;
        continue when j = any (v_usadas);
        continue when coalesce((v_line->>'unit_price_cents')::int, 0) <= 0;
        continue when coalesce((v_line->>'qty')::numeric, 1) <> v_iqty;
        continue when public._talao_e_modificador(v_line->>'name') or public._talao_e_acompanhamento(v_line->>'name');
        continue when public._talao_e_deposito(v_line->>'name') or public._talao_e_saco(v_line->>'name');
        v_ln := public._talao_norm(v_line->>'name');
        v_sim := greatest(extensions.similarity(v_nome, v_ln),
                          extensions.word_similarity(v_ln, v_nome),
                          extensions.similarity(replace(v_nome, ' ', ''), replace(v_ln, ' ', '')));
        if v_sim > v_bsim then v_bsim := v_sim; v_best := j; end if;
      end loop;
    end if;

    -- extras escolhidos na app (preço de balcão): EXTRA… à parte do resto (bebida/acompanhamento)
    v_app_mod := 0; v_app_outro := 0;
    begin
      select coalesce(sum((gi.value->>'price_add')::numeric) filter (where public._talao_e_modificador(gi.value->>'name')), 0),
             coalesce(sum((gi.value->>'price_add')::numeric) filter (where not public._talao_e_modificador(gi.value->>'name')), 0)
        into v_app_mod, v_app_outro
        from jsonb_array_elements(case when jsonb_typeof(v_item->'selected_options_priced') = 'array'
                                       then v_item->'selected_options_priced' else '[]'::jsonb end) g,
             jsonb_array_elements(case when jsonb_typeof(g.value->'items') = 'array'
                                       then g.value->'items' else '[]'::jsonb end) gi;
    exception when others then v_app_mod := null; v_app_outro := null;
    end;

    if v_best is null or v_bsim < 0.5 then
      v_out := v_out || jsonb_build_object('idx', v_idx, 'product_id', v_item->>'productId', 'casou', false,
                                           'sim', round(v_bsim, 3));
      continue;
    end if;
    v_usadas := v_usadas || v_best;
    v_base := coalesce((p_lines->v_best->>'unit_price_cents')::int, 0);
    v_extra := 0;
    v_priced := case when v_header then 0 else 1 end;
    v_comp := 0;
    v_grupo := jsonb_build_array(p_lines->v_best->>'name');
    j := v_best + 1;
    while j < v_n loop
      v_line := p_lines->j;
      v_up := coalesce((v_line->>'unit_price_cents')::int, 0);
      v_ln := public._talao_norm(v_line->>'name');
      exit when j = any (v_usadas);
      exit when public._talao_e_deposito(v_line->>'name') or public._talao_e_saco(v_line->>'name');
      exit when v_up = 0 and v_ln ~ '(^| )menu( |$)';          -- cabeçalho de outro menu
      if v_ln = '' then
        null;                                                   -- separador "-----"
      elsif public._talao_e_modificador(v_line->>'name') then
        v_extra := v_extra + v_up;
      elsif v_up = 0 then
        null;                                                   -- linha descritiva (ex.: "3C Whopper")
      elsif v_header then
        -- menu com cabeçalho: todas as sublinhas até ao próximo artigo (no máximo 6)
        exit when v_priced >= 6;
        exit when v_priced >= 1 and exists (
          select 1 from unnest(v_outros) o
           where o <> '' and greatest(extensions.similarity(o, v_ln), extensions.word_similarity(v_ln, o)) >= 0.6);
        v_base := v_base + v_up;
        v_priced := v_priced + 1;
      elsif v_menu and public._talao_e_acompanhamento(v_line->>'name') then
        v_base := v_base + v_up;
      elsif not v_menu and v_comp < 2 and v_ref > 0
            and v_base < v_ref * 0.5 and v_base + v_up <= v_ref * 1.5 then
        -- caixa com o preço partido em duas linhas
        v_base := v_base + v_up;
        v_comp := v_comp + 1;
      else
        exit;
      end if;
      v_usadas := v_usadas || j;
      v_grupo := v_grupo || to_jsonb(v_line->>'name');
      j := j + 1;
    end loop;
    v_out := v_out || jsonb_build_object(
      'idx', v_idx, 'product_id', v_item->>'productId', 'casou', true, 'sim', round(v_bsim, 3),
      'linha', p_lines->v_best->>'name', 'grupo', v_grupo, 'menu', v_menu, 'cabecalho', v_header,
      'base_talao_cents', v_base, 'extras_talao_cents', v_extra,
      'extras_app_mod', v_app_mod, 'extras_app_outros', v_app_outro);
  end loop;
  return v_out;
end $function$;

-- Remendo por âncora (contagem = 1 obrigatória) — o resto da função fica igual.
create or replace function pg_temp.volta_remendo(p_fn regprocedure, p_nome text, p_anc text[], p_rep text[])
returns void language plpgsql as $$
declare v_def text; v_new text; i int; v_n int;
begin
  v_def := pg_get_functiondef(p_fn);
  v_new := v_def;
  for i in 1 .. array_length(p_anc, 1) loop
    v_n := (length(v_new) - length(replace(v_new, p_anc[i], ''))) / length(p_anc[i]);
    if v_n <> 1 then
      raise exception 'VOLTA_ANCORA % de % aparece % vezes (esperado 1)', i, p_nome, v_n;
    end if;
    v_new := replace(v_new, p_anc[i], p_rep[i]);
  end loop;
  execute v_new;
end $$;

-- Robô do catálogo: proposta absurda (leitura partida) não entra; linhas de depósito nunca são produto.
select pg_temp.volta_remendo('public.catalog_price_update_from_receipt(uuid)'::regprocedure, 'catalog_price_update_from_receipt',
  array[
$a$  v_segunda    int := 0;$a$,
$a$    IF v_new_base <= 0 THEN v_sem_match := v_sem_match + 1; CONTINUE; END IF;$a$,
$a$      CONTINUE WHEN v_ln ~ '(^| )saco( |$)';$a$,
$a$    'sem_match', v_sem_match, 'ja_batiam', v_iguais, 'segunda_volta', v_segunda,$a$
  ],
  array[
$b$  v_segunda    int := 0;
  v_absurdas   int := 0;   -- 09/11/2026$b$,
$b$    IF v_new_base <= 0 THEN v_sem_match := v_sem_match + 1; CONTINUE; END IF;
    -- 09/11/2026: leitura partida do talão (ex.: 0,55 para uma caixa de 6,20) não vira proposta.
    IF v_new_base < v_prod.price * 0.4 OR v_new_base > v_prod.price * 2.5 THEN
      v_absurdas := v_absurdas + 1; CONTINUE;
    END IF;$b$,
$b$      CONTINUE WHEN v_ln ~ '(^| )saco( |$)';
      CONTINUE WHEN public._talao_e_deposito(v_line->>'name');$b$,
$b$    'sem_match', v_sem_match, 'ja_batiam', v_iguais, 'segunda_volta', v_segunda, 'absurdas', v_absurdas,$b$
  ]);

-- ── 5. Recibo do cliente: linha própria do depósito Volta ───────────────────────────────────────
select pg_temp.volta_remendo('public._recibo_pedido(text)'::regprocedure, '_recibo_pedido',
  array[
$a$    IF COALESCE(o.helper_fee_eur, 0) > 0 THEN
      v_linhas := v_linhas || jsonb_build_object('nome', 'Ajudante', 'valor_cents', ROUND(o.helper_fee_eur * 100)::int);
    END IF;$a$
  ],
  array[
$b$    IF COALESCE(o.helper_fee_eur, 0) > 0 THEN
      v_linhas := v_linhas || jsonb_build_object('nome', 'Ajudante', 'valor_cents', ROUND(o.helper_fee_eur * 100)::int);
    END IF;
    -- 09/11/2026: depósito Volta em linha própria (obrigação legal), com os acertos do talão.
    IF COALESCE(o.deposit_cents, 0) + COALESCE(o.deposit_ajuste_cents, 0) > 0 THEN
      v_linhas := v_linhas || jsonb_build_object(
        'nome', 'Depósito Volta (' || GREATEST(1, ROUND((COALESCE(o.deposit_cents, 0) + COALESCE(o.deposit_ajuste_cents, 0))
                                                     / NULLIF(public.volta_deposito_cents_unidade(), 0)::numeric))::int
                || ' emb.)',
        'valor_cents', COALESCE(o.deposit_cents, 0) + COALESCE(o.deposit_ajuste_cents, 0));
    END IF;$b$
  ]);

-- ── 6. Painel admin (PT-BR) ─────────────────────────────────────────────────────────────────────
create or replace function public.admin_volta_produtos(
  p_loja text default null, p_filtro text default 'todos', p_busca text default null,
  p_limite int default 200, p_offset int default 0)
returns table(tipo text, id text, loja_id text, loja_nome text, nome text, categoria text, preco numeric,
              deposit_units int, deposit_review boolean, deposit_origem text, image_url text, total bigint)
language plpgsql stable security definer set search_path to 'public' as $$
begin
  if not public.is_admin() then raise exception 'forbidden' using errcode = '42501'; end if;
  return query
  with base as (
    select 'produto'::text as tipo, p.id::text as id, p.restaurant_id::text as loja_id, r.name::text as loja_nome,
           p.name::text as nome, p.category::text as categoria, p.price::numeric as preco,
           p.deposit_units, p.deposit_review, p.deposit_origem, p.photo_url::text as image_url
      from public.products p
      left join public.restaurants r on r.id::text = p.restaurant_id::text
     where coalesce(p.is_available, true)
    union all
    select 'opcao', poi.id::text, p.restaurant_id::text, r.name::text,
           (p.name || ' › ' || pog.name || ' › ' || poi.name)::text, ('Opção de menu')::text, poi.price_add::numeric,
           poi.deposit_units, poi.deposit_review, poi.deposit_origem, null::text
      from public.product_option_items poi
      join public.product_option_groups pog on pog.id = poi.group_id
      join public.products p on p.id = pog.product_id
      left join public.restaurants r on r.id::text = p.restaurant_id::text
     where coalesce(poi.is_available, true) and coalesce(p.is_available, true)
  )
  select b.tipo, b.id, b.loja_id, b.loja_nome, b.nome, b.categoria, b.preco, b.deposit_units, b.deposit_review,
         b.deposit_origem, b.image_url, count(*) over ()
    from base b
   where (p_loja is null or b.loja_id = p_loja)
     and (coalesce(p_filtro, 'todos') = 'todos'
          or (p_filtro = 'com' and b.deposit_units > 0)
          or (p_filtro = 'sem' and b.deposit_units = 0)
          or (p_filtro = 'rever' and b.deposit_review))
     and (p_busca is null or btrim(p_busca) = '' or b.nome ilike '%' || btrim(p_busca) || '%')
   order by b.loja_nome nulls last, b.nome
   limit least(greatest(coalesce(p_limite, 200), 1), 1000) offset greatest(coalesce(p_offset, 0), 0);
end $$;

create or replace function public.admin_volta_definir(p_tipo text, p_id text, p_units int)
returns jsonb language plpgsql security definer set search_path to 'public' as $$
declare v_antes int; v_n int;
begin
  if not public.is_admin() then raise exception 'forbidden' using errcode = '42501'; end if;
  if p_units is null or p_units < 0 or p_units > 48 then raise exception 'INVALID_UNITS: %', p_units; end if;
  if p_tipo = 'produto' then
    select deposit_units into v_antes from public.products where id = p_id;
    update public.products set deposit_units = p_units, deposit_review = false, deposit_origem = 'admin' where id = p_id;
  elsif p_tipo = 'opcao' then
    select deposit_units into v_antes from public.product_option_items where id = p_id;
    update public.product_option_items set deposit_units = p_units, deposit_review = false, deposit_origem = 'admin' where id = p_id;
  else
    raise exception 'INVALID_TIPO: %', p_tipo;
  end if;
  get diagnostics v_n = row_count;
  if v_n = 0 then raise exception 'NOT_FOUND: % %', p_tipo, p_id; end if;
  begin
    perform public.log_admin_action('volta_deposito_definir', p_tipo, p_id,
      jsonb_build_object('antes', v_antes, 'depois', p_units));
  exception when others then raise notice 'log_admin_action falhou: %', sqlerrm;
  end;
  return jsonb_build_object('ok', true, 'tipo', p_tipo, 'id', p_id, 'deposit_units', p_units, 'antes', v_antes);
end $$;

create or replace function public.admin_volta_resumo_lojas()
returns table(loja_id text, loja_nome text, produtos_com int, opcoes_com int, rever int)
language plpgsql stable security definer set search_path to 'public' as $$
begin
  if not public.is_admin() then raise exception 'forbidden' using errcode = '42501'; end if;
  return query
  with prod as (
    select p.restaurant_id::text as loja_id,
           count(*) filter (where p.deposit_units > 0)::int as com,
           count(*) filter (where p.deposit_review)::int as rev
      from public.products p where coalesce(p.is_available, true) group by 1),
  opc as (
    select p.restaurant_id::text as loja_id,
           count(*) filter (where poi.deposit_units > 0)::int as com,
           count(*) filter (where poi.deposit_review)::int as rev
      from public.product_option_items poi
      join public.product_option_groups pog on pog.id = poi.group_id
      join public.products p on p.id = pog.product_id
     where coalesce(poi.is_available, true) group by 1)
  select coalesce(prod.loja_id, opc.loja_id), r.name::text,
         coalesce(prod.com, 0), coalesce(opc.com, 0), coalesce(prod.rev, 0) + coalesce(opc.rev, 0)
    from prod full join opc on opc.loja_id = prod.loja_id
    left join public.restaurants r on r.id::text = coalesce(prod.loja_id, opc.loja_id)
   where coalesce(prod.com, 0) + coalesce(opc.com, 0) + coalesce(prod.rev, 0) + coalesce(opc.rev, 0) > 0
   order by 2 nulls last;
end $$;

create or replace function public.admin_volta_relatorio_mensal(p_ano int, p_mes int)
returns jsonb language plpgsql stable security definer set search_path to 'public' as $$
declare v_ini timestamptz; v_fim timestamptz; v jsonb;
begin
  if not public.is_admin() then raise exception 'forbidden' using errcode = '42501'; end if;
  v_ini := make_timestamptz(p_ano, p_mes, 1, 0, 0, 0, 'Europe/Lisbon');
  v_fim := v_ini + interval '1 month';
  select jsonb_build_object(
    'ano', p_ano, 'mes', p_mes,
    'pedidos', count(*) filter (where coalesce(o.deposit_cents, 0) + coalesce(o.deposit_ajuste_cents, 0) <> 0
                                   or o.deposit_from_receipt_cents is not null),
    'embalagens', coalesce(sum(o.deposit_units), 0),
    'cobrado_cents', coalesce(sum(o.deposit_cents), 0),
    'ajustes_cents', coalesce(sum(o.deposit_ajuste_cents), 0),
    'talao_cents', coalesce(sum(o.deposit_from_receipt_cents), 0),
    'parceiros_cents', coalesce(sum(o.deposit_cents + o.deposit_ajuste_cents) filter (where coalesce(o.is_partner_store, false)), 0),
    'bora_cents', coalesce(sum(o.deposit_cents + o.deposit_ajuste_cents) filter (where not coalesce(o.is_partner_store, false)), 0))
    into v
    from public.orders o
   where o.status = 'delivered' and o.delivered_at >= v_ini and o.delivered_at < v_fim;
  return v;
end $$;

revoke all on function public.admin_volta_produtos(text, text, text, int, int) from public, anon;
revoke all on function public.admin_volta_definir(text, text, int) from public, anon;
revoke all on function public.admin_volta_resumo_lojas() from public, anon;
revoke all on function public.admin_volta_relatorio_mensal(int, int) from public, anon;
grant execute on function public.admin_volta_produtos(text, text, text, int, int) to authenticated;
grant execute on function public.admin_volta_definir(text, text, int) to authenticated;
grant execute on function public.admin_volta_resumo_lojas() to authenticated;
grant execute on function public.admin_volta_relatorio_mensal(int, int) to authenticated;
