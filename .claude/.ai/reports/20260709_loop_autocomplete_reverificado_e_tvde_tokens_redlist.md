# Loop autónomo 2026-07-09 — Autocomplete Guarda (re-verificado) + TVDE Bora Tokens (Lista Vermelha)

## Contexto
Danilo reportou 2 bugs com fotos de teste real. Executor headless (sem canal).

## Bug #1 — Autocomplete da Guarda (🟢 zona segura)
**Estado: código correto e PROVADO offline. Falta chegar ao device (deploy).**

- `lib/services/place_autocomplete_service_io.dart` (caminho do Android real) e
  `..._web.dart` têm agora lógica paralela: viés suave Guarda → se NENHUM
  resultado local, retry explícito `"<query> Guarda"` (dedup por place_id) →
  fallback nacional sem viés → rerank determinístico Guarda-primeiro.
- **Prova determinística** (o que o teste web-only não dava):
  `test/place_autocomplete_io_logic_test.dart` — **3/3 verde**, reproduz os
  cenários reais com `http.Client` falso no caminho `io`:
  1. "Continente" devolve outra cidade → serviço puxa o da Guarda ao topo ✅
  2. "Lavie" devolve VAZIO → retry "Lavie Guarda" acha o shopping ✅
  3. Cobertura nacional quando nem "<q> Guarda" acha nada ✅
- `flutter analyze` dos 6 ficheiros tocados: **0 erros**, só 2 `info` de
  deprecação `dart:html`/`dart:js` pré-existentes no bindings web (não novos).

**Porque o device ainda falhava:** a correção está na working tree (não commitada)
→ nunca entrou no APK que o Danilo testou. A "aprovação só web" das iterações
anteriores nunca fechou porque a prova em device real exige um **build de
produção** (🔴 Lista Vermelha / CI) — que este executor não pode fazer.

**Achado honesto:** `adb` NÃO existe neste ambiente headless (`where.exe adb`,
`$LOCALAPPDATA/Android/Sdk` → nada). A premissa "telemóvel ligado por USB +
juiz_capture.py detecta" **não se aplica a este processo executor**. A prova
visual em device real tem de ser feita pelo Danilo após um build. O que dá para
garantir por código está garantido (logic test verde no caminho io).

## Bug #2 — TVDE sem gastar Bora Tokens (🔴 LISTA VERMELHA)
**Estado: fundação pronta; aplicação BLOQUEADA à espera do "vai".**

- `supabase/migrations/20260709010000_tvde_tokens_applied_columns.sql` já existe
  (iteração anterior): adiciona `tvde_rides.tokens_applied_count` +
  `tokens_applied_value_cents` (aditivo, reversível). **NÃO aplicada à DB.**
- Falta (tudo 🔴, não feito): threading do desconto em `tvde_request_ride` /
  `tvde_finish_ride` / cálculo `tvde_ride_charge_cents` com teto 50%
  (`token_payment_max_pct`), débito real de tokens, e o toggle "Usar Bora Tokens"
  no ecrã de pagamento do TVDE (espelhar o delivery em `payment_method_screen.dart`).
- Regra respeitada: NÃO mexer no GANHO de tokens (zero para TVDE), só o GASTO.
- Gotcha registado na memória: editar sempre a `tvde_finish_ride` de 3 args
  (`20260704090300_tvde_finish_3arg_fix.sql`).

## /ctx doctor
- v1.0.89 (desatualizado → v1.0.169). Runtimes 2/11 (js, shell). Server PASS,
  FTS5/SQLite PASS, Hook PASS.

## /ctx stats
- Sessão 4 min · 1 tool call · 435 B em contexto · sem savings ainda.

## Ficheiros tocados nesta iteração
- Nenhum editado. Só verificação: corri o logic test (verde), `flutter analyze`
  (limpo), li migration+serviços, escrevi este relatório.
