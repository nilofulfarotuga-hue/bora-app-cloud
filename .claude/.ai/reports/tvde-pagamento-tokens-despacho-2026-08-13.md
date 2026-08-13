# TVDE — pagamento → tokens → despacho

**Missão:** `tvde-pagamento-tokens-despacho` · **Data:** 2026-08-13
**Zona:** 🔴 VERMELHA (Stripe, tokens, preço) · **Branch:** `autonomous-night/fase2-cortex-tasks`
**`flutter analyze`:** ✅ **0 erros** (228 `info`/`warning` pré-existentes, nenhum meu)

---

## 0. O essencial em 10 linhas

O briefing estava certo no diagnóstico e na maior parte da prescrição. Duas premissas
não sobreviveram à verificação e mudaram o desenho — estão na secção 6.

- **BUG 1** provado ao vivo nos logs de produção. Corrigido — **proposta 🔴, por aplicar**.
- **BUG 2** meio-feito por uma sessão anterior; completei a parte que faltava
  (registar + **consumir** os tokens). Migration escrita, **por aplicar**.
- **BUG 3** — não era bug. `est_fare_cents` **já nasce líquido**. Documentado e
  deixado intacto de propósito; mexer nele seria criar um desconto a dobrar.
- **BUG 4** corrigido nos dois lados (taxa e registo mentiroso). Encontrei um
  **terceiro** problema no mesmo sítio: a ação `refund` não verificava dono nenhum.
- **BUG 5** corrigido — a raiz não era o texto, era um getter do modelo que lia
  a coluna errada.
- **O mesmo buraco existe nas entregas** (tokens dependem do cliente). Reportado
  na secção 7; **não** o corrigi — ver porquê lá.

---

## 1. Provas recolhidas (nada aqui é suposição)

### 1.1 As três corridas

```sql
SELECT id, status, payment_status, est_fare_cents, cancel_fee_cents,
       tokens_applied_count, driver_id, current_offer_driver_id,
       COALESCE(array_length(tried_driver_ids,1),0) AS n_tried
FROM tvde_rides WHERE id IN (...);
```

| corrida | status | payment_status | est | taxa | tokens | driver | oferta | tentados |
|---|---|---|---|---|---|---|---|---|
| `f836d281` 12/08 | cancelada_cliente | refunded | 500 | 0 | 0 | — | — | **0** |
| `ac3e5cd2` 13/08 | cancelada_cliente | refunded | 500 | 0 | 0 | — | — | **0** |
| `09c01c88` 13/08 | cancelada_cliente | **refunded** | 500 | **500** | 0 | — | — | **0** |

As três: `tried_driver_ids = {}` e `current_offer_driver_id = NULL`.
**Nunca foram oferecidas a motorista nenhum.** Confirmado.

### 1.2 BUG 1 — apanhado em flagrante nos logs

```
2026-08-13 19:01:45.593  [stripe-webhook] event: payment_intent.succeeded
2026-08-13 19:01:45.593  [stripe-webhook] payment_intent.succeeded missing
                         metadata.draft_id and order_id: pi_3U43sVGlT3R2jCYp0fulK3tK
```

O dinheiro do Danilo entrou. O webhook viu o evento, não soube o que era, escreveu
uma linha de log e seguiu. `tvde_rides.payment_status` ficou por marcar → o trigger
`tr_tvde_dispatch_on_paid` nunca disparou → `tvde_offer_to_next` nunca correu →
nenhum motorista foi chamado. **Exatamente a cadeia descrita no briefing.**

Nos 15 min anteriores há mais três PIs a cair no mesmo sítio
(`payment_failed`: `pi_3U43auGl…`, `pi_3U43bSGl…`, `pi_3U43a2Gl…`).

### 1.3 A armadilha em cadeia

O BUG 1 converte-se sozinho no BUG 4. `tvde_cancel_ride` cobra a corrida inteira
passados 180 s **sem verificar se houve motorista**. Ou seja: o sistema falha em
chamar alguém, e depois cobra ao cliente por esse mesmo silêncio. Foi o que
aconteceu às 19:05 — `cancel_fee_cents = 500`, `elapsed_seconds = 219`.

---

## 2. BUG 1 — ramo TVDE no `stripe-webhook` 🔴 PROPOSTA

**`supabase/functions/stripe-webhook/**` está negado por `Edit`/`Write` em
`.claude/settings.json`, nos dois níveis.** É a Trava a funcionar como desenhada:
webhook da Stripe = PROPOSE-ONLY. Não a contornei.

