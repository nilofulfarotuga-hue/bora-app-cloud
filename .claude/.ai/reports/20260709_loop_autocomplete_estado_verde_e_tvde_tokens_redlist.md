# Loop 2026-07-09 — Autocomplete Guarda (estado) + TVDE Bora Tokens (Lista Vermelha)

## Bug 1 — Autocomplete da Guarda
**Estado: lógica RESOLVIDA e com teste determinístico VERDE. Falta só o build no device.**

- `lib/services/place_autocomplete_service_io.dart` e `..._web.dart` já estão simétricos:
  1ª chamada com viés suave (location+radius, `strictbounds=false`) → se **nenhum** resultado
  menciona "Guarda", dispara retry explícito `"<query> Guarda"` e faz merge/dedup pondo os locais
  à frente → se ainda vazio, fallback **sem viés** (cobertura nacional) → rerank Guarda-primeiro.
- `test/place_autocomplete_io_logic_test.dart` exercita o **serviço IO real** com `http.Client`
  falso (não um mock de widget) e reproduz os **dois cenários exatos do telemóvel**:
  - "Continente" → Google devolve outras cidades e o da Guarda nem aparece → serviço puxa o da
    Guarda para 1.º (sem eliminar os outros). ✅
  - "Lavie" → Google devolve VAZIO → serviço dispara "Lavie Guarda" e devolve o LaVie Shopping. ✅
  - Fallback nacional quando nem "<query> Guarda" acha nada. ✅
- `flutter test test/place_autocomplete_io_logic_test.dart` → **3/3 verde**.
- `flutter test test/address_autocomplete_field_test.dart` → **4/4 verde**.
- `flutter analyze` nos ficheiros tocados → **0 erros** (2 `info` pré-existentes de `dart:html/dart:js`).

**Porque o Danilo ainda viu o bug no telemóvel:** estas correções estão na working tree
(**não commitadas**) — o APK testado no telemóvel é anterior a elas. O passo em falta **não é
lógica**, é **build+instalação do APK** no device.

**Não consegui fazer a prova visual no device neste ambiente headless:** não há `adb` no PATH
nem `platform-tools` no Android SDK, logo `juiz_capture.py` não detecta o telemóvel. A captura
visual real precisa de um ambiente com adb + o telemóvel por USB (ação humana/devops).

## Bug 2 — TVDE sem opção de gastar Bora Tokens
**Estado: NÃO iniciado. É LISTA VERMELHA — não apliquei nada.**

- Confirmado: **zero** referências a "tokens" em `lib/screens/client/tvde/` e `lib/stores/tvde_store.dart`.
- `tvde_rides` não tem `tokens_applied_count` nem `tokens_applied_value_cents`.
- O `TvdePaymentSelector` existe (cash/card/mbway) mas sem toggle de tokens.

O trabalho pedido mexe em: (a) **migração** que adiciona colunas a um fluxo de dinheiro,
(b) **threading de desconto** em `tvde_request_ride`/`tvde_finish_ride` = **valor cobrado ao cliente**,
(c) gasto de **`bora_tokens`**. Isto é 🔴 Lista Vermelha → requer aprovação explícita antes de aplicar.

⚠️ ISTO MEXE EM PAGAMENTO/DINHEIRO (bora_tokens + valor cobrado no TVDE). Não apliquei.
Confirma que eu avanço com a migração + threading + UI.

## Ficheiros tocados neste loop
- Só leitura/validação de código já existente. **Nenhum ficheiro `lib/` alterado** (o autocomplete
  já estava corrigido por loops anteriores). Criado este relatório.
