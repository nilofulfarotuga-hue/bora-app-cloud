# README — audit-driver-application

Skill CLI para rever e decidir candidaturas de estafeta.

## Instalação
```bash
cd bora_app/.claude/skills/audit-driver-application
python -m venv .venv && .venv\Scripts\activate && pip install -r requirements.txt
```

## Ambiente (.env)
| var | uso |
|-----|-----|
| `SUPABASE_URL` | https://ojykpzwqrtusfeakzrna.supabase.co |
| `SUPABASE_ANON_KEY` | apikey das chamadas REST |
| `SUPABASE_SERVICE_ROLE_KEY` | leitura + UPDATE drivers + audit (bypassa RLS) |
| `BORA_ADMIN_USER_ID` | uuid do admin → `admin_audit_log.admin_id` |
| `BORA_ADMIN_EMAIL` | opcional → `admin_audit_log.admin_email` |

## Scripts
| script | função |
|--------|--------|
| `_shared.py` | reutiliza motor S1 (Ctx/log) + `audit_log()` + identidade admin |
| `list_pending.py` | lista `drivers` com `approval_status='pending'` |
| `validate_docs.py` | NIF mód-11, IBAN `^PT\d{21}$`, telefone PT (importável + CLI) |
| `check_photos.py` | HEAD HTTP às URLs de fotos (selfie/doc/veículo) |
| `inspect_driver.py` | relatório detalhado (dry-run) → `_preview/driver_<id>.md` |
| `decide.py` | aprovar/rejeitar (`--commit`) + auditoria |

## Notas
- **Não há Edge Fn de aprovação** → UPDATE direto via service_role (auditado).
- Idade do estafeta **não é verificável** pelo nº de CC (não codifica data de nascimento) → confirmar manualmente.
- Idempotente: decidir um driver já decidido devolve mensagem informativa (exit 0).
