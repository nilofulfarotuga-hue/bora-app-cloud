# Sessão 2.3 — Upload de Fotos Unificado (UX + Persistência)
**Data:** 2026-05-17 | **Branch:** autonomous-night-2026-04-29 | **Tag rollback:** pre-foto-upload-unificado-2026-05-17

---

## Causa Raiz Confirmada

**`updateCurrentUserPhoto()` em `auth_store.dart` persistia APENAS em:**
1. ✅ Estado local in-memory
2. ✅ SharedPreferences (_persistClient/_persistDriver/_persistPartner)
3. ✅ `auth.users.user_metadata['bora_photo_url']` via `auth.updateUser()`

**NUNCA persistia em:**
- ❌ `public.users.photo_url` — por isso 0/5 clientes com foto
- ❌ `public.drivers.photo_url` — por isso 0/8 drivers com foto actualizada
- ❌ `public.restaurants.photo_url` — por isso 0/14 partners com foto

**Resultado observável:** foto aparecia no device que fez upload (via SharedPreferences) mas não noutros devices, no admin, nem em sessão fresca.

### Hipóteses confirmadas/descartadas

| Hipótese | Estado |
|---|---|
| H2: Código faz upload mas esquece UPDATE público | ✅ CONFIRMADA |
| H1: RLS falta UPDATE policy | ❌ Descartada — users_update_own + drivers_update_own existem; restaurants_auth_write (ALL) existe |
| H3: UPDATE silenciosamente falha | ❌ Descartada — UPDATE nunca era tentado |
| H4/H5 | ❌ Descartadas |

### Adicional encontrado durante investigação

- `register_client_screen.dart` também só escrevia em `auth.user_metadata`, nunca em `public.users`
- Trigger `auth.users → public.users`: **não existe** — rows em `public.users` não são criadas automaticamente
- `restaurants_auth_write (ALL, auth.uid() IS NOT NULL)`: qualquer utilizador autenticado pode UPDATE em qualquer restaurante — **⚠️ RLS crítico a endurecer**
- `_kPhotoUrl = 'bora_photo_url'` = consistente com `register_client_screen` ✅

---

## Estado UX — quase tudo já estava correcto

| Ponto | UX actual | Correcto? |
|---|---|---|
| Client perfil | Camera + Galeria (BottomSheet) | ✅ JÁ CORRECTO |
| Driver signup (doc/veículo) | Camera + Galeria (_showPhotoOptions) | ✅ JÁ CORRECTO |
| SendPackage / CarryGroceries | MandatoryPhotoPicker (câmara+galeria) | ✅ JÁ CORRECTO |
| Talão storeShopping | Só câmara (Decisão G) | ✅ EXCEPÇÃO MANTIDA |
| Admin hero banner | ❌ Só galeria | **CORRIGIDO** → câmara+galeria |

`mandatory_photo_picker.dart` + `OrderPhotoUploadService` já existiam e estavam correctos.

---

## Commits (3)

| Commit | Ficheiro | Mudança |
|---|---|---|
| `220c7d4` | `lib/auth/auth_store.dart` | `updateCurrentUserPhoto` agora faz UPSERT/UPDATE em `users`/`drivers`/`restaurants` após `auth.updateUser` |
| `d8b1003` | `lib/screens/register_client_screen.dart` | Signup com foto → UPSERT `public.users.photo_url` |
| `3d8f4c3` | `lib/screens/admin/admin_partner_detail_screen.dart` | `_uploadHero` com BottomSheet câmara+galeria |

---

## Smoke Tests T1-T10

| Test | Descrição | Estado |
|---|---|---|
| T1 | Cliente toca foto perfil → BottomSheet câmara+galeria | ✅ Já existia — não alterado |
| T2 | Upload foto perfil → `users.photo_url` guardado na DB | ⏳ Requer teste físico |
| T3 | Outro device após upload → foto visível | ⏳ Requer teste físico |
| T4 | Driver faz upload foto perfil → `drivers.photo_url` actualizado | ⏳ Requer teste físico |
| T5 | Admin hero upload → BottomSheet câmara+galeria | ✅ Novo comportamento |
| T6 | Talão storeShopping — só câmara, intocado | ✅ `driver_map_screen` não alterado |
| T7 | Driver signup fotos → `document_photo_url` preenchido | ✅ `driver_signup_screen` não alterado |
| T8 | Novo driver signup → `drivers.document_photo_url` | ⏳ Verificar com signup real |
| T9 | Novo client signup com foto → `users.photo_url` | ⏳ Requer teste físico |
| T10 | UPSERT cria row quando não existe em `public.users` | ⏳ Forçar: criar user em auth sem row pública, fazer login, mudar foto → verificar row criada |

**Comandos de validação via MCP após testes:**
```sql
SELECT id, photo_url FROM users WHERE photo_url IS NOT NULL;
SELECT user_id, photo_url FROM drivers WHERE photo_url IS NOT NULL;
SELECT id, photo_url FROM restaurants WHERE photo_url IS NOT NULL;
```

---

## PhotoPickerService — Decisão final

**Não foi criado** — não era necessário. Os ecrãs que precisavam já tinham a UX correcta. Apenas o admin hero estava errado (corrigido com BottomSheet inline, 23 linhas). O `mandatory_photo_picker.dart` continua a ser o helper reutilizável para sendPackage/carryGroceries.

---

## Follow-ups Registados

| # | Prioridade | Item |
|---|---|---|
| 1 | 🔴 CRÍTICO | **`restaurants_auth_write (ALL, auth.uid() IS NOT NULL)`** — qualquer user autenticado pode UPDATE qualquer restaurante. Endurecer para "só o partner dono" antes do lançamento. Sessão dedicada de RLS hardening. |
| 2 | 🟡 MÉDIO | **Trigger `auth.users → public.users`** — não existe. Considerar criar para auto-popular `id/email/name` no INSERT de novos auth users. |
| 3 | 🟡 MÉDIO | **5 users em `public.users` com `name/email NULL`** — backfill one-off: `UPDATE users u SET email = a.email FROM auth.users a WHERE u.id = a.id AND u.email IS NULL` |
| 4 | 🟡 MÉDIO | **Partner foto** — `_partnerRestaurant` pode ser null quando `_currentPartner != null`. Se null, UPDATE em restaurants silencia. Investigar quando `setPartnerRestaurant` é chamado e garantir que está carregado no boot do dashboard. |
| 5 | 🟢 BAIXO | `push_token_service.dart` — comentário ainda menciona só `client/driver`. Actualizar para incluir `partner`. |

---

## Achados Fora de Scope

1. **`mandatory_photo_picker.dart`** usa `OrderPhotoUploadService` → Edge Fn `upload-order-photo`. O `_useEdgeFn = true` está activo. Confirmar que a Edge Fn está deployada antes do lançamento (não testado nesta sessão).

2. **`profile_screen.dart`** tem 3 estratégias de upload (direct → fallback edge fn `upload-avatar`). Complexidade elevada. Funciona em produção (3 ficheiros no bucket avatars). Não alterado.

3. **`driver_signup_screen.dart`** usa `createSignedUrl(1 ano)` para documentos — URLs expiram após 1 ano. Admin approval screen vai mostrar imagem quebrada passado 1 ano. Follow-up: migrar para public bucket com RLS adequada, ou regenerar URLs a pedido.

---

## Admin counterpart

**Não são necessários novos ecrãs admin** para esta sessão. O toggle `is_popular` e o upload hero já existem nos ecrãs admin correctos (sessão 2.1).

O backfill de `public.users` (follow-up #3) é um one-off SQL a correr via Supabase dashboard.
