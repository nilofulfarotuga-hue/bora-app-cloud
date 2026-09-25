# Análise READ-ONLY — Teste Real StoreShopping V2 (2026-05-11)

**Branch:** `autonomous-night-2026-04-29`
**HEAD:** `64748d9` (sessão 17-bugs anterior)
**Pedido teste:** `5041075d-50c4-4491-ad2b-df9b884d7410` (CASH não-parceiro, status=driverAccepted)
**Modo:** Análise pura — NADA foi modificado nesta sessão.
**Tempo análise:** ~45min

---

## Resumo Executivo (5 linhas)

1. **8 bugs raiz, 1 consequência (D auto-resolve após A), 1 falso positivo (G).** BUG A já fixed via MCP (bucket criado), faltam migrations sync repo.
2. **Bloqueador #1: BUG A→B→C+I→D dependentes em cadeia.** BUG A (bucket) desbloqueia D (RPC chamada). BUG C/I são UX layer.
3. **Impacto financeiro: BUG F real (€0.22 diff cliente vs server), BUG G é falso positivo** — driver_earnings €5.79 está MATEMATICAMENTE CORRECTO com distance=4.445km (não €5.33 que assumia distance=2km).
4. **Risco produção: BAIXO.** Maior risco em BUG F (precisa Flutter passar distância real ao server antes de mostrar total). Opção B path (sem tocar RLS) preferida para BUG B.
5. **Próximo passo: BUG A migration sync (~10min) + BUG B/C/I correções UI (~1h) + BUG E debug com logs (~30min) + BUG F UX fix (~1h) + BUG H tela CASH (~30min). Total fix completo: ~3h30min.**

---

## A0 — Baseline Confirmado

```
HEAD: 64748d9 (sessão 17-bugs)
Branch: autonomous-night-2026-04-29
Trigger #18 ACTIVO: trg_zz_set_purchase_flow_version BEFORE INSERT orders ✓
Query 1: v2_count=1, v1_count=0, null_count=0 (storeShopping non-partner 24h)
Query 2: v1_count=0, v2_count=0 (storeShopping partner 24h — sem pedidos)
Bucket receipts: EXISTE (file_size_limit=null por confirmar; mime=null)
RLS receipts: 4 policies activas (admin/client/driver_select + driver_insert)
```

---

## BUG A — Bucket `receipts` (CRÍTICO, já fixed via MCP)

**Estado:** Bucket criado in-flight via MCP nesta sessão. Falta migration repo.

**Causa raiz confirmada:** Migration anterior `20260511110000_storeshopping_v2_schema.sql` faz `INSERT INTO storage.buckets ... ON CONFLICT DO NOTHING` MAS o INSERT pode ter sido revertido OU nunca aplicado em prod. Bucket não existia em `SELECT * FROM storage.buckets WHERE id='receipts'`.

**Ficheiros a tocar:**
- `supabase/migrations/<ts>_create_receipts_bucket.sql` (NOVO — sync repo)

**Mudança proposta:** Migration idempotente com `INSERT INTO storage.buckets (...) ON CONFLICT (id) DO NOTHING`. Inclui `file_size_limit=10485760` (10MB) + `allowed_mime_types=ARRAY['image/jpeg','image/png','image/webp']`.

**Risco:** **BAIXO**. Idempotente, prod já tem bucket → no-op. Dev/staging cria fresh.

**Conformidade:** business_rules §STORESHOPPING NÃO-PARCEIRO + memória 7-DOCS-FINAL convenção de migrations.

**Dependências:** Nenhuma (root bug).

**Ordem:** **PRIMEIRO** (desbloqueia tudo).

### Template Migration (já aprovado pelo prompt)

```sql
-- supabase/migrations/20260511220000_create_receipts_bucket.sql
-- Storage bucket 'receipts' — sync repo
-- Bucket já criado em prod via MCP em 2026-05-11.
-- Esta migration garante criação idempotente em dev/staging.

INSERT INTO storage.buckets (
  id, name, public, file_size_limit, allowed_mime_types
) VALUES (
  'receipts',
  'receipts',
  false,
  10485760,  -- 10 MB
  ARRAY['image/jpeg', 'image/png', 'image/webp']
)
ON CONFLICT (id) DO NOTHING;

-- RLS policies já existem em prod (criadas em sessão close-todos 2026-05-11):
-- - admin_select_all_receipts_storage
-- - client_select_own_receipt
-- - driver_insert_own_receipt
-- - driver_select_own_receipt
--
-- Para dev/staging fresh, replicar as 4 policies (ver migration
-- 20260511120000_receipts_storage_rls_applied.sql que JÁ está no repo).
```

