# README — update-design-token (Modo A)

Altera um token de cor global, gerando diff para revisão. **Não toca `lib/`** sem `--apply`.

## Ambiente (.env, só p/ --apply → auditoria)
`SUPABASE_URL`, `SUPABASE_ANON_KEY`, `SUPABASE_SERVICE_ROLE_KEY`, `BORA_ADMIN_USER_ID`.

## Uso
```bash
python scripts/preview_token.py --token warning
python scripts/generate_patch.py --token warning --new-value "#F59E0B"          # dry
python scripts/generate_patch.py --token warning --new-value "#F59E0B" --apply  # aplica + audita
```

## Scripts
| script | função |
|--------|--------|
| `_shared.py` | motor S1 (Ctx/log) + `audit_log` + `REPO_ROOT` |
| `preview_token.py` | valor atual + nº/lista de ecrãs que usam o token |
| `generate_patch.py` | diff (default) / aplica com backup (`--apply`) + auditoria |

## Notas
- Ficheiros default: `lib/config/app_theme.dart` e `lib/config/app_colors.dart` (procura nos dois).
- `primary`/`secondary`/`accent` exigem `--confirm-brand` (impacto de marca).
- Só hex `Color(0xFF......)`; gradientes → manual.
