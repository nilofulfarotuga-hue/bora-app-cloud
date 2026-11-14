# Bloco 3 (g) — os itens ficam "pending" depois de o estafeta fechar a compra

> fechar-app-15-11 · escrito a 14/11/2026 (23h UTC) pelo ajudante `dispatch` (só leitura e proposta).
> Nada aqui foi aplicado. Produção só foi lida.
> Prova local: `supabase/tests/fechar_app_3g_prova.mjs` (PGlite).

## 1. Em poucas palavras

É verdade e é geral: quando o estafeta fecha a compra numa loja não-parceira, a função
grava o que aconteceu a cada produto (comprado, não havia, trocado) numa tabela à parte
(`order_purchase_items_v2`) e **nunca volta a escrever na lista do pedido**
(`orders.items`). A lista fica para sempre com `purchaseStatus: "pending"`.

O estrago visível é mais pequeno do que parece: na app do cliente não se nota (o ecrã
que aparece depois do fecho já lê a tabela certa). Nota-se no **painel** (os itens de um
pedido entregue aparecem todos como "pending") e no **recibo do cliente** (lista todos
os produtos pedidos, incluindo os que não havia). E engana quem lê o pedido por SQL,
agentes incluídos.

Proponho acertar a lista **sem tocar na função do dinheiro**: um gatilho pequeno que,
quando o pedido já fechado segue para entrega, copia o estado de cada produto da tabela
do talão para a lista do pedido. Só escreve `purchaseStatus`. Não toca em valores.

## 2. A prova

Lido em produção a 14/11/2026.

- **Pedido `b2b746d7` (Auchan):** `orders.items` tem 12 produtos, todos
  `purchaseStatus = 'pending'`. `order_purchase_items_v2` tem 12 linhas: 7 `purchased`,
  3 `replaced`, 2 `unavailable`.
- **A função não escreve na lista.** `finalizar_talao_nao_parceiro` (20 536 caracteres,
  md5 da definição `d2c931572e9679d881ac4a1057015de1`) faz, por esta ordem: linhas
  146–180 grava as linhas do talão em `order_purchase_items_v2`; linhas 285–300 acerta
  os totais e põe `is_purchase_finalized = true`; linhas 342–343
  `UPDATE public.orders SET status = 'onTheWay'`. Em nenhum sítio há `items =`. A outra
  função de fecho, `finalize_storeshopping_purchase_v2`, faz igual (linhas 96, 162–176, 203).
  Só a antiga `finalize_storeshopping_purchase` (v1) reescrevia `purchaseStatus`.
- **Não é só este pedido.** Há 46 pedidos com linhas do talão (23 de restaurante
  não-parceiro, 23 de mercado). Em 43 deles a lista está toda `pending`, e os 43 estão
  entregues. Em 7 desses houve produtos em falta ou trocados.
- **As linhas do talão não trazem o identificador do produto.** Em 151 das 153 linhas,
  `original_item_id` está vazio: a função só o guarda se parecer um UUID, e os produtos
  dos mercados têm identificadores como `auc-…`. A coluna é de texto, cabia. Por isso só
  dá para casar as linhas com a lista pelo nome, preço e quantidade.
- **Casar por nome + preço + quantidade funciona em 143 de 152 produtos** desses
  pedidos. Os 9 que não casam estão em 3 pedidos antigos (num deles o talão foi gravado
  numa linha só). Esses ficam como estão.

## 3. Quem lê `orders.items[].purchaseStatus` depois do fecho

**App do cliente — não se vê erro.** O único sítio que lê é
`lib/screens/order_details_screen.dart`, cartão "O que compraste" (`_ItemsCard`, linha
1175: risca os `unavailable`). Mas esse cartão fica escondido quando
`purchaseFlowVersion == 2` (linha 134), que é o que estas funções de fecho gravam; em
vez dele aparece `_PurchaseV2Card` (linha 1517), que lê `order_purchase_items_v2` e
mostra a verdade.

