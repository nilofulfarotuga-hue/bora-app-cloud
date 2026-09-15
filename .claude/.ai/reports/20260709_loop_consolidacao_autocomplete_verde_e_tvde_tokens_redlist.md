# Loop autónomo — consolidação: Autocomplete (verde) + TVDE tokens (🔴 bloqueado)

**Data:** 2026-07-09 · **Branch:** autonomous-night-2026-04-29 · **Modo:** Protecção Total (executor headless)

## Bug 1 — Autocomplete de guarda quebrado (Continente/Lavie) → CORRIGIDO + PROVADO POR TESTE LÓGICO

A correção das iterações anteriores está **completa e correta** em AMBAS as implementações
(IO=Android real, Web=Chrome), com paridade total:

- **Viés** (`maps_config.dart`): `location`+`radius=25 km` na Guarda, **sem** `strictbounds`
  (o strictbounds matava comércios locais como o Lavie no device real).
- **Garantia determinística** (`place_autocomplete_service_io.dart` / `_web.dart`):
  1. 1.ª query com viés suave.
  2. Se **nenhum** resultado da Guarda → dispara `"<query> Guarda"` e mete à frente (dedup por place_id).
  3. Se **ainda** vazio → retry **sem viés** (cobertura nacional).
  4. `_rankGuardaFirst` — rerank estável: Guarda ao topo, sem excluir os demais.

Isto resolve os DOIS casos que o Danilo viu no telemóvel:
- **"Continente"** (outra cidade em 1.º) → Continente da Guarda passa a 1.º.
- **"Lavie"** (vazio) → `"Lavie Guarda"` devolve o LaVie Shopping.

### Prova (o buraco anterior era "só teste web")
- `test/place_autocomplete_io_logic_test.dart` exercita o **serviço IO real** com `http.Client`
  falso (`createPlaceAutocompleteServiceForTest`) e reproduz os 2 cenários reais + fallback nacional.
- **10/10 testes verdes** (logic + widget + tvde payment selector). `flutter analyze`: **0 erros**.

### ⚠️ Limitação desta sessão (headless)
`adb` **não está no PATH** deste shell (`hermes`) — a captura visual no device Android real
(`juiz_capture.py` via `adb devices`) **não foi possível** nesta corrida. A lógica está provada por
teste determinístico (que é mais forte que o teste web anterior), mas a **prova visual no device
fica pendente** de uma sessão com `adb` disponível.

## Bug 2 — TVDE sem opção de gastar Bora Tokens → 🔴 LISTA VERMELHA (só fundação; resto BLOQUEADO)

Isto mexe em **`bora_tokens`** (gasto) e nos **valores cobrados** → Lista Vermelha. Estado:

- **FEITO (seguro, aditivo, reversível):** `supabase/migrations/20260709010000_tvde_tokens_applied_columns.sql`
  adiciona `tvde_rides.tokens_applied_count` + `tokens_applied_value_cents` (NOT NULL DEFAULT 0).
  **Ainda NÃO aplicada à BD.** Não toca saldos nem RPCs. Rollback documentado no ficheiro.
- **BLOQUEADO (aguarda "vai" do Danilo):**
  1. Aplicar a migration à BD (Supabase).
  2. Threading do desconto nas RPCs `tvde_request_ride` / `tvde_finish_ride` (mesma regra **máx 50%**
     de `platform_settings.token_payment_max_pct`; **não** mexer no ganho de tokens que é 0 no TVDE).
  3. Débito real dos tokens da wallet no fecho da corrida (espelhar `orders`).
  4. Toggle "Usar Bora Tokens" na UI do ecrã de pagamento TVDE (igual ao delivery).
     Confirmado: `tvde_request_ride_screen.dart` **não** tem nenhuma referência a token (UI não aplicada).

## Bugs relacionados encontrados (fora do escopo)
- `place_autocomplete_service_web.dart` usa `dart:html`/`dart:js` (deprecated pós Flutter 3.x) —
  funciona mas devia migrar para `package:web`+`dart:js_interop`. Não urgente.
- `tvde_request_ride_screen.dart:233/235` `use_build_context_synchronously` e `:952` `activeColor`
  deprecated — info-level, pré-existentes.

## Ficheiros
- Verificados (Bug 1, sem alteração nesta corrida — já corretos): `lib/config/maps_config.dart`,
  `lib/services/place_autocomplete_service_io.dart`, `lib/services/place_autocomplete_service_web.dart`,
  `test/place_autocomplete_io_logic_test.dart`, `test/address_autocomplete_field_test.dart`.
- Fundação Bug 2 (prévia, não aplicada): `supabase/migrations/20260709010000_tvde_tokens_applied_columns.sql`.
- Criado: este relatório.

## ⚠️ CONFIRMAÇÃO NECESSÁRIA
Bug 2 (TVDE gastar Bora Tokens) mexe em dinheiro/`bora_tokens`. Fundação pronta e reversível; o
threading do desconto + débito + UI só avançam com o teu **"vai"**.
