# Cancelamento estilo Uber — Janela de graça (grace period)

> Data: 2026-06-28 · Autor: sessão autónoma (Hermes/Opus) · Estado: **PROPOSTA — aguarda aprovação 1-clique do Danilo**
> ⚠️ LISTA VERMELHA (mexe em dinheiro). Mecanismo desenhado e pronto; o FLIP em produção (deploy EF + setting) fica para o Danilo.

---

## 1. Estado REAL hoje (verificado via MCP em produção)

Ao contrário do que se assumia, **o cancelamento automático com taxa por estado JÁ funciona**:

- O cliente cancela direto pela EF `cancel-order-with-choice` (Flutter `OrderStore.clientCancelOrder` → `WalletService.cancelWithChoice`). **Não passa por fila admin.**
- A EF calcula a taxa por *tier* (estado) e processa reembolso/split sozinha:
  - `before_dispatch` (created/preparing/callingDriver) → `cancel_fee_before_dispatch_cents` = **100** (€1,00)
  - `after_accept` (driverAccepted) → `cancel_fee_after_accept_cents` = **250** (€2,50)
  - `after_pickup` (pickedUp/onTheWay) → `cancel_fee_after_pickup_ratio` = **1.0** (100% retido, sem reembolso)
- Reembolso wallet faz split **80% saldo livre / 20% tokens** (`wallet_split_free_pct`=0.8), respeitando `wallet_cancel_hard_floor_cents`=-4000.
- CASH/MBWay-não-pago → taxa vira **dívida na wallet** (`wallet_debit_cancel_fee`).
- A fila `cancellation_requests` + aprovação admin existe e **fica reservada para disputas e para pedidos de cancelamento de estafeta/parceiro** — exatamente o desenho-alvo Uber.

**Conclusão:** falta UMA peça para igualar o Uber/Glovo → a **janela de graça** (cancelar grátis logo após criar) + o **contador visível**. Tudo o resto já está.

---

## 2. Gap

1. Não existe `cancel_grace_seconds`. Hoje, cancelar 5s depois de criar já cobra €1,00.
2. O cliente não vê contador ("Podes cancelar grátis durante 00:59").

---

## 3. Desenho (aditivo, com kill-switch pelo próprio valor)

### 3.1 Setting novo (platform_settings)
```sql
-- NÃO APLICAR sem aprovação. Default 0 = comportamento IDÊNTICO ao de hoje.
INSERT INTO public.platform_settings (key, value, description, category) VALUES
  ('cancel_grace_seconds', '0',
   'Janela (segundos) após criar o pedido em que o cliente cancela GRÁTIS (reembolso total, sem taxa). 0 = desligado. Sugerido: 120.',
   'cancellation')
ON CONFLICT (key) DO NOTHING;
```
> Com `cancel_grace_seconds=0` a EF comporta-se exatamente como hoje. O "ligar" = mudar para 120 (ou o que o Danilo decidir). Isto torna o flip **reversível por valor**.

### 3.2 Diff EF `cancel-order-with-choice/index.ts` (cirúrgico)
- Adicionar `created_at` ao `select` da order (linha ~80).
- Ler o setting e aplicar override de taxa = 0 dentro da janela, **apenas** no tier `before_dispatch`:
```ts
// novo helper em _shared/platform_settings.ts:
//   export async function getCancelGraceSeconds(): Promise<number> { ... default 0 ... }
const graceSeconds = await getCancelGraceSeconds();
const createdMs = order.created_at ? Date.parse(order.created_at) : 0;
const withinGrace =
  graceSeconds > 0 && createdMs > 0 && (Date.now() - createdMs) <= graceSeconds * 1000;

let fee = Number(computeCancelFeeEur(t, totalEur, fees).toFixed(2));
if (withinGrace && t === 'before_dispatch') fee = 0; // grace = cancelamento grátis
```
- Resto da EF fica **inalterado** (refundEur = total - fee → reembolso total quando fee=0).
- Devolver `within_grace` no JSON para a UI confirmar.

### 3.3 Diff Flutter (UI — só depois da EF estar live, para não mentir)
- `order_tracking_screen.dart`:
  - Mostrar contador quando `status==created/preparing/callingDriver` e `now-createdAt <= grace`: *"Podes cancelar grátis durante MM:SS"*.
  - No diálogo de cancelar, `_feeLabelForStatus` passa a devolver **"Grátis"** dentro da janela; fora dela mantém €1,00 / €2,50 / 100%.
- `cancel_grace_seconds` lido via `quote`/settings endpoint já existente (ou novo getter).

---

## 4. Matemática ao cêntimo (exemplo: pedido €18,40 pago por cartão; grace=120s)

| Cenário | Estado / timing | Taxa | Reembolso | Split wallet (se wallet) |
|---|---|---|---|---|
| **1. Dentro da janela** | ≤120s, antes de dispatch | **€0,00** | **€18,40** (100%) | €14,72 saldo + €3,68 tokens |
| **2. Fora da janela, pré-aceite** | >120s, created/preparing/callingDriver | **€1,00** | €17,40 | €13,92 + €3,48 tokens |
| **3. Após estafeta aceitar** | driverAccepted | **€2,50** | €15,90 | €12,72 + €3,18 tokens |
| **4. Após pickup** | pickedUp/onTheWay | **100% (€18,40)** | €0,00 | — |

- Cartão → reembolso via Stripe (5–10 dias). Wallet → instantâneo, split 80/20.
- CASH/MBWay-não-pago → a taxa (cenários 2–4) vira dívida na wallet (floor -€40).
- **Único valor que muda com o flip:** Cenário 1 deixa de cobrar €1,00 (passa a €0,00). Impacto = renúncia de €1,00 por cancelamento dentro de 120s. Padrão Uber/Glovo.

---

## 5. Admin (PT-BR)
- `cancel_grace_seconds` deve ser editável no painel (categoria "cancellation"). Como controla dinheiro, segue o padrão das chaves financeiras: edição via fluxo dedicado (`update-platform-setting`) **ou** adicionar prefixo `cancel_` à whitelist do `admin_platform_settings_screen` — **decisão do Danilo**.
- Histórico de cancelamentos: já gravado em `orders` (cancel_reason, cancel_fee, cancelled_at, cancellation_initiator) + `cancellation_requests` para disputas. Ecrã `admin_cancellation_requests_screen.dart` já existe.

---

## 6. Checklist do FLIP (a executar com aprovação do Danilo)
1. [ ] Aplicar migration do setting `cancel_grace_seconds` (valor inicial à escolha; sugiro 120).
2. [ ] Adicionar `getCancelGraceSeconds()` em `_shared/platform_settings.ts`.
3. [ ] Aplicar diff na EF `cancel-order-with-choice` + deploy (`deploy-edge-function --i-know-what-im-doing`).
4. [ ] Aplicar diff Flutter (contador + label "Grátis") e build.
5. [ ] Confirmar `client-cancel-order` e `execute-cancellation` (mesmas 3 settings) — se quiserem grace coerente, replicar o override lá também.
6. [ ] Testar 4 cenários com pagamento cash em staging.

> Nota: `stripe-webhook` v17 ainda tem fee hardcoded (ver descrição do setting `cancel_fee_before_dispatch_cents`). Não afeta o grace, mas convém alinhar numa sessão futura.
