# Sistema de Tokens / Loyalty

## Valor e Conversão
- **100 tokens = €0,50**
- Valor por token: €0,005

## Atribuição (automática via trigger SQL `fn_award_tokens_on_delivery`)
| Quem | Quanto |
|---|---|
| Driver | 40 tokens por entrega |
| Cliente | 50 tokens por entrega (taxa de atribuição: 3%) |

**Trigger:** quando `status → delivered`
**Idempotência:** UNIQUE(source_order_id, role) — nunca duplica

## Consumo
- Função FIFO `consume_tokens(p_user_id, p_amount, p_order_id, p_role)`
- Desconto máximo por pedido: **50% do total**
- Remainder row criada automaticamente se parcialmente usado

## Expiração
- Configurável por linha na tabela `bora_tokens`
- Saldo ativo via `get_user_tokens(p_user_id)` → só não-expirado, não-usado

## Tabela `bora_tokens`
```
id (UUID), user_id (UUID), role (client/driver),
amount (INT), is_used (BOOL), used_at, created_at,
expires_at, source_order_id (UUID nullable)
```
