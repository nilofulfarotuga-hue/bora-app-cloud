# README — audit-partner-application

Skill CLI para rever e decidir candidaturas de parceiro (restaurantes/lojas/farmácias).

## Instalação / ambiente
Idêntico a `audit-driver-application` (mesmo `.env`: SUPABASE_*, BORA_ADMIN_USER_ID).
```bash
python -m venv .venv && .venv\Scripts\activate && pip install -r requirements.txt
```

## Scripts
| script | função |
|--------|--------|
| `_shared.py` | motor S2 (Ctx/log/audit_log) — reutiliza S1 |
| `list_pending.py` | lista `restaurants` com `approval_status='pending'` |
| `validate_docs.py` | NIF/IBAN, business_hours JSONB, lat/lng PT, categoria, licença INFARMED (condicional) |
| `check_assets.py` | HEAD HTTP a logo/capa/owner_doc/activity_doc |
| `inspect_partner.py` | relatório (dry-run) → `_preview/partner_<id>.md` |
| `decide.py` | aprovar/rejeitar (`--commit`) + auditoria |

## Notas / pendências
- `restaurants.id` é **TEXT** → auditoria usa `admin_audit_log.entity_id_text`.
- **`licenca_infarmed` não existe** em `restaurants` (verificado via MCP). Validação é
  condicional; se a coluna for adicionada no futuro, passa a ser verificada. Pendência
  pré-launch: considerar coluna `licenca_infarmed` ou tabela `pharmacy_licenses`.
- `decide.py` não liga `is_online` (ir live é decisão separada do admin).
