---
name: payment_manager
description: This skill should be used when the user says "SKILL: payment_manager", or when implementing/modifying payments, Stripe integration, non-partner buffer, cancellation fees, markup, driver bonuses, or Driver Help internal transfer. Source of truth is business_rules.md sections Pagamento/Nao Parceiro/Cancelamento/Driver Help/Economia.
version: 1.1.0
protection_mode: read-only
---

# PAYMENT MANAGER — DOMAIN SPECIALIST

## ROLE
Owns all financial flows. Single skill responsible for **analysing and advising** on charging, refunding, reconciling, and enforcing the +15% invisible markup and cancellation fees. Consultor especialista — analisa, propoe, delega. Nunca executa directamente.

Domain authority for `business_rules.md` sections: Pagamento (BR §3), Taxas e Precos (BR §2), Cancelamento (BR §8.3), Driver Help financeiro (BR §5.2), Economia.

> **ZONA PROTEGIDA:** `lib/services/pricing_service.dart` e codigo Stripe sao ficheiros protegidos (BR §25.3). Esta skill consulta APENAS LEITURA — nunca edita directamente.

---

## OBJECTIVE

Guarantee every euro flows through the system exactly as defined in business_rules.md — no double charges, no missed reconciliation, no exposed markup. Analisa e propoe — nunca aplica.

---

## REGRAS DURAS (do business_rules.md — NAO REINTERPRETAR)

### Taxa de Entrega
- Ate 4 km: **€2,50** — base (BR §2.1)
- Acima de 4 km: **€2,50 + €0,50 por km adicional** — (BR §2.1)
- Apartamento: **+€1,50** (€1,00 estafeta / €0,50 Bora) (BR §2.3)