**Painel (PT-BR) — vê-se errado.** `lib/screens/admin/admin_order_detail_screen.dart`,
`_buildCanonicalRow` (linhas 722–758): pinta de verde o `bought`, de vermelho e riscado
o `unavailable`, e escreve o estado em letra pequena. Hoje um pedido entregue mostra os
12 produtos com "pending", sem verde nem vermelho. A secção das faltas
(`admin_substituicao_section.dart`) está certa: lê as linhas do talão e só cai na lista
do pedido quando elas não existem.

**Recibo do cliente — sai errado, por outra razão.** `_recibo_pedido` não lê
`purchaseStatus`: lista todos os `orders.items` com o preço pedido (linhas 32–37). Para o
`b2b746d7` devolve 12 linhas que somam 33,56 € (o subtotal antes da compra); o pedido
fechou em 32,27 € no total, com 2 produtos em falta e 3 trocados. O recibo mostra
produtos que não vieram.

**App do estafeta.** `driver_map_screen.dart` e `compra_rascunho_service.dart` usam o
`purchaseStatus` durante a compra. Depois do fecho já não mostram a lista.

**Funções SQL.** Nenhuma lê depois do fecho. `partner_chamar_estafeta` e
`_order_edit_build` só escrevem `'pending'` ao criar. As funções da Supabase
(`supabase/functions/`) não leem `purchaseStatus`; `notify-purchase-finalized` lê a
tabela do talão.

**Quem lê por SQL.** Um agente ou uma consulta que olhe para `orders.items` de um pedido
entregue vê "pending" em tudo e conclui que a compra não foi marcada. Foi assim que
este caso apareceu.

## 4. `_rascunho_compra_itens_fecho` já serve?

Não, faz o caminho contrário. Essa função (migração por aplicar
`20261114190000_compra_guardada_e_fila_estafeta.sql`) pega no rascunho da compra
(`order_purchase_drafts`) e monta o `p_items` que o fecho recebe, para se poder fechar
pelo painel ou por MCP sem refazer a compra. Não escreve em `orders.items`, só existe
para pedidos com rascunho, e não conhece "trocado". Depois de um fecho feito com ela a
lista do pedido fica `pending` na mesma. A proposta abaixo não depende dessa migração
nem choca com ela.

## 5. A proposta

**Passo A (daqui para a frente).** Uma função que calcula a lista com o estado certo e
um gatilho que a usa.

- Quando: `BEFORE UPDATE OF status` em `orders`, só quando o estado passa para
  `onTheWay` ou `delivered` e o pedido já tem `is_purchase_finalized = true`. As duas
  funções de fecho acabam com `UPDATE … SET status = 'onTheWay'` depois de gravarem o
  talão, por isso o gatilho já encontra as linhas. O `delivered` serve de rede: se o
  fecho foi feito com o pedido já a caminho, acerta na entrega.
- O quê: muda só a chave `purchaseStatus` de cada produto. `purchased` → `bought`,
  `unavailable` → `unavailable`, `replaced` → `replaced` (valor novo; a app só compara
  com `bought`, `unavailable` e `pending`, por isso um trocado aparece neutro, como hoje).
- Não acrescenta nem tira produtos, não muda nomes, preços nem quantidades. Os
  produtos que o estafeta acrescentou (`added`) continuam só na tabela do talão.
- Produto que não casa com nenhuma linha do talão fica como estava. Não se adivinha.
- Se alguma coisa falhar lá dentro, o gatilho avisa (`WARNING`) e deixa o pedido seguir
  com a lista como estava. Nunca trava um fecho.
- Não toca em `finalizar_talao_nao_parceiro` nem em `finalize_storeshopping_purchase_v2`.
  O gatilho `orders_financial_lock` não é chamado a decidir nada: nenhuma coluna de
  dinheiro muda.

