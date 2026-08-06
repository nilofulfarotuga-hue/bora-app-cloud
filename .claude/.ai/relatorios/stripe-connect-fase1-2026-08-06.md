# Stripe Connect Express — Fase 1 (fundação + onboarding + extrato)
**Data:** 2026-08-06 · **Sessão:** Claude Code (Fable) no PC · **Branch:** autonomous-night-2026-04-29

> Regra de ouro respeitada: **nenhum dinheiro novo se move**. O acerto semanal
> continua manual. `stripe_connect_enabled` continua **false**. Nenhuma zona
> protegida foi tocada (dispatch, pricing, finalizePurchase, bora_tokens,
> create-payment-intent, webhook Stripe existente, post_order_to_ledger,
> apply_order_financial_split, partner_store_share — tudo intacto).

## 0. Fundação (pré-existente) confirmada por SQL ✅
- As 4 tabelas (`restaurants`, `service_providers`, `drivers`, `cleaners`) têm
  as 6 colunas `stripe_*`.
- `platform_settings` categoria `stripe_connect` com as 7 chaves e os valores
  esperados (`stripe_connect_enabled=false`, `stripe_fee_bearer="partner"`,
  0.015 / 25 / 0.0025 / 25 / 200).

## 1. O que ficou feito

### Base de dados (migrations APLICADAS em prod)
| Migration | Conteúdo |
|---|---|
| `stripe_connect_statement_2026_08_06` | `stripe_connect_events` (idempotência, PK event_id) · `partner_statement_lines` + índice + RLS (dono lê o seu, admin lê tudo, só service_role escreve) · `stripe_connect_fee_cents()` (função ÚNICA da taxa — lê platform_settings; `fee_bearer='platform'` → 0) · `apply_stripe_account_update()` (espelho da conta, fonte única usada pelo webhook e pelo re-sync; só service_role) · `get_statement()` · `admin_list_connect_accounts()` · backfill dos acertos existentes |
| `stripe_connect_status_rpc_2026_08_06` | `get_my_connect_status(p_role)` + `get_statement` v2 com `connect_enabled` |

Ficheiros no repo: `supabase/migrations/20260806120000_stripe_connect_statement.sql`
e `20260806121000_stripe_connect_status_rpc.sql`.

**Desvio consciente da spec:** `owner_id` é **TEXT**, não uuid — `restaurants.id`
e `service_providers.id` são TEXT legado (impossível guardar "mr-kebab" num uuid).
Drivers/cleaners guardam o uuid como texto.

**Backfill:** existiam só 2 `driver_weekly_settlements` → 5 linhas criadas
(2 vendas, 2 acertos, 1 payout). As outras 3 tabelas de acerto estavam vazias
(o SQL cobre-as na mesma, idempotente).

### Edge Functions (DEPLOYADAS, v1 ACTIVE)
| Função | verify_jwt | O que faz |
|---|---|---|
| `stripe-connect-onboard` | true | Resolve a linha pelo JWT (nunca aceita id do cliente), cria conta Express (PT/EUR/transfers, metadata bora_*), grava `stripe_account_id`+`pending`, devolve Account Link; conta `enabled` → login link do Express Dashboard |
| `stripe-connect-webhook` | false (assinatura própria `STRIPE_CONNECT_WEBHOOK_SECRET`) | `account.updated` → RPC espelho · `account.application.deauthorized` → disabled · `payout.paid/failed` → auditoria em `stripe_connect_events`; failed → `notify_admin_event`. Idempotente por event_id; erro no handler apaga o registo para a Stripe reentregar. **Separado do stripe-webhook existente.** |
| `stripe-connect-admin` | true (+ `is_admin()`) | onboard_link / login_link / resync (accounts.retrieve → espelho) / disconnect (volta a acerto manual). Tudo em `admin_audit_log`. |

As 3 usam o interruptor `BORA_STRIPE_MODE` (test→`STRIPE_TEST_SECRET_KEY`), igual ao tvde-payment.

**Desvio consciente da spec:** os deep links `boraapp://connect/*` não são
possíveis — a Stripe **só aceita http(s)** em refresh_url/return_url (e o scheme
real do app é `pt.boraapp.bora`, não `boraapp://`). Ficou o fallback web como
principal: `https://bora-app-web.pages.dev/connect/refresh|return`.

### App (PT-PT)
- `lib/screens/connect/connect_payments_screen.dart` — "Receber pagamentos":
  estado grande em português simples (Ainda não configurado / Em verificação /
  A receber normalmente / Bloqueado — faltam dados), `currently_due` traduzido,
  botão Começar/Continuar/Ver os meus pagamentos (browser externo). "Stripe"
  quase não aparece.
- `lib/screens/connect/connect_statement_screen.dart` — "Extrato": Hoje/Esta
  semana/Este mês, linhas + totais (vendido, comissão, taxas, líquido),
  "Pago pela Stripe ✅ a DD/MM", Exportar PDF (AdminExportService já existente),
  rodapé "Pagamento ainda por transferência bancária." enquanto
  `connect_enabled=false`.
