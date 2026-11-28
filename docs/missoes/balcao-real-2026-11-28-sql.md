# Missão balcao-real-2026-11-28 — SQL para a Claude.ai aplicar por MCP

> Escrito pelo Claude Code na nuvem a 28/11/2026. Esta sessão **não correu nada no Supabase**.
> Tudo o que está aqui foi provado num Postgres 16 descartável dentro do contentor, com as funções
> copiadas das migrações do repo (robô do talão de 28/11, `_talao_casar_itens` de 10/11, ajudantes
> `_talao_*`) e tabelas mínimas. Os resultados das provas estão por baixo de cada bloco.
>
> Nada disto mexe em dinheiro: nenhum bloco muda `products.price`, cobranças, reembolso, ganhos,
> carteiras ou tokens. Só o preço de balcão que o **estafeta vê** e textos de aviso.

Ordem para aplicar (cada bloco é uma migração própria; guardar no repo com a versão que o servidor
gravar):

1. `carimbo_balcao_real_guardas` — bloco 1 (ecrã).
2. `resumo_telefone_balcao_real` — bloco 2 (B3, ecrã).
3. `talao_menu_unico_kfc` — blocos 3 e 4 (B4). Antes, correr a prova 5 no talão real, em transação desfeita.

---

## 1. Carimbo do balcão real: duas guardas (achado no caminho, só ecrã)

Porquê: o gatilho `zzzzz_orders_carimba_balcao_real` deixava passar um `balcaoReal` que já viesse
no pedido (um item copiado de um pedido antigo, ou uma app mexida) e carimbava produtos ao quilo,
cujo talão muda com o peso. A app nova do estafeta já ignora o balcão real nos produtos ao quilo.

```sql
-- Carimbo do balcão real (trigger BEFORE INSERT em orders), duas guardas novas — só ecrã:
--  (1) um `balcaoReal` que venha já no pedido (da app ou de outro lado) é sempre tirado: só o
--      servidor o carimba. Antes passava intacto e podia mostrar ao estafeta um balcão inventado
--      ou velho (ex.: item copiado de um pedido antigo cujo produto já não tem balcão real).
--  (2) produtos ao quilo (variable_weight) não levam balcão real: o talão deles muda com o peso.
--      A app do estafeta já os ignora (lib/services/preco_balcao.dart); o Telegram passa a bater.
CREATE OR REPLACE FUNCTION public._orders_carimba_balcao_real()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE v_out jsonb := '[]'::jsonb; v_it jsonb; v_real numeric; v_mudou boolean := false;
BEGIN
  BEGIN
    IF jsonb_typeof(NEW.items) IS DISTINCT FROM 'array' OR jsonb_array_length(NEW.items) = 0 THEN
      RETURN NEW;
    END IF;
    FOR v_it IN SELECT e.value FROM jsonb_array_elements(NEW.items) e LOOP
      IF jsonb_typeof(v_it) = 'object' AND v_it ? 'balcaoReal' THEN
        v_it := v_it - 'balcaoReal';
        v_mudou := true;
      END IF;
      v_real := NULL;
      IF NOT COALESCE(NEW.is_partner_store, false)
         AND (v_it->>'productId') IS NOT NULL AND (v_it->>'basePrice') IS NOT NULL
         AND COALESCE(v_it->>'variable_weight', 'false') <> 'true' THEN
        SELECT p.preco_balcao_real INTO v_real FROM products p
         WHERE p.id = v_it->>'productId' AND p.preco_balcao_real IS NOT NULL
           AND NOT COALESCE(p.variable_weight, false);
      END IF;
      IF v_real IS NOT NULL AND v_real > 0 AND v_real < (v_it->>'basePrice')::numeric THEN
        v_it := v_it || jsonb_build_object('balcaoReal', ROUND(v_real, 2));
        v_mudou := true;
      END IF;
      v_out := v_out || jsonb_build_array(v_it);
    END LOOP;
    IF v_mudou THEN NEW.items := v_out; END IF;
  EXCEPTION WHEN others THEN NULL;   -- nunca parte a criação do pedido
  END;
  RETURN NEW;
END $function$;
```

Prova (Postgres local, `BEGIN … ROLLBACK`):

