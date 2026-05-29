---
name: update-design-token
description: Gera o diff (Modo A) para alterar um token de cor global em app_theme.dart/app_colors.dart + lista os ecrãs afetados (grep). NÃO toca lib/ sem --apply. Avisos especiais para primary (verde) e accent (laranja) e auditoria "1 laranja/ecrã".
metadata:
  type: codegen
  category: ui
  depends_on: bora-knowledge
  uses_edge_fns: []
  version: 1.0.0
---

# Update Design Token (Modo A — patch generator)

Altera um token de cor (`Color(0x...)`) **gerando diff para revisão**. **Não edita `lib/`**
sem `--apply` (zona Fase 3/4 fechada).

## Pré-requisitos (LER bora-knowledge ANTES de agir)
1. `bora-knowledge/knowledge/01-design-system.md` (paleta, regra 1 laranja/ecrã)
2. `bora-knowledge/knowledge/10-protected-zones.md`

## Uso
```bash
python scripts/preview_token.py --token warning                       # valor atual + ecrãs afetados
python scripts/generate_patch.py --token warning --new-value "#F59E0B" # gera diff (dry)
python scripts/generate_patch.py --token warning --new-value "#F59E0B" --apply
```

## Modos
- **DEFAULT (gerar)**: localiza `static const Color <token> = Color(0x..)` em
  `app_theme.dart`/`app_colors.dart`, gera `_preview/<token>.diff` + lista de ecrãs que usam
  `AppColors.<token>`/`AppTheme.<token>`. NÃO escreve.
- **`--apply`**: backup + escreve o ficheiro + `admin_audit_log`.

## Avisos especiais (do design system)
- **`primary`** (`#16A34A` verde) ou **`secondary`/`accent`** (`#F97316` laranja) →
  aviso de **impacto global** (marca). Exige `--confirm-brand`.
- Se o token for **accent/laranja** → relatório lembra a regra **"1 laranja por ecrã"**.

## Limites
- Trata tokens `Color(0xFF......)`. Gradientes e tokens multi-valor → manual (a skill avisa).
- Não toca pricing/dispatch/tokens DB.
