---
id: e2e-scroll-carrossel-fix-2026-07-11
tipo: relatorio
origem: [executor autonomo, testes-e2e]
ultima_confirmacao: 2026-07-11
zona: verde
confianca: auto
---

# E2E — Scroll/carrossel + prova de pedido real (2026-07-11)

## Pergunta do Danilo
O Maestro toca no Continente mas **não rola** a lista vertical nem o carrossel
horizontal → nunca escolhe produto → **zero pedidos** na `orders`. Corrigir os flows
para rolar (DOWN vertical / LEFT carrossel), tocar num produto real, encher o carrinho,
finalizar em dinheiro e **criar 1 pedido REAL**. Garantir `e2e_log` criada e o runner a
escrever cada passo.

## Pedido criado na tabela `orders`? **NÃO (ainda)** — bloqueio de ambiente, não de código
Os **dois telemóveis estão `unauthorized` no adb** (`N75LTG5X5DSKDMV4`, `RZGYB1XQD2P`).
O executor é headless e **não consegue tocar** o prompt "Permitir depuração USB" no ecrã do
telemóvel → o Maestro não pode conduzir os devices agora. Assim que o Danilo autorizar o USB
(1 toque em cada telemóvel) e correr `run-tudo.cmd` / `runner.py --fluxo delivery-mercado-cash`,
o fluxo corrigido deve criar o pedido.

## Causa-raiz encontrada (o porquê de nunca escolher produto)
Verifiquei o código real da loja (`MarketStoreTab` / `MarketProductCard`):
- O preço do **produto** é `toStringAsFixed(2)` → tem **PONTO**: `€1.29`.
- A **taxa de entrega** (stats-row) e o rodapé são texto fixo com **VÍRGULA**: `€2,50`, e
  **não são tocáveis**.
- O YAML antigo fazia `tapOn: text "€.*" index:0` → batia na **taxa de entrega** (fica no topo),
  não num produto. O `Adicionar ao carrinho` nunca aparecia → o fluxo travava aí. **Este era o bug.**
- Além disso a grelha "Comprar por categoria" (até ~38 categorias, 4 col) é **muito alta**: um
  único `scroll` cego não chega aos carrosséis de produto.

## Correção aplicada — `flows/cliente/delivery-mercado-cash.yaml`
1. Espera de carga passa a exigir um **preço de PRODUTO** visível: regex `€[0-9]+[.][0-9][0-9]`
   (o ponto exclui a taxa `€2,50` da vírgula).
2. **`scrollUntilVisible` DOWN** com esse mesmo alvo — rola determinístico até um produto ficar
   à vista, passando a grelha alta (idempotente: para no alvo).
3. **`swipe LEFT`** — demonstra/varre o carrossel horizontal (nunca falha o fluxo).
4. `tapOn` no **preço do 1.º card** (index 0) → o preço está dentro do `GestureDetector` do card
   → abre `ProductDetailScreen`.
5. `Adicionar ao carrinho.*` (botão de TEXTO real do detalhe: "Adicionar ao carrinho · €X").
6. `back` → `Ver carrinho.*` → `Finalizar pedido` (scrollUntilVisible) → `Dinheiro` →
   `Confirmar pagamento`.
7. **Assert final corrigido**: em CASH o ecrã de pagamento faz `pop` e mostra o SnackBar
   `Pedido criado. Aguardando confirmação de pagamento.` — **não** há ecrã "Pedido ..." dedicado.
   Passei a esperar `Pedido criado.*|A preparar o seu pedido.*|Aguardando confirmação.*|Início`.
   A **prova real** continua a ser a linha em `orders` (o `poll_db` do runner já valida isso).

Cada passo escreve um milestone em `e2e_log` via `../comum/diario.yaml`.

## `e2e_log` (diário / observabilidade) — **CRIADA e a funcionar**
- Tabela `public.e2e_log` existe; tinha 15 linhas (última escrita real hoje 13:38 UTC pelo runner).
- Escrevi uma linha de estado desta correção (id **23**, `run_id=fix-2026-07-11-scroll-carrossel`)
  para o Claude.ai ver ao vivo.
- Ver ao vivo: `SELECT created_at, fluxo, passo, estado, detalhe FROM e2e_log ORDER BY created_at DESC LIMIT 40;`

