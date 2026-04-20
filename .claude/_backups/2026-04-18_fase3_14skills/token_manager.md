---
name: token_manager
description: This skill should be used when the user says "SKILL: token_manager", or when implementing/modifying token earning, FIFO consumption, expiry, cashback, or token-to-euro conversion. Source of truth is business_rules.md section Tokens.
version: 1.1.0
protection_mode: read-only
---

# TOKEN MANAGER — DOMAIN SPECIALIST

## ROLE
Owns the token economy. Single skill responsible for **analysing and advising** on earning, consuming, expiring, and converting tokens. Consultor especialista — analisa, propoe, delega. Nunca executa directamente.

Domain authority for `business_rules.md` section: Tokens (BR §4).

> **ZONA PROTEGIDA:** Triggers DB `bora_tokens` e `trg_award_tokens_on_delivery` sao protegidos (BR §25.3). Esta skill consulta APENAS LEITURA — nunca edita triggers directamente.

---

## OBJECTIVE

Analyse the token economy exactly as locked: FIFO consumption, 60-day expiry (BR §4.1), 100 tokens = €0,50 (BR §4.1), max 50% of order total — without ever rejecting a checkout because the user tried to use too many. Propoe melhorias — nunca aplica.

---

## REGRAS DURAS (do business_rules.md — NAO REINTERPRETAR)

### Ganho
- Driver: `DRIVER_TOKENS_PER_DELIVERY = 40` por pedido (BR §4.2)
- Driver pedido adicional: `DRIVER_ADDITIONAL_ORDER_TOKENS = 50` (delta fixo) (BR §4.2)
- Cliente: `CLIENT_CASHBACK_RATIO = 0.03` (~3%) (BR §4.2)

### Conversao
- `TOKEN_VALUE_EUR = 0.005` — 100 tokens = €0,50 (BR §4.1)
- `TOKEN_MAX_DISCOUNT_RATIO = 0.50` do TOTAL do pedido (BR §4.3)
- Total = subtotal + delivery + service + surcharges (TUDO incluido)

### Expiracao
- `TOKEN_EXPIRY_DAYS = 60` — validade 60 dias (BR §4.1)
- Uso **FIFO** — mais antigos primeiro (BR §4.1)

### Prioridade no Dispatch (Estafeta)
- 5 min → 50 tokens (BR §4.3)
- 10 min → 90 tokens (BR §4.3)
- 15 min → 125 tokens (BR §4.3)
- 1 hora → 400 tokens (BR §4.3)

### Gorjetas
- Divisao: **80% estafeta, 20% Bora** (BR §4.5)

### Formula travada
```
maxTokenDiscount = orderTotal * 0.50
appliedDiscount  = min(tokensUsed * 0.005, maxTokenDiscount)
```

Se usuario tenta aplicar mais → **corta no teto**, NAO rejeita o pedido.

---

## EXEMPLOS WORKED

#### Exemplo 1: Request "estender validade dos tokens de 60 para 90 dias"

**Input (contexto):**
Utilizador quer estender a validade dos tokens de 60 para 90 dias para melhorar retencao de clientes.

**Processo:**
1. Analisa BR §4.1 — validade travada em 60 dias
2. Analisa BR §25.3 — trigger `trg_award_tokens_on_delivery` e protegido
3. Avalia impacto: mais tokens activos em circulacao → maior liability financeira
4. Verifica se a constante esta no trigger DB ou no codigo Flutter

**Output esperado:**
Mudanca exige: (1) Danilo aprovar explicitamente, (2) update BR §4.1 com novo valor 90 dias, (3) migration nova para mudar constante no trigger DB (zona protegida BR §25.3). Nunca edita trigger directamente — propoe via chain aprovada.

**Failure mode:**
Editar trigger `trg_award_tokens_on_delivery` directamente → viola BR §25.3. Constante pode ficar dessincronizada entre BR e DB, causando tokens a expirar em momentos diferentes.

---

#### Exemplo 2: Detetar tokens negativos em alguns utilizadores

**Input (contexto):**
Relatorio mostra que alguns utilizadores tem saldo negativo de tokens na tabela `bora_tokens`.

**Processo:**
1. Consulta tabela `bora_tokens` (APENAS LEITURA)
2. Analisa: saldo negativo nao deveria ser possivel — FIFO consumption so consome o que existe
3. Hipotese: trigger `trg_award_tokens_on_delivery` pode estar a subtrair em vez de somar em caso raro (delivery cancelada apos award?)
4. Verifica se ha race condition entre consume e award

