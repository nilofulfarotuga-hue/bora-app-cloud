# Loop autónomo — Autocomplete VERDE (verificado) + TVDE Tokens (aguarda "vai")

**Data:** 2026-07-09 · **Branch:** autonomous-night-2026-04-29 · **Modo:** executor headless, PROTEÇÃO TOTAL

## Bug 1 — Autocomplete da Guarda (RESOLVIDO + VERIFICADO)

Estado do working tree já continha a correção completa e um teste de **lógica io real**
(`test/place_autocomplete_io_logic_test.dart`) que fecha o buraco apontado pelo Danilo
("aprovado só com teste web, não pegou o erro real"). O teste usa `MockClient` (sem rede,
sem device) e reproduz os dois cenários reais do telemóvel:

1. **"Continente"** → Google devolve Continentes de outras cidades (Lisboa/Porto) e o da
   Guarda nem aparece → o serviço dispara `"Continente Guarda"` e coloca-o em 1.º (rerank
   determinístico), **sem eliminar** os das outras cidades (viés suave, não filtro).
2. **"Lavie"** → Google devolve VAZIO (comércio local mal indexado) → o serviço dispara
   `"Lavie Guarda"` e devolve o LaVie Shopping.
3. Cobertura nacional: se nem `"<query> Guarda"` acha nada → fallback SEM viés.

Mecanismo (em `lib/services/place_autocomplete_service_io.dart` + `lib/config/maps_config.dart`):
viés suave `location`+`radius` (25 km centro Guarda), **sem** `strictbounds` (que matava
comércios locais), retry explícito `"<query> Guarda"` quando não há resultado local, fallback
sem viés, e `_rankGuardaFirst` estável.

**Verificação executada:** `flutter test` nos 2 ficheiros de autocomplete → **7/7 passam**
(3 lógica io + 4 widget). Verde confirmado.

> Nota honesta: prova visual em telemóvel Android real (adb/juiz_capture.py) **não foi
> possível** neste executor headless (sem canal, sem acesso confirmado a adb). A cobertura
> substituta é o teste de lógica io determinístico acima, que exercita exatamente os dois
> bugs reais — algo que o teste web/widget anterior NÃO fazia.

## Bug 2 — TVDE gastar Bora Tokens (🔴 LISTA VERMELHA — aguarda "vai")

Toca `bora_tokens` (gasto) + valor cobrado ao cliente + migration → **dinheiro real**.
Preparação feita, aplicação final RETIDA conforme regra.

- **Fundação (aditiva, reversível):** `supabase/migrations/20260709010000_tvde_tokens_applied_columns.sql`
  adiciona `tvde_rides.tokens_applied_count` + `tokens_applied_value_cents` (DEFAULT 0),
  espelhando `orders.*`. **NÃO altera RPC nem debita tokens.**
- **Verificado em prod (read-only):** as duas colunas **ainda NÃO existem** em `tvde_rides`
  → migration não aplicada, corretamente à espera de aprovação.
- **Falta (o que precisa de "vai"):** threading do desconto (máx 50%, `token_payment_max_pct`)
  em `tvde_request_ride`/cálculo de `tvde_ride_charge_cents`, débito real de tokens no finish,
  e o toggle "Usar Bora Tokens" na folha de pagamento TVDE (`_TvdePaymentSheet` /
  `tvde_payment_selector`), espelhando o delivery. **Não mexer no GANHO de tokens (já é zero
  para TVDE) — só o gasto.**

## Bugs relacionados encontrados (fora do escopo)
- Nenhum bug novo. `_TvdePaymentSheet` já tem a arquitetura certa para receber o toggle de
  tokens (valor final já é `amountCents` calculado no ecrã) — ponto de inserção limpo.

## ctx (output real)
- `/ctx doctor`: Server PASS · FTS5 PASS · Hook PASS · Runtimes 2/11 · **v1.0.89 desatualizado → v1.0.169**.
- `/ctx stats`: sessão 3 min · 1 tool call · 435 B em contexto · sem savings ainda.
