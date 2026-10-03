# SEC Safe Fixes — 2026-06-23

## Fixes aplicados (SEGUROS — pré-aprovados pelo Danilo no contrato)

### 3.1 Bucket `avatars` — listagem pública desativada
- **Antes:** `public = true` (qualquer pessoa podia listar todos os avatares)
- **Depois:** `public = false` (acesso individual via signed URL mantém-se)
- **SQL:** `UPDATE storage.buckets SET public = false WHERE name = 'avatars' AND public = true;`
- **Verificação:** `SELECT name, public FROM storage.buckets WHERE name = 'avatars';` → `public: false` ✅
- **Impacto:** Zero. O app usa signed URLs para aceder a avatares — nunca lista o bucket.

### 3.2 Backup table — RLS enabled
- **Tabela:** `_backup_continente_precos_pre_oficial_2026_06_14`
- **Antes:** `relrowsecurity = false` (acessível a qualquer role autenticado)
- **Depois:** `relrowsecurity = true` (RLS activo, sem policies = ninguém acede via API)
- **SQL:** `ALTER TABLE _backup_continente_precos_pre_oficial_2026_06_14 ENABLE ROW LEVEL SECURITY;`
- **Verificação:** `SELECT relname, relrowsecurity FROM pg_class WHERE relname = '...'` → `true` ✅
- **Impacto:** Zero. Tabela de backup, não usada pelo app nem por RPCs.

## Fixes NÃO aplicados (REQUEREM APROVAÇÃO)

Ver `security/revoke-anon-functions.sql` — 14 funções SECURITY DEFINER executáveis por anon.
Ver `sessions/2026-06-23-sec1-sec2-dryrun.md` — relatório completo do dry-run anterior.
