# FASE 2 · PARTE A.2 — Plano detalhado para resolver BUG 1

> **Data:** 2026-04-28
> **Estado:** ⏸ AGUARDA OK FINAL DO DANILO antes de apply (A.3)
> **Substitui:** parte da direcção indicada no fim do A.1
> **Alcance:** approve + reject (justificação no §1) · ban/reactivate/edit/forceLogout ficam para Fase 3 (BUG 2)

---

## 1. Decisão arquitectural — RPCs focadas vs RPC genérica

**Recomendação: RPCs focadas (Opção a).** Justificação:

| Critério | Focadas | Genérica |
|---|---|---|
| Validações específicas (force em approve; reason obrigatório em reject; duration em ban) | ✅ cada RPC trata o seu | ❌ if/elseif gigante dentro |
| Audit log expressivo (`driver_approve`, `driver_force_approve`, `driver_reject`, `driver_ban`) | ✅ semantics claras | ❌ acaba em `driver_status_change` genérico |
| Erros pelo lado do cliente | ✅ `RAISE EXCEPTION 'missing_docs: …'` específico | ❌ erro genérico requer parsing de payload |
| Code surface | n RPCs (1 por verbo, ~50 linhas cada) | 1 RPC (~150 linhas) | RPCs focadas têm mais files mas menos branching cyclomatic |
| Reuso | helper privado `_admin_op_guard()` para gate | shared dentro do switch | empate |
| Risco de "Swiss army knife" | ✅ baixo | 🚨 alto, vide history de outros backends |

**Trade-off aceito:** mais migrations no futuro (1 por novo verbo). Compensa com clareza e auditoria semântica.

### Alcance desta task: approve **+** reject

Por que **incluir reject**: o `_reject` actual em `admin_driver_approval_screen.dart:120-162` faz UPDATE directo igualzinho ao `_approve` — **também é silenciosamente bloqueado pela RLS `drivers_update_own`**. Resolver só approve deixaria reject quebrado e o próprio fluxo de "aprovações" parcial. Os 2 verbos formam um **par natural** do mesmo workflow (Pendentes → Aprovados / Rejeitados).

### Alcance da Fase 3 (BUG 2 do relatório-mãe)

`admin_ban_driver`, `admin_reactivate_driver`, `admin_edit_driver`, `admin_force_logout_driver` — quando chegarmos ao painel de "Estafetas aprovados sem acções" do roadmap.

---

## 2. Migration M1 — Reconciliação dos 3 legacy seeds

### Estado actual

```
SELECT id, name, approval_status, approved_at, approved_by
FROM drivers WHERE approval_status='approved';
→ 3 rows, todas com approved_at=NULL e approved_by=NULL
```

### Justificação para popular `approved_at = created_at`

- **Honestidade temporal:** `created_at` é a única data verificável. Faz sentido como proxy de "quando ficaram approved" porque na ausência de qualquer evidência de approval admin posterior, presume-se que foram seedados/inseridos já como approved.
- **`approved_by` continua `NULL`:** isto é honesto — não houve humano. Diferenciar de approveds futuros (que terão approved_by populado) permite auditoria limpa.
- **Audit log com flag `legacy_seed`:** 1 row em `admin_audit_log` por driver, com `admin_id=NULL`, `admin_email='system@migration'`, `action='driver_legacy_seed_marked'`, `details={driver_id, driver_name, approved_at_set_to, reason: 'pre-existing approveds with NULL audit fields, reconciled via migration 20260428xxx'}`.

### Alternativa rejeitada — coluna `is_legacy_seed BOOLEAN`

Adicionar coluna em `drivers` é over-engineering: o sinal está implícito em `approved_by IS NULL AND approved_at IS NOT NULL`. Sem nova coluna, sem novo lugar a manter.

### Alternativa rejeitada — deixar `approved_at` NULL e só logar

Queries de relatórios (e.g. dashboards) frequentemente filtram por `approved_at IS NOT NULL`. Deixar NULL trataria os 3 seeds como "ainda não aprovados" em vários sítios. Popular evita esta ambiguidade.

### SQL exacto da Migration M1