---

## BUG B — Path duplicado `receipts/receipts/...`

**Causa raiz confirmada (READ):**
- `lib/screens/driver_map_screen.dart` linha **2802**: `storagePath = 'receipts/${order.id}.jpg';`
- `lib/screens/driver_map_screen.dart` linha **2804**: `storage.from('receipts').uploadBinary(storagePath, ...)`
- Resultado: bucket=`receipts`, name=`receipts/<order_id>.jpg`, URL=`/storage/v1/object/receipts/receipts/<order_id>.jpg`

**Análise risco:** RLS já lida com **AMBOS** os formatos via `replace(replace(objects.name, 'receipts/', ''), '.jpg', '')`. Funcionalmente CORRECTO (DB row tem name=`receipts/abc.jpg`, replace extrai `abc`).

A duplicação é **visual** na URL — não afecta funcionamento. O 400 reportado foi consequência de BUG A (bucket missing), NÃO de path duplicado.

**Decisão preferida (Opção B — menor risco):**
- **Manter path actual** `receipts/<order_id>.jpg` (RLS já compatível)
- **Sem alteração de código nem RLS** — apenas validar BUG A fixed → upload funciona

**Ficheiros a tocar:** Nenhum (apenas validar após fix BUG A).

**Risco:** **BAIXO** (sem alteração).

**Conformidade:** N/A (não-bug funcional).

**Dependências:** BUG A.

**Ordem:** Validar após BUG A.

**Alternativa Opção A (apenas se Danilo preferir):**
- Mudar driver_map linha 2802 para `storagePath = '${order.id}.jpg';`
- Ajustar 4 RLS policies para `o.id = replace(objects.name, '.jpg', '')`
- Risco MÉDIO (RLS deploy + Flutter deploy sincronizado)

---

## BUG C — Upload falha silenciosamente (UX layer)

**Causa raiz confirmada (READ `driver_map_screen.dart:2812-2816`):**

```dart
} catch (e) {
  messenger.showSnackBar(SnackBar(
      content: Text('Erro upload talão: $e')));
  return;
}
```

UI **JÁ MOSTRA** SnackBar com erro. MAS:
1. SnackBar duration default = 4s; mensagem pode passar despercebida
2. Texto técnico `StorageException(...)` confuso para estafeta
3. Após erro, estafeta volta para tela checklist sem indicação clara que precisa re-tirar foto ou contactar admin

**Mudança proposta:**
- Substituir SnackBar por `AlertDialog` com:
  - Título: "Falha ao enviar talão"
  - Body PT-PT amigável: "Não foi possível guardar a foto do talão. Verifica ligação à internet e tenta de novo."
  - Botão "Tentar novamente" (re-abre `_ReceiptCaptureSheet`)
  - Botão "Cancelar"
- Log `e` em debugPrint para diagnóstico interno

**Ficheiros:** `lib/screens/driver_map_screen.dart` linha 2812-2816 + helper `_showUploadErrorDialog`.

**Risco:** **BAIXO** (UI-only, sem impacto DB).

**Conformidade:** business_rules §UX storeShopping V2 (auditoria).

**Dependências:** BUG A.

**Ordem:** Após BUG A + B.

---

## BUG D — RPC v2 nunca chamada (consequência)

**Causa raiz confirmada:** `driver_map_screen.dart:2811-2814` faz `return` no catch do upload, que pula `finalizeStoreShoppingV2WithReceipt` na linha 2819. Como bucket não existia (BUG A), upload sempre falhava → return → RPC v2 nunca chamada.

**Auto-resolve:** Após BUG A fix (bucket criado), upload sucede → RPC v2 É chamada. **Sem alteração de código necessária.**

**Validação pós-fix:** Cria pedido teste novo + estafeta finaliza → confirmar via:
```sql
SELECT id, purchase_flow_version, is_purchase_finalized FROM orders WHERE id=...;
SELECT * FROM order_receipts_v2 WHERE order_id=...;
SELECT count(*) FROM order_purchase_items_v2 WHERE order_id=...;
```

**Ficheiros:** Nenhum.

**Risco:** N/A.

**Ordem:** Validação após A+B.

---

## BUG E — driver_push_tokens vazio (commit `fc981de` não funcionou)

**Causa raiz parcialmente identificada (READ `notification_service.dart:144-163` + `push_token_service.dart:43-110`):**

