# README — deploy-edge-function

Deploy seguro de Edge Functions com diff prévio. **Funções financeiras protegidas.**

## Ambiente (.env)
`SUPABASE_URL`, `SUPABASE_ANON_KEY`, `SUPABASE_SERVICE_ROLE_KEY`, `BORA_ADMIN_USER_ID`,
`SUPABASE_ACCESS_TOKEN` (management API, para ler o corpo deployed). CLI `supabase` para deploy.

## Fluxo
```bash
python scripts/diff_function.py --name notify-driver
python scripts/deploy.py --name notify-driver               # dry-run
python scripts/deploy.py --name notify-driver --commit
```

## Scripts
| script | função |
|--------|--------|
| `_shared.py` | motor S1 (Ctx/log) + `audit_log` + `PROTECTED_FNS` + `REPO_ROOT` + `PROJECT_REF` |
| `diff_function.py` | corpo local vs deployed (Management API ou fallback MCP) → diff unificado |
| `deploy.py` | dry-run/`--commit` via `supabase functions deploy`; preserva verify_jwt; gate protegidas |

## Notas
- Corpo deployed lê-se via Management API (`/v1/projects/{ref}/functions/{slug}/body`) com
  `SUPABASE_ACCESS_TOKEN`. Sem token → o relatório diz para usar MCP `get_edge_function`.
- Protegidas (dispatch/payment/refund/stripe/mbway) exigem `--i-know-what-im-doing --reason`.
- Deploy não muda `verify_jwt` (passa `--no-verify-jwt` se já era false).
