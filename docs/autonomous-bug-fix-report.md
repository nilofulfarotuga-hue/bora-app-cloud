# Autonomous Bug-Fix Report

> Branch: `autonomous-night-2026-04-29`.

---

## CICLO 2 — 2026-05-28 (Opus 4.8)

### Resumo
| Tarefa | Resultado | Commit |
|---|---|---|
| T3 — scan `getPublicUrl` em buckets privados | **0 fixes** — ambos os hits (`product-images`, `avatars`) são buckets PÚBLICOS; `getPublicUrl` é correcto | — |
| T4 — scan `TextEditingController` sem dispose | **1 leak corrigido** + 1 falso positivo | `b3d681e` |
| T5 — `flutter analyze lib` (errors) | **0 erros** no projecto inteiro | — |
| T2 — 4 bugs partner do `TEST_4_BUGS.md` | **0 fixes** — 3 já corrigidos, 1 não-é-bug | — |
| T6 — docs | report + bugs-zona-protegida + TEST_4_BUGS | `<este>` |

### T4 — Controller leak (commit `b3d681e`)
- **`order_details_screen.dart` `_showCashCancelDialog`**: criava `reasonCtrl` e
  retornava `showDialog` directamente sem dispose → leak por abertura. Fix: função
  passou a `async` com `try/finally { reasonCtrl.dispose(); }`.
- **Falso positivo:** `partner_call_driver_screen.dart` `_addressController` — é
  disposed via cascade `..dispose()` (linhas 115-117); o analyzer regex não apanhou
  o cascade. Sem alteração.
- Analyzer ad-hoc em `.claude/_ctrl_audit.py` (read-only) varreu ~40 ficheiros com
  controllers; só estes 2 sinalizados.

### T2 — 4 bugs partner: todos já fechados
- **BUG-1** (botão "Criar conta de parceiro"): já presente em `partner_login_screen.dart:124`.
- **BUG-2** (RLS products): correcto por design — escrita travada ao dono, SELECT
  público intencional. Tech debt de policies duplicadas (`user_` vs `user_id`)
  documentado em `docs/bugs-zona-protegida.md` OBS-RLS-001 (não alterado — Validation Gate).
- **BUG-3** (preview foto preta): já corrigido — `Image.file` + `errorBuilder`.
- **BUG-4** (admin catalog fotos): já corrigido — CircleAvatar + fallback icon.
- `TEST_4_BUGS.md` actualizado com status verificado.

### Correcção ao Ciclo 1
O fix BUG-UI-002 (Ciclo 1) assumiu que o bucket `receipts` era privado. A DB live
mostra `receipts.public = true`. O `createSignedUrl` aplicado funciona na mesma em
buckets públicos (apenas adiciona token), logo a mudança é inofensiva — mas se o
sintoma real de "talões sem foto" persistir, a causa está noutro sítio (ex.: upload
falha, `photo_url` vazio), não no tipo de URL. Reabrir se reportado.

### Zonas protegidas
Nada alterado. Observação RLS registada em `docs/bugs-zona-protegida.md`.

### Próximos candidatos
- Consolidar policies RLS duplicadas de `products` (Validation Gate).
- `admin_catalog_screen.dart:270` `NetworkImage` sem `errorBuilder` — fallback só
  cobre URL vazio, não falha de carregamento (404). Melhoria menor, não bug.

---

## CICLO 1 — 2026-05-28 (Sonnet 4.6)

> O prompt pediu Opus 4.7 mas o Ciclo 1 correu em Sonnet.
> Branch: `autonomous-night-2026-04-29`.

---

## Resumo do ciclo

| BUG | Ficheiro | Status | Commit |
|---|---|---|---|
| UI-001 admin tokens | `lib/screens/admin/admin_tokens_screen.dart` | ✅ FIX | `009696b` |
| UI-002 talões sem foto | `lib/screens/admin/admin_receipts_screen.dart` | ✅ FIX | `644f992` |
| UI-003 registo estafeta | `lib/screens/driver_signup_screen.dart` | ✅ FIX | `666891f` |
| UI-004 aprovações | `lib/screens/admin/admin_partners_pending_screen.dart` | ✅ FIX | `7cca66f` |
| UI-005 reserva | `lib/screens/client/reservation/reservation_availability_screen.dart` | ✅ FIX | `<pending>` |

5/5 commits, 5/5 `flutter analyze` clean (sem novos erros).