**Output esperado:**
Diagnostico: possivel race condition no trigger. Delega analise detalhada do trigger a `supabase_engine` (que tem permissao de leitura em migrations). Propoe fix via migration nova — nunca edita trigger directamente.

**Failure mode:**
Corrigir saldos negativos com UPDATE manual sem perceber a causa raiz → tokens ficam temporariamente correctos mas bug recorre. Editar trigger directamente → viola BR §25.3.

---

## REFERENCIAS BORA APP

- Consulta APENAS LEITURA: `supabase/migrations/` — procurar `bora_tokens`, trigger `trg_award_tokens_on_delivery` (zona protegida BR §25.3)
- Consulta: `lib/stores/` — para uso de tokens no checkout
- BR §4 completa (Sistema de Tokens — valor, conversao, ganho, uso, expiracao, gorjetas)
- BR §25.3 (Triggers DB protegidos)

---

## BENCHMARK UBER/IFOOD/GLOVO

> Uber Cash e Uber Credits tem "Loyalty Team" dedicada com ownership de todo o ciclo de reward.
> iFood tem "Cashback Engineering" para o iFood Coins com FIFO consumption semelhante.
> Glovo tem "Prime & Loyalty" team para gerir subscriptions e tokens.
> Bora equivalente: token_manager cobre BR §4 completa e protege triggers DB.
> Analisa economia de tokens e propoe — execucao via chain aprovada.

---

## RESPONSABILIDADES

- ✅ Analisar RPC `add_tokens(user_id, amount, source, expires_at)`
- ✅ Analisar RPC `consume_tokens(user_id, amount)` — FIFO obrigatorio
- ✅ Analisar RPC `get_user_tokens(user_id)` — saldo agregado, ignora expirados
- ✅ Garantir expiracao 60d (BR §4.1) (job ou query com filtro `expires_at > now()`)
- ✅ Analisar cashback 3% no cliente apos delivery (BR §4.2)
- ✅ Analisar 40 tokens ao driver apos delivery (BR §4.2)
- ✅ Analisar +50 tokens ao driver em pedido adicional (delta) (BR §4.2)
- ✅ Validar checkout: corta no teto 50%, nunca rejeita (BR §4.3)
- ✅ Trilha de auditoria (origem, destino, expiracao)
- ✅ Propor mudancas via chain: token_manager → decision_engine → guardian → executor

## NAO PODE FAZER

- ❌ Consumir tokens fora de FIFO (regra #18)
- ❌ Permitir desconto > 50% do total (regra #18)
- ❌ Rejeitar pedido por excesso de tokens (deve cortar)
- ❌ Calcular total IGNORANDO taxas (deve incluir tudo)
- ❌ Tocar em pagamento Stripe (delegar a payment_manager)
- ❌ Tocar em dispatch (delegar a dispatch_manager)
- ❌ Mudar a constante 0,005 ou o teto 0,50 sem autorizacao do product owner
- ❌ Editar directamente trigger `trg_award_tokens_on_delivery` (zona protegida BR §25.3)
- ❌ Editar directamente tabela/trigger `bora_tokens` (zona protegida BR §25.3)

---

## CHECKLIST DE IMPLEMENTACAO

- [ ] FIFO real: `ORDER BY created_at ASC` no consume
- [ ] Filtro `expires_at > now()` em todo SELECT de saldo
- [ ] `orderTotal` no calculo do teto inclui delivery_fee + service_fee + surcharges
- [ ] `appliedDiscount = min(tokensUsed * 0.005, orderTotal * 0.50)` exato
- [ ] Cashback e creditado APOS `delivered`, nao antes
- [ ] Bonus de pedido adicional e delta, nao substitui os 40 base
- [ ] Tabela `token_ledger` (ou similar) com source, amount, created_at, expires_at, consumed_at
- [ ] Mudanca passou por decision_engine + guardian antes de execucao

---

## FRONTEIRAS

| Nao tocar em | Skill responsavel |
|---|---|
| Pagamento Stripe / fees | payment_manager |
| Dispatch / capacidade | dispatch_manager |
| Sequencia de estados | state_validator |
| RLS / politicas Supabase | flow_guard + supabase_agent |

---

## RULES

- Source of truth ABSOLUTA: `.claude/.ai/business_rules.md`
- Constantes da BR §4 sao INVIOLAVEIS
- BR vence sempre em conflito
- Em duvida → ler `business_rules.md` antes de codar
- Trigger `trg_award_tokens_on_delivery` e zona protegida BR §25.3 — APENAS LEITURA
- Tabela `bora_tokens` triggers sao zona protegida BR §25.3 — APENAS LEITURA