```sql
BEGIN;

-- 1) Update legacy seeds — only those that are approved AND have null audit fields
UPDATE public.drivers
SET approved_at = created_at
WHERE approval_status = 'approved'
  AND approved_at IS NULL
  AND approved_by IS NULL
  AND created_at IS NOT NULL;

-- 2) One audit row per reconciled legacy seed
-- We INSERT directly because (a) postgres role bypasses the RLS,
-- (b) we want admin_id=NULL to honestly mark "no human did this".
INSERT INTO public.admin_audit_log
  (admin_id, admin_email, action, entity_type, entity_id, details)
SELECT
  NULL,
  'system@migration',
  'driver_legacy_seed_marked',
  'driver',
  d.id,
  jsonb_build_object(
    'driver_name', d.name,
    'approved_at_set_to', d.approved_at,
    'reason',
      'Pre-existing approved drivers had approved_at/approved_by NULL '
      || '(seeded or inserted via SQL bypassing the never-working admin '
      || 'panel UPDATE path). Reconciled by migration 20260428000002.'
  )
FROM public.drivers d
WHERE d.approval_status = 'approved'
  AND d.approved_by IS NULL
  AND d.approved_at = d.created_at;  -- only the rows we just updated

COMMIT;
```

### Risco e reversão

- **Risco:** baixo. Não muda `approval_status`, `approved_by` ou `rejection_reason`. Só popula `approved_at`.
- **Reverter:** `UPDATE drivers SET approved_at = NULL WHERE approved_by IS NULL AND approval_status='approved' AND id IN (<3 ids>); DELETE FROM admin_audit_log WHERE action='driver_legacy_seed_marked';`

---

## 3. Migration M2 — RPCs `admin_approve_driver` e `admin_reject_driver`

### 3.1 Helper interno privado (factor-out do gate)

```sql
CREATE OR REPLACE FUNCTION public._admin_op_guard()
RETURNS TABLE (admin_id UUID, admin_email TEXT)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_uid   UUID;
  v_email TEXT;
  v_role  TEXT;
BEGIN
  v_uid := auth.uid();
  IF v_uid IS NULL THEN
    RAISE EXCEPTION 'admin_required: not authenticated' USING ERRCODE = '42501';
  END IF;

  v_email := COALESCE(auth.jwt() ->> 'email',
                      auth.jwt() -> 'user_metadata' ->> 'email');

  v_role := COALESCE(auth.jwt() -> 'user_metadata' ->> 'bora_role',
                     auth.jwt() ->> 'role');

  IF v_role <> 'admin' THEN
    RAISE EXCEPTION 'admin_required: caller bora_role=% (need admin)', v_role
      USING ERRCODE = '42501';
  END IF;

  RETURN QUERY SELECT v_uid, v_email;
END;
$$;

REVOKE ALL ON FUNCTION public._admin_op_guard() FROM public, anon;
GRANT EXECUTE ON FUNCTION public._admin_op_guard() TO authenticated;

COMMENT ON FUNCTION public._admin_op_guard() IS
  'Internal guard: ensures the caller is authenticated AND has bora_role=admin. Returns the admin uid + email for use by callers.';
```

### 3.2 RPC `admin_approve_driver`

