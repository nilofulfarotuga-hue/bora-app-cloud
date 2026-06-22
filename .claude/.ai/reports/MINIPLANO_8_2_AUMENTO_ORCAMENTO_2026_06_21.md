# MINI-PLANO 8.2 — Confirmação do cliente quando o talão passa do orçamento
> 2026-06-21 · errand · **AGUARDA OK DO DANILO/CLAUDE.AI antes de qualquer código**

## Estado atual (confirmado no código)
- `errand_execution_sheet.dart:160-198` `_finalizePurchase()` → RPC **`finalize_errand_purchase`**
  (server) que, segundo o comentário (linha 181), **já dispara `charge-extra` automaticamente se
  o buffer for ultrapassado** — SEM nenhuma confirmação do cliente.
- Buffer = `estimativa × errand_buffer_multiplier` (§55.4, hoje **1.2**). Dentro do buffer, a
  cobrança extra é silenciosa (é para isso que serve o buffer). Acima do buffer, hoje cobra na
  mesma sem perguntar.
- Colunas já existem: `final_total`, `final_purchase_value`, `is_purchase_finalized`,
  `refund_amount`, `payment_buffer_total`.

## Objetivo
Inserir uma **confirmação explícita do cliente** quando o valor real ultrapassar o buffer
autorizado, ANTES de cobrar o extra. Reutilizar `notify-client` (push) + `charge-extra` (já
existe). **NÃO** mexer em `pricing_calculate_errand` nem na matemática de preço.

## Recomendação de timing → **(A) ANTES de comprar (modelo Glovo)** como caminho primário
**Porquê A e não B (depois do talão):**
- Em (B) o dinheiro do cliente já foi gasto; se ele recusar o extra, fica um buraco financeiro
  (estafeta/ Bora a absorver). Em (A) ainda não se comprou → recusa = cancelamento limpo pela
  regra §55.6 ("após aceitar, antes da compra → €2,50").
- O buffer ×1.2 continua a ser folga silenciosa; a confirmação só dispara para excesso **acima**
  do buffer (caso raro), portanto baixa fricção.

### Fluxo A (primário) — estados
1. Estafeta, na loja, prevê que vai passar → toca **"Pedir aumento de orçamento"** no execution
   sheet → indica novo total previsto.
2. App grava pedido de aumento (`errand_budget_requested_cents` + `errand_budget_status='pending'`)
   e chama **`notify-client`** (push).
3. Cliente abre a app → folha de confirmação: "O estafeta precisa de ~€X (orçaste €Y). Autorizas?"
4a. **Autoriza** → buffer autorizado sobe para `requested × 1.2`; `errand_budget_status='approved'`.
    Estafeta compra dentro do novo limite → `finalize_errand_purchase` normal (charge-extra agora
    limitado ao buffer já consentido).
4b. **Recusa** → `errand_budget_status='rejected'` → cancelamento §55.6 (antes da compra = €2,50);
    estafeta recolhe.

### Fluxo B (fallback de segurança)
Se o estafeta comprar sem pedir e o talão exceder o buffer: `finalize_errand_purchase` **bloqueia
o charge-extra**, marca `errand_budget_status='pending_post'`, notifica o cliente; só cobra extra
após consentimento. Recusa pós-compra cai em §55.6 (decisão de quem absorve = **Danilo decide**,
não eu).

## Settings
- `errand_overbudget_confirm_pct` (default = buffer atual, i.e. confirmação quando
  `real > estimativa × 1.2`). Configurável; sem impacto no cálculo base.

## ⚠️ Superfície de servidor (é por isto que 8.2 está gated)
8.2 **exige** mudança server-side numa RPC financeira (`finalize_errand_purchase`) + 1 RPC nova
(`errand_request_budget_increase`/consent) + 2 colunas (`errand_budget_requested_cents`,
`errand_budget_status`). Isto colide com a regra "nada de lógica financeira no servidor" do
prompt principal → precisa de aprovação explícita. **Mínimo possível:** não tocar na matemática;
só (i) gravar consentimento e (ii) condicionar o charge-extra existente a esse consentimento.

## Ficheiros (quando aprovado)
- Migration: 2 colunas em `orders` + RPC consent + ajuste guard no `finalize_errand_purchase`.
- `errand_execution_sheet.dart` (botão "Pedir aumento" + estados).
- Ecrã cliente (folha de confirmação) + handler push.
- Admin: mostrar eventos de aumento no detalhe do pedido.

## Decisões que peço ao Danilo
1. Confirmar timing **(A) antes de comprar** como primário (vs B).
2. Autorizar a mudança mínima no `finalize_errand_purchase` (gating do charge-extra por
   consentimento) — sim/não.
3. Recusa pós-compra (fluxo B): cliente paga tudo (§55.6) ou Bora absorve? (default proposto:
   §55.6 — cliente paga, com flag admin).