```sql
-- Testes do carimbo e do resumo (correr dentro de BEGIN … ROLLBACK).
begin;
insert into restaurants values ('mc','McDonald''s Guarda','271000000',null),('parc','Loja Parceira','271000001',null);
insert into products(id, restaurant_id, name, price, variable_weight, preco_balcao_real) values
  ('bigmac','mc','Big Mac',6.20,false,5.65), ('banana','mc','Banana',1.30,true,1.10), ('sem-real','mc','Cola',2.00,false,null);
insert into orders(id, restaurant_id, is_partner_store, items) values
 ('t1','mc',false,'[{"productId":"bigmac","name":"Big Mac","price":7.13,"basePrice":6.20,"quantity":2},
                    {"productId":"banana","name":"Banana","price":1.50,"basePrice":1.30,"quantity":1,"variable_weight":true},
                    {"productId":"sem-real","name":"Cola","price":2.30,"basePrice":2.00,"quantity":1,"balcaoReal":0.01}]'),
 ('t2','parc',true,'[{"productId":"bigmac","name":"Big Mac","price":6.20,"basePrice":6.20,"quantity":1,"balcaoReal":3}]');
select id, i->>'name' as item, i->>'balcaoReal' as balcao_real,
       case i->>'name' when 'Big Mac' then (case id when 't1' then '5.65' else null end) else null end as esperado
  from orders o, jsonb_array_elements(o.items) i order by id, item;
select public.encomenda_telefone_resumo('t1')->>'total_balcao' as total_balcao_t1, '14.60 (2×5,65 + 1,30 + 2,00)' as esperado;
rollback;
```

Resultado: Big Mac de loja não-parceira com balcão real 5,65 → `balcaoReal 5.65`; banana ao quilo →
sem carimbo; Cola que trazia `balcaoReal 0.01` de fora (produto sem balcão real) → tirado; loja
parceira que trazia `balcaoReal 3` → tirado. `total_balcao` do resumo = 14.60 (2×5,65 + 1,30 + 2,00).

## 2. B3 — `encomenda_telefone_resumo` passa a `balcaoReal ?? basePrice` (só ecrã/aviso)

É o texto do aviso "📞 LIGAR À LOJA" (lista dos itens com o preço e o TOTAL BALCÃO), chamado por
`admin_chamar_estafeta_ja`. Nenhuma conta de dinheiro lê o `total_balcao`. Remendo por âncora: troca
uma linha na definição que está no ar e aborta sem mexer se a linha não aparecer exatamente uma vez.
Correr duas vezes não faz nada à segunda (provado).

```sql
-- B3 — encomenda_telefone_resumo (aviso "📞 LIGAR À LOJA": itens e TOTAL BALCÃO). Só texto.
-- Remendo por âncora: troca UMA linha na definição que está no ar; aborta sem mudar nada se a
-- linha não aparecer exatamente 1 vez.
do $remendo$
declare v_def text; v_anc text; v_rep text; v_n int;
begin
  v_def := pg_get_functiondef('public.encomenda_telefone_resumo(text)'::regprocedure);
  if position('balcaoReal' in v_def) > 0 then
    raise notice 'B3: encomenda_telefone_resumo já usa balcaoReal — nada a fazer';
    return;
  end if;
  v_anc := $a$      v_unit := ROUND((it->>'basePrice')::numeric + COALESCE(v_extra, 0), 2);$a$;
  v_rep := $b$      -- 28/11/2026 (balcao-real): balcaoReal = balcão lido no último talão (mais barato), carimbado
      -- pelo servidor só em lojas não-parceiras. Só texto do aviso: nada de dinheiro lê isto.
      v_unit := ROUND(COALESCE((it->>'balcaoReal')::numeric, (it->>'basePrice')::numeric) + COALESCE(v_extra, 0), 2);$b$;
  v_n := (length(v_def) - length(replace(v_def, v_anc, ''))) / length(v_anc);
  if v_n <> 1 then
    raise exception 'B3_ANCORA de encomenda_telefone_resumo aparece % vezes (esperado 1)', v_n;
  end if;
  execute replace(v_def, v_anc, v_rep);
end
$remendo$;
```

### Classificação das funções que leem `basePrice` (B3)

Varri todas as migrações do repo (última definição de cada função). As que leem `basePrice` são estas
nove; duas já foram feitas hoje pela Claude.ai.

