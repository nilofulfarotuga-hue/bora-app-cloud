---
id: tvde-pagamentos-pente-fino-2026-07-20
tema: tvde
estado: atual
tipo: relatorio
data: 2026-07-20
autor: CEO-AI (sessão interativa, MODO PROTECÇÃO TOTAL)
---

# TVDE cliente — pagamento a sério (Dinheiro · Cartão · MB Way) — pente fino

**Autorização do Danilo:** *"vai na Fase 1 + faz o ecrã admin de dívidas de motorista
(Flutter). NÃO apliques nada de backend de dinheiro (EF, migration, RPC) — o Claude.ai faz
via MCP. No bug 4 (€8 dupla), só investiga e prova o link, não mexes."*

**Cumprido à risca:** zero alterações a Edge Functions, migrations, RPCs ou preços.
Só Flutter. Plano detalhado em `PLANO-tvde-pagamentos-pente-fino-2026-07-20.md`.

---

## 1. A prova que explica tudo

```sql
select payment_method, payment_status, count(*) n, count(payment_intent_id) com_pi
  from tvde_rides group by 1,2;
-- [{"payment_method":"cash","payment_status":null,"n":53,"com_pi":0}]

select count(*) from tvde_roundtrip_credits;   -- 0
```

**53 corridas TVDE desde sempre. TODAS em dinheiro. ZERO com `payment_intent_id`.
ZERO vales ida-e-volta alguma vez criados.** Nenhum pagamento online do TVDE passou
alguma vez em produção — não é intermitência, é um caminho que nunca funcionou.

E as assinaturas:
```sql
select plan, payment_status, activated_via, stripe_payment_intent_id is not null tem_pi
  from tvde_subscriptions;
-- 3 linhas · activated_via ∈ {admin, bonus_admin} · tem_pi = false em todas
```
As 3 assinaturas existentes foram **concedidas pelo admin**, nenhuma foi paga. O caminho
de pagamento do plano também nunca foi exercido em produção.

---

## 2. Causa-raiz (bug 1) — confirmada, e era mesmo a tua hipótese

O MB Way **nunca recebeu o número de telemóvel** em nenhum ponto do TVDE-corrida:

| Camada | O que estava lá |
|---|---|
| `TvdePaymentSelector` | só 3 chips — **nenhum campo de número** |
| `_TvdePayResult` | `(method, note, tokensUsed)` — **sem telefone** |
| `_solicitar()` | `store.requestRidePaid(...)` chamado **sem `mbwayPhone:`** |
| EF `tvde-payment:159` | `const phone = String(body.phone ?? '')` → `''` |
| EF `tvde-payment:160` | `e164 = '+351' + ''` → **`"+351"`** → a Stripe recusa |

O `TvdeStore.requestRidePaid` **já aceitava** `mbwayPhone` e já o enviava — o parâmetro
simplesmente nunca era preenchido por ninguém. Um buraco de 1 argumento.

---

## 3. Bug 4 (€8 cobrança dupla) — **DESMENTIDO com prova**

Investigado, não tocado, conforme instruído. `tvde_finish_ride` (definição ao vivo):

```plpgsql
v_prepaid := v_ride.roundtrip_credit_id IS NOT NULL;
...
IF v_prepaid THEN
  v_fare        := v_stops_fee;          -- tarifa = SÓ as paradas extra
  v_driver_earn := v_driver_earn + v_stops_drv;
  v_bora_cut    := v_fare - v_driver_earn;
```

**Não há cobrança dupla.** Quando a corrida está ligada ao vale (`roundtrip_credit_id`
preenchido), a tarifa final passa a ser apenas as paradas extra (€0 se não houver
paradas). O `paymentMethod:'cash'` da corrida de ida é inofensivo — não há nada a cobrar.

**Mas o link é condição necessária.** Se a ida não ficar ligada ao vale, `v_prepaid` é
falso e o cliente paga a ida outra vez. Por isso o fluxo MB Way do €8 foi construído
**com a corrida criada ANTES** do `activate_roundtrip` (secção 4.3).

---

## 4. O que foi feito (só Flutter)

### 4.1 Corrida · MB Way — campo de número + envio (fecha o bug 1)
- `lib/widgets/tvde/tvde_payment_selector.dart` — o selector passa a mostrar o campo
  **Número MBWay** (prefixo `+351`) quando MB Way está escolhido. Mesmo contrato do
  `ReservationPaymentMethodSheet`: 9 dígitos, controller do pai.