```sql
CREATE OR REPLACE FUNCTION public.admin_approve_driver(
  p_driver_id     UUID,
  p_force         BOOLEAN DEFAULT FALSE,
  p_justification TEXT    DEFAULT NULL
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_admin       RECORD;
  v_driver      RECORD;
  v_missing     TEXT[] := ARRAY[]::TEXT[];
  v_was_forced  BOOLEAN := FALSE;
  v_action_name TEXT;
BEGIN
  -- Gate
  SELECT admin_id, admin_email INTO v_admin FROM public._admin_op_guard();

  -- Load driver (within DEFINER, RLS does not apply)
  SELECT * INTO v_driver FROM public.drivers WHERE id = p_driver_id;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'driver_not_found: %', p_driver_id USING ERRCODE = 'P0002';
  END IF;

  IF v_driver.approval_status = 'approved' THEN
    RAISE EXCEPTION 'driver_already_approved: %', p_driver_id USING ERRCODE = '23514';
  END IF;

  -- Validate documents
  IF v_driver.photo_url IS NULL OR length(v_driver.photo_url) = 0 THEN
    v_missing := array_append(v_missing, 'Foto pessoal');
  END IF;
  IF v_driver.document_photo_url IS NULL OR length(v_driver.document_photo_url) = 0 THEN
    v_missing := array_append(v_missing, 'Foto do documento');
  END IF;
  IF v_driver.document_number IS NULL OR length(v_driver.document_number) = 0 THEN
    v_missing := array_append(v_missing, 'Número do documento');
  END IF;
  IF COALESCE(v_driver.vehicle_type, '') <> 'bicycle'
     AND (v_driver.vehicle_photo_url IS NULL OR length(v_driver.vehicle_photo_url) = 0) THEN
    v_missing := array_append(v_missing, 'Foto do veículo');
  END IF;

  IF array_length(v_missing, 1) IS NOT NULL AND NOT p_force THEN
    RAISE EXCEPTION 'missing_docs: %', array_to_string(v_missing, ', ')
      USING ERRCODE = '23502';
  END IF;

  -- Force path requires non-empty justification (audit trail)
  IF p_force AND array_length(v_missing, 1) IS NOT NULL THEN
    IF p_justification IS NULL OR length(trim(p_justification)) = 0 THEN
      RAISE EXCEPTION 'justification_required: force-approve needs justification'
        USING ERRCODE = '23502';
    END IF;
    v_was_forced := TRUE;
  END IF;

  -- Apply update
  UPDATE public.drivers
     SET approval_status  = 'approved',
         approved_at      = now(),
         approved_by      = v_admin.admin_id,
         rejection_reason = NULL
   WHERE id = p_driver_id;

  -- Audit (always; never block on audit failure)
  v_action_name := CASE WHEN v_was_forced THEN 'driver_force_approve' ELSE 'driver_approve' END;
  BEGIN
    PERFORM public.log_admin_action(
      v_action_name,
      'driver',
      p_driver_id,
      jsonb_build_object(
        'driver_name',   v_driver.name,
        'driver_email',  v_driver.email,
        'missing_docs',  to_jsonb(v_missing),
        'was_forced',    v_was_forced,
        'justification', p_justification
      )
    );
  EXCEPTION WHEN OTHERS THEN
    -- Best-effort: don't fail the approve if the log fails.
    RAISE WARNING 'admin_approve_driver: audit log failed: %', SQLERRM;
  END;

  RETURN jsonb_build_object(
    'success',       true,
    'driver_id',     p_driver_id,
    'driver_name',   v_driver.name,
    'was_forced',    v_was_forced,
    'missing_docs',  v_missing,
    'justification', p_justification,
    'approved_at',   now()
  );
END;
$$;

REVOKE ALL ON FUNCTION public.admin_approve_driver(UUID, BOOLEAN, TEXT) FROM public, anon;
GRANT EXECUTE ON FUNCTION public.admin_approve_driver(UUID, BOOLEAN, TEXT) TO authenticated;

COMMENT ON FUNCTION public.admin_approve_driver(UUID, BOOLEAN, TEXT) IS
  'Admin approves a driver. SECURITY DEFINER bypasses drivers_update_own RLS. Validates required documents server-side; if any missing, requires p_force=true AND non-empty p_justification. Records driver_approve OR driver_force_approve in admin_audit_log.';
```

### 3.3 RPC `admin_reject_driver`

```sql
CREATE OR REPLACE FUNCTION public.admin_reject_driver(
  p_driver_id UUID,
  p_reason    TEXT
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_admin  RECORD;
  v_driver RECORD;
BEGIN
  SELECT admin_id, admin_email INTO v_admin FROM public._admin_op_guard();

  IF p_reason IS NULL OR length(trim(p_reason)) < 3 THEN
    RAISE EXCEPTION 'reason_required: rejection needs a reason (min 3 chars)'
      USING ERRCODE = '23502';
  END IF;

  SELECT * INTO v_driver FROM public.drivers WHERE id = p_driver_id;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'driver_not_found: %', p_driver_id USING ERRCODE = 'P0002';
  END IF;

  IF v_driver.approval_status = 'rejected' THEN
    RAISE EXCEPTION 'driver_already_rejected: %', p_driver_id USING ERRCODE = '23514';
  END IF;

  UPDATE public.drivers
     SET approval_status  = 'rejected',
         rejection_reason = trim(p_reason),
         approved_at      = NULL,
         approved_by      = NULL
   WHERE id = p_driver_id;

  BEGIN
    PERFORM public.log_admin_action(
      'driver_reject',
      'driver',
      p_driver_id,
      jsonb_build_object(
        'driver_name',  v_driver.name,
        'driver_email', v_driver.email,
        'reason',       trim(p_reason),
        'previous_status', v_driver.approval_status
      )
    );
  EXCEPTION WHEN OTHERS THEN
    RAISE WARNING 'admin_reject_driver: audit log failed: %', SQLERRM;
  END;

  RETURN jsonb_build_object(
    'success',     true,
    'driver_id',   p_driver_id,
    'driver_name', v_driver.name,
    'reason',      trim(p_reason)
  );
END;
$$;

REVOKE ALL ON FUNCTION public.admin_reject_driver(UUID, TEXT) FROM public, anon;
GRANT EXECUTE ON FUNCTION public.admin_reject_driver(UUID, TEXT) TO authenticated;

COMMENT ON FUNCTION public.admin_reject_driver(UUID, TEXT) IS
  'Admin rejects a driver candidacy. SECURITY DEFINER bypasses RLS. Reason required (>= 3 chars). Records driver_reject in admin_audit_log.';
```

