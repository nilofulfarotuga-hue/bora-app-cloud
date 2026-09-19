# README — migrate-screen-to-design (Modo A)

Re-skin de 1 ecrã para o design system, gerando diff. **Não toca `lib/`** sem `--apply`.

## Uso
```bash
python scripts/analyze_screen.py --screen cart_screen
python scripts/generate_patch.py --screen cart_screen          # dry (diff em _preview/)
python scripts/generate_patch.py --screen cart_screen --apply  # backup + escreve + flutter analyze
```

## Scripts
| script | função |
|--------|--------|
| `_shared.py` | `REPO_ROOT` + `log` + `HEX_TOKEN` (mapa hex→AppColors) |
| `analyze_screen.py` | tabela de mudanças propostas (substituições + sinalizações) |
| `generate_patch.py` | gera diff; `--apply` backup+escreve+flutter analyze |

## Notas
- Só substitui literais de cor inequívocos (marca/semânticos). Branco/preto → só sinaliza.
- Sinaliza AppBar custom→BoraScreenAppBar e accent rows (decisão humana; não auto).
- Garante import de `app_colors.dart`. NÃO altera lógica/Stripe/realtime/strings/fotos.
- `--screen` aceita o stem (ex.: `cart_screen`) ou caminho relativo a `lib/screens/`.