- `tvde_request_ride_screen.dart` — `_TvdePayResult` ganha `mbwayPhone`; a folha
  pré-preenche do perfil (`AuthStore.currentClient?.phone`), valida 9 dígitos antes de
  confirmar, e `_solicitar()` passa o número a `requestRidePaid(mbwayPhone:)`.

### 4.2 Corrida · MB Way — espera pela confirmação (bug 2, parcial)
- `lib/screens/client/tvde/ride_mbway_waiting_dialog.dart` (novo) — dialog de espera
  (poll 3 s, timeout 120 s, não-dispensável), irmão do `PlanMbwayWaitingDialog`.
- `TvdeStore.fetchRidePaymentStatus(rideId)` (novo, **SELECT read-only**) — lê
  `tvde_rides.payment_status`.
- Degrada com honestidade: sem confirmação segue para o tracking com aviso, em vez de
  fingir que pagou.

> ⚠️ **Isto ainda não fecha 100%** — ver secção 6. Nada hoje escreve `succeeded` no
> `payment_status` da corrida. O dialog está pronto e passa a funcionar sozinho no
> momento em que a ação server-side existir.

### 4.3 €8 ida-e-volta · MB Way (fecha o bug 3)
`_solicitarRoundtrip()` reescrito. Antes: só cartão, e o
`TvdeStore.createRoundtripPaymentMbway()` era **código morto — nunca chamado por ninguém**.
Agora abre o `ReservationPaymentMethodSheet` (cartão | MB Way) e segue esta ordem:

1. PaymentIntent dos €8 (`create_roundtrip` ou `create_roundtrip_mbway` com o número)
2. Cartão → confirma já. MB Way → confirma-se na app do banco.
3. **Cria a corrida de IDA** — tem de existir antes do passo 4 (secção 3)
4. `activate_roundtrip` liga a ida ao vale. No MB Way é o próprio `activate_roundtrip`
   que serve de poll: só passa com o PaymentIntent em `succeeded`, é idempotente, e
   devolve 402 enquanto não estiver pago.

Sem confirmação, o vale não é criado e a corrida segue como corrida normal — o cliente
paga a tarifa ao motorista. **Nunca há cobrança dupla nem corrida grátis.**

### 4.4 Admin (PT-BR) — as duas lacunas fechadas
- `admin_tvde_roundtrips_screen.dart` (novo) — a RPC `admin_tvde_roundtrips(p_limit)`
  **já existia em produção mas nenhum ecrã a chamava**; os vales eram invisíveis.
  Estados: por usar / usada / expirado.
- `admin_tvde_driver_debts_screen.dart` (novo) — dívidas em dinheiro dos motoristas.
  Lê `tvde_driver_balances` **direto** (a policy `tvde_driver_bal_select` já permite
  `is_admin()`), junta nome/telefone de `drivers`, mostra o **total**, busca e exporta CSV.
  Read-only: *liquidar* mexe em dinheiro e precisa de RPC nova (não feita, por ordem tua).
- Ambos ligados no `admin_dashboard_screen.dart`.

### 4.5 Plano/assinatura (C)
**Já estava completo e correto** — não foi tocado. `tvde_plans_screen.dart` usa o
`ReservationPaymentMethodSheet` + `PlanMbwayWaitingDialog`. É o padrão-ouro que foi
copiado para (A) e (B).

---

## 5. Checklist — só marcado com prova

| # | Item | Estado | Prova |
|---|---|---|---|
| 1 | Corrida · Dinheiro cria corrida | ✅ | `payment_method='cash'` × 53 em `tvde_rides`; caminho não tocado |
| 2 | Corrida · Cartão COBROU | ⚠️ **não provado** | código pronto e compila; exige cartão real (secção 7) |
| 3 | Corrida · MB Way COBROU | ⚠️ **não provado** | bug do telefone corrigido; falta a ação server-side (secção 6) |
| 4 | €8 · Cartão COBROU + vale criado | ⚠️ **não provado** | fluxo pronto; `tvde_roundtrip_credits` ainda = 0 |
| 5 | €8 · MB Way COBROU + vale criado | ⚠️ **não provado** | fluxo novo pronto; idem |
| 6 | Plano · Cartão COBROU | ⚠️ **não provado** | código já existia; nunca exercido (3 subs = grant admin) |
| 7 | Plano · MB Way COBROU | ⚠️ **não provado** | idem |
| 8 | Cancelamento → refund correto | ⚠️ **não auditado** | `action:'refund'` existe; sem corrida paga não há o que reembolsar |
| 9 | Admin vê dinheiro + cartão + plano + ida-e-volta + dívidas | ✅ | 2 ecrãs novos; `admin_tvde_roundtrips` responde; dívida real €46,10 |
| 10 | Relatório das 2 overloads + bugs extra | ✅ | secções 6 e 8 |

