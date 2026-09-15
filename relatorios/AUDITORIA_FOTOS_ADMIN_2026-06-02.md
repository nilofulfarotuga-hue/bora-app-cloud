# 🔍 AUDITORIA FOTOS → ADMIN — 2026-06-02

> Modo: **read-only** · Branch `autonomous-night-2026-04-29` · ZERO edições a `lib/`
> Objectivo: provar end-to-end (upload → storage → DB → admin render) que cada foto do cadastro tem onde aparecer no admin **após** aprovação.

---

## 1. Inventário de campos de foto

### Driver (`drivers`)
| # | Coluna DB | Upload em | Variável no signup |
|---|---|---|---|
| D1 | `photo_url` | (avatar do utilizador, separado do signup) | n/a |
| D2 | `registration_selfie_url` | `driver_signup_screen.dart` Passo 3 | `_selfieFile` (kind=`selfie`) |
| D3 | `document_photo_url` | `driver_signup_screen.dart` Passo 3 | `_documentPhotoFile` (kind=`document`) |
| D4 | `vehicle_photo_url` | `driver_signup_screen.dart` Passo 4 | `_vehiclePhotoFile` (kind=`vehicle`) |
| D5 | `vehicle_doc_url` | `driver_signup_screen.dart` Passo 4 | `_vehicleDocFile` (kind=`vehicle_doc`) |

### Partner (`restaurants`)
| # | Coluna DB | Upload em | Variável |
|---|---|---|---|
| P1 | `photo_url` (logo) | `register_partner_screen.dart` Passo 4 | `_logoFile` (kind=`logo`) |
| P2 | `hero_image_url` (capa) | **NÃO no signup** — só em partner dashboard | n/a |
| P3 | `owner_doc_url` | `register_partner_screen.dart` Passo 2 | `_ownerDocFile` (kind=`owner_doc`) |
| P4 | `activity_doc_url` | `register_partner_screen.dart` Passo 2 | `_activityDocFile` (kind=`activity_doc`) |

---

## 2. Buckets Supabase Storage

Buckets criados/configurados via migrations (`supabase/migrations/`):

| Bucket | public | Migrations / Edge Fn |
|---|---|---|
| `avatars` | **true** (público) | `20260430010000_avatars_bucket_rls.sql` · edge `upload-avatar` |
| `order-photos` | **false** (privado) | `20260508092347_bloco_3_storage_buckets_moddatetime.sql` |
| `receipts` | **false** (privado) | `20260511110000_…` · `20260511220000_create_receipts_bucket.sql` · **`20260531070000_make_receipts_bucket_private.sql`** · edges `ocr-receipt`, `upload-receipt` |

**⚠️ Observação:** o repo só cria 3 buckets via migration. Os ficheiros de driver-docs e partner-docs **vão provavelmente para `avatars` (público)** ou para um bucket criado fora das migrations (configurado direto via dashboard Supabase) — **pendente verificação DB**: `select id, public from storage.buckets;` quando estável.

**Upload paths (do código):**
- Driver `_uploadPhoto` chama edge function/RPC (`functions.invoke`) e devolve `signed_url`/`url`/`path` — fluxo via Edge Fn, bucket configurado server-side (não no client).
- Partner upload (`register_partner_screen.dart:270-370`) usa `functions.invoke('register-partner', ...)` que retorna `data['public_url']` — bucket configurado server-side.

---

## 3. Matriz de cobertura — Upload → DB → Admin

| # | Entidade | Campo DB | Upload em | Bucket | Ecrã admin onde aparece | Widget render | Compatível? | Status |
|---|---|---|---|---|---|---|---|---|
| D1 | Driver | `photo_url` (avatar) | edge `upload-avatar` | **avatars (pub)** | `admin_clients_screen`, `admin_driver_approval`, `admin_driver_detail`, `admin_catalog`, `admin_receipts`, `admin_partner_detail`, `admin_partners_pending` | `NetworkImage` / `Image.network` | ✅ pub+Image.network OK | ✅ **OK** |
| D2 | Driver | `registration_selfie_url` | edge fn (kind=selfie) | pendente DB | `admin_driver_approval` (pending) + `admin_driver_detail` (após) | `Image.network` + `PrivateBucketImage` | depende do bucket | ✅ **OK** (coberto pending + detail) |
| D3 | Driver | `document_photo_url` | edge fn (kind=document) | pendente DB | `admin_driver_approval` + `admin_driver_detail` | `Image.network` + `PrivateBucketImage` | depende | ✅ **OK** |
| D4 | Driver | `vehicle_photo_url` | edge fn (kind=vehicle) | pendente DB | `admin_driver_approval` + `admin_driver_detail` | `Image.network` + `PrivateBucketImage` | depende | ✅ **OK** |
| D5 | Driver | `vehicle_doc_url` | edge fn (kind=vehicle_doc) | pendente DB | **só `admin_driver_detail`** (NÃO no approval) | `PrivateBucketImage` | depende | 🟡 **GAP MENOR** — admin não vê o doc do veículo durante a aprovação |
| P1 | Partner | `photo_url` (logo) | edge `register-partner` (kind=logo) | provável `avatars` | `admin_partner_detail`, `admin_partners_pending`, vários | `Image.network` | ✅ se pub | ✅ **OK** |
| P2 | Partner | `hero_image_url` | partner dashboard (não signup) | pendente DB | `admin_partner_detail` | `Image.network` | ✅ se pub | ✅ **OK** |
| P3 | Partner | `owner_doc_url` | edge `register-partner` (kind=owner_doc) | pendente DB | **só `admin_partners_pending`** | `Image.network` | depende | 🔴 **BURACO CRÍTICO** — após aprovação a admin perde acesso ao doc do proprietário |
| P4 | Partner | `activity_doc_url` | edge `register-partner` (kind=activity_doc) | pendente DB | **só `admin_partners_pending`** | `Image.network` | depende | 🔴 **BURACO CRÍTICO** — idem |

