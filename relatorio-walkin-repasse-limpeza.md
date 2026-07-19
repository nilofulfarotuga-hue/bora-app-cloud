# Relatório — Walk-in, repasse Beleza (saldo negativo) e fecho semanal Limpeza

**Data:** 2026-07-19 · **Branch:** autonomous-night-2026-04-29 · **Modo:** PROTECÇÃO TOTAL
**⚠️ Envolve dinheiro real (repasses).** Código pronto e testado; **a aplicação das
migrations à base de produção aguarda o teu "vai"** (Lista Vermelha).

---

## Contexto de arranque
- `git pull` (HTTPS) feito antes de começar → estava 1 commit atrás; fast-forward do
  `a3cc03f ci: bump versionCode to 479` (só versionCode, sem código).
- **Tarefa 3 (Limpeza) já estava feita e no origin** no commit `43bd618`
  (`feat(limpeza): fecho/repasse semanal de profissionais de limpeza`). Auditei a
  migration e confere com a especificação (ver §3). Só faltava juntar ao relatório
  combinado e confirmar a matemática.
- Não toquei em `booking_flow_screen.dart` (a tarefa concorrente do cliente) — sem colisão.

---

## TAREFA 1 — BUG: walk-in do parceiro aparecia na tela do CLIENTE

### Causa raiz (provada no código)
`ServicesStore.fetchMyAppointments()` (`lib/stores/services_store.dart`) lia
`from('appointments').select(...).order(...).limit(100)` **sem qualquer filtro de
`client_user_id` nem de `is_walk_in`** — dependia 100% da RLS.

A política `ap_select` (migration `20260608000002`) é:
```
client_user_id = auth.uid()
  OR EXISTS (service_provider do provider pertence a auth.uid() OU is_admin)
```
Ou seja: quando **um parceiro-dono abre "As minhas marcações" no lado cliente**, a
query sem filtro devolve as marcações do **seu próprio provider** — incluindo os
walk-ins do balcão (`is_walk_in=true`, `client_user_id=null`, sinal `waived` → o card
mostrava "Sem sinal"). Exatamente o sintoma do Gilberto.

### Correção (cirúrgica, aditiva)
`lib/stores/services_store.dart`:
- **`fetchMyAppointments`**: obtém `uid = auth.currentUser?.id` (bail-out se null) e passa
  a filtrar explicitamente:
  ```dart
  .eq('client_user_id', uid)
  .eq('is_walk_in', false)
  ```
  Agora só aparecem as marcações onde o utilizador é o **cliente** e que **não são
  walk-ins** — mesmo que ele também seja parceiro.
- **`subscribeMyAppointments`** (realtime): o stream já filtra `client_user_id=uid`
  (walk-ins têm `client_user_id=null`, logo nunca entravam). Ainda assim adicionei um
  guarda defensivo `where((row) => row['is_walk_in'] != true)` no mapeamento.

### RLS
A `ap_select` **não é permissiva de mais**: escopa a (linhas do próprio cliente) OU
(linhas do próprio provider). Não vaza para utilizadores arbitrários. **Não a apertei**
porque o app do parceiro precisa de ler as marcações do seu provider — apertar partia o
lado parceiro. O vazamento era a falta de filtro na **query**, agora corrigida.
`flutter analyze` → **No issues found**.

---

## TAREFA 2 — €0,50 por walk-in + saldo semanal NEGATIVO (Beleza)

Migration nova: `supabase/migrations/20260719010000_appointment_walkin_fee_negative_payout.sql`

### Decisões (documentadas, caminho conservador)
1. **Quando cobra:** o €0,50 do walk-in é cobrado **apenas quando `status='completed'`**
   (serviço realizado). Walk-in cancelado/no-show **não** cobra — igual à lógica
   "só conta o que aconteceu". *(Nota: o parceiro precisa de marcar o walk-in como
   concluído, fluxo já existente, para a taxa entrar.)*
2. **Setting nova** `appointment_walkin_fee_cents = 50` (`to_jsonb(50)`, ON CONFLICT DO
   NOTHING) — separada do `appointment_deposit_bora_cut_cents` para não confundir o
   "uso do sistema" com o corte do sinal.
3. **Walk-ins não entram no split do sinal** (€2,50 do parceiro): um walk-in tem
   `deposit_status='waived'` e `deposit_cents=0`, não há sinal para repartir. Por isso o
   count de `completed` do lado do parceiro passou a exigir `is_walk_in=false`; o walk-in
   só contribui com a taxa de −€0,50.