**Não marquei nenhum dos "COBROU".** Nenhuma cobrança real foi feita — ver secção 7.

### Provas mecânicas

**`flutter analyze`** — 0 erros. Os `info` restantes são pré-existentes
(const/deprecated), **nenhum** nos ficheiros novos.

**`flutter test test/tvde_payment_selector_test.dart`** — 9/9 verdes: os **3 testes que já
existiam ficaram intactos** + 6 novos de regressão do bug do número:
```
+1 switch OFF → só Dinheiro      +2 switch ON → 3 métodos     +3 onChanged com o valor certo
+4 MB Way escolhido → mostra o campo do número
+5 Dinheiro → sem campo          +6 Cartão → sem campo
+7 kill switch OFF ganha ao método → sem campo
+8 o número escrito fica no controller do pai
+9 erro de validação aparece no campo
00:05 +9: All tests passed!
```

**Suite completa** — 46 passam, 1 falha: `order_eta_service_distance_test.dart`
("distâncias não podem repetir-se entre restaurantes"). **Não é desta sessão** — é um
ficheiro *untracked* (`??` no `git status`) criado por outro executor a trabalhar em
paralelo nesta mesma working directory, sobre haversine de restaurantes. Zero relação com
TVDE/pagamentos e fora do meu diff.

**Juiz · chão anti-trapaça** (`python .claude/juiz/anti_trapaca.py --base HEAD`):
```
JUIZ · CHÃO ANTI-TRAPAÇA (determinístico)  →  ✅ CLEAN
Δ casos de teste: +6 · Nenhuma batota detetada. Diff mecânico limpo.   EXIT=0
```

---

## 6. 🔴 O que falta, e é backend (para o Claude.ai aplicar via MCP)

### 6.1 BLOQUEADOR do MB Way da corrida — ação `confirm_ride_payment`
A EF `tvde-payment` só tem `charge` e `refund`, e o cabeçalho diz que **não usa o
`stripe-webhook`**. Quando o MB Way é cobrado, o PaymentIntent volta em
`requires_action`/`processing` e fica gravado assim — **e nada, em lado nenhum, alguma vez
o atualiza para `succeeded`**.

Falta uma ação que faça retrieve do PI e escreva o estado:
```ts
// action: 'confirm_ride_payment'  { ride_id }
// → stripe.paymentIntents.retrieve(ride.payment_intent_id)
// → update tvde_rides set payment_status = pi.status where id = ride_id
// (mesmo padrão do `activate` do tvde-plan-payment, que já funciona)
```
O dialog do lado do cliente já faz poll ao `payment_status` — **assim que esta ação
existir, o MB Way da corrida fecha sozinho, sem mais nenhuma alteração no Flutter.**

### 6.2 Overloads de `tvde_request_ride` — confirmado ao vivo
```sql
tvde_request_ride(float8,float8,text,float8,float8,text,numeric,text)     -- p_payment_method
tvde_request_ride(float8,float8,text,float8,float8,text,numeric,integer)  -- p_tokens_to_apply
```
A UI e a EF nomeiam `p_payment_method` → o PostgREST resolve **sempre** para a primeira
→ **`p_tokens_to_apply` nunca chega e o toggle de tokens é decorativo**. A migration de
fusão já está escrita e continua por aplicar (com a fórmula 10× já corrigida):
`supabase/migrations/20260717000000_PROPOSTA_tvde_request_ride_merge_tokens_payment.sql`.
As 5 linhas client-side do threading continuam uncommitted — **só commitar DEPOIS da
migration entrar em prod**, senão parte o TVDE inteiro com PGRST202.

