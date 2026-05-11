---
name: storage-bucket-validator
description: Audita estado de um bucket Supabase Storage e as suas policies RLS. Útil para diagnóstico rápido quando uploads falham 400/403, para confirmar deploy de RLS após migration, ou para validar config (file_size_limit, mime types).
triggers:
  - "verificar bucket"
  - "audit storage bucket"
  - "validar policies storage"
  - "/storage-bucket-validator"
  - "diagnose upload failure"
---

# Storage Bucket Validator

Skill para o Robô B diagnosticar estado de um bucket Supabase Storage —
existência, configuração, RLS policies, e amostra de ficheiros.

## Quando invocar

- Upload falha com 400/403 e suspeita-se de bucket missing ou RLS errada
- Após migration de bucket criação para confirmar deploy correcto
- Auditoria periódica de buckets sensíveis (receipts, partner-uploads, etc)
- Validar antes de prod release que bucket existe + tem RLS apropriadas

## Parâmetros

- `bucket_id` (text, obrigatório) — ID do bucket (ex: 'receipts')
- `sample_count` (int, default 5) — quantos ficheiros recentes listar
- `check_path_pattern` (text, opcional) — regex para path expected

## Algoritmo

1. **Existence**:
   ```sql
   SELECT id, name, public, file_size_limit, allowed_mime_types, created_at
   FROM storage.buckets WHERE id = $1;
   ```
   - Se 0 rows → ❌ BUCKET MISSING (root cause uploads 400)
   - Reportar config

2. **RLS Policies**:
   ```sql
   SELECT policyname, cmd,
          qual::text AS using_expr,
          with_check::text AS check_expr
   FROM pg_policies
   WHERE schemaname='storage' AND tablename='objects'
     AND (qual::text LIKE '%' || $1 || '%' OR
          with_check::text LIKE '%' || $1 || '%')
   ORDER BY policyname;
   ```
   - Listar todas policies que referenciam o bucket
   - Por padrão esperar: 1 INSERT (driver/owner), 2-3 SELECT (owner+admin), 1 UPDATE/DELETE se aplicável
   - Flag se nenhuma policy existe (RLS deny-all)

3. **RLS Logic Sanity**:
   - Para cada policy, parsing simples do expression para detectar:
     - Está a usar `bucket_id = $bucket`? ✓
     - Usa `auth.uid()` para owner check? ✓
     - Usa `is_admin()` para admin override? ✓
     - REPLACE chain para path stripping? (warning se ausente quando esperado)

4. **Sample files**:
   ```sql
   SELECT name, owner, created_at, last_accessed_at,
          metadata->>'size' AS size_bytes,
          metadata->>'mimetype' AS mime
   FROM storage.objects
   WHERE bucket_id = $1
   ORDER BY created_at DESC
   LIMIT $sample_count;
   ```
   - Listar últimos N ficheiros
   - Se vazio + bucket existe → flag "bucket vazio (possível flow não chega ao upload)"

5. **Path pattern validation** (se check_path_pattern fornecido):
   ```sql
   SELECT name, name ~ $pattern AS matches
   FROM storage.objects WHERE bucket_id = $1
   LIMIT 50;
   ```
   - Reportar % de ficheiros que match
   - Flag se < 100% match

## Output Format

```
=== Storage Bucket Audit — <bucket_id> ===

📦 Existence: ✅ EXISTS | ❌ MISSING
  Public: <bool>
  File size limit: <bytes> (<MB> MB)
  Allowed MIME: <list>
  Created: <date>

🛡 RLS Policies (<count>):
  - <policy_name> [<CMD>]
    using: <expr_summary>
    check: <expr_summary>
    sanity: ✅ OK | ⚠️ <warning>
  ...

📁 Sample files (<count>):
  - <name> | <size> | <mime> | <date>
  ...

🔍 Pattern validation (if requested):
  Pattern: <regex>
  Match rate: <pct>% (<n>/<total>)

⚠️ Flags:
  - <flag1>
  - <flag2>

💡 Recommendations:
  - <action1>
  - <action2>
```

## Casos especiais

- **Bucket missing**: recomendar migration template idempotente
- **Sem RLS**: recomendar migration para criar policies (referencing pattern Bora)
- **Bucket vazio + RLS OK**: investigar UI flow (cliente Flutter nunca chama upload?)
- **Mime mismatch**: ficheiros uploaded com mime fora do allowed_mime_types → bucket pode estar a rejeitar silenciosamente

## Notas

- Read-only — NÃO modifica DB nem bucket
- Para criar bucket via skill: NÃO. Devem ser migrations versionadas no repo.
- Útil em par com `storeshopping-v2-debugger` quando o receipt falta — esta skill confirma se é bucket ou se é flow upstream que falhou.
