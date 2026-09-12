# Proposta — TVDE Autocomplete Guarda + Bora Tokens · PROPOSE-ONLY (redispatch)

- **Executor:** loop autónomo, MODO PROTECÇÃO TOTAL, `[PROPOSE-ONLY]` · **Modelo:** Opus 4.7
- **Data:** 2026-07-17 · **Branch:** `autonomous-night-2026-04-29`
- **Origem:** ordem original 8448 (09/07), redisparada no loop novo (Juiz por git/disco).
- **Nada foi aplicado à DB, nada foi commitado, nada foi pushed.** Espera "vai" do Danilo.

## Resumo executivo

Este pedido já tinha sido trabalhado 2× antes nesta branch (13/07 e mais cedo 17/07).
Este ciclo foi principalmente **verificação ao vivo** (DB real via MCP, `git log`,
`git diff`, `flutter analyze`) — e encontrou **1 bug novo real** (fórmula de tokens TVDE
10× errada) dentro da própria proposta pendente, que corrigi no ficheiro de migration
(ainda não aplicado à DB).

| Bug | Estado | Ação necessária |
|---|---|---|
| 1a. Autocomplete Guarda (Continente/Lavie) | ✅ **já corrigido e commitado** (`f90d9fa`, `fbd07a7`) | Build+install de APK novo para o Danilo confirmar no telemóvel (🔴 build produção) |
| 1b. Dropdown cortado na folha "Adicionar parada" | 🟢 aberto, diff pronto (não aplicado) | "vai" → aplicar diff em `tvde_ride_tracking_screen.dart` |
| 2. TVDE gastar Bora Tokens (fim-a-fim) | 🔴 aberto, client-side pronto (uncommitted), SQL pronta (não aplicada) | "vai" → aplicar migration SQL (DB) + commitar os 3 ficheiros já editados |

---

## BUG 1a — Autocomplete Guarda (Continente noutra cidade / Lavie vazio)

**Já resolvido e commitado** nesta branch: `f90d9fa` (viés geográfico + retry
"`<query> Guarda`" + fallback nacional) e `fbd07a7` (gate frágil removido, dispara
SEMPRE o retry ancorado). Confirmado por leitura de
`lib/services/place_autocomplete_service_io.dart` — o código vivo já tem `_isGuarda`,
`_rankGuardaFirst`, viés `kGuardaBiasLat/Lng` e o retry incondicional. Teste de
regressão em `test/place_autocomplete_io_logic_test.dart`.

Não há nada de código para propor aqui. O que falta é **prova em device real**: não
havia Android ligado por USB nesta sessão (`adb devices` vazio). Ver
`project_autocomplete_guarda_stale_apk` na memória — o sintoma reportado por Danilo
era de um APK anterior a estes commits. Isto é 🔴 (build de produção) — aguarda "vai"
para gerar e instalar um APK novo e confirmar visualmente.

---

## BUG 1b — Autocomplete cortado na folha "Adicionar parada" (durante a corrida)

Confirmado **ainda aberto**: `lib/screens/client/tvde/tvde_ride_tracking_screen.dart`
linha 1178 continua com `final maxSheet = MediaQuery.of(context).size.height * 0.7;`
e sem `useSafeArea: true` no `showModalBottomSheet` (linha ~137-145) — exatamente como
diagnosticado em 2026-07-13.

**Diff completo já preparado** (não reaplicado por mim, já estava documentado e
reconfirmado válido linha-a-linha contra o código atual) em
[`proposta-tvde-parada-adicional.md`](proposta-tvde-parada-adicional.md), secção
"BUG #1". Resumo do fix: `useSafeArea: true` no `showModalBottomSheet` +
`maxSheet = media.size.height - bottomInset - media.padding.top` (em vez do `0.7`
fixo), para a folha ocupar exatamente o espaço acima do teclado em qualquer ecrã.
Zona 🟢 (UI pura, sem dinheiro/GPS/realtime).

Esse mesmo ficheiro documenta também um BUG #3 (notificação de oferta de entrega
silenciosa em foreground no mapa TVDE) — não relacionado a este pedido, fora de
escopo, mas ainda válido e por corrigir.

---

## BUG 2 — TVDE sem opção de gastar Bora Tokens (fim-a-fim)

