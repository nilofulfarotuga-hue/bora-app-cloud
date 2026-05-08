# BLOCO 3 — Storage buckets + extension (Sessão 7-SEC-2 · 2026-05-08)

**Data**: 2026-05-08
**Sessão**: 7-SEC-2
**Modo**: MCP directo via Claude.ai
**Migration aplicada**: `bloco_3_storage_buckets_moddatetime`
(`20260508092347`)

---

## Objectivo

- Endurecer permissões dos buckets `avatars` e `order-photos`.
- Mover extensão `moddatetime` para schema `extensions`
  (boa prática Supabase).

---

## §3.1 Bucket `avatars`

### Antes

Sem policies aplicadas (acesso default — geralmente bloqueado para
non-service_role mas comportamento inconsistente).

### Depois — 4 policies

#### `avatars_select_public`

```sql
CREATE POLICY avatars_select_public ON storage.objects
  FOR SELECT
  USING (bucket_id = 'avatars');
```

Qualquer user (autenticado ou não) pode ler avatares — necessário
para mostrar foto de perfil em listas públicas.

#### `avatars_insert_own` / `avatars_update_own` / `avatars_delete_own`

```sql
CREATE POLICY avatars_insert_own ON storage.objects
  FOR INSERT WITH CHECK (
    bucket_id = 'avatars'
    AND (storage.foldername(name))[1] = auth.uid()::text
  );
```

(análogo para UPDATE/DELETE)

### Convenção de path Flutter

Filename **deve** começar com o `auth.uid()` do user como primeira
pasta:

```
{auth.uid()}/photo.jpg
{auth.uid()}/avatar_2026.png
```

Não-convenção: arquivos directamente na raiz do bucket
(`photo.jpg`) deixam de poder ser inseridos pelo próprio user.

### Rollback info

Se upload de avatares partir após BLOCO 3:
- Verificar que Flutter está a usar formato
  `{auth.uid()}/photo.jpg`.
- Se Flutter usava root sem prefix, precisa adaptar antes do
  launch.

---

## §3.2 Bucket `order-photos`

### Antes

`public=true` (qualquer pessoa com URL podia aceder).

### Depois

- `public=false` (privado).
- Policy `order_photos_select_participants`:

```sql
CREATE POLICY order_photos_select_participants ON storage.objects
  FOR SELECT USING (
    bucket_id = 'order-photos'
    AND EXISTS (
      SELECT 1 FROM orders o
      WHERE o.id::TEXT = (storage.foldername(name))[1]
        AND (
          o.client_id = auth.uid()
          OR o.assigned_driver_id::TEXT = auth.uid()::TEXT
          OR o.partner_id = auth.uid()
        )
    )
  );
```

Apenas participantes do order (cliente, estafeta atribuído,
partner) podem ler as fotos.

### Convenção de path

Foto de order deve estar dentro de pasta `{order.id}/`:

```
{order.id}/proof_pickup.jpg
{order.id}/proof_delivery.jpg
{order.id}/issue.png
```

---

## §3.3 Extension `moddatetime`

### Antes

Instalada em schema `public`.

### Depois

Movida para schema `extensions` (boa prática Supabase — separa
extensões de tabelas user).

```sql
DROP EXTENSION moddatetime;
CREATE EXTENSION moddatetime SCHEMA extensions;
```

Triggers existentes que usem `extensions.moddatetime()` continuam
a funcionar (PostgreSQL resolve via search_path).

---

## Resumo BLOCO 3

| Recurso | Acção | Notas |
|---|---|---|
| `avatars` | 4 policies (1 select + 3 mutate own) | Path `{uid}/file.ext` |
| `order-photos` | Privatizado + 1 policy participants | Path `{order_id}/file.ext` |
| `moddatetime` | Schema `public` → `extensions` | Boa prática |

**Estado final BLOCO 3**: storage seguro, fotos de pedidos não
acessíveis a strangers. ✅