- `_alerta_txt_pedido` — aviso do Telegram. Já usa `balcaoReal ?? basePrice` (migração 161639). Nada a fazer.
- `_orders_carimba_balcao_real` — o próprio carimbo. Guardas novas no bloco 1.
- `encomenda_telefone_resumo` — **ecrã/aviso**. SQL no bloco 2.
- `partner_chamar_estafeta` — **dinheiro** (cria o pedido do parceiro e grava `price`/`basePrice`).
  Só loja parceira, onde o balcão real não existe. Não se toca.
- `_order_edit_build` — **dinheiro** (o parceiro edita o pedido e o servidor recalcula os preços).
  Só parceiro. Não se toca.
- `estafeta_ajustar_peso` — **dinheiro** (calcula a diferença a cobrar/devolver ao cliente pelo peso).
  Tem de continuar a usar `basePrice`. Por isso a app ignora o balcão real nos produtos ao quilo
  (senão o "Previsto" e o intervalo de ±30 % da folha da balança deixavam de bater com o servidor).
- `_talao_casar_itens` — **dinheiro** (alimenta o robô que pode subir `products.price`). Usa
  `basePrice` só como referência da "caixa com preço partido em duas linhas". Não se toca.
- `_trg_alerta_preco_catalogo_fn` — aviso ao painel, mas mede **dinheiro**: o `catalog_price_gap_cents`
  ("talão menos preço base da app") alimenta o vigia "pedido no vermelho". A pergunta dele é "o
  preço do cliente cobre o talão?", que só o `basePrice` responde. Com o balcão real dava alarmes
  falsos (talão entre o balcão real e o preço normal, que o robô já trata sozinho). Recomendo não mudar.
- `demo_boom_criar_pedido` — cria pedidos da demonstração (escreve `basePrice`, chama `create_order`).
  Não lê para mostrar. Não se toca.

## 3. B4 — talão de UM só menu que não casou (pedido KFC 14658088)

Regra proposta: o pedido tem um só produto (fora os extras que o estafeta acrescenta), quantidade 1,
e é um menu (nome com menu/box/combo/balde/bucket, ou com opções pagas). O robô não casou nada
(`sem_match ≥ 1` e tudo o resto a 0). Então: **total do talão − sacos − depósitos − extras EXTRA… da
app = esse menu** (com as opções não-EXTRA, como no robô). Guardas iguais: 0,4× a 2,5× do preço.

- Confiança 0,95 só quando a loja lida bate com a do pedido (`store_check.ok`), o total impresso bate
  com a soma das linhas (±1 cêntimo) e com o valor escrito pelo estafeta (±1 cêntimo). Senão 0,6.
- Mais barato com 0,95 → só o balcão real do estafeta (`status='estafeta'`, revertível no painel).
- Mais caro, ou confiança 0,6 → proposta `pending` no painel. **Nunca sobe nem baixa o preço do
  cliente sozinho** (mais seguro que o robô normal, porque as peças não são as mesmas).
- Produto ao quilo, loja parceira, 2+ produtos, quantidade ≠ 1, talão já tratado → não entra.