<!-- SQL-3G:INICIO -->
```sql
-- ════════════════════════════════════════════════════════════════════════════
-- PROPOSTA fechar-app-15-11 (3g) — o estado de cada produto (comprado / não havia /
-- trocado) passa a ficar também em orders.items[].purchaseStatus. NÃO APLICADA.
-- Cicatriz: 14/11/2026, pedido b2b746d7 (Auchan): 12 produtos "pending" depois de
-- fechado e entregue; a verdade só estava em order_purchase_items_v2.
-- Não mexe em finalizar_talao_nao_parceiro nem em finalize_storeshopping_purchase_v2,
-- nem em nenhuma coluna de dinheiro.
-- ════════════════════════════════════════════════════════════════════════════

-- A lista do pedido com o purchaseStatus tirado das linhas do talão. Casa por nome +
-- preço + quantidade (as linhas do talão quase nunca trazem o identificador do produto).
-- Produtos iguais repetidos: o 1.º com a 1.ª linha, o 2.º com a 2.ª…; se houver menos
-- linhas do que produtos (o gatilho trg_opi_v2_block_duplicate junta linhas iguais), os
-- que sobram recebem o estado das outras só quando todas dizem o mesmo. Sem par: fica
-- como estava. Só calcula, não grava nada.
CREATE OR REPLACE FUNCTION public._itens_com_estado_do_talao(p_order_id text, p_items jsonb)
RETURNS jsonb
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path TO 'public'
AS $$
  WITH it AS (
    SELECT e.value AS v, e.ordinality AS n,
           COALESCE(e.value->>'name', '') AS nome,
           round(COALESCE(NULLIF(e.value->>'price', '')::numeric, 0) * 100)::int AS preco,
           COALESCE(NULLIF(e.value->>'quantity', '')::numeric, 1) AS qtd
      FROM jsonb_array_elements(CASE WHEN jsonb_typeof(p_items) = 'array'
                                     THEN p_items ELSE '[]'::jsonb END) WITH ORDINALITY e
  ), k AS (
    SELECT it.*, row_number() OVER (PARTITION BY it.nome, it.preco, it.qtd ORDER BY it.n) AS vez
      FROM it
  ), t AS (
    SELECT COALESCE(l.original_name, '') AS nome,
           COALESCE(l.original_price_cents, 0) AS preco,
           COALESCE(l.original_qty, 1)::numeric AS qtd,
           l.status,
           row_number() OVER w AS vez,
           count(*) OVER (PARTITION BY l.original_name, l.original_price_cents, l.original_qty) AS quantas,
           min(l.status) OVER (PARTITION BY l.original_name, l.original_price_cents, l.original_qty)
             = max(l.status) OVER (PARTITION BY l.original_name, l.original_price_cents, l.original_qty) AS todas_iguais
      FROM public.order_purchase_items_v2 l
     WHERE l.order_id = p_order_id
       AND l.status IN ('purchased', 'replaced', 'unavailable')
    WINDOW w AS (PARTITION BY l.original_name, l.original_price_cents, l.original_qty
                 ORDER BY CASE l.status WHEN 'purchased' THEN 1 WHEN 'replaced' THEN 2 ELSE 3 END, l.id)
  )
  SELECT COALESCE(
           jsonb_agg(
             CASE WHEN t.status IS NULL THEN k.v
                  ELSE k.v || jsonb_build_object('purchaseStatus',
                         CASE t.status WHEN 'purchased' THEN 'bought'
                                       WHEN 'replaced' THEN 'replaced'
                                       ELSE 'unavailable' END)
             END ORDER BY k.n),
           p_items)
    FROM k
    LEFT JOIN t
      ON t.nome = k.nome AND t.preco = k.preco AND t.qtd = k.qtd
     AND (t.vez = k.vez
          OR (k.vez > t.quantas AND t.todas_iguais AND t.vez = t.quantas));
$$;
REVOKE ALL ON FUNCTION public._itens_com_estado_do_talao(text, jsonb) FROM PUBLIC, anon, authenticated;

CREATE OR REPLACE FUNCTION public.fn_orders_itens_estado_do_talao()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
BEGIN
  -- Nunca trava a mudança do pedido: se algo falhar, a lista fica como estava.
  BEGIN
    IF jsonb_typeof(NEW.items) = 'array'
       AND EXISTS (SELECT 1 FROM public.order_purchase_items_v2 l WHERE l.order_id = NEW.id) THEN
      NEW.items := public._itens_com_estado_do_talao(NEW.id, NEW.items);
    END IF;
  EXCEPTION WHEN OTHERS THEN
    RAISE WARNING '[fn_orders_itens_estado_do_talao] pedido %: %', NEW.id, SQLERRM;
  END;
  RETURN NEW;
END;
$$;
REVOKE ALL ON FUNCTION public.fn_orders_itens_estado_do_talao() FROM PUBLIC, anon, authenticated;

-- As duas funções de fecho acabam com UPDATE … SET status = 'onTheWay' depois de
-- gravarem o talão; 'delivered' é a rede para um fecho feito já a caminho.
DROP TRIGGER IF EXISTS trg_orders_itens_estado_do_talao ON public.orders;
CREATE TRIGGER trg_orders_itens_estado_do_talao
  BEFORE UPDATE OF status ON public.orders
  FOR EACH ROW
  WHEN (NEW.status IN ('onTheWay', 'delivered')
        AND NEW.status IS DISTINCT FROM OLD.status
        AND COALESCE(NEW.is_purchase_finalized, false))
  EXECUTE FUNCTION public.fn_orders_itens_estado_do_talao();
```
<!-- SQL-3G:FIM -->

