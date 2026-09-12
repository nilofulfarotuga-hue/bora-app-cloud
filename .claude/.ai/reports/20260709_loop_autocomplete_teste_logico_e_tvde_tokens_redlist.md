# Loop 2026-07-09 — Autocomplete (prova ao nível da lógica) + TVDE tokens (🔴 bloqueado)

## Contexto
Re-run de 2 bugs confirmados por teste real (fotos) do Danilo. Loops anteriores já
tinham trabalho no working tree; este loop focou em **provar** o Bug #1 no nível
onde ele vive e em **confirmar** que o Bug #2 é Lista Vermelha.

## Bug #1 — Autocomplete da Guarda (Continente/Lavie) → RESOLVIDO e PROVADO
- A lógica de viés já estava no working tree (`place_autocomplete_service_io.dart`):
  retry explícito `"<query> Guarda"` quando nenhum resultado local aparece +
  fallback sem viés + rerank Guarda-primeiro. Lógica **sólida**.
- **Buraco real que o Danilo apontou:** a "aprovação" anterior veio de
  `test/address_autocomplete_field_test.dart`, que usa um **serviço MOCK** — nunca
  tocou na lógica de rede/rerank. Por isso "passava" sem apanhar o erro real.
- **Correção deste loop (zona segura, reversível):**
  - `lib/services/place_autocomplete_service_io.dart`: injeção opcional de
    `http.Client` no construtor (`_client`) + factory de teste
    `createPlaceAutocompleteServiceForTest(...)` (`@visibleForTesting`). Sem impacto
    no caminho de produção (factory pública inalterada).
  - **Novo teste** `test/place_autocomplete_io_logic_test.dart` — reproduz
    deterministicamente, com `MockClient`, os 2 cenários reais:
    1. "Continente" devolve outras cidades → serviço dispara "Continente Guarda" e
       coloca o da Guarda em 1.º (sem excluir os demais).
    2. "Lavie" devolve VAZIO → serviço dispara "Lavie Guarda" e acha o LaVie Shopping.
    3. Fallback nacional sem viés como última cobertura.
- **Validação:** `flutter analyze` limpo (0 erros; 2 `info` de deprecação pré-existentes
  no ficheiro web, baseline). `flutter test` → **7/7 verdes** (3 novos + 4 widget).

## Bug #2 — TVDE gastar Bora Tokens → 🔴 LISTA VERMELHA, NÃO aplicado
- Estado real: existe só a **migration-fundação** `20260709010000_tvde_tokens_applied_columns.sql`
  (2 colunas aditivas/reversíveis em `tvde_rides`; NÃO debita, NÃO altera cobrança).
- **Falta tudo o que toca dinheiro:** toggle "Usar Bora Tokens" na UI do pagamento
  TVDE, threading do desconto em `tvde_request_ride`/`tvde_ride_charge_cents`, e o
  débito real de tokens (teto 50%). Isto mexe em `bora_tokens` + valor cobrado ao
  cliente → **Lista Vermelha**. Preparação feita; alteração final NÃO aplicada.

## Bugs relacionados encontrados (fora do escopo)
1. **Prova em device real impossível neste ambiente headless:** `adb: command not found`.
   O loop pressupõe `juiz_capture.py` via `adb devices`, mas o adb não está no PATH
   deste executor → prova visual em telemóvel real **não é gerável** por aqui.
2. **Ficheiro web** usa `dart:html`/`dart:js` deprecados (2 `info`, pré-existente).
3. Ficheiros TVDE modificados no working tree (`tvde_request_ride_screen`, `tvde_store`)
   são da feature **customer_note** — não têm nada de tokens.

## Ficheiros tocados neste loop
- `lib/services/place_autocomplete_service_io.dart` (injeção de http.Client + factory de teste)
- `test/place_autocomplete_io_logic_test.dart` (novo — prova a lógica real)