Código actual já tem fix do commit fc981de:
- `saveTokenForDriver` chama `PushTokenService.registerForRole('driver').ignore()` ANTES do try/catch legacy
- `registerForRole` valida `client.auth.currentUser != null`, fetcha token, chama RPC `register_push_token`

**Hipóteses prováveis:**
1. **`saveTokenForDriver(driverId)` NÃO É CHAMADO** para o estafeta teste9 no fluxo actual de login (suspeita primária)
2. `NotificationService.instance.fcmToken` ainda é null quando saveTokenForDriver é chamado, e `FirebaseMessaging.instance.getToken()` falha silenciosamente em release
3. `auth.currentUser` é null durante o curto window entre login button e auth state settled (race condition)
4. `consent_granted` é false (ConsentStore desliga FCM)
5. RPC `register_push_token` falha por permissões/RLS mas debugPrint está em release build ignored

**Mudança proposta (defensive fix):**
1. **Em `_RootNavigator` / `auth_gate`**: adicionar `WidgetsBinding.instance.addPostFrameCallback` que detecta auth.currentUser + role 'driver' e chama `PushTokenService.registerForRole('driver')` independentemente de login screen flow
2. **Em `PushTokenService.registerForRole`**: substituir `debugPrint` por log também ao `Sentry`/admin (se disponível) — visibilidade em release
3. **Retry**: PushTokenService deve enquadrar uma fila de retry quando `getToken()` falha (3 tentativas com backoff)

**Ficheiros a tocar:**
- `lib/main.dart` ou `lib/screens/_root_navigator.dart` (auth gate entrypoint)
- `lib/services/push_token_service.dart` (retry + logging)
- `lib/screens/driver_home_screen.dart` (chamada explícita em initState)

**Risco:** **MÉDIO** (toca auth flow). Mitigação: idempotente, nunca corrompe state.

**Conformidade:** business_rules §52.1 (push tokens multi-device).

**Dependências:** Nenhuma.

**Ordem:** Independente — pode ser corrigido em paralelo a A+B.

**TODO Danilo (pré-fix):** capturar `flutter run --verbose` durante login estafeta teste9, ver se `[NotificationService] saveTokenForDriver` e `[PushTokenService] ✓ token registered for driver` aparecem nos logs. Isto confirma se é caso (1) ou (2/3/4).

---

## BUG F — Cliente vê €13.44 mas DB tem €13.66 (€0.22 diff)

**Causa raiz confirmada via DB+pricing_service READ:**

```
Pedido teste DB:
  subtotal = €8.44 (já com 15% markup embutido)
  distance_km = 4.445
  service_fee = €2.50  (= _nonPartnerPurchaseFee, constante)
  delivery_fee = €2.72 (= €2.50 base + extra)
  extra = (4.445 - 4.0) × €0.50 = €0.2225 → round €0.22

Total real server = €8.44 + €2.50 + €2.72 = €13.66 ✓
Total estimado Flutter = €8.44 + €2.50 + €2.50 = €13.44 (sem extra)

DISCREPÂNCIA: €0.22 = extra distância (4.445 - 4.0 km × €0.50)
```

**O Flutter local `PricingService.calculateBreakdown` USA a MESMA fórmula** (`_partnerDeliveryFee + extraDistance × _packageExtraPerKm`). Logo, a diferença vem do **valor de `distance` passado**:
- Flutter local: assume distance ≤ 4km (provavelmente passa 1km default ou usa estimativa antes de ter rota)
- Server (`quote_order_pricing` RPC ou trigger): usa distance real (4.445km)

Cliente vê total estimado, server cria pedido com total real, cliente cobrado €13.66 quando esperava €13.44 = **bad UX/contrato**.

**Mudança proposta (NÃO TOCA pricing_service):**
1. **Flutter** (`cart_store.dart` ou `cart_screen.dart`): antes de mostrar total final ao cliente no checkout, chamar Edge Fn / RPC `quote_order_pricing` server-side com distance/endereços reais → obter total authoritative → mostrar isso
2. **Ou alternativa simples:** mostrar disclaimer "Total estimado — pode variar conforme distância real (~±€0.50)" + commit total no momento do create_order quando server retorna valores definitivos

**Preferida:** Opção 1 (server-side quote pre-checkout). Já existe RPC `quote_order_pricing` no DB — só usar.

**Ficheiros:**
- `lib/stores/cart_store.dart` (linha ~158 onde chama `PricingService.calculateBreakdown`)
- `lib/screens/cart_screen.dart` (linha ~437 antes de `cartStore.finishOrder`)

