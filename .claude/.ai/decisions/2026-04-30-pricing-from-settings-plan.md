# Plano — `pricing_calculate` lê de `platform_settings` (C1)

> **Status:** PLAN-ONLY · NÃO IMPLEMENTAR sem aprovação explícita
> **Risco:** ALTO · toca em ledger financeiro real, Stripe LIVE
> **Branch destino:** `draft/pricing-from-settings` (a criar)
> **Sessão:** 2026-04-30 (auditoria total autónoma)

## Problema

`pricing_calculate(...)` SQL ainda tem constantes hardcoded para todas as taxas
(€2.50 base entrega, €0.50/km, 10% comissão visível, 5% markup oculto, 5%
service fee, €0.30 saco restaurante, €0.10 saco mercado, €0.80 bónus driver,
×1.15 buffer pre-auth, etc.).

A tabela `platform_settings` (26 entradas, criada em migration `20260430110000`)
existe e é editável pelo admin via `admin_update_setting` RPC, **mas nenhum
valor lá guardado afecta cálculos reais**. É efectivamente decoração.

Sem este refactor, qualquer mudança de estratégia comercial (ex: subir
delivery base para €3, baixar comissão visível para 8%) requer migration SQL
+ deploy. Não é dinâmico.

## Pré-requisito (Danilo confirma)

`SELECT key FROM platform_settings ORDER BY key;` deve retornar pelo menos:
- `pricing.delivery_base_eur` = `2.50`
- `pricing.delivery_per_km_eur` = `0.50`
- `pricing.partner_commission_visible_pct` = `0.10`
- `pricing.partner_markup_hidden_pct` = `0.05`
- `pricing.partner_service_fee_pct` = `0.05`
- `pricing.bag_fee_restaurant_eur` = `0.30`
- `pricing.bag_fee_market_eur` = `0.10`
- `pricing.driver_base_eur` = `3.80`
- `pricing.driver_per_km_eur` = `0.20`
- `pricing.driver_bonus_eur` = `0.80`
- `pricing.driver_stack_partner_eur` = `3.00`
- `pricing.payment_buffer_pct` = `1.15`
- `pricing.cash_max_eur` = `40.00`
- `pricing.apartment_surcharge_eur` = `1.50`
- `pricing.apartment_split_driver_eur` = `1.00`

Verificar com: `SELECT key, value FROM platform_settings WHERE key LIKE 'pricing.%' ORDER BY key;`

Se faltar alguma, criar migration `seed_pricing_settings.sql` antes do refactor.

## Estratégia — paralelo + switchover atómico

**NÃO** modificar `pricing_calculate` directamente. Em vez disso:

### Passo 1 — Criar `pricing_calculate_v2` em paralelo

```sql
CREATE OR REPLACE FUNCTION public.pricing_calculate_v2(
  p_service_type text, p_subtotal numeric, p_distance_km numeric,
  p_is_partner_store boolean, p_apartment_delivery boolean,
  p_payment_method text, p_bag_count integer
) RETURNS jsonb LANGUAGE plpgsql STABLE AS $$
DECLARE
  v_settings jsonb;
  v_delivery_base numeric;
  v_delivery_per_km numeric;
  -- ...
BEGIN
  SELECT jsonb_object_agg(key, value) INTO v_settings
  FROM platform_settings WHERE key LIKE 'pricing.%';

  v_delivery_base := (v_settings->>'pricing.delivery_base_eur')::numeric;
  v_delivery_per_km := (v_settings->>'pricing.delivery_per_km_eur')::numeric;
  -- ... etc

  -- mesma lógica de pricing_calculate mas com variáveis
  RETURN jsonb_build_object(...);
END;
$$;
```

### Passo 2 — Smoke testes exaustivos

Para cada cenário em `tests/sql/pricing_smoke.sql` (criar):
- restaurante parceiro 4km €25
- não-parceiro 6km €40
- carryGroceries 3km €15
- sendPackage 8km
- com apartmentDelivery
- cash €40 limite
- bagCount=5 mercado
- stacking partner €3 bónus

Comparar JSON output de `pricing_calculate(...)` vs `pricing_calculate_v2(...)`.
Tolerância: zero diferença em delivery_fee/service_fee/platform_commission/
driver_earnings/customer_total. Se houver, settings têm valor errado.

### Passo 3 — Switchover atómico (UMA migration)

```sql
BEGIN;
-- Renomear original → backup
ALTER FUNCTION pricing_calculate(...) RENAME TO pricing_calculate_legacy_pre_settings;
-- Renomear v2 → canónica
ALTER FUNCTION pricing_calculate_v2(...) RENAME TO pricing_calculate;
COMMIT;
```

Todas as RPCs que chamam `pricing_calculate(...)` (create_order incluído)
continuam a funcionar — assinatura idêntica.

### Rollback

Se algo partir em produção:
```sql
BEGIN;
ALTER FUNCTION pricing_calculate(...) RENAME TO pricing_calculate_v2_broken;
ALTER FUNCTION pricing_calculate_legacy_pre_settings(...) RENAME TO pricing_calculate;
COMMIT;
```

Tempo de rollback: <30s. Garantia: dois nomes diferentes existem; basta swap.

## Critério de aceitação

- 100% dos cenários do smoke test produzem mesmo JSON
- 0 erros em `flutter analyze` no app cliente/driver após deploy
- 24h de observação sem novos `mbway_debug_errors` ou `driver_transactions`
  com totals NULL
- Admin pode mudar `pricing.delivery_base_eur` no `admin_platform_settings_screen`
  e o próximo pedido criado já reflecte o novo valor

## Pendência

Antes de executar:
1. Danilo aprova explicitamente este plano
2. `SELECT * FROM platform_settings WHERE key LIKE 'pricing.%';` confirma 15 chaves
3. Branch `draft/pricing-from-settings` criada do `autonomous-night-2026-04-29`
4. Smoke test SQL escrito + corrido em prod (read-only) antes do refactor