### O que já existe (confirmado por leitura, não é preciso reescrever)
- Toggle "Usar Bora Tokens" **já implementado** em `_TvdePaymentSheetState`
  (`lib/screens/client/tvde/tvde_request_ride_screen.dart:856-965`) — mesmo padrão
  visual/âmbar do delivery, lê saldo (`get_user_tokens`) e `token_payment_max_pct`
  (`get_setting`), calcula `tokensToUse` com `TOKEN_VALUE_EUR=0.005`, clamped a 50%.
- Colunas `tvde_rides.tokens_applied_count/value_cents` — aplicadas em prod desde
  2026-07-11 (`20260709010000_tvde_tokens_applied_columns.sql`).

### O que estava a faltar (causa raiz confirmada AO VIVO via MCP nesta sessão)
```
SELECT p.oid::regprocedure, pg_get_function_arguments(p.oid)
FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
WHERE n.nspname='public' AND p.proname='tvde_request_ride';
```
→ produção **ainda tem as 2 overloads de 8 args por fundir** (confirmado hoje,
17/07, não é informação stale):
1. `(..., p_payment_method text DEFAULT 'cash')` — sem lógica de tokens.
2. `(..., p_tokens_to_apply integer DEFAULT 0)` — tem a lógica de tokens, mas nunca é
   chamada (o app só envia `p_payment_method` nomeado → PostgREST resolve sempre para
   a overload 1). Morta em produção.

`TvdeStore.requestRide()`/`requestRidePaid()` e a Edge Function `tvde-payment` só
enviam `p_payment_method` → o toggle da UI era **decorativo**.

### Client-side — JÁ PRONTO, uncommitted (não toquei, só verifiquei — 5 linhas, 3 ficheiros)
```diff
--- a/lib/screens/client/tvde/tvde_request_ride_screen.dart
+++ b/lib/screens/client/tvde/tvde_request_ride_screen.dart
@@ paymentMethod: 'cash',
+          tokensUsed: tokensUsed,

--- a/lib/stores/tvde_store.dart
+++ b/lib/stores/tvde_store.dart
@@ requestRide({
+    int tokensUsed = 0,
@@ params: {
+        'p_tokens_to_apply': tokensUsed,

--- a/supabase/functions/tvde-payment/index.ts
+++ b/supabase/functions/tvde-payment/index.ts
@@ p_payment_method: method,
+          p_tokens_to_apply: Number(body.tokens_used ?? 0),
```
Confirmei que o caminho cartão/MB Way (`requestRidePaid` → Edge Fn `tvde-payment`) e o
caminho dinheiro (`requestRide` → RPC direta) estão **ambos** corretamente fiados até
à RPC. `flutter analyze`: 0 erros, nenhum issue novo nestes ficheiros (baseline
216-220, ver secção Prova).

### DB-side — SQL PROPOSTA pronta em `supabase/migrations/20260717000000_PROPOSTA_tvde_request_ride_merge_tokens_payment.sql`
Funde as duas overloads numa só de 9 args (payment_method + tokens_to_apply juntos),
mantendo a fórmula de tarifa mais recente (plano/km-extra) + o bloco de desconto de
tokens. Remove as 2 overloads de 8 args (nenhum caller as usa isoladas depois desta
fusão). **Não mexe** em ganho de tokens (continua zero) nem em `tvde_finish_ride`.

### ⚠️ BUG NOVO encontrado e CORRIGIDO nesta sessão (dentro da própria proposta)
A fórmula de desconto herdada da overload-2 morta usava `p_tokens_to_apply * 5`
(cents por token, hardcoded). Confirmei ao vivo (`SELECT value FROM platform_settings
WHERE key='token_value_cents_x100'` → **50**) que o valor real é `tokens × 50 / 100 =
0,5 cents/token` — o mesmo que `BRTokens.TOKEN_VALUE_EUR=0.005` e o toggle da UI já
mostram ao cliente. A fórmula herdada cobraria a plataforma em **10× o desconto
prometido na UI** (ex.: 50 tokens → UI mostra -€0,25, mas o backend aplicaria -€2,50).
Nunca chegou a produção (overload morta), mas entraria em vigor com a fusão se não
fosse corrigida agora. **Já corrigido no ficheiro da migration proposta** — lê
`token_value_cents_x100` de `platform_settings` (mesmo padrão da função para outras
settings), em vez de hardcode. Nada foi aplicado à DB.

