# README — update-platform-setting

Altera **uma** chave de `platform_settings` com dry-run, auditoria e nota ADR.

## Ambiente (.env)
`SUPABASE_URL`, `SUPABASE_ANON_KEY`, `SUPABASE_SERVICE_ROLE_KEY`, `BORA_ADMIN_USER_ID`,
`BORA_ADMIN_EMAIL`.

## Uso
```bash
python scripts/show_setting.py --key reservation_prepayment_cents
python scripts/update_setting.py --key reservation_prepayment_cents --value 400 --reason "..."          # dry-run
python scripts/update_setting.py --key reservation_prepayment_cents --value 400 --reason "..." --commit
```

## Scripts
| script | função |
|--------|--------|
| `_shared.py` | motor S1 (Ctx/log) + `audit_log` + `REPO_ROOT` |
| `show_setting.py` | valor/descrição/categoria atuais + chaves relacionadas |
| `update_setting.py` | dry-run (SQL+impacto) / `--commit` (UPDATE + auditoria + nota ADR) |

## Regras
- `--value` = **JSON** (`400`, `0.15`, `true`, `"texto"`, `{"a":1}`). A coluna é `jsonb`.
- **Chaves blindadas** (contêm `stripe_`/`dispatch_`/`pricing_`/`commission_`/`fee_`) exigem
  `--i-know-what-im-doing`.
- `--commit` cria nota em `.claude/.ai/knowledge/decisions/{data}-update-setting-{key}.md`
  (path relativo a `bora_app/`; criado se não existir).
- Confirmar SEMPRE com o Danilo antes de `--commit` (é regra de negócio).