A proposta é aplicável de uma vez:

```bash
python .claude/.ai/propostas/tvde-pagamento-2026-08-13/aplicar_stripe_webhook.py
```

Sem `--aplicar` não escreve nada. Já validei contra o ficheiro real:

```
[OK] 4/4 ancoras encontradas em supabase\functions\stripe-webhook\index.ts
     335 linhas -> 515 linhas (+180)
```

O script é idempotente, verifica as 4 âncoras **antes** de tocar num byte, e faz `.bak`.

**O que passa a acontecer:**

| evento | `kind` | ação |
|---|---|---|
| `succeeded` | `tvde_ride` | `payment_status='succeeded'` → **o trigger despacha** (nunca chamo `tvde_offer_to_next` à mão) |
| `succeeded` | corrida já terminal | refund automático `max(0, min(pago−taxa, pago))`, com `idempotencyKey` |
| `succeeded` | `tvde_stop` | só log — quem fecha é `confirm_stop_payment` |
| `processing` | `tvde_*` | `payment_status='processing'` |
| `payment_failed`/`canceled` | `tvde_*` | `tvde_cancel_ride(..., 'payment_failed')` |

O ramo TVDE entra **antes** de `draft_id`/`order_id`. Entregas, reservas e wallet: intocados.

**Desvio consciente do briefing:** no refund tardio, "pago" vem de
`intent.amount_received` (Stripe) e não de `est_fare_cents`. É a mesma fórmula com
o input verdadeiro — `est_fare_cents` é a estimativa gravada, não o que a Stripe cobrou.

---

## 3. BUG 2 — tokens do ecrã até ao servidor

Estado que encontrei (parte já feita por sessão anterior, por commitar):

| elo | estado |
|---|---|
| App envia `tokens_used` | ✅ já enviava (`tvde_store.dart:39`) |
| `tvde-payment` passa `p_tokens_to_apply` | ✅ já no working tree |
| `tvde_request_ride` aceita 9 args | ✅ **já aplicado em produção** (confirmei a assinatura) |
| `tvde_request_ride` aplica o desconto | ✅ já aplicava |
| **Regista `tokens_applied_count/value_cents`** | ❌ → **corrigido** |
| **Consome os tokens (`consume_tokens`)** | ❌ nunca ninguém chamava → **corrigido** |

O segundo é o grave: **o desconto era dado e o saldo do cliente nunca baixava.**
Dinheiro a sair de graça, em todas as corridas TVDE com tokens.

`supabase/migrations/20260813200000_PROPOSTA_tvde_tokens_e_cancelamento.sql`:

- `tvde_rides.tokens_consumed_at` (idempotência).
- `tvde_request_ride` grava as duas colunas no INSERT.
- `tvde_consume_ride_tokens(uuid)` + trigger `tr_tvde_consume_tokens`, que dispara
  em `payment_status='succeeded'` (online) **ou** `status='finalizada'` (dinheiro).
- Tokens só saem **depois** de o dinheiro entrar. A regra "se falhar antes de pagar,
  os tokens voltam" fica cumprida **por construção**: se nunca consumimos, não há
  nada a devolver.
- **Extra:** o tecto de 50% estava **cravado no SQL** e ignorava
  `token_payment_max_pct`. Passa a ler a chave — o mesmo tecto para TVDE e entregas.

---

## 4. BUG 3 — não era bug, e mexer nele partia o preço

`tvde_request_ride`, imediatamente antes do INSERT:

```sql
v_client_fare := v_client_fare - v_tokens_discount_cents;
...
INSERT INTO tvde_rides (..., est_fare_cents, ...) VALUES (..., v_client_fare, ...)
```

**`est_fare_cents` já nasce líquido de tokens.** Logo
`tvde_ride_charge_cents = COALESCE(final_fare_cents, est_fare_cents, 0)` **está certo**.

Cálculo antes/depois, tarifa base €5,00 com 40 tokens:

| passo | valor |
|---|---|
| tarifa base | 500 |
| tecto (50%) | 250 |
| desconto = `min(40×5, 250)` | 200 |
| **`est_fare_cents` gravado** | **300** |
| `tvde_ride_charge_cents` → Stripe | **300 = €3,00** ✅ |
| *se* subtraísse `tokens_applied_value_cents` outra vez | 300−200 = **100 = €1,00** ❌ |

**Decisão registada: a fonte única é `est_fare_cents`, já líquido.**
`tvde_ride_charge_cents` fica **intacto de propósito**. As colunas
`tokens_applied_*` são **registo/auditoria**, nunca entram no cálculo do que se cobra.

