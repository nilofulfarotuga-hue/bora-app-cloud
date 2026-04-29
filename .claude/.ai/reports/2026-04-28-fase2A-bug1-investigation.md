# FASE 2 · PARTE A.1 — Investigação BUG 1 (aprovar estafeta)

> **Data:** 2026-04-28
> **Estado:** ⏸ AGUARDA OK do Danilo para avançar para A.2 (plano)
> **Resumo:** O bug é mais profundo do que se pensava. Há **2 camadas** a bloquear o admin: validação client-side em Dart (já conhecida) **e** RLS server-side em `drivers` (descoberta nova nesta investigação).

---

## 1. Fluxo `_approve` actual — `lib/screens/admin/admin_driver_approval_screen.dart:70-118`

```dart
Future<void> _approve(String driverId) async {
  // 1. find driver in _pending list (in-memory)
  final driver = _pending.firstWhere((d) => d['id'] == driverId, orElse: () => {});

  // 2. Build "missing" list
  final missing = <String>[];
  if (photo_url empty)         missing.add('Foto pessoal');
  if (document_photo_url empty) missing.add('Foto do documento');
  if (document_number empty)   missing.add('Número do documento');
  if (vehicle_type != 'bicycle' && vehicle_photo_url empty) missing.add('Foto do veículo');

  // 3. CAMADA 1 (client) — early return with snackbar
  if (missing.isNotEmpty) {
    ScaffoldMessenger.of(context).showSnackBar(... 'Falta: ...' ... red);
    return;
  }

  // 4. UPDATE direct on drivers (no RPC)
  try {
    await Supabase.instance.client.from('drivers').update({
      'approval_status': 'approved',
      'approved_at':     now(),
      'approved_by':     auth.currentUser?.id,
    }).eq('id', driverId);
    _load();
  } catch (e) {
    showSnackBar('Erro ao aprovar: $e');
  }
}
```

**Observações sobre o ponto 4:** UPDATE directo via PostgREST, **não passa por nenhuma RPC**. O único RPC chamado pelo painel admin actualmente é `admin_dashboard_metrics` (read-only).

---

## 2. **DESCOBERTA NOVA — CAMADA 2 (server, RLS)**

A tabela `public.drivers` tem RLS **enabled** com 3 policies:

| Policy | Operação | Condição |
|---|---|---|
| `drivers_insert_own` | INSERT (`a`) | NULL (sem condição USING/WITH CHECK explícita aqui) |
| `drivers_select_authenticated` | SELECT (`r`) | `auth.uid() IS NOT NULL` |
| **`drivers_update_own`** | **UPDATE (`w`)** | **`user_id = auth.uid()`** ⚠️ |

**Implicação directa:**
> Mesmo que o admin remova o early return Dart, o UPDATE falharia silenciosamente porque o admin **não é** o `user_id` do driver. PostgREST devolve **204 No Content** mesmo quando a RLS filtra todas as rows — não é tratado como erro pelo cliente, e o `_load()` mostra que o driver continua `pending`. Isto explica perfeitamente o "voltou em silêncio" reportado.

**Não existe** policy que dê acesso a admin (nem por email allowlist, nem por `bora_role='admin'` no JWT).

---

## 3. Prova empírica: 3 drivers approved, mas ZERO foram aprovados pelo painel

```sql
SELECT approval_status, count(*), count(approved_by), count(approved_at)
FROM public.drivers GROUP BY approval_status;

approval_status | total | with_approved_by | with_approved_at
----------------+-------+------------------+-----------------
approved        |     3 |                0 |               0
pending         |     1 |                0 |               0
```

→ **Todos os 3 approveds têm `approved_by=NULL` e `approved_at=NULL`.** Isto é prova *empírica* de que **nenhum driver alguma vez foi aprovado via o painel admin** desde que estas colunas existem (foram seeded ou aprovados via SQL directo, postgres role bypassa RLS).

---

## 4. Prova adicional via logs Supabase API (24h)

Todos os PATCH `/rest/v1/drivers` na janela são para **um único driver-id** `519d0782-88f9-4a5f-8249-8bdae11de7a8` (o app driver a actualizar `is_online` etc — `auth.uid() = user_id` para esse, RLS deixa passar). Nenhum PATCH para outros driver-ids → **nenhuma evidência de admin a tentar aprovar terceiros**. Mesmo se houvesse tentativas, voltariam 204 silenciosamente.

---

## 5. Constraints e schema relevantes