### 3.4 Códigos de erro lançados (para tradução em UI)

| ERRCODE | Mensagem | UI mostra |
|---|---|---|
| `42501` | `admin_required: …` | "Sem permissões de admin." |
| `P0002` | `driver_not_found: …` | "Estafeta não encontrado." |
| `23514` | `driver_already_approved: …` / `driver_already_rejected: …` | "Estafeta já está nesse estado." |
| `23502` (a) | `missing_docs: Foto pessoal, …` | Modal "Faltam: …" + botão "Aprovar mesmo assim" |
| `23502` (b) | `justification_required: …` | "Tens de preencher a justificação." |
| `23502` (c) | `reason_required: …` | "Tens de preencher o motivo de rejeição." |
| outros | `<raw>` | "Erro: <raw>" (fallback) |

---

## 4. Edits Dart linha-a-linha

### 4.1 `lib/screens/admin/admin_driver_approval_screen.dart`

#### Edit 1 — adicionar import de `dart:async` e `AdminAuditService` (audit log fica no servidor agora, mas mantemos o import caso seja útil noutros pontos do ecrã — saltamos AdminAuditService aqui pois a RPC já loga).

```diff
 import 'package:flutter/material.dart';
+import 'package:supabase_flutter/supabase_flutter.dart';
 import '../../config/app_colors.dart';
```

(Confirma se já há os imports certos — se sim, este edit é no-op.)

#### Edit 2 — refazer `_approve(String driverId)` (substitui L70-118)