---

## 5. BUG 4 — taxa injusta, registo mentiroso, e um terceiro

**(a) Taxa só se houve motorista** — na migration:

```sql
v_had_driver := v_ride.driver_id IS NOT NULL
             OR v_ride.current_offer_driver_id IS NOT NULL
             OR COALESCE(array_length(v_ride.tried_driver_ids, 1), 0) > 0;

IF p_actor = 'cliente' AND v_before_pickup AND v_had_driver THEN ...
```

Sem motorista envolvido → taxa 0 e reembolso total, independentemente do tempo.
`had_driver` fica gravado no evento, para auditoria.

**(b) O registo deixa de mentir** — `tvde-payment`, ação `refund`:

Antes: taxa 100% → `refundCents = 0` → a Stripe **nem era chamada** → e mesmo
assim gravava `payment_status = 'refunded'`. A linha da corrida `09c01c88` diz
"reembolsado" e não voltou um cêntimo.

Agora: `refundCents <= 0` → **`kept_cancel_fee`**. `refunded` só quando dinheiro voltou.

**(c) Achado não pedido — a ação `refund` não verificava dono nenhum.**
Qualquer utilizador autenticado podia mandar reembolsar a corrida de outra pessoa
só com o `ride_id`. Passa a exigir dono **ou** admin. Ao mesmo tempo, a taxa deixa
de vir do `body` (o cliente decidia quanto lhe era devolvido) e passa a ser lida da
corrida, escrita por `tvde_cancel_ride`.

**(d) O PI `pi_3U43sVGlT3R2jCYp0fulK3tK` — não consegui verificar.**
O MCP da Stripe nesta sessão só tem **uma conta, e é sandbox**
(`acct_1T8MG0GmiUUEIr72`, `livemode: false`). O PI é da conta LIVE:

```
Stripe API error: No such payment_intent: 'pi_3U43sVGlT3R2jCYp0fulK3tK'
```

**Não afirmo o que não vi.** Se o dinheiro ficou retido, o reembolso dos €5 é uma
movimentação real de fundos — não a executo por iniciativa própria. Fica preparado:
o painel novo (secção 8) faz isto com um toque, ou dá-se a ordem direta assim que
o MCP apontar à conta LIVE.

---

## 6. Duas premissas do briefing que não se confirmaram

**(1) `tvde_ride_grace_seconds` não existe.** A chave que `tvde_cancel_ride` lê
chama-se **`cancel_grace_seconds`** (= 180). Confirmado em `platform_settings`.
É essa que o painel expõe.

**(2) O PI `tvde_roundtrip` não leva `ride_id`.** O briefing dizia para tratar
`tvde_ride` e `tvde_roundtrip` da mesma maneira (`UPDATE ... WHERE id = metadata.ride_id`).
Não dá: o PI do pacote paga um **vale**, e a metadata é só
`{kind, user_id, tokens_used, tokens_discount_cents}`. A ligação à corrida de ida
só acontece em `activate_roundtrip`, chamado **pelo cliente**.

→ No webhook trato-o defensivamente (log explícito, sem inventar), e fica o
**BUG 1-bis** aberto: *o pacote ida-e-volta tem a mesma doença do BUG 1* — se o
cliente fechar a app durante o MB Way, o dinheiro sai e o vale nunca é criado.
Não o corrigi porque a correção certa (mover a criação do vale para o webhook)
é uma mudança de desenho do checkout do pacote, não uma linha — e é 🔴.

---

## 6-bis. BUG 6 — a corrida nascia "cash" e o motorista era chamado antes de pagar

Reportado pelo Danilo a 2026-08-13 20:10 e confirmado por mim nos eventos.
**É pior do que o reportado: o motorista não foi só chamado — aceitou e pôs-se a caminho.**

```
20:10:43.398  solicitada           client   payment_method: "cash"   <-- MB Way!
20:10:43.398  oferta               system   driver 4f61dd31, ttl 40s <-- MESMO ms
20:10:44.846  push_enviado         system   driver 4f61dd31
20:10:58.757  motorista_atribuido  driver
20:10:58.757  motorista_a_caminho  driver                            <-- ACEITOU
20:12:44.126  cancelada_cliente    admin    payment_failed, elapsed=121
```

`payment_intent_id = NULL`. Um motorista da Guarda conduziu 2 minutos para uma
corrida nunca paga, com o cliente ainda parado no ecrã do MB Way.