- Entradas: dashboard do parceiro (2 botões), hub parceiro-serviços (2 tiles,
  role provider), perfil do estafeta (2 tiles, role driver).

### Painel admin (PT-BR)
- `lib/screens/admin/admin_connect_payments_screen.dart` — "Pagamentos Connect":
  lista as contas dos 4 papéis (filtro por papel, chips de estado,
  charges/payouts, o que falta, data de onboarding); ações por conta (reenviar
  link, abrir no dashboard Stripe, re-sincronizar, desligar → acerto manual);
  edição das 7 chaves `stripe_connect` via RPC `admin_update_setting` com aviso
  "mexer nas taxas muda o que o parceiro vê no extrato"; extrato de qualquer
  conta + exportar CSV; trilha de auditoria (ações `stripe_connect_*`).
- Card registado no `admin_dashboard_screen.dart`.

### Guia
- `GUIA_DANILO_STRIPE_CONNECT.md` (raiz do repo, PT-BR): ativar Connect +
  termos, modelo de preços, criar o webhook novo (URL + 4 eventos + "Listen to
  events on Connected accounts"), colar `STRIPE_CONNECT_WEBHOOK_SECRET` no
  Supabase, cadastro presencial com o Gilberto (Ouro e Prata), teste em modo
  teste antes de ligar.

## 2. Prova real (outputs verdadeiros da sessão)

**a) Transições de estado pelo caminho do webhook** — parceiro fictício
`DEMO_CONNECT_PROVA` (cleaner d92a9f8c…, conta `acct_DEMO_PROVA_20260806`),
chamando `apply_stripe_account_update` (exatamente o que o webhook chama):
```
1-pending:    {"status":"pending","charges":false,"payouts":false,"due":[]}
2-restricted: {"status":"restricted","charges":true,"payouts":false,
               "due":["individual.verification.document","external_account"]}
3-enabled:    {"status":"enabled","charges":true,"payouts":true,"due":[],
               "onboarded_at":"2026-08-06T09:00:11.165825+00:00"}   ← carimbado sozinho
```
(rpc devolveu `{"found":["cleaner"],"status":...}` em cada passo)

**b) get_statement** (impersonação do utilizador fictício via request.jwt.claims):
```
totals: {"sold_cents":2500,"commission_cents":375,"stripe_fee_cents":63,
         "net_cents":2062,"last_payout_at":"2026-08-06T08:00:35...","adjustment_cents":0}
connect_enabled: false
```
Taxa 63c veio da função única: ROUND(2500×0.015)+25. Líquido 20,62 € ✅.

**c) Função única de taxa:** `stripe_connect_fee_cents(10000,'processing')=175` ·
`(10000,'payout')=50` ✅.

**d) Fail-closed dos endpoints deployados:**
```
POST /functions/v1/stripe-connect-webhook (sem assinatura) → 400
  "Missing stripe-signature or connect webhook secret"
POST /functions/v1/stripe-connect-onboard (sem JWT) → 401
```

**e) Limpeza da prova:** linhas DEMO, cleaner DEMO e user auth DEMO apagados
(contagens 0/0/0); restam só as 5 linhas reais do backfill.

**f) flutter analyze:** `flutter analyze lib` → exit 0, **0 erros** (226 infos/
warnings pré-existentes no repo). Ficheiros novos:
`flutter analyze lib/screens/connect lib/screens/admin/admin_connect_payments_screen.dart`
→ **"No issues found!"**.

**g) Bug apanhado pela prova real:** `v_found || 'texto'` em plpgsql é ambíguo
(malformed array literal). Corrigido para `array_append` na BD e no ficheiro da
migration ANTES do commit.

## 2-bis. ADENDA (mesmo dia, após o Danilo dar o signing secret) — E2E REAL ✅

O Danilo passou o `whsec_...` do webhook Connect. O `npx supabase` não tem binário
win32-x64 (erro "No matching Supabase CLI binary package found"), mas existe
`C:\supabase\supabase.exe` já autenticado → usei esse.

**Secret gravado e confirmado:**
```
supabase secrets list | grep -i connect
STRIPE_CONNECT_WEBHOOK_SECRET | 05a93b34de45b29881d5229c5c5ee5bf88109b082113dfe9dcf20072e447b19f
```

**E2E do webhook por HTTP real** (evento assinado com HMAC-SHA256 do próprio
secret, como a Stripe faz — `t=<ts>,v1=<hmac>`):
```
1) assinatura VÁLIDA   → {"received":true}                  HTTP 200
2) MESMO evento repetido → {"received":true,"duplicate":true} HTTP 200  ← idempotência
3) assinatura FALSA     → "Webhook signature error: No signatures found
                           matching the expected signature for payload"  HTTP 400
```

**E2E a alterar mesmo a base de dados** (cleaner fictício com
`stripe_account_id='acct_PROVA_E2E_20260806'`, 2 eventos `account.updated`
assinados enviados por HTTP):
```
antes:  {"status":"pending","payouts":false,"onboarded_at":null}
evento A (currently_due com 2 itens, payouts=false) → HTTP 200
evento B (currently_due vazio, payouts=true)        → HTTP 200
depois: {"status":"enabled","charges":true,"payouts":true,"due":[],
         "onboarded_at":"2026-08-06T13:42:43.597577+00:00"}
```
Cadeia inteira provada: assinatura → `stripe_connect_events` → RPC espelho →
linha atualizada → `stripe_onboarded_at` carimbado sozinho.

