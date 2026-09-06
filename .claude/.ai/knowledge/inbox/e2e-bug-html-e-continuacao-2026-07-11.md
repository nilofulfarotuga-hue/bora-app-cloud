# Bug HTML em produção + continuação E2E — 2026-07-11

Executor autónomo (headless). Duas frentes. Nada de dinheiro tocado (fora da Lista Vermelha).

---

## PARTE 1 — Bug real: entidades HTML nos nomes de produtos (Continente) — RESOLVIDO

### O que o Danilo viu
Foto do Continente com nomes por descodificar:
`Trela para C&atilde;o` (→ Cão), `Ra&ccedil;&atilde;o` (→ Ração), `H&uacute;mida` (→ Húmida).

### Causa raiz (confirmada no código + dados)
O atributo SFCC `data-product-tile-impression` (Continente) e `data-gtm` (Auchan) vêm
**duplamente codificados** (`&amp;ccedil;`). O crawler (`supabase/functions/update-products/index.ts`)
fazia **um só passe** de `decodeEntities` sobre o atributo (`&amp;`→`&`), deixando a entidade
interna (`&ccedil;`) intacta dentro do JSON → gravava `Ra&ccedil;&atilde;o` na coluna `name`.
A migration antiga `20260430100000_fix_html_entities_products.sql` só corrigia `name`+`description`
e o crawler voltava a sujar a cada scrape.

### Âmbito em produção (antes do fix)
- `products.name`: **1242** linhas com entidade
- `products.category`: **1347**
- `products.brand_low`: **331**
- `products.description`: **0** (já limpo)
- Entidades presentes não cobertas pela v1: `&ordm;` (25), `&ndash;` (8), `&acute;` (1), `&ordf;` (1).

### Correção — FONTE (crawler) + DADOS (UPDATE)
1. **Crawler** `supabase/functions/update-products/index.ts`:
   - `parseImpression` e `parseGtm` fazem agora **2.º passe** de `decodeEntities` sobre
     `name`/`brand`/`category` já parseados (nunca mais grava entidade).
   - `decodeEntities` alargado com `&ordf; &ordm; &acute; &hellip; &ndash; &mdash;`.
   - **Deployed em prod: `update-products` v20** (verify_jwt=false preservado).
2. **Dados** — migration nova `supabase/migrations/20260711120000_fix_html_entities_products_v2.sql`
   (loop por par entidade→char; cobre name+category+brand_low; ordem: nomeadas primeiro, `&amp;`
   por último; idempotente; NÃO toca `photo_url`). **Aplicada em prod** via SQL.

### Verificação pós-fix (prod)
- name/category/brand com entidade: **0 / 0 / 0**.
- Restam 870 nomes com `&` — todos **ampersands legítimos** ("Ben & Jerry's", "M&M's",
  "Repair & Protect", "Black & White"). Correto.
- Spot-check: "Ração para cães", "Reparação", "Salmão", "Húmida" agora corretos.

**Recomendação:** o painel admin de catálogo deve mostrar `name` já descodificado (agora sim).
Ficheiros dev one-off (`.claude/.ai/scripts/continente-*.js`) têm o mesmo padrão de 1 passe mas
NÃO são o importador recorrente (esse é a Edge Function) — deixados como estão (surgical).

---

## PARTE 2 — Continuação do E2E `delivery-mercado-cash.yaml`

### Diagnóstico da falha das 16:09
O fluxo progredia até "abriu categoria (chips no topo da lista de produtos)" e depois **abortava
num assert-duro** `extendedWaitUntil visible: "Buscar produtos.*"` — dependia do campo de pesquisa
da `StoreProductsScreen` aparecer, o que travava o fluxo ANTES de escolher qualquer produto.
(A corrida mais recente das 17:42 nem lá chegou: falhou no pré-passo `reset-role-screen`, rc=1 —
device/infra, não este fluxo.)

### Factos do código (verificados)
- `market_store_tab.dart:528-538`: a "barra" `"Procurar em X..."` do detalhe da loja é um
  **GestureDetector que NAVEGA** para `StoreProductsScreen` — **não** abre teclado nem pesquisa.
