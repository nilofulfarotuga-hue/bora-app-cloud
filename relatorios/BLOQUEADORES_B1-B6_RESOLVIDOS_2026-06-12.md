# SESSÃO BLOQUEADORES PRÉ-LAUNCH — 2026-06-12 ✅

**Origem:** AUDITORIA_GERAL_PRE_LAUNCH_2026-06-12.md · **Modo:** commit por bloco, push único.
**Settings já na DB (confirmados por SELECT antes de tudo):** `delivery_max_distance_km=15` · `token_payment_max_pct=50` · `token_withdrawal_max_pct_weekly=50` · `partner_driver_stacking_bonus_cents=300` (stacking correto — **não tocado**).

## Resumo para o Danilo (PT-BR)

Os 6 bloqueadores foram corrigidos e os 3 de dinheiro foram **provados em produção** com chamadas reais recusadas pelo servidor (transações abortadas, zero lixo criado):

1. **B1 distância:** pedido de 16 km agora é recusado pelo servidor (`delivery_distance_exceeded: 16 km > 15 km`); 14 km passa. App mostra "Entrega não disponível. Máximo 15 km."
2. **B3a tokens no pagamento:** servidor recusa desconto acima de 50% (`token_cap_exceeded: 800 > 765 (50% de €15,30)`); o app agora lê os 50% do banco (não é mais hardcode) e mostra "Máximo 50% em Bora Tokens (€X,XX)".
3. **B3b saque semanal (o bug do 50%+50%+50%):** nova RPC atômica com janela seg→dom. Provado com o SEU entregador real: ele já converteu 1.142 tokens essa semana com saldo 19 → **qualquer saque é recusado** ("Limite semanal atingido. Podes sacar mais na próxima semana."). O teste da spec (1000 → 500 OK → +1 recusado) bate com a fórmula: cap=500, depois saldo=500→cap=250 e 501>250 ✋.
4. **B4 preço base:** o entregador agora vê o preço de prateleira (o que ELE paga na caixa) na lista de compras e no "Total na caixa"; o que o CLIENTE paga (dinheiro/diff) continua com markup, calculado à parte. Hardcode 0.15 eliminado.
5. **B6 alergênios:** coluna `allergens` + índice GIN no banco; parceiro marca os 14 alergênios no formulário; cliente vê chips ou o aviso "Consulte o estabelecimento…". Não bloqueia pedidos.
6. **B5 paginação:** o app NÃO carrega mais os 45 mil produtos na memória. Na abertura só carrega parceiros + restaurantes (menus completos); mercados carregam 30 por página com scroll infinito; mercado abre com 120 para as seções. Busca continua 100% no banco.

## Checklist de validação

| Critério | Estado | Evidência |
|---|---|---|
| flutter analyze 0 errors | ✅ | ver secção Analyze abaixo |
| B1: 16 km recusado / 14 km passa | ✅ prod | `delivery_distance_exceeded: 16 km > 15 km`; 14 km → caiu em `MISSING_DROPOFF_COORDS` (passou o gate, zero escritas) |
| B3a: €10→máx €5; acima recusado cliente E servidor | ✅ prod (servidor) + UI cap | `token_cap_exceeded: tokens_cents=800 > max_cents=765 (pct=50, total=15.30)`; UI: `min(saldo, total×pct/100/0.005)` com pct da DB |
| B3b: saldo 1000 → 500 OK → +1 recusado | ✅ fórmula + prod | fórmula `já_sacado+novo > saldo×50%`: 0+500≤500 OK; depois 501>250 recusa. Prod (driver real): `already=1142 new=1 cap=9 balance=19` recusado |
| B4: estafeta vê €1,00 / cliente vê €1,15 | ✅ código | item row = `basePrice ?? price`; cliente: `clientAdjustedTotal` com `BRBusiness.NON_PARTNER_MARKUP_RATIO` |
| B5: mercado abre sem travar + scroll infinito | ✅ código (testar no A36) | arranque `inFilter` parceiros+restaurantes; páginas 30; `NotificationListener` no grid; spinner 1º load |
| B6: campo na DB + ecrã mostra ou disclaimer | ✅ prod + código | `allergens ARRAY` + `idx_products_allergens` confirmados por SELECT; chips/disclaimer no detalhe |
| Ficheiro knowledge gravado | ✅ | `.claude/.ai/knowledge/BLOQUEADORES_RESOLVIDOS_2026-06-12.md` |
| Obsidian | ⚠️ manual | Danilo: `.claude\scripts\sync-obsidian-knowledge.ps1 -VaultPath "C:\Users\danil\Desktop\Bora"` |

## Commits (por bloco)

