# Loop autónomo 2026-07-09 — Autocomplete (VERDE) + TVDE Tokens (🔴 CONFIRMAÇÃO)

Consolida e supera os ~13 relatórios `20260709_loop_autocomplete_*` (mesma tarefa, não convergia
porque o bug #2 é 🔴 Lista Vermelha e espera "vai" do Danilo).

## Bug #1 — Autocomplete biasing Guarda — ✅ VERDE (código fechado)
Fix já presente em `place_autocomplete_service_io.dart` (Android) e `_web.dart`:
1ª chamada com viés suave (location+radius, sem strictbounds) → se NENHUM resultado da Guarda,
retry explícito `"<query> Guarda"` + merge/dedup + `_rankGuardaFirst`; se ainda vazio, fallback
sem viés (cobertura nacional).

Prova (headless): `flutter test test/place_autocomplete_io_logic_test.dart` → **3/3 PASS**
- "Continente" (outra cidade em 1.º) → serviço puxa o da Guarda ao topo ✅
- "Lavie" (Google devolve VAZIO) → retry "Lavie Guarda" acha o shopping ✅
- fallback nacional quando nem "<q> Guarda" acha ✅
`flutter analyze` (ficheiros tocados) → **0 erros** (15 infos pré-existentes: Radio deprecated,
dart:html/js, const — nenhum novo).

⚠️ **Prova visual em device NÃO foi possível:** `adb` não está no ambiente (nem PATH nem
`%LOCALAPPDATA%/Android/Sdk/platform-tools`). `juiz_capture.py` não corre sem adb. A validação
final no telemóvel do Danilo fica do lado dele (o código está correto e provado por teste lógico
que reproduz os dois erros reais das fotos — já não é "só teste web").

## Bug #2 — TVDE gastar Bora Tokens — 🔴 PREPARADO, NÃO APLICADO
Toca `bora_tokens` (gasto) + cobrança TVDE = Lista Vermelha → PROPOSE-ONLY.
Feito (reversível, nada aplicado a prod):
- `supabase/migrations/20260709010000_tvde_tokens_applied_columns.sql` — colunas aditivas
  `tvde_rides.tokens_applied_count` + `tokens_applied_value_cents` (DEFAULT 0). **NÃO aplicada.**
Falta (é o gasto de dinheiro — só com "vai"):
- Threading do desconto (teto 50% via `token_payment_max_pct`) em `tvde_request_ride` /
  `tvde_ride_charge_cents` + débito de tokens (NÃO mexer no GANHO, que é 0 para TVDE).
- Toggle "Usar Bora Tokens" no folha de pagamento TVDE (espelhar delivery).

## Bugs relacionados encontrados (fora do escopo)
1. **Loop não converge:** ~13 relatórios duplicados da mesma tarefa 2026-07-09 — o executor
   re-fazia o bug #1 (já verde) a cada volta em vez de parar no bloqueio 🔴.
2. **`adb` ausente** no ambiente do executor → nenhuma prova visual de device é possível headless.
   Infra a resolver se se quer "não aceitar aprovação só com teste web" de forma automática.
3. **Scope creep no ecrã TVDE:** o loop anterior meteu um campo "Nota para o motorista"
   (refactor `CustomerNoteField`) em vez do toggle de tokens pedido. É útil e não-financeiro,
   mas NÃO é o que a tarefa #2 pedia.

---
⚠️ **ISTO MEXE EM PAGAMENTO/DINHEIRO (bug #2).** Fundação pronta. Confirma que eu aplico:
migration das colunas + threading do gasto de tokens + toggle na UI TVDE.