### As duas causas, encadeadas

**(1) O Flutter não passava o método.** `_solicitarRoundtripOnline` criava a corrida
de ida com `store.requestRide(...)` **sem `paymentMethod`** → default `'cash'`.
O comentário no código até explicava o raciocínio (o PaymentIntent dos €8 está no
*vale*, não na corrida) — o raciocínio estava certo, a consequência é que não foi
seguida até ao fim.

**(2) `fn_tvde_dispatch_on_request` despacha na hora toda a corrida `'cash'`** — e
"cash" era, na prática, "o cliente não disse nada":

```sql
if new.status = 'solicitada' and coalesce(new.payment_method,'cash') = 'cash' then
```

`payment_method` é `NOT NULL DEFAULT 'cash'` (confirmei em `information_schema`),
por isso o `COALESCE` nunca fez nada — mas o desenho dizia *"na dúvida, despacha"*.

### Correção

**Servidor** (`20260813210000_PROPOSTA_tvde_bug6_despacho_so_cash.sql`) — o gate fica
onde não se pode esquecer:

```sql
if new.status = 'solicitada' and new.payment_method = 'cash' then
  perform public.tvde_offer_to_next(new.id);
else
  -- grava `dispatch_deferred` no evento, para não parecer silêncio
```

Na dúvida, **não** despacha. Cartão e MB Way passam a depender só de
`payment_status='succeeded'` → `tr_tvde_dispatch_on_paid`.

**A válvula que substitui o despacho no INSERT.** Verifiquei que *nem*
`tvde_create_roundtrip_credit` *nem* a variante `_cash` chamavam `tvde_offer_to_next`:
**o `payment_method='cash'` acidental era a única coisa que despachava a ida do pacote.**
Tirá-lo sem substituto deixaria o pacote online morto. Por isso
`tvde_create_roundtrip_credit` passa a marcar `payment_status='succeeded'` na corrida
de ida ao ligar o vale — o pacote está pago, logo a perna está paga — e o despacho sai
pelo mesmo trigger de qualquer corrida paga online. Um só mecanismo.

**App:** a ida do pacote passa a nascer com o método real (`'mbway'`/`'card'`).

### Achado extra — o mesmo bug no "Tentar de novo"

`TvdeStore.retryRide()` também caía no default `'cash'`. Quem pagou por MB Way, ficou
sem motorista e tocou em **"Tentar de novo"** recebia uma corrida em **dinheiro** sem o
saber — o motorista chegaria a pedir o valor em mão a quem julgava já ter pago.
Agora `retryRide` leva o método real e **recusa-se** a repetir uma corrida paga online
(devolve `null`); o ecrã manda o cliente à folha de pagamento com uma mensagem clara.

### Interação a vigiar

`20260804000000_PROPOSTA_tvde_roundtrip_tokens.sql` redefine
`tvde_create_roundtrip_credit` com **6** argumentos. Se for aplicada **depois** desta,
tem de levar a mesma linha do `payment_status` — senão a ida do pacote online deixa de
ser despachada de todo. Está avisado no cabeçalho da migration nova.

### Prova a recolher depois de aplicar

```sql
SELECT at, status, actor, meta FROM tvde_ride_events
WHERE ride_id = '<nova corrida MB Way>' ORDER BY at;
```

**Antes:** `solicitada` e `oferta` no mesmo milissegundo.
**Depois (verde):** `solicitada` com `meta->>'dispatch_deferred' = 'true'`, **nenhuma**
`oferta` até o pagamento fechar, e só então `oferta` + `push_enviado`.

---

## 7. Comparação com as entregas (o que copiar, e o que **não** copiar)

### 7.1 Tokens — as entregas também têm o buraco

| | Entregas | TVDE (depois desta missão) |
|---|---|---|
| O que o cliente envia | `token_discount_cents` — **o desconto em cêntimos** | `tokens_used` — só a **contagem** |
| Quem calcula o desconto | servidor recalcula o tecto, mas aceita o valor | servidor calcula tudo |
| Tecto | `token_payment_max_pct` (lido) ✅ | agora também lê a chave ✅ |
| Registo | `tokens_applied_value_cents` ✅ | ✅ (novo) |
| **Quem consome** | **o Flutter, e é `catch` silencioso** ❌ | **o servidor, por trigger** ✅ |

`lib/screens/payment_method_screen.dart:1168`:

```dart
} catch (e) {
  // Consumption failure is non-fatal — order already created.
  debugPrint('[Checkout] consume_tokens error (non-fatal): $e');
}
```