```sql
-- B4 (missão balcao-real-2026-11-28) — talão de um só MENU cujas peças não batem com as da app
-- (pedido KFC 14658088: 3 hot wings, batata média e molhos ao balcão em vez da maçaroca).
-- Regra: pedido com UM só produto de menu (quantidade 1) que o robô não conseguiu casar →
-- total do talão − sacos − depósitos − extras EXTRA… da app = esse produto (com as opções não-EXTRA).
-- Guardas iguais às do robô (0,4× a 2,5× do preço). Confiança alta (0,95) só quando a loja lida bate
-- com a do pedido E o total impresso bate com a soma das linhas E com o valor escrito pelo estafeta.
-- Talão mais barato + confiança alta → só o balcão real do estafeta (status 'estafeta').
-- Tudo o resto (mais caro, confiança baixa) → proposta 'pending' para o painel. NUNCA sobe nem baixa
-- products.price sozinho: o preço do cliente só muda se o Danilo aprovar no painel.

-- (1) Conta pura (sem tabelas): fácil de testar.
create or replace function public._talao_menu_unico_conta(
  p_price numeric, p_outros numeric, p_mod numeric, p_lines jsonb,
  p_total_cents int, p_typed_cents int, p_loja_ok boolean)
 returns jsonb
 language plpgsql
 stable
 set search_path to 'public', 'extensions'
as $function$
declare
  v_soma int := 0; v_saco int := 0; v_dep int := 0; v_total int; v_l jsonb; v_val int;
  v_new_unit numeric(12,2); v_expected numeric(12,2); v_new_base numeric(12,2);
  v_total_ok boolean; v_conf numeric; v_dec text;
begin
  if p_price is null or p_price <= 0 or jsonb_typeof(p_lines) is distinct from 'array' then
    return jsonb_build_object('decisao', 'sem_dados');
  end if;
  for v_l in select e.value from jsonb_array_elements(p_lines) e loop
    v_val := round(coalesce((v_l->>'qty')::numeric, 1) * coalesce((v_l->>'unit_price_cents')::numeric, 0))::int;
    v_soma := v_soma + v_val;
    if public._talao_e_saco(v_l->>'name') then v_saco := v_saco + v_val;
    elsif public._talao_e_deposito(v_l->>'name') then v_dep := v_dep + v_val;
    end if;
  end loop;
  v_total := coalesce(p_total_cents, v_soma);
  v_new_unit := round((v_total - v_saco - v_dep) / 100.0 - coalesce(p_mod, 0), 2);
  v_expected := round(p_price + coalesce(p_outros, 0), 2);
  v_new_base := round(v_new_unit - coalesce(p_outros, 0), 2);
  v_total_ok := p_total_cents is not null and abs(v_soma - p_total_cents) <= 1
                and p_typed_cents is not null and abs(p_typed_cents - p_total_cents) <= 1;
  v_conf := case when coalesce(p_loja_ok, false) and v_total_ok then 0.95 else 0.6 end;
  v_dec := case
    when v_new_base <= 0 or v_new_base < p_price * 0.4 or v_new_base > p_price * 2.5 then 'absurda'
    when v_new_unit = v_expected then 'igual'
    when v_new_unit < v_expected and v_conf >= 0.9 then 'estafeta'
    else 'pending' end;
  return jsonb_build_object('decisao', v_dec, 'confianca', v_conf, 'total_cents', v_total,
    'soma_linhas_cents', v_soma, 'sacos_cents', v_saco, 'depositos_cents', v_dep,
    'novo_unit', v_new_unit, 'esperado', v_expected, 'nova_base', v_new_base,
    'loja_ok', coalesce(p_loja_ok, false), 'total_ok', v_total_ok);
end $function$;

-- (2) Aplicar a um talão (chamada pelo robô quando nada casou).
create or replace function public._talao_menu_unico_aplicar(p_receipt_id uuid, p_items jsonb)
 returns jsonb
 language plpgsql
 security definer
 set search_path to 'public', 'extensions'
as $function$
declare
  v_r record; v_order record; v_item jsonb; v_prod record; v_nome text;
  v_mod numeric := 0; v_outros numeric := 0; v_c jsonb; v_dec text; v_linha text;
begin
  select r.id, r.order_id, r.receipt_parsed, r.receipt_parsed_total_cents, r.driver_typed_total_cents
    into v_r from order_receipts_v2 r where r.id = p_receipt_id;
  if v_r.id is null then return jsonb_build_object('ok', false, 'error', 'receipt_not_found'); end if;
  select o.id, o.restaurant_id, o.is_partner_store into v_order from orders o where o.id = v_r.order_id;
  if v_order.id is null or coalesce(v_order.is_partner_store, false) then
    return jsonb_build_object('ok', true, 'skipped', 'sem_pedido_ou_parceiro');
  end if;
  -- os extras acrescentados pelo estafeta (productId extra_…) não contam como produto do pedido
  select coalesce(jsonb_agg(i), '[]'::jsonb) into p_items
    from jsonb_array_elements(coalesce(p_items, '[]'::jsonb)) i
   where coalesce(i->>'productId', '') not like 'extra\_%';
  if jsonb_array_length(p_items) <> 1 then
    return jsonb_build_object('ok', true, 'skipped', 'nao_e_um_so_produto');
  end if;
  v_item := p_items->0;
  if coalesce((v_item->>'quantity')::numeric, 1) <> 1 then
    return jsonb_build_object('ok', true, 'skipped', 'quantidade_diferente_de_1');
  end if;
  v_nome := public._talao_norm(v_item->>'name');
  if not (v_nome ~ '(^| )(menu|box|combo|balde|bucket)( |$)'
          or (jsonb_typeof(v_item->'selected_options_priced') = 'array'
              and jsonb_array_length(v_item->'selected_options_priced') > 0)) then
    return jsonb_build_object('ok', true, 'skipped', 'nao_e_menu');
  end if;
  select p.id, p.price, p.restaurant_id, p.preco_balcao_real, coalesce(p.variable_weight, false) as vw
    into v_prod from products p
   where p.id = (v_item->>'productId') and p.restaurant_id::text = v_order.restaurant_id::text;
  if v_prod.id is null or v_prod.price is null or v_prod.price <= 0 or v_prod.vw then
    return jsonb_build_object('ok', true, 'skipped', 'produto_fora_da_loja_ou_ao_quilo');
  end if;
  if exists (select 1 from catalog_price_updates c
              where c.receipt_id = p_receipt_id and c.product_id = v_prod.id and c.option_item_id is null) then
    return jsonb_build_object('ok', true, 'skipped', 'ja_tratado');
  end if;
  begin
    select coalesce(sum((gi.value->>'price_add')::numeric) filter (where public._talao_e_modificador(gi.value->>'name')), 0),
           coalesce(sum((gi.value->>'price_add')::numeric) filter (where not public._talao_e_modificador(gi.value->>'name')), 0)
      into v_mod, v_outros
      from jsonb_array_elements(case when jsonb_typeof(v_item->'selected_options_priced') = 'array'
                                     then v_item->'selected_options_priced' else '[]'::jsonb end) g,
           jsonb_array_elements(case when jsonb_typeof(g.value->'items') = 'array'
                                     then g.value->'items' else '[]'::jsonb end) gi;
  exception when others then
    return jsonb_build_object('ok', true, 'skipped', 'opcoes_ilegiveis');
  end;

  v_c := public._talao_menu_unico_conta(v_prod.price, v_outros, v_mod, v_r.receipt_parsed->'lines',
           v_r.receipt_parsed_total_cents, v_r.driver_typed_total_cents,
           coalesce((v_r.receipt_parsed->'store_check'->>'ok')::boolean, false));
  v_dec := v_c->>'decisao';
  v_linha := 'MENU ÚNICO: total do talão ' || to_char((v_c->>'total_cents')::numeric / 100, 'FM9990.00')
          || ' − sacos ' || to_char((v_c->>'sacos_cents')::numeric / 100, 'FM9990.00')
          || ' − depósitos ' || to_char((v_c->>'depositos_cents')::numeric / 100, 'FM9990.00');

  if v_dec = 'igual' then
    update products set preco_balcao_real = null, preco_balcao_real_em = now(), preco_balcao_real_fonte = p_receipt_id
     where id = v_prod.id and preco_balcao_real is not null;
  elsif v_dec = 'estafeta' then
    if v_prod.preco_balcao_real is not null and v_prod.preco_balcao_real = (v_c->>'nova_base')::numeric then
      v_dec := 'igual';
    else
      update products set preco_balcao_real = (v_c->>'nova_base')::numeric, preco_balcao_real_em = now(),
                          preco_balcao_real_fonte = p_receipt_id
       where id = v_prod.id;
      insert into catalog_price_updates
        (product_id, restaurant_id, order_id, receipt_id, old_base, new_base, confianca, linha_talao, status, decided_at, decided_by)
      values (v_prod.id, v_prod.restaurant_id::text, v_order.id, p_receipt_id, round(v_prod.price::numeric, 2),
              (v_c->>'nova_base')::numeric, (v_c->>'confianca')::numeric, v_linha, 'estafeta', now(), 'robot');
    end if;
  elsif v_dec = 'pending' then
    insert into catalog_price_updates
      (product_id, restaurant_id, order_id, receipt_id, old_base, new_base, confianca, linha_talao, status)
    values (v_prod.id, v_prod.restaurant_id::text, v_order.id, p_receipt_id, round(v_prod.price::numeric, 2),
            (v_c->>'nova_base')::numeric, (v_c->>'confianca')::numeric, v_linha, 'pending');
  end if;
  return jsonb_build_object('ok', true, 'decisao', v_dec, 'conta', v_c, 'product_id', v_prod.id);
end $function$;

revoke all on function public._talao_menu_unico_conta(numeric, numeric, numeric, jsonb, int, int, boolean) from public, anon, authenticated;
revoke all on function public._talao_menu_unico_aplicar(uuid, jsonb) from public, anon, authenticated;
```

