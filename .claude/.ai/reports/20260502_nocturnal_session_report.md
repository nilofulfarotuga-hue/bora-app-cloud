# Sessão Nocturna 2026-05-02 — 5 fases atómicas

**Branch:** `autonomous-night-2026-04-29`
**Início:** sessão autónoma noturna após Danilo dormir.
**Estado:** ✅ Todas as 5 fases concluídas, smoke MCP validado, push em origin.

---

## Tabela executiva

| FASE | Status | SHA | Migration | Smoke | Tempo |
|---|---|---|---|---|---|
| 1 — Heartbeat 30s + auto-offline 90s | ✅ DONE | `0d10069` | `20260502030000_driver_heartbeat.sql` | ✅ marked=1, stale→offline | ~50 min |
| 2 — Pickup guard storeShopping | ✅ DONE | `1473177` | `20260502040000_storeshopping_pickup_guard.sql` | ✅ block/pass/partner-noblock | ~15 min |
| 3 — Admin cash collected display | ✅ DONE | `cc69148` | (sem migration) | flutter analyze 0 errors | ~20 min |
| 4 — Foto prova unavailable items | ✅ DONE | `7db95bb` | `20260502050000_orders_items_unavailable_photos.sql` | ✅ UPDATE direct passa | ~70 min |
| 5 — Botão ligar tel: link | ✅ DONE | `2d25658` | (sem migration) | flutter analyze 0 errors | ~15 min |

**Total:** 5/5 fases DONE. ~3h. Sem skips, sem fails.

---

## Migrations aplicadas em prod (Supabase `ojykpzwqrtusfeakzrna`)

1. `driver_heartbeat_30s_auto_offline_90s` — drivers.last_heartbeat_at + RPC `driver_heartbeat()` + `mark_stale_drivers_offline()` + pg_cron `* * * * *`.
2. `driver_heartbeat_fix_uuid_column` — patch (drivers.id é UUID, não TEXT).
3. `storeshopping_pickup_guard` — trigger `enforce_storeshopping_finalize_before_pickup` BEFORE UPDATE em orders.
4. `orders_items_unavailable_photos_column` — ADD COLUMN orders.items_unavailable_photos JSONB.

---

## Smoke MCP results

### FASE 1 — heartbeat
| Cenário | Resultado |
|---|---|
| Driver stale (heartbeat -120s) | mark_stale_count=1, is_online=false ✅ |
| Driver fresh (heartbeat -30s) | is_online=true (não tocado) ✅ |
| pg_cron agendado | active=true, schedule='* * * * *' ✅ |

### FASE 2 — pickup guard
| Cenário | Resultado |
|---|---|
| pickedUp sem finalize (non-partner) | BLOCKED com `finalize_purchase_before_pickup` ✅ |
| pickedUp com finalize=true | PASSED ✅ |
| pickedUp partner sem finalize | NÃO BLOQUEADO (correcto, partner usa fluxo restaurant) ✅ |

### FASE 4 — items_unavailable_photos
| Cenário | Resultado |
|---|---|
| UPDATE direct na coluna sem GUC bypass | PASSA (não bate em enforce_financial_immutability) ✅ |

---

## Bugs colaterais detectados durante a sessão