**Sim, o mesmo buraco existe nas entregas.** Se a app morrer entre criar o pedido e
consumir, o cliente fica com o desconto **e** com os tokens. Silenciosamente.

**Não o corrigi**, e digo porquê em vez de o fazer à socapa: `payment_method_screen.dart`
+ `create_order` são o checkout que cobra — 🔴 e fora do âmbito escrito desta missão.
A correção é a mesma receita que acabei de aplicar ao TVDE (trigger no servidor em vez
de chamada do cliente), e é uma sessão própria. **Fica reportado, como pediste.**

O TVDE, note-se, ficou com o padrão **melhor** que o das entregas: passa contagem em
vez de cêntimos, e consome no servidor. Se se copiar alguma coisa, copie-se ao contrário.

### 7.2 MB Way — é aqui que as entregas estão certas e o TVDE estava errado

As entregas **nunca dependeram do Flutter**: `payment_intent.succeeded` →
`stripe-webhook` → `finalize-order-from-intent` (modo B) ou `orders.payment_status='paid'`
(modo A) → `notify-partner` + `dispatch-engine`. O cliente pode fechar a app; o pedido
segue.

O TVDE tinha **o oposto**: o único caminho para marcar pago era o poll do cliente. Fechar
a app = dinheiro cobrado e corrida parada. **É exatamente isto que o BUG 1 fecha.**

O que o TVDE copia, ponto por ponto:

1. o webhook marca pago (não o cliente);
2. quem despacha é o servidor a seguir a essa marca — nas entregas o `dispatch-engine`,
   no TVDE o trigger `tr_tvde_dispatch_on_paid`;
3. o poll do cliente passa a ser **rede de segurança**, não o mecanismo.

---

## 8. Painel admin (PT-BR)

**Ecrã novo:** `lib/screens/admin/admin_tvde_stuck_payments_screen.dart` — "Corridas
presas no pagamento", ligado ao dashboard.

- Lista `status='solicitada'` + pagamento por fechar há > N min (5 / 15 / 1 h / 1 dia).
- **Coluna de tokens** — quantos, quanto valeram, e se **já foram descontados**
  (distingue "desconto dado" de "saldo baixou").
- Ações: **Reconferir na Stripe** · **Reembolsar** · **Cancelar**.
- RPC `admin_tvde_stuck_payments(p_minutes)` (read-only, gated por `is_admin()`).
- Para o botão "Reconferir" funcionar, `confirm_ride_payment` passa a aceitar admin
  (dava 403 em corridas de outros).

**Ajuste sem deploy** (`admin_platform_settings_screen.dart`):

| chave | estado |
|---|---|
| `cancel_grace_seconds` | já era editável |
| `tvde_cancel_full_after_grace` | **adicionada** |
| `token_payment_max_pct` | **adicionada** (só afeta TVDE depois da migration) |

---

## 9. ⚠️ ISTO MEXE EM PAGAMENTO/DINHEIRO. Está tudo pronto — confirma que eu aplico.

Nada disto foi aplicado em produção. Por ordem:

| # | ação | risco se sair fora de ordem |
|---|---|---|
| 1 | aplicar `20260813200000_PROPOSTA_tvde_tokens_e_cancelamento.sql` | — |
| 2 | aplicar `20260813210000_PROPOSTA_tvde_bug6_despacho_so_cash.sql` | — |
| 3 | `python .../aplicar_stripe_webhook.py --aplicar` + deploy `stripe-webhook` | **sem isto o passo 2 deixa cartão/MB Way sem quem os despache** |
| 4 | deploy `tvde-payment` | sem o passo 1 o refund não lê `cancel_fee_cents` correto |
| 5 | build/deploy do app (Flutter + admin) | sem o passo 1 o ecrã novo dá erro tratado |

**Os passos 2 e 3 andam juntos.** O passo 2 tira o despacho no INSERT a cartão/MB Way;
quem passa a despachá-los é o webhook do passo 3. Aplicar o 2 sozinho deixa as corridas
online paradas.

**Não fiz `git push`.** Dois motivos, ambos concretos:

1. **A branch não bate certo.** A missão diz `autonomous-night-2026-04-29`; a branch
   atual é `autonomous-night/fase2-cortex-tasks`. Não adivinho para onde publicar.
2. **Push = publicação** (regra 3 do CLAUDE.md): dispara build Android → Play alpha
   **e** deploy web. Com o backend por aplicar, publicava-se um app que fala com um
   servidor que ainda não sabe responder.

