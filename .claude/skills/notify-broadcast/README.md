# README — notify-broadcast

Push em massa segmentada via `push_broadcasts` + Edge Fn `execute-broadcast`.

## Ambiente (.env)
`SUPABASE_URL`, `SUPABASE_ANON_KEY`, `SUPABASE_SERVICE_ROLE_KEY`, `BORA_ADMIN_USER_ID`.

## Fluxo
```bash
python scripts/preview_audience.py --segment clients
python scripts/send.py --segment clients --title "Promo!" --body "..."            # dry-run
python scripts/send.py --segment clients --title "Promo!" --body "..." --commit --confirm
```

## Scripts
| script | função |
|--------|--------|
| `_shared.py` | motor S1 (Ctx/log) + `audit_log` |
| `preview_audience.py` | conta tokens ativos por segmento (`*_push_tokens.active=true`) |
| `send.py` | dry-run preview / `--commit --confirm` insere push_broadcasts + chama execute-broadcast |

## Notas
- Segmentos suportados: all/clients/drivers/partners (city não suportado pela Edge Fn — pendência).
- `--commit` exige `--confirm`. Audita quem enviou + segmento + nº.