- **Schema discovery — drivers.id é UUID, não TEXT:** Aparece como inconsistência face ao `orders.id TEXT`. RPC heartbeat inicial usava `auth.uid()::text` que falhou. Patch aplicado. Anota: padrão de cast em triggers/RPCs orders deve ser tratado por tabela individualmente — alguns são UUID, outros TEXT.
- **Storage policy "order-photos upload own" exige path `{auth.uid}/...`:** ditou o esquema do path da foto unavailable. Já estava em design.
- **Pre-existing info `prefer_const_constructors` em [admin_order_detail_screen.dart:725](../../lib/screens/admin/admin_order_detail_screen.dart#L725) e `activeColor` deprecated em [driver_home_screen.dart:934](../../lib/screens/driver_home_screen.dart#L934).** NÃO introduzidas por mim. Anotar para limpeza pós-launch.

---

## Ficheiros tocados (lista completa)

### Backend (migrations + frontend)
- `supabase/migrations/20260502030000_driver_heartbeat.sql` (NEW)
- `supabase/migrations/20260502040000_storeshopping_pickup_guard.sql` (NEW)
- `supabase/migrations/20260502050000_orders_items_unavailable_photos.sql` (NEW)

### Flutter
- `lib/services/heartbeat_service.dart` (NEW)
- `lib/screens/driver_home_screen.dart` (FASE 1: import, dispose, lifecycle, toggles, init delay)
- `lib/screens/driver_map_screen.dart` (FASE 4: image_picker, supabase, _captureUnavailableProof, _unavailablePhotos state, modified "Não há" callback, modified GestureDetector toggle, modified finalizePurchaseV2 call; FASE 5: url_launcher, Row Chat+Ligar)
- `lib/stores/order_store.dart` (FASE 4: param `unavailablePhotos`, UPDATE direct após RPC succeed)
- `lib/screens/admin/admin_order_detail_screen.dart` (FASE 3: cash collected card; FASE 4: items_unavailable_photos lookup, _PhotoThumb widget, SELECT estendida)
- `.claude/.ai/decisions/2026-05-01-todos-pos-launch.md` (Twilio masking TODO)

---

## flutter analyze diff (issues totais)

- **Antes da sessão:** 52 issues (info/deprecation warnings, todos pré-existentes).
- **Depois da sessão:** 52 issues. **0 erros novos.**
- Warnings pré-existentes não tocados intencionalmente (fora de scope).

---

## TODOs adicionados em todos-pos-launch.md

- **Twilio number masking** (BAIXO/privacidade): `tel:` link directo expõe números. Edge Function `dial-via-mask` proposta com Twilio Conference + 2 PINs. Estimado ~2h + onboarding Twilio.

(Outros TODOs já existentes mantidos: BUG 24 admin reset foto driver, BUG 30 (✅ FIXED nesta sessão), BUG 39 polyline tempo real, tech-debt GUC bypass, tech-debt shell driver↔cliente, admin cash display (✅ FIXED), Twilio masking.)

**Nota:** BUG 30 e admin cash display estavam como TODO; ambos foram FIXED nesta sessão. Sugiro Danilo reordenar a lista (mover esses 2 para "RESOLVED").

---

## Próximos passos sugeridos para Danilo

1. **Codemagic build:** push detectado em `autonomous-night-2026-04-29`. Verificar build OK. Última SHA: `2d25658`.
2. **Smoke E2E manual após APK:**
   - **FASE 1:** abrir driver app → toggle Online → Supabase Studio: `drivers.last_heartbeat_at` deve actualizar a cada 30s. Fechar app/perda de rede → após 90s, `is_online=false`.
   - **FASE 2:** estafeta tenta marcar pickedUp num pedido storeShopping não-parceiro sem finalizar → erro "finalize_purchase_before_pickup". Após finalizar → passa.
   - **FASE 3:** admin abre pedido cash delivered → secção "💵 Cash entregue" verde aparece com valor + adjustment.
   - **FASE 4:** estafeta marca um item ❌ → câmera abre → tira foto → botão fica disabled durante upload → marca vermelho. Cancelar câmera → não marca. Toggle de volta a pending → foto removida. Admin order detail mostra thumbnail clicável (zoom).
   - **FASE 5:** estafeta vê pedido com clientPhone → vê botão "Ligar" verde ao lado de "Chat" → tap → app de chamada nativa.
3. **Sanity check produção:** `SELECT * FROM cron.job WHERE jobname='mark-stale-drivers-offline'` → confirma `active=true`. Ver `cron.job_run_details` últimas 5 execuções para garantir 0 falhas.
4. **TODOs pós-launch:** revisar `.claude/.ai/decisions/2026-05-01-todos-pos-launch.md` e priorizar.

---

## Lista de commits desta sessão (cronológica)

```
2d25658 feat(driver): direct call button with tel: link (Twilio masking TODO)
7db95bb feat(storeshopping): driver photo proof for unavailable items
cc69148 feat(admin): cash collected display in order detail
1473177 feat(storeshopping): server guard pickup requires finalized purchase
0d10069 feat(driver): heartbeat 30s + auto-offline 90s (launch blocker)
```

5 commits atómicos. Cada um pode ser revertido individualmente sem afectar os outros.

---

## NÃO mexido (regras rigorosas honradas)

- ✅ dispatch engine intacto
- ✅ pricing_service intacto
- ✅ tokens Batch D regras intactas (apenas casts UUID)
- ✅ Stripe core intacto
- ✅ código 4 dígitos card/mbway intacto (não tocado nesta sessão)
- ✅ enforce_financial_immutability core intacto
- ✅ finalize_storeshopping_purchase RPC NÃO foi editada (só lida nas FASEs)

---

**Boa noite, Danilo. Sessão completa, código em produção, smokes OK. Verifica de manhã.**