## 4. B4 — ligar o "menu único" ao robô (remendo por âncora)

Troca 3 âncoras exatas na definição de `catalog_price_update_from_receipt` que está no ar (a da
migração 20261128161615). Aborta sem mudar nada se alguma âncora não aparecer exatamente uma vez.
Idempotente (provado: a segunda vez só avisa).

```sql
-- (3) Ligar o "menu único" ao robô do talão, sem reescrever a função inteira: troca 3 âncoras
-- exatas na definição que está no ar (cada uma tem de aparecer 1 vez, senão aborta e não muda nada).
do $remendo$
declare
  v_def text; v_new text; v_anc text[]; v_rep text[]; v_n int; i int;
begin
  v_def := pg_get_functiondef('public.catalog_price_update_from_receipt(uuid)'::regprocedure);
  if position('_talao_menu_unico_aplicar' in v_def) > 0 then
    raise notice 'B4: o robô já chama o menu único — nada a fazer';
    return;
  end if;
  v_anc := array[
$a$  v_estafeta   int := 0;   -- 28/11/2026: mais barato aplicado só ao preço que o estafeta vê$a$,
$a$  RETURN jsonb_build_object('ok', true, 'aplicadas', v_aplicadas, 'pendentes', v_pendentes,$a$,
$a$'extras_mais_caros', v_extras, 'extras_pendentes', v_extras_pend);$a$
  ];
  v_rep := array[
$b$  v_estafeta   int := 0;   -- 28/11/2026: mais barato aplicado só ao preço que o estafeta vê
  v_menu_unico jsonb;      -- 28/11/2026 (B4): pedido de um só menu que não casou$b$,
$b$  -- 28/11/2026 (B4 balcao-real, pedido KFC 14658088): nada casou e o pedido é UM só menu →
  -- total do talão − sacos − depósitos = esse menu. Nunca mexe em products.price.
  IF v_aplicadas + v_pendentes + v_estafeta + v_iguais + v_segunda + v_absurdas = 0 AND v_sem_match >= 1 THEN
    BEGIN
      v_menu_unico := public._talao_menu_unico_aplicar(p_receipt_id, v_items);
    EXCEPTION WHEN others THEN
      v_menu_unico := jsonb_build_object('ok', false, 'error', SQLERRM);
    END;
  END IF;

  RETURN jsonb_build_object('ok', true, 'aplicadas', v_aplicadas, 'pendentes', v_pendentes,$b$,
$b$'extras_mais_caros', v_extras, 'extras_pendentes', v_extras_pend, 'menu_unico', v_menu_unico);$b$
  ];
  v_new := v_def;
  for i in 1 .. array_length(v_anc, 1) loop
    v_n := (length(v_new) - length(replace(v_new, v_anc[i], ''))) / length(v_anc[i]);
    if v_n <> 1 then
      raise exception 'B4_ANCORA % de catalog_price_update_from_receipt aparece % vezes (esperado 1)', i, v_n;
    end if;
    v_new := replace(v_new, v_anc[i], v_rep[i]);
  end loop;
  execute v_new;
end
$remendo$;
```

