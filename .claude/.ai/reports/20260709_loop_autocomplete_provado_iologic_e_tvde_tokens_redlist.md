# Loop autónomo — autocomplete provado (IO logic) + TVDE tokens (Lista Vermelha)

Data: 2026-07-09 · Branch: autonomous-night-2026-04-29 · Executor headless

## Bug 1 — Autocomplete da Guarda (Continente/Lavie) — RESOLVIDO no código, provado
- **Causa real (fotos do device):** o viés `location+radius` do Google Places é FRACO.
  "Continente" devolve 5 Continentes de cidades maiores e o da Guarda nem entra no conjunto;
  "Lavie" (comércio local mal indexado) devolve VAZIO sob `country:pt`.
- **Fix (já no working tree, `place_autocomplete_service_io.dart`):**
  1. 1.ª query com viés Guarda; 2. se NENHUM resultado da Guarda → retry explícito
     `"<query> Guarda"` e merge (locais à frente, dedup por place_id);
  3. se ainda vazio → retry SEM viés (cobertura nacional); 4. rerank determinístico Guarda-first.
- **Prova (não-web, cobre a falha que o teste web mascarava):**
  `flutter test test/place_autocomplete_io_logic_test.dart` → **+3 All tests passed**.
  Os 3 testes reproduzem EXATAMENTE os 2 bugs das fotos (Continente-outra-cidade, Lavie-vazio)
  com `http.Client` fake exercitando o código IO real.
- **Porque as fotos ainda mostram o bug:** o fix está **uncommitted** — nunca entrou num build
  instalado no telemóvel do Danilo (o device corre uma APK antiga).
- **Prova visual em device real:** IMPOSSÍVEL neste ambiente headless — `adb` não existe aqui
  (`adb: command not found`), logo `juiz_capture.py` não deteta o device. O que falta é
  operacional: commit → CI build_android → instalar a nova APK → re-testar "Continente"/"Lavie".

## Bug 2 — TVDE gastar Bora Tokens — LISTA VERMELHA (não aplicado)
- Estado: existe só a **migration draft** `supabase/migrations/20260709010000_tvde_tokens_applied_columns.sql`
  (adiciona `tvde_rides.tokens_applied_count` + `tokens_applied_value_cents`) — **NÃO aplicada**.
- O threading do desconto (tvde_request_ride/tvde_finish_ride + Edge Fn de cobrança) e o toggle na
  UI de pagamento TVDE **não estão implementados** e **não foram tocados** por mim.
- Motivo do bloqueio: mexe em `bora_tokens` (gasto) + reduz o valor cobrado online ao cliente
  (`tvde_ride_charge_cents`) → toca Stripe/pagamentos. É 🔴 dinheiro real = PROPOSE-ONLY.

## Bugs relacionados encontrados (fora do escopo)
- `tvde_store.dart` / `tvde_request_ride_screen.dart` têm alterações uncommitted de OUTRA feature
  (nota do cliente para o motorista) — não conflita, mas está no mesmo working tree por rever.
- Muitos ficheiros de ecrã (cart/menu/store/product) aparecem modificados (re-skin design system)
  — uncommitted; convém um commit atómico separado do fix de autocomplete.

## ctx doctor / ctx stats — ver output real na conversa (doctor PASS; stats 43.4% redução)