```dart
Future<void> _approve(String driverId) async {
  // Compute missing docs locally for UI hint only — server is the source of truth.
  final driver = _pending.firstWhere(
    (d) => d['id'] == driverId,
    orElse: () => <String, dynamic>{},
  );
  final missing = _missingDocs(driver);

  bool force = false;
  String? justification;

  if (missing.isEmpty) {
    final ok = await _confirmSimple(
      title: 'Aprovar estafeta?',
      body: 'Vais aprovar ${driver['name'] ?? 'este estafeta'}.',
      confirmLabel: 'Aprovar',
      confirmColor: AppColors.primary,
    );
    if (ok != true) return;
  } else {
    // Force path: dialog with checkbox + justification field
    final result = await _confirmForceApprove(driver: driver, missing: missing);
    if (result == null) return;
    force = true;
    justification = result;
  }

  try {
    final res = await Supabase.instance.client.rpc(
      'admin_approve_driver',
      params: {
        'p_driver_id': driverId,
        'p_force': force,
        'p_justification': justification,
      },
    );
    if (!mounted) return;
    final wasForced = (res is Map && res['was_forced'] == true);
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(wasForced
          ? 'Estafeta aprovado (override admin).'
          : 'Estafeta aprovado.'),
      backgroundColor: wasForced ? Colors.orange.shade700 : AppColors.primary,
    ));
    await _load();
  } on PostgrestException catch (e) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(_humanizeRpcError(e)),
      backgroundColor: Colors.red,
      duration: const Duration(seconds: 5),
    ));
  } catch (e) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text('Erro inesperado ao aprovar: $e'),
      backgroundColor: Colors.red,
    ));
  }
}

List<String> _missingDocs(Map<String, dynamic> driver) {
  final missing = <String>[];
  if ((driver['photo_url'] as String?)?.isEmpty ?? true) missing.add('Foto pessoal');
  if ((driver['document_photo_url'] as String?)?.isEmpty ?? true) missing.add('Foto do documento');
  if ((driver['document_number'] as String?)?.isEmpty ?? true) missing.add('Número do documento');
  final vt = driver['vehicle_type'] as String? ?? '';
  if (vt != 'bicycle' && ((driver['vehicle_photo_url'] as String?)?.isEmpty ?? true)) {
    missing.add('Foto do veículo');
  }
  return missing;
}

Future<bool?> _confirmSimple({
  required String title,
  required String body,
  required String confirmLabel,
  required Color confirmColor,
}) {
  return showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(title),
      content: Text(body),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
        ElevatedButton(
          style: ElevatedButton.styleFrom(backgroundColor: confirmColor),
          onPressed: () => Navigator.pop(ctx, true),
          child: Text(confirmLabel),
        ),
      ],
    ),
  );
}

/// Returns the entered justification on confirm, or null on cancel.
Future<String?> _confirmForceApprove({
  required Map<String, dynamic> driver,
  required List<String> missing,
}) async {
  final controller = TextEditingController();
  bool acknowledged = false;
  return showDialog<String>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setLocal) {
        final justOk = controller.text.trim().length >= 3;
        return AlertDialog(
          title: const Text('Faltam documentos'),
          content: SizedBox(
            width: 360,
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(
                'Vais aprovar ${driver['name'] ?? 'este estafeta'} mesmo sem:',
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 8),
              ...missing.map((m) => Padding(
                padding: const EdgeInsets.only(left: 8, top: 2, bottom: 2),
                child: Text('• $m', style: const TextStyle(color: Colors.red)),
              )),
              const SizedBox(height: 12),
              TextField(
                controller: controller,
                onChanged: (_) => setLocal(() {}),
                maxLines: 2,
                decoration: const InputDecoration(
                  labelText: 'Justificação (obrigatória, mínimo 3 caracteres)',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 8),
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                value: acknowledged,
                onChanged: (v) => setLocal(() => acknowledged = v ?? false),
                title: const Text('Compreendo o risco e quero aprovar mesmo assim.'),
                controlAffinity: ListTileControlAffinity.leading,
              ),
            ]),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, null), child: const Text('Cancelar')),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: Colors.orange.shade800),
              onPressed: (acknowledged && justOk)
                  ? () => Navigator.pop(ctx, controller.text.trim())
                  : null,
              child: const Text('Aprovar mesmo assim'),
            ),
          ],
        );
      },
    ),
  );
}

String _humanizeRpcError(PostgrestException e) {
  final msg = e.message;
  if (msg.startsWith('admin_required'))            return 'Sem permissões de admin.';
  if (msg.startsWith('driver_not_found'))          return 'Estafeta não encontrado (refresca a lista).';
  if (msg.startsWith('driver_already_approved'))   return 'Estafeta já estava aprovado.';
  if (msg.startsWith('driver_already_rejected'))   return 'Estafeta já estava rejeitado.';
  if (msg.startsWith('missing_docs:')) {
    return 'Documentos em falta: ${msg.substring('missing_docs:'.length).trim()}';
  }
  if (msg.startsWith('justification_required')) return 'Tens de preencher a justificação.';
  if (msg.startsWith('reason_required'))        return 'Tens de preencher o motivo de rejeição.';
  return 'Erro: $msg';
}
```

#### Edit 3 — refazer `_reject(String driverId)` (substitui L120-162)

```dart
Future<void> _reject(String driverId) async {
  final controller = TextEditingController();
  final reason = await showDialog<String>(
    context: context,
    builder: (ctx) => StatefulBuilder(builder: (ctx, setLocal) {
      final ok = controller.text.trim().length >= 3;
      return AlertDialog(
        title: const Text('Rejeitar candidatura'),
        content: TextField(
          controller: controller,
          onChanged: (_) => setLocal(() {}),
          maxLines: 3,
          decoration: const InputDecoration(
            labelText: 'Motivo (mín. 3 caracteres)',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, null), child: const Text('Cancelar')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            onPressed: ok ? () => Navigator.pop(ctx, controller.text.trim()) : null,
            child: const Text('Rejeitar'),
          ),
        ],
      );
    }),
  );
  if (reason == null) return;

  try {
    await Supabase.instance.client.rpc('admin_reject_driver', params: {
      'p_driver_id': driverId,
      'p_reason': reason,
    });
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
      content: Text('Candidatura rejeitada.'),
      backgroundColor: Colors.red,
    ));
    await _load();
  } on PostgrestException catch (e) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(_humanizeRpcError(e)),
      backgroundColor: Colors.red,
      duration: const Duration(seconds: 5),
    ));
  } catch (e) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text('Erro inesperado: $e'),
      backgroundColor: Colors.red,
    ));
  }
}
```