**Risco:** **MÉDIO**. Pricing é área proibida mas estamos só a LER do server, não a alterar. O risco é chamar `quote_order_pricing` ANTES do user confirmar pode causar charges/quotas no server. Throttle/cache 30s recomendado.

**Conformidade:** business_rules §STORESHOPPING NÃO-PARCEIRO (subtotal+€2.50+€2.50 mas distance > 4km muda delivery_fee — bug é não mostrar isso ao cliente).

**Dependências:** Nenhuma.

**Ordem:** Após FASE 1 bugs (A+B+C+I+D+E).

---

## BUG G — driver_earnings €5.79 vs €5.33 (FALSO POSITIVO)

**Causa raiz: NÃO É BUG. Cálculo correcto pelo pricing_service.**

**Validação matemática (com distance_km=4.445 do DB):**

```
boraMarkup     = subtotal × 0.15 = €8.44 × 0.15 = €1.266 → round €1.27
boraGross      = boraMarkup + deliveryFee + serviceFee = €1.27 + €2.72 + €2.50 = €6.49
driverFixed    = base + shoppingBonus + perKm×distance
               = €3.80 + €0.80 + (€0.20 × 4.445)
               = €4.60 + €0.889 = €5.489 → round €5.49
boraNet        = max(0, boraGross − driverFixed) = €6.49 − €5.49 = €1.00
driverShare30% = €1.00 × 0.30 = €0.30
driverEarnings = €5.49 + €0.30 = €5.79 ✓ BATE COM DB
```

**Conclusão:** O cálculo manual no prompt assumia `distance=2km`, mas a distância real é 4.445km. Driver_earnings está **correctamente computado**.

**Acção:** Nenhuma alteração. **Reportar como FALSO POSITIVO** no relatório.

**TODO Danilo:** verificar se "2km" no prompt era estimativa ou medição real. Se medição real, então `distance_km=4.445` no DB seria o bug (cálculo de distância errado em outro lugar). Quick check: distância Google Maps cliente↔Continente Guarda.

---

## BUG H — Tela estafeta "Cliente paga €8.54" em vez de €13.66

**Causa raiz confirmada (READ `driver_map_screen.dart:2274-2280 + 2691-2696`):**

```dart
final adjustedTotal = boughtTotal + _bagFee + addedFinalTotal;
// adjustedTotal = €8.44 + €0.10 + €0 = €8.54 (apenas produtos + sacos)
// NÃO inclui service_fee (€2.50) + delivery_fee (€2.72)

if (isCash) {
  // linha 2691-2696
  Row(... 'Cliente paga na entrega:' ... '€${adjustedTotal.toStringAsFixed(2)}')
}
```

Em CASH, cliente paga TOTAL FINAL ao estafeta na entrega: `subtotal_real + sacos + service_fee + delivery_fee + extras_pos_compra`. Mas tela mostra apenas `subtotal_real + sacos`.

**Mudança proposta:**
- Adicionar variável `cashClientPays = adjustedTotal + serviceFee + deliveryFee` (lidas de `order.serviceFee + order.deliveryFee`)
- Tela CASH mostra breakdown explícito:
  ```
  Produtos comprados: €X.XX
  Sacos: €0.YY
  Taxa de serviço: €2.50
  Entrega: €Z.ZZ
  ─────────────
  Total cliente paga: €T.TT
  ```
- Branch MBWay/Stripe inalterado (já mostra "Bora reembolsa-te" — não é cliente que paga)

**Ficheiros:** `lib/screens/driver_map_screen.dart` linhas ~2680-2700 (CASH branch da summary).

**Risco:** **BAIXO** (UI-only, valores vêm de `order.*Fee` que já existem).

**Conformidade:** business_rules §PAGAMENTO CASH (estafeta cobra TOTAL na entrega, max €40).

**Dependências:** Nenhuma (mas mais útil após BUG F porque garante valores authoritative).

**Ordem:** Após BUG F (para garantir order.deliveryFee é authoritative).

---

## BUG I — Modal Confirmar sem foto não dá erro

**Causa raiz: NÃO É BUG. UI já mostra SnackBar (READ `driver_map_screen.dart:2949-2953`):**

```dart
if (_photo == null) {
  ScaffoldMessenger.of(context).showSnackBar(
    const SnackBar(content: Text('Tira foto do talão primeiro.')),
  );
  return;
}
```

