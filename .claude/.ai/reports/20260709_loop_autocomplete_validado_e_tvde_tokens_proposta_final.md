# Loop autónomo — Autocomplete Guarda (validado) + TVDE Bora Tokens (proposta 🔴)

**Data:** 2026-07-09 · **Branch:** autonomous-night-2026-04-29 · **Modo:** PROTEÇÃO TOTAL

---

## PARTE 1 — Autocomplete da Guarda ✅ CORRIGIDO E VALIDADO (zona segura)

### Bug real (fotos do Danilo no telemóvel)
1. Digitar **"Continente"** → aparecia um Continente de **outra cidade** em 1.º, o da Guarda nem surgia.
2. Digitar **"Lavie"** (LaVie Shopping da Guarda) → **zero resultados**.

Causa: o viés `location+radius` do Google Places é **fraco** — para nomes comuns devolve as
cidades maiores e o local da Guarda nem entra no conjunto (logo o rerank não tinha o que reordenar);
para comércio local mal indexado (`Lavie` sozinho sob `country:pt`) devolve vazio.

### Correção (já em `lib/services/place_autocomplete_service_io.dart` + `lib/config/maps_config.dart`)
- Viés **suave** (location + radius 25 km, **sem** `strictbounds` — o strictbounds matava lojas pequenas).
- Se **nenhum** resultado da Guarda aparecer → retry explícito **`"<query> Guarda"`** e mete à frente (dedup por `place_id`).
- Se **ainda** vazio → fallback **sem viés** (cobertura nacional) para nunca deixar um nome válido sem resultado.
- Rerank determinístico `_rankGuardaFirst` (Guarda em 1.º, estável, sem excluir os demais).

### Prova
- Teste de lógica **novo** que exercita o serviço `io` real com `http.Client` falso (não mock de widget) —
  `test/place_autocomplete_io_logic_test.dart` — reproduz os **dois cenários exatos** do Danilo:
  Continente-outra-cidade→Guarda-em-1.º, e Lavie-vazio→"Lavie Guarda"→LaVie Shopping. **Passa.**
- `flutter test` dos 2 ficheiros de autocomplete: **7/7 verdes**.

### ⚠️ Limitação honesta desta execução
A tarefa pediu **prova visual em device Android real** (`adb devices` / `juiz_capture.py`).
**Neste run headless o `adb` NÃO está no PATH nem no Android SDK** — não foi possível capturar o
device. A validação foi feita ao **nível da lógica** (onde o bug real vivia — o teste de widget
web antigo usava mock e por isso não o apanhava). Para fechar 100% falta 1 captura no telemóvel
ligado por USB (correr `adb devices` numa sessão interativa + repetir "Continente"/"Lavie").

---

## PARTE 2 — TVDE gastar Bora Tokens 🔴 LISTA VERMELHA — PROPOSTA (aguarda "vai")

**Toca `bora_tokens` (gasto/desconto de dinheiro) → a Trava bloqueia aplicar autonomamente.**
Feito só o trabalho de **preparação**; a aplicação final espera aprovação do Danilo.

### Estado preparado (reversível, NÃO aplicado à DB)
- **Migration fundação** `supabase/migrations/20260709010000_tvde_tokens_applied_columns.sql` —
  só adiciona `tvde_rides.tokens_applied_count` + `tokens_applied_value_cents` (aditivo, `DEFAULT 0`,
  rollback incluído). **NÃO aplicada** (é o gasto de tokens = 🔴).

### Mecânica a espelhar do delivery (fonte: `payment_method_screen.dart` §210-225)
```
maxPct        = platform_settings.token_payment_max_pct  (fallback 50)   → teto 50%
TOKEN_VALUE   = BRTokens.TOKEN_VALUE_EUR = 0.005 €  (1 token = MEIO cêntimo)
maxDiscount€  = valorCobradoOnline * (maxPct/100)
maxTokens     = floor(maxDiscount€ / 0.005)
tokensToUse   = min(saldoTokens, maxTokens)
desconto€     = useTokens ? tokensToUse * 0.005 : 0
cobrançaFinal = valorOnline - desconto€
```
Para TVDE o "valorCobradoOnline" é **`tvde_ride_charge_cents`** (valor do plano — ver memória
`project_tvde_payment_flow_v10`), **não** a tarifa cheia.

### Remaining (só com "vai"):
1. RPC nova (migration) que, no fecho online, debita tokens do saldo, grava
   `tvde_rides.tokens_applied_count/value_cents` e reduz a cobrança — **teto 50%**, atómico,
   **sem tocar no GANHO** de tokens (que é 0 no TVDE).
2. UI: toggle "Usar Bora Tokens" no ecrã de pagamento do TVDE, idêntico ao delivery
   (`tvde_request_ride_screen.dart` **hoje não tem nenhuma referência a tokens**).
3. Teste do teto 50% + débito atómico.

### 🐞 BUG RELACIONADO ENCONTRADO (corrigido — doc, não dinheiro)
O comentário da migration fundação dizia **"1 token = 1 cêntimo de desconto"**, mas o código real é
`TOKEN_VALUE_EUR = 0.005` → **1 token = €0,005 = meio cêntimo**. Se a RPC do TVDE fosse implementada
a seguir o comentário, dava **o DOBRO** do desconto (bug financeiro). Comentário corrigido nesta migration.

---

## ⚠️ CONFIRMAÇÃO NECESSÁRIA
A Parte 2 (RPC de débito de tokens + UI do toggle no TVDE) **mexe em `bora_tokens` / dinheiro**.
Está tudo preparado e a proposta escrita. **Confirma que eu aplico** (migration RPC + UI + deploy).