### 4.2 `lib/screens/admin/admin_drivers_screen.dart`

Atalhos hoje em L106-135 (modal "Aprovar"/"Rejeitar" só para `pending`). Hoje fazem UPDATE directo, **também silenciosamente bloqueado pela RLS**. Migrar para chamar as RPCs:

#### Edit 4 — `_updateStatus`

```diff
- Future<void> _updateStatus(String driverId, String newStatus) async {
-   try {
-     await Supabase.instance.client
-         .from('drivers')
-         .update({'approval_status': newStatus}).eq('id', driverId);
-     await _load();
-   } catch (e) { /* snackbar */ }
- }
+ // Removed: replaced by direct RPC calls in the bottom-sheet buttons.
+ // Kept _load() reachable.
```

#### Edit 5 — botões do modal de detalhe (L106-135) chamam as novas RPCs

(Reaproveita a mesma logica do screen de approval; importa o helper `_humanizeRpcError` para coerência. Para evitar duplicação posso mover para `lib/services/admin_audit_service.dart` ou criar `admin_rpc_errors.dart` — proponho um pequeno utility.)

**Pequeno utility novo:** `lib/screens/admin/_admin_rpc_errors.dart` (file-private)

```dart
// File-private utility to humanize PostgrestException messages from
// admin_* RPCs. Used by both admin_driver_approval_screen.dart and
// admin_drivers_screen.dart.
import 'package:supabase_flutter/supabase_flutter.dart';

String humanizeAdminRpcError(PostgrestException e) {
  final msg = e.message;
  if (msg.startsWith('admin_required'))          return 'Sem permissões de admin.';
  if (msg.startsWith('driver_not_found'))        return 'Estafeta não encontrado.';
  if (msg.startsWith('driver_already_approved')) return 'Estafeta já estava aprovado.';
  if (msg.startsWith('driver_already_rejected')) return 'Estafeta já estava rejeitado.';
  if (msg.startsWith('missing_docs:')) {
    return 'Documentos em falta: ${msg.substring('missing_docs:'.length).trim()}';
  }
  if (msg.startsWith('justification_required')) return 'Justificação obrigatória.';
  if (msg.startsWith('reason_required'))        return 'Motivo obrigatório.';
  return 'Erro: $msg';
}
```

E o screen `admin_drivers_screen.dart` importa-o e usa a mesma logica do approval screen mas resumida.

---

## 5. Plano de validação

### 5.1 SQL (com setup + cleanup atómico)

| # | Cenário | Setup | Asserção | Cleanup |
|---|---|---|---|---|
| V1 | Admin aprova driver com docs OK | criar driver pending com todos os docs | RPC retorna `success=true, was_forced=false`; `approval_status='approved'`; audit log row `driver_approve` | DELETE driver |
| V2 | Admin tenta aprovar driver com doc em falta sem `force` | driver pending sem `vehicle_photo_url` (e vehicle≠bicycle) | RPC RAISE `missing_docs: Foto do veículo` | DELETE driver |
| V3 | Admin força aprovação sem justificação | driver com docs em falta, `force=true`, `justification=NULL` | RPC RAISE `justification_required` | DELETE driver |
| V4 | Admin força aprovação **com** justificação | mesmo driver, `force=true`, `justification='Conheço pessoalmente'` | RPC retorna `was_forced=true`; audit log `driver_force_approve` com `justification` populada | DELETE driver |
| V5 | Não-admin tenta aprovar | JWT simulado com bora_role='client' | RPC RAISE `admin_required` | — |
| V6 | Admin rejeita driver com motivo válido | driver pending | RPC retorna `success=true, reason=...`; `approval_status='rejected'`; audit log `driver_reject` | DELETE driver |
| V7 | Admin rejeita sem motivo | driver pending, `p_reason=''` | RPC RAISE `reason_required` | DELETE driver |
| V8 | Admin tenta rejeitar driver já rejeitado | driver com `approval_status='rejected'` | RPC RAISE `driver_already_rejected` | DELETE driver |
| V9 | Migration M1 reconciliou os 3 legacy | (estado actual) | depois de M1: `approved_at = created_at` para os 3; `admin_audit_log` tem 3 rows `driver_legacy_seed_marked` | reverter via UPDATE + DELETE rows com action='driver_legacy_seed_marked' |
| V10 | RLS continua a bloquear UPDATE directo (no anti-bypass) | tentar UPDATE com JWT autenticado não-admin via PostgREST simulado | retorna 0 rows afectadas | — |