**Connect já está ATIVO na conta Stripe:** `GET /v1/accounts` devolveu
`{"object":"list","data":[],"has_more":false}` — lista vazia em vez de erro
"only Connect platforms can…", ou seja o passo 1 do guia já está feito, com 0
contas ligadas até agora.

**Limpeza:** cleaner demo, user auth demo e os 3 eventos de prova apagados
(contagens 0/0/0; `stripe_connect_events` vazia; ficam as 5 linhas reais do
backfill).

**Estado atualizado das pendências:** só falta um parceiro real passar pelo
onboarding. Os passos 1–3 do guia estão satisfeitos.

## 3. O que NÃO foi possível (e porquê)

1. ~~**Conta Connect real em modo TESTE na Stripe**~~ — **RESOLVIDO na adenda
   §2-bis**: com o secret gravado, o webhook foi provado ponta-a-ponta por HTTP
   real (assinatura válida/falsa/repetida + linha da BD a mudar para `enabled`).
   Falta apenas um **parceiro real** percorrer o onboarding — isso é do Danilo,
   presencialmente (secção 4 do guia).
   Nota: `STRIPE_TEST_SECRET_KEY` continua por criar; enquanto não existir, o
   modo teste (`BORA_STRIPE_MODE=test`) não funciona — o sistema corre em live.
2. **Screenshot do ecrã de extrato** — `adb devices` vazio (telemóvel não está
   ligado por USB) e este PC (4 GB RAM) não compila o app localmente. O ecrã
   compila limpo (analyze) e a RPC que o alimenta está provada em 2b.

## 4. ⚠️ Dinheiro — o que fica à espera do teu "vai"
Nada foi alterado em valores: `stripe_connect_enabled=false`,
`stripe_fee_bearer="partner"`, taxas intactas. O painel novo permite editá-los,
mas **só tu** (JWT admin) consegues. Não há nenhuma alteração financeira
pendente de aplicar nesta fase — a travagem seguinte é a Fase 2.

## 5. Rollback (se precisares de reverter tudo)
```sql
DROP FUNCTION IF EXISTS public.get_my_connect_status(text);
DROP FUNCTION IF EXISTS public.admin_list_connect_accounts();
DROP FUNCTION IF EXISTS public.get_statement(timestamptz, timestamptz);
DROP FUNCTION IF EXISTS public.apply_stripe_account_update(text, boolean, boolean, jsonb, text);
DROP FUNCTION IF EXISTS public.stripe_connect_fee_cents(integer, text);
DROP POLICY IF EXISTS statement_owner_select ON public.partner_statement_lines;
DROP FUNCTION IF EXISTS public.statement_owner_matches(text, text);
DROP TABLE IF EXISTS public.partner_statement_lines;
DROP TABLE IF EXISTS public.stripe_connect_events;
-- Edge Functions: apagar stripe-connect-onboard / -webhook / -admin no dashboard.
-- (A Trava bloqueia DROPs por agente — rollback é ato humano, como deve ser.)
```

## 6. Notas fora do scope
- A Trava (`protege-banco.sh`) bloqueou o primeiro apply por causa de um
  `DROP POLICY IF EXISTS` cosmético — removi o DROP (a tabela era nova). A Trava
  funcionou como desenhada; nada a corrigir.
- `admin_update_setting` já existia — reutilizada (nenhuma RPC nova de settings).

## 7. Fase 2 (próximo prompt — NÃO feito de propósito)
- Transferências automáticas (`stripe.transfers.create`) no fecho semanal,
  gated por `stripe_connect_enabled` + conta `enabled`.
- Linhas de extrato geradas automaticamente por pedido/marcação entregue
  (hoje só o backfill dos acertos + o que a Fase 2 escrever).
- Rateio real da taxa de payout na linha do acerto.
- Página `/connect/return|refresh` no web app com mensagem bonita de regresso.
- Reconciliação payout ↔ linhas (marcar settlement_id nos payouts Stripe).

## 8. Passos humanos — estado final
1. ✅ Connect ativado no dashboard (confirmado: `/v1/accounts` responde).
2. ✅ Webhook criado + `STRIPE_CONNECT_WEBHOOK_SECRET` gravado e **provado a
   funcionar** (§2-bis).
3. ⬜ **Único passo que falta:** cadastrar um parceiro real (ex.: Gilberto,
   Ouro e Prata) — secção 4 do guia. O estado dele muda sozinho no app e no
   painel quando a Stripe verificar.
4. (Opcional) `STRIPE_TEST_SECRET_KEY` se quiseres um ambiente de testes
   separado; sem ela tudo corre em live.

⚠️ O `whsec_` do webhook passou pelo chat desta sessão. Se quiseres ser
rigoroso, dá **"Roll secret"** no endpoint do dashboard da Stripe e regrava —
leva 1 minuto e eu volto a provar.
