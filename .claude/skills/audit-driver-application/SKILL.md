---
name: audit-driver-application
description: Revê candidatura de estafeta (drivers.approval_status='pending') — valida NIF/IBAN/telefone/fotos, gera relatório PT-BR e aprova/rejeita com auditoria em admin_audit_log. Dry-run por defeito; --commit escreve.
metadata:
  type: auditor
  category: driver
  depends_on: bora-knowledge
  uses_edge_fns: []
  version: 1.0.0
---

# Audit Driver Application

Revê e decide candidaturas de estafeta. **Não existe** Edge Fn de aprovação
(verificado via MCP `list_edge_functions`) → a decisão é `UPDATE` direto via
service_role + registo em `admin_audit_log`.

## Pré-requisitos (LER bora-knowledge ANTES de agir)
1. `bora-knowledge/knowledge/05-business-rules.md`
2. `bora-knowledge/knowledge/07-database-key-tables.md` (schema `drivers`)
3. `bora-knowledge/knowledge/10-protected-zones.md` (intocáveis)

## Variáveis de ambiente
`SUPABASE_URL`, `SUPABASE_ANON_KEY`, `SUPABASE_SERVICE_ROLE_KEY`,
`BORA_ADMIN_USER_ID` (uuid do admin, p/ auditoria), `BORA_ADMIN_EMAIL` (opcional).

## Modos
- **DEFAULT (dry-run)**: lê e gera relatório `_preview/driver_<id>.md`. NÃO escreve.
- **`--commit`** (em `decide.py`): aplica a decisão na DB + auditoria.

```bash
python scripts/list_pending.py                                   # candidaturas pendentes
python scripts/inspect_driver.py --driver-id <uuid>              # relatório detalhado (dry-run)
python scripts/decide.py --driver-id <uuid> --action approve --commit
python scripts/decide.py --driver-id <uuid> --action reject --reason-code docs_invalidos --reason "CC ilegível" --commit
```

## Pipeline (inspect_driver.py)
1. Ler bora-knowledge 05/07/10.
2. `SELECT` driver por `--driver-id` ou `--email` (service_role).
3. Campos obrigatórios não-nulos: name, phone, nif, iban, document_number,
   document_photo_url, vehicle_photo_url, registration_selfie_url, address,
   consent_accepted_at, submitted_at.
4. Validações (`validate_docs.py`): NIF mód-11, IBAN `^PT\d{21}$`, telefone PT.
   Idade: **não verificável** a partir do nº de CC (não codifica DOB) → aviso manual.
5. Fotos (`check_photos.py`): HEAD HTTP às 3+ URLs → 200 = OK.
6. Relatório PT-BR (✅/⚠️/❌ + links Storage + sugestão final).

## Decisão (decide.py)
- **approve**: `UPDATE drivers SET approval_status='approved', approved_at=now(),
  approved_by=:admin, reviewed_at=now()`.
- **reject**: `UPDATE drivers SET approval_status='rejected', rejection_reason=:reason,
  approved_by=:admin, reviewed_at=now()`.
- Auditoria: linha em `admin_audit_log` (action `driver_application_approved|rejected`).
- **Idempotente**: já no estado pretendido → mensagem informativa, exit 0.

## Salvaguardas
- Sem `--commit` → só relatório, NÃO toca DB.
- NÃO altera `token_balance`, `priority_until`, `is_online`, `is_banned`.
- NÃO mexe em pricing_service nem dispatch.
- Toda decisão regista quem (`BORA_ADMIN_USER_ID`) / quando (now()) / razão.