---

## 4. 🔴 Buracos detectados (priorizados)

### 🔴 BURACO #1 — `restaurants.owner_doc_url` invisível após aprovação
- **Evidência:** referenciado APENAS em `admin_partners_pending_screen.dart:236`. Ecrã filtra `approval_status='pending'`. Em `admin_partner_detail_screen.dart` (que carrega após aprovação) **não há grep do nome da coluna**.
- **Impacto:** depois de aprovar o parceiro, a admin perde para sempre o acesso visual ao doc de identidade do proprietário. Inspecção/auditoria/fraude → impossível pelo UI.
- **Severidade:** ALTA (compliance + auditoria + GDPR — admin tem de poder reabrir o doc se houver disputa).
- **Proposta (NÃO implementar agora):** acrescentar uma secção "Documentos" em `admin_partner_detail_screen.dart` (já tem hero+logo). Esboço:
  ```dart
  // Secção: Documentos da candidatura
  if ((r['owner_doc_url'] as String?)?.isNotEmpty ?? false)
    _DocTile(label: 'Doc proprietário', url: r['owner_doc_url']);
  if ((r['activity_doc_url'] as String?)?.isNotEmpty ?? false)
    _DocTile(label: 'Doc atividade', url: r['activity_doc_url']);
  ```
  Widget `_DocTile` envolve `Image.network` ou `PrivateBucketImage` conforme bucket. Reusar exatamente o padrão de `partners_pending:225-274`.

### 🔴 BURACO #2 — `restaurants.activity_doc_url` invisível após aprovação
- Mesmo problema, mesma fix conjunta com #1 (no mesmo ecrã `admin_partner_detail_screen`).

### 🟡 GAP MENOR — `drivers.vehicle_doc_url` ausente do ecrã de aprovação
- **Evidência:** referenciado em `admin_driver_detail_screen.dart` mas **não** em `admin_driver_approval_screen.dart`. Os outros 3 docs (selfie/document/vehicle_photo) estão em ambos.
- **Impacto:** no momento da aprovação, a admin só vê 3 dos 4 documentos do estafeta — pode aprovar sem ver o doc do veículo (livrete).
- **Severidade:** MÉDIA (admin pode sempre ir ao detail para o ver, mas o fluxo de aprovação deveria mostrar tudo de uma vez).
- **Proposta (NÃO implementar agora):** adicionar bloco em `admin_driver_approval_screen.dart` com `vehicle_doc_url` (já existe widget pronto para os outros 3).

### ⚠️ INVESTIGAR — Bucket dos docs sensíveis (NIF/IBAN-adjacente)
- Os campos sensíveis (selfie, doc identidade, doc atividade do parceiro) não têm bucket criado explicitamente nas migrations do repo. Há **risco** de estarem no bucket `avatars` (público) → exposição.
- **Acção:** quando a DB estabilizar, correr `select id, name, public from storage.buckets order by id;` e listar os objects (`select bucket_id, count(*) from storage.objects group by 1`) para confirmar onde estão os ficheiros reais (e se algum bucket público contém docs sensíveis). **Bucket público com dados sensíveis = vazamento.** Esta é a única excepção que justificaria migration imediata — mas só posso confirmar via DB.

---

## 5. ✅ O que está bem (confirmado)

- `drivers.photo_url` (avatar) — bucket `avatars` público + `NetworkImage`. Render correto em **7 ecrãs admin**.
- `drivers.registration_selfie_url`, `document_photo_url`, `vehicle_photo_url` — visíveis em **`admin_driver_approval` (durante pending) + `admin_driver_detail` (após)**. Cobertura completa.
- `restaurants.photo_url` (logo) e `hero_image_url` — visíveis em `admin_partner_detail` (com Image.network). Edição/clear via admin também existe (linhas 296/334 do detail).

---

## 6. Pendências de DB (não bloqueantes para esta auditoria)

1. `select id, public from storage.buckets order by id;` → lista real de buckets.
2. `select bucket_id, count(*) from storage.objects group by bucket_id;` → onde estão os ficheiros.
3. `select bucket_id from storage.objects where name like '%selfie%' or name like '%doc%' limit 5;` → confirmar bucket dos docs sensíveis.

---

## 7. Resumo executivo

| Métrica | Valor |
|---|---|
| Total de campos auditados | **9** (5 driver + 4 partner) |
| ✅ OK | **6** (D1–D4, P1, P2) |
| 🟡 GAP MENOR | **1** (D5 `vehicle_doc_url` falta no approval) |
| 🔴 BURACO CRÍTICO | **2** (P3 `owner_doc_url`, P4 `activity_doc_url` invisíveis após aprovação) |
| ⚠️ Investigar | **1** (bucket dos docs sensíveis — pendente DB) |

**Acção recomendada (depois da aprovação do Danilo):**
1. Implementar secção "Documentos" em `admin_partner_detail_screen.dart` para mostrar `owner_doc_url` + `activity_doc_url` após aprovação. **(corrige #1 + #2 com uma intervenção)**
2. Acrescentar `vehicle_doc_url` em `admin_driver_approval_screen.dart`. **(corrige gap menor)**
3. Quando DB estabilizar: verificar bucket dos docs sensíveis. Se algum estiver no `avatars` (público) → migrar para bucket privado + signed URLs.

**NÃO implementado nesta sessão** (por instrução: parar após auditoria; Danilo decide o que aprovar).