### Casos de teste do B4 (conta pura)

```sql
-- Casos de teste do B4 (conta pura). Correr dentro de BEGIN … ROLLBACK; cada linha diz o esperado.
-- Pedido KFC 14658088: Box Meal Mix (preço 13,23) + Maçaroca (+2,44, opção não-EXTRA). Talão 13,60
-- com "DEPOSITO 0,75". As linhas abaixo imitam um talão de combo com peças diferentes das da app.
with l as (select '[
  {"name":"BOX MEAL MIX","qty":1,"unit_price_cents":1060},
  {"name":"3 HOT WINGS","qty":1,"unit_price_cents":0},
  {"name":"BATATA MEDIA","qty":1,"unit_price_cents":125},
  {"name":"MOLHO BBQ","qty":1,"unit_price_cents":100},
  {"name":"DEPOSITO","qty":1,"unit_price_cents":75}]'::jsonb as lines),
casos(caso, esperado, r) as (
  select 'a) KFC: loja e total batem → só estafeta, base 10,41', 'estafeta',
         public._talao_menu_unico_conta(13.23, 2.44, 0, (select lines from l), 1360, 1360, true)
  union all
  select 'b) total escrito pelo estafeta diferente → pending', 'pending',
         public._talao_menu_unico_conta(13.23, 2.44, 0, (select lines from l), 1360, 1400, true)
  union all
  select 'c) loja lida não bate → pending', 'pending',
         public._talao_menu_unico_conta(13.23, 2.44, 0, (select lines from l), 1360, 1360, false)
  union all
  select 'd) talão MAIS CARO → pending (nunca sobe o cliente sozinho)', 'pending',
         public._talao_menu_unico_conta(13.23, 2.44, 0,
           '[{"name":"BOX MEAL MIX","qty":1,"unit_price_cents":1800}]'::jsonb, 1800, 1800, true)
  union all
  select 'e) leitura partida (0,56 €) → absurda', 'absurda',
         public._talao_menu_unico_conta(13.23, 2.44, 0,
           '[{"name":"BOX MEAL MIX","qty":1,"unit_price_cents":300}]'::jsonb, 300, 300, true)
  union all
  select 'f) com saco 0,30 → saco fora, mesma base 10,41', 'estafeta',
         public._talao_menu_unico_conta(13.23, 2.44, 0,
           (select lines from l) || '[{"name":"SACO","qty":1,"unit_price_cents":30}]'::jsonb, 1390, 1390, true)
  union all
  select 'g) talão igual ao da app → igual', 'igual',
         public._talao_menu_unico_conta(13.23, 2.44, 0,
           '[{"name":"BOX MEAL MIX","qty":1,"unit_price_cents":1567}]'::jsonb, 1567, 1567, true)
  union all
  select 'h) soma das linhas não bate com o total impresso → pending', 'pending',
         public._talao_menu_unico_conta(13.23, 2.44, 0,
           '[{"name":"BOX MEAL MIX","qty":1,"unit_price_cents":1100}]'::jsonb, 1285, 1285, true)
)
select caso, esperado, r->>'decisao' as deu, r->>'nova_base' as nova_base,
       (r->>'decisao') = esperado as passou
  from casos order by caso;
```