**Passo B (pedidos antigos, opcional, só com ordem expressa).** Acerta os pedidos já
fechados (à volta de 43). É um `UPDATE` em `orders`, por isso leva cópia de segurança
e precisa de ordem do Danilo. Só muda a coluna `items`. Precisa do Passo A aplicado.

<!-- SQL-3G-ANTIGOS:INICIO -->
```sql
-- PROPOSTA fechar-app-15-11 (3g), Passo B — acertar os pedidos já fechados. NÃO APLICADA.
-- Antes: correr em transação com ROLLBACK e contar as linhas.
CREATE TABLE IF NOT EXISTS public.bkp_orders_items_talao_20261115 AS
  SELECT o.id, o.items, now() AS guardado_em
    FROM public.orders o
   WHERE jsonb_typeof(o.items) = 'array'
     AND COALESCE(o.is_purchase_finalized, false)
     AND EXISTS (SELECT 1 FROM public.order_purchase_items_v2 l WHERE l.order_id = o.id)
     AND o.items IS DISTINCT FROM public._itens_com_estado_do_talao(o.id, o.items);
ALTER TABLE public.bkp_orders_items_talao_20261115 ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.bkp_orders_items_talao_20261115 FROM anon, authenticated;

UPDATE public.orders o
   SET items = public._itens_com_estado_do_talao(o.id, o.items)
  FROM public.bkp_orders_items_talao_20261115 b
 WHERE b.id = o.id
   AND o.items IS NOT DISTINCT FROM b.items;
```
<!-- SQL-3G-ANTIGOS:FIM -->

**Como desfazer.** Passo A: `DROP TRIGGER trg_orders_itens_estado_do_talao ON public.orders;`
e apagar as duas funções; o que já foi acertado na lista não estraga nada. Passo B:
`UPDATE public.orders o SET items = b.items FROM public.bkp_orders_items_talao_20261115 b WHERE b.id = o.id;`.

## 6. Porque assim e não de outra maneira

- **Dentro de `finalizar_talao_nao_parceiro`.** Seria o sítio mais direto, mas obriga a
  reescrever uma função de 20 mil caracteres que mexe em dinheiro para lhe juntar uma
  linha, e ficava por fazer na outra função de fecho. O gatilho cobre as duas e não
  toca em nenhuma.
- **Só corrigir quem lê** (o painel passar a ler a tabela do talão). Resolve o painel,
  mas a lista do pedido continua a mentir a quem a ler a seguir. Pode fazer-se depois,
  sem pressa.
- **Gatilho quando se grava o talão** (`order_purchase_items_v2`). Dispararia uma vez
  por produto, cada uma com um `UPDATE` ao pedido a meio da função do dinheiro. Mais
  arriscado do que um gatilho que só muda a linha que já está a ser gravada.

## 7. Limites conhecidos

