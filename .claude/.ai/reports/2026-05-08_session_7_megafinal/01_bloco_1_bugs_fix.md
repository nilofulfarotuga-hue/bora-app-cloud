# BLOCO 1 — BUGs LOW/MEDIUM closed (Sessão 7-FIX-2 · 2026-05-08)

**Data**: 2026-05-08
**Sessão**: 7-FIX-2 (continuação da 7-FIX de 2026-05-07)
**Modo**: MCP directo via Claude.ai
**BUGs alvo**: 7E-B-001, 7E-B-003, 7E-B-006

---

## Objectivo

Fechar os 3 BUGs LOW/MEDIUM remanescentes do smoke test 7E-B
após a sessão 7-FIX (que já fechou os 3 BUGs HIGH 004/005/007 a
2026-05-07).

---

## BUG-7E-B-001 (LOW) — Cash limit DOCS_VS_CODE mismatch

### Diagnóstico final

A validação MCP em prod confirmou:
```sql
SELECT key, value FROM platform_settings WHERE key = 'max_cash_amount_cents';
-- Resultado: max_cash_amount_cents = 4000 (€40)
```

E o trigger SQL `enforce_cash_payment_limit` lê desta setting.

### Causa raíz

O ficheiro `_shared/business_rules.ts` (código frontend/Edge Fns)
declarava `CASH_MAX_ORDER_VALUE_EUR=30.00` desalinhado com prod
(€40). A documentação `business_rules.md` em §3.2 dizia genericamente
"Máximo €40,00" sem referência explícita à setting nem ao trigger.

### Acção tomada

- **Migration**: nenhuma (sem mudança de comportamento DB).
- **Documentação**: `business_rules.md §3.2` actualizada com:
  - Valor configurado em `platform_settings.max_cash_amount_cents=4000`
  - Nome do trigger: `orders_enforce_cash_limit`

### Estado pós-execução

✅ **CLOSED 2026-05-08.**

### Pendente (não bloqueante)

Alinhar `_shared/business_rules.ts` (€30 → €40) — fora do scope
desta sessão (ZERO código produção em 7 MEGAFINAL). Recomenda-se
sessão dedicada futura tocando código frontend/Edge Fns.

---

## BUG-7E-B-003 (LOW) — `storeShopping` retorna `bag_fee=0` (FALSE POSITIVE)

### Diagnóstico final

Validação MCP em prod:
```sql
SELECT
  id,
  service_type,
  bag_count,
  bag_fee,
  CASE WHEN bag_count > 0 THEN bag_fee::numeric / bag_count
       ELSE NULL
  END AS cents_per_bag,
  created_at
FROM orders
WHERE service_type = 'storeShopping'
  AND created_at > now() - interval '30 days'
  AND bag_count > 0
ORDER BY created_at DESC;
```

Resultado: 4 orders, todos com `cents_per_bag = 10.00` exacto.

### Conclusão

**FALSE POSITIVE.** A função SQL `finalize_storeshopping_purchase`
está correcta e a aplicar `bag_fee = bag_count × 10c` conforme
regra documentada em §2.6.

### Causa do falso positivo

O test T06 `test_t06_storeshopping_bag_fee_zero` valida
`pricing_calculate` (preview pré-checkout), que devolve
`bag_fee=0` para `storeShopping`. Isto **é correcto**: o bag fee
só é calculado pós-finalização (`finalize_storeshopping_purchase`)
quando o estafeta confirma o número real de sacos.

O BUG original assumia que `pricing_calculate` deveria devolver o
bag fee — isso seria errado, pois o número de sacos só é conhecido
no momento da entrega.

### Acção tomada

- **Migration**: nenhuma.
- **Documentação**: `business_rules.md §2.6` ganhou nota explícita
  da validação prod 2026-05-08.
- **`BUGS_FOUND.md`**: BUG-003 marcado como CLOSED com nota
  "FALSE POSITIVE" e explicação técnica.

### Estado pós-execução

✅ **CLOSED 2026-05-08 (FALSE POSITIVE).**

---

## BUG-7E-B-006 (MEDIUM) — Stripe webhook fee mismatch

### Diagnóstico final

Edge Function `stripe-webhook` v17 tem hardcoded:
```typescript
const CANCEL_FEE_BEFORE_DISPATCH_EUR = 1.50;
```

Mas a tabela `business_rules.md §8.3` (texto antigo) dizia €1.00
e `_shared/business_rules.ts` declarava `1.00`. Comentário do
webhook estava desalinhado.

### Decisão

Manter o valor **€1.50** como o oficial. Razão: já está em prod e
a Edge Fn já cobra esse valor; alterar quebra a contabilidade.

### Acção tomada

- **Migration**: `fix_bug_006_stripe_cancel_fee_setting`
  (`20260508084132`).
- **SQL aplicado**:
  ```sql
  INSERT INTO platform_settings (key, value, description)
  VALUES (
    'cancel_fee_before_dispatch_cents',
    '150',
    'Fee aplicado em cancelamentos antes do dispatch (€1.50)'
  )
  ON CONFLICT (key) DO UPDATE
    SET value = EXCLUDED.value,
        description = EXCLUDED.description,
        updated_at = now();
  ```
- **Documentação**: §48.1 do `business_rules.md` agora explicita
  o valor 150c + cita o nome da migration.

### Pendente (não bloqueante)

Edge Function `stripe-webhook` v17 ainda tem o valor **hardcoded**.
Refactor para ler da setting `cancel_fee_before_dispatch_cents` fica
para sessão dedicada futura (5F-β-β). Não bloqueante porque o valor
está alinhado em ambos os sítios.

### Estado pós-execução

✅ **CLOSED 2026-05-08 (com pendente não-bloqueante 5F-β-β).**

---

## Resumo BLOCO 1

| BUG | Severidade | Tipo close | Migration | Pendente |
|---|---|---|---|---|
| 001 | LOW | Doc fix | — | sync `business_rules.ts` |
| 003 | LOW | FALSE POSITIVE | — | — |
| 006 | MEDIUM | Setting + migration | `fix_bug_006_stripe_cancel_fee_setting` | refactor stripe-webhook 5F-β-β |

**Estado final BLOCO 1**: 3/3 BUGs CLOSED. Combinado com 7-FIX
(004/005/007), todos os 6 BUGs do smoke 7E-B estão fechados.