## Âmbito: outros flows de "escolher da lista"
O único fluxo que cria pedido a partir de lista é o **delivery-mercado-cash** (registry.json).
**Não existem** ainda YAMLs de delivery-restaurante nem de favores — quando forem criados, herdam
o mesmo padrão (scrollUntilVisible DOWN por preço/nome → tocar card → adicionar → carrinho → cash).

## Ficheiros tocados
- `.claude/testes-e2e/flows/cliente/delivery-mercado-cash.yaml` — reescrito (scroll determinístico
  + alvo de produto por regex com ponto + assert final correto).
- `e2e_log` (Supabase) — 1 linha de estado (id 23). *(sem alteração de schema — a tabela já existia)*
- `.claude/.ai/knowledge/inbox/e2e-scroll-carrossel-fix-2026-07-11.md` — este relatório.

## Próximo passo (precisa de mão humana, 1 vez)
Autorizar USB debugging nos 2 telemóveis (toque no prompt) → correr o fluxo → confirmar
`orders` com pedido novo + linhas na `e2e_log`. Não bloqueia mais nada do lado do código.

---

## ATUALIZAÇÃO 2 (executor autónomo, mais tarde 2026-07-11) — reescrita search + 2.º bloqueio

Cruzei de novo o `e2e_log` com o código e encontrei que a correção anterior **ainda travava** e
que havia um **2.º bloqueio escondido** que mataria o pedido mesmo com o scroll perfeito.

### O que ainda travava (evidência no e2e_log)
O run mais completo (14:11 UTC) chegou a **"loja carregou (grelha de categorias visível)"** e
**parou** — nunca registou "rolou vertical até um produto". Ou seja: o `scrollUntilVisible` até ao
PREÇO de um card de carrossel **estourava o timeout e abortava o flow**. Os carrosséis de produto
são **lazy** e ficam muito abaixo da grelha alta (~38 categorias) → rolar até um preço lá em baixo é
frágil de mais para ser a prova-mestre.

### 2.º bloqueio (mataria o pedido MESMO com scroll ok)
O pagamento **CASH** tem pre-flight em `payment_method_screen.dart` que EXIGE endereço de entrega
(`deliveryLocation` + `dropoffStreet`). A conta `teste-cliente@bora.app` **não tinha nenhum**
`client_addresses` → snackbar vermelho "Endereço de entrega não definido" e **0 pedidos**, mesmo
chegando ao checkout. **Corrigido:** INSERT de endereço default ("Casa · Guarda", `is_default=true`,
lat/lng Guarda) para essa conta → a home (`_detectLocation`) preenche o dropoff sozinha. Verde/reversível.

### Nova reescrita do flow (substitui a caça ao preço do carrossel)
Escolha de produto agora **determinística via PESQUISA da loja** (StoreProductsScreen), que resolve
sempre — confirmei via RPC `search_products('agua', Continente, …)` que devolve secção + produtos
com preço. Scroll continua **real e demonstrado**: `scrollUntilVisible DOWN` até à grelha,
`scrollUntilVisible UP` para recuperar a barra de pesquisa, `swipe LEFT` no carrossel horizontal de
chips. Depois: toca no 1.º produto (pelo preço `€X.XX` do subtítulo — a secção não tem €) → detalhe →
"Adicionar ao carrinho" → `back` → "Ver carrinho" → "Finalizar pedido" → "Dinheiro" → "Confirmar
pagamento" → assert de sucesso (`Os meus pedidos` / SnackBar). Cada milestone escreve em `e2e_log`.

### Estado da DB no fecho
- `orders` (48h): **0** (baseline; é o que o próximo run deve virar).
- `e2e_log`: existe e é escrita LIVE — o `runner.py` injeta `SUPABASE_URL/KEY/E2E_RUN_ID` em TODOS os
  flows via `--env` (linha 327); `comum/diario.yaml` → `diario-log.js` grava cada passo.
- Continente: 13 863 produtos com preço → alvo de pesquisa garantido.

### Ficheiros tocados (atualização 2)
- `.claude/testes-e2e/flows/cliente/delivery-mercado-cash.yaml` — **reescrito**: search determinístico
  + scroll DOWN/UP/LEFT + assert de sucesso (`Os meus pedidos`).
- DB: 1 INSERT em `client_addresses` (default de `teste-cliente@bora.app`, id `30b14532-…dd04`).
- Continua sem commit/push (loop headless). Nada da Lista Vermelha tocado.