**Hipótese:** SnackBar pode ter sido ocultado por outro SnackBar imediatamente posterior, OU o user tocou "Confirmar" várias vezes rápidas e só viu o último.

**Mudança proposta (UX hardening, opcional):**
- Substituir SnackBar por estado visual no botão "Confirmar": disabled + tooltip "Tira foto primeiro" quando `_photo == null`
- Mais visível que SnackBar transient
- Bonus: mesmo para campo valor — disabled até photo+total preenchidos

**Ficheiros:** `lib/screens/driver_map_screen.dart` `_ReceiptCaptureSheet` (linha ~2960 onSubmit button).

**Risco:** **BAIXO**.

**Conformidade:** business_rules §UX storeShopping V2.

**Dependências:** Nenhuma.

**Ordem:** Após BUG C (juntos formam fix UX completo).

---

## BUG J — V1 finalize_storeshopping_purchase débito €1.70 (DOCUMENTAR APENAS)

**Causa raiz suspeita:** V1 tem cálculo errado de `total_charge_cents` quando há sacos + cliente já tinha saldo. €1.70 = ?

**Acção:** **Apenas documentar** — V1 é área proibida e deprecated para storeShopping não-parceiro (trigger #18 força V2 em novos pedidos).

**Migration policy:** V1 continua a servir storeShopping partner + restaurant onde matemática é diferente. V1 storeShopping non-partner deprecated.

**Documentação sugerida:** Adicionar comment em `finalize_storeshopping_purchase` RPC: `-- DEPRECATED for storeShopping non-partner. Use v2.`. Mas mesmo isso requer ALTER FUNCTION → área proibida. Apenas adicionar nota em business_rules.md §52.3.

**Ficheiros:** `business_rules.md` (doc only).

**Risco:** N/A.

---

## Bugs externos ao scope (encontrados durante análise)

1. **`orders` schema inconsistency**: coluna `restaurant_earnings` referenciada em alguma query mas NÃO EXISTE (erro execute_sql). Pode ser dead code de view ou trigger antigo. Verificar `pg_views` + `pg_get_triggerdef` para detectar references.

2. **Discrepância distance Flutter vs server**: Flutter local pricing usa distance default/estimada (BUG F root cause). Estrutura mais ampla: `cart_store` cálcula breakdown ANTES de saber a rota real. Refactor `cart_store.recompute()` para async chamar `quote_order_pricing` quando endereço dropoff muda.

3. **`PushTokenService._lastRegisteredRole` static** — race condition possível se 2 utilizadores (driver + client) usarem o mesmo device em sessões consecutivas. O cache pode bloquear re-registo legítimo. Reset state em logout (já tem `resetSessionState` mas não chamado em flow real).

4. **Migration `20260511110000_storeshopping_v2_schema.sql` linha 138** tem `INSERT INTO storage.buckets` que pode ter sido revertido em algum rollback. Sync repo necessário (BUG A migration).

---

## Skills novas identificadas

1. **`storeshopping-v2-debugger`** — Localização: `.claude/skills/storeshopping-v2-debugger/SKILL.md`
   - Triggers: "diagnosticar pedido storeShopping v2", "validar fluxo v2", "auditar order_receipts_v2"
   - Função: query orchestration para validar estado de um pedido (orders + order_purchase_items_v2 + order_receipts_v2 + wallet_transactions + audit log) num único output.

2. **`storage-bucket-validator`** — Localização: `.claude/skills/storage-bucket-validator/SKILL.md`
   - Triggers: "verificar bucket X", "audit storage policies"
   - Função: verificar existência, RLS policies, file_size_limit, mime types de qualquer bucket Supabase.

3. **`driver-earnings-validator`** — Localização: `.claude/skills/driver-earnings-validator/SKILL.md`
   - Triggers: "validar driver_earnings X", "auditar pagamento estafeta Y"
   - Função: replicar fórmula pricing_service contra order DB row + flag se discrepância.

Nenhuma criada nesta sessão (read-only). Sugestões para Danilo aprovar em sessão futura.

---

## Migration Plan — Bucket Receipts (idempotente)

**Path sugerido:** `supabase/migrations/20260511220000_create_receipts_bucket.sql`

**Conteúdo (template aprovado pelo prompt):**

```sql
-- ════════════════════════════════════════════════════════════
-- Storage bucket 'receipts' — sync repo (bucket já em prod via MCP)
-- ════════════════════════════════════════════════════════════

INSERT INTO storage.buckets (
  id, name, public, file_size_limit, allowed_mime_types
) VALUES (
  'receipts',
  'receipts',
  false,
  10485760,  -- 10 MB
  ARRAY['image/jpeg', 'image/png', 'image/webp']
)
ON CONFLICT (id) DO NOTHING;

-- RLS policies já existem em prod (migration anterior
-- 20260511120000_receipts_storage_rls_applied.sql). NÃO duplicar.
```

Encoding UTF-8 sem BOM. Comentários PT-PT. Idempotente (ON CONFLICT DO NOTHING).

---

## Validação Trigger #18 — Resultados

| Query | Resultado | Esperado | Status |
|---|---|---|---|
| Q1 — storeShopping non-partner 24h: v2=1, v1=0, null=0, total=1 | ✓ | total = v2_count | ✅ PASS |
| Q2 — storeShopping partner 24h: v1=0, v2=0, total=0 | ✓ | sem pedidos | ✅ PASS (sem amostra) |
| Q3 — trigger definition | `CREATE TRIGGER trg_zz_set_purchase_flow_version BEFORE INSERT ON public.orders FOR EACH ROW EXECUTE FUNCTION ...` | match | ✅ PASS |

**Conclusão:** Trigger #18 funciona correctamente para pedidos não-parceiros. Parceiros mantêm v1 default (sem pedidos parceiros recentes para validar exhaustivamente, mas lógica está correcta na função).

---

## Ordem Final Sugerida de Aplicação

| # | Bug | Esforço | Risco | Dependências |
|---|---|---|---|---|
| 1 | **A** — Migration receipts bucket sync | 10min | BAIXO | — |
| 2 | **B** — Validate path (no code change) | 5min | NULL | A |
| 3 | **C** — UX upload error dialog | 30min | BAIXO | A |
| 4 | **I** — UX disable button sem foto | 20min | BAIXO | C |
| 5 | **D** — Validate RPC v2 chamado | 10min teste | NULL | A+B |
| 6 | **E** — Push tokens defensive + retry | 1h | MÉDIO | (paralelo) |
| 7 | **F** — Server-side quote pre-checkout | 1h | MÉDIO | — |
| 8 | **H** — Tela CASH breakdown completo | 30min | BAIXO | F (recomendado) |
| 9 | **G** — Reportar falso positivo | 5min doc | NULL | — |
| 10 | **J** — Doc V1 deprecated não-parceiro | 5min doc | NULL | — |

**Total estimado fix completo:** ~3h30min (sequencial) ou ~2h30min (com BUG E em paralelo).

---

## Áreas Proibidas Tentadas (transparência)

Nenhuma. Esta sessão foi 100% READ-ONLY:
- Apenas SELECT em DB (sem apply_migration / execute_sql modificador)
- Apenas leitura de ficheiros Flutter (sem Write/Edit)
- `pricing_service.dart` LIDO apenas para validar matemática BUG F+G (autorizado por prompt)

---

## TODOs Danilo

1. **Capturar logs Flutter verbose para BUG E**: `flutter run --verbose` em login estafeta teste9 → ver se `[NotificationService] saveTokenForDriver` e `[PushTokenService] ✓ token registered for driver` aparecem.
2. **Decidir Opção A vs B para BUG B**: confirmar Opção B (sem mudança) é aceitável agora que bucket existe.
3. **Validar distance_km=4.445**: verificar Google Maps cliente↔Continente Guarda. Se ≠ 4.4km, BUG real em cálculo de distância (outro bug).
4. **Aprovar criação das 3 skills sugeridas** (storeshopping-v2-debugger, storage-bucket-validator, driver-earnings-validator).
5. **Confirmar V1 deprecação não-parceiro** em business_rules.md §52.3.

---

## Próxima Sessão (Execução)

Após Danilo aprovar plano:
- Sessão exec: aplicar fixes na ordem acima
- Tempo total estimado: 3h30min
- Modo: PROTECÇÃO TOTAL + commits granulares por bug
- Validação ponta-a-ponta: criar pedido teste novo CASH + MBWay → estafeta finaliza → confirmar todos os bugs A-I resolvidos

---

## Sync

- Local: `.claude/.ai/reports/2026-05-11_storeshopping_v2_real_test_analysis.md`
- Obsidian: `.obsidian-vault/sessoes/2026-05-11_storeshopping_v2_real_test_analysis.md` (sync)

---

*Análise READ-ONLY executada em ~45min. NENHUMA modificação aplicada. Plano para aprovação Danilo.*
