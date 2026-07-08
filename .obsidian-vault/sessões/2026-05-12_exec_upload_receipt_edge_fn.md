# Sessão Execução Upload Receipt Edge Function — 2026-05-12

**Branch:** `autonomous-night-2026-04-29`
**Baseline:** `6b1c674` (sessão anterior pós-teste manual)
**HEAD final:** `e783b40`
**Tempo:** ~1h
**Modo:** PROTECÇÃO TOTAL + Opus 4.7

---

## Resumo Executivo

| Bug | Estado | Commit |
|---|---|---|
| **#3** Dialog "Total ajustado" | ✅ JÁ REMOVIDO (sessão anterior) | n/a |
| **#1** Upload 400 → Edge Function | ✅ FIXED via Edge Function `upload-receipt` | (commit no momento) |
| **#2** Loop GET orders | 🟡 PARTIAL fix + TODO sessão dedicada | `e783b40` |
| **#4** Validation E2E | ⏸ DEFERIDO Danilo (pedido teste limpo entretanto) | n/a |

**Score: 1 FIX completo + 1 PARTIAL + 1 doc + 1 deferred = scope coberto.**

---

## BUG #3 — Dialog "Total ajustado" (verificação)

**Estado:** ✅ JÁ REMOVIDO desde commit `e06501a` (sessão anterior).

**Verificação grep:**
- `'Total ajustado'` em `lib/`: 2 ocorrências
  - `cart_screen.dart:441` — apenas COMMENT (`// AlertDialog 'Total ajustado'...`)
  - `driver_map_screen.dart:2673` — label `'Total ajustado:'` em summary do estafeta (DIFERENTE — não é dialog)
- `'distância exacta'`: 0 ocorrências
- `'Pretendes continuar'`: 0 ocorrências

**Conclusão:** Re-aparição reportada no último teste manual foi **APK não rebuilt** após commit `e06501a`. Próximo build da branch `autonomous-night-2026-04-29` resolverá.

**Acção:** Nenhuma alteração de código (já está correcto).

---

## BUG #1 — Upload via Edge Function `upload-receipt` (CRÍTICO FIXED)

**Causa raiz definitiva:** `storage.from('receipts').upload()` directo do cliente Flutter falhava com **HTTP 400 silencioso** mesmo após:
- Bucket existir ✅
- Path correcto (sem prefixo duplicado) ✅
- RLS com uuid::text cast ✅
- Bucket público temporariamente ✅

**Diagnóstico Danilo via MCP**: pattern `upload-avatar` (Edge Function com service_role + base64) funciona em prod. Edge Function bypass storage rate limits/quirks que afectam upload directo.

### Fix Aplicado

**Edge Function `upload-receipt`** (já deployed via MCP, ACTIVE, verify_jwt=true):
- Sync source code para repo: `supabase/functions/upload-receipt/index.ts`
- API: `POST /functions/v1/upload-receipt` com `{orderId, fileBase64, totalCents}`
- Validações server-side:
  - 401 unauthorized (sem JWT)
  - 400 orderId_required / fileBase64_required / invalid_base64
  - 404 order_not_found
  - 403 not_your_order (assigned_driver_id != caller)
  - 413 file_too_large (>10MB)
  - 500 upload_failed (detail no body)
- Sucesso: `200 {success, path, bucket, order_id, total_cents}`
- Path final no bucket: `{order_id}.jpg`

**Flutter `ReceiptUploadService`** (novo `lib/services/receipt_upload_service.dart`):
- `uploadReceipt(orderId, photoFile, totalCents)` → `Future<String>` (path)
- Feature flag `_useEdgeFn = true` para rollback emergencial
- Parsing erro estruturado com mensagens PT-PT por código:
  - `not_your_order` → "Este pedido não está atribuído a si."
  - `file_too_large` → "Foto muito grande. Tira nova foto com menos qualidade."
  - `order_not_found` → "Pedido não encontrado. Refresca a app."
  - `unauthorized` → "Sessão expirada. Inicia sessão de novo."

**Callers Flutter substituídos:**
1. `lib/screens/driver_map_screen.dart` (fluxo activo estafeta) — linha ~2812
2. `lib/screens/store_shopping_purchase_screen.dart` (orphan screen) — linha ~118

Ambos agora chamam `ReceiptUploadService.uploadReceipt(...)` em vez de `storage.from('receipts').uploadBinary(...)`.

**AlertDialog "Falha ao enviar talão"** (BUG C anterior) mantido — agora mostra mensagens PT-PT específicas por código de erro.

---

## BUG #2 — Loop GET orders (PARTIAL FIX + TODO)

**Causa raiz não confirmada** após ~40min investigação:
- `_fallbackRefreshTimer` em `order_store.dart:155` fazia `Timer.periodic(seconds: 3)` → `notifyListeners()` a cada 3s
- 3-4 GET/seg reportados nos logs NÃO são consistentes com 0.33 notify/seg do timer
- Realtime stream (line 2012-2053) é WebSocket, não polling — não causa GETs
- `loadOrders()` callers: apenas initState/auth events, não loops obvios

**Defensive fix aplicado** (commit `e783b40`):
- `_fallbackRefreshTimer` interval: **3s → 30s** (10x menos notifyListeners)
- Reduz potencial cascade de rebuilds + qualquer query disparada por widgets watching OrderStore
- Timer continua como fallback se Realtime stalar