### 5.2 Logs API (após apply em produção)

- POST `/rest/v1/rpc/admin_approve_driver` aparece (200)
- POST `/rest/v1/rpc/admin_reject_driver` aparece (200)
- PATCH `/rest/v1/drivers?id=eq…` para approval_status DESAPARECE (admin não bate mais directamente)

### 5.3 UI manual (apk dev) — só após apply

- Pendente com docs OK → botão check verde → diálogo "Aprovar?" → sim → SnackBar verde, lista refresca, status=Aprovado
- Pendente com 1 doc em falta → botão check verde → diálogo "Faltam:" + checkbox + justificação → preenche → "Aprovar mesmo assim" → SnackBar laranja "(override admin)"
- Pendente → botão X vermelho → diálogo motivo → preenche → "Rejeitar" → SnackBar vermelho

---

## 6. Plano de rollback

### Se algo correr mal **após** apply

1. **DB rollback (RPCs):** `DROP FUNCTION public.admin_approve_driver(UUID, BOOLEAN, TEXT) CASCADE; DROP FUNCTION public.admin_reject_driver(UUID, TEXT) CASCADE; DROP FUNCTION public._admin_op_guard() CASCADE;`
2. **DB rollback (legacy seed):** `UPDATE public.drivers SET approved_at = NULL WHERE approved_by IS NULL AND approval_status='approved'; DELETE FROM public.admin_audit_log WHERE action='driver_legacy_seed_marked';`
3. **Dart rollback:** `git revert <commit>` no ramo do app.

Importante: a Fase 1 (audit log infra, `is_active_admin`, `bora_role` trigger) **fica intacta** — não é tocada por este rollback.

### Se o user clicar mas RPC falhar inesperadamente

- O Dart trata `PostgrestException` e mostra SnackBar verbose (`_humanizeRpcError`). UI nunca fica "muda". Os erros que conhecemos têm tradução; outros caem no fallback "Erro: <raw>" para o user reportar a mensagem.

### Risco residual

- **Dependência transitiva:** se um dia removermos `bora_role='admin'` do user (e.g. signup overwrite escapar do trigger), ele perde a capacidade de aprovar. Mitigação: o trigger `trg_protect_admin_bora_role` da Fase 1 protege exactamente este cenário. Se ainda assim falhar, é um bug do trigger e abre fronteira para a PARTE B (que precisamos de fazer a seguir).

---

## 7. Itens explicitamente **fora** do scope desta task (para Fase 3)

- `admin_ban_driver`, `admin_reactivate_driver`, `admin_edit_driver`, `admin_force_logout_driver`
- Migrar gate de admin de email-allowlist para JWT em todos os sítios Dart (= PARTE B desta Fase 2)
- Tornar a UI de "Estafetas aprovados" mais útil (BUG 2 do relatório-mãe)

---

## 8. Pergunta ao Danilo

OK para apply nesta ordem?

1. Migration M1 (legacy seed reconciliation)
2. Migration M2 (`_admin_op_guard` + `admin_approve_driver` + `admin_reject_driver`)
3. Edits Dart (3 ficheiros: `admin_driver_approval_screen.dart`, `admin_drivers_screen.dart`, novo `_admin_rpc_errors.dart`)
4. Validação SQL automática (V1–V10)
5. Logs API confirmação

Se OK, avanço para A.3 sem mais paragens. Se quiseres ajustar algum dialog, mensagem, ou alcance — diz agora.