- `StoreProductsScreen` abre em **modo browse**: chips de categoria + grelha de cards com **PREÇO**
  (`store_products_screen.dart:1184`, `toStringAsFixed(2)` → `€X.XX`). Card `onTap` → `ProductDetailScreen`.

### Correção aplicada ao YAML (regra de ouro: nunca travar)
- **Removido** o assert-duro `"Buscar produtos"` (causa do abort das 16:09).
- Depois da categoria → **direto** a `scrollUntilVisible €[0-9]+[.][0-9][0-9]` (60s) + `tapOn` index 0
  — **SEM barra de busca** (o tap em "Procurar em" é só navegação).
- Swipe dos chips passou a `optional: true` (demonstrativo, nunca trava).
- `takeScreenshot: evidencia-grelha-loja` antes do scroll (evidência).
- Resto do funil intacto: Adicionar ao carrinho → Ver carrinho → Finalizar → Dinheiro →
  Confirmar → prova real em `orders`.

### Execução ao vivo (estado verificado 18:5x, 2026-07-11)
<!-- RESULTADO_RUN -->
O fluxo `delivery-mercado-cash.yaml` já **não** aborta no passo da categoria (o assert-duro foi
removido; vai direto ao `scrollUntilVisible €[0-9]+[.][0-9][0-9]`). **Novo bloqueio observado**,
mais cedo no funil: as corridas 18:39/18:41 falharam no **pré-passo** `comum/reset-role-screen.yaml`
(a app resumiu num estado inesperado — cara de flakiness de device/ANR, **não** deste fluxo). O
loop **auto-recuperou** (regra de ouro): nova corrida arrancou às 18:57 depois da falha. Ainda
**sem pedido real** em `orders` (2 dias, storeShopping/continente/test = 0) porque nenhuma corrida
chegou ao fim — o gargalo agora é o setup do device, não o passo categoria→produto (esse está
corrigido). Não há como forçar um device daqui (executor headless, sem `python`/emulador local);
o `loop-noturno.py` continua a tentar no host dos devices.

**Verificação de código/infra feita pelo executor (esta iteração):**
- `update-products` **v20 confirmada ACTIVE** com o 2.º passe de `decodeEntities` em
  name/brand/category (li o corpo deployed) — fonte blindada, LIVE.
- `products`: **0 entidades** em name/category/brand_low/description (47080 produtos) — reconfirmado.
  Spot-check Continente animais: "Snack para Cão", "Ração", "Húmida" corretos (ex. do Danilo → limpos).
- migration `fix_html_entities_products_v2` **registada** em `schema_migrations`
  (prod version `20260711190321`; ficheiro repo `20260711120000_..._v2.sql`) — histórico consistente.

**Nova iteração (executor, ~19:5x 2026-07-11):**
- `e2e_log` confirma: as corridas **19:40 e 19:42** falharam no **pré-passo**
  `comum/reset-role-screen.yaml` (ANR/estado transitório no 1.º boot limpo), **não** no passo
  categoria→produto (esse continua corrigido). Ainda **0 pedidos** store/continente em `orders` (2d).
- **Correção aplicada** (regra de ouro = próxima estratégia): `reset-role-screen.yaml` ganhou um
  **2.º `clearState:true` de recuperação** — se depois de dispensar diálogos ainda não estamos no
  RoleScreen, faz mais UM boot limpo + re-dispensa diálogos antes do assert final. Um ANR de
  arranque é quase sempre pontual → a 2.ª tentativa deve destravar o funil e deixá-lo chegar,
  enfim, ao passo produto→carrinho→dinheiro→`orders`.
- Executor headless (sem device/emulador/python local) → não força uma corrida; o `loop-noturno.py`
  no host dos devices é que a exercita.

---

## Ficheiros tocados
- `supabase/functions/update-products/index.ts` (2.º passe decode + entidades extra) — **deployed v20**
- `supabase/migrations/20260711120000_fix_html_entities_products_v2.sql` (novo) — **aplicado em prod**
- `.claude/testes-e2e/flows/cliente/delivery-mercado-cash.yaml` (fix do abort + robustez)
- `.claude/testes-e2e/flows/comum/reset-role-screen.yaml` (2.º clearState de recuperação — destrava o pré-passo)
- prod DB `public.products`: name/category/brand_low descodificados (1242/1347/331 → 0 entidades)
