# Loop autónomo 2026-07-09 — Autocomplete Guarda (strictbounds) + TVDE Bora Tokens

## BUG #1 — Autocomplete da Guarda (RESOLVIDO, código) ✅

### Diagnóstico (empírico, API real)
Testei a Places Autocomplete API com a chave real e o viés atual (location+radius, **sem** strictbounds):

| Input | Viés suave (atual) | `strictbounds=true` |
|---|---|---|
| `Continente` | Guarda **+ Viseu + Covilhã** misturados | **só Guarda** (2 Continentes + charging) |
| `Lavie` | "LA VIE Guarda" em 1.º (a API devolve!) | "LA VIE Guarda" |

**Conclusões:**
1. O "resultado de outra cidade" = viés demasiado **suave**: a API mistura lojas homónimas nacionais (Viseu ~65 km, Covilhã ~35 km) porque nada as exclui.
2. O "Lavie devolve nada" **não** é da API (ela devolve LA VIE Guarda). É do **build antigo no telemóvel** que ainda tinha `types=geocode` (só ruas, exclui POIs). A working tree já removeu isso; faltava só rebuild — e o strictbounds torna o "Continente" limpo.

### Fix aplicado (zona segura — mapas/UI, reversível)
Como o Bora **só serve o município da Guarda**, mudei o viés de SUAVE → **FORTE** (`strictbounds=true`), restringindo ao raio de 20 km (exclui Viseu/Covilhã, mantém Lavie da Guarda):
- `lib/config/maps_config.dart` — nova const `kGuardaStrictBounds = true` + comentário atualizado.
- `lib/services/place_autocomplete_service_io.dart` — `if (kGuardaStrictBounds) 'strictbounds': 'true'` (Android/iOS — o device real usa esta).
- `lib/services/place_autocomplete_service_web.dart` — `request['strictbounds'] = true` (a plataforma que foi aprovada antes; agora consistente com o mobile).

`flutter analyze` nos 5 ficheiros: **0 erros** (só 2 `info` pré-existentes de `dart:html`/`dart:js` no ficheiro web, não introduzidos aqui).

### Prova visual no device — BLOQUEADA neste ambiente
`adb` NÃO está no PATH deste shell headless → `juiz_capture.py` não consegue detetar o device. A prova visual no telemóvel Android tem de ser feita numa sessão com adb disponível:
```
flutter run --dart-define-from-file=.dart_defines -d <device>
# digitar "Continente" → só Guarda; digitar "Lavie" → LA VIE Guarda
```

---

## BUG #2 — TVDE sem opção de gastar Bora Tokens (PREPARADO, ⚠️ NÃO APLICADO) 🔴🔴

**Toca `bora_tokens` (gasto) E o valor cobrado ao cliente → Lista Vermelha dupla.** Fiz toda a
preparação; NÃO apliquei migration, NÃO fiz deploy de edge functions, NÃO commitei.

### Fundação escrita (reversível, aditiva) — ficheiro criado, NÃO aplicado
`supabase/migrations/20260709010000_tvde_tokens_applied_columns.sql`
- `tvde_rides.tokens_applied_count` INT DEFAULT 0
- `tvde_rides.tokens_applied_value_cents` INT DEFAULT 0
(espelham `orders.*`; NÃO tocam ganho de tokens, só preparam o gasto)

### Threading a aplicar (mesma regra do delivery — máx 50%)
Modelo de referência: delivery em `create_order` (`20260612214500_b3a_token_payment_cap.sql`):
o cliente envia `token_discount_cents`; o servidor valida o teto `FLOOR(total × token_payment_max_pct)`
(default 50) e regista em `tokens_applied_value_cents`.

1. **RPC `tvde_request_ride`** (última def: `20260703190000_tvde_plan_extra_ride_pricing.sql`):
   - novo param `p_token_discount_cents INTEGER DEFAULT 0`;
   - validar `INVALID_TOKEN_AMOUNT` (<0) e `token_cap_exceeded` contra
     `FLOOR(<valor cobrado online> × token_payment_max_pct)` — **base do teto = o valor que
     realmente vai à Stripe** (o do plano, não a tarifa cheia); ver nota abaixo;
   - gravar `tokens_applied_count` = `tokens_applied_value_cents` = `p_token_discount_cents`.

2. **RPC `tvde_ride_charge_cents(ride_id)`** (existe na BD; chamada pela edge fn, não está numa
   migration — extrair a def atual via MCP `get_edge_function`/`execute_sql` antes de editar):
   - subtrair `tokens_applied_value_cents` ao valor devolvido, com `GREATEST(0, ...)`.
   - Nota de ordem: o teto (passo 1) depende deste valor. Resolver calculando o charge base
     **dentro** de `tvde_request_ride` antes de validar o teto, ou validar em duas fases.

3. **Débito real de tokens** — usar o mecanismo existente `consume_tokens`
   (`20260404000002_consume_tokens.sql`), o MESMO que o delivery usa, para debitar `bora_tokens`
   pelo `tokens_applied_count`. NÃO reinventar; NÃO mexer no ganho (zero para TVDE).

4. **Edge fn `tvde-payment`** (`supabase/functions/tvde-payment/index.ts`, ação `charge`):
   passar `p_token_discount_cents: Number(body.token_discount_cents ?? 0)` na chamada
   `userClient.rpc('tvde_request_ride', {...})`. O `amountCents` já virá reduzido via passo 2.

5. **UI — ecrã de pagamento do TVDE** (`lib/screens/client/tvde/tvde_request_ride_screen.dart`):
   replicar o toggle "Usar Bora Tokens" do delivery (`lib/screens/payment_method_screen.dart`):
   ler saldo de tokens do cliente, calcular `min(saldoCents, FLOOR(valorCobrado × 0.50))`,
   mostrar o mesmo switch + linha de desconto, e enviar `token_discount_cents` no body do charge.
   (`lib/stores/tvde_store.dart` faz o threading até à edge fn.)

### Testes a fazer (no device real, com adb)
- Corrida com toggle ON: desconto ≤ 50%, saldo de tokens desce, Stripe cobra o líquido.
- Corrida com toggle OFF: comportamento atual inalterado.
- Corrida coberta €0: toggle escondido/no-op (não há cobrança online).

---

## ⚠️ CONFIRMAÇÃO NECESSÁRIA (Danilo)
O BUG #2 mexe em pagamento/tokens. Está tudo mapeado e a fundação (colunas) escrita em ficheiro.
**Falta a tua ordem "vai"** para: aplicar a migration, editar as RPCs de cobrança + `consume_tokens`,
fazer deploy da `tvde-payment` e testar no telemóvel. Nada disto foi aplicado.