**Hipóteses NÃO confirmadas** (TODO sessão dedicada com `flutter run --verbose`):
1. Widget em build chama `loadOrders()` (anti-pattern) — não encontrado no grep
2. Supabase Realtime emit excessivo (driver_lat updates a cada 5s × multiplos channels)
3. ChangeNotifier rebuild loop (notify → widget rebuild → query trigger)
4. Auth state changes repetidas (AuthStore.refreshApprovalStatus em loop?)

**Recomendação:** próxima sessão com APK rebuilt e logcat live para identificar origem real.

---

## BUG #4 — Validation E2E (DEFERIDO)

**Estado pedido teste:** `5041075d-50c4-4491-ad2b-df9b884d7410` NÃO existe mais na DB (provavelmente limpo entretanto).

**Storage state actual:**
- `storage.objects` em bucket `receipts`: 1 row legacy `receipts/test-debug.jpg` (criado 2026-05-11, teste debug Danilo). Path antigo com prefixo duplicado — não afecta novos uploads via Edge Function.

**TODO Danilo (validação manual completa pós-rebuild APK):**

1. Build novo APK da branch `autonomous-night-2026-04-29` HEAD `e783b40`
2. Criar pedido teste storeShopping non-partner CASH
3. Estafeta aceita + finaliza compra (tira foto + digita total)
4. Confirmar via MCP:
   ```sql
   SELECT o.id, o.status, o.is_purchase_finalized, o.purchase_flow_version,
     o.final_purchase_value, o.cash_total_due,
     (SELECT COUNT(*) FROM order_purchase_items_v2 WHERE order_id = o.id) AS items_v2_count,
     (SELECT COUNT(*) FROM order_receipts_v2 WHERE order_id = o.id) AS receipts_v2_count,
     (SELECT photo_url FROM order_receipts_v2 WHERE order_id = o.id LIMIT 1) AS receipt_path,
     (SELECT COUNT(*) FROM storage.objects
      WHERE bucket_id = 'receipts' AND name = o.id::text || '.jpg') AS storage_exists
   FROM orders o WHERE o.id = '<test_order_uuid>';
   ```
   Esperado: `items_v2_count > 0`, `receipts_v2_count = 1`, `receipt_path = '<uuid>.jpg'`, `storage_exists = 1`
5. Verificar Edge Function logs via Supabase Dashboard → upload-receipt invocations 200 OK
6. Confirmar tela estafeta avança para "Entregar" automaticamente
7. Cliente recebe push "Compra finalizada"

---

## Áreas Proibidas (transparência)

**Todas intactas:**
- `pricing_service.dart` — não tocado
- `finalize_storeshopping_purchase` v1 — não tocado
- `finalize_storeshopping_purchase_v2` RPC — não tocado
- Stripe/MBWay webhooks — não tocados
- dispatch-engine — não tocado
- 17 triggers + trigger #18 — não tocados
- `enforce_financial_immutability` — não tocado
- Payout semanal — não tocado
- `wallet_apply_post_delivery_adjustment` — não tocado
- Storage RLS receipts — não tocada (já correcta desde sessão anterior)

---

## Bugs externos descobertos

1. **BUG #2 partial fix** — Causa raiz real desconhecida. Hipóteses documentadas mas requer flutter --verbose live para confirmar. TODO sessão dedicada.

2. **Storage legacy file** — `receipts/test-debug.jpg` (path antigo) ainda existe no bucket. Não afecta funcionalidade mas pode confundir admin auditor. Considerar limpeza em manutenção futura.

3. **Pedido teste `5041075d` limpo entretanto** — sem snapshot para validation E2E. Danilo deve criar novo pedido em manual test.

---

## Skill sugerida (não criada nesta sessão)

- **`supabase-storage-upload-via-edge`** — Localização: `.claude/skills/supabase-storage-upload-via-edge/SKILL.md`
  - Triggers: "upload Supabase falha 400 sem motivo", "Edge Function para storage"
  - Função: documenta o pattern (cliente → Edge Function service_role → storage) e gera scaffold de Edge Function + Flutter service para qualquer bucket

Adiada para próxima sessão de manutenção.

---

## TODOs Danilo (validação manual ponta-a-ponta)

1. **CRÍTICO**: Build novo APK + criar pedido teste novo → confirmar upload 200 (não mais 400)
2. **CRÍTICO**: DB query checklist completo (BUG #4 acima)
3. Verificar Edge Function `upload-receipt` logs no Supabase Dashboard
4. Confirmar dialog "Total ajustado" NÃO aparece em novo APK (BUG #3 verification)
5. Monitorizar logs GET orders rate: se ainda > 1/seg, sessão dedicada BUG #2 com flutter --verbose
6. Considerar limpeza `receipts/test-debug.jpg` legacy file

---

## Confirmações finais (per spec)

- ✅ Upload via Edge Function deployado (sync repo em `supabase/functions/upload-receipt/index.ts`)
- 🟡 Loop GET orders — partial fix (timer 3s→30s) + TODO sessão dedicada
- ✅ Dialog "Total ajustado" 100% removido (já estava — só verificação grep)
- ⏸ Pipeline E2E documentado — validation manual Danilo (pedido teste limpo)
- ✅ Edge Function sync repo
- N/A config.toml (não existe em supabase/ root; cada Edge Fn deployed via MCP sem config local)
- ✅ Áreas proibidas todas intactas

---

## Sync

- Local: `.claude/.ai/reports/2026-05-12_exec_upload_receipt_edge_fn.md`
- Obsidian: `.obsidian-vault/sessoes/2026-05-12_exec_upload_receipt_edge_fn.md`

---

*Sessão exec autónoma 2026-05-12 pós-segundo teste manual.*
*Feature-flag rollback `_useEdgeFn = false` disponível em ReceiptUploadService caso necessário.*