### 6.3 Liquidar dívida de motorista
Não existe RPC para liquidar. O ecrã novo é read-only + export. Para liquidar seria
preciso algo como `admin_tvde_settle_driver_debt(driver_id, valor, motivo)` com escrita em
`admin_audit_log`.

---

## 7. Porque nenhuma cobrança real foi feita

Há device ligado (`23028RN4DG`), **mas o APK não chegou a ser gerado**:

```
Running Gradle task 'assembleDebug'...   698,3s
FAILURE: Gradle build daemon disappeared unexpectedly (it may have been killed or may have crashed)
JVM crash log found: android/hs_err_pid12256.log
adb: failed to stat build/app/outputs/flutter-apk/app-debug.apk: No such file or directory
```

Crash da JVM do Gradle (`-Xmx1536m` numa máquina com ~3,8 GB) — é o problema de RAM já
conhecido desta máquina, **não** tem relação com o código desta sessão: rebentou no
Gradle, não na compilação Dart. Não repeti a tentativa igual (Lei do Pré-Voo); a
compilação do Dart foi provada por outra via — ver secção 5 (widget tests).

E mesmo com APK:

- `BORA_STRIPE_MODE` faz default a **`live`** — qualquer teste cobra **dinheiro real**.
- Cartão exige os dados de um cartão real; MB Way exige que **tu** confirmes no telemóvel.

Não disparei cobranças LIVE nem pushes MB Way para o teu telemóvel sem tu contares com
isso. **O que precisas de fazer:** abrir a app no device, pedir uma corrida, escolher
MB Way, e o número aparece agora (antes não aparecia). Confirmas no MB Way e vemos o
`payment_status` na hora — mas o item 3 do checklist só fecha depois da 6.1.

---

## 8. Bugs extra encontrados no pente fino (nenhum tocado)

### 8.1 🔴 Dívida do motorista acumula mesmo quando o cliente paga online
`tvde_finish_ride` acumula em `tvde_driver_balances` sem olhar ao método de pagamento:
```plpgsql
IF v_settle > 0 THEN
  INSERT INTO public.tvde_driver_balances (driver_id, balance, ...)
    VALUES (v_uid, ROUND(v_settle / 100.0, 2), now())
    ON CONFLICT (driver_id) DO UPDATE SET balance = ... + ROUND(v_settle / 100.0, 2);
```
`v_settle` é a parte da Bora. Isso faz sentido em **dinheiro** (o motorista recebeu tudo
em mão e deve à Bora). Em **cartão/MB Way a Bora já recebeu tudo** — o motorista passaria
a dever uma quantia que não deve, e ainda por cima é a Bora que lhe deve a ele.
Nunca deu problema porque nenhuma corrida online passou (secção 1) — **mas explode no
minuto em que a primeira passar.** Prioridade alta, a arrumar junto com a 6.1.

### 8.2 🟡 `price_cents` histórico não bate com o `platform_settings`
As assinaturas gravadas têm `price_cents=5600` (€56) para o plano semanal, mas
`tvde_plan_weekly_cents=4000` (€40). São grants de admin antigos; a EF lê o preço
server-side, por isso não afeta cobranças. Só ruído no ecrã de assinaturas.

### 8.3 🟢 `tvde_cash_max_cents` não existe em `platform_settings`
O travão de €40 em dinheiro do TVDE não tem chave própria. A confirmar se é intencional
(herda do delivery) ou se o travão simplesmente não existe no TVDE.

---

## 9. Ficheiros tocados

**Novos**
- `lib/screens/client/tvde/ride_mbway_waiting_dialog.dart`
- `lib/screens/admin/admin_tvde_roundtrips_screen.dart`
- `lib/screens/admin/admin_tvde_driver_debts_screen.dart`

**Alterados**
- `lib/widgets/tvde/tvde_payment_selector.dart` — campo de número MB Way
- `lib/screens/client/tvde/tvde_request_ride_screen.dart` — telefone + poll + €8 MB Way
- `lib/stores/tvde_store.dart` — `fetchRidePaymentStatus` (SELECT)
- `lib/screens/admin/admin_dashboard_screen.dart` — 2 entradas novas

**Zonas protegidas:** nenhuma tocada (`dispatch_engine`, `pricing_service.dart`,
`finalizePurchase`, `bora_tokens`, `stripe-webhook`, delivery, preços, `versionCode`).