### 🚨 Mina no working tree — e agora está entrançada com o meu trabalho

Ficheiros de uma sessão anterior (`tvde_store.dart`, `tvde_request_ride_screen.dart`,
`tvde-plan-payment/index.ts`) chamam `tvde_create_roundtrip_credit_cash` com **2
argumentos**. Em produção a função tem **1**. Deployado assim, **o pacote ida-e-volta
em dinheiro parte inteiro** ("function not found"). A própria migration
`20260804000000_PROPOSTA_tvde_roundtrip_tokens.sql` avisa disto no cabeçalho — e
**não** inclui a versão CASH; ficou por escrever.

**Na 1.ª volta desta missão consegui deixá-los fora do commit. Já não consigo:**
o BUG 6 vive exatamente nesses dois ficheiros Dart
(`_solicitarRoundtripOnline` e `retryRide`). Estão agora no commit — com o meu fix
**e** com a chamada de 2 argumentos.

**Consequência prática:** o último bloqueador antes de qualquer deploy é escrever
`tvde_create_roundtrip_credit_cash(p_outbound_ride_id UUID, p_tokens_to_apply INT
DEFAULT 0)`. Já tenho o corpo atual da função lido do servidor — é meia hora de
trabalho, e desarma a mina de vez. **Não a escrevi porque não estava no âmbito
pedido; digo-o em vez de a deixar caladinha.** Diz e faço.

---

## 10. Teste ponta-a-ponta — o que falta, e é humano

Não posso executá-lo: precisa de MB Way real (€5), do segundo telemóvel em modo
motorista online, e dos passos 1–4 acima feitos. Quando estiver, a prova a recolher é:

```sql
-- 1. o webhook viu e marcou (tem de aparecer a linha nova, não a antiga "missing metadata")
--    [stripe-webhook] tvde ride paid: <ride_id>

-- 2. e o despacho arrancou sozinho
SELECT id, payment_status, current_offer_driver_id, offer_expires_at,
       array_length(tried_driver_ids,1) AS n_tried, tokens_applied_count, tokens_consumed_at
FROM tvde_rides ORDER BY created_at DESC LIMIT 1;
```

**Verde =** `payment_status='succeeded'` · `current_offer_driver_id` preenchido ·
`n_tried ≥ 1` · push recebido no telemóvel do motorista ·
`tokens_consumed_at` preenchido se tiver usado tokens.

---

## 11. Ficheiros

**Escritos por mim**

| ficheiro | o quê |
|---|---|
| `.claude/.ai/propostas/tvde-pagamento-2026-08-13/aplicar_stripe_webhook.py` | 🔴 BUG 1 — proposta aplicável (4/4 âncoras OK) |
| `supabase/migrations/20260813200000_PROPOSTA_tvde_tokens_e_cancelamento.sql` | 🔴 BUG 2 + 4a + tecto + RPC do painel |
| `supabase/migrations/20260813210000_PROPOSTA_tvde_bug6_despacho_so_cash.sql` | 🔴 BUG 6 — gate do despacho + válvula do pacote |
| `lib/stores/tvde_store.dart` | BUG 6 — `retryRide` deixa de virar dinheiro às escondidas |
| `lib/screens/client/tvde/tvde_request_ride_screen.dart` | BUG 6 — ida do pacote leva o método real |
| `supabase/functions/tvde-payment/index.ts` | BUG 4b/4c — registo honesto, dono/admin, taxa do servidor |
| `lib/models/tvde_ride.dart` | BUG 5 — raiz: getters liam `status`, não `payment_status` |
| `lib/screens/client/tvde/tvde_ride_tracking_screen.dart` | BUG 5 — texto MB Way + cancelar não salta o refund |
| `lib/screens/client/tvde/ride_mbway_waiting_dialog.dart` | BUG 5 — poll da corrida 120 s → 300 s |
| `lib/screens/admin/admin_tvde_stuck_payments_screen.dart` | painel (novo) |
| `lib/screens/admin/admin_dashboard_screen.dart` | entrada do painel |
| `lib/screens/admin/admin_platform_settings_screen.dart` | 2 chaves editáveis |

**NÃO tocados:** `stripe-webhook/index.ts` (Trava) · `tvde_ride_charge_cents`
(secção 4) · qualquer ramo de entregas/reservas/wallet · `tvde-plan-payment/index.ts`
· `tvde_create_roundtrip_credit_cash` (a mina da secção 9, por desarmar).
