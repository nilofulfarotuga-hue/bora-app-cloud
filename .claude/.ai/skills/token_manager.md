---
name: token_manager
description: This skill should be used when the user says "SKILL: token_manager", or when implementing/modifying token earning, FIFO consumption, expiry, cashback, or token-to-euro conversion. Source of truth is business_rules.md section Tokens.
version: 1.0.0
---

# TOKEN MANAGER — DOMAIN SPECIALIST

## ROLE
Owns the token economy. Single skill responsible for earning, consuming, expiring, and converting tokens.

Domain authority for `business_rules.md` section: Tokens.

---

## OBJECTIVE

Implement the token economy exactly as locked: FIFO consumption, 60-day expiry, 100 tokens = 0,50€, max 50% of order total — without ever rejecting a checkout because the user tried to use too many.

---

## REGRAS DURAS (do business_rules.md — NÃO REINTERPRETAR)

### Ganho
- Driver: `DRIVER_TOKENS_PER_DELIVERY = 40` por pedido
- Driver pedido adicional: `DRIVER_ADDITIONAL_ORDER_TOKENS = 50` (delta fixo)
- Cliente: `CLIENT_CASHBACK_RATIO = 0.03` (~3%)

### Conversão
- `TOKEN_VALUE_EUR = 0.005` (100 tokens = 0,50€)
- `TOKEN_MAX_DISCOUNT_RATIO = 0.50` do TOTAL do pedido
- Total = subtotal + delivery + service + surcharges (TUDO incluído)

### Expiração
- `TOKEN_EXPIRY_DAYS = 60`
- Uso **FIFO** — mais antigos primeiro

### Fórmula travada
```
maxTokenDiscount = orderTotal * 0.50
appliedDiscount  = min(tokensUsed * 0.005, maxTokenDiscount)
```

Se usuário tenta aplicar mais → **corta no teto**, NÃO rejeita o pedido.

---

## RESPONSABILIDADES

- ✅ RPC `add_tokens(user_id, amount, source, expires_at)`
- ✅ RPC `consume_tokens(user_id, amount)` — FIFO obrigatório
- ✅ RPC `get_user_tokens(user_id)` — saldo agregado, ignora expirados
- ✅ Garantir expiração 60d (job ou query com filtro `expires_at > now()`)
- ✅ Calcular cashback 3% no cliente após delivery
- ✅ Adicionar 40 tokens ao driver após delivery
- ✅ Adicionar +50 tokens ao driver em pedido adicional (delta)
- ✅ Validar checkout: corta no teto 50%, nunca rejeita
- ✅ Trilha de auditoria (origem, destino, expiração)

## NÃO PODE FAZER

- ❌ Consumir tokens fora de FIFO (regra #18)
- ❌ Permitir desconto > 50% do total (regra #18)
- ❌ Rejeitar pedido por excesso de tokens (deve cortar)
- ❌ Calcular total IGNORANDO taxas (deve incluir tudo)
- ❌ Tocar em pagamento Stripe (delegar a payment_manager)
- ❌ Tocar em dispatch (delegar a dispatch_manager)
- ❌ Mudar a constante 0,005 ou o teto 0,50 sem autorização do product owner

---

## CHECKLIST DE IMPLEMENTAÇÃO

- [ ] FIFO real: `ORDER BY created_at ASC` no consume
- [ ] Filtro `expires_at > now()` em todo SELECT de saldo
- [ ] `orderTotal` no cálculo do teto inclui delivery_fee + service_fee + surcharges
- [ ] `appliedDiscount = min(tokensUsed * 0.005, orderTotal * 0.50)` exato
- [ ] Cashback é creditado APÓS `delivered`, não antes
- [ ] Bônus de pedido adicional é delta, não substitui os 40 base
- [ ] Tabela `token_ledger` (ou similar) com source, amount, created_at, expires_at, consumed_at

---

## FRONTEIRAS

| Não tocar em | Skill responsável |
|---|---|
| Pagamento Stripe / fees | payment_manager |
| Dispatch / capacidade | dispatch_manager |
| Sequência de estados | state_validator |
| RLS / políticas Supabase | flow_guard + supabase_agent |

---

## RULES

- Source of truth ABSOLUTA: `.claude/.ai/business_rules.md`
- Constantes da seção 📐 são INVIOLÁVEIS
- BR vence sempre em conflito
- Em dúvida → ler `business_rules.md` antes de codar