### Bug relacionado, fora de escopo, documentado no cabeçalho da migration
Pagamento **dinheiro**: `TvdeDriverStore.finishRide()` envia sempre
`p_tokens_to_apply: 0` a `tvde_finish_ride` (fix deliberado do CAMPO-02 p/ evitar
PGRST203) — o desconto fica registado na criação da corrida mas não é reaplicado ao
`final_fare_cents` cobrado em dinheiro no fim. Card/MB Way não têm este problema
(cobram `est_fare_cents`, já com desconto, no momento da criação). Fix sugerido:
tarefa à parte, tocaria `tvde_finish_ride` (já estável/testado) — não mexido aqui.

### ⚠️ ISTO MEXE EM DINHEIRO (bora_tokens + RPC de cobrança TVDE)
Está tudo pronto — client-side já editado (uncommitted), SQL da migration já escrita
e agora com o bug de 10× corrigido. **Confirma que eu aplico**: (1) corro a migration
`20260717000000_PROPOSTA_...sql` via MCP `apply_migration`, (2) commito os 3 ficheiros
já editados + a migration, (3) push. Só depois de "vai".

---

## Prova / verificação desta sessão
- `adb devices` → vazio, **sem Android ligado** por USB nesta sessão (headless).
- `flutter analyze` → **0 erros**, 220 issues totais (baseline conhecido 216-217;
  nenhum issue novo nos 3 ficheiros TVDE tocados nem em `place_autocomplete_service_io.dart`).
- `pg_proc`/`platform_settings` consultados ao vivo via Supabase MCP (read-only,
  projeto `ojykpzwqrtusfeakzrna`) — evidência colada acima, não inventada.
- Sem device real disponível não há captura de ecrã em device; captura web não fiel
  o suficiente para provar o autocomplete nativo Android (usa implementação IO
  diferente da web) — **não reclamo prova visual que não tenho**.

## Admin Panel
Nenhuma feature nova de gestão — tokens TVDE já usam as mesmas tabelas/telas do
delivery. Sem paridade admin nova necessária.

## Ficheiros tocados nesta sessão
- `supabase/migrations/20260717000000_PROPOSTA_tvde_request_ride_merge_tokens_payment.sql`
  (editado — fix do bug de 10× nos tokens; ficheiro continua **untracked, não aplicado**)
- Este relatório (novo)

---

## RECONFIRMAÇÃO 2026-07-17 (3.ª passagem, redisparo automático da ordem 8448)

**Nada mudou desde a 2.ª passagem — zero trabalho novo necessário.** Verificação ao vivo
(não confiei só na memória):
- `git diff` dos 3 ficheiros client-side (`tvde_request_ride_screen.dart`, `tvde_store.dart`,
  `tvde-payment/index.ts`) → **exatamente as 5 linhas já descritas acima**, ainda uncommitted.
- Migration `20260717000000_PROPOSTA_...sql` → lida por inteiro, fórmula já correta
  (`token_value_cents_x100`, não `*5`), ainda **untracked, não aplicada**.
- `git log` confirma `f90d9fa` e `fbd07a7` (fix autocomplete Guarda) **reais e no histórico**
  — não é alegação de memória não verificada.
- `tvde_ride_tracking_screen.dart`: BUG 1b (dropdown cortado) **ainda aberto**, código
  idêntico ao diagnosticado em `proposta-tvde-parada-adicional.md` (`isScrollControlled`
  sem `useSafeArea` na chamada de `showModalBottomSheet` linha 137-145; `maxSheet = ...*0.7`
  fixo em `_AddStopSheetState.build`). Diff dessa proposta continua válido linha-a-linha.
- `adb devices` → vazio outra vez, sem Android por USB neste executor headless (mesma
  limitação de sempre — ver `project_autocomplete_guarda_stale_apk`).

**Por que não apliquei nada:** esta ordem chegou com `[PROPOSE-ONLY]` explícito no prompt
("prepara o fix completo mas NÃO apliques") — cobre as 3 alterações (incluindo o BUG 1b,
que é 🟢 zona segura mas ainda assim dentro do escopo PROPOSE-ONLY desta ordem específica).
Não editei ficheiros. Esperar "vai" do Danilo aplica-se às 3 coisas:
1. BUG 1a → gerar+instalar APK novo (🔴 build produção) e confirmar visualmente.
2. BUG 1b → aplicar o diff já pronto em `proposta-tvde-parada-adicional.md` (🟢, 2 edits).
3. BUG 2 (tokens TVDE) → aplicar migration SQL + commitar os 3 ficheiros já editados (🔴 dinheiro).

Redisparar esta mesma ordem outra vez sem uma resposta "vai" do Danilo não vai produzir
nada de novo — o estado é estável e já foi verificado 3×.
