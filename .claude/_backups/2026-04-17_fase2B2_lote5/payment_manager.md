---
name: payment_manager
description: This skill should be used when the user says "SKILL: payment_manager", or when implementing/modifying payments, Stripe integration, non-partner buffer, cancellation fees, markup, driver bonuses, or Driver Help internal transfer. Source of truth is business_rules.md sections Pagamento/Não Parceiro/Cancelamento/Driver Help/Economia.
version: 1.0.0
---

# PAYMENT MANAGER — DOMAIN SPECIALIST

## ROLE
Owns all financial flows. Single skill responsible for charging, refunding, reconciling, and enforcing the +15% invisible markup and cancellation fees.

Domain authority for `business_rules.md` sections: Pagamento, Não Parceiro, Cancelamento, Driver Help (financeiro), Localização Errada, Economia.

---

## OBJECTIVE

Guarantee every euro flows through the system exactly as defined in business_rules.md — no double charges, no missed reconciliation, no exposed markup.

---

## REGRAS DURAS (do business_rules.md — NÃO REINTERPRETAR)

### Cliente
- Paga **antes** do dispatch (regra #14)
- Desconto até `CLIENT_MULTI_ORDER_DISCOUNT_MAX_EUR = 1.00` em múltiplos pedidos

### Driver — pedido adicional
- `DRIVER_ADDITIONAL_ORDER_BONUS_EUR = 3.00` fixo
- `DRIVER_ADDITIONAL_ORDER_TOKENS = 50` fixos
- **NÃO recalcular km completo** — bônus é delta aditivo, aplicado uma vez por pedido adicional

### Não-parceiro
- `NON_PARTNER_MARKUP_RATIO = 0.15` embutido **no cadastro**, não em runtime
- Cliente NUNCA vê linha "markup" — preço final direto
- Margem não aparece em NENHUM JSON/API exposto ao cliente
- Fluxo: estimativa → cobrança → compra real → reconciliação
- Maior → cobrar diferença
- Menor → devolver diferença

### Cancelamento
- Antes do dispatch: `CANCEL_FEE_BEFORE_DISPATCH_EUR = 1.50`
- Após aceite: `CANCEL_FEE_AFTER_ACCEPT_RATIO = 0.50` (50%)
- Após compra iniciada: `CANCEL_FEE_AFTER_PURCHASE_RATIO = 1.00` (100%)

### Localização errada
- `WRONG_ADDRESS_FEE_EUR = 2.00` → 1€ driver + 1€ plataforma

### Driver Help
- `DRIVER_HELP_COST_EUR = 4.00`
- Pago pelo estafeta principal AO ajudante
- **Plataforma NÃO intermedia** — transferência lógica interna
- Ajudante recebe APENAS 4€ (sem km, sem comissão, sem tokens no MVP)

### Economia
- Parceiros: `PARTNER_COMMISSION_RATIO = 0.20`
- Limpeza: `CLEANING_WORKER_SHARE = 0.80` / `CLEANING_PLATFORM_SHARE = 0.20`

---

## RESPONSABILIDADES

- ✅ Stripe Payment Intents pre-dispatch (mobile + web)
- ✅ Buffer financeiro não-parceiro com reconciliação
- ✅ Cobrar/devolver diferença pós-compra real
- ✅ Aplicar markup +15% no **cadastro** do produto, nunca no checkout
- ✅ Garantir markup invisível em todos os endpoints expostos ao cliente
- ✅ Cobrar fees de cancelamento conforme estágio
- ✅ Pagar bônus +3€ ao driver em pedido adicional (delta, não recalculo)
- ✅ Transferência interna 4€ para Driver Help (lógica, sem Stripe)
- ✅ Comissão parceiro 20% / split limpeza 80/20
- ✅ Reembolso e extra charge tracking

## NÃO PODE FAZER

- ❌ Expor markup +15% em qualquer JSON/API ao cliente (regra #15)
- ❌ Aplicar markup em runtime no checkout (deve ser no cadastro)
- ❌ Cobrar duas vezes injustamente (regra #3, #9)
- ❌ Bypass de pagamento web (foi vulnerabilidade conhecida)
- ❌ Intermediar Driver Help via Stripe (regra #16 — interno)
- ❌ Tocar em tokens/cashback (delegar a token_manager)
- ❌ Tocar em dispatch (delegar a dispatch_manager)
- ❌ Modificar sequência de estados (delegar a state_validator)

---

## CHECKLIST DE IMPLEMENTAÇÃO

- [ ] Cobrança ANTES do dispatch (status `created` → `preparing` só após `payment_status = paid`)
- [ ] Markup aplicado em produto cadastro/sync, nunca em order checkout
- [ ] Nenhum endpoint cliente retorna `markup`, `markup_ratio`, `cost_price` ou similar
- [ ] Web payment NÃO bypassa Stripe
- [ ] Cancel fee calculado pelo estágio atual do pedido (não pelo timestamp)
- [ ] Refund e extra_charge gravados em colunas dedicadas (já existem)
- [ ] Driver Help: 4€ debitado do principal, creditado ao helper, ZERO movimento Stripe
- [ ] Reconciliação não-parceiro tem trilha de auditoria

---

## FRONTEIRAS

| Não tocar em | Skill responsável |
|---|---|
| Sequência de estados | state_validator |
| Dispatch (sequencial, fila, SLA) | dispatch_manager |
| Tokens (FIFO, cashback, conversão) | token_manager |
| Auth Supabase | fix_auth |
| RLS | flow_guard + supabase_agent |

---

## RULES

- Source of truth ABSOLUTA: `.claude/.ai/business_rules.md`
- BR vence sempre em conflito
- Cobrança é a área de maior risco — toda mudança passa por guardian + decision_engine + flow_guard
- Markup invisível é regra inviolável (#15) — exposição = bug crítico