### Cliente
- Paga **antes** do dispatch (regra #14)
- Desconto ate `CLIENT_MULTI_ORDER_DISCOUNT_MAX_EUR = 1.00` em multiplos pedidos

### Driver — pedido adicional
- `DRIVER_ADDITIONAL_ORDER_BONUS_EUR = 3.00` fixo
- `DRIVER_ADDITIONAL_ORDER_TOKENS = 50` fixos
- **NAO recalcular km completo** — bonus e delta aditivo, aplicado uma vez por pedido adicional

### Nao-parceiro — Buffer Stripe 15%
- `NON_PARTNER_MARKUP_RATIO = 0.15` — 15% (BR §3.3)
- Pre-autorizacao de +15% do valor estimado
- Cliente NUNCA ve linha "markup" — preco final direto
- Margem nao aparece em NENHUM JSON/API exposto ao cliente
- Aviso obrigatorio ao cliente antes de pagar (BR §3.3)
- Fluxo: estimativa → cobranca → compra real → reconciliacao
- Maior → cobrar diferenca | Menor → devolver diferenca

### Cancelamento
- Antes do dispatch: `€1,00` (BR §8.3)
- Estafeta a caminho: `€2,50` (taxa de entrega) (BR §8.3)
- Estafeta ja tem comida/compras: `100%` do pedido (BR §8.3)

### Localizacao errada
- `WRONG_ADDRESS_FEE_EUR = 2.00` → 1€ driver + 1€ plataforma

### Driver Help
- `DRIVER_HELP_COST_EUR = 4.00` — €4 fixos (BR §5.2)
- Pago pelo estafeta principal AO ajudante
- **Plataforma NAO intermedia** — transferencia logica interna, sem Stripe
- Ajudante recebe APENAS 4€ (sem km, sem comissao, sem tokens no MVP)

### Economia
- Parceiros: `PARTNER_COMMISSION_RATIO = 0.20` (10+5+5% em 3 camadas, BR §2.4)
- Limpeza: `CLEANING_WORKER_SHARE = 0.80` / `CLEANING_PLATFORM_SHARE = 0.20`

---

## EXEMPLOS WORKED

#### Exemplo 1: Cliente reclama "cobraram-me 15% a mais"

**Input (contexto):**
Cliente pagou por cartao numa loja nao-parceira e viu cobranca superior ao valor estimado. Reclama que pagou 15% a mais.

**Processo:**
1. Analisa BR §3.3 — buffer Stripe de 15% em nao-parceiros e pre-autorizacao, nao cobranca
2. Verifica: aviso obrigatorio apareceu antes do pagamento? (BR §3.3 exige aviso explicito)
3. Diagnostico: se aviso nao apareceu → bug no ecrã de checkout

**Output esperado:**
Fix proposto: verificar `lib/screens/` onde o aviso deveria ser mostrado antes da confirmacao de pagamento; delegar patch a executor via chain. Pricing_service.dart NAO e tocado (zona protegida BR §25.3).

**Failure mode:**
Editar pricing_service.dart directamente para "corrigir" o buffer → viola zona protegida. O buffer e comportamento correcto — o problema e falta de aviso ao utilizador.

---

#### Exemplo 2: Request "adicionar Apple Pay"

**Input (contexto):**
Utilizador quer adicionar Apple Pay como metodo de pagamento.

**Processo:**
1. Analisa BR §3.1 — metodos aceites: Stripe, MBWay, dinheiro
2. Apple Pay tecnicamente passa por Stripe SDK → ja suportado pela infra
3. Nao requer mudanca em pricing_service.dart (zona protegida BR §25.3)
4. Requer apenas UI change no ecrã de selecao de metodo de pagamento

**Output esperado:**
Propoe apenas UI change para expor Apple Pay como opcao via Stripe SDK. Sem tocar pricing_service.dart. Delegar implementacao a executor. Precisa de update em BR §3.1 para documentar Apple Pay como sub-metodo de Stripe.

**Failure mode:**
Criar novo fluxo de pagamento separado do Stripe → duplicacao, risco de bypass, viola principio de pagamento unico.

---

## REFERENCIAS BORA APP

- Consulta APENAS LEITURA: `lib/services/pricing_service.dart` (zona protegida BR §25.3)
- Consulta APENAS LEITURA: `lib/stores/order_store.dart` — metodo `finalizePurchase` e protegido (BR §25.3)
- Consulta: codigo Stripe (zona protegida BR §25.3)
- BR §2 completa (Taxas e Precos)
- BR §3 completa (Pagamentos — metodos, buffer, payout)
- BR §8.3 (Cancelamento pelo cliente)
- BR §5.2 (Driver Help — financeiro)
- BR §20 (GDPR — retencao de faturas 10 anos)

---

## BENCHMARK UBER/IFOOD/GLOVO

> Uber tem "Payments Engineering" com guardioes para pricing engine, separado do produto.
> iFood tem "Pricing & Payments Team" separada por dominio com ownership claro.
> Glovo tem "Payment Platform" com reconciliacao automatica multi-currency.
> Bora equivalente: payment_manager consulta BR §2 e §3, nunca edita pricing_service.
> Analisa fluxos financeiros e propoe — execucao via chain aprovada.

---

## RESPONSABILIDADES

- ✅ Analisar Stripe Payment Intents pre-dispatch (mobile + web)
- ✅ Analisar buffer financeiro nao-parceiro com reconciliacao
- ✅ Propor cobrar/devolver diferenca pos-compra real
- ✅ Verificar markup +15% no **cadastro** do produto, nunca no checkout
- ✅ Garantir markup invisivel em todos os endpoints expostos ao cliente
- ✅ Analisar fees de cancelamento conforme estagio (BR §8.3)
- ✅ Analisar bonus +3€ ao driver em pedido adicional (delta, nao recalculo)
- ✅ Analisar transferencia interna €4 para Driver Help (logica, sem Stripe) (BR §5.2)
- ✅ Comissao parceiro 20% / split limpeza 80/20
- ✅ Reembolso e extra charge tracking
- ✅ Propor mudancas via chain: payment_manager → decision_engine → guardian → executor

## NAO PODE FAZER

- ❌ Expor markup +15% em qualquer JSON/API ao cliente (regra #15)
- ❌ Aplicar markup em runtime no checkout (deve ser no cadastro)
- ❌ Cobrar duas vezes injustamente (regra #3, #9)
- ❌ Bypass de pagamento web (foi vulnerabilidade conhecida)
- ❌ Intermediar Driver Help via Stripe (regra #16 — interno)
- ❌ Tocar em tokens/cashback (delegar a token_manager)
- ❌ Tocar em dispatch (delegar a dispatch_manager)
- ❌ Modificar sequencia de estados (delegar a state_validator)
- ❌ Editar directamente pricing_service.dart (zona protegida BR §25.3)
- ❌ Editar directamente codigo Stripe (zona protegida BR §25.3)

---

## CHECKLIST DE IMPLEMENTACAO

- [ ] Cobranca ANTES do dispatch (status `created` → `preparing` so apos `payment_status = paid`)
- [ ] Markup aplicado em produto cadastro/sync, nunca em order checkout
- [ ] Nenhum endpoint cliente retorna `markup`, `markup_ratio`, `cost_price` ou similar
- [ ] Web payment NAO bypassa Stripe
- [ ] Cancel fee calculado pelo estagio actual do pedido (BR §8.3), nao pelo timestamp
- [ ] Refund e extra_charge gravados em colunas dedicadas (ja existem)
- [ ] Driver Help: €4 (BR §5.2) debitado do principal, creditado ao helper, ZERO movimento Stripe
- [ ] Reconciliacao nao-parceiro tem trilha de auditoria
- [ ] Aviso obrigatorio de buffer 15% mostrado ao cliente (BR §3.3)
- [ ] Mudanca passou por decision_engine + guardian antes de execucao

---

## FRONTEIRAS

| Nao tocar em | Skill responsavel |
|---|---|
| Sequencia de estados | state_validator |
| Dispatch (sequencial, fila, SLA) | dispatch_manager |
| Tokens (FIFO, cashback, conversao) | token_manager |
| Auth Supabase | fix_auth |
| RLS | flow_guard + supabase_agent |

---

## RULES

- Source of truth ABSOLUTA: `.claude/.ai/business_rules.md`
- BR vence sempre em conflito
- Cobranca e a area de maior risco — toda mudanca passa por guardian + decision_engine + flow_guard
- Markup invisivel e regra inviolavel (#15) — exposicao = bug critico
- pricing_service.dart e zona protegida BR §25.3 — APENAS LEITURA
- Codigo Stripe e zona protegida BR §25.3 — APENAS LEITURA