Resultado no Postgres local: 8 de 8 passaram (a: estafeta 10,41 · b, c, d, h: pending · e: absurda ·
f: estafeta 10,41 com o saco fora · g: igual).

Prova ponta-a-ponta (robô inteiro + remendo, pedido imitado do KFC com 3 hot wings 8,75, batata média
2,10, molho 2,00 e depósito 0,75 = 13,60): `sem_match 1`, `menu_unico.decisao = estafeta`,
`products.price` continua 13,23, `preco_balcao_real` = 10,41 (o estafeta passa a ver 10,41 + 2,44 da
maçaroca = 12,85 €), uma linha `catalog_price_updates` "MENU ÚNICO: total do talão 13.60 − sacos 0.00
− depósitos 0.75". Segundo passe no mesmo talão → `ja_tratado`, sem linha nova. Pedido com 2 produtos
→ `nao_e_um_so_produto`.

## 5. Prova no talão real, antes de aplicar o bloco 4 (transação desfeita)

Colar os blocos 3 e 4 depois do `begin`, ver o que o robô faria ao talão real e desfazer tudo:

```sql
begin;
-- (colar aqui o bloco 3 e o bloco 4)
select public.catalog_price_update_from_receipt('73a07b48-f1f3-48b7-bd0f-9e9981c0d0b0') -> 'menu_unico';
select id, price, preco_balcao_real from products
 where id = (select o.items->0->>'productId' from orders o
              join order_receipts_v2 r on r.order_id = o.id
             where r.id = '73a07b48-f1f3-48b7-bd0f-9e9981c0d0b0');
rollback;
```

Se o talão real der `pending` (confiança baixa) está certo na mesma: a proposta vai para o painel e o
Danilo decide. Se a primeira volta do robô já tiver casado outra linha, o menu único não corre.

## 6. Reportado, NÃO proposto (mexe em dinheiro)

- O robô do talão (`catalog_price_update_from_receipt`) **não exclui produtos ao quilo**: um talão
  mais pesado do que o previsto pode subir sozinho `products.price` (até +50 %). ⚠️ ISTO MEXE EM
  DINHEIRO: a guarda seria `AND NOT COALESCE(p.variable_weight, false)` nas duas voltas. Fica para o
  "autorizo" do Danilo.
- Talão do KFC com "DEPOSITO 0,75" quando a app cobrou 0,10 € de depósito Volta pela lata. Ou a KFC
  cobra outro depósito (copo/caixa), ou o 0,75 junta várias embalagens. ⚠️ ISTO MEXE EM DINHEIRO
  (depósito cobrado ao cliente): só relatório.
