---
name: audit-partner-application
description: Revê candidatura de parceiro (restaurants.approval_status='pending') — valida NIF/IBAN/business_hours/lat-lng/categoria/assets, gera relatório PT-BR e aprova/rejeita com auditoria em admin_audit_log. Dry-run por defeito; --commit escreve.
metadata:
  type: auditor
  category: partner
  depends_on: bora-knowledge
  uses_edge_fns: []
  version: 1.0.0
---

# Audit Partner Application

Revê e decide candidaturas de parceiro (restaurantes/lojas/farmácias). **Não existe**
Edge Fn de aprovação (verificado via MCP) → decisão por `UPDATE` direto (service_role)
+ `admin_audit_log`.

## Pré-requisitos (LER bora-knowledge ANTES de agir)
1. `bora-knowledge/knowledge/05-business-rules.md`
2. `bora-knowledge/knowledge/07-database-key-tables.md` (schema `restaurants`)
3. `bora-knowledge/knowledge/10-protected-zones.md`

## Ambiente
`SUPABASE_URL`, `SUPABASE_ANON_KEY`, `SUPABASE_SERVICE_ROLE_KEY`,
`BORA_ADMIN_USER_ID`, `BORA_ADMIN_EMAIL` (opcional).

## Modos
```bash
python scripts/list_pending.py
python scripts/inspect_partner.py --restaurant-id <text-id>      # relatório (dry-run)
python scripts/decide.py --restaurant-id <text-id> --action approve --commit
python scripts/decide.py --restaurant-id <text-id> --action reject --reason-code docs_invalidos --reason "..." --commit
```

## Pipeline (inspect_partner.py)
1. Ler bora-knowledge 05/07/10.
2. `SELECT` restaurante por `--restaurant-id` (id TEXT) ou `--email`.
3. Obrigatórios: name, address, phone, nif, iban, owner_doc_url, photo_url (logo),
   hero_image_url (capa), category, lat, lng, business_hours, submitted_at.
4. Validações:
   - NIF mód-11, IBAN `^PT\d{21}$`.
   - `business_hours` JSONB: 7 dias (mon..sun), cada com `open`/`close` em `hh:mm`.
   - lat/lng dentro do continente PT (36.9–42.2 / -9.6…-6.2).
   - `category ∈ {restaurant, supermarket, store, pharmacy}` (enum DB em inglês).
   - **licenca_infarmed**: validação **condicional** — só se a coluna existir
     (verificado via `information_schema`). Hoje **NÃO existe** → anota pendência.
5. Assets (`check_assets.py`): HEAD HTTP a logo/capa/docs → 200.
6. Relatório PT-BR `_preview/partner_<id>.md` (✅/⚠️/❌ + sugestão).

## Decisão (decide.py)
- approve/reject: `UPDATE restaurants SET approval_status=..., approved_at/by, reviewed_at, rejection_reason`.
- **NÃO** liga `is_online` (continua a cargo do admin; evita ir live sem querer).
- Auditoria em `admin_audit_log` (id TEXT → `entity_id_text`).
- Idempotente.

## Salvaguardas
- Dry-run default. NÃO mexe em produtos, pricing, dispatch, tokens.
- `is_active_admin` e `is_online` não são tocados aqui.
- Regista quem/quando/razão (D7).
