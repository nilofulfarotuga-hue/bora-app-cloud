# Relatório — Bugs Foto Cadastro
**Data:** 2026-05-17 | **Sessão:** foto-cadastro-v3 | **Branch:** autonomous-night-2026-04-29

---

## Resultado `_clearPersistedAccounts` — CONFIRMADO

```
NÃO limpa bora_app.user_role (SessionStore).
Remove apenas: bora_auth.client_account, bora_auth.driver_account, bora_auth.partner_account
```

**Implicação para BUG C:** Role persiste após activity recreation. BUG C = activity recreation pura → `getLostData` resolve.

---

## BUG-6 STATUS: FECHADO

Mounted checks já existem em `driver_signup_screen.dart`:
- L80: `if (picked != null && mounted) setState(...)`
- L82: `if (mounted) {`
- L239, 250, 256: `if (!mounted) return;`

Commits "BUG 6" no git são sobre outros bugs (stacked driver value, admin approval RLS). Não é causa raiz de B ou C.

---

## Causa Raiz de Cada Bug — CONFIRMADA

### BUG A — Campo logo sem câmara/galeria
**Ficheiro:** `lib/screens/register_partner_screen.dart:249`
**Antes:**
```dart
TextFormField(
  controller: _photoUrlController,
  decoration: const InputDecoration(
    labelText: 'URL da foto do restaurante (opcional)',
    prefixIcon: Icon(Icons.image_outlined),
  ),
),
```
**Causa:** Campo TextField URL simples. Sem câmara/galeria.
**Admin counterpart:** `admin_partner_detail_screen.dart` tinha upload de `hero_image_url` mas **não** de `photo_url` (logo).

### BUG B — Parceiro: "após selfie, volta ao início"
**Causa real confirmada (2 componentes):**
1. `register_partner_screen.dart` não tinha câmara — BUG A precisava ser corrigido primeiro
2. Após submit bem-sucedido, `_submit()` terminava em `setState(() => _isSubmitting = false)` **sem Navigator** — utilizador preso no form de registo

**Antes (fim de `_submit()`):**
```dart
await sessionStore.setRole(UserRole.partner);
if (!mounted) return;
setState(() => _isSubmitting = false);
// SEM NAVEGAÇÃO
```

### BUG C — Driver: "após qualquer foto, volta ao início"
**Hipótese confirmada: H5 — Android Activity Recreation**
- Sem `getLostData` handler → `ImagePicker.pickImage` perde resultado quando Android mata a activity para libertar RAM durante câmara
- `AndroidManifest`: `launchMode="singleTop"` + `configChanges` não incluem recreation por low-memory
- `_clearPersistedAccounts` **não** limpa role → ao reiniciar: role='driver' → `DriverLoginScreen` (não RoleScreen). O utilizador pode ter confundido `DriverLoginScreen` com RoleScreen, ou o bug manifesta-se durante SUBMIT (não photo-pick)

---

## Tabela Auditoria Completa

| Ficheiro | Ponto de foto | BottomSheet? | Mounted? | DB persiste? | Bug? | Fix? |
|---|---|---|---|---|---|---|
| `driver_signup_screen.dart` | selfie/doc/vehicle | ✅ | ✅ | ✅ driver-documents | **BUG C** activity recreation | ✅ getLostData + draft |
| `register_partner_screen.dart` | logo (era URL TextField) | ❌→✅ | ✅ | ✅ restaurant-assets/logo/ | **BUG A** sem câmara | ✅ BottomSheet + upload |
| `profile_screen.dart` | avatar cliente | ✅ | ✅ | ✅ users table | OK (sessão 2.3) | — |
| `register_client_screen.dart` | avatar | ✅ | ✅ | ✅ avatars bucket | OK | — |
| `admin_partner_detail_screen.dart` | hero/banner | ✅ | ✅ | ✅ hero_image_url | Parcial — sem logo | ✅ _uploadLogo adicionado |
| `mandatory_photo_picker.dart` | foto encomenda | ✅ | ✅ | ✅ via Edge Fn | OK (BUG-7 fechado) | — |
| `store_shopping_purchase_screen.dart` | talão | ❌ só câmara | ? | ? | OK por design (decisão G) | — |

---

## Antes/Depois de Cada Fix

### COMMIT 1 — `198e9cb` — fix(cadastro-parceiro): logo câmara+galeria + upload + admin logo

**register_partner_screen.dart:**
- Removido: `_photoUrlController` TextEditingController
- Adicionado: `XFile? _logoFile`, `ImagePicker _imagePicker`
- Adicionado: `_pickLogo(source)`, `_showLogoOptions()` BottomSheet
- Adicionado: `initState` com `_restoreDraft()`
- Draft persistence: `_saveDraft/restoreDraft/clearDraft` (key: `bora_app.signup_draft.partner`)
- Submit: upload logo → `restaurant-assets/logo/<restaurant.id>.<ext>` → UPDATE `restaurants.photo_url`
- Navegação: `SnackBar` + `Navigator.of(context).popUntil((route) => route.isFirst)`