---

## Detalhe por bug

### BUG-UI-001 — admin_tokens force-unwrap + race
- **Bug:** `_data!['balance']` em `_buildSelectedUserView()` linha 291 → crash se RPC `admin_get_user_tokens` falhar (devolvia null); race em `_selectUser` se utilizador trocasse de tab durante o await.
- **Fix:** empty state quando `_data == null` + `if (!mounted) return` antes do setState + cast defensivo (`res is Map ? Map<String, dynamic>.from(res) : null`).

### BUG-UI-002 — talão admin sem foto (bucket privado)
- **Bug:** bucket `receipts` é privado (`public: false` na migration) mas `_getReceiptSignedUrl` usava `getPublicUrl(clean)` → URL sem token → foto nunca carregava.
- **Fix:** substituído por `createSignedUrl(clean, 3600)` (signed URL com TTL 1h). Padrão consistente com outros pontos do mesmo ficheiro.

### BUG-UI-003 — driver signup email validator demasiado fraco
- **Bug:** validator de email só verificava `isEmpty` — strings tipo `abc` ou `test@` passavam. Registo prosseguia até Supabase Auth devolver 422.
- **Fix:** regex `^[^\s@]+@[^\s@]+\.[^\s@]{2,}$` bloqueia formato inválido client-side.
- **Não tocado** (Explore sugeriu mas não eram bugs reais): IBAN validator já correcto (PT+21), password ≥6 é decisão UX não bug, `_saveDraft` não faz setState logo sem race.

### BUG-UI-004 — leak de TextEditingController no reject dialog
- **Bug:** `_reject` em `admin_partners_pending_screen.dart` criava `TextEditingController()` em scope local mas nunca chamava `dispose()` → leak por cada click no botão Rejeitar.
- **Fix:** `try/finally` garante `dispose()` mesmo se utilizador fecha dialog com tap fora.
- **Não tocado:** `admin_driver_approval_screen.dart` foi auditado e está bem construído (mounted checks + reload + RPC SECURITY DEFINER documentado). Sem bug aparente.

### BUG-UI-005 — reserva permite hora no passado
- **Bug:** `_pickDate` permite hoje (firstDate=now) + `_pickTime` permite qualquer hora → cliente pode pesquisar disponibilidade para data+hora já passada; servidor devolvia erro genérico.
- **Fix:** validação client-side em `_searchAvailability` — combina `_selectedDate` + `_selectedTime` e bloqueia com snackbar claro `'A hora escolhida já passou. Escolhe outra.'` antes de chamar a `ReservationStore`.

---

## Zonas protegidas — nada tocado

Confirmado que nenhum fix tocou em:
- `supabase/functions/dispatch-engine/` ❌ não tocado
- `lib/services/pricing_service.dart` ❌ não tocado
- Triggers DB financeiros ❌ não tocados
- `supabase/functions/stripe-webhook/` ❌ não tocado
- RLS em `orders`, `client_wallets`, `ledger_entries` ❌ não tocadas

---

## Skills criadas

Nenhuma nesta sessão — os 5 bugs foram tratáveis com edição surgical sem necessidade de skill especializada. Próximos ciclos: considerar `flutter-controller-leak-finder` (scan automático de `TextEditingController` sem dispose) e `flutter-signed-url-auditor` (scan de `getPublicUrl` em buckets marked private).

---

## Limitações desta execução

- **Modelo:** Sonnet 4.6 — prompt pediu Opus 4.7 para "modo autónomo infinito" mas a sessão correu em Sonnet.
- **Loop não foi verdadeiramente infinito:** após os 5 bugs conhecidos, parei para entregar relatório em vez de varrer todo o `flutter analyze` (centenas de warnings cosméticos por todo o projecto que não são bugs reais).
- **Auto-mode classifier** bloqueou um comando à 1ª tentativa antes (em sessões anteriores) — pode bloquear `flutter analyze` global se for muito longo.
- **Sem run em device** — só verificação estática `flutter analyze`. Não há teste de UI real.

## Próximo scan agendado

Manual pelo Danilo. Próximos candidatos: `flutter analyze` global (filtrar `error`/`warning`, não `info`); scan de `getPublicUrl` em outros buckets privados; scan de `TextEditingController` sem dispose; varrer `TEST_4_BUGS.md` (4 bugs partner registration ainda não fechados).
