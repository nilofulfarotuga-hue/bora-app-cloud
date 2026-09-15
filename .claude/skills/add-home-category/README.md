# README — add-home-category (Modo A)

Gera os diffs para adicionar uma 8ª categoria à home do cliente. **Não toca `lib/`**
sem `--apply`.

## Instalação / ambiente
`.env` (só necessário p/ `--apply` → auditoria): `SUPABASE_URL`, `SUPABASE_ANON_KEY`,
`SUPABASE_SERVICE_ROLE_KEY`, `BORA_ADMIN_USER_ID`.
```bash
python -m venv .venv && .venv\Scripts\activate && pip install -r requirements.txt
```

## Uso
```bash
# 1. Gerar (revisão) — escreve _preview/, não toca lib/
python scripts/generate_patch.py --label "Flores" \
  --gradient-start "#16A34A" --gradient-end "#22C55E" \
  --asset "assets/images/categories/flores.png" \
  --screen "StoresScreen(category: BusinessCategory.store)"

# 2. Rever _preview/relatorio.md + *.diff. Depois aplicar:
python scripts/generate_patch.py ... --apply
# 3. Verificar
python scripts/verify.py --label "Flores"
```

## Scripts
| script | função |
|--------|--------|
| `_shared.py` | motor S1 (Ctx/log) + `audit_log` |
| `generate_patch.py` | gera diffs (default) / aplica com backup (`--apply`) + auditoria |
| `verify.py` | `flutter analyze` (best-effort) + confirma label em client_home_screen.dart |

## Notas
- Caminhos default: `lib/config/app_colors.dart`, `lib/screens/client_home_screen.dart`
  (override via `--colors-file` / `--home-file`).
- O PNG do tile e a entrada no `pubspec.yaml` são manuais (a skill lembra).
- Regra "1 laranja/ecrã": categoria laranja exige `--confirm-orange`.
