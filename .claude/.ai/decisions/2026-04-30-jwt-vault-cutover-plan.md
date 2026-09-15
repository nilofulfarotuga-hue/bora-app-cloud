# Plano — JWT vault cutover (C2)

> **Status:** PLAN-READY · branch `draft/01-jwt-vault` existe (vazia)
> **Risco:** ALTO · pode partir dispatch-engine + cron jobs
> **Pré-requisito manual Danilo:** criar secret no vault

## Problema

Quatro ficheiros SQL têm o `SUPABASE_ANON_KEY` JWT hardcoded:
- `supabase/migrations/20260415140000_dispatch_trigger_pgcron.sql`
- `supabase/migrations/20260427000000_dispatch_ttl_auto_reject.sql`
- `supabase/migrations/20260429180000_fix_dispatch_maintenance_types.sql`
- `supabase/migrations/20260429210000_partner_hours_system.sql`

Estes JWTs aparecem em chamadas a `net.http_post(...)` para a Edge Function
`dispatch-engine` (cron jobs). Se a Supabase rotar o anon key, todos os jobs
falham silenciosamente.

## Pré-requisito (Danilo executa manualmente)

```sql
-- Una vez no SQL editor do Supabase Studio:
SELECT vault.create_secret(
  'eyJhbGciOiJIUzI1NiIs...'::text,    -- valor: o anon key actual
  'dispatch_anon_jwt'::text,           -- nome
  'JWT for dispatch-engine cron jobs (C2 vault cutover)'::text  -- description
);
```

Confirmar com:
```sql
SELECT name FROM vault.decrypted_secrets WHERE name = 'dispatch_anon_jwt';
-- Deve retornar 1 linha
```

## Implementação

### Passo 1 — Helper function

```sql
-- migration: 20260501XXXXXX_dispatch_jwt_vault_helper.sql
CREATE OR REPLACE FUNCTION public._dispatch_jwt() RETURNS text
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public, vault
AS $$
DECLARE v_jwt text;
BEGIN
  SELECT decrypted_secret INTO v_jwt
  FROM vault.decrypted_secrets WHERE name = 'dispatch_anon_jwt';
  IF v_jwt IS NULL THEN
    RAISE EXCEPTION 'dispatch_jwt_not_in_vault: run vault.create_secret first';
  END IF;
  RETURN v_jwt;
END; $$;
REVOKE ALL ON FUNCTION _dispatch_jwt FROM PUBLIC;
GRANT EXECUTE ON FUNCTION _dispatch_jwt TO authenticated, service_role;
```

### Passo 2 — Substituir hardcoded em 4 ficheiros

Em cada SQL onde aparece o JWT em `net.http_post(headers := jsonb_build_object('Authorization', 'Bearer ' || 'eyJ...'))`:

```sql
-- ANTES
'Authorization', 'Bearer ' || 'eyJhbGciOi...'

-- DEPOIS
'Authorization', 'Bearer ' || public._dispatch_jwt()
```

### Passo 3 — Re-aplicar em prod

Cada um dos 4 ficheiros tem `CREATE OR REPLACE FUNCTION` ou `CREATE OR REPLACE TRIGGER`
— seguro re-aplicar idempotentemente.

```bash
supabase db push --include-all  # ou aplicar via mcp__supabase__apply_migration um por um
```

### Passo 4 — Smoke test

```sql
-- Criar uma order pending e ver se cron dispatch a apanha
INSERT INTO orders (...)
VALUES (..., 'callingDriver');
-- Esperar 60s
SELECT id, status FROM orders ORDER BY created_at DESC LIMIT 1;
-- Deve estar em 'driverAccepted' (ou ainda 'callingDriver' se timeout não bateu)
-- O importante: NÃO falhar com 'invalid_jwt'
```

## Rollback

Se o cron começa a falhar:
```sql
-- Reverter a 4 ficheiros para versão pre-vault (git checkout origin/main -- supabase/migrations/...)
-- Aplicar via apply_migration
```

Tempo de rollback: ~5min (4 ficheiros + apply).

## Critério de aceitação

- `SELECT _dispatch_jwt();` retorna o JWT (read-only test)
- 24h de jobs cron sem falhas em `pg_cron.job_run_details`
- Rotação simulada: Danilo cria novo secret com mesmo nome via
  `vault.update_secret(...)` e o próximo cron pick-a o novo valor
- Zero referências a `eyJhbGciOi` nos 4 ficheiros migrados (grep)

## Pendência

1. Danilo executa `vault.create_secret(...)` manualmente
2. Danilo confirma `SELECT name FROM vault.decrypted_secrets;` mostra `dispatch_anon_jwt`
3. Cutover em janela de baixo tráfego (madrugada PT)
