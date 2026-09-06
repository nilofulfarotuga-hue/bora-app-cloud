# Tech Debt — `app.financial_bypass` GUC pattern

**Data:** 2026-05-01
**Severidade:** Baixa (funciona, é menos auditável)
**Plano:** Refactor pós-launch
**Owner:** Danilo

---

## Contexto

Para fixar BUG 16 (`FINANCIAL_COLUMNS_IMMUTABLE` em `_finalizePurchaseUnchecked`), o trigger `enforce_financial_immutability` foi modificado para aceitar bypass via session GUC `app.financial_bypass`:

```plpgsql
IF auth.role() <> 'service_role'
   AND COALESCE(current_setting('app.financial_bypass', true), 'false') <> 'true'
THEN
  -- enforce immutability
END IF;
```

A RPC `finalize_storeshopping_purchase` (SECURITY DEFINER) faz `PERFORM set_config('app.financial_bypass', 'true', true)` antes do UPDATE.

## Por que funciona em produção

PostgREST abre 1 transação por request. `SET LOCAL` (terceiro arg `true` em `set_config`) só vive dentro dessa transação. Quando a transação termina, o GUC volta a `false`. Logo:
- Cliente Flutter não tem como deixar o GUC "pendurado" entre requests.
- Concurrent requests não vêm o GUC um do outro (cada um na sua tx).

## Por que é tech-debt

- **Menos auditável** que o padrão original `service_role only`. Qualquer RPC SECURITY DEFINER pode setar o GUC; futura revisão de segurança precisa varrer todas as RPCs e validar que só as trusted o setam.
- **Padrão fora-do-comum**. Reviewers externos podem confundir com bypass global.
- **Quebra se um dia migrarmos para drivers a Postgres direto** (não via PostgREST) onde uma sessão pode ter múltiplas transações.

## Refactor proposto pós-launch

Trocar a check do trigger por uma baseada em `current_user`:

```plpgsql
IF auth.role() <> 'service_role'
   AND current_user <> 'postgres'
THEN
  -- enforce immutability
END IF;
```

`current_user` dentro de uma SECURITY DEFINER function vira o owner real da função (que para Supabase migrations é `postgres`). Isto:
- Remove o GUC e todos os `set_config` calls.
- Aproveita o mecanismo nativo de role do Postgres em vez de uma flag custom.
- Mais alinhado com o padrão Supabase recomendado.

Steps:
1. Migration: alterar trigger `enforce_financial_immutability` para usar `current_user` check.
2. Migration: remover `PERFORM set_config('app.financial_bypass', 'true', true)` de TODAS as RPCs que toquem colunas financeiras.
3. Smoke: re-validar `finalize_storeshopping_purchase` + qualquer outra RPC equivalente.

Estimado em 30 min após launch.

## NÃO executar agora

Razão: estamos a 30 dias do launch. O padrão GUC funciona; refactor traz risco zero de receita perdida e pode introduzir bugs. Pós-launch sem stress.

---

## Referências

- Migration que introduziu o GUC bypass: [20260501020000_finalize_storeshopping_purchase_rpc.sql](../../supabase/migrations/20260501020000_finalize_storeshopping_purchase_rpc.sql)
- Migration security fix v3 que mantém o GUC: [20260501030000_finalize_storeshopping_security_fix.sql](../../supabase/migrations/20260501030000_finalize_storeshopping_security_fix.sql)
- Trigger function: `public.enforce_financial_immutability`