- `approval_status` — TEXT, NOT NULL, default `'pending'`. CHECK: `IN ('pending', 'approved', 'rejected')`. Manter.
- `approved_at` — timestamptz, nullable. Populado pelo Dart com `now().toUtc()`.
- `approved_by` — uuid, nullable. Populado pelo Dart com `auth.currentUser?.id`.
- `rejection_reason` — text, nullable. Populado em `_reject` via dialog com motivo.
- Sem triggers em `drivers` (verificado).

---

## 6. Mapa COMPLETO dos pontos de validação no fluxo de approval

| # | Camada | Localização | O que verifica | Falha gera |
|---|---|---|---|---|
| 1 | **Frontend (Dart)** | `admin_driver_approval_screen.dart:75-103` | `photo_url`, `document_photo_url`, `document_number`, `vehicle_photo_url` (se não bicycle) | SnackBar vermelho + early return |
| 2 | **Frontend (Dart, segundo ponto de entrada)** | `admin_drivers_screen.dart:50-55, 113-115` | **NADA** — `_updateStatus(driverId, newStatus)` faz UPDATE directo sem validação client-side | (passa para camada 3) |
| 3 | **Network (PostgREST)** | UPDATE `/rest/v1/drivers?id=eq...` | — | 204 No Content em qualquer caso (sucesso ou rows=0) |
| 4 | **Server (RLS policy)** | `drivers_update_own (USING user_id = auth.uid())` | que o utilizador autenticado é o **dono** da row | row ignorada silenciosamente; admin nunca passa esta camada |
| 5 | **Server (CHECK constraint)** | `drivers_approval_status_check` | `approval_status IN ('pending','approved','rejected')` | erro 23514 (improvável: o código só envia valores válidos) |
| 6 | **Audit log** | (nada) | — | nenhum registo de quem aprovou/rejeitou |

**Notas:**
- Há **2 caminhos** no painel para "aprovar" um driver: `admin_driver_approval_screen` (com validação Dart) e `admin_drivers_screen` (sem validação Dart). Ambos partem na **mesma RLS** (camada 4).
- A camada 6 (audit) não existe ainda para approval. Já temos a infra (`AdminAuditService`/`log_admin_action`) da Fase 1, falta só wire.

---

## 7. Estado de pré-condições para a solução (Fase 1 já entregou)

| Pré-condição | Estado | Evidência |
|---|---|---|
| `bora_role='admin'` para `nilofulfarotuga@gmail.com` | ✅ | confirmado em SQL — sessão Fase 1 |
| Trigger `trg_protect_admin_bora_role` activo | ✅ | confirmado em SQL — sessão Fase 1 |
| RPC `log_admin_action` SECURITY DEFINER em produção | ✅ | smoke test pass — Fase 1 |
| `AdminAuditService.logAction(...)` Dart helper | ✅ | em uso em `admin_partners_screen` |
| `auth.email()` legível por SECURITY DEFINER RPC | ✅ | usado em `log_admin_action` |

---

## 8. Diagnóstico final

O bug 1 não é apenas "early return Dart". É um **bug de duas camadas** onde a UI dá feedback de erro útil só quando docs faltam (camada 1), mas mesmo com docs completos o sistema **falha silenciosamente** porque a RLS bloqueia (camada 4). Isto significa que **o painel admin nunca aprovou um driver em produção** — todos os approveds têm `approved_by` nulo.

Qualquer solução tem de resolver as **duas camadas** simultaneamente. Solução parcial (só mexer na camada 1) deixa o bug ainda activo.

---

## 9. Espaço para discussão (apresentar plano em A.2)

A solução natural é uma **RPC `admin_approve_driver(...)` com `SECURITY DEFINER`** que:
- Verifica `bora_role='admin'` no JWT (gate server-side)
- Aceita parâmetro `force boolean` para o caso de docs faltarem
- Faz UPDATE bypassando RLS (porque é DEFINER)
- Chama `log_admin_action('driver_approve' ou 'driver_force_approve')` automaticamente
- Retorna o novo estado para o cliente confirmar

E em paralelo:
- `admin_driver_approval_screen.dart` — mostrar modal de confirmação dupla quando docs faltam ("Faltam X documentos. Tens a certeza?") em vez de early return; chamar a RPC.
- `admin_drivers_screen.dart` — remover o atalho `_updateStatus` (ou redirigi-lo para a mesma RPC) para evitar bypass de auditoria.

Mas isto é **A.2** — deixo para o próximo passo. Aguardo OK antes de detalhar.

---

## Pergunta ao Danilo

Confirmas a investigação? Se sim, **OK para A.2** que vou propor:
1. Migration: nova RPC `public.admin_approve_driver(driver_id, force, justification)` SECURITY DEFINER + gate `bora_role='admin'` + audit log integrado.
2. Edits Dart cirúrgicos em ambos os ecrãs admin.
3. Plano de validação SQL+logs.
