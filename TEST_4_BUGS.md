# Teste dos 4 Bugs — Partner Registration Flow

## BUG-1: PartnerLoginScreen — "Criar Conta" button missing
**Expected:** Screen should show "Não tens conta? Criar conta de parceiro" button
**Test:**
1. Open app → RoleScreen
2. Tap Partner role
3. Verify "Não tens conta?" button appears at bottom
4. Tap button → should navigate to RegisterPartnerScreen

## BUG-2: RLS Policy — Products unauthorized access
**Expected:** Only partner who owns restaurant can see/edit products
**Test:**
1. Login as Partner (registered)
2. Try to add new product
3. Should only see own restaurant's products
4. Verify RLS blocks access to other restaurants' products

## BUG-3: Product Photo Preview — black/blank screen
**Expected:** Product photo should show image or fallback icon
**Test:**
1. In AddProductScreen
2. Select product photo from gallery
3. Verify preview shows image (not black screen)
4. If no image, should show fallback icon

## BUG-4: Admin Catalog — product photos missing
**Expected:** Admin catalog should display product images as CircleAvatar
**Test:**
1. Login as Admin
2. Navigate to Admin Catalog
3. Verify each product shows photo or fallback icon
4. Images should be circular with fallback icon if missing

## Status (verificado no Ciclo 2 autónomo — 2026-05-28)
- [x] Bug 1 verified — **já corrigido**: `partner_login_screen.dart:124` mostra
      "Não tens conta? Criar conta de parceiro" → navega para RegisterPartnerScreen (:140).
- [x] Bug 2 verified — **não é bug**: RLS de `products` correcta. INSERT/UPDATE/DELETE
      travados ao dono do restaurante; SELECT público é intencional (clientes navegam o
      catálogo). Tech debt de policies duplicadas documentado em `docs/bugs-zona-protegida.md`
      (OBS-RLS-001) — não alterado (Validation Gate).
- [x] Bug 3 verified — **já corrigido**: `add_product_screen.dart:237` usa `Image.file`
      com `errorBuilder` → `Icons.broken_image` (sem ecrã preto).
- [x] Bug 4 verified — **já corrigido**: `admin_catalog_screen.dart:262-270` usa
      CircleAvatar com `NetworkImage` + fallback icon quando `photo_url` vazio.