| Bloco | Commit | Ficheiros principais |
|---|---|---|
| B1 cap distância | `afdbad1` | migration 20260612213000 + order_store + payment_method_screen |
| B3a cap tokens pagamento | `b342513` | migration 20260612214500 + order_store + payment_method_screen |
| B3b cap semanal saque | `54997ed` | migration 20260612220000 + driver_earnings_screen |
| B4 preços base estafeta | `55d3a5b` | driver_map_screen |
| B6 alergénios | `a0394ee` | migration 20260612221500 + allergens.dart + modelo + stores + 2 ecrãs |
| B5 paginação catálogo | (este push) | restaurant_store + store_products_screen + market_store_screen |
| Docs | (este push) | este relatório + knowledge |

## Detalhe técnico por bloco

### B1 — `create_order` cap de distância
Validação logo após `INVALID_DISTANCE`, antes de qualquer escrita: lê `delivery_max_distance_km` (fallback 15), `RAISE ... USING ERRCODE='23514'`. Takeaway isento (sem entrega). Flutter: `OrderStore.lastCreateOrderError` (novo campo, reset por chamada) + `_createOrderErrorMessage()` no checkout traduz o código nos 3 call-sites (extrai o limite real da mensagem do servidor — se o setting mudar, a mensagem acompanha).

### B3a — cap de tokens server-side
`token_discount_cents` novo no `p_input` (enviado só quando >0). Validado após o pricing (cap = `FLOOR(customer_total × pct)` cents) e gravado em `tokens_applied_value_cents` (já considerado pelo `trg_enforce_refund_cap`). **Charge/buffer não mudaram** — ver "gap conhecido" no knowledge (cartão+tokens >5% do buffer é limitação pré-existente da validação ±5% do create-payment-intent; mexer é zona Stripe → decisão à parte).

### B3b — `driver_convert_tokens(p_amount)`
Guards: `AUTH_REQUIRED`, `NOT_A_DRIVER`, `INVALID_AMOUNT`. Semana = `date_trunc('week', now())` (segunda 00:00). Já sacado = `SUM(driver_transactions.amount)` da semana (type/status) convertido a tokens pelo `token_value_cents_x100`. Depois do cap: `consume_tokens` + INSERT `driver_transactions` + UPDATE/INSERT `driver_balances` — tudo na mesma transação. `REVOKE PUBLIC` + `GRANT authenticated`. O `compute_driver_settlement` já soma estas transações ✅.

### B4 — separação dinheiro estafeta vs cliente
`boughtTotal`/`addedFinalTotal`/`adjustedTotal` ("Total na caixa") = base. `clientBoughtTotal`/`clientAddedTotal`/`clientAdjustedTotal` = com markup, usados SÓ em "Cliente paga na entrega" (cash) e no diff vs `paymentBufferTotal`. "Bora reembolsa-te" agora mostra o valor base (o que o estafeta gastou de facto — antes sobre-prometia +15%).

### B5 — arquitetura da paginação
- `loadProductsFromSupabase` (arranque): `inFilter('restaurant_id', parceiros ∪ restaurantes)`; se a lista de restaurantes ainda não carregou, adia e o listener de auth encadeia o reload.
- Novo: `storePageSize=30`, `storeHasMoreProducts()`, `storeProductsLoading()`, `storeLoadedCount()`, `ensureStoreProductsLoaded(id, {minCount})`, `loadMoreStoreProducts(id)` (reentrante, dedupe por id, `.eq is_available`, mesma ordenação sort_order/id).
- Parse unificado `_productFromRow` + `_productProjection` (arranque e páginas).
- `MarketStoreScreen.initState` → ensure 120; `StoreProductsScreen.initState` → ensure 30 + `NotificationListener` (threshold 400px) no corpo browse.
- **Limitação v1 (anotada):** chips de categoria/tab Categorias derivam do que está carregado — completam-se à medida que o utilizador pagina; pesquisa (DB) cobre tudo. Follow-up: RPC `store_product_categories` + paginação por categoria.

### B6 — alergénios
Slugs canónicos no `lib/config/allergens.dart` (mapa slug→label PT-PT). Form parceiro: `FilterChip` por alergénio antes da secção de foto. Detalhe cliente: secção "Alergénios" com chips âmbar ou disclaimer em itálico. Payloads insert/update incluem `allergens`; projeção do load inclui a coluna.

## Analyze

`flutter analyze --no-pub` com TODOS os blocos aplicados: **ERRORS: 0** ✅ (restam apenas warnings/infos pré-existentes da baseline de 150 issues — ex.: `Radio.groupValue` deprecated em ecrãs admin; nada introduzido por esta sessão).

## Para testar no A36 (build seguinte)

1. Checkout com morada >15 km → SnackBar "Entrega não disponível. Máximo 15 km."
2. Checkout com tokens: toggle mostra "Máximo 50% em Bora Tokens (€X,XX)".
3. Estafeta → Ganhos → Converter: segunda tentativa acima do cap semanal → mensagem do limite.
4. Pedido mercado: lista de compras do estafeta com preços de prateleira; "Total na caixa".
5. Continente: abre rápido, 30 a 30 no scroll; pesquisa "água" funciona; secções do hero com conteúdo.
6. Parceiro: novo produto com alergénios; cliente vê chips no detalhe; produto sem alergénios mostra o disclaimer.