4. **Saldo negativo permitido:** não havia nenhum clamp `GREATEST(...,0)` (confirmado) e a
   coluna `net_payout_cents` não tem CHECK ≥ 0. `direction` passa a ser dinâmico:
   `net ≥ 0 → 'bora_to_partner'`, `net < 0 → 'partner_to_bora'` (parceiro paga a Bora).
5. **Colunas novas** (aditivas) em `appointment_payouts`:
   `total_walkins int` + `total_walkin_fees_cents int`.

### Fórmula nova de `compute_provider_weekly_payout`
```
completed  = nº status='completed'  AND is_walk_in=false
walkins    = nº status='completed'  AND is_walk_in=true
retained   = no_show + (cancelled & deposit_status='retained')   [is_walk_in=false]
consumed   = completed + retained
walkin_fees= walkins * appointment_walkin_fee_cents (50)
net        = consumed * partner_cut(250) + service_rev_app − walkin_fees
direction  = net ≥ 0 ? bora_to_partner : partner_to_bora
bora_rev   = completed*booking_fee(50) + retained*bora_cut(50) + walkin_fees
```

### Provas de matemática
| Teste | completed | walkins | retained | net | direction |
|---|---|---|---|---|---|
| **A** — 3 clientes + 4 walk-ins | 3 | 4 | 0 | 3×250 − 4×50 = **+550 (€5,50)** | bora_to_partner ✅ |
| **B** — só 5 walk-ins | 0 | 5 | 0 | 0 − 5×50 = **−250 (€2,50)** | partner_to_bora ✅ |

Ambos batem com o esperado no pedido.

### Admin (PT-BR) — `admin_appointments_payouts_screen.dart`
- Cada linha mostra **walk-ins da semana** e o desconto (`N walk-ins · −€X,XX (uso do sistema)`).
- Saldo **negativo** é claro: montante a vermelho `−€X,XX`, barra lateral vermelha e chip
  **"A PAGAR À BORA"** vs **"A RECEBER DA BORA"** no caso normal.
- `admin_list_appointment_payouts` devolve `ap.*` → as colunas novas fluem sem alterar a RPC.
`flutter analyze` → **No issues found**.

---

## TAREFA 3 — Fecho semanal da LIMPEZA (já em `43bd618`, auditado)

Migration `supabase/migrations/20260719000000_cleaner_weekly_settlements.sql`:
- Tabela `cleaner_weekly_settlements` com todas as colunas pedidas + `UNIQUE(cleaner_id,
  week_start_at)`; RLS leitura pelo próprio cleaner OU admin, escrita só admin. ✅
- `compute_cleaner_weekly_settlement(p_cleaner_id, p_week_start=null, p_persist=true)` +
  `compute_all_cleaner_weekly_settlements()`, **reutilizando** `driver_settlement_week_bounds`. ✅
- Soma `cleaner_earnings_cents` dos `cleaning_bookings` com `status='completed'`, não-teste,
  **pela data do serviço** (`COALESCE(completed_at, scheduled_at)`), nunca pelo pagamento.
  Cancelado/no-show não paga. Upsert `ON CONFLICT (cleaner_id, week_start_at)`. ✅
- RPCs admin (list/mark-paid/recompute) + cron `cleaning-weekly-settlement` `'0 8 * * 1'`. ✅
- Tela admin `admin_cleaner_settlements_screen.dart` + link no dashboard. ✅

### Prova de matemática
**2 serviços completos + 1 cancelado** → o `count(*)`/`SUM` filtra `status='completed'`,
logo `total_jobs = 2` e `net = soma dos 2` (o cancelado é ignorado). ✅

---

## ⚠️ PENDENTE DE "VAI" (dinheiro real — Lista Vermelha)
Está tudo pronto e o `flutter analyze` limpo. **Não apliquei nada que mova/altere dinheiro.**
Confirma que eu aplico:
1. **Aplicar à base de produção** a migration `20260719010000` (Beleza: taxa walk-in +
   saldo negativo).
2. **Aplicar à base de produção** a migration `20260719000000` (Limpeza) — se ainda não
   estiver aplicada (o commit já está no origin, mas o *apply* à DB é o passo de dinheiro).

O `git commit`/`push` do **código** (Tarefas 1 e 2) não move dinheiro (a CI só compila o app
e injeta chaves como dart-defines; **não** corre `db push`), por isso segue com a entrega.
A ativação real dos repasses só acontece quando as migrations forem aplicadas à DB.