- **Trocado aparece como `replaced`, sem dizer por quê.** O nome do produto que veio
  continua só na tabela do talão. No painel aparece a palavra "replaced" em letra
  pequena (o painel escreve o estado tal como vem). Traduzir é uma linha na app.
- **Produtos iguais repetidos com estados diferentes.** O gatilho de produção
  `trg_opi_v2_block_duplicate` junta linhas iguais do talão; se três produtos iguais
  tiveram destinos diferentes, não dá para saber qual foi qual. Nesse caso os que
  sobram ficam como estavam.
- **O recibo do cliente continua a listar tudo.** `_recibo_pedido` não lê
  `purchaseStatus`. Com a lista acertada passa a ser possível saltar os `unavailable`
  com uma condição, mas é o documento que vai ao cliente: fica para decisão à parte.
- **Fecho feito por fora com nomes diferentes dos do pedido** não casa (ficam `pending`).

## 8. Para aplicar

- Não é dinheiro nem despacho: nenhuma coluna de valores muda e as funções de fecho
  ficam iguais. Mas é um gatilho novo na tabela `orders`, por isso peço ordem na mesma.
- Ordem do Danilo precisa para o Passo A: uma frase com data (ex.: "aplica o acerto do
  estado dos itens depois do talão, 15/11"). Para o Passo B, outra, porque escreve em
  pedidos já entregues (ex.: "acerta também os pedidos antigos").
- Quem aplica: a Claude.ai, por migração com o bloco SQL do Passo A (cópia exata).
- Depois de aplicar, prova em produção só por leitura: o gatilho existe
  (`pg_trigger`), e no próximo pedido de loja não-parceira fechado,
  `orders.items` deixa de ter `pending` nos produtos que casam com o talão.
- Passo B: ensaiar primeiro em transação com `ROLLBACK`, contar as linhas, e só depois
  aplicar. A cópia fica em `bkp_orders_items_talao_20261115`.

## 9. O que ficou por provar

- A prova é local (PGlite). O fecho usado é uma réplica das três frases de
  `finalizar_talao_nao_parceiro` que interessam (gravar o talão, marcar fechado, passar
  a `onTheWay`), pela mesma ordem; a função verdadeira não corre fora de produção sem
  meia base de dados atrás.
- Não corri o gatilho ao lado dos outros 46 gatilhos `BEFORE` de `orders`. Não vejo
  choque: o gatilho só muda a chave `purchaseStatus` dentro de `items`, e nenhuma função
  SQL de produção lê essa chave fora da criação do pedido e do fecho antigo (secção 3);
  `trg_checkin_premio_items_guarda` só dispara quando o `UPDATE` nomeia a coluna
  `items`. Mas não está provado com os gatilhos verdadeiros.
- O Passo B não foi ensaiado contra produção: o `UPDATE` nomeia `items`, por isso
  dispara `trg_checkin_premio_items_guarda` e os gatilhos sem lista de colunas. Não
  mudam nada à partida, mas é para ver no ensaio com `ROLLBACK`.
- Não vi o ecrã do painel num navegador (modo leve).

## 10. Outros erros vistos (só reportar)

1. **`original_item_id` perde-se em quase todas as linhas do talão** (151 de 153). A
   função só o guarda quando parece um UUID e ainda o converte para UUID, numa coluna
   que é de texto. É uma linha dentro da função do dinheiro (linhas 153–154); com o
   identificador guardado, casar as linhas com a lista deixava de depender do nome.
2. **Recibo do cliente com produtos que não vieram** (secção 3). Vale para todos os
   pedidos de loja não-parceira com faltas ou trocas.
3. **O fecho do `b2b746d7` trouxe 3 linhas `replaced`, que a app do estafeta não sabe
   mandar** (`TalaoNaoParceiroService.montarItens` só manda `purchased`, `unavailable`
   e `added`). Bate com o que está na proposta 3f: esse fecho não veio da app.
4. **`trg_opi_v2_block_duplicate` engole linhas iguais sem avisar** (devolve `NULL`).
   Dois produtos iguais na mesma compra ficam numa linha só no talão.
