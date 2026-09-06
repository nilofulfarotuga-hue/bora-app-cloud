# 🔒 CORREÇÃO FOTOS ADMIN — Relatório Final (2026-06-02)

> Branch `autonomous-night-2026-04-29` · Opus 4.7 · execução autónoma
> Bloqueador de lançamento RGPD resolvido + 2 gaps de UX admin corrigidos.

---

## 1. Diagnóstico (origem auditoria 2026-06-02)

| # | Problema | Severidade |
|---|---|---|
| 🚨 | `restaurants.owner_doc_url` + `activity_doc_url` guardados em bucket PÚBLICO `restaurant-assets` → qualquer pessoa com o URL via documentos de identidade do dono. | **RGPD CRÍTICO** |
| 🔴 | Após aprovação, docs do parceiro só apareciam em `admin_partners_pending` (filtrado por `status='pending'`) → admin perdia acesso visual. | Compliance |
| 🟡 | `vehicle_doc_url` (livrete) não aparecia em `admin_driver_approval`, só no `admin_driver_detail`. | UX admin |

---

## 2. Execução (7 passos)

### PASSO 1 — Bucket privado
Migration `20260602100000_create_restaurant_documents_bucket.sql`:
- `restaurant-documents` PRIVADO + 4 policies (espelha `driver-documents`).
- Upload: pasta `auth.uid()` OU `temp-*` (signup pré-link).
- SELECT: dono OR admin. UPDATE/DELETE só `service_role`.
- Commit **af3e27a** (já aplicado).

### PASSO 2 — Migração 2 ficheiros existentes
Script Node download → upload → verify → delete. Os 2 docs (owner + activity) migrados de `restaurant-assets` para `restaurant-documents`. DB actualizada com paths novos.

### PASSO 3 — Edge Function
`upload-restaurant-asset/index.ts` decide server-side: `kind ∈ {owner_doc, activity_doc}` → bucket `restaurant-documents` (privado, `public_url=null`). Restantes (logo) → `restaurant-assets`. Adiciona campo `bucket` no response. Deploy **v4**.

### PASSO 4 — Admin Partner Detail
`admin_partner_detail_screen.dart`:
- SELECT extendido com `owner_doc_url, activity_doc_url`.
- Novo card **"Documentos"** entre Logo e botão Editar.
- Widget `_PartnerDocImage` (cópia do `_ZoomableImage` do driver detail) — `PrivateBucketImage` + fullscreen `InteractiveViewer`.

### PASSO 5 — Admin Driver Approval
`admin_driver_approval_screen.dart`: bloco `vehicle_doc_url` adicionado após `vehicle_photo_url`, mesmo padrão `GestureDetector → PrivateBucketImage → _showFullscreen`.

### PASSO 5b — Consistência partners_pending
`admin_partners_pending_screen.dart`: `Image.network(owner_doc_url)` → `PrivateBucketImage` (paths já não são URLs públicos).

### PASSO 6 — Validação MCP

```sql
-- 1) Onde estão os docs?
SELECT bucket_id, count(*) FROM storage.objects
WHERE name ILIKE '%owner_doc%' OR name ILIKE '%activity_doc%'
GROUP BY 1;
-- → [{bucket_id: "restaurant-documents", n: 2}]   ✅ ZERO em restaurant-assets

-- 2) Buckets
SELECT id, public FROM storage.buckets
WHERE id IN ('restaurant-assets','restaurant-documents','driver-documents');
-- → driver-documents:false · restaurant-assets:true · restaurant-documents:false  ✅

-- 3) DB guarda apenas paths
SELECT owner_doc_url, activity_doc_url FROM restaurants
WHERE owner_doc_url IS NOT NULL LIMIT 5;
-- → temp-1779836494632/owner_doc-1779836496216.jpg
--   temp-1779836496412/activity_doc-1779836496709.jpg   ✅ paths, não URLs
```

### PASSO 7 — Commits + Push

| Commit | Conteúdo |
|---|---|
| af3e27a | Migration bucket + migração 2 ficheiros |
| 3d7a1af | Edge Fn (split server-side) + `register_partner_screen` (store path) |
| 49a544e | `admin_partner_detail` secção Documentos + `admin_partners_pending` PrivateBucketImage |
| dcc3fd1 | `admin_driver_approval` mostra `vehicle_doc_url` |

`flutter analyze` (3 ficheiros): **0 erros**, só 14 infos pré-existentes (use_build_context_synchronously, curly_braces, deprecated activeColor — todas fora dos blocos modificados).

---

## 3. Zonas NÃO tocadas (auditoria)

- `pricing_service.dart`, `dispatch_engine.dart`, `OrderStatus`, RPCs financeiras, triggers `bora_tokens`, Stripe Edge Fns, RLS de `orders/wallets/ledger_entries`. ✅
- `_RootNavigator` e fluxo de auth. ✅
- Logo + hero do parceiro mantêm-se públicos (decisão de negócio correta). ✅

---

## 4. Estado final

| Métrica | Antes | Depois |
|---|---|---|
| Docs sensíveis em bucket público | 2 | **0** |
| Bucket `restaurant-documents` | inexistente | **privado + 4 policies** |
| Admin vê docs do parceiro após aprovação | ❌ | ✅ (PrivateBucketImage signed URL) |
| Admin vê livrete na aprovação | ❌ | ✅ |
| `flutter analyze` nas alterações | n/a | **0 erros** |

**RGPD bloqueador de lançamento: resolvido.** Pronto para próximo build (versionCode bump quando o Danilo decidir disparar).