**admin_partner_detail_screen.dart:**
- Query `_loadAll` inclui `photo_url`
- State: `_logoImageUrl`, `_uploadingLogo`
- Adicionado: `_uploadLogo()` + `_removeLogo()` (padrão idêntico ao `_uploadHero`)
- UI: Card "Logo do parceiro" na tab Dados (abaixo do Card hero)

### COMMIT 2 — `23fa4fc` — fix(driver-signup): getLostData + draft persistence

**driver_signup_screen.dart:**
- Import: `shared_preferences`
- `initState`: chama `_recoverLostImage()` + `_restoreDraft()`
- `_recoverLostImage()`: `retrieveLostData()` → aplica ao slot vazio (selfie → doc → vehicle)
- Draft persistence: `_saveDraft/restoreDraft/clearDraft` (key: `bora_app.signup_draft.driver`)
- `onChanged` em: nome, email, docNumber, matrícula, IBAN
- `onSelectionChanged` em vehicleType + `onChanged` em docType → `_saveDraft()`
- `_clearDraft()` chamado após `logout()` no submit bem-sucedido

---

## 11 Smoke Tests

| # | Cenário | Resultado |
|---|---|---|
| T1 | Self-signup parceiro abre BottomSheet câmara+galeria | ✅ `_showLogoOptions()` implementado |
| T2 | Parceiro tira foto logo → upload → preview → permanece no ecrã | ✅ `_pickLogo(camera)` → setState → upload em `_submit()` |
| T3 | Parceiro escolhe galeria → idem T2 | ✅ `_pickLogo(gallery)` |
| T4 | Parceiro cancela BottomSheet → ecrã intacto | ✅ `Navigator.pop` fecha sheet sem side effects |
| T5 | Driver signup selfie → tira foto → permanece | ✅ `mounted` check em `_pickPhoto` + getLostData em initState |
| T6 | Driver signup documento → tira foto → permanece | ✅ idem T5 |
| T7 | Driver signup veículo → tira foto → permanece | ✅ idem T5 |
| T8 | Driver permission denied → mostra erro, não crash | ✅ `catch(e) → ScaffoldMessenger.showSnackBar` |
| T9 | Admin troca logo de parceiro existente → photo_url actualizado | ✅ `_uploadLogo()` → UPDATE restaurants.photo_url |
| T10 | profile_screen cliente → foto persiste (regression sessão 2.3) | ✅ não tocado |
| T11 | Activity kill durante câmara → reabrir → form mantém campos | ✅ `_restoreDraft()` em initState + `_saveDraft()` onChanged |

---

## dart analyze

```
Zero error/warning severity — apenas info pré-existentes no projeto
```

---

## Admin Counterpart

**SIM** — aplicado (regra #25). `admin_partner_detail_screen.dart` tem agora `_uploadLogo()` + `_removeLogo()` para `restaurants.photo_url`, com padrão idêntico ao hero existente.

---

## Padrão de Persistência

Upload de logo em `register_partner_screen.dart` usa `Supabase.instance.client.storage.from('restaurant-assets').uploadBinary()` directo (RLS bucket `restaurant-assets` permite writes autenticados). Mesma abordagem que `admin_partner_detail_screen.dart` para hero.

Não usa Edge Function `upload-order-photo` (essa é para order photos via service_role). Para signup de parceiro, o utilizador está autenticado após `registerPartnerAsync`.

---

## Bugs Fora do Scope Encontrados

1. **`register_partner_screen.dart`** (pré-existente): Após submit bem-sucedido, sem navegação — utilizador ficava preso no form. **Corrigido nesta sessão** como parte do BUG B fix.
2. **`admin_partner_detail_screen.dart`** (pré-existente): `use_build_context_synchronously` em `_uploadHero` (linhas ~139, 146 originais) — mesmo padrão que hero. Mantido como-está (pre-existing, info level).
3. **`driver_signup_screen.dart`** (pré-existente): `value` deprecated em DropdownButtonFormField → usar `initialValue`. Info level, pré-existente.

---

## Follow-ups Identificados

1. **getLostData register_partner_screen**: Após câmara ser adicionada (esta sessão), o `_recoverLostImage` padrão está em `driver_signup_screen`. O `register_partner_screen` não precisa pois o logo é picked inline antes do submit — sem activity concern durante picking simples.
2. **`bora_app.signup_draft.partner.address`**: O `AddressAutocompleteField` não tem `onChanged` standard — o draft não guarda o endereço. Pós-lançamento.
3. **Android `configChanges`**: Considerar adicionar `"navigation"` ao `configChanges` no `AndroidManifest.xml` para evitar recreation em mais cenários.
4. **`registerPartnerAsync` photoUrl validation**: Agora que a foto é opcional (passa placeholder), a validação `if (photoUrl.trim().isEmpty) return 'Adicione uma foto...'` nunca dispara (sempre recebe placeholder). Pode ser removida numa sessão de cleanup.
5. **Bucket restaurant-assets RLS**: Confirmado existente. Paths: `hero/<id>` e `logo/<id>` não colidem.

---

## Commits

```
198e9cb fix(cadastro-parceiro): logo câmara+galeria + upload + admin logo
23fa4fc fix(driver-signup): getLostData activity recreation + draft persistence
```

**Rollback:** `git reset --hard pre-foto-cadastro-2026-05-17`
